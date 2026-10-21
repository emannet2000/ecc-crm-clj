{-# LANGUAGE OverloadedStrings #-}
module ECC.WorkflowSupport where
import Control.Monad (unless,void,when)
import Control.Monad.IO.Class (liftIO)
import qualified Data.Aeson as A
import Data.Aeson ((.=))
import qualified Data.Aeson.Key as K
import qualified Data.Aeson.KeyMap as KM
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import qualified Data.Text as T
import Data.Time (Day,defaultTimeLocale,parseTimeM)
import Network.HTTP.Types hiding (Query)
import qualified Web.Scotty as S
import Database.SQLite.Simple.FromField (FromField)
import ECC.Store
import ECC.DB (Env(..),getLead,getClient)
import ECC.Models
import ECC.Security (reject)
import System.Environment (lookupEnv)
import Text.Read (readMaybe)

bodyObject :: S.ActionM A.Value
bodyObject = do
 bytes <- S.body
 case A.eitherDecode bytes of
  Right value@(A.Object fields) -> do
   forM_Fields fields
   pure value
  _ -> reject status400 "Enter valid form values"
 where
  forM_Fields fields = mapM_ (\v -> case v of A.String t | T.length t>20000 -> reject status400 "A field is too long"; _ -> pure ()) (KM.elems fields)

field :: T.Text -> A.Value -> T.Text
field key (A.Object obj) = case KM.lookup (K.fromText key) obj of
 Just (A.String t) -> if key=="password" then t else T.strip t
 Just (A.Number n) | let integer=round n :: Integer, fromInteger integer==n, integer>=toInteger(minBound::Int), integer<=toInteger(maxBound::Int) -> T.pack(show(round n::Integer))
 Just (A.Bool b) -> if b then "true" else "false"
 _ -> ""
field _ _ = ""
number :: T.Text -> A.Value -> Maybe Int
number key value = readMaybe (T.unpack (field key value))
needed :: T.Text -> A.Value -> S.ActionM T.Text
needed key value = let t=field key value in if T.null t then reject status400 (key<>" is required") else pure t
bounded :: T.Text -> Int -> A.Value -> S.ActionM T.Text
bounded key maximumLength value = do
 t <- needed key value
 when (T.length t>maximumLength) $ reject status400 (key<>" is too long")
 pure t
intField :: T.Text -> A.Value -> S.ActionM Int
intField key value = maybe (reject status400 (key<>" must be a number")) pure (number key value)
choice :: T.Text -> [T.Text] -> A.Value -> S.ActionM T.Text
choice key values value = do
 t <- needed key value
 unless (t `elem` values) $ reject status400 ("Choose a valid "<>key)
 pure t
dateField :: T.Text -> Bool -> A.Value -> S.ActionM (Maybe T.Text)
dateField key required value = do
 let t=field key value
 if T.null t && not required then pure Nothing else
  case parseTimeM True defaultTimeLocale "%F" (T.unpack t) :: Maybe Day of
   Just _ -> pure (Just t)
   Nothing -> reject status400 (key<>" must be a date")

revision :: Env -> T.Text -> Int -> IO Int
revision env kind rid = do
 rows <- query (envConn env) "SELECT revision FROM record_versions WHERE kind=? AND record_id=?" (kind,rid) :: IO [Only Int]
 pure $ case rows of Only n:_ -> n; _ -> 1
checkRevision :: Env -> T.Text -> Int -> A.Value -> S.ActionM ()
checkRevision env kind rid input = do
 actual <- liftIO $ revision env kind rid
 expected <- maybe (reject (mkStatus 428 "Precondition Required") "Reload this record before saving") pure (number "expectedRevision" input)
 when (actual/=expected) $ reject status409 "Someone else changed this record. Reload it, review their changes, and save again. Your form has been kept."
checkOwnRevision :: Int -> A.Value -> S.ActionM ()
checkOwnRevision actual input = when (number "expectedRevision" input /= Just actual) $ reject status409 "This item changed. Reload it before saving; your form has been kept."

-- Add revisions without changing the long-established domain constructors.
respondJson :: A.ToJSON a => Env -> a -> S.ActionM ()
respondJson env value = do
 let json = A.toJSON value
     records = Set.toList (collect json)
     chunks [] = []
     chunks xs = take 200 xs : chunks (drop 200 xs)
 -- Bound parameters and query only records present in this response.
 revisions <- liftIO $ fmap (Map.fromList . concat) $ mapM (\batch -> do
   let keys = A.toJSON [A.object ["kind" .= kind,"id" .= rid] | (kind,rid) <- batch]
   rows <- query (envConn env) "SELECT v.kind,v.record_id,v.revision FROM json_each(?) j JOIN record_versions v ON v.kind=json_extract(j.value,'$.kind') AND v.record_id=json_extract(j.value,'$.id')" (Only keys) :: IO [(T.Text,Int,Int)]
   pure [((kind,rid),n) | (kind,rid,n) <- rows]) (chunks records)
 users <- liftIO $ metadata "users" "SELECT u.id,u.mfa_secret IS NULL AND u.role='admin' FROM json_each(?) j JOIN users u ON u.id=CAST(j.value AS INTEGER)" records
 scans <- liftIO $ metadata "documents" "SELECT d.id,d.scan_status FROM json_each(?) j JOIN documents d ON d.id=CAST(j.value AS INTEGER)" records
 requireMfa <- liftIO $ (==Just "true") <$> lookupEnv "REQUIRE_ADMIN_MFA"
 let enrich (A.Array xs) = A.Array (fmap enrich xs)
     enrich (A.Object obj) =
       let children = fmap enrich obj
       in case record obj of
         Just key@(kind,rid) ->
           let revised = KM.insert "revision" (A.toJSON (Map.findWithDefault 1 key revisions)) children
               extra | kind=="users" = KM.insert "mfaRequired" (A.Bool (requireMfa && Map.findWithDefault False rid users)) revised
                     | kind=="documents" = KM.insert "scanStatus" (A.toJSON (Map.findWithDefault ("Pending"::T.Text) rid scans)) revised
                     | otherwise = revised
           in A.Object extra
         Nothing -> A.Object children
     enrich v = v
 S.json (enrich json)
 where
 record :: A.Object -> Maybe (T.Text,Int)
 record obj =
  let has key = KM.member key obj
      ident key = case KM.lookup key obj of Just (A.Number n) -> Just (round n::Int); _ -> Nothing
  in if has "leadNumber" then (,) "leads" <$> ident "leadId"
     else if has "number" && has "caseOfficerId" then (,) "clients" <$> ident "id"
     else if has "priority" && has "assignedTo" then (,) "tasks" <$> ident "id"
     else if has "category" && has "clientId" then (,) "cases" <$> ident "id"
     else if has "filename" && has "mimeType" then (,) "documents" <$> ident "id"
     else if has "email" && has "role" then (,) "users" <$> ident "id"
     else Nothing
 collect (A.Array xs) = foldMap collect xs
 collect (A.Object obj) = maybe Set.empty Set.singleton (record obj) <> foldMap collect obj
 collect _ = Set.empty
 metadata :: FromField a => T.Text -> Query -> [(T.Text,Int)] -> IO (Map.Map Int a)
 metadata kind sql records =
  case [rid | (k,rid) <- records,k==kind] of
   [] -> pure Map.empty
   ids -> Map.fromList <$> query (envConn env) sql (Only (A.toJSON ids))

canAccess :: Env -> User -> T.Text -> Int -> IO Bool
canAccess env u kind rid = case kind of
 "lead" -> maybe False (const True) <$> getLead (envConn env) rid
 "client" -> maybe False (const True) <$> getClient (envConn env) rid
 "case" -> do
  rows <- query (envConn env) "SELECT client_id FROM cases WHERE id=?" (Only rid) :: IO [Only Int]
  case rows of Only cid:_ -> canAccess env u "client" cid; _ -> pure False
 _ -> pure False
owner :: Env -> User -> A.Value -> S.ActionM (Maybe Int,Maybe Int,Maybe Int)
owner env u input = do
 value <- needed "owner" input
 case T.splitOn ":" value of
  [kind,sid] | Just rid <- readMaybe (T.unpack sid) -> do
   ok <- liftIO $ canAccess env u kind rid
   unless ok $ reject status404 "Choose an accessible record"
   case kind of
    "lead" -> pure (Just rid,Nothing,Nothing)
    "client" -> pure (Nothing,Just rid,Nothing)
    "case" -> do
     [Only cid] <- liftIO $ query (envConn env) "SELECT client_id FROM cases WHERE id=?" (Only (rid::Int))
     pure (Nothing,Just cid,Just rid)
    _ -> reject status400 "Choose a lead, student or application"
  _ -> reject status400 "Choose a lead, student or application"
checkOwner :: Env -> User -> Maybe Int -> Maybe Int -> S.ActionM ()
checkOwner env u ml mc = do
 ok <- liftIO $ case mc of Just cid -> canAccess env u "client" cid; _ -> case ml of Just lid -> canAccess env u "lead" lid; _ -> pure False
 unless ok $ reject status404 "Record not found"
staff :: Env -> Int -> S.ActionM ()
staff env uid = do
 rows <- liftIO $ query (envConn env) "SELECT id FROM users WHERE id=? AND role<>'viewer' AND suspended=0" (Only uid) :: S.ActionM [Only Int]
 when (null rows) $ reject status400 "Choose an active staff member"

-- SQL fragments contain only constants. Values remain bound parameters.
visibleLeads, visibleClients, visibleTasks :: Query
visibleLeads = "SELECT id FROM leads WHERE deleted_at IS NULL AND converted_client_id IS NULL AND ((SELECT assigned_only FROM request_context WHERE id=1)<>'true' OR (SELECT role FROM request_context WHERE id=1)='admin' OR consultant_id=(SELECT actor_id FROM request_context WHERE id=1))"
visibleClients = "SELECT id FROM clients WHERE deleted_at IS NULL AND ((SELECT assigned_only FROM request_context WHERE id=1)<>'true' OR (SELECT role FROM request_context WHERE id=1)='admin' OR case_officer_id=(SELECT actor_id FROM request_context WHERE id=1))"
-- Correlate to the candidate task so record/profile reads never enumerate every
-- visible task, client and lead in the database. Caller aliases tasks as t.
taskVisibility :: Query
taskVisibility = "((t.client_id IS NULL AND EXISTS (SELECT 1 FROM leads l WHERE l.id=t.lead_id AND l.deleted_at IS NULL AND l.converted_client_id IS NULL AND ((SELECT assigned_only FROM request_context WHERE id=1)<>'true' OR (SELECT role FROM request_context WHERE id=1)='admin' OR l.consultant_id=(SELECT actor_id FROM request_context WHERE id=1)))) OR (EXISTS (SELECT 1 FROM clients c WHERE c.id=t.client_id AND c.deleted_at IS NULL AND ((SELECT assigned_only FROM request_context WHERE id=1)<>'true' OR (SELECT role FROM request_context WHERE id=1)='admin' OR c.case_officer_id=(SELECT actor_id FROM request_context WHERE id=1))))) AND ((SELECT assigned_only FROM request_context WHERE id=1)<>'true' OR (SELECT role FROM request_context WHERE id=1)='admin' OR t.assigned_to_id=(SELECT actor_id FROM request_context WHERE id=1))"

visibleTasks = "SELECT t.id FROM tasks t WHERE "<>taskVisibility
jsonRows :: ToRow q => Env -> Query -> q -> IO [A.Value]
jsonRows env sql args = map fromOnly <$> (query (envConn env) sql args :: IO [Only A.Value])
recordHistory :: Env -> User -> Maybe Int -> Maybe Int -> Maybe Int -> T.Text -> T.Text -> IO ()
recordHistory env u ml mc cs kind note = void $ execute (envConn env) "INSERT INTO work_history(lead_id,client_id,case_id,actor_id,kind,note) VALUES (?,?,?,?,?,?)" (ml,mc,cs,userId u,kind,note)

-- Assignment must give the assignee access to the associated record.
checkAssignee :: Env -> Int -> Maybe Int -> Maybe Int -> S.ActionM ()
checkAssignee env uid ml mc = do
 [Only scoped] <- liftIO $ query_ (envConn env) "SELECT assigned_only='true' FROM request_context WHERE id=1" :: S.ActionM [Only Bool]
 when scoped $ checkAssigned
 where
 checkAssigned = do
  rows<-liftIO $ query (envConn env) "SELECT id FROM users WHERE id=? AND (role='admin' OR id=(SELECT consultant_id FROM leads WHERE id=?) OR id=(SELECT case_officer_id FROM clients WHERE id=?))" (uid,ml,mc) :: S.ActionM [Only Int]
  when (null rows) $ reject status400 "Assign this task or appointment to the record's responsible staff member, or reassign the record first"
