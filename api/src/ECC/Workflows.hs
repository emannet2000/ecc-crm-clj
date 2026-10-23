{-# LANGUAGE OverloadedStrings #-}
module ECC.Workflows where
import Control.Monad (forM,forM_,unless,void,when)
import Control.Monad.IO.Class (liftIO)
import qualified Data.Aeson as A
import Data.Aeson ((.=))
import qualified Data.ByteString.Lazy as BL
import qualified Data.ByteString as B
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import Data.Time
import Data.Time.Clock.POSIX (getPOSIXTime)
import Network.HTTP.Types hiding (Query)
import qualified Network.Wai as Wai
import qualified Web.Scotty as S
import System.Environment (lookupEnv)
import Text.Read (readMaybe)
import ECC.Auth
import ECC.MFA
import ECC.Store
import ECC.DB (Env(..))
import ECC.Clock (businessDay)
import ECC.Models
import qualified ECC.Access as Access
import ECC.Security
import ECC.WorkflowSupport
import qualified ECC.Portal as Portal
import qualified ECC.Operations as Ops
import qualified ECC.ProfilePhotos as ProfilePhotos
import qualified ECC.Applications as Applications
import qualified ECC.Journey as Journey
import qualified ECC.Integrations as Integrations
import qualified ECC.StudentWorkflows as StudentWorkflows
import qualified ECC.Finance as Finance
import qualified ECC.Money as Money
import qualified ECC.Csv as Csv
import qualified Data.Aeson.KeyMap as KM
import qualified Data.Aeson.Key as K

type Guard = (User -> S.ActionM ()) -> S.ActionM ()

accountGate :: Env -> User -> S.ActionM ()
accountGate env u = do
 req<-S.request
 required<-liftIO $ (==Just "true") <$> lookupEnv "REQUIRE_ADMIN_MFA"
 rows<-liftIO $ query (envConn env) "SELECT mfa_secret IS NOT NULL FROM users WHERE id=?" (Only (userId u)) :: S.ActionM [Only Bool]
 let enabled=rows==[Only True]
     path=Wai.pathInfo req
     security=take 3 path==["api","workspace","security"] || path `elem` [["api","auth","me"],["api","auth","logout"]]
 verified<-case requestToken req of
  Nothing -> pure False
  Just tok -> do
   found<-liftIO $ query (envConn env) "SELECT mfa_verified FROM sessions WHERE token_hash=?" (Only (tokenHash tok)) :: S.ActionM [Only Int]
   pure (found==[Only 1])
 when (not security && ((required && userRole u=="admin" && not enabled) || enabled && not verified)) $ reject status403 "Set up or verify your authenticator in Account security before opening workspace records."

routes :: Env -> Guard -> Guard -> Guard -> S.ScottyM ()
routes env reader writer admin = do
 StudentWorkflows.routes env reader writer
 Finance.routes env reader writer
 ProfilePhotos.routes env reader writer admin
 Applications.routes env reader writer admin
 Ops.routes env reader writer admin
 Portal.routes env writer
 S.get "/api/workspace/reports.csv" $ admin $ \_ -> do
  range<-maybe "" id <$> S.queryParamMaybe "q"
  rows<-liftIO $ reports env range
  let columns=["title","leads","converted","openTasks","overdueTasks","completedCases","averageCaseDays","from","to"]
      val row key=case row of
       A.Object o -> case KM.lookup(K.fromText key)o of
        Just(A.String t)->t
        Just A.Null->""
        Just v->TE.decodeUtf8(BL.toStrict(A.encode v))
        _->""
       _->""
  S.setHeader "Content-Type" "text/csv; charset=utf-8"
  S.setHeader "Content-Disposition" "attachment; filename=management-summary.csv"
  S.raw(Csv.renderCsv(map Csv.cell columns:map(\row ->map(Csv.cell . val row)columns)rows))
 S.get "/api/workspace/calendar.ics" $ reader $ \_ -> calendar env
 S.get "/api/workspace/:section" $ do
  section<-S.pathParam "section"
  (if section `elem` ["merge","reports","invoices","ageing","bottlenecks","trends"] then admin else reader) $ \u -> do
   q<-maybe "" id . lookup "q" <$> S.queryParams
   offset<-max 0 . maybe 0 id . (>>=readMaybe . T.unpack) . lookup "offset" <$> S.queryParams
   rows<-listSection env u section q offset
   options<-if section=="security" then pure [] else liftIO $ optionsFor env q
   extra<-if section=="security" then securityState env u else if section=="notifications" then liftIO(Ops.preferences env u) else pure A.Null
   respondJson env (A.object ["rows".=rows,"options".=options,"security".=extra])
 S.post "/api/workspace/:section/:action" $ do
  section<-S.pathParam "section"
  action<-S.pathParam "action"
  (if section `elem` ["merge","invoices"] || section=="security" && action `elem` ["suspend","resume","revoke-user","reset-mfa","access"] then admin else if section `elem` ["security","search"] then reader else writer) $ \u -> do
   input<-bodyObject
   result<-perform env u section action input
   respondJson env result

optionsFor :: Env -> T.Text -> IO [A.Value]
optionsFor env q = do
 let search="%"<>q<>"%"
 records<-jsonRows env ("SELECT json_object('value','lead:'||id,'label','Lead · '||full_name||' · '||lead_number) FROM leads WHERE id IN ("<>visibleLeads<>") AND (full_name LIKE ? OR phone LIKE ? OR lead_number LIKE ?) UNION ALL SELECT json_object('value','client:'||id,'label','Student · '||full_name||' · '||client_number) FROM clients WHERE id IN ("<>visibleClients<>") AND (full_name LIKE ? OR phone LIKE ? OR client_number LIKE ?) UNION ALL SELECT json_object('value','case:'||c.id,'label','Case · '||cl.full_name||' · '||coalesce(c.service_category,'Case')||' · '||c.id) FROM cases c JOIN clients cl ON cl.id=c.client_id WHERE cl.id IN ("<>visibleClients<>") AND (cl.full_name LIKE ? OR c.service_category LIKE ?) LIMIT 200") (search,search,search,search,search,search,search,search)
 users<-jsonRows env "SELECT json_object('value','staff:'||id,'label',name||' · '||role) FROM users WHERE role<>'viewer' AND suspended=0 ORDER BY name" ()
 requests<-jsonRows env ("SELECT json_object('value','request:'||id,'label','Checklist · '||title) FROM document_requests WHERE (lead_id IN ("<>visibleLeads<>") OR client_id IN ("<>visibleClients<>")) AND title LIKE ? ORDER BY id DESC LIMIT 200") (Only search)
 docs<-jsonRows env ("SELECT json_object('value','document:'||id,'label','File · '||filename) FROM documents WHERE (lead_id IN ("<>visibleLeads<>") OR client_id IN ("<>visibleClients<>")) AND filename LIKE ? ORDER BY id DESC LIMIT 200") (Only search)
 tasks<-jsonRows env ("SELECT json_object('value','task:'||id,'label','Task · '||title) FROM tasks WHERE id IN ("<>visibleTasks<>") AND title LIKE ? ORDER BY id DESC LIMIT 200") (Only search)
 pure (records++users++requests++docs++tasks)

listSection :: Env -> User -> T.Text -> T.Text -> Int -> S.ActionM [A.Value]
listSection env u section q offset
 | section=="integrations" = liftIO $ Integrations.staffRows env u Nothing Nothing
 | section=="search", Just savedId<-T.stripPrefix "@view:" q = savedViewRows env u (A.object ["id".=savedId]) offset
 | Journey.commercialSection section = Journey.commercialRows env u section Nothing Nothing q offset
 | otherwise = liftIO $ case section of
 "tasks" -> jsonRows env ("SELECT json_object('id',t.id,'title',t.title,'description',coalesce(t.description,''),'scheduledAt',replace(substr(coalesce(t.scheduled_at,''),1,16),' ','T'),'dueAt',replace(substr(coalesce(t.due_at,''),1,16),' ','T'),'completedAt',t.completed_at,'overdue',t.status<>'Done' AND ((t.due_at IS NOT NULL AND t.due_at<datetime('now')) OR (t.due_at IS NULL AND t.due_date<date('now',business_offset()))),'dueDate',coalesce(t.due_date,''),'priority',t.priority,'status',t.status,'assignee',coalesce(t.assigned_to_id,''),'assigneeName',coalesce(u.name,'Unassigned'),'owner',CASE WHEN t.client_id IS NOT NULL THEN 'client:'||t.client_id ELSE 'lead:'||t.lead_id END,'recordName',coalesce(cl.full_name,l.full_name),'recurrenceDays',coalesce(t.recurrence_days,''),'revision',v.revision) FROM tasks t LEFT JOIN users u ON u.id=t.assigned_to_id LEFT JOIN clients cl ON cl.id=t.client_id LEFT JOIN leads l ON l.id=t.lead_id JOIN record_versions v ON v.kind='tasks' AND v.record_id=t.id WHERE t.id IN ("<>visibleTasks<>") AND (t.title LIKE ? OR coalesce(cl.full_name,l.full_name) LIKE ?) ORDER BY t.due_date NULLS LAST,t.id DESC LIMIT 50 OFFSET ?") (search,search,offset)
 "history" -> jsonRows env ("SELECT json_object('id',h.id,'title',coalesce(c.full_name,l.full_name),'kind',h.kind,'note',h.note,'actor',coalesce(u.name,'System'),'date',h.created_at,'case',h.case_id) FROM work_history h LEFT JOIN clients c ON c.id=h.client_id LEFT JOIN leads l ON l.id=h.lead_id LEFT JOIN users u ON u.id=h.actor_id WHERE (h.lead_id IN ("<>visibleLeads<>") OR h.client_id IN ("<>visibleClients<>")) AND (h.task_id IS NULL OR h.task_id IN ("<>visibleTasks<>")) AND (h.note LIKE ? OR coalesce(c.full_name,l.full_name) LIKE ?) ORDER BY h.id DESC LIMIT 50 OFFSET ?") (search,search,offset)
 "documents" -> Ops.documentRows env Nothing q offset
 "reminders" -> jsonRows env ("SELECT json_object('id',r.id,'task',t.id,'title',t.title,'daysBefore',r.days_before,'escalateAfter',r.escalate_after,'enabled',CASE WHEN r.enabled=1 THEN 'true' ELSE 'false' END,'revision',r.revision) FROM reminder_rules r JOIN tasks t ON t.id=r.task_id WHERE t.id IN ("<>visibleTasks<>") AND t.title LIKE ? ORDER BY r.id DESC LIMIT 50 OFFSET ?") (search,offset)
 "search" -> searchRows env u q offset
 "reports" -> reports env q
 "mail" -> Ops.mailRows env u q offset
 "notifications" -> Ops.notificationRows env u offset
 "ageing" -> Ops.reportRows env "ageing" q 0 True
 "bottlenecks" -> Ops.reportRows env "bottlenecks" q 0 True
 "trends" -> Ops.reportRows env "trends" q 0 True
 "merge" -> pure []
 "security" -> jsonRows env "SELECT json_object('id',substr(token_hash,1,16),'title','Browser/API session','created',created_at,'expires',expires_at,'verified',mfa_verified) FROM sessions WHERE user_id=? AND expires_at>datetime('now') ORDER BY created_at DESC LIMIT 50 OFFSET ?" (userId u,offset)
 "appointments" -> jsonRows env ("SELECT json_object('id',id,'title',title,'owner',CASE WHEN client_id IS NOT NULL THEN 'client:'||client_id ELSE 'lead:'||lead_id END,'assignee',owner_id,'startsAt',replace(substr(starts_at,1,16),' ','T'),'endsAt',replace(substr(ends_at,1,16),' ','T'),'location',location,'meetingUrl',meeting_url,'meetingId',meeting_id,'passcode',passcode,'task',task_id,'clientVisible',client_visible=1,'status',status,'revision',revision) FROM appointments WHERE (lead_id IN ("<>visibleLeads<>") OR client_id IN ("<>visibleClients<>")) AND title LIKE ? ORDER BY starts_at DESC,id DESC LIMIT 50 OFFSET ?") (search,offset)
 "invoices" -> jsonRows env "SELECT json_object('id',i.id,'title','INV-'||printf('%06d',i.id)||' · '||c.full_name,'owner','client:'||i.client_id,'description',i.description,'currency',i.currency,'amount',printf('%.2f',i.amount_minor/100.0),'paid',printf('%.2f',i.paid_minor/100.0),'balance',printf('%.2f',i.balance_minor/100.0),'dueDate',i.due_date,'status',i.status,'revision',i.revision) FROM invoice_balances i JOIN clients c ON c.id=i.client_id WHERE c.deleted_at IS NULL AND (c.full_name LIKE ? OR i.description LIKE ?) ORDER BY i.id DESC LIMIT 50 OFFSET ?" (search,search,offset)
 "portal" -> jsonRows env ("SELECT json_object('id',p.id,'title','Portal · '||c.full_name,'expires',p.expires_at,'status',CASE WHEN p.revoked=1 THEN 'Revoked' WHEN p.expires_at<datetime('now') THEN 'Expired' ELSE 'Active' END,'owner','client:'||p.client_id) FROM portal_links p JOIN clients c ON c.id=p.client_id WHERE c.id IN ("<>visibleClients<>") ORDER BY p.id DESC LIMIT 50 OFFSET ?") (Only offset)
 "communication" -> pure []
 _ -> pure []
 where search="%"<>q<>"%"

searchRows :: Env -> User -> T.Text -> Int -> IO [A.Value]
searchRows env _ q offset = do
 let term="%"<>q<>"%"
 jsonRows env ("SELECT json_object('id',id,'title',full_name,'kind','Lead','path','/leads/'||id,'number',lead_number,'email',email,'phone',phone) FROM leads WHERE id IN ("<>visibleLeads<>") AND (full_name LIKE ? OR email LIKE ? OR phone LIKE ? OR lead_number LIKE ?) UNION ALL SELECT json_object('id',id,'title',full_name,'kind','Student','path','/clients/'||id,'number',client_number,'email',email,'phone',phone) FROM clients WHERE id IN ("<>visibleClients<>") AND (full_name LIKE ? OR email LIKE ? OR phone LIKE ? OR client_number LIKE ?) UNION ALL SELECT json_object('id',id,'title',title,'kind','Task','path',CASE WHEN client_id IS NOT NULL THEN '/clients/'||client_id ELSE '/leads/'||lead_id END) FROM tasks WHERE id IN ("<>visibleTasks<>") AND title LIKE ? UNION ALL SELECT json_object('id',id,'title',coalesce(service_category,'Case')||' · '||stage,'kind','Case','path','/clients/'||client_id) FROM cases WHERE client_id IN ("<>visibleClients<>") AND (service_category LIKE ? OR destination LIKE ? OR stage LIKE ?) LIMIT 50 OFFSET ?")
  (term,term,term,term,term,term,term,term,term,term,term,term,offset)

reports :: Env -> T.Text -> IO [A.Value]
reports env range = do
 -- Date ranges are bound; invalid or missing ranges use the last 30 days.
 today<-businessDay
 let parts=T.splitOn "," range
     parsed t=parseTimeM True defaultTimeLocale "%F" (T.unpack t) :: Maybe Day
     (start,end)=case parts of [a,b] | Just x<-parsed a,Just y<-parsed b,x<=y -> (x,y); _ -> (addDays (-30) today,today)
 jsonRows env "SELECT json_object('title',u.name,'leads',(SELECT count(*) FROM leads l WHERE l.consultant_id=u.id AND l.merged_into IS NULL AND date(l.created_at,business_offset()) BETWEEN ? AND ?),'converted',(SELECT count(*) FROM leads l WHERE l.consultant_id=u.id AND l.merged_into IS NULL AND l.converted_client_id IS NOT NULL AND date(l.created_at,business_offset()) BETWEEN ? AND ?),'openTasks',(SELECT count(*) FROM tasks t WHERE t.assigned_to_id=u.id AND t.status<>'Done'),'overdueTasks',(SELECT count(*) FROM tasks t WHERE t.assigned_to_id=u.id AND t.status<>'Done' AND t.due_date<date('now',business_offset())),'completedCases',(SELECT count(*) FROM cases c JOIN clients cl ON cl.id=c.client_id WHERE cl.case_officer_id=u.id AND date((SELECT min(h.created_at) FROM work_history h WHERE h.case_id=c.id AND h.kind='case_completed')) BETWEEN ? AND ?),'averageCaseDays',(SELECT round(avg(julianday(h.created_at)-julianday(c.created_at)),1) FROM cases c JOIN work_history h ON h.case_id=c.id AND h.kind='case_completed' AND h.id=(SELECT min(h2.id) FROM work_history h2 WHERE h2.case_id=c.id AND h2.kind='case_completed') JOIN clients cl ON cl.id=c.client_id WHERE cl.case_officer_id=u.id AND date(h.created_at,business_offset()) BETWEEN ? AND ?),'from',?,'to',?) FROM users u WHERE u.role<>'viewer' ORDER BY u.name" (start,end,start,end,start,end,start,end,start,end)

perform :: Env -> User -> T.Text -> T.Text -> A.Value -> S.ActionM A.Value
perform env u section action input = case (section,action) of
 ("integrations","retry") -> Integrations.retry env u input
 _ | action `elem` ["zoom","calendar","checkout","sign"] -> Integrations.request env u section action input
 ("tasks","create") -> Ops.createTask env u input
 ("tasks","save") -> saveTask env u input
 ("history","add") -> do
  (ml,mc,cs)<-owner env u input
  note<-bounded "note" 20000 input
  liftIO $ recordHistory env u ml mc cs "note" note
  pure saved
 ("documents","save") -> saveChecklist env u input
 ("documents","attach") -> attachVersion env u input
 ("reminders","save") -> saveReminder env u input
 ("merge","preview") -> mergeRecords env u False input
 ("merge","confirm") -> mergeRecords env u True input
 ("search","save") -> do
  name<-bounded "name" 100 input
  entity<-choice "entity" ["leads","clients","tasks","cases"] input
  liftIO $ void $ execute (envConn env) "INSERT INTO saved_views(user_id,name,entity,query,overdue,mine) VALUES (?,?,?,?,?,?)" (userId u,name,entity,field "query" input,field "overdue" input=="true",field "mine" input=="true")
  pure saved
 ("search","views") -> A.toJSON <$> liftIO (jsonRows env "SELECT json_object('id',id,'title',name,'entity',entity,'query',query,'overdue',overdue,'mine',mine,'revision',revision) FROM saved_views WHERE user_id=? ORDER BY name" (Only (userId u)))
 ("search","apply") -> applyView env u input
 ("search","delete") -> do
  vid<-intField "id" input
  liftIO $ void $ execute (envConn env) "DELETE FROM saved_views WHERE id=? AND user_id=?" (vid,userId u)
  pure saved
 ("appointments","save") -> saveAppointment env u input
 ("invoices","save") -> saveInvoice env u input
 ("invoices","send") -> sendInvoice env u input
 ("security",_) -> securityAction env u action input
 ("portal",_) -> Portal.manage env u action input
 ("communication","send") -> sendCommunication env u input
 _ | Journey.commercialSection section -> Journey.commercialAction env u section action input
 _ -> reject status404 "Action not found"
 where saved=A.object ["message".=("Saved successfully"::T.Text)]

saveTask :: Env -> User -> A.Value -> S.ActionM A.Value
saveTask env u input = do
 tid<-intField "id" input
 rows<-liftIO $ query (envConn env) ("SELECT lead_id,client_id FROM tasks WHERE id=? AND id IN ("<>visibleTasks<>")") (Only tid) :: S.ActionM [(Maybe Int,Maybe Int)]
 when (null rows) $ reject status404 "Task not found"
 checkRevision env "tasks" tid input
 title<-bounded "title" 255 input
 dueDate<-dateField "dueDate" False input
 (scheduled,dueTime)<-Journey.taskTimes input
 let due=maybe dueDate (Just . T.take 10) dueTime
 priority<-choice "priority" ["Low","Medium","High","Urgent"] input
 status<-choice "status" ["Pending","In Progress","Done"] input
 assigned<-intField "assignee" input
 staff env assigned
 forM_ rows $ \(ml,mc) -> checkAssignee env assigned ml mc
 let recurrence=number "recurrenceDays" input
 when (maybe False (\n -> n<1 || n>366) recurrence || recurrence/=Nothing && due==Nothing) $ reject status400 "Recurring tasks need a deadline and a repeat interval of 1–366 days"
 liftIO $ do
  void $ execute (envConn env) "UPDATE tasks SET title=?,description=?,due_date=?,priority=?,status=?,assigned_to_id=?,recurrence_days=?,scheduled_at=?,due_at=? WHERE id=?" (title,field "description" input,due,priority,status,assigned,recurrence,scheduled,dueTime,tid)
  forM_ rows $ \(ml,mc) -> void $ execute (envConn env) "INSERT INTO work_history(lead_id,client_id,task_id,actor_id,kind,note) VALUES (?,?,?,?,'task.updated',?)" (ml,mc,tid,userId u,"Task updated: "<>title)
 pure (A.object ["message".=("Task saved"::T.Text)])

saveChecklist :: Env -> User -> A.Value -> S.ActionM A.Value
saveChecklist env u input = do
 (ml,mc,cs)<-owner env u input
 title<-bounded "title" 255 input
 status<-choice "status" ["Missing","Received","Approved","Rejected"] input
 expiry<-dateField "expiresOn" False input
 let rid=number "id" input
 forM_ rid $ \i -> do
  records<-liftIO $ query (envConn env) "SELECT lead_id,client_id,revision FROM document_requests WHERE id=?" (Only i) :: S.ActionM [(Maybe Int,Maybe Int,Int)]
  case records of
   [(oldL,oldC,rev)] -> do
    checkOwner env u oldL oldC
    checkOwnRevision rev input
    when(oldL/=ml || oldC/=mc) $ reject status400 "A checklist item stays with its original record. Create a new item for another record."
   _ -> reject status404 "Checklist item not found"
  when (status `elem` ["Received","Approved"]) $ do
   files<-liftIO $ query (envConn env) "SELECT document_id FROM document_versions WHERE request_id=?" (Only i) :: S.ActionM [Only Int]
   when (null files) $ reject status400 "Attach a file version before marking it received or approved"
   when (status=="Approved") $ do
    latest<-liftIO $ query (envConn env) "SELECT document_id FROM document_versions WHERE request_id=? ORDER BY version DESC LIMIT 1" (Only i) :: S.ActionM [Only Int]
    forM_ latest $ \(Only did) -> Ops.requireClean env did
 when (rid==Nothing && status/="Missing") $ reject status400 "New checklist items start as Missing"
 when (status=="Rejected" && T.null (field "reviewNote" input)) $ reject status400 "Explain why the document was rejected"
 liftIO $ do
  case rid of
   Nothing -> void $ execute (envConn env) "INSERT INTO document_requests(lead_id,client_id,case_id,title,required,expires_on) VALUES (?,?,?,?,?,?)" (ml,mc,cs,title,field "required" input/="false",expiry)
   Just i -> void $ execute (envConn env) "UPDATE document_requests SET lead_id=?,client_id=?,case_id=?,title=?,required=?,status=?,expires_on=?,review_note=?,reviewed_by=? WHERE id=?" (ml,mc,cs,title,field "required" input/="false",status,expiry,field "reviewNote" input,userId u,i)
  recordHistory env u ml mc cs "document_review" (title<>" · "<>status)
 pure (A.object ["message".=("Checklist saved"::T.Text)])

selectedId :: T.Text -> T.Text -> A.Value -> S.ActionM Int
selectedId key prefix input = let raw=T.replace (prefix<>":") "" (field key input) in maybe (reject status400 ("Choose a "<>key)) pure (readMaybe (T.unpack raw))
attachVersion :: Env -> User -> A.Value -> S.ActionM A.Value
attachVersion env u input = do
 rid<-selectedId "request" "request" input
 did<-selectedId "document" "document" input
 records<-liftIO $ query (envConn env) "SELECT lead_id,client_id,revision FROM document_requests WHERE id=?" (Only rid) :: S.ActionM [(Maybe Int,Maybe Int,Int)]
 case records of
  [(ml,mc,rev)] -> do
   checkOwner env u ml mc
   checkOwnRevision rev input
   docs<-liftIO $ query (envConn env) "SELECT lead_id,client_id FROM documents WHERE id=?" (Only did) :: S.ActionM [(Maybe Int,Maybe Int)]
   unless (docs==[(ml,mc)]) $ reject status400 "The file must belong to the same record as the checklist item"
   liftIO $ do
    void $ execute (envConn env) "INSERT INTO document_versions(request_id,document_id,version) SELECT ?,?,coalesce(max(version),0)+1 FROM document_versions WHERE request_id=?" (rid,did,rid)
    void $ execute (envConn env) "UPDATE document_requests SET status='Received',reviewed_by=NULL,review_note=NULL WHERE id=?" (Only rid)
   pure (A.object ["message".=("New version attached; review is required"::T.Text)])
  _ -> reject status404 "Checklist item not found"

saveReminder :: Env -> User -> A.Value -> S.ActionM A.Value
saveReminder env _ input = do
 tid<-intField "task" input
 allowed<-liftIO $ query (envConn env) ("SELECT id FROM tasks WHERE id=? AND id IN ("<>visibleTasks<>")") (Only tid) :: S.ActionM [Only Int]
 when (null allowed) $ reject status404 "Task not found"
 before<-intField "daysBefore" input
 after<-intField "escalateAfter" input
 when (before<0 || before>365 || after<1 || after>365) $ reject status400 "Choose reminder days between 0–365 and escalation days between 1–365"
 old<-liftIO $ query (envConn env) "SELECT revision FROM reminder_rules WHERE task_id=?" (Only tid) :: S.ActionM [Only Int]
 forM_ old $ \(Only rev) -> checkOwnRevision rev input
 liftIO $ void $ execute (envConn env) "INSERT INTO reminder_rules(task_id,days_before,escalate_after,enabled) VALUES (?,?,?,?) ON CONFLICT(task_id) DO UPDATE SET days_before=excluded.days_before,escalate_after=excluded.escalate_after,enabled=excluded.enabled,revision=reminder_rules.revision+1" (tid,before,after,field "enabled" input/="false")
 pure (A.object ["message".=("Email reminder and overdue escalation saved"::T.Text)])

applyView :: Env -> User -> A.Value -> S.ActionM A.Value
applyView env u input = do
 rows<-savedViewRows env u input 0
 pure (A.object ["results".=rows,"message".=("Saved view results"::T.Text)])

savedViewRows :: Env -> User -> A.Value -> Int -> S.ActionM [A.Value]
savedViewRows env u input offset = do
 vid<-intField "id" input
 rows<-liftIO $ query (envConn env) "SELECT entity,query,overdue,mine FROM saved_views WHERE id=? AND user_id=?" (vid,userId u) :: S.ActionM [(T.Text,T.Text,Bool,Bool)]
 case rows of
  [(entity,q,overdue,mine)] -> do
   let term="%"<>q<>"%"
   result<-liftIO $ case entity of
    "tasks" -> jsonRows env ("SELECT json_object('id',t.id,'title',t.title,'kind','Task','path',CASE WHEN client_id IS NOT NULL THEN '/clients/'||client_id ELSE '/leads/'||lead_id END) FROM tasks t WHERE id IN ("<>visibleTasks<>") AND title LIKE ? AND (NOT ? OR assigned_to_id=?) AND (NOT ? OR status<>'Done' AND due_date<date('now',business_offset())) ORDER BY due_date,id LIMIT 50 OFFSET ?") (term,mine,userId u,overdue,offset)
    "cases" -> jsonRows env ("SELECT json_object('id',c.id,'title',coalesce(c.service_category,'Case')||' · '||cl.full_name,'kind','Case','path','/clients/'||cl.id) FROM cases c JOIN clients cl ON cl.id=c.client_id WHERE cl.id IN ("<>visibleClients<>") AND (cl.full_name LIKE ? OR c.service_category LIKE ?) AND (NOT ? OR cl.case_officer_id=?) AND (NOT ? OR c.next_deadline<date('now',business_offset()) AND c.stage NOT IN ('Approved','Rejected','Completed')) ORDER BY c.next_deadline,c.id LIMIT 50 OFFSET ?") (term,term,mine,userId u,overdue,offset)
    "clients" -> jsonRows env ("SELECT json_object('id',id,'title',full_name,'kind','Student','path','/clients/'||id) FROM clients WHERE id IN ("<>visibleClients<>") AND (full_name LIKE ? OR phone LIKE ?) AND (NOT ? OR case_officer_id=?) AND (NOT ? OR EXISTS(SELECT 1 FROM cases c WHERE c.client_id=clients.id AND c.next_deadline<date('now',business_offset()) AND c.stage NOT IN ('Approved','Rejected','Completed'))) ORDER BY id DESC LIMIT 50 OFFSET ?") (term,term,mine,userId u,overdue,offset)
    _ -> jsonRows env ("SELECT json_object('id',id,'title',full_name,'kind','Lead','path','/leads/'||id) FROM leads WHERE id IN ("<>visibleLeads<>") AND (full_name LIKE ? OR phone LIKE ? OR email LIKE ?) AND (NOT ? OR consultant_id=?) AND (NOT ? OR next_followup<date('now',business_offset())) ORDER BY id DESC LIMIT 50 OFFSET ?") (term,term,term,mine,userId u,overdue,offset)
   pure result
  _ -> reject status404 "Saved view not found"

mergeRecords :: Env -> User -> Bool -> A.Value -> S.ActionM A.Value
mergeRecords env u commit input = do
 kind<-choice "entity" ["leads","clients"] input
 source<-intField "source" input
 target<-intField "target" input
 when (source==target) $ reject status400 "Choose two different records"
 let singular=if kind=="leads" then "lead" else "client"
 forM_ [source,target] $ \rid -> liftIO (canAccess env u singular rid) >>= \ok -> unless ok (reject status404 "Choose two active records")
 when (envAssignedOnly env) $ do
  let officer=if kind=="leads" then "consultant_id" else "case_officer_id"
  owners<-liftIO $ query (envConn env) (Query ("SELECT "<>officer<>" FROM "<>kind<>" WHERE id IN (?,?)")) (source,target) :: S.ActionM [Only (Maybe Int)]
  when (length owners/=2 || head owners/=last owners) $ reject status409 "Assign both records to the same staff member before merging in assigned-only mode"
 sourceRev<-liftIO $ revision env kind source
 targetRev<-liftIO $ revision env kind target
 counts<-liftIO $ if kind=="leads" then
  jsonRows env "SELECT json_object('documents',(SELECT count(*) FROM documents WHERE lead_id=?),'tasks',(SELECT count(*) FROM tasks WHERE lead_id=?),'notes',(SELECT count(*) FROM work_history WHERE lead_id=?),'activities',(SELECT count(*) FROM activities WHERE lead_id=?))" (source,source,source,source)
  else jsonRows env "SELECT json_object('documents',(SELECT count(*) FROM documents WHERE client_id=?),'tasks',(SELECT count(*) FROM tasks WHERE client_id=?),'cases',(SELECT count(*) FROM cases WHERE client_id=?),'invoices',(SELECT count(*) FROM invoices WHERE client_id=?))" (source,source,source,source)
 if not commit then pure (A.object ["sourceRevision".=sourceRev,"targetRevision".=targetRev,"counts".=counts,"message".=("Preview only. The source will be archived; its children move to the surviving record. Source field values remain in the archived source and audit history."::T.Text)]) else do
  unless (number "sourceRevision" input==Just sourceRev && number "targetRevision" input==Just targetRev && field "confirmation" input=="MERGE") $ reject status409 "Preview the current records and type MERGE before confirming"
  previous<-liftIO $ query (envConn env) "SELECT id FROM merge_log WHERE kind=? AND source_id=?" (kind,source) :: S.ActionM [Only Int]
  unless (null previous) $ reject status409 "This source was already merged"
  liftIO $ do
   if kind=="leads" then do
    forM_ ["documents","tasks","activities","work_history","document_requests","appointments","notifications","mail_outbox"] $ \table -> void $ execute (envConn env) (Query ("UPDATE "<>table<>" SET lead_id=? WHERE lead_id=?")) (target,source)
    void $ execute (envConn env) "UPDATE leads SET deleted_at=datetime('now'),merged_into=? WHERE id=?" (target,source)
    recordHistory env u (Just target) Nothing Nothing "merged" ("Merged lead "<>T.pack(show source)<>" into this record; original fields remain in the archived source.")
   else do
    -- Existing portal grants must not expand to the survivor's data after merging.
    void $ execute (envConn env) "DELETE FROM portal_sessions WHERE link_id IN (SELECT id FROM portal_links WHERE client_id=?)" (Only source)
    void $ execute (envConn env) "UPDATE portal_links SET revoked=1 WHERE client_id=?" (Only source)
    forM_ ["cases","documents","tasks","work_history","document_requests","appointments","invoices","commercial_documents","payment_instructions","integration_jobs","integration_links","notifications","mail_outbox"] $ \table -> void $ execute (envConn env) (Query ("UPDATE "<>table<>" SET client_id=? WHERE client_id=?")) (target,source)
    void $ execute (envConn env) "UPDATE leads SET converted_client_id=? WHERE converted_client_id=?" (target,source)
    void $ execute (envConn env) "UPDATE client_photos SET client_id=? WHERE client_id=? AND NOT EXISTS (SELECT 1 FROM client_photos WHERE client_id=?)" (target,source,target)
    void $ execute (envConn env) "UPDATE clients SET deleted_at=datetime('now'),merged_into=? WHERE id=?" (target,source)
    recordHistory env u Nothing (Just target) Nothing "merged" ("Merged client "<>T.pack(show source)<>"; source portal links were revoked.")
   void $ execute (envConn env) "INSERT INTO merge_log(kind,source_id,target_id,actor_id) VALUES (?,?,?,?)" (kind,source,target,userId u)
  pure (A.object ["message".=("Records merged. The archived source cannot be restored independently."::T.Text)])

saveAppointment :: Env -> User -> A.Value -> S.ActionM A.Value
saveAppointment env u input = do
 (ml,mc,cs)<-owner env u input
 title<-bounded "title" 255 input
 assigned<-intField "assignee" input
 staff env assigned
 checkAssignee env assigned ml mc
 let parse key=case parseTimeM True defaultTimeLocale "%FT%R" (T.unpack (field key input)) :: Maybe UTCTime of
       Nothing -> reject status400 (key<>" must be a UTC date and time")
       Just time -> pure time
 start<-parse "startsAt"
 end<-parse "endsAt"
 when (end<=start || diffUTCTime end start>86400) $ reject status400 "The appointment must end after it starts, within 24 hours"
 status<-choice "status" ["Scheduled","Completed","Cancelled"] input
 let meetingUrl=field "meetingUrl" input
     meetingId=field "meetingId" input
     passcode=field "passcode" input
     visible=field "clientVisible" input=="true"
     task=number "task" input
 when (not(T.null meetingUrl) && not ("https://" `T.isPrefixOf` meetingUrl) || T.length meetingUrl>2000 || T.length meetingId>100 || T.length passcode>100) $ reject status400 "Use an HTTPS meeting URL and meeting credentials up to 100 characters"
 forM_ task $ \tid -> do
  related<-liftIO $ query (envConn env) "SELECT id FROM tasks WHERE id=? AND lead_id IS ? AND client_id IS ? AND (? IS NULL OR case_id=?)" (tid,ml,mc,cs,cs) :: S.ActionM [Only Int]
  when(null related) $ reject status400 "Choose a task in this application"
 when(visible && mc==Nothing) $ reject status400 "Client-visible meetings require a client"

 let rid=number "id" input
 forM_ rid $ \i -> do
  old<-liftIO $ query (envConn env) "SELECT lead_id,client_id,revision FROM appointments WHERE id=?" (Only i) :: S.ActionM [(Maybe Int,Maybe Int,Int)]
  case old of [(l,c,r)] -> checkOwner env u l c >> checkOwnRevision r input; _ -> reject status404 "Appointment not found"
 collision<-liftIO $ query (envConn env) "SELECT id FROM appointments WHERE owner_id=? AND status='Scheduled' AND starts_at<? AND ends_at>? AND id<>coalesce(?,0)" (assigned,end,start,rid) :: S.ActionM [Only Int]
 when (status=="Scheduled" && not (null collision)) $ reject status409 "This staff member already has an overlapping appointment"
 liftIO $ do
  meeting<-case rid of
   Nothing -> do
    [Only i]<-query (envConn env) "INSERT INTO appointments(lead_id,client_id,owner_id,title,starts_at,ends_at,location,status,case_id,task_id,meeting_url,meeting_id,passcode,client_visible) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?) RETURNING id" (ml,mc,assigned,title,start,end,field "location" input,status,cs,task,meetingUrl,meetingId,passcode,visible)
    pure (i::Int)
   Just i -> do
    void $ execute (envConn env) "UPDATE appointments SET lead_id=?,client_id=?,owner_id=?,title=?,starts_at=?,ends_at=?,location=?,status=?,case_id=?,task_id=?,meeting_url=?,meeting_id=?,passcode=?,client_visible=?,revision=revision+1 WHERE id=?" (ml,mc,assigned,title,start,end,field "location" input,status,cs,task,meetingUrl,meetingId,passcode,visible,i)
    pure i
  void $ execute (envConn env) "INSERT INTO work_history(lead_id,client_id,case_id,meeting_id,actor_id,kind,note) VALUES (?,?,?,?,?,?,?)" (ml,mc,cs,meeting,userId u,if rid==Nothing then "meeting.scheduled"::T.Text else "meeting.updated",title<>" · "<>status<>" · "<>T.pack(show start)<>" to "<>T.pack(show end))
 pure (A.object ["message".=("Appointment saved. Times are UTC."::T.Text)])

amountMinor :: T.Text -> Maybe Int
amountMinor = Money.amountMinor

saveInvoice :: Env -> User -> A.Value -> S.ActionM A.Value
saveInvoice env u input = do
 (_,mc,cs)<-owner env u input
 cid<-maybe (reject status400 "Choose a client") pure mc
 description<-bounded "description" 1000 input
 currency<-choice "currency" ["PHP","USD","EUR","GBP","AUD","CAD","NZD"] input
 amount<-maybe (reject status400 "Enter a positive amount with at most two decimal places") pure (amountMinor (field "amount" input))
 when (amount>100000000000) $ reject status400 "Amount exceeds the supported limit"
 due<-dateField "dueDate" True input
 status<-choice "status" ["Draft","Issued","Paid","Void"] input
 let rid=number "id" input
 forM_ rid $ \i -> do
  old<-liftIO $ query (envConn env) "SELECT client_id,description,currency,amount_minor,status,revision,case_id FROM invoices WHERE id=?" (Only i) :: S.ActionM [(Int,T.Text,T.Text,Int,T.Text,Int,Maybe Int)]
  case old of
   [(oldC,oldD,oldCurrency,oldA,oldStatus,rev,oldCase)] -> do
    checkOwnRevision rev input
    when (cs/=Nothing && oldCase/=cs) $ reject status409 "This invoice belongs to another application"
    when (status=="Paid" && oldStatus/="Paid") $ reject status400 "Record payments in Payments instead of manually marking an invoice Paid"
    when (status=="Void") $ do
     [Only paid] <- liftIO $ query (envConn env) "SELECT paid_minor FROM invoice_balances WHERE id=?" (Only i) :: S.ActionM [Only Int]
     when (paid/=0) $ reject status409 "Reverse all payments before voiding this invoice"
    when (oldStatus/="Draft" && (oldC/=cid || oldD/=description || oldCurrency/=currency || oldA/=amount)) $ reject status409 "Issued invoice amounts and client details are locked. Void this invoice and create a corrected one."
    when (oldStatus `elem` ["Paid","Void"] && status/=oldStatus || oldStatus=="Issued" && status=="Draft") $ reject status400 "This invoice status cannot be reversed"
   _ -> reject status404 "Invoice not found"
 when (rid==Nothing && status/="Draft") $ reject status400 "New invoices start as Draft"
 liftIO $ do
  case rid of
   Nothing -> void $ execute (envConn env) "INSERT INTO invoices(client_id,description,currency,amount_minor,due_date,case_id) VALUES (?,?,?,?,?,?)" (cid,description,currency,amount,due,cs)
   Just i -> void $ execute (envConn env) "UPDATE invoices SET client_id=?,description=?,currency=?,amount_minor=?,due_date=?,status=?,paid_at=CASE WHEN ?='Paid' THEN coalesce(paid_at,datetime('now')) ELSE paid_at END,revision=revision+1 WHERE id=?" (cid,description,currency,amount,due,status,status,i)
  recordHistory env u Nothing (Just cid) cs "invoice" (description<>" · "<>status)
 pure (A.object ["message".=("Invoice saved. Record receipts in Payments; balances and Paid status update automatically."::T.Text)])

sendInvoice :: Env -> User -> A.Value -> S.ActionM A.Value
sendInvoice env u input = do
 rid<-intField "id" input
 rateLimitAccount env "outgoing" (T.pack(show(userId u)))
 rows<-liftIO $ query (envConn env) "SELECT c.email,i.description,i.currency,i.amount_minor,i.due_date,i.status FROM invoices i JOIN clients c ON c.id=i.client_id WHERE i.id=? AND c.deleted_at IS NULL" (Only rid) :: S.ActionM [(Maybe T.Text,T.Text,T.Text,Int,T.Text,T.Text)]
 case rows of
  [(Just email,description,currency,amount,due,status)] | status `elem` ["Issued","Paid"] -> do
   [(paid,balance)] <- liftIO $ query (envConn env) "SELECT paid_minor,balance_minor FROM invoice_balances WHERE id=?" (Only rid) :: S.ActionM [(Int,Int)]
   let money n=T.pack(show(n `div` 100))<>"."<>T.justifyRight 2 '0' (T.pack(show(n `mod` 100)))
   liftIO $ void $ execute (envConn env) "INSERT INTO mail_outbox(recipient,subject,body,actor_id) VALUES (?,?,?,?)" (email,"Invoice INV-"<>T.pack(show rid),description<>"\nAmount: "<>currency<>" "<>T.pack(show(amount `div`100))<>"."<>T.justifyRight 2 '0' (T.pack(show(amount `mod`100)))<>"\nPaid: "<>currency<>" "<>money paid<>"\nOutstanding balance: "<>currency<>" "<>money balance<>"\nDue: "<>due<>"\nStatus: "<>status,userId u)
   pure (A.object ["message".=("Invoice email queued"::T.Text)])
  _ -> reject status400 "Issue the invoice and ensure the client has an email address before sending"

securityState :: Env -> User -> S.ActionM A.Value
securityState env u = do
 [Only enabled]<-liftIO $ query (envConn env) "SELECT mfa_secret IS NOT NULL FROM users WHERE id=?" (Only (userId u)) :: S.ActionM [Only Bool]
 users<-if userRole u=="admin" then liftIO (Access.teamAccess env) else pure []
 pure (A.object ["enabled".=enabled,"users".=users])

provePassword :: Env -> User -> A.Value -> S.ActionM ()
provePassword env u input = do
 pw<-needed "password" input
 rows<-liftIO $ query (envConn env) "SELECT password_hash FROM users WHERE id=?" (Only(userId u)) :: S.ActionM [Only T.Text]
 unless (case rows of [Only hash] -> checkPassword (TE.encodeUtf8 pw) (TE.encodeUtf8 hash); _ -> False) $ reject status403 "Current password is incorrect"
securityAction :: Env -> User -> T.Text -> A.Value -> S.ActionM A.Value
securityAction env u action input = do
 rateLimitAccount env "security" (T.pack(show(userId u)))
 case action of
  "access" -> provePassword env u input >> Access.saveAccess env u input
  "setup" -> do
   provePassword env u input
   [Only enabled]<-liftIO $ query (envConn env) "SELECT mfa_secret IS NOT NULL FROM users WHERE id=?" (Only(userId u)) :: S.ActionM [Only Bool]
   when enabled $ reject status409 "MFA is already enabled"
   secret<-liftIO newSecret
   liftIO $ void $ execute (envConn env) "UPDATE users SET mfa_pending=? WHERE id=?" (secret,userId u)
   pure (A.object ["secret".=secret,"uri".=("otpauth://totp/ECC:"<>TE.decodeUtf8(urlEncode True(TE.encodeUtf8(userEmail u)))<>"?secret="<>secret<>"&issuer=ECC&algorithm=SHA256&digits=6&period=30"),"message".=("Add this key to a SHA-256 compatible authenticator, then confirm with its code."::T.Text)])
  "enable" -> do
   provePassword env u input
   code<-needed "code" input
   rows<-liftIO $ query (envConn env) "SELECT mfa_pending FROM users WHERE id=? AND mfa_secret IS NULL" (Only(userId u)) :: S.ActionM [Only (Maybe T.Text)]
   secret<-case rows of [Only(Just s)]->pure s; _ -> reject status400 "Start authenticator setup first"
   now<-liftIO $ floor . (/30) <$> getPOSIXTime
   let valid=[step | step<-[now-1,now,now+1],sameCode (totp (unbase32 secret) step 6) code]
   when(null valid) $ reject status400 "Authenticator code is incorrect"
   codes<-liftIO $ forM [1..8::Int] $ \_ -> T.take 16 . TE.decodeUtf8 <$> randomToken
   req<-S.request
   tok<-maybe (reject status401 "Sign in again") pure (requestToken req)
   liftIO $ do
    void $ execute (envConn env) "UPDATE users SET mfa_secret=?,mfa_pending=NULL,mfa_last_step=? WHERE id=?" (secret,head valid,userId u)
    void $ execute (envConn env) "DELETE FROM sessions WHERE user_id=? AND token_hash<>?" (userId u,tokenHash tok)
    void $ execute (envConn env) "UPDATE sessions SET mfa_verified=1 WHERE token_hash=?" (Only(tokenHash tok))
    void $ execute (envConn env) "DELETE FROM mfa_recovery_codes WHERE user_id=?" (Only(userId u))
    forM_ codes $ \recovery -> void $ execute (envConn env) "INSERT INTO mfa_recovery_codes(user_id,code_hash) VALUES (?,?)" (userId u,tokenHash(TE.encodeUtf8 recovery))
   pure (A.object ["recoveryCodes".=codes,"message".=("MFA enabled. Save these single-use recovery codes now; they will not be shown again."::T.Text)])
  "disable" -> do
   provePassword env u input
   verified<-liftIO $ verifyMfa env (userId u) (field "code" input)
   unless verified $ reject status403 "Enter a fresh authenticator or recovery code"
   liftIO $ do
    void $ execute (envConn env) "UPDATE users SET mfa_secret=NULL,mfa_pending=NULL,mfa_last_step=-1 WHERE id=?" (Only(userId u))
    void $ execute (envConn env) "DELETE FROM mfa_recovery_codes WHERE user_id=?" (Only(userId u))
    void $ execute (envConn env) "DELETE FROM sessions WHERE user_id=?" (Only(userId u))
   pure(A.object ["message".=("MFA disabled. Sign in again."::T.Text)])
  "revoke" -> do
   sid<-needed "session" input
   liftIO $ void $ execute (envConn env) "DELETE FROM sessions WHERE user_id=? AND substr(token_hash,1,16)=?" (userId u,sid)
   liftIO $ securityAudit env u (userId u) "Session revoked"
   pure saved
  "reset-mfa" -> do
   uid<-intField "user" input
   when(uid==userId u) $ reject status400 "Use your recovery code to disable your own authenticator"
   reason<-bounded "reason" 500 input
   provePassword env u input
   enrolled<-liftIO $ query (envConn env) "SELECT id FROM users WHERE id=? AND mfa_secret IS NOT NULL" (Only(userId u)) :: S.ActionM [Only Int]
   when(null enrolled) $ reject status403 "Enable your own authenticator before resetting another account"
   verified<-liftIO $ verifyMfa env (userId u) (field "code" input)
   unless verified $ reject status403 "Enter a fresh authenticator or recovery code"
   target<-liftIO $ query (envConn env) "SELECT email FROM users WHERE id=?" (Only uid) :: S.ActionM [Only T.Text]
   email<-case target of [Only addr]->pure addr; _->reject status404 "Account not found"
   liftIO $ do
    void $ execute (envConn env) "UPDATE users SET mfa_secret=NULL,mfa_pending=NULL,mfa_last_step=-1 WHERE id=?" (Only uid)
    void $ execute (envConn env) "DELETE FROM mfa_recovery_codes WHERE user_id=?" (Only uid)
    void $ execute (envConn env) "DELETE FROM sessions WHERE user_id=?" (Only uid)
    void $ execute (envConn env) "INSERT INTO audit_log(entity_type,entity_id,entity_name,action,changes,actor_id) VALUES ('user',?,'Administrator MFA recovery','mfa_changed',?,?)" (uid,TE.decodeUtf8(BL.toStrict(A.encode(A.object["reason".=reason]))),userId u)
    void $ execute (envConn env) "INSERT INTO mail_outbox(recipient,subject,body,actor_id) VALUES (?,?,?,?)" (email,"Your ECC authenticator was reset"::T.Text,"An administrator reset your authenticator and signed out your sessions. Sign in with your password and enroll a new authenticator in Account security. Contact your administrator immediately if you did not request this."::T.Text,userId u)
   pure(A.object ["message".=("Authenticator reset; sessions and recovery codes revoked. The account owner has been queued a notification and should enroll a new authenticator."::T.Text)])
  "revoke-user" -> do
   uid<-intField "user" input
   liftIO $ void $ execute (envConn env) "DELETE FROM sessions WHERE user_id=?" (Only uid)
   liftIO $ securityAudit env u uid "All sessions revoked"
   pure saved
  "suspend" -> setSuspended True
  "resume" -> setSuspended False
  _ -> reject status404 "Security action not found"
 where
  saved=A.object ["message".=("Account access updated"::T.Text)]
  setSuspended suspended=do
   uid<-intField "user" input
   when(uid==userId u) $ reject status400 "You cannot suspend your own account"
   admins<-liftIO $ query (envConn env) "SELECT id FROM users WHERE role='admin' AND suspended=0 AND id<>?" (Only uid) :: S.ActionM [Only Int]
   when(suspended && null admins) $ reject status400 "Keep at least one active administrator"
   liftIO $ void $ execute (envConn env) "UPDATE users SET suspended=? WHERE id=?" (suspended,uid)
   pure saved

sendCommunication :: Env -> User -> A.Value -> S.ActionM A.Value
sendCommunication env u input = do
 (ml,mc,cs)<-owner env u input
 subject<-bounded "subject" 255 input
 message<-bounded "message" 20000 input
 rateLimitAccount env "outgoing" (T.pack(show(userId u)))
 rows<-liftIO $ case mc of
  Just cid -> query (envConn env) "SELECT email FROM clients WHERE id=?" (Only cid)
  _ -> query (envConn env) "SELECT email FROM leads WHERE id=?" (Only ml)
 email<-case rows :: [Only(Maybe T.Text)] of [Only(Just addr)] | not(T.null addr) ->pure addr; _ ->reject status400 "Add an email address to this record first"
 when(T.any (`elem` ['\r','\n']) subject) $ reject status400 "Subject must be one line"
 liftIO $ do
  void $ execute (envConn env) "INSERT INTO mail_outbox(recipient,subject,body,actor_id,lead_id,client_id) VALUES (?,?,?,?,?,?)" (email,subject,message,userId u,ml,mc)
  recordHistory env u ml mc cs "email_queued" (subject<>"\n"<>message)
 pure(A.object ["message".=("Email queued for "<>email)])

calendar :: Env -> S.ActionM ()
calendar env = do
 rows<-liftIO $ query_ (envConn env) ("SELECT id,title,strftime('%Y%m%dT%H%M%SZ',starts_at),strftime('%Y%m%dT%H%M%SZ',ends_at),location FROM appointments WHERE status='Scheduled' AND (lead_id IN ("<>visibleLeads<>") OR client_id IN ("<>visibleClients<>")) ORDER BY starts_at LIMIT 5000") :: S.ActionM [(Int,T.Text,T.Text,T.Text,T.Text)]
 now<-liftIO getCurrentTime
 let escaped=T.replace "\n" "\\n" . T.replace "\r" "" . T.replace ";" "\\;" . T.replace "," "\\," . T.replace "\\" "\\\\"
     event (i,title,start,end,location)=["BEGIN:VEVENT","UID:"<>T.take 16(tokenHash(TE.encodeUtf8(envPublicUrl env)))<>"-"<>T.pack(show i)<>"@ecc","DTSTAMP:"<>T.pack(formatTime defaultTimeLocale "%Y%m%dT%H%M%SZ" now),"DTSTART:"<>start,"DTEND:"<>end,"SUMMARY:"<>escaped title,"LOCATION:"<>escaped location,"END:VEVENT"]
     folded text=foldLine 75 text
     contents=T.intercalate "\r\n" (concatMap folded (["BEGIN:VCALENDAR","VERSION:2.0","PRODID:-//ECC//Workspace//EN"]++concatMap event rows++["END:VCALENDAR"]))<>"\r\n"
 S.setHeader "Content-Type" "text/calendar; charset=utf-8"
 S.setHeader "Content-Disposition" "attachment; filename=appointments.ics"
 S.raw (BL.fromStrict(TE.encodeUtf8 contents))

foldLine :: Int -> T.Text -> [T.Text]
foldLine budget text =
 let takeBytes _ [] = ([],[])
     takeBytes n allChars@(c:cs) = let size=B.length(TE.encodeUtf8(T.singleton c)) in
       if size>n then ([],allChars) else let (a,b)=takeBytes (n-size) cs in (c:a,b)
     segments _ []=[]
     segments n chars=let (first,rest)=takeBytes n chars in T.pack first:segments 74 rest
 in case segments budget (T.unpack text) of
     [] -> [""]
     first:rest -> first:map (" "<>) rest

securityAudit :: Env -> User -> Int -> T.Text -> IO ()
securityAudit env actor uid description = void $ execute (envConn env) "INSERT INTO audit_log(entity_type,entity_id,entity_name,action,actor_id) VALUES ('session',?,?,'revoked',?)" (uid,description,userId actor)
