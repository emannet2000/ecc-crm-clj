{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}
module ConcurrencyTests (run) where

import Control.Concurrent
import Control.Exception (SomeException, bracket, try, throwIO)
import Control.Monad (unless, void)
import qualified Data.Aeson as A
import Data.Aeson ((.=),(.:))
import Data.Aeson.Types (parseMaybe)
import qualified Data.ByteString.Char8 as B
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import Data.List (sort)
import System.Directory (getTemporaryDirectory, doesFileExist, removeFile)
import System.FilePath ((</>))
import qualified Network.Wai as W
import qualified Network.Wai.Test as WT
import Network.HTTP.Types (statusCode)
import qualified Web.Scotty as S
import ECC.Store
import ECC.Auth (randomToken)
import ECC.Migrations (runMigrations)
import ECC.Server (transactionalApplication)
import qualified ECC.DB as DB
import qualified ECC.Routes as Routes

raceActions :: forall a. IO a -> IO a -> IO [a]
raceActions first second = do
  start <- newEmptyMVar
  let worker action = do
        result <- newEmptyMVar
        _ <- forkIO $ try (readMVar start >> action) >>= putMVar result
        pure result
  one <- worker first
  two <- worker second
  putMVar start ()
  results <- mapM takeMVar [one,two]
  mapM (either throwIO pure) (results :: [Either SomeException a])

run :: IO ()
run = do
  directory <- getTemporaryDirectory
  suffix <- B.unpack <$> randomToken
  let path = directory </> ("ecc-concurrency-"++suffix++".sqlite3")
      cleanup = mapM_ (\file -> doesFileExist file >>= \exists -> if exists then removeFile file else pure ()) [path,path++"-wal",path++"-shm"]
      assert label good = unless good (fail label)
  bracket (openDatabase path) (\cn -> close cn >> cleanup) $ \first -> do
    runMigrations first "migrations"
    DB.addUser first "race@test.local" "Race admin" "admin" "concurrency-password-123"
    bracket (openDatabase path) close $ \second -> do
      let secret="concurrency-test-secret-at-least-32-bytes"
          make cn = transactionalApplication cn <$> S.scottyApp (Routes.app (DB.Env cn secret False "http://localhost:4000" False))
      api1 <- make first
      api2 <- make second
      let call api token route fields = WT.runSession (WT.srequest (WT.SRequest
            ((WT.setPath W.defaultRequest route) {W.requestMethod="POST",W.requestHeaders=[("Content-Type","application/json")]++[("Authorization","Bearer "<>token)|not(B.null token)]}) (A.encode fields))) api
      login <- call api1 "" "/api/auth/login" (A.object["lrEmail".=("race@test.local"::T.Text),"lrPassword".=("concurrency-password-123"::T.Text)])
      value <- either fail pure (A.eitherDecode(WT.simpleBody login))
      token <- maybe (fail "Race login token missing") (pure . TE.encodeUtf8) (parseMaybe(A.withObject "login" (.:"token")) value)
      void $ execute_ first "INSERT INTO clients(client_number,full_name) VALUES ('RACE-1','Concurrent client')"
      void $ execute_ first "INSERT INTO invoices(client_id,description,currency,amount_minor,due_date,status) VALUES (1,'Race invoice','PHP',10000,'2020-01-01','Issued')"
      let race route fields = do
            results <- raceActions (call api1 token route (A.object fields)) (call api2 token route (A.object fields))
            assert "Exactly one concurrent financial mutation commits" (sort(map(statusCode . WT.simpleStatus)results)==[200,409])
      race "/api/workspace/payments/record" ["id".=(1::Int),"expectedRevision".=(1::Int),"amount".=("40.00"::T.Text),"paidOn".=("2020-01-01"::T.Text),"method".=("Cash"::T.Text)]
      state <- query_ first "SELECT paid_minor,balance_minor FROM invoice_balances WHERE id=1" :: IO [(Int,Int)]
      assert "Concurrent receipt is recorded only once" (state==[(4000,6000)])
      void $ execute_ first "INSERT INTO invoices(client_id,description,currency,amount_minor,due_date,status) VALUES (1,'Other invoice','PHP',10000,'2020-01-01','Issued')"
      wrongReceipt <- call api1 token "/api/workspace/payments/reverse" (A.object["id".=(2::Int),"expectedRevision".=(1::Int),"payment".=(1::Int),"paidOn".=("2020-01-02"::T.Text),"reason".=("Wrong invoice selection"::T.Text)])
      assert "A receipt from another invoice cannot be reversed" (statusCode(WT.simpleStatus wrongReceipt)==409)
      race "/api/workspace/payments/reverse" ["id".=(1::Int),"expectedRevision".=(2::Int),"payment".=(1::Int),"paidOn".=("2020-01-02"::T.Text),"reason".=("Correct duplicated instruction"::T.Text)]
      rows <- query_ first "SELECT count(*),sum(amount_minor) FROM invoice_payments WHERE invoice_id=1" :: IO [(Int,Int)]
      assert "Concurrent reversal creates exactly one compensating entry" (rows==[(2,0)])
      void $ execute_ first "INSERT INTO expenses(supplier,description,category,currency,amount_minor,expense_on,status,created_by,created_name) VALUES ('Supplier','Race expense','Office','PHP',500,'2020-01-01','Approved',1,'Race admin')"
      race "/api/workspace/expenses/pay" ["id".=(1::Int),"expectedRevision".=(1::Int),"paidOn".=("2020-01-02"::T.Text),"method".=("Cash"::T.Text)]
      entries <- query_ first "SELECT count(*),sum(amount_minor) FROM expense_entries" :: IO [(Int,Int)]
      assert "Concurrent expense payment is posted once" (entries==[(1,500)])
      -- A lost response followed by an identical retry must also be harmless.
      retry <- call api2 token "/api/workspace/expenses/pay" (A.object["id".=(1::Int),"expectedRevision".=(1::Int),"paidOn".=("2020-01-02"::T.Text),"method".=("Cash"::T.Text)])
      assert "Lost-response retry is rejected without another entry" (statusCode(WT.simpleStatus retry)==409)
  putStrLn "Two-connection receipt, reversal, expense and retry races passed"
