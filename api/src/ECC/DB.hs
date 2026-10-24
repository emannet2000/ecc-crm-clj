{-# LANGUAGE OverloadedStrings #-}

-- | SQLite data access: every SQL statement in the application lives
-- here.  Row parsers are positional, so SELECT column order must match the
-- tuple order used when reading rows.
module ECC.DB
  ( Env(..)
  , leadStages
  , listLeadsPage
  , listClientsPage
  , listTasksPage
  , getUserByEmailWithHash
  , getUserById
  , listUsers
  , addUser
  , insertUser
  , patchUser
  , deleteUser
  , countAdminsExcluding
  , getPasswordHash
  , updatePassword
  , setPassword
  , wipeCrmData
  , listLeads
  , getLead
  , getLeadDetail
  , insertLead
  , patchLead
  , deleteLead
  , advanceStage
  , convertToClient
  , addNote
  , bulkLeads
  , importLeads
  , listTasks
  , insertTask
  , setTaskStatus
  , deleteTask
  , listActivities
  , activitiesForLead
  , listClients
  , getClient
  , getClientDetail
  , insertClient
  , patchClient
  , deleteClient
  , upsertCase
  , deleteCase
  , documentsForLead
  , documentsForClient
  , insertDocument
  , getDocumentContent
  , deleteDocument
  , listAuditEntries
  , getStats
  ) where

import Control.Monad (forM, forM_, void)
import qualified Data.Aeson as A
import qualified Data.ByteString as B
import Data.Maybe (listToMaybe, maybeToList)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import Data.Time.Clock (UTCTime)
import Data.Time.Calendar (Day)
import Data.Time.Format (defaultTimeLocale, parseTimeM)
import ECC.Store


import ECC.Auth (hashPassword)
import ECC.Clock (businessDay)
import ECC.Models

data Env = Env
  { envConn   :: Connection
  , envSecret :: B.ByteString
  , envProduction :: Bool
  , envPublicUrl :: Text
  , envAssignedOnly :: Bool
  }

leadStages :: [Text]
leadStages =
  [ "New Lead", "Contacted", "Initial Assessment", "Qualified"
  , "Consultation Booked", "Proposal Sent", "Converted", "Closed/Lost" ]

nonEmpty :: Maybe Text -> Maybe Text
nonEmpty t = t >>= \v -> if T.null (T.strip v) then Nothing else Just v

-- | Allocate a reference from the durable counter inside the request transaction.
-- Leads retain the L counter while displaying ECC, separate from student numbers.
nextNumber :: Connection -> Text -> Text -> Text -> Int -> IO Text
nextNumber conn prefix _ _ pad = do
  rows <- query conn
    "INSERT INTO reference_counters(prefix,year,value) VALUES (?,CAST(strftime('%Y','now',business_offset()) AS INTEGER),1) ON CONFLICT(prefix,year) DO UPDATE SET value=reference_counters.value+1 RETURNING year,value"
    (Only prefix) :: IO [(Int,Integer)]
  case rows of
    [(year,n)] -> let digits = T.pack (show n) in pure ((if prefix == "L" then "ECC" else prefix) <> "-" <> T.pack (show year) <> "-" <> T.justifyRight pad '0' digits)
    _ -> fail "Could not allocate reference"

logActivity :: Connection -> Int -> Text -> Text -> IO ()
logActivity conn leadId kind desc = void $ execute conn
  "INSERT INTO activities (lead_id, type, description, date) VALUES (?,?,?,CURRENT_DATE)"
  (leadId, kind, desc)

touchLastContact :: Connection -> Int -> IO ()
touchLastContact conn leadId = void $ execute conn
  "UPDATE leads SET last_contact = CURRENT_DATE WHERE id = ?" (Only leadId)

-- ---------- users ----------

getUserByEmailWithHash :: Connection -> Text -> IO (Maybe (User, Text))
getUserByEmailWithHash conn email = do
  rows <- query conn
    "SELECT id, email, name, role, password_hash FROM users WHERE lower(email) = lower(?)"
    (Only email) :: IO [(Int, Text, Text, Text, Text)]
  pure $ case rows of
    [(i, e, n, r, h)] -> Just (User i e n r, h)
    _ -> Nothing

getUserById :: Connection -> Int -> IO (Maybe User)
getUserById conn uid = do
  rows <- query conn "SELECT id, email, name, role FROM users WHERE id = ?"
    (Only uid) :: IO [(Int, Text, Text, Text)]
  pure $ case rows of
    [(i, e, n, r)] -> Just (User i e n r)
    _ -> Nothing

listUsers :: Connection -> IO [User]
listUsers conn = map (\(i, e, n, r) -> User i e n r)
  <$> query_ conn "SELECT id, email, name, role FROM users ORDER BY name"

-- | CLI: create a user or update name\/role\/password on email conflict.
addUser :: Connection -> Text -> Text -> Text -> Text -> IO ()
addUser conn email name role pw = do
  h <- hashPassword (TE.encodeUtf8 pw)
  void $ execute conn
    "INSERT INTO users (email, password_hash, name, role) VALUES (?,?,?,?) \
    \ON CONFLICT (email) DO UPDATE SET password_hash = EXCLUDED.password_hash, \
    \name = EXCLUDED.name, role = EXCLUDED.role"
    (email, TE.decodeUtf8 h, name, role)

-- | CLI: set a new password for an existing user; False when user missing.
setPassword :: Connection -> Text -> Text -> IO Bool
setPassword conn email pw = do
  h <- hashPassword (TE.encodeUtf8 pw)
  n <- execute conn "UPDATE users SET password_hash = ? WHERE lower(email) = lower(?)"
    (TE.decodeUtf8 h, email)
  pure (n > 0)

-- | API: create a user; Nothing when the email is already taken.
insertUser :: Connection -> NewUser -> IO (Maybe User)
insertUser conn nu = do
  taken <- getUserByEmailWithHash conn (nuEmail nu)
  case taken of
    Just _  -> pure Nothing
    Nothing -> do
      h <- hashPassword (TE.encodeUtf8 (nuPassword nu))
      ids <- returning conn
        "INSERT INTO users (email, password_hash, name, role) VALUES (?,?,?,?) RETURNING id"
        [ (T.toLower (T.strip (nuEmail nu)), TE.decodeUtf8 h, nuName nu, nuRole nu) ] :: IO [[Int]]
      getUserById conn (head (concat ids))

-- | API: partial update; empty\/missing password keeps the current one.
patchUser :: Connection -> Int -> UpdateUser -> IO Bool
patchUser conn uid uu = do
  mhp <- case filter (not . T.null) (maybeToList (uuPassword uu)) of
    []    -> pure Nothing
    (pw:_) -> Just . TE.decodeUtf8 <$> hashPassword (TE.encodeUtf8 pw)
  n <- execute conn
    "UPDATE users SET name=COALESCE(NULLIF(?,''),name), role=COALESCE(NULLIF(?,''),role), \
    \password_hash=COALESCE(?,password_hash) WHERE id=?"
    (uuName uu, uuRole uu, mhp, uid)
  pure (n > 0)

deleteUser :: Connection -> Int -> IO Bool
deleteUser conn uid = (> 0) <$> execute conn "DELETE FROM users WHERE id = ?" (Only uid)

-- | Number of admins other than @uid@ — used to protect the last admin.
countAdminsExcluding :: Connection -> Int -> IO Int
countAdminsExcluding conn uid = do
  rs <- query conn
    "SELECT COUNT(*) FROM users WHERE role = 'admin' AND suspended=0 AND id <> ?" (Only uid)
    :: IO [Only Int]
  pure (maybe 0 fromOnly (listToMaybe rs))

-- | Stored bcrypt hash for the given user (for verifying the current
-- password during a self-service change).
getPasswordHash :: Connection -> Int -> IO (Maybe Text)
getPasswordHash conn uid = do
  rs <- query conn "SELECT password_hash FROM users WHERE id = ?" (Only uid)
    :: IO [Only Text]
  pure $ listToMaybe rs >>= Just . fromOnly

-- | Set a password by user id; False when the user does not exist.
updatePassword :: Connection -> Int -> Text -> IO Bool
updatePassword conn uid pw = do
  h <- hashPassword (TE.encodeUtf8 pw)
  n <- execute conn "UPDATE users SET password_hash = ? WHERE id = ?" (TE.decodeUtf8 h, uid)
  pure (n > 0)

-- | CLI: remove all CRM records but keep user accounts.
wipeCrmData :: Connection -> IO ()
wipeCrmData conn = execScript conn "DELETE FROM documents; DELETE FROM activities; DELETE FROM tasks; DELETE FROM cases; UPDATE leads SET converted_client_id=NULL; DELETE FROM clients; DELETE FROM leads; DELETE FROM audit_log;"

-- ---------- leads ----------

type LeadRow = ( Int, Text, Text, Maybe Text, Maybe Text, Maybe Text
               , Maybe Int, Maybe Text, Maybe Text, Text
               , Maybe Text, Maybe Text, Maybe Text
               , Maybe Day, Maybe Day, UTCTime, UTCTime )

toLead :: LeadRow -> Lead
toLead (i, num, nm, em, ph, src, cid, cname, q, st, dst, sv, notes, lc, fu, ca, ua) =
  Lead i num nm em ph src cid cname q st dst sv notes lc fu ca ua

leadSelect :: Query
leadSelect =
  "SELECT l.id, l.lead_number, l.full_name, l.email, l.phone, l.source, \
  \l.consultant_id, c.name AS consultant_name, l.quality, l.stage, \
  \l.destination, l.service, l.notes, l.last_contact, l.next_followup, \
  \l.created_at, l.updated_at \
  \FROM (SELECT * FROM leads WHERE deleted_at IS NULL AND converted_client_id IS NULL AND ((SELECT assigned_only FROM request_context WHERE id=1) IS DISTINCT FROM 'true' OR (SELECT role FROM request_context WHERE id=1)='admin' OR consultant_id=(SELECT actor_id FROM request_context WHERE id=1))) l LEFT JOIN users c ON c.id = l.consultant_id"

listLeads :: Connection -> IO [Lead]
listLeads conn = do
  rows <- query_ conn (leadSelect <> " ORDER BY l.id DESC") :: IO [LeadRow]
  pure (map toLead rows)

getLead :: Connection -> Int -> IO (Maybe Lead)
getLead conn lid = do
  rows <- query conn (leadSelect <> " WHERE l.id = ?") (Only lid) :: IO [LeadRow]
  pure (toLead <$> listToMaybe rows)

getLeadDetail :: Connection -> Int -> IO (Maybe LeadDetail)
getLeadDetail conn lid = do
  ml <- getLead conn lid
  case ml of
    Nothing -> pure Nothing
    Just l -> do
      ts <- tasksForLead conn lid
      acts <- activitiesForLead conn lid
      docs <- documentsForLead conn lid
      pure (Just (LeadDetail l ts acts docs))

insertLead :: Connection -> NewLead -> Int -> IO Lead
insertLead conn nl actorId = do
  num <- nextNumber conn "L" "leads" "lead_number" 4
  today <- businessDay
  ids <- returning conn
    "INSERT INTO leads (lead_number, full_name, email, phone, source, consultant_id, quality, stage, destination, service, notes, next_followup, last_contact) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?) RETURNING id"
    [ ( num, nlFullName nl, nonEmpty (nlEmail nl), nonEmpty (nlPhone nl)
      , nonEmpty (nlSource nl), maybe (Just actorId) Just (nlConsultantId nl)
      , nonEmpty (nlQuality nl), maybe "New Lead" id (nlStage nl)
      , nonEmpty (nlDestination nl), nonEmpty (nlService nl), nonEmpty (nlNotes nl)
      , nlNextFollowup nl, Just today ) ]
  let lid = head (concat ids)
  logActivity conn lid "created" ("Lead created: " <> num <> " — " <> nlFullName nl)
  mlead <- getLead conn lid
  maybe (error "lead vanished after insert") pure mlead

patchLead :: Connection -> Int -> UpdateLead -> Maybe Int -> IO (Maybe Lead)
patchLead conn lid ul _ = do
  existing <- getLead conn lid
  case existing of
    Nothing -> pure Nothing
    Just old -> do
      case ulStage ul of
        Just newSt | newSt /= stage old ->
          logActivity conn lid "stage_change" ("Moved to " <> newSt)
        _ -> pure ()
      void $ execute conn
        "UPDATE leads SET full_name=COALESCE(NULLIF(?,''),full_name), email=COALESCE(NULLIF(?,''),email), \
        \phone=COALESCE(NULLIF(?,''),phone), source=COALESCE(NULLIF(?,''),source), \
        \consultant_id=COALESCE(?,consultant_id), quality=COALESCE(NULLIF(?,''),quality), \
        \stage=COALESCE(NULLIF(?,''),stage), destination=COALESCE(NULLIF(?,''),destination), \
        \service=COALESCE(NULLIF(?,''),service), notes=COALESCE(NULLIF(?,''),notes), \
        \last_contact=COALESCE(?,last_contact), next_followup=COALESCE(?,next_followup), \
        \updated_at=datetime('now') WHERE id=?"
        ( ulFullName ul, ulEmail ul, ulPhone ul, ulSource ul
        , ulConsultantId ul, ulQuality ul, ulStage ul, ulDestination ul
        , ulService ul, ulNotes ul, ulLastContact ul, ulNextFollowup ul, lid )
      getLead conn lid

-- Database triggers record the change in the same transaction.
deleteLead :: Connection -> Int -> Maybe Int -> IO Bool
deleteLead conn lid _ = (>0) <$> execute conn
  "UPDATE leads SET deleted_at=datetime('now') WHERE id=? AND deleted_at IS NULL AND converted_client_id IS NULL" (Only lid)

advanceStage :: Connection -> Int -> IO (Either Text (Maybe Lead))
advanceStage conn lid = do
  mlead <- getLead conn lid
  case mlead of
    Nothing -> pure (Right Nothing)
    Just l -> case nextOf (stage l) of
      Nothing -> pure (Left ("Already at terminal stage: " <> stage l))
      Just nxt -> do
        void $ execute conn "UPDATE leads SET stage=?, updated_at=datetime('now') WHERE id=?"
          (nxt, lid)
        logActivity conn lid "stage_change" ("Moved to " <> nxt)
        Right <$> getLead conn lid
  where
    nextOf s = case break (== s) leadStages of
      (_, (_:after)) -> listToMaybe after
      _              -> Nothing

convertToClient :: Connection -> Int -> Int -> IO (Maybe Client)
convertToClient conn lid officerId = do
  locked <- query conn "SELECT id FROM leads WHERE id=? AND deleted_at IS NULL" (Only lid) :: IO [Only Int]
  existing <- query conn "SELECT converted_client_id FROM leads WHERE id=?" (Only lid) :: IO [Only (Maybe Int)]
  case existing of
    [Only (Just cid)] -> getClient conn cid
    _ | null locked -> pure Nothing
    _ -> do
      mlead <- getLead conn lid
      case mlead of
        Nothing -> pure Nothing
        Just l -> do
          client <- insertClientRaw conn (fullName l) (email l) (phone l) (Just officerId)
          let cid = clientId client
          case (service l, destination l) of
            (Nothing, Nothing) -> pure ()
            _ -> void $ execute conn
              "INSERT INTO cases (client_id,service_category,destination,stage) VALUES (?,?,?,'New Client')"
              (cid,service l,destination l)
          void $ execute conn "UPDATE documents SET client_id=?,lead_id=NULL WHERE lead_id=?" (cid,lid)
          void $ execute conn "UPDATE tasks SET client_id=? WHERE lead_id=?" (cid,lid)
          logActivity conn lid "converted" ("Converted to " <> clientNumber client)
          void $ execute conn "UPDATE leads SET converted_client_id=?,stage='Converted',updated_at=datetime('now') WHERE id=?" (cid,lid)
          pure (Just client)

addNote :: Connection -> Int -> Text -> IO ()
addNote conn lid note = do
  logActivity conn lid "note" ("Added note: " <> note)
  touchLastContact conn lid

bulkLeads :: Connection -> BulkRequest -> Int -> IO Int
bulkLeads conn br actorId = do
  results <- forM (brIds br) $ \lid -> case brOp br of
    BulkDelete -> boolToInt <$> deleteLead conn lid (Just actorId)
    BulkAssign -> do
      void $ execute conn
        "UPDATE leads SET consultant_id=?, updated_at=datetime('now') WHERE id=?"
        (brConsultantId br, lid)
      pure 1
    BulkAdvance -> either (const 0) (maybe 0 (const 1)) <$> advanceStage conn lid
  pure (sum results)
  where
    boolToInt b = if b then 1 else 0

-- | Import leads from parsed CSV rows (first row = header).  Columns are
-- matched by header name; unknown columns are ignored, so files exported by
-- this same API round-trip cleanly.  Valid rows are inserted, invalid ones
-- are reported per row.  \"Consultant\" is matched against user display
-- names (case-insensitive).
importLeads :: Connection -> [[Text]] -> Int -> IO ImportResult
importLeads conn allRows actorId =
  case allRows of
    (hdr : dataRows) | not (null dataRows) -> do
      users <- filter ((/= "viewer") . userRole) <$> listUsers conn
      let consultants = [ (T.toLower (userName u), userId u) | u :: User <- users ]
          hdrMap = [ (norm h, k) | (k, h) <- zip [0 ..] hdr ]
          norm = T.toLower . T.strip
          pick r name = lookup (norm name) hdrMap >>= \k -> listToMaybe (drop k r)
          val r name = T.strip <$> pick r name >>= nonEmptyT
          dateCell r name =
            case val r name of
              Nothing -> Right Nothing
              Just s -> case parseTimeM False defaultTimeLocale "%Y-%m-%d"
                               (T.unpack s) of
                Just d -> Right (Just (d :: Day))
                Nothing -> Left ("\"" <> name <> "\" must be YYYY-MM-DD")
          build n r =
            case val r "Full Name" of
              Nothing -> Left (n, "Full Name is required")
              Just nm | T.length nm>200 -> Left (n,"Full Name must be 200 characters or fewer")
              Just _ | maybe False (`notElem` leadStages) (val r "Stage") -> Left (n,"Invalid lead stage")
              Just _ | maybe False (`notElem` ["Hot","Warm","Cold"]) (val r "Quality") -> Left (n,"Invalid lead quality")
              Just nm ->
                let mConsultant =
                      case val r "Consultant" of
                        Nothing -> Right Nothing
                        Just cname ->
                          case lookup (T.toLower cname) consultants of
                            Just uid -> Right (Just uid)
                            Nothing -> Left ("Unknown consultant: " <> cname)
                    mDates = (,) <$> dateCell r "Last Contact"
                                 <*> dateCell r "Next Follow-up"
                 in case mConsultant of
                      Left err -> Left (n, err)
                      Right mcid -> case mDates of
                        Left err -> Left (n, err)
                        Right (mlc, mnf) ->
                          Right ( NewLead
                                    { nlFullName = nm
                                    , nlEmail = val r "Email"
                                    , nlPhone = val r "Phone"
                                    , nlSource = val r "Source"
                                    , nlQuality = val r "Quality"
                                    , nlStage = val r "Stage"
                                    , nlDestination = val r "Destination"
                                    , nlService = val r "Service"
                                    , nlNotes = val r "Notes"
                                    , nlNextFollowup = mnf
                                    , nlConsultantId = mcid
                                    }
                                , mlc )
          results = zipWith build [1 ..] dataRows
          failures = [ ImportRowError n e | Left (n, e) <- results ]
          goods = [ g | Right g <- results ]
      imported <- do
        forM_ goods $ \(nl, mlc) -> do
          l <- insertLead conn nl actorId
          forM_ mlc $ \d ->
            void $ execute conn "UPDATE leads SET last_contact=? WHERE id=?"
              (Just d, leadId l)
        pure (length goods)
      pure (ImportResult imported failures)
    _ -> pure (ImportResult 0 [])
  where
    nonEmptyT t = if T.null (T.strip t) then Nothing else Just t


-- ---------- clients / cases ----------

type ClientRowT = (Int, Text, Text, Maybe Text, Maybe Text, Maybe Int, UTCTime)

clientSelect :: Query
clientSelect =
  "SELECT cl.id, cl.client_number, cl.full_name, cl.email, cl.phone, \
  \cl.case_officer_id, u.name AS case_officer_name, cl.created_at \
  \FROM (SELECT * FROM clients WHERE deleted_at IS NULL AND ((SELECT assigned_only FROM request_context WHERE id=1) IS DISTINCT FROM 'true' OR (SELECT role FROM request_context WHERE id=1)='admin' OR case_officer_id=(SELECT actor_id FROM request_context WHERE id=1))) cl LEFT JOIN users u ON u.id = cl.case_officer_id"

toClient :: (Int, Text, Text, Maybe Text, Maybe Text, Maybe Int, Maybe Text, UTCTime) -> Client
toClient (i, num, nm, em, ph, officer, oname, ca) =
  Client i num nm em ph officer oname ca

listClients :: Connection -> IO [Client]
listClients conn = do
  rows <- query_ conn (clientSelect <> " ORDER BY cl.id DESC")
    :: IO [(Int, Text, Text, Maybe Text, Maybe Text, Maybe Int, Maybe Text, UTCTime)]
  pure (map toClient rows)

-- Keep authorization and existence checks independent of workspace size.
getClient :: Connection -> Int -> IO (Maybe Client)
getClient conn cid = do
  rows <- query conn (clientSelect <> " WHERE cl.id = ?") (Only cid)
    :: IO [(Int, Text, Text, Maybe Text, Maybe Text, Maybe Int, Maybe Text, UTCTime)]
  pure (toClient <$> listToMaybe rows)

getClientDetail :: Connection -> Int -> IO (Maybe ClientDetail)
getClientDetail conn cid = do
  client <- getClient conn cid
  case client of
    Nothing -> pure Nothing
    Just clientRecord -> do
      casesRows <- query conn
        "SELECT id, client_id, service_category, destination, stage, next_deadline, created_at FROM cases WHERE client_id = ? ORDER BY id"
        (Only cid) :: IO [(Int, Int, Maybe Text, Maybe Text, Text, Maybe Day, UTCTime)]
      let cases = map (\(i, c, sc, d, st, dl, ca) -> CaseRow i c sc d st dl ca) casesRows
      docs <- documentsForClient conn cid
      ts <- query conn (taskSelect <> " WHERE t.client_id=? ORDER BY t.id DESC") (Only cid) :: IO [TaskRowT]
      acts <- query conn (actSelect <> " WHERE l.converted_client_id=? ORDER BY a.id DESC") (Only cid) :: IO [ActRowT]
      history <- query conn "SELECT h.id,coalesce(h.lead_id,0),cl.full_name,h.kind,coalesce(u.name,'Student/System')||': '||h.note,date(h.created_at,business_offset()) FROM work_history h JOIN clients cl ON cl.id=h.client_id LEFT JOIN users u ON u.id=h.actor_id WHERE h.client_id=? AND (h.task_id IS NULL OR (SELECT assigned_only FROM request_context WHERE id=1)<>'true' OR (SELECT role FROM request_context WHERE id=1)='admin' OR EXISTS(SELECT 1 FROM tasks t WHERE t.id=h.task_id AND t.assigned_to_id=(SELECT actor_id FROM request_context WHERE id=1))) ORDER BY h.id DESC LIMIT 200" (Only cid) :: IO [ActRowT]
      pure (Just (ClientDetail clientRecord cases docs (map toTask ts) (map toAct history ++ map toAct acts)))

insertClientRaw :: Connection -> Text -> Maybe Text -> Maybe Text -> Maybe Int -> IO Client
insertClientRaw conn nm em ph officer = do
  num <- nextNumber conn "ECC" "clients" "client_number" 5
  ids <- returning conn
    "INSERT INTO clients (client_number, full_name, email, phone, case_officer_id) VALUES (?,?,?,?,?) RETURNING id"
    [ (num, nm, em, ph, officer) ]
  detail <- getClient conn (head (concat ids))
  maybe (error "client vanished after insert") pure detail

insertClient :: Connection -> NewClient -> IO Client
insertClient conn nc =
  insertClientRaw conn (ncFullName nc) (ncEmail nc) (ncPhone nc) (ncCaseOfficer nc)

patchClient :: Connection -> Int -> NewClient -> Maybe Int -> IO Bool
patchClient conn cid nc _ = do
  existing <- getClient conn cid
  case existing of
    Nothing -> pure False
    Just _ -> do
      n <- execute conn
        "UPDATE clients SET full_name=COALESCE(NULLIF(?,''),full_name), email=COALESCE(?,email), \
        \phone=COALESCE(?,phone), case_officer_id=COALESCE(?,case_officer_id) WHERE id=?"
        (Just (ncFullName nc), ncEmail nc, ncPhone nc, ncCaseOfficer nc, cid)
      pure (n > 0)

deleteClient :: Connection -> Int -> Maybe Int -> IO Bool
deleteClient conn cid _ = (>0) <$> execute conn
  "UPDATE clients SET deleted_at=datetime('now') WHERE id=? AND deleted_at IS NULL" (Only cid)

upsertCase :: Connection -> Int -> CaseInput -> IO ()
upsertCase conn cid ci = case ciCaseId ci of
  Just caseId -> void $ execute conn
    "UPDATE cases SET service_category=COALESCE(?,service_category), \
    \destination=COALESCE(?,destination), stage=COALESCE(?,stage), \
    \next_deadline=COALESCE(?,next_deadline) WHERE id=? AND client_id=?"
    (ciServiceCategory ci, ciDestination ci, ciStage ci, ciNextDeadline ci, caseId, cid)
  Nothing -> void $ execute conn
    "INSERT INTO cases (client_id, service_category, destination, stage, next_deadline) VALUES (?,?,?,?,?)"
    (cid, ciServiceCategory ci, ciDestination ci,
     maybe "Documents Under Review" id (ciStage ci), ciNextDeadline ci)

deleteCase :: Connection -> Int -> IO Bool
deleteCase conn caseId = (> 0) <$> execute conn "DELETE FROM cases WHERE id = ?" (Only caseId)

-- ---------- documents ----------

type DocRowT = (Int, Maybe Int, Maybe Int, Text, Text, Int, Maybe Text, UTCTime)

docSelect :: Query
docSelect =
  "SELECT d.id, d.lead_id, d.client_id, d.filename, d.mime_type, d.size, \
  \u.name AS uploader_name, d.created_at \
  \FROM documents d LEFT JOIN users u ON u.id = d.uploaded_by"

toDoc :: DocRowT -> Document
toDoc (i, lid, cid, fname, mime, sz, up, ca) =
  Document i lid cid fname mime sz up ca

documentsForLead :: Connection -> Int -> IO [Document]
documentsForLead conn lid = do
  rows <- query conn (docSelect <> " WHERE d.lead_id = ? ORDER BY d.id DESC")
    (Only lid) :: IO [DocRowT]
  pure (map toDoc rows)

documentsForClient :: Connection -> Int -> IO [Document]
documentsForClient conn cid = do
  rows <- query conn (docSelect <> " WHERE d.client_id = ? ORDER BY d.id DESC")
    (Only cid) :: IO [DocRowT]
  pure (map toDoc rows)

-- | Stores the raw bytes; exactly one of lead\/client id must be Just.
insertDocument :: Connection -> Maybe Int -> Maybe Int -> Text -> Text
               -> B.ByteString -> Maybe Int -> IO Document
insertDocument conn mlid mcid fname mime content uploaderId = do
  ids <- returning conn
    "INSERT INTO documents (lead_id, client_id, filename, mime_type, size, content, uploaded_by) VALUES (?,?,?,?,?,?,?) RETURNING id"
    [ (mlid, mcid, fname, mime, B.length content, Binary content, uploaderId) ]
    :: IO [[Int]]
  let did = head (concat ids)
  rows <- query conn (docSelect <> " WHERE d.id = ?") (Only did) :: IO [DocRowT]
  pure (toDoc (head rows))

-- | Filename + content-type + bytes for a download.
getDocumentContent :: Connection -> Int -> IO (Maybe (Text, Text, B.ByteString))
getDocumentContent conn did = do
  rows <- query conn
    "SELECT filename, mime_type, content FROM documents WHERE id = ?"
    (Only did) :: IO [(Text, Text, Binary B.ByteString)]
  pure $ case rows of
    [(fname, mime, Binary bs)] -> Just (fname, mime, bs)
    _                          -> Nothing

deleteDocument :: Connection -> Int -> IO Bool
deleteDocument conn did = (> 0) <$> execute conn "DELETE FROM documents WHERE id = ?" (Only did)

-- ---------- tasks ----------

taskSelect :: Query
taskSelect =
  "SELECT t.id, COALESCE(t.lead_id,0) AS lead_id, COALESCE(cl.full_name,l.full_name) AS lead_name, t.title, t.description, \
  \t.due_date, t.priority, t.status, t.assigned_to_id, u.name AS assignee_name, \
  \t.created_at, t.client_id \
  \FROM (SELECT * FROM tasks WHERE (client_id IS NULL OR EXISTS (SELECT 1 FROM clients owner_client WHERE owner_client.id=tasks.client_id AND owner_client.deleted_at IS NULL AND ((SELECT assigned_only FROM request_context WHERE id=1) IS DISTINCT FROM 'true' OR (SELECT role FROM request_context WHERE id=1)='admin' OR owner_client.case_officer_id=(SELECT actor_id FROM request_context WHERE id=1)))) AND (lead_id IS NULL OR EXISTS (SELECT 1 FROM leads owner_lead WHERE owner_lead.id=tasks.lead_id AND owner_lead.deleted_at IS NULL AND (tasks.client_id IS NOT NULL OR (SELECT assigned_only FROM request_context WHERE id=1) IS DISTINCT FROM 'true' OR (SELECT role FROM request_context WHERE id=1)='admin' OR owner_lead.consultant_id=(SELECT actor_id FROM request_context WHERE id=1)))) AND ((SELECT assigned_only FROM request_context WHERE id=1) IS DISTINCT FROM 'true' OR (SELECT role FROM request_context WHERE id=1)='admin' OR assigned_to_id=(SELECT actor_id FROM request_context WHERE id=1))) t LEFT JOIN leads l ON l.id = t.lead_id LEFT JOIN clients cl ON cl.id=t.client_id \
  \LEFT JOIN users u ON u.id = t.assigned_to_id"

listTasks :: Connection -> IO [Task]
listTasks conn = do
  rows <- query_ conn (taskSelect <> " ORDER BY t.due_date NULLS LAST, t.id DESC")
    :: IO [TaskRowT]
  pure (map toTask rows)

tasksForLead :: Connection -> Int -> IO [Task]
tasksForLead conn lid = do
  rows <- query conn (taskSelect <> " WHERE t.lead_id = ? ORDER BY t.id DESC")
    (Only lid) :: IO [TaskRowT]
  pure (map toTask rows)

type TaskRowT = ( Int, Int, Maybe Text, Text, Maybe Text, Maybe Day
                , Text, Text, Maybe Int, Maybe Text, UTCTime, Maybe Int )

toTask :: TaskRowT -> Task
toTask (i, lid, lname, title, desc, due, prio, st, aid, aname, ca, cid) =
  Task i lid lname title desc due prio st aid aname ca cid

insertTask :: Connection -> NewTask -> Int -> IO Task
insertTask conn nt actorId = do
  ids <- returning conn
    "INSERT INTO tasks (lead_id, title, description, due_date, priority, status, assigned_to_id,client_id) VALUES (?,?,?,?,?,?,?,?) RETURNING id"
    [ (ntLeadId nt, ntTitle nt, ntDescription nt, ntDueDate nt,
       maybe "Medium" id (ntPriority nt), "Pending" :: Text, actorId, ntClientId nt) ] :: IO [[Int]]
  let tid = head (concat ids)
  forM_ (ntLeadId nt) $ \lid -> logActivity conn lid "task" ("Task added: " <> ntTitle nt)
  rows <- query conn (taskSelect <> " WHERE t.id = ?") (Only tid) :: IO [TaskRowT]
  pure (toTask (head rows))

setTaskStatus :: Connection -> Int -> Text -> IO Bool
setTaskStatus conn tid st = do
  n <- execute conn "UPDATE tasks SET status=? WHERE id=?" (st, tid)
  pure (n > 0)

deleteTask :: Connection -> Int -> IO Bool
deleteTask conn tid = (> 0) <$> execute conn "DELETE FROM tasks WHERE id=?" (Only tid)

-- ---------- activities ----------

type ActRowT = (Int, Int, Maybe Text, Text, Maybe Text, Day)

actSelect :: Query
actSelect =
  "SELECT a.id, a.lead_id, l.full_name AS lead_name, a.type, a.description, a.date \
  \FROM activities a JOIN leads l ON l.id = a.lead_id AND l.deleted_at IS NULL AND ((SELECT assigned_only FROM request_context WHERE id=1) IS DISTINCT FROM 'true' OR (SELECT role FROM request_context WHERE id=1)='admin' OR l.consultant_id=(SELECT actor_id FROM request_context WHERE id=1))"

listActivities :: Connection -> Int -> IO [Activity]
listActivities conn limit = do
  rows <- query conn (actSelect <> " ORDER BY a.id DESC LIMIT ?") (Only limit)
    :: IO [ActRowT]
  pure (map toAct rows)

activitiesForLead :: Connection -> Int -> IO [Activity]
activitiesForLead conn lid = do
  rows <- query conn (actSelect <> " WHERE a.lead_id = ? ORDER BY a.id DESC")
    (Only lid) :: IO [ActRowT]
  pure (map toAct rows)

toAct :: ActRowT -> Activity
toAct (i, lid, lname, kind, desc, day) = Activity i lid lname kind desc day

-- ---------- stats ----------

-- ---------- audit trail ----------

type AuditRowT = (Int, Text, Int, Maybe Text, Text, Maybe A.Value, Maybe Text, UTCTime)

toAudit :: AuditRowT -> AuditEntry
toAudit (i, etype, eid, ename, action, changes, actor, ca) =
  AuditEntry i etype eid ename action changes actor ca

auditSelect :: Query
auditSelect =
  "SELECT a.id, a.entity_type, a.entity_id, a.entity_name, a.action, \
  \a.changes, u.name AS actor_name, a.created_at \
  \FROM audit_log a LEFT JOIN users u ON u.id = a.actor_id"

-- | Latest audit entries, optionally filtered by entity type and\/or id.
listAuditEntries :: Connection -> Maybe Text -> Maybe Int -> Int -> IO [AuditEntry]
listAuditEntries conn mType mId limit
  | Just t <- mType, Just i <- mId = do
      rows <- query conn (auditSelect <>
        " WHERE a.entity_type = ? AND a.entity_id = ? ORDER BY a.id DESC LIMIT ?")
        (t, i, limit) :: IO [AuditRowT]
      pure (map toAudit rows)
  | Just t <- mType = do
      rows <- query conn (auditSelect <>
        " WHERE a.entity_type = ? ORDER BY a.id DESC LIMIT ?") (t, limit)
        :: IO [AuditRowT]
      pure (map toAudit rows)
  | otherwise = do
      rows <- query conn (auditSelect <> " ORDER BY a.id DESC LIMIT ?") (Only limit)
        :: IO [AuditRowT]
      pure (map toAudit rows)

-- ---------- stats ----------

getStats :: Connection -> IO Stats
getStats conn = do
  total <- scalar ("SELECT count(*) FROM (" <> leadSelect <> ") records")
  hot <- scalar ("SELECT count(*) FROM (" <> leadSelect <> ") records WHERE quality='Hot'")
  clients <- scalar ("SELECT count(*) FROM (" <> clientSelect <> ") records")
  openT <- scalar ("SELECT count(*) FROM (" <> taskSelect <> ") records WHERE cancelled_at IS NULL AND status<>'Done'")
  overdue <- scalar ("SELECT count(*) FROM (" <> taskSelect <> ") records WHERE cancelled_at IS NULL AND status<>'Done' AND due_date<date('now',business_offset())")
  stages <- query_ conn ("SELECT stage,count(*) FROM (" <> leadSelect <> ") records GROUP BY stage") :: IO [(Text,Int)]
  sources <- query_ conn ("SELECT coalesce(source,'Unknown'),count(*) AS count FROM (" <> leadSelect <> ") records GROUP BY source ORDER BY count DESC") :: IO [(Text,Int)]
  upcomingRows <- query_ conn (taskSelect <>
    " WHERE t.cancelled_at IS NULL AND t.status<>'Done' ORDER BY t.due_date NULLS LAST LIMIT 6") :: IO [TaskRowT]
  recent <- listActivities conn 8
  pure Stats
    { stTotalLeads = total
    , stHotLeads = hot
    , stTotalClients = clients
    , stOpenTasks = openT
    , stOverdueTasks = overdue
    , stStageCounts = map (uncurry StageCount) stages
    , stSourceCounts = map (uncurry SourceCount) sources
    , stUpcomingTasks = map toTask upcomingRows
    , stRecentActivity = recent
    }
  where
    scalar q = do
      rs <- query_ conn q :: IO [Only Int]
      pure (maybe 0 fromOnly (listToMaybe rs))

-- Lists are bounded at the database, with a stable offset and order.
listLeadsPage :: Connection -> Int -> Int -> Text -> Text -> Text -> Text -> Text -> Bool -> IO [Lead]
listLeadsPage conn limit offset search stageFilter qualityFilter sourceFilter sort ascending = map toLead <$> (query conn
  (leadSelect <> " WHERE (l.full_name LIKE ? OR l.email LIKE ? OR l.lead_number LIKE ? OR l.phone LIKE ?) AND (?='' OR l.stage=?) AND (?='' OR l.quality=?) AND (?='' OR l.source=?) ORDER BY " <> sortColumn <> direction <> ",l.id DESC LIMIT ? OFFSET ?")
  (q,q,q,q,stageFilter,stageFilter,qualityFilter,qualityFilter,sourceFilter,sourceFilter,limit,offset) :: IO [LeadRow])
  where
    q = "%" <> search <> "%"
    sortColumn = case sort of "name" -> "l.full_name"; "stage" -> "l.stage"; "quality" -> "l.quality"; "followup" -> "l.next_followup"; _ -> "l.id"
    direction = if ascending then " ASC NULLS LAST" else " DESC NULLS LAST"
listClientsPage :: Connection -> Int -> Int -> Text -> IO [Client]
listClientsPage conn limit offset search = map toClient <$> (query conn
  (clientSelect <> " WHERE (cl.full_name LIKE ? OR cl.email LIKE ? OR cl.client_number LIKE ? OR cl.phone LIKE ?) ORDER BY cl.id DESC LIMIT ? OFFSET ?")
  (q,q,q,q,limit,offset) :: IO [(Int,Text,Text,Maybe Text,Maybe Text,Maybe Int,Maybe Text,UTCTime)]) where q = "%" <> search <> "%"
listTasksPage :: Connection -> Int -> Int -> IO [Task]
listTasksPage conn limit offset = map toTask <$> (query conn
  (taskSelect <> " ORDER BY t.due_date NULLS LAST,t.id DESC LIMIT ? OFFSET ?") (limit,offset) :: IO [TaskRowT])
