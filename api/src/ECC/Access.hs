{-# LANGUAGE OverloadedStrings #-}
-- Role ceilings remain in the route guards. These settings can only restrict them.
module ECC.Access (assignedOnly, authorize, teamAccess, saveAccess, hasPrivilege, requirePrivilege) where

import Control.Monad (forM, unless, void, when)
import Control.Monad.IO.Class (liftIO)
import qualified Data.Aeson as A
import Data.Aeson ((.=))
import qualified Data.Aeson.Key as K
import qualified Data.Aeson.KeyMap as KM
import qualified Data.ByteString.Lazy as BL
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import Network.HTTP.Types
import qualified Network.Wai as W
import qualified Web.Scotty as S
import ECC.DB (Env(..))
import ECC.Models
import ECC.Store
import ECC.Security (reject)
import ECC.WorkflowSupport (choice, intField, checkOwnRevision)

privilegeNames :: [T.Text]
privilegeNames = legacyPrivileges ++ ["sales_view", "finance_view", "payments_record", "expenses_record", "expenses_approve", "finance_periods", "finance_reconcile"]

legacyPrivileges :: [T.Text]
legacyPrivileges = ["edit", "delete", "download", "export", "email", "portal"]

defaultPrivileges :: T.Text -> [T.Text]
defaultPrivileges role
 | role=="admin" = privilegeNames
 | role=="viewer" = ["download", "export"]
 | otherwise = legacyPrivileges

settings :: Env -> User -> IO (T.Text, [T.Text], Int)
settings env u = do
 rows <- query (envConn env) "SELECT access_level,privileges,revision FROM user_access WHERE user_id=?" (Only (userId u)) :: IO [(T.Text,T.Text,Int)]
 pure $ case rows of
  [(scope,encoded,rev)] -> (scope, either (const []) id (A.eitherDecodeStrict (TE.encodeUtf8 encoded)),rev)
  _ -> (if envAssignedOnly env then "assigned" else "all",defaultPrivileges (userRole u),0)

hasPrivilege :: Env -> User -> T.Text -> IO Bool
hasPrivilege env u key
 | userRole u=="admin" = pure True
 | userRole u=="viewer" && key `elem` ["edit","delete","email","portal","payments_record","expenses_record","expenses_approve", "finance_periods", "finance_reconcile"] = pure False
 | otherwise = do
  (_,privileges,_) <- settings env u
  pure (key `elem` privileges)

requirePrivilege :: Env -> User -> T.Text -> S.ActionM ()
requirePrivilege env u key = do
 allowed <- liftIO $ hasPrivilege env u key
 unless allowed $ reject status403 "Your account does not have the required privilege. Contact an administrator."

assignedOnly :: Env -> User -> IO Bool
assignedOnly env u = do
 (scope,_,_) <- settings env u
 pure (envAssignedOnly env || scope == "assigned")

authorize :: Env -> User -> S.ActionM ()
authorize env u = when (userRole u /= "admin") $ do
 req <- S.request
 (_,privileges,_) <- liftIO $ settings env u
 let path = W.pathInfo req
     writing = W.requestMethod req `notElem` ["GET","HEAD","OPTIONS"]
     financial = case path of
      ("api":"workspace":section:_) -> section `elem` ["payments","expenses","payment-history","periods","reconciliation"]
      _ -> False
     financeFiles = take 2 path == ["api","finance"]
     personal = case path of
      ["api","auth",_] -> True
      ("api":"workspace":"security":_) -> True
      ("api":"workspace":"notifications":_) -> True
      ("api":"workspace":"search":_) -> True
      ("api":"reminders":_:_:"read":_) -> True
      _ -> False
     exporting = "finance-export" `elem` path || "export" `elem` path || "report-export" `elem` path || "reports.csv" `elem` path || "calendar.ics" `elem` path
     downloading = "download" `elem` path || "photo" `elem` path && not writing
     emailing = case path of ("api":"workspace":"communication":_) -> writing; _ -> False
     portal = case path of ("api":"workspace":"portal":_) -> writing; _ -> False
     required = ["edit" | writing && not personal && not financial && not financeFiles] ++ ["delete" | W.requestMethod req == "DELETE" || "bulk" `elem` path] ++ ["download" | downloading] ++ ["export" | exporting] ++ ["email" | emailing] ++ ["portal" | portal]
 unless (all (`elem` privileges) required) $ reject status403 "Your account does not have the required privilege. Contact an administrator."

teamAccess :: Env -> IO [A.Value]
teamAccess env = do
 users <- query_ (envConn env) "SELECT id,email,name,role FROM users ORDER BY name" :: IO [(Int,T.Text,T.Text,T.Text)]
 forM users $ \(uid,email,name,role) -> do
  let u=User uid email name role
  (savedScope,savedPrivileges,rev) <- settings env u
  let scope=if role=="admin" then "all" else savedScope
      privileges=if role=="admin" then privilegeNames else savedPrivileges
  [(suspended,mfaEnabled)] <- query (envConn env) "SELECT suspended,mfa_secret IS NOT NULL FROM users WHERE id=?" (Only uid) :: IO [(Int,Bool)]
  pure (A.object (["id".=uid,"name".=name,"role".=role,"suspended".=suspended,"mfaEnabled".=mfaEnabled,"accessLevel".=scope,"revision".=rev] ++ [K.fromText key .= (if key `elem` privileges then "allowed"::T.Text else "denied") | key <- privilegeNames]))

saveAccess :: Env -> User -> A.Value -> S.ActionM A.Value
saveAccess env actor input = do
 unless (userRole actor == "admin") $ reject status403 "Admin access required"
 uid <- intField "user" input
 rows <- liftIO $ query (envConn env) "SELECT id,email,name,role FROM users WHERE id=?" (Only uid) :: S.ActionM [(Int,T.Text,T.Text,T.Text)]
 target <- case rows of [(i,e,n,r)] -> pure (User i e n r); _ -> reject status404 "Account not found"
 when (userRole target == "admin") $ reject status400 "Administrators retain full privileges. Change the role in Users before restricting access."
 scope <- choice "accessLevel" ["all","assigned"] input
 privileges <- fmap concat $ forM privilegeNames $ \key -> do
  let newKey = key `notElem` legacyPrivileges
      absent = case input of A.Object obj -> not (KM.member (K.fromText key) obj); _ -> False
  value <- if newKey && absent then pure "denied" else choice key ["allowed","denied"] input
  pure [key | value == "allowed"]
 when (userRole target == "viewer" && any (`elem` privileges) ["edit","delete","email","portal","payments_record","expenses_record","expenses_approve", "finance_periods", "finance_reconcile"]) $ reject status400 "Viewers cannot receive write privileges. Change the role in Users first."
 (_,_,rev) <- liftIO $ settings env target
 checkOwnRevision rev input
 let encoded=TE.decodeUtf8 (BL.toStrict (A.encode privileges))
 liftIO $ do
  void $ execute (envConn env) "INSERT INTO user_access(user_id,access_level,privileges) VALUES (?,?,?) ON CONFLICT(user_id) DO UPDATE SET access_level=excluded.access_level,privileges=excluded.privileges,revision=user_access.revision+1" (uid,scope,encoded)
  void $ execute (envConn env) "INSERT INTO audit_log(entity_type,entity_id,entity_name,action,changes,actor_id) VALUES ('user',?,'Account access','updated',?,?)" (uid,TE.decodeUtf8(BL.toStrict(A.encode(A.object["accessLevel".=scope,"privileges".=privileges]))),userId actor)
 pure (A.object ["message".=("Access and privileges saved. Changes apply immediately."::T.Text)])
