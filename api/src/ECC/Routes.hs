{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}

-- | All HTTP routes (Scotty).  Every endpoint lives under @/api@ and speaks
-- camelCase JSON.  Protected endpoints require @Authorization: Bearer <jwt>@;
-- viewers are read-only.
module ECC.Routes (app) where

import Control.Exception (SomeException, throwIO, evaluate)
import Control.Monad (unless,when, void, forM_)
import ECC.Store
import qualified ECC.DailyWork as DailyWork
import qualified ECC.Access as Access
import ECC.Security
import qualified ECC.Operations as Ops
import qualified Data.Aeson.KeyMap as KM
import Control.Monad.IO.Class (liftIO)
import qualified Data.Aeson as A
import Data.Aeson ((.=))
import qualified Data.ByteString as B
import qualified Data.ByteString.Lazy as BL
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import qualified Data.Text.Lazy as TL
import Network.HTTP.Types (status200, status400, status401, status403,
                           status404, status409, status500)
import qualified Network.Wai as Wai
import Network.Wai.Parse (FileInfo (..))
import qualified Web.Scotty as S

import ECC.MFA (verifyMfa)
import ECC.WorkflowSupport (respondJson,checkRevision,taskVisibility)
import qualified ECC.Workflows as Workflows
import ECC.Auth (checkPassword, checkLoginPassword, randomToken, tokenHash)
import ECC.Csv (clientsCsv, leadsCsv, parseCsv)
import ECC.DB
import ECC.Release (releaseContract)
import ECC.Clock (businessZone, clockPayload)
import Data.Time.Clock (getCurrentTime)
import ECC.Models

errJson :: Int -> T.Text -> A.Value
errJson code msg =
  A.object ["error" .= msg, "status" .= code]

unauthorized :: T.Text -> S.ActionM ()
unauthorized msg = S.status status401 >> S.json (errJson 401 msg)

forbidden :: T.Text -> S.ActionM ()
forbidden msg = S.status status403 >> S.json (errJson 403 msg)

notFound :: T.Text -> S.ActionM ()
notFound msg = S.status status404 >> S.json (errJson 404 msg)

badRequest :: T.Text -> S.ActionM ()
badRequest msg = S.status status400 >> S.json (errJson 400 msg)

serverError :: T.Text -> S.ActionM ()
serverError msg = S.status status500 >> S.json (errJson 500 msg)

-- ---------- auth plumbing ----------

currentUser :: Env -> S.ActionM (Maybe User)
currentUser env = do
  req <- S.request
  case requestToken req of
    Nothing -> pure Nothing
    Just tok -> do
      muid <- liftIO $ validSession env tok
      case muid of
        Nothing -> pure Nothing
        Just uid -> liftIO $ getUserById (envConn env) uid

-- Main-schema triggers keep the actor for writes; reads use connection-local context.
setRequestContext :: Env -> User -> S.ActionM ()
setRequestContext env u = do
  req <- S.request
  scope <- liftIO $ Access.assignedOnly env u
  let params = (userId u,userRole u,if scope then "true"::T.Text else "false")
  liftIO $ do
    void $ execute (envConn env) "UPDATE temp.request_context SET actor_id=?,role=?,assigned_only=? WHERE id=1" params
    when (not (isPostgres (envConn env)) && Wai.requestMethod req `notElem` ["GET","HEAD","OPTIONS"]) $
      void $ execute (envConn env) "UPDATE main.request_context SET actor_id=?,role=?,assigned_only=? WHERE id=1" params

withUser :: Env -> (User -> S.ActionM ()) -> S.ActionM ()
withUser env act = do
  mu <- currentUser env
  case mu of
    Just u -> do
      setRequestContext env u
      Workflows.accountGate env u
      authorizePath env u
      Access.authorize env u
      act u
    Nothing -> unauthorized "Not authenticated"

withWriter :: Env -> (User -> S.ActionM ()) -> S.ActionM ()
withWriter env act = withUser env $ \u ->
  if userRole u == "viewer"
    then forbidden "Read-only account — ask an admin for write access"
    else act u

-- | Admin-only endpoints (user management).
withAdmin :: Env -> (User -> S.ActionM ()) -> S.ActionM ()
withAdmin env act = withUser env $ \u ->
  if userRole u /= "admin"
    then forbidden "Admin access required"
    else do
      act u

-- | Optional query-string parameter.
qparam :: T.Text -> S.ActionM (Maybe T.Text)
qparam name = lookup name <$> S.queryParams

-- | Downloads authenticate using the same secure cookie or bearer header.
currentUserWithQueryToken :: Env -> S.ActionM (Maybe User)
currentUserWithQueryToken env = do
  -- Downloads use the same HttpOnly cookie as every other request.
  mu <- currentUser env
  case mu of
    Nothing -> pure Nothing
    Just u -> do
      setRequestContext env u
      Workflows.accountGate env u
      authorizePath env u
      Access.authorize env u
      pure (Just u)

-- Check nested record routes before writes and downloads, as well as reads.
authorizePath :: Env -> User -> S.ActionM ()
authorizePath env u = do
  req <- S.request
  scope <- liftIO $ Access.assignedOnly env u
  let conn = envConn env
      check records = when (null records) (reject status404 "Record not found")
  case Wai.pathInfo req of
    ("api":"leads":sid:_) | Just i <- (readMaybeT sid :: Maybe Int) -> do
      if Wai.requestMethod req == "POST" && "restore" `elem` Wai.pathInfo req && userRole u == "admin" then pure () else do
        ml <- liftIO $ getLead conn i
        -- Conversion retries may read the original source record.
        case ml of
          Just _ -> pure ()
          Nothing | "convert" `elem` Wai.pathInfo req -> do
            rows <- liftIO $ query conn "SELECT id FROM leads WHERE id=? AND deleted_at IS NULL AND converted_client_id IS NOT NULL AND (?='admin' OR NOT ? OR consultant_id=?)" (i,userRole u,scope,userId u) :: S.ActionM [Only Int]
            check rows
          Nothing -> reject status404 "Lead not found"
    ("api":"clients":sid:_) | Just i <- (readMaybeT sid :: Maybe Int) ->
      if "restore" `elem` Wai.pathInfo req && userRole u == "admin" then pure () else do
        mc <- liftIO $ getClient conn i
        when (maybe True (const False) mc) (reject status404 "Student not found")
    ("api":kind:sid:_) | kind `elem` ["documents","cases","tasks"], Just i <- (readMaybeT sid :: Maybe Int) -> do
      owners <- liftIO $ case kind of
        "documents" -> query conn "SELECT lead_id,client_id FROM documents WHERE id=?" (Only i)
        "cases" -> query conn "SELECT NULL,client_id FROM cases WHERE id=?" (Only i)
        _ -> query conn ("SELECT t.lead_id,t.client_id FROM tasks t WHERE t.id=? AND "<>taskVisibility) (Only i)
      case owners :: [(Maybe Int,Maybe Int)] of
        [(ml,mc)] -> case mc of
          Just cid -> liftIO (getClient conn cid) >>= \r -> when (maybe True (const False) r) (reject status404 "Record not found")
          Nothing -> case ml of
            Just lid -> liftIO (getLead conn lid) >>= \r -> when (r == Nothing) (reject status404 "Record not found")
            Nothing -> reject status404 "Record not found"
        _ -> reject status404 "Record not found"
    _ -> pure ()

-- ---------- the application ----------

app :: Env -> S.ScottyM ()
app env = do
  DailyWork.contactRoutes env (withWriter env)
  S.setMaxRequestBodySize (27 * 1024)
  S.defaultHandler (S.Handler (\(err :: SomeException) -> liftIO (throwIO err)))
  Workflows.routes env (withUser env) (withWriter env) (withAdmin env)
  -- Same-origin deployment: no permissive CORS policy.
  S.get "/api/time" $ do
    S.setHeader "Cache-Control" "no-store"
    now <- liftIO getCurrentTime
    zone <- liftIO businessZone
    S.json (clockPayload zone now)
  S.get "/api/ready" $ do
    _ <- liftIO (query_ (envConn env) "SELECT count(*) FROM main.users" :: IO [Only Int])
    respondJson env (A.object ["status" .= ("ready"::T.Text), "contract" .= releaseContract])
  S.get "/api/metrics" $ withAdmin env $ \_ -> do
    let storage = if isPostgres (envConn env) then "pg_database_size(current_database())" else "(SELECT page_count*page_size FROM pragma_page_count(),pragma_page_size())"
    rows <- liftIO (query_ (envConn env) ("SELECT json_object('pendingMail',(SELECT count(*) FROM mail_outbox WHERE sent_at IS NULL),'failedMail',(SELECT count(*) FROM mail_outbox WHERE sent_at IS NULL AND attempts>=5),'activeSessions',(SELECT count(*) FROM sessions WHERE expires_at>datetime('now')),'databaseBytes'," <> storage <> ")") :: IO [Only A.Value])
    respondJson env (map fromOnly rows)
  S.get "/api/archive" $ withAdmin env $ \_ -> do
    (limit,offset,_) <- paging
    rows <- liftIO (query (envConn env) "SELECT item FROM (SELECT json_object('id',id,'kind','lead','name',full_name,'number',lead_number,'date',deleted_at) AS item FROM leads WHERE deleted_at IS NOT NULL UNION ALL SELECT json_object('id',id,'kind','client','name',full_name,'number',client_number,'date',deleted_at) FROM clients WHERE deleted_at IS NOT NULL) ORDER BY json_extract(item,'$.date') DESC,json_extract(item,'$.kind'),json_extract(item,'$.id') DESC LIMIT ? OFFSET ?" (limit,offset) :: IO [Only A.Value])
    respondJson env (map fromOnly rows)
  S.post "/api/leads/:id/restore" $ do
    lid <- S.pathParam "id"
    withAdmin env $ \_ -> do
      n <- liftIO $ execute (envConn env) "UPDATE leads SET deleted_at=NULL WHERE id=? AND deleted_at IS NOT NULL AND converted_client_id IS NULL AND merged_into IS NULL" (Only (lid::Int))
      if n>0 then respondJson env (A.object ["restored" .= True]) else notFound "Archived lead not found"
  S.post "/api/clients/:id/restore" $ do
    cid <- S.pathParam "id"
    withAdmin env $ \_ -> do
      n <- liftIO $ execute (envConn env) "UPDATE clients SET deleted_at=NULL WHERE id=? AND deleted_at IS NOT NULL AND merged_into IS NULL" (Only (cid::Int))
      if n>0 then respondJson env (A.object ["restored" .= True]) else notFound "Archived student not found"
  S.get "/api/duplicates" $ withUser env $ \u -> do
    scope <- liftIO $ Access.assignedOnly env u
    (limit,offset,_) <- paging
    rows <- liftIO $ query (envConn env)
      "WITH records AS (SELECT id,'lead' AS kind,full_name,lower(trim(email)) AS email,replace(replace(replace(replace(replace(phone,' ',''),'+',''),'-',''),'(',''),')','') AS phone FROM leads WHERE deleted_at IS NULL AND converted_client_id IS NULL AND (?='admin' OR NOT ? OR consultant_id=?) UNION ALL SELECT id,'client',full_name,lower(trim(email)),replace(replace(replace(replace(replace(phone,' ',''),'+',''),'-',''),'(',''),')','') FROM clients WHERE deleted_at IS NULL AND (?='admin' OR NOT ? OR case_officer_id=?)), matches AS (SELECT 'email' AS field,email AS value,json_group_array(json_object('id',id,'kind',kind,'name',full_name)) AS records FROM records WHERE email<>'' GROUP BY email HAVING count(*)>1 UNION ALL SELECT 'phone',phone,json_group_array(json_object('id',id,'kind',kind,'name',full_name)) FROM records WHERE length(phone)>=7 GROUP BY phone HAVING count(*)>1) SELECT json_object('field',field,'value',value,'records',json(records)) FROM matches ORDER BY field,value LIMIT ? OFFSET ?"
      (userRole u,scope,userId u,userRole u,scope,userId u,limit,offset) :: S.ActionM [Only A.Value]
    respondJson env (map fromOnly rows)
  S.get "/api/reminders" $ withUser env $ \u -> do
    scope <- liftIO $ Access.assignedOnly env u
    (limit,offset,_) <- paging
    rows <- liftIO $ query (envConn env)
      ("SELECT item FROM (SELECT json_object('id',t.id,'kind','task','title',t.title,'due',t.due_date,'path',CASE WHEN t.client_id IS NOT NULL THEN '/clients/'||t.client_id ELSE '/leads/'||t.lead_id END,'read',json(CASE WHEN EXISTS(SELECT 1 FROM reminder_receipts r WHERE r.user_id=? AND r.task_id=t.id AND r.due_date=t.due_date) THEN 'true' ELSE 'false' END)) AS item FROM tasks t LEFT JOIN leads l ON l.id=t.lead_id LEFT JOIN clients c ON c.id=t.client_id WHERE t.cancelled_at IS NULL AND t.status<>'Done' AND t.due_date<=date('now',business_offset(),'+7 days') AND l.deleted_at IS NULL AND c.deleted_at IS NULL AND "<>taskVisibility<>" UNION ALL SELECT json_object('id',l.id,'kind','followup','title','Follow up: '||l.full_name,'due',l.next_followup,'path','/leads/'||l.id,'read',json(CASE WHEN EXISTS(SELECT 1 FROM followup_receipts r WHERE r.user_id=? AND r.lead_id=l.id AND r.due_date=l.next_followup) THEN 'true' ELSE 'false' END)) FROM leads l WHERE l.deleted_at IS NULL AND l.converted_client_id IS NULL AND l.next_followup<=date('now',business_offset(),'+7 days') AND (?='admin' OR NOT ? OR l.consultant_id=?)) ORDER BY json_extract(item,'$.due'),json_extract(item,'$.kind'),json_extract(item,'$.id') LIMIT ? OFFSET ?")
      (userId u,userId u,userRole u,scope,userId u,limit,offset) :: S.ActionM [Only A.Value]
    respondJson env (map fromOnly rows)
  S.post "/api/reminders/:kind/:id/read" $ do
    kind <- S.pathParam "kind" :: S.ActionM T.Text
    rid <- S.pathParam "id" :: S.ActionM Int
    withUser env $ \u -> do
      scope <- liftIO $ Access.assignedOnly env u
      if kind=="task" then do
        _ <- liftIO $ execute (envConn env) ("INSERT INTO reminder_receipts(user_id,task_id,due_date) SELECT ?,t.id,t.due_date FROM tasks t WHERE t.id=? AND t.due_date IS NOT NULL AND "<>taskVisibility<>" ON CONFLICT DO NOTHING") (userId u,rid)
        pure ()
      else if kind=="followup" then do
        _ <- liftIO $ execute (envConn env) "INSERT INTO followup_receipts(user_id,lead_id,due_date) SELECT ?,id,next_followup FROM leads WHERE id=? AND next_followup IS NOT NULL AND (?='admin' OR NOT ? OR consultant_id=?) ON CONFLICT DO NOTHING" (userId u,rid,userRole u,scope,userId u)
        pure ()
      else reject status400 "Invalid reminder type"
      respondJson env (A.object ["read" .= True])
  S.post "/api/auth/logout" $ endSession env >> respondJson env (A.object ["loggedOut" .= True])
  S.post "/api/auth/recover" $ do
    rateLimit env "recover"
    body <- validated env
    addr <- textField "email" body
    rateLimitAccount env "recover" addr
    mu <- liftIO $ getUserByEmailWithHash (envConn env) (T.strip addr)
    forM_ mu $ \(u,_) -> issueAccountToken env (userId u) (userEmail u)
    respondJson env (A.object ["message" .= ("If the account exists, a recovery link has been queued."::T.Text)])
  S.post "/api/auth/reset" $ do
    rateLimit env "reset"
    body <- validated env
    tok <- textField "token" body
    pw <- textField "password" body
    when (T.length pw < 12 || B.length (TE.encodeUtf8 pw)>72) $ reject status400 "Use a password of 12–72 bytes"
    rows <- liftIO $ query (envConn env) "DELETE FROM account_tokens WHERE token_hash=? AND expires_at>datetime('now') RETURNING user_id" (Only (tokenHash (TE.encodeUtf8 tok))) :: S.ActionM [Only Int]
    case rows of
      [Only uid] -> do
        _ <- liftIO $ updatePassword (envConn env) uid pw
        endSession env
        respondJson env (A.object ["updated" .= True])
      _ -> reject status400 "This link is invalid or expired. Request a new one."
  S.post "/api/users/:id/invite" $ do
    uid <- S.pathParam "id"
    withAdmin env $ \adminUser -> do
      rateLimitAccount env "invite" (T.pack (show (userId adminUser)))
      mu <- liftIO $ getUserById (envConn env) uid
      case mu of
        Nothing -> notFound "User not found"
        Just u -> issueAccountToken env uid (userEmail u) >> respondJson env (A.object ["queued" .= True])


  -- ---- auth ----
  S.post "/api/auth/login" $ do
    rateLimit env "login"
    LoginRequest email password otp <- validated env
    rateLimitAccount env "login" email
    mrow <- liftIO $ getUserByEmailWithHash (envConn env) email
    matched <- liftIO $ evaluate (checkLoginPassword (TE.encodeUtf8 password) (TE.encodeUtf8 . snd <$> mrow))
    case mrow of
      Just (u, hash)
        | matched -> do
            [Only factor] <- liftIO $ query (envConn env) "SELECT mfa_secret FROM users WHERE id=?" (Only (userId u))
            verified <- liftIO $ verifyMfa env (userId u) (maybe "" id otp)
            unless verified $ reject status401 "Enter your authenticator or recovery code"
            tok <- startSession env (userId u) hash factor
            respondJson env (LoginResponse (TE.decodeUtf8 tok) u)
      _ -> unauthorized "Invalid email or password"

  S.get "/api/auth/me" $
    withUser env (respondJson env)

  -- ---- users ----
  S.get "/api/users" $
    withUser env $ \_ -> respondJson env =<< liftIO (listUsers (envConn env))

  S.post "/api/users" $
    withAdmin env $ \_ -> do
      rawUser <- validated env
      temporary <- liftIO randomToken
      let invited = T.null (nuPassword rawUser)
          nu = if invited then rawUser { nuPassword = TE.decodeUtf8 temporary } else rawUser
      if not (validRole (nuRole nu))
        then badRequest "Role must be admin, consultant, or viewer"
        else if T.null (T.strip (nuEmail nu)) || T.null (T.strip (nuName nu))
                || T.length (nuPassword nu) < 12
          then badRequest "Name, email, and a password of at least 12 characters are required"
          else do
            mu <- liftIO $ insertUser (envConn env) nu
            case mu of
              Just u  -> do
                when invited $ issueAccountToken env (userId u) (userEmail u)
                S.status status200 >> respondJson env u
              Nothing -> badRequest "Email is already registered"

  S.patch "/api/users/:id" $ do
    uid <- S.pathParam "id"
    withAdmin env $ \actor -> do
      uu <- validated env
      checkRevisionBody env "users" uid
      case uuRole uu of
        Just r | not (validRole r) ->
          badRequest "Role must be admin, consultant, or viewer"
        _ -> do
          mt <- liftIO $ getUserById (envConn env) uid
          case mt of
            Nothing -> notFound "User not found"
            Just t -> do
              let demoting = maybe False (/= "admin") (uuRole uu)
                             && userRole t == "admin"
              admins <- if demoting
                          then liftIO $ countAdminsExcluding (envConn env) uid
                          else pure 1
              if demoting && admins == 0
                then badRequest "Cannot remove the last admin"
                else if uid == userId actor && demoting
                  then badRequest "You cannot change your own role"
                  else do
                    ok <- liftIO $ patchUser (envConn env) uid uu
                    if ok then respondJson env (A.object ["updated" .= True])
                          else notFound "User not found"

  S.delete "/api/users/:id" $ do
    uid <- S.pathParam "id"
    withAdmin env $ \actor ->
      if uid == userId actor
        then badRequest "You cannot delete your own account"
        else do
          mt <- liftIO $ getUserById (envConn env) uid
          case mt of
            Nothing -> notFound "User not found"
            Just t -> do
              admins <- if userRole t == "admin"
                          then liftIO $ countAdminsExcluding (envConn env) uid
                          else pure 1
              if admins == 0
                then badRequest "Cannot delete the last admin"
                else do
                  ok <- liftIO $ deleteUser (envConn env) uid
                  if ok then respondJson env (A.object ["deleted" .= True])
                        else notFound "User not found"

  -- change own password (any role)
  S.put "/api/auth/password" $
    withUser env $ \u -> do
      pc <- validated env
      mhash <- liftIO $ getPasswordHash (envConn env) (userId u)
      let okPw = maybe False (\h -> checkPassword (TE.encodeUtf8 (pcCurrent pc))
                                                  (TE.encodeUtf8 h)) mhash
      if not okPw
        then unauthorized "Current password is incorrect"
        else if T.length (pcNew pc) < 12
          then badRequest "New password must be at least 12 characters"
          else do
            ok <- liftIO $ updatePassword (envConn env) (userId u) (pcNew pc)
            if ok then endSession env >> respondJson env (A.object ["updated" .= True])
                  else serverError "Could not update password"

  -- ---- leads ----

  -- ---- leads ----
  S.get "/api/leads" $
    withUser env $ \_ -> do
      (limit,offset,search) <- paging
      st <- maybe "" id <$> qparam "stage"
      quality <- maybe "" id <$> qparam "quality"
      source <- maybe "" id <$> qparam "source"
      sort <- maybe "id" id <$> qparam "sort"
      ascending <- (== Just "asc") <$> qparam "direction"
      respondJson env =<< liftIO (listLeadsPage (envConn env) limit offset search st quality source sort ascending)

  S.post "/api/leads" $
    withWriter env $ \u -> do
      nl <- validated env
      l <- liftIO $ insertLead (envConn env) nl (userId u)
      S.status status200 >> respondJson env l

  S.get "/api/leads/:id" $ do
    lid <- S.pathParam "id"
    withUser env $ \_ -> do
      md <- liftIO $ getLeadDetail (envConn env) lid
      case md of
        Just d -> respondJson env d
        Nothing -> notFound "Lead not found"

  S.patch "/api/leads/:id" $ do
    lid <- S.pathParam "id"
    withWriter env $ \u -> do
      ul <- validated env
      checkRevisionBody env "leads" lid
      ml <- liftIO $ patchLead (envConn env) lid ul (Just (userId u))
      case ml of
        Just l -> respondJson env l
        Nothing -> notFound "Lead not found"

  S.delete "/api/leads/:id" $ do
    lid <- S.pathParam "id"
    withWriter env $ \u -> do
      ok <- liftIO $ deleteLead (envConn env) lid (Just (userId u))
      if ok then respondJson env (A.object ["deleted" .= True])
            else notFound "Lead not found"

  S.post "/api/leads/:id/advance" $ do
    lid <- S.pathParam "id"
    withWriter env $ \_ -> do
      res <- liftIO $ advanceStage (envConn env) lid
      case res of
        Right (Just l) -> respondJson env l
        Right Nothing -> notFound "Lead not found"
        Left why -> badRequest why

  S.post "/api/leads/:id/convert" $ do
    lid <- S.pathParam "id"
    withWriter env $ \u -> convertLeadRecord env u lid

  S.post "/api/leads/:id/notes" $ do
    lid <- S.pathParam "id"
    withWriter env $ \_ -> do
      NoteRequest note <- validated env
      ok <- liftIO $ do
        addNote (envConn env) lid note
        pure True
      if ok then respondJson env (A.object ["added" .= True])
            else badRequest "Could not add note"

  S.post "/api/bulk/leads" $
    withWriter env $ \u -> do
      br <- validated env
      when (length (brIds br)>500) $ reject status400 "Select at most 500 leads"
      forM_ (brIds br) $ \lid -> liftIO (getLead (envConn env) lid) >>= \r -> when (r == Nothing) (reject status404 "Lead not found")
      n <- liftIO $ bulkLeads (envConn env) br (userId u)
      respondJson env (A.object ["affected" .= n])

  S.post "/api/import/leads" $
    withWriter env $ \u -> do
      fs <- S.files
      case pickFile fs of
        Nothing -> badRequest "No file provided — attach a CSV as the \"file\" part"
        Just fi -> do
          let bytes = BL.toStrict (fileContent fi)
          if B.length bytes > maxImportBytes
            then badRequest "File too large (max 2 MB)"
            else case TE.decodeUtf8' bytes of
              Left _ -> badRequest "File is not valid UTF-8"
              Right csvText ->
                let rows = parseCsv csvText
                in if length rows > maxImportRows + 1
                     then badRequest ("Too many rows (max "
                                       <> T.pack (show (maxImportRows :: Int))
                                       <> " leads per import)")
                     else do
                       res <- liftIO $
                         importLeads (envConn env) rows (userId u)
                       respondJson env res

  -- ---- tasks ----
  S.get "/api/tasks" $
    withUser env $ \_ -> do
      (limit,offset,_) <- paging
      respondJson env =<< liftIO (listTasksPage (envConn env) limit offset)

  S.post "/api/tasks" $
    withWriter env $ \u -> do
      nt <- validated env
      case (ntLeadId nt,ntClientId nt) of
        (Just lid,Nothing) -> liftIO (getLead (envConn env) lid) >>= \r -> when (r == Nothing) (reject status400 "Choose an accessible lead")
        (Nothing,Just cid) -> liftIO (getClient (envConn env) cid) >>= \r -> when (maybe True (const False) r) (reject status400 "Choose an accessible client")
        _ -> reject status400 "Choose exactly one lead or client"
      t <- liftIO $ insertTask (envConn env) nt (userId u)
      S.status status200 >> respondJson env t

  S.patch "/api/tasks/:id" $ do
    tid <- S.pathParam "id"
    withWriter env $ \_ -> do
      TaskStatusRequest st <- validated env
      checkRevisionBody env "tasks" tid
      ok <- liftIO $ setTaskStatus (envConn env) tid st
      if ok then respondJson env (A.object ["updated" .= True])
            else notFound "Task not found"

  S.delete "/api/tasks/:id" $ do
    tid <- S.pathParam "id"
    withWriter env $ \_ -> do
      ok <- liftIO $ deleteTask (envConn env) tid
      if ok then respondJson env (A.object ["deleted" .= True])
            else notFound "Task not found"

  -- ---- activities ----
  S.get "/api/activities" $
    withUser env $ \_ -> do
      mlead <- qparam "leadId"
      mlimit <- qparam "limit"
      let limit = maybe 20 (max 1 . min 500) (mlimit >>= readMaybeT)
      acts <- liftIO $ case mlead >>= readMaybeT of
        Just lid -> activitiesForLead (envConn env) lid
        Nothing -> listActivities (envConn env) limit
      respondJson env acts

  -- ---- clients ----
  S.get "/api/clients" $
    withUser env $ \_ -> do
      (limit,offset,search) <- paging
      respondJson env =<< liftIO (listClientsPage (envConn env) limit offset search)

  S.post "/api/clients" $
    withWriter env $ \u -> do
      input <- validated env
      let nc = input { ncCaseOfficer = Just (maybe (userId u) id (ncCaseOfficer input)) }
      c <- liftIO $ insertClient (envConn env) nc
      S.status status200 >> respondJson env c

  S.get "/api/clients/:id" $ do
    cid <- S.pathParam "id"
    withUser env $ \_ -> do
      mc <- liftIO $ getClientDetail (envConn env) cid
      case mc of
        Just cd -> respondJson env cd
        Nothing -> notFound "Student not found"

  S.patch "/api/clients/:id" $ do
    cid <- S.pathParam "id"
    withWriter env $ \u -> do
      nc <- validated env
      checkRevisionBody env "clients" cid
      ok <- liftIO $ patchClient (envConn env) cid nc (Just (userId u))
      if ok then respondJson env (A.object ["updated" .= True])
            else notFound "Student not found"

  S.delete "/api/clients/:id" $ do
    cid <- S.pathParam "id"
    withWriter env $ \u -> do
      ok <- liftIO $ deleteClient (envConn env) cid (Just (userId u))
      if ok then respondJson env (A.object ["deleted" .= True])
            else notFound "Student not found"

  S.post "/api/clients/:id/cases" $ do
    cid <- S.pathParam "id"
    withWriter env $ \_ -> do
      ci <- validated env
      forM_ (ciCaseId ci) $ \caseId -> do
        checkRevisionBody env "cases" caseId
        rows <- liftIO $ query (envConn env) "SELECT id FROM cases WHERE id=? AND client_id=?" (caseId,cid) :: S.ActionM [Only Int]
        when (null rows) $ reject status404 "Case not found"
      liftIO $ upsertCase (envConn env) cid ci
      mc <- liftIO $ getClientDetail (envConn env) cid
      case mc of
        Just cd -> respondJson env cd
        Nothing -> notFound "Student not found"

  S.delete "/api/cases/:id" $ do
    caseId <- S.pathParam "id"
    withWriter env $ \_ -> do
      ok <- liftIO $ deleteCase (envConn env) caseId
      if ok then respondJson env (A.object ["deleted" .= True])
            else notFound "Case not found"

  -- ---- documents ----
  -- Uploads are multipart/form-data with a \"file\" part; the owner record
  -- (lead or client) comes from the path.  Responds with the refreshed
  -- detail payload so clients can re-render in one round trip.

  S.post "/api/leads/:id/documents" $ do
    lid <- S.pathParam "id"
    withWriter env $ \u -> do
      ml <- liftIO $ getLead (envConn env) lid
      case ml of
        Nothing -> notFound "Lead not found"
        Just _ -> do
          r <- storeUpload env (Just lid) Nothing (userId u)
          case r of
            Left why -> badRequest why
            Right () -> do
              md <- liftIO $ getLeadDetail (envConn env) lid
              maybe (serverError "Lead vanished") (respondJson env) md

  S.post "/api/clients/:id/documents" $ do
    cid <- S.pathParam "id"
    withWriter env $ \u -> do
      mc <- liftIO $ getClientDetail (envConn env) cid
      case mc of
        Nothing -> notFound "Student not found"
        Just _ -> do
          r <- storeUpload env Nothing (Just cid) (userId u)
          case r of
            Left why -> badRequest why
            Right () -> do
              md <- liftIO $ getClientDetail (envConn env) cid
              maybe (serverError "Client vanished") (respondJson env) md

  S.get "/api/documents/:id/download" $ do
    did <- S.pathParam "id"
    mu <- currentUserWithQueryToken env
    case mu of
      Nothing -> unauthorized "Not authenticated"
      Just _ -> do
        Ops.requireClean env did
        mdoc <- liftIO $ getDocumentContent (envConn env) did
        case mdoc of
          Nothing -> notFound "Document not found"
          Just (fname, _mime, bs) -> do
            let safeName = T.take 200 (T.filter (\c -> c >= ' ' && c /= '\DEL' && c `notElem` ['"','\\','/']) fname)
            S.setHeader "Content-Type" "application/octet-stream"
            S.setHeader "Content-Disposition"
              ("attachment; filename=\""
                <> TL.fromStrict safeName <> "\"")
            S.raw (BL.fromStrict bs)

  S.delete "/api/documents/:id" $ do
    did <- S.pathParam "id"
    withWriter env $ \_ -> do
      versions <- liftIO $ query (envConn env) "SELECT document_id FROM document_versions WHERE document_id=?" (Only (did::Int)) :: S.ActionM [Only Int]
      unless (null versions) $ reject status409 "Versioned files are retained for history. Reject the checklist item or attach a replacement version instead."
      ok <- liftIO $ deleteDocument (envConn env) did
      if ok then respondJson env (A.object ["deleted" .= True])
            else notFound "Document not found"

  -- ---- audit trail (admin) ----
  S.get "/api/audit" $
    withAdmin env $ \_ -> do
      mType <- qparam "entityType"
      mId <- qparam "entityId"
      mLimit <- qparam "limit"
      let limit = maybe 100 (\n -> max 1 (min 500 n)) (mLimit >>= readMaybeT)
      entries <- liftIO $ listAuditEntries (envConn env)
                   (nonEmptyT mType) (mId >>= readMaybeT) limit
      respondJson env entries

  -- ---- stats ----
  S.get "/api/stats" $ withUser env $ \_ -> do
    stats<-liftIO $ getStats (envConn env)
    today<-liftIO $ DailyWork.todaySummary env
    let enriched=case A.toJSON stats of A.Object fields -> A.Object(KM.insert "stToday" today fields); value -> value
    respondJson env enriched

  -- ---- csv export ----
  -- Downloads use the secure session cookie; credentials never appear in URLs.

  S.get "/api/export/leads.csv" $ do
    mu <- currentUserWithQueryToken env
    case mu of
      Nothing -> unauthorized "Not authenticated"
      Just _ -> do
        ls <- liftIO $ listLeads (envConn env)
        csvAttachment "leads.csv" (leadsCsv ls)

  S.get "/api/export/clients.csv" $ do
    mu <- currentUserWithQueryToken env
    case mu of
      Nothing -> unauthorized "Not authenticated"
      Just _ -> do
        cs <- liftIO $ listClients (envConn env)
        csvAttachment "students.csv" (clientsCsv cs)

csvAttachment :: T.Text -> BL.ByteString -> S.ActionM ()
csvAttachment name body = do
  S.setHeader "Content-Type" "text/csv; charset=utf-8"
  S.setHeader "Content-Disposition"
    ("attachment; filename=\"" <> TL.fromStrict name <> "\"")
  S.raw body

readMaybeT :: Read a => T.Text -> Maybe a
readMaybeT s = case reads (T.unpack s) of
  [(v, "")] -> Just v
  _         -> Nothing

validRole :: T.Text -> Bool
validRole r = r `elem` ["admin", "consultant", "viewer"]

-- | Blank query values count as absent.
nonEmptyT :: Maybe T.Text -> Maybe T.Text
nonEmptyT t = case t of
  Just v | not (T.null (T.strip v)) -> Just v
  _ -> Nothing

-- ---------- upload plumbing ----------

maxUploadBytes :: Int
maxUploadBytes = 25 * 1024 * 1024  -- 25 MB

maxImportBytes :: Int
maxImportBytes = 2 * 1024 * 1024   -- 2 MB

maxImportRows :: Int
maxImportRows = 5000

-- | Validates and stores the uploaded file from a multipart body; exactly
-- one of the lead\/client ids must be @Just@.  @Left@ is a client-facing
-- error message.
storeUpload :: Env -> Maybe Int -> Maybe Int -> Int -> S.ActionM (Either T.Text ())
storeUpload env mlead mclient uploaderId = do
  fs <- S.files
  case pickFile fs of
    Nothing -> pure (Left "No file provided")
    Just fi -> do
      let bytes = BL.toStrict (fileContent fi)
      if B.length bytes > maxUploadBytes
        then pure (Left "File too large (max 25 MB)")
        else do
          _ <- liftIO $ insertDocument (envConn env) mlead mclient
                 (sanitizeFilename (TE.decodeUtf8With (\_ _ -> Just '_') (fileName fi)))
                 ("application/octet-stream")
                 bytes
                 (Just uploaderId)
          pure (Right ())

-- | The uploaded part must be named @file@.
pickFile :: [S.File BL.ByteString] -> Maybe (FileInfo BL.ByteString)
pickFile fs = case [fi | ("file", fi) <- fs] of
  (fi:_) -> Just fi
  []     -> Nothing

-- | Strip any client-supplied path components and cap the length.
sanitizeFilename :: T.Text -> T.Text
sanitizeFilename raw =
  let noPath = head' [seg | seg <- T.split (== '/') raw, not (T.null seg)]
      base = lastDef noPath (T.split (== '\\') raw)
  in T.take 255 (if T.null base then "untitled" else base)
  where
    head' (x:_) = x
    head' []    = ""
    lastDef d xs = if null xs then d else last xs

-- Stable server-side pagination, capped to avoid unbounded request work.
paging :: S.ActionM (Int,Int,T.Text)
paging = do
  ml <- qparam "limit"
  mo <- qparam "offset"
  mq <- qparam "q"
  pure (maybe 50 (max 1 . min 200) (ml >>= readMaybeT),maybe 0 (max 0) (mo >>= readMaybeT),maybe "" (T.take 200) mq)

checkRevisionBody :: Env -> T.Text -> Int -> S.ActionM ()
checkRevisionBody env kind rid = do
 bytes <- S.body
 case A.eitherDecode bytes of
  Left _ -> reject status400 "Invalid form values"
  Right value -> checkRevision env kind rid value


convertLeadRecord :: Env -> User -> Int -> S.ActionM ()
convertLeadRecord env u lid = do
  rows <- liftIO $ query (envConn env) "SELECT consultant_id FROM leads WHERE id=? AND deleted_at IS NULL" (Only lid) :: S.ActionM [Only (Maybe Int)]
  case rows of
    [Only assigned] -> do
      mc <- liftIO $ convertToClient (envConn env) lid (maybe (userId u) id assigned)
      case mc of
        Just c -> do
          liftIO $ do
            forM_ ["work_history","document_requests","appointments","notifications","mail_outbox"] $ \table -> void $ execute (envConn env) (Query ("UPDATE "<>table<>" SET client_id=?,lead_id=NULL WHERE lead_id=?")) (clientId c,lid)
          respondJson env c
        Nothing -> notFound "Lead or converted record not found"
    _ -> notFound "Lead not found"
