{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}
module ECC.Logging (LogSink, writeLog, logEvent, requestFields, safeRoute, exceptionFields, catchSync, startupCheck, requestId) where

import Control.Exception (SomeException(..), SomeAsyncException, IOException, catch, fromException, throwIO)
import qualified Data.Aeson as A
import Data.Aeson ((.=))
import Data.Aeson.Types (Pair)
import qualified Data.ByteString.Lazy as BL
import qualified Data.ByteString as B
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import Data.Text.Encoding.Error (lenientDecode)
import Data.Time.Clock (getCurrentTime)
import Data.Typeable (typeOf)
import qualified Network.Wai as Wai
import System.IO (stdout, hFlush)
import System.IO.Error (ioeGetErrorType)
import System.Exit (ExitCode)
import ECC.Release (releaseContract)
import qualified ECC.Store as Store

type LogSink = A.Value -> IO ()

-- One encoded write keeps concurrent records on separate lines.
writeLog :: LogSink
writeLog value = B.hPut stdout (BL.toStrict (A.encode value) <> "\n") >> hFlush stdout

logEvent :: LogSink -> T.Text -> T.Text -> [Pair] -> IO ()
logEvent sink severity event fields = do
  now <- getCurrentTime
  sink (A.object (["timestamp" .= now, "severity" .= severity, "event" .= event,
                  "service" .= ("ecc-crm-api" :: T.Text), "version" .= releaseContract] ++ fields))

requestId :: Wai.Request -> T.Text
requestId req = maybe "unassigned" (TE.decodeUtf8With lenientDecode) (lookup "X-Request-ID" (Wai.requestHeaders req))

requestFields :: Wai.Request -> [Pair]
requestFields req = ["requestId" .= requestId req, "method" .= method, "route" .= safeRoute (Wai.pathInfo req)]
 where
  raw = Wai.requestMethod req
  method = if raw `elem` ["GET","HEAD","POST","PUT","PATCH","DELETE","OPTIONS"] then TE.decodeUtf8 raw else "OTHER"

-- Only application-defined literals may enter logs. Unknown values, including
-- record IDs and URL tokens, are never copied. Limit attacker-controlled depth.
safeRoute :: [T.Text] -> T.Text
safeRoute ("api":parts) = "/api/" <> T.intercalate "/" (map segment (take 8 parts))
 where
  segment part | part `elem` literals = part
               | otherwise = ":value"
  literals = T.words "health ready time metrics archive duplicates reminders read auth logout recover reset login me password users invite leads clients tasks cases activities documents advance convert notes restore bulk import audit stats export leads.csv clients.csv download workspace portal exchange requests upload profile photo rescan finance expenses attachments print invoices payments record conflict mail retry notifications report-export finance-export milestones save contact-log add payment-history periods reconciliation candidates applications checklist checklist-templates reports.csv calendar.ics security sessions revoke mfa setup enable disable"
safeRoute _ = "/:asset"

-- Do not print displayException: SQL, IO and user exceptions can contain
-- credentials, SQL parameters, paths or document contents. Typed categories
-- remain useful even when the exception text cannot be trusted.
exceptionFields :: SomeException -> [Pair]
exceptionFields exception@(SomeException inner) =
  ["errorType" .= T.pack (show (typeOf inner))] ++
  case fromException exception :: Maybe Store.SQLError of
    Just err -> ["databaseCode" .= show (Store.sqlError err), "operation" .= ("database_transaction" :: T.Text)]
    Nothing -> case fromException exception :: Maybe IOException of
      Just err -> ["errorCategory" .= show (ioeGetErrorType err)]
      Nothing -> []

catchSync :: IO a -> (SomeException -> IO a) -> IO a
catchSync action handler = action `catch` \err ->
  case fromException err :: Maybe SomeAsyncException of
    Just _ -> throwIO err
    Nothing -> case fromException err :: Maybe ExitCode of
      Just _ -> throwIO err
      Nothing -> handler err

-- Stage names are application literals, never configuration values or exception text.
startupCheck :: LogSink -> T.Text -> IO a -> IO a
startupCheck sink stage action = catchSync action $ \err -> do
  logEvent sink "ERROR" "startup_check_failed" (["stage" .= stage] ++ exceptionFields err)
  throwIO err
