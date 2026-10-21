{-# LANGUAGE OverloadedStrings #-}
module LoggingTests (run) where

import Control.Exception (bracket, throwIO, try, AsyncException(ThreadKilled))
import Control.Monad (unless)
import qualified Data.Aeson as A
import Data.Aeson ((.:))
import qualified Data.Aeson.Key as Key
import Data.Aeson.Types (parseMaybe)
import qualified Data.ByteString as B
import qualified Data.ByteString.Lazy as BL
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import Data.IORef
import qualified Network.Wai as W
import qualified Network.Wai.Test as WT
import Network.HTTP.Types
import ECC.Config (Config(..))
import ECC.Logging
import ECC.Server
import qualified ECC.Store as Store

assert :: String -> Bool -> IO ()
assert label condition = unless condition (fail label)

field :: A.FromJSON a => T.Text -> A.Value -> Maybe a
field key = parseMaybe (A.withObject "log" (.: fromStringKey key))
 where
  fromStringKey = Key.fromText

run :: IO ()
run = do
  records <- newIORef []
  let sink value = modifyIORef' records (++ [value])
      cfg = Config 4000 ":memory:" "logging-test-secret-at-least-32-bytes" False False 2 "http://localhost:4000" False
      secret = "private-document-password-token"
      request = (WT.setPath W.defaultRequest ("/api/leads/" <> secret <> "/documents?token=" <> secret))
        { W.requestHeaders = [("X-Request-ID",secret),("Authorization",secret),("Cookie",secret)] }
      exploding _ _ = ioError (userError (T.unpack (TE.decodeUtf8 secret)))
  response <- WT.runSession (WT.request request) (operationalWith sink cfg exploding)
  assert "Unexpected exceptions produce HTTP 500" (WT.simpleStatus response == status500)
  ident <- maybe (fail "Missing request reference") pure (lookup "X-Request-ID" (WT.simpleHeaders response))
  assert "Incoming request IDs cannot forge log identity" (B.length ident == 43 && ident /= secret)
  values <- readIORef records
  assert "Exception and completion records share response reference" (length values == 2 && all ((== Just (TE.decodeUtf8 ident)) . field "requestId") values)
  assert "Request log has timestamp, version, severity, safe route and timing"
    (case reverse values of
      value:_ -> field "route" value == Just ("/api/leads/:value/documents"::T.Text)
        && field "severity" value == Just ("ERROR"::T.Text)
        && (field "timestamp" value::Maybe T.Text) /= Nothing
        && (field "version" value::Maybe T.Text) /= Nothing
        && maybe False (>=0) (field "durationMs" value::Maybe Double)
      _ -> False)
  assert "Secrets from paths, headers, query and exception text stay out of logs"
    (not (secret `B.isInfixOf` BL.toStrict (A.encode values)))
  assert "Error response includes reference without exception text"
    (ident `B.isInfixOf` BL.toStrict (WT.simpleBody response) && not (secret `B.isInfixOf` BL.toStrict (WT.simpleBody response)))
  second <- WT.runSession (WT.request request) (operationalWith sink cfg (\_ respond -> respond (W.responseLBS status200 [("X-Request-ID","forged")] "ok")))
  let ids = filter ((=="X-Request-ID") . fst) (WT.simpleHeaders second)
  assert "Each request has a fresh ID and cannot override response reference" (length ids==1 && snd (head ids)/=ident && snd(head ids)/="forged")
  writeIORef records []
  bracket (Store.openDatabase ":memory:") Store.close $ \cn -> do
    let database _ _ = throwIO (Store.SQLError Store.ErrorBusy (TE.decodeUtf8 secret) "private SQL")
    busy <- WT.runSession (WT.request request) (operationalWith sink cfg (transactionalApplicationWith sink cn database))
    assert "Database failures retain HTTP 503" (WT.simpleStatus busy == status503)
  databaseLogs <- readIORef records
  assert "Database errors include safe error code and correlation"
    (any (\value -> field "databaseCode" value == Just ("ErrorBusy"::T.Text) && field "operation" value == Just ("database_transaction"::T.Text)) databaseLogs)
  assert "Database messages do not leak" (not (secret `B.isInfixOf` BL.toStrict (A.encode databaseLogs)))
  cancelled <- try (catchSync (throwIO ThreadKilled) (\_ -> pure ())) :: IO (Either AsyncException ())
  assert "Cancellation is never swallowed by request error handling" (case cancelled of Left ThreadKilled -> True; _ -> False)
  putStrLn "Logging regression checks passed"
