{-# LANGUAGE OverloadedStrings #-}
module ECC.Security where
import Data.Char (isSpace, isDigit)
import System.Environment (lookupEnv)
import Control.Monad (void, when, forM_)
import Data.Aeson ((.=), (.:))
import qualified Data.Aeson as A
import qualified Data.Aeson.Key as K
import qualified Data.Aeson.KeyMap as KM
import qualified Data.ByteString as B
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import qualified Data.Text.Lazy as TL
import ECC.Store
import Network.Socket (SockAddr(..))
import Network.HTTP.Types
import qualified Network.Wai as Wai
import qualified Web.Scotty as S
import Control.Monad.IO.Class (liftIO)
import ECC.Auth
import ECC.DB (Env(..))

requestToken :: Wai.Request -> Maybe B.ByteString
requestToken req = case bearerToken (Wai.requestHeaders req) of
  Just t -> Just t
  Nothing -> lookup hCookie (Wai.requestHeaders req) >>= lookupCookie . B.split 59
  where
    lookupCookie [] = Nothing
    lookupCookie (x:xs) = case B.stripPrefix "ecc-session=" (B.dropWhile (==32) x) of
      Just t -> Just t
      Nothing -> lookupCookie xs

validSession :: Env -> B.ByteString -> IO (Maybe Int)
validSession env tok = do
  uid <- verifyToken (envSecret env) tok
  case uid of
    Nothing -> pure Nothing
    Just i -> do
      found <- query (envConn env) "SELECT user_id FROM sessions WHERE token_hash=? AND user_id=? AND expires_at>datetime('now') AND user_id IN (SELECT id FROM users WHERE suspended=0)" (tokenHash tok,i) :: IO [Only Int]
      pure $ case found of [Only n] -> Just n; _ -> Nothing

startSession :: Env -> Int -> T.Text -> Maybe T.Text -> S.ActionM B.ByteString
startSession env uid expectedHash expectedMfa = do
  tok <- liftIO $ makeToken (envSecret env) uid
  inserted <- liftIO $ execute (envConn env) "INSERT INTO sessions(token_hash,user_id,expires_at,mfa_verified) SELECT ?,id,datetime('now','+8 hours'),CASE WHEN mfa_secret IS NULL THEN 0 ELSE 1 END FROM users WHERE id=? AND password_hash=? AND suspended=0 AND mfa_secret IS ?" (tokenHash tok,uid,expectedHash,expectedMfa)
  when (inserted /= 1) $ reject status401 "Account changed. Sign in again."
  S.setHeader "Set-Cookie" ("ecc-session=" <> TL.fromStrict (TE.decodeUtf8 tok) <> "; Path=/; HttpOnly; SameSite=Strict; Max-Age=28800" <> if envProduction env then "; Secure" else "")
  pure tok

endSession :: Env -> S.ActionM ()
endSession env = do
  req <- S.request
  forM_ (requestToken req) $ \tok -> liftIO $ void $ execute (envConn env) "DELETE FROM sessions WHERE token_hash=?" (Only (tokenHash tok))
  S.setHeader "Set-Cookie" ("ecc-session=; Path=/; HttpOnly; SameSite=Strict; Max-Age=0" <> if envProduction env then "; Secure" else "")

reject :: Status -> T.Text -> S.ActionM a
reject status message = S.status status >> S.json (A.object ["error" .= message,"status" .= statusCode status]) >> S.finish

-- Persistent, bounded rate limiting; never trust a client-supplied forwarding header.
rateLimit :: Env -> T.Text -> S.ActionM ()
rateLimit env category = do
  req <- S.request
  proxySecret <- liftIO $ lookupEnv "PROXY_TOKEN"
  let trusted = case proxySecret of
        Just secret | length secret >= 32 -> lookup "X-ECC-Proxy-Token" (Wai.requestHeaders req) == Just (TE.encodeUtf8 (T.pack secret))
        _ -> False
      address = if trusted then maybe "unknown" show (lookup "X-ECC-Client-IP" (Wai.requestHeaders req)) else case Wai.remoteHost req of
          SockAddrInet _ host -> show host
          SockAddrInet6 _ _ host _ -> show host
          SockAddrUnix path -> path
      key = category <> ":" <> T.pack address
  rateLimitKey env key (if category == "reset" then 20 else 200)

rateLimitAccount :: Env -> T.Text -> T.Text -> S.ActionM ()
rateLimitAccount env category account = rateLimitKey env (category <> ":account:" <> tokenHash (TE.encodeUtf8 (T.toLower (T.strip account)))) 20

rateLimitKey :: Env -> T.Text -> Int -> S.ActionM ()
rateLimitKey env key maximumAttempts = do
  rows <- liftIO $ query (envConn env)
    "INSERT INTO login_attempts(key,attempts,expires_at) VALUES (?,1,datetime('now','+15 minutes')) ON CONFLICT(key) DO UPDATE SET attempts=CASE WHEN login_attempts.expires_at<datetime('now') THEN 1 ELSE login_attempts.attempts+1 END, expires_at=CASE WHEN login_attempts.expires_at<datetime('now') THEN datetime('now','+15 minutes') ELSE login_attempts.expires_at END RETURNING attempts"
    (Only key) :: S.ActionM [Only Int]
  when (any ((>maximumAttempts) . fromOnly) rows) $ do
    S.setHeader "Retry-After" "900"
    reject status429 "Too many attempts. Please try again in 15 minutes."

-- Validate before decoding domain records. The wire protocol uses field prefixes.
validated :: A.FromJSON a => Env -> S.ActionM a
validated env = do
  bytes <- S.body
  value <- case A.eitherDecode bytes of
    Left _ -> reject status400 "Invalid JSON request"
    Right v -> pure v
  case value of
    A.Object obj -> forM_ (KM.toList obj) $ \(key,val) -> do
      let name = K.toText key
          suffix s = s `T.isSuffixOf` name || T.toLower s == name
          enum endings values = when (any suffix endings) $ case val of
            A.String t | t `elem` values -> pure ()
            A.Null -> pure ()
            _ -> reject status400 (name <> " has an invalid value")
      case val of
        A.String t -> do
          let maxLen | suffix "Notes" || suffix "Note" || suffix "Description" = 20000
                     | suffix "Password" || name `elem` ["pcNew","pcCurrent"] = 72
                     | otherwise = 255
          when (T.length t > maxLen || ((suffix "Password" || name `elem` ["pcNew","pcCurrent"]) && B.length (TE.encodeUtf8 t)>72)) $ reject status400 (name <> " is too long")
          when ((suffix "Password" || name `elem` ["pcNew","pcCurrent","password"]) && T.any (=='\0') t) $ reject status400 "Passwords cannot contain NUL characters"
          when (any suffix ["FullName","Name","Title","Note"] && T.null (T.strip t)) $ reject status400 (name <> " is required")
          when (suffix "FullName" && T.length(T.strip t)>200) $ reject status400 "Use no more than 200 characters for the full name"
          when (suffix "Email" && not(T.null t)) $ case T.splitOn "@" t of
            [namePart,domainPart] | not(T.null namePart),not(T.null domainPart),not(T.any isSpace t) -> pure ()
            _ -> reject status400 "Enter a valid email address"
          when (suffix "Phone" && not(T.null(T.strip t))) $ do
            let digits=T.filter isDigit t
            when (T.length t>50 || T.length digits<7 || T.length digits>20 || T.any (\c -> not(isDigit c || c `elem` ("+()- ."::String))) t) $ reject status400 "Enter a phone number with 7–20 digits; +, spaces, brackets and hyphens are allowed"
          when ((name == "pcNew" || name == "nuPassword" && not (T.null t) || name == "uuPassword" && not (T.null t)) && T.length t < 12) $ reject status400 "Use a password of at least 12 characters"
        _ -> pure ()
      enum ["Stage"] ["New Lead","Contacted","Initial Assessment","Qualified","Consultation Booked","Proposal Sent","Converted","Closed/Lost","Documents Under Review","Application Submitted","Submitted","Decision Pending","Approved","Rejected","Completed"]
      enum ["Quality"] ["Hot","Warm","Cold"]
      enum ["Priority"] ["Low","Medium","High","Urgent"]
      enum ["Status"] ["Pending","In Progress","Done"]
      enum ["Role"] ["admin","consultant","viewer"]
      when (name `elem` ["nlConsultantId","ulConsultantId","ncCaseOfficer","brConsultantId"]) $ case A.fromJSON val of
        A.Success (Just uid) -> do
          users <- liftIO $ query (envConn env) "SELECT id FROM users WHERE id=? AND role<>'viewer'" (Only (uid::Int)) :: S.ActionM [Only Int]
          when (null users) $ reject status400 "Select an existing staff member"
        A.Success Nothing -> pure ()
        A.Error _ -> reject status400 "Invalid staff assignment"
    _ -> reject status400 "Expected a JSON object"
  case A.fromJSON value of
    A.Success parsed -> pure parsed
    A.Error _ -> reject status400 "Required fields are missing or invalid"

issueAccountToken :: Env -> Int -> T.Text -> S.ActionM ()
issueAccountToken env uid recipient = do
  tok <- liftIO randomToken
  let link = envPublicUrl env <> "/?reset=" <> TE.decodeUtf8 tok
  liftIO $ do
    -- Keep an outstanding emailed link valid until expiry. The surrounding
    -- request transaction serializes concurrent recovery/invitation requests.
    void $ execute (envConn env) "DELETE FROM account_tokens WHERE user_id=? AND expires_at<=datetime('now')" (Only uid)
    inserted <- execute (envConn env) "INSERT INTO account_tokens(token_hash,user_id,expires_at) SELECT ?,?,datetime('now','+1 hour') WHERE NOT EXISTS(SELECT 1 FROM account_tokens WHERE user_id=? AND expires_at>datetime('now'))" (tokenHash tok,uid,uid)
    when (inserted==1) $ void $ execute (envConn env) "INSERT INTO mail_outbox(recipient,subject,body) VALUES (?,?,?)" (recipient,"Your ECC CRM account"::T.Text,"Set your password using this link (expires in one hour):\n\n" <> link <> "\n\nIf you did not request this, ignore this email.")

textField :: T.Text -> A.Value -> S.ActionM T.Text
textField key (A.Object obj) = case KM.lookup (K.fromText key) obj of
  Just (A.String t) -> pure t
  _ -> reject status400 (key <> " is required")
textField _ _ = reject status400 "Expected a JSON object"
