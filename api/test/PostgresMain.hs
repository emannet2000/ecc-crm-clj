{-# LANGUAGE OverloadedStrings #-}
module Main (main) where

import Control.Exception (bracket, finally)
import Control.Monad (unless)
import qualified Data.ByteString.Char8 as B
import qualified Data.Text as T
import System.Environment (lookupEnv)
import qualified Web.Scotty as S
import ECC.Auth (randomToken)
import qualified ECC.DB as DB
import ECC.Migrations (runMigrations, requireCurrentSchema)
import qualified ECC.Routes as Routes
import ECC.Server (transactionalApplication)
import ECC.Store
import qualified FeatureTests
import qualified ClientApplicationTests

-- This suite is deliberately separate: a missing PostgreSQL server must not
-- appear as a passing PostgreSQL test in the ordinary SQLite suite.
main :: IO ()
main = do
 url<-lookupEnv "ECC_TEST_DATABASE_URL" >>= maybe (fail "Set ECC_TEST_DATABASE_URL to a disposable PostgreSQL database") pure
 unless (any (`T.isPrefixOf` T.pack url) ["postgresql://","postgres://"]) $ fail "ECC_TEST_DATABASE_URL must be a PostgreSQL URL"
 bracket (openDatabase url) close $ \cn -> do
  suffix<-T.toLower . T.filter (\c -> c>='a' && c<='z' || c>='A' && c<='Z' || c>='0' && c<='9') . T.pack . B.unpack <$> randomToken
  let schema="ecc_test_"<>suffix
      cleanup=execScript cn ("SET search_path=public; DROP SCHEMA "<>schema<>" CASCADE")
  execScript cn ("CREATE SCHEMA "<>schema<>"; SET search_path="<>schema<>",public")
  flip finally cleanup $ do
   runMigrations cn "migrations"
   runMigrations cn "migrations"
   requireCurrentSchema cn "migrations"
   -- Real parameter binding, scalar codecs and PostgreSQL expression behavior.
   [(name,n,yes)]<-query cn "SELECT ?,?,NOT ?" ("O'Brien ? café"::T.Text,42::Int,False) :: IO [(T.Text,Int,Bool)]
   unless (name=="O'Brien ? café" && n==42 && yes) $ fail "PostgreSQL parameter/field round trip failed"
   [Only none]<-query cn "SELECT ? IS NULL" (Only (Nothing::Maybe Int)) :: IO [Only Bool]
   unless none $ fail "PostgreSQL NULL parameter failed"
   [Only bytes]<-query cn "SELECT ?" (Only(Binary(B.pack "\NUL\255x"))) :: IO [Only(Binary B.ByteString)]
   let Binary actual=bytes
   unless (actual==B.pack "\NUL\255x") $ fail "PostgreSQL binary round trip failed"
   range<-query cn "SELECT ? BETWEEN ? AND ?" ("2026-01-02"::T.Text,"2026-01-01"::T.Text,"2026-01-03"::T.Text) :: IO [Only Bool]
   unless (range==[Only True]) $ fail "PostgreSQL date range failed"
   withTransaction cn $ DB.addUser cn "admin@example.com" "Admin" "admin" "correct-password-123"
   -- Shared workflow tests exercise assigned-only access, just like the SQLite suite.
   application<-S.scottyApp(Routes.app(DB.Env cn "postgres-integration-secret-32-bytes" False "http://localhost:4000" True))
   let api=transactionalApplication cn application
   FeatureTests.run cn api
   ClientApplicationTests.run cn api
   [Only dataRows]<-query_ cn "SELECT count(*) FROM clients" :: IO [Only Int]
   unless (dataRows>0) $ fail "PostgreSQL workflows did not persist students"
   putStrLn "PostgreSQL transport, schema replay, WAI workflows, student conversion, permissions and persistence passed"
