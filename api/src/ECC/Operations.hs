{-# LANGUAGE OverloadedStrings #-}
module ECC.Operations where
import Control.Monad (unless,when,void)
import Control.Monad.IO.Class (liftIO)
import qualified Data.Aeson as A
import Data.Aeson ((.=))
import qualified Data.Aeson.Key as K
import qualified Data.Aeson.KeyMap as KM
import qualified Data.ByteString.Lazy as BL
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import Network.HTTP.Types hiding (Query)
import Network.Wai.Parse (FileInfo(..))
import qualified Web.Scotty as S
import ECC.Store
import ECC.DB (Env(..),insertDocument)
import ECC.Models
import ECC.WorkflowSupport
import qualified ECC.Applications as Applications
import qualified ECC.Journey as Journey
import qualified ECC.Integrations as Integrations
import qualified ECC.Finance as Finance
import qualified ECC.Access as Access
import ECC.Auth (randomToken)
import qualified ECC.StudentWorkflows as StudentWorkflows
import ECC.Security (reject,rateLimitAccount)
import qualified ECC.Csv as Csv

type Guard=(User -> S.ActionM ()) -> S.ActionM ()
routes :: Env -> Guard -> Guard -> Guard -> S.ScottyM ()
routes env reader writer admin = do
 S.get "/api/workspace/record/:kind/:id/:section" $ reader $ \u -> do
  kind<-S.pathParam "kind"; rid<-S.pathParam "id"; section<-S.pathParam "section"
  let own=kind<>":"<>T.pack(show(rid::Int))
  (ml,mc,cs)<-owner env u (A.object["owner".=own])
  offset<-S.queryParamMaybe "offset" :: S.ActionM (Maybe Int)
  q<-maybe "" id <$> S.queryParamMaybe "q"
  when(section=="invoices" && userRole u/="admin") $ reject status403 "Invoice administration requires an administrator"
  when(section `elem` ["payments","invoices"]) $ Access.requirePrivilege env u "finance_view"
  rows<-if section=="integrations" then liftIO $ Integrations.staffRows env u mc cs else if section=="payments" then liftIO $ Finance.invoiceRowsScoped env mc cs q (max 0(maybe 0 id offset)) 50 else if Journey.commercialSection section then Journey.commercialRows env u section mc cs q (max 0(maybe 0 id offset)) else liftIO $ recordRows env section ml mc cs q (max 0(maybe 0 id offset))
  summary<-liftIO $ jsonRows env "SELECT json_object('required',coalesce(sum(required=1),0),'outstanding',coalesce(sum(required=1 AND (status<>'Approved' OR expires_on<date('now',business_offset()))),0),'review',coalesce(sum(status='Received'),0),'expiring',coalesce(sum(expires_on<=date('now',business_offset(),'+30 days')),0)) FROM document_requests WHERE lead_id IS ? AND client_id IS ? AND (? IS NULL OR case_id=?)" (ml,mc,cs,cs)
  staffOptions<-liftIO $ jsonRows env "SELECT json_object('value','staff:'||id,'label',name) FROM users WHERE suspended=0 AND role<>'viewer' ORDER BY name" ()
  caseOptions<-liftIO $ case (kind,mc) of
   ("client",Just cid)->jsonRows env "SELECT json_object('value','case:'||id,'label',coalesce(service_category,'Case')||' · '||stage) FROM cases WHERE client_id=? ORDER BY id" (Only cid)
   _->pure []
  recordPayment<-liftIO $ Access.hasPrivilege env u "payments_record"
  download<-liftIO $ Access.hasPrivilege env u "download"
  exportAllowed<-liftIO $ Access.hasPrivilege env u "export"
  key<-TE.decodeUtf8 <$> liftIO randomToken
  respondJson env (A.object["submissionKey".=key,"permissions".=A.object["record".=recordPayment,"export".=exportAllowed,"download".=download],"rows".=rows,"summary".=summary,"options".=(A.object["value".=own,"label".=("Current "<>kind)]:caseOptions++staffOptions)])
 S.get "/api/workspace/conflict/:section/:id" $ reader $ \u -> do
  section<-S.pathParam "section"; rid<-S.pathParam "id"
  current<-currentForm env u section rid
  respondJson env current
 S.post "/api/workspace/documents/:id/upload" $ writer $ \u -> do
  rid<-S.pathParam "id"
  rows<-liftIO $ query (envConn env) "SELECT lead_id,client_id,case_id,revision FROM document_requests WHERE id=?" (Only(rid::Int)) :: S.ActionM [(Maybe Int,Maybe Int,Maybe Int,Int)]
  case rows of
   [(ml,mc,cs,rev)] -> do
    checkOwner env u ml mc
    expected<-S.formParam "expectedRevision" :: S.ActionM Int
    checkOwnRevision rev (A.object["expectedRevision".=expected])
    files<-S.files
    case files of
     [(_,fi)] -> do
      let bytes=fileContent fi
          name=T.take 255(T.filter(\c -> c `notElem` ['\r','\n','/','\\','\0']) (TE.decodeUtf8With (\_ _->Just '_') (fileName fi)))
      when (BL.null bytes || BL.length bytes>25*1024*1024 || T.null name) $ reject status400 "Choose a nonempty file up to 25 MB"
      liftIO $ do
       doc<-insertDocument (envConn env) ml mc name "application/octet-stream" (BL.toStrict bytes) (Just(userId u))
       void $ execute (envConn env) "INSERT INTO document_versions(request_id,document_id,version) SELECT ?,?,coalesce(max(version),0)+1 FROM document_versions WHERE request_id=?" (rid,documentId doc,rid)
       void $ execute (envConn env) "UPDATE document_requests SET status='Received',review_note=NULL,reviewed_by=NULL WHERE id=?" (Only rid)
       recordHistory env u ml mc cs "document_uploaded" ("Uploaded for scanning: "<>name)
      S.json(A.object["message".=("File uploaded and quarantined until malware scanning completes"::T.Text)])
     _ -> reject status400 "Choose one file"
   _ -> reject status404 "Checklist item not found"
 S.post "/api/workspace/documents/rescan" $ admin $ \u -> do
  input<-bodyObject; rid<-intField "id" input
  rateLimitAccount env "scan-retry" (T.pack(show(userId u)))
  changed<-liftIO $ query (envConn env) "UPDATE documents SET scan_status='Pending',scan_attempts=0,scan_lease=NULL,scan_until=NULL,scan_detail=NULL WHERE id=(SELECT document_id FROM document_versions WHERE request_id=? ORDER BY version DESC LIMIT 1) AND scan_status='Error' RETURNING id" (Only rid) :: S.ActionM [Only Int]
  case changed of
   [Only did] -> do
    liftIO $ void $ execute (envConn env) "INSERT INTO audit_log(entity_type,entity_id,entity_name,action,actor_id) VALUES ('document',?,'Failed malware scan queued again','updated',?)" (did,userId u)
    S.json(A.object["message".=("Scan queued again; file remains quarantined"::T.Text)])
   _ -> reject status400 "Select an item whose latest file has a failed scan. Infected files require a replacement upload."
 S.post "/api/workspace/mail/retry" $ admin $ \u -> do
  input<-bodyObject; mid<-intField "id" input
  rateLimitAccount env "mail-retry" (T.pack(show(userId u)))
  n<-liftIO $ execute (envConn env) "UPDATE mail_outbox SET attempts=0,last_error=NULL,next_attempt_at=NULL,retry_count=retry_count+1,retried_at=datetime('now') WHERE id=? AND sent_at IS NULL AND attempts>=5 AND retry_count<3 AND (claimed_until IS NULL OR claimed_until<datetime('now')) AND (retried_at IS NULL OR retried_at<datetime('now','-15 minutes'))" (Only mid)
  unless(n==1) $ reject status409 "Only exhausted, unclaimed failures can be retried: maximum three manual retries, at least 15 minutes apart"
  liftIO $ void $ execute (envConn env) "INSERT INTO audit_log(entity_type,entity_id,entity_name,action,actor_id) VALUES ('user',?,'Email retry requested','updated',?)" (userId u,userId u)
  S.json(A.object["message".=("Email queued for retry; SMTP acceptance does not confirm inbox delivery"::T.Text)])
 S.post "/api/workspace/notifications/:action" $ reader $ \u -> do
  action<-S.pathParam "action"; input<-bodyObject
  case action :: T.Text of
   "read" -> do
    nid<-intField "id" input
    liftIO $ void $ execute (envConn env) "UPDATE notifications SET read_at=coalesce(read_at,datetime('now')) WHERE id=? AND user_id=?" (nid,userId u)
   "archive" -> do
    nid<-intField "id" input
    liftIO $ void $ execute (envConn env) "UPDATE notifications SET archived_at=datetime('now'),read_at=coalesce(read_at,datetime('now')) WHERE id=? AND user_id=?" (nid,userId u)
   "preferences" -> do
    let flag key=field key input/="false"
    existing<-liftIO $ query (envConn env) "SELECT revision FROM notification_preferences WHERE user_id=?" (Only(userId u)) :: S.ActionM [Only Int]
    case existing of Only rev:_ -> checkOwnRevision rev input; _ -> pure ()
    liftIO $ void $ execute (envConn env) "INSERT INTO notification_preferences(user_id,assignments,deadlines,documents,escalations,email_enabled) VALUES (?,?,?,?,?,?) ON CONFLICT(user_id) DO UPDATE SET assignments=excluded.assignments,deadlines=excluded.deadlines,documents=excluded.documents,escalations=excluded.escalations,email_enabled=excluded.email_enabled,revision=notification_preferences.revision+1" (userId u,flag "assignments",flag "deadlines",flag "documents",flag "escalations",flag "emailEnabled")
   _ -> reject status404 "Notification action not found"
  S.json(A.object["message".=("Notifications updated"::T.Text)])
 S.get "/api/workspace/report-export/:kind" $ admin $ \_ -> do
  kind<-S.pathParam "kind"; range<-maybe "" id <$> S.queryParamMaybe "q"
  unless(kind `elem` ["ageing","bottlenecks","trends"]) $ reject status404 "Report not found"
  rows<-liftIO $ reportRows env kind range 0 True
  let cols=reportColumns kind
      textValue (A.String t)=t
      textValue A.Null=""
      textValue v=TE.decodeUtf8(BL.toStrict(A.encode v))
      get row key=case row of A.Object o -> maybe "" textValue(KM.lookup(K.fromText key)o); _ -> ""
  S.setHeader "Content-Type" "text/csv; charset=utf-8"
  S.setHeader "Content-Disposition" "attachment; filename=management-report.csv"
  S.raw(Csv.renderCsv(map Csv.cell cols:map(\row -> map(Csv.cell . get row)cols)rows))

recordRows :: Env -> T.Text -> Maybe Int -> Maybe Int -> Maybe Int -> T.Text -> Int -> IO [A.Value]
recordRows env section ml mc cs q offset = case section of
 "profile" -> Journey.profileRows env ml mc
 "client-messages" -> Journey.messageRows env mc cs offset
 "applications" -> Applications.applicationRows env mc q offset
 "invoices" -> jsonRows env "SELECT json_object('id',i.id,'title','INV-'||printf('%06d',i.id),'owner',CASE WHEN i.case_id IS NOT NULL THEN 'case:'||i.case_id ELSE 'client:'||i.client_id END,'description',i.description,'currency',i.currency,'lineItems',i.line_items,'subtotal',printf('%.2f',i.subtotal_minor/100.0),'discount',printf('%.2f',i.discount_minor/100.0),'tax',printf('%.2f',i.tax_minor/100.0),'amount',printf('%.2f',i.amount_minor/100.0),'paid',printf('%.2f',i.paid_minor/100.0),'balance',printf('%.2f',i.balance_minor/100.0),'dueDate',i.due_date,'status',i.status,'revision',i.revision) FROM invoice_balances i WHERE i.client_id=? AND (? IS NULL OR i.case_id=?) AND i.description LIKE ? ORDER BY i.id DESC LIMIT 50 OFFSET ?" (mc,cs,cs,"%"<>q<>"%",offset)
 "documents" -> documentRows env (Just(ml,mc,cs)) q offset
 "tasks" -> jsonRows env ("SELECT json_object('id',t.id,'title',t.title,'description',coalesce(t.description,''),'notes',t.notes,'scheduledAt',replace(substr(coalesce(t.scheduled_at,''),1,16),' ','T'),'dueAt',replace(substr(coalesce(t.due_at,''),1,16),' ','T'),'completedAt',t.completed_at,'overdue',t.cancelled_at IS NULL AND t.status<>'Done' AND ((t.due_at IS NOT NULL AND t.due_at<datetime('now')) OR (t.due_at IS NULL AND t.due_date<date('now',business_offset()))),'dueDate',coalesce(t.due_date,''),'priority',t.priority,'status',CASE WHEN t.cancelled_at IS NOT NULL THEN 'Cancelled' ELSE t.status END,'assignee',coalesce(t.assigned_to_id,''),'assigneeName',coalesce(u.name,'Unassigned'),'recurrenceDays',coalesce(t.recurrence_days,''),'revision',v.revision,'caseId',t.case_id) FROM tasks t LEFT JOIN users u ON u.id=t.assigned_to_id JOIN record_versions v ON v.kind='tasks' AND v.record_id=t.id WHERE "<>(if mc/=Nothing then "t.client_id=?" else "t.lead_id=?")<>" AND "<>taskVisibility<>" AND (? IS NULL OR t.case_id=?) AND t.title LIKE ? ORDER BY t.due_date NULLS LAST,t.id LIMIT 50 OFFSET ?") (if mc/=Nothing then mc else ml,cs,cs,"%"<>q<>"%",offset)
 "appointments" -> jsonRows env "SELECT json_object('id',id,'title',title,'owner',CASE WHEN case_id IS NOT NULL THEN 'case:'||case_id WHEN client_id IS NOT NULL THEN 'client:'||client_id ELSE 'lead:'||lead_id END,'assignee',owner_id,'startsAt',replace(substr(starts_at,1,16),' ','T'),'endsAt',replace(substr(ends_at,1,16),' ','T'),'location',location,'notes',notes,'meetingUrl',meeting_url,'meetingId',meeting_id,'passcode',passcode,'clientVisible',client_visible=1,'task',task_id,'status',status,'revision',revision) FROM appointments WHERE lead_id IS ? AND client_id IS ? AND (? IS NULL OR case_id=?) AND title LIKE ? ORDER BY starts_at DESC LIMIT 50 OFFSET ?" (ml,mc,cs,cs,"%"<>q<>"%",offset)
 "history" -> jsonRows env ("SELECT json_object('id',h.id,'title',h.note,'note',h.note,'actor',coalesce(u.name,'System/Client'),'kind',h.kind,'meetingUrl',coalesce((SELECT meeting_url FROM appointments WHERE id=h.meeting_id),''),'date',h.created_at) FROM work_history h LEFT JOIN users u ON u.id=h.actor_id WHERE h.lead_id IS ? AND h.client_id IS ? AND (? IS NULL OR h.case_id=?) AND (h.task_id IS NULL OR h.task_id IN ("<>visibleTasks<>")) AND h.note LIKE ? ORDER BY h.id DESC LIMIT 50 OFFSET ?") (ml,mc,cs,cs,"%"<>q<>"%",offset)
 _ -> pure []

documentRows :: Env -> Maybe (Maybe Int,Maybe Int,Maybe Int) -> T.Text -> Int -> IO [A.Value]
documentRows env scope mode offset = do
 let (allRecords,ml,mc,cs)=case scope of Nothing -> (True,Nothing,Nothing,Nothing); Just(l,c,s)->(False,l,c,s)
 jsonRows env ("SELECT json_object('id',d.id,'title',d.title,'owner',CASE WHEN d.case_id IS NOT NULL THEN 'case:'||d.case_id WHEN d.client_id IS NOT NULL THEN 'client:'||d.client_id ELSE 'lead:'||d.lead_id END,'status',d.status,'required',CASE WHEN d.required=1 THEN 'true' ELSE 'false' END,'expiresOn',coalesce(d.expires_on,''),'reviewNote',coalesce(d.review_note,''),'revision',d.revision,'expiryWarning',CASE WHEN d.expires_on<date('now',business_offset()) THEN 'Expired' WHEN d.expires_on<=date('now',business_offset(),'+30 days') THEN 'Expires within 30 days' ELSE '' END,'outstanding',d.required=1 AND (d.status<>'Approved' OR d.expires_on<date('now',business_offset())),'scanStatus',coalesce((SELECT f.scan_status FROM document_versions v JOIN documents f ON f.id=v.document_id WHERE v.request_id=d.id ORDER BY v.version DESC LIMIT 1),'No file'),'versions',(SELECT json_group_array(json_object('documentId',v.document_id,'version',v.version,'filename',f.filename,'scanStatus',f.scan_status)) FROM document_versions v JOIN documents f ON f.id=v.document_id WHERE v.request_id=d.id)) FROM document_requests d WHERE (d.lead_id IN ("<>visibleLeads<>") OR d.client_id IN ("<>visibleClients<>")) AND (? OR (d.lead_id IS ? AND d.client_id IS ? AND (? IS NULL OR d.case_id=?))) AND (CASE ? WHEN 'review' THEN d.status='Received' WHEN 'expiring' THEN d.expires_on<=date('now',business_offset(),'+30 days') WHEN 'outstanding' THEN d.required=1 AND (d.status<>'Approved' OR d.expires_on<date('now',business_offset())) ELSE d.title LIKE '%'||?||'%' END) ORDER BY d.status='Received' DESC,d.expires_on NULLS LAST,d.id DESC LIMIT 50 OFFSET ?") (allRecords,ml,mc,cs,cs,mode,mode,offset)

mailRows :: Env -> User -> T.Text -> Int -> IO [A.Value]
mailRows env u q offset=jsonRows env ("SELECT json_object('id',m.id,'title',m.subject,'recipient',m.recipient,'status',CASE WHEN m.sent_at IS NOT NULL THEN 'Accepted by SMTP' WHEN m.attempts>=5 THEN 'Failed' WHEN m.claimed_until>datetime('now') THEN 'Sending' WHEN m.next_attempt_at>datetime('now') THEN 'Retry scheduled' ELSE 'Queued' END,'attempts',m.attempts,'lastError',coalesce(m.last_error,''),'created',m.created_at,'sentAt',m.sent_at,'retryCount',m.retry_count,'nextAttempt',m.next_attempt_at) FROM mail_outbox m WHERE (?='admin' OR m.actor_id=? AND (m.lead_id IN ("<>visibleLeads<>") OR m.client_id IN ("<>visibleClients<>"))) AND (m.subject LIKE ? OR m.recipient LIKE ?) ORDER BY m.id DESC LIMIT 50 OFFSET ?") (userRole u,userId u,"%"<>q<>"%","%"<>q<>"%",offset)

notificationRows :: Env -> User -> Int -> IO [A.Value]
notificationRows env u offset = do
 Journey.refreshOverdue env
 jsonRows env ("SELECT json_object('id',n.id,'title',n.title,'kind',n.kind,'date',n.created_at,'status',CASE WHEN read_at IS NULL THEN 'Unread' ELSE 'Read' END,'path',CASE WHEN n.client_id IS NOT NULL THEN '/clients/'||n.client_id ELSE '/leads/'||n.lead_id END) FROM notifications n LEFT JOIN notification_preferences p ON p.user_id=n.user_id WHERE n.archived_at IS NULL AND n.user_id=? AND (n.client_id IN ("<>visibleClients<>") OR n.lead_id IN ("<>visibleLeads<>")) AND CASE n.kind WHEN 'assignments' THEN coalesce(p.assignments,1) WHEN 'deadlines' THEN coalesce(p.deadlines,1) WHEN 'documents' THEN coalesce(p.documents,1) WHEN 'escalations' THEN coalesce(p.escalations,1) ELSE 0 END=1 ORDER BY n.id DESC LIMIT 50 OFFSET ?") (userId u,offset)

preferences :: Env -> User -> IO A.Value
preferences env u = do
 rows<-jsonRows env "SELECT json_object('assignments',assignments=1,'deadlines',deadlines=1,'documents',documents=1,'escalations',escalations=1,'emailEnabled',email_enabled=1,'revision',revision) FROM notification_preferences WHERE user_id=?" (Only(userId u))
 pure $ case rows of row:_ -> row; _ -> A.object["assignments".=True,"deadlines".=True,"documents".=True,"escalations".=True,"emailEnabled".=True,"revision".=(1::Int)]

reportColumns :: T.Text -> [T.Text]
reportColumns kind=case kind of
 "ageing" -> ["id","title","stage","ageDays","overdueDays","staff"]
 "bottlenecks" -> ["title","cases","averageAgeDays","oldestDays"]
 _ -> ["date","title","openTasks","overdueTasks","openCases"]
reportRows :: Env -> T.Text -> T.Text -> Int -> Bool -> IO [A.Value]
reportRows env kind range offset exporting = do
 let limit=(if exporting then 10000 else 50) :: Int
     parts=T.splitOn "," range
     (start,end)=case parts of [a,b] | T.length a==10,T.length b==10,a<=b ->(a,b); _ ->("0001-01-01","9999-12-31")
 case kind of
  "ageing" -> jsonRows env "SELECT json_object('id',c.id,'title',cl.full_name||' · '||coalesce(c.service_category,'Case'),'stage',c.stage,'ageDays',CAST(julianday('now')-julianday(c.created_at) AS INTEGER),'overdueDays',CASE WHEN c.next_deadline<date('now',business_offset()) THEN CAST(julianday(date('now',business_offset()))-julianday(c.next_deadline) AS INTEGER) ELSE 0 END,'staff',coalesce(u.name,'Unassigned'),'path','/clients/'||cl.id) FROM cases c JOIN clients cl ON cl.id=c.client_id LEFT JOIN users u ON u.id=cl.case_officer_id WHERE cl.deleted_at IS NULL AND c.stage NOT IN ('Approved','Rejected','Completed') AND date(c.created_at,business_offset()) BETWEEN ? AND ? ORDER BY c.created_at,c.id LIMIT ? OFFSET ?" (start,end,limit,offset)
  "bottlenecks" -> jsonRows env "SELECT json_object('title',c.stage,'cases',count(*),'averageAgeDays',round(avg(julianday('now')-julianday(coalesce((SELECT max(h.created_at) FROM work_history h WHERE h.case_id=c.id AND h.kind='case_updated'),c.created_at))),1),'oldestDays',CAST(max(julianday('now')-julianday(coalesce((SELECT max(h.created_at) FROM work_history h WHERE h.case_id=c.id AND h.kind='case_updated'),c.created_at))) AS INTEGER)) FROM cases c JOIN clients cl ON cl.id=c.client_id WHERE cl.deleted_at IS NULL AND c.stage NOT IN ('Approved','Rejected','Completed') AND date(c.created_at,business_offset()) BETWEEN ? AND ? GROUP BY c.stage ORDER BY count(*) DESC LIMIT ? OFFSET ?" (start,end,limit,offset)
  _ -> jsonRows env "SELECT json_object('date',s.day,'title',s.staff_name,'openTasks',open_tasks,'overdueTasks',overdue_tasks,'openCases',open_cases) FROM workload_snapshots s WHERE s.day BETWEEN ? AND ? ORDER BY s.day DESC,s.staff_name LIMIT ? OFFSET ?" (start,end,limit,offset)

requireClean :: Env -> Int -> S.ActionM ()
requireClean env did = do
 rows<-liftIO $ query (envConn env) "SELECT scan_status FROM documents WHERE id=?" (Only did) :: S.ActionM [Only T.Text]
 unless(rows==[Only "Clean"]) $ reject (mkStatus 423 "Locked") "This file is quarantined until malware scanning succeeds. Pending, infected and failed scans cannot be downloaded or approved."

currentForm :: Env -> User -> T.Text -> Int -> S.ActionM A.Value
currentForm env u section rid = do
 rows<-liftIO $ case section of
  "checklist-templates" -> Applications.templateForm env u rid
  "applications" -> Applications.applicationForm env u rid
  "milestones" -> StudentWorkflows.milestoneForm env rid
  "tasks" -> jsonRows env ("SELECT json_object('id',t.id,'title',title,'description',coalesce(description,''),'notes',notes,'dueDate',coalesce(due_date,''),'priority',priority,'status',CASE WHEN cancelled_at IS NOT NULL THEN 'Cancelled' ELSE status END,'assignee',coalesce(assigned_to_id,''),'recurrenceDays',coalesce(recurrence_days,''),'revision',v.revision) FROM tasks t JOIN record_versions v ON v.kind='tasks' AND v.record_id=t.id WHERE t.id=? AND t.id IN ("<>visibleTasks<>")") (Only rid)
  "documents" -> jsonRows env ("SELECT json_object('id',id,'title',title,'owner',CASE WHEN case_id IS NOT NULL THEN 'case:'||case_id WHEN client_id IS NOT NULL THEN 'client:'||client_id ELSE 'lead:'||lead_id END,'required',required=1,'status',status,'expiresOn',coalesce(expires_on,''),'reviewNote',coalesce(review_note,''),'revision',revision) FROM document_requests WHERE id=? AND (lead_id IN ("<>visibleLeads<>") OR client_id IN ("<>visibleClients<>"))") (Only rid)
  "reminders" -> jsonRows env ("SELECT json_object('id',id,'task',task_id,'daysBefore',days_before,'escalateAfter',escalate_after,'enabled',enabled=1,'revision',revision) FROM reminder_rules WHERE task_id=? AND task_id IN ("<>visibleTasks<>")") (Only rid)
  "clients" -> jsonRows env ("SELECT json_object('id',c.id,'ncFullName',full_name,'ncEmail',coalesce(email,''),'ncPhone',coalesce(phone,''),'ncCaseOfficer',coalesce(case_officer_id,''),'revision',v.revision) FROM clients c JOIN record_versions v ON v.kind='clients' AND v.record_id=c.id WHERE c.id=? AND c.id IN ("<>visibleClients<>")") (Only rid)
  "cases" -> jsonRows env ("SELECT json_object('id',c.id,'ciCaseId',c.id,'ciServiceCategory',coalesce(service_category,''),'ciDestination',coalesce(destination,''),'ciStage',stage,'ciNextDeadline',coalesce(next_deadline,''),'revision',v.revision) FROM cases c JOIN record_versions v ON v.kind='cases' AND v.record_id=c.id WHERE c.id=? AND client_id IN ("<>visibleClients<>")") (Only rid)
  "leads" -> jsonRows env ("SELECT json_object('id',l.id,'ulFullName',full_name,'ulEmail',coalesce(email,''),'ulPhone',coalesce(phone,''),'ulSource',coalesce(source,''),'ulQuality',coalesce(quality,''),'ulStage',stage,'ulDestination',coalesce(destination,''),'ulService',coalesce(service,''),'ulNotes',coalesce(notes,''),'ulLastContact',coalesce(last_contact,''),'ulNextFollowup',coalesce(next_followup,''),'ulConsultantId',coalesce(consultant_id,''),'revision',v.revision) FROM leads l JOIN record_versions v ON v.kind='leads' AND v.record_id=l.id WHERE l.id=? AND l.id IN ("<>visibleLeads<>")") (Only rid)
  "appointments" -> jsonRows env ("SELECT json_object('id',id,'title',title,'owner',CASE WHEN client_id IS NOT NULL THEN 'client:'||client_id ELSE 'lead:'||lead_id END,'assignee',owner_id,'startsAt',replace(substr(starts_at,1,16),' ','T'),'endsAt',replace(substr(ends_at,1,16),' ','T'),'location',location,'notes',notes,'meetingUrl',meeting_url,'meetingId',meeting_id,'passcode',passcode,'task',task_id,'clientVisible',client_visible=1,'status',status,'revision',revision) FROM appointments WHERE id=? AND (lead_id IN ("<>visibleLeads<>") OR client_id IN ("<>visibleClients<>"))") (Only rid)
  "invoices" | userRole u=="admin" -> jsonRows env "SELECT json_object('id',id,'owner','client:'||client_id,'description',description,'currency',currency,'lineItems',line_items,'discount',printf('%.2f',discount_minor/100.0),'tax',printf('%.2f',tax_minor/100.0),'amount',printf('%.2f',amount_minor/100.0),'dueDate',due_date,'status',status,'revision',revision) FROM invoices WHERE id=?" (Only rid)
  "notifications" -> do row<-preferences env u; pure [row]
  "users" | userRole u=="admin" -> jsonRows env "SELECT json_object('id',u.id,'uuName',name,'uuRole',role,'revision',v.revision) FROM users u JOIN record_versions v ON v.kind='users' AND v.record_id=u.id WHERE u.id=?" (Only rid)
  _ -> pure []
 case rows of row:_ ->pure row; _ ->reject status404 "Current record not found"

createTask :: Env -> User -> A.Value -> S.ActionM A.Value
createTask env u input = do
 (ml,mc,cs)<-owner env u input
 title<-bounded "title" 255 input
 assigned<-intField "assignee" input
 staff env assigned
 checkAssignee env assigned ml mc
 dueDate<-dateField "dueDate" False input
 (scheduled,dueTime)<-Journey.taskTimes input
 let due=maybe dueDate (Just . T.take 10) dueTime
 priority<-choice "priority" ["Low","Medium","High","Urgent"] input
 status<-if T.null(field "status" input) then pure "Pending" else choice "status" ["Pending","In Progress","Done","Cancelled"] input
 let recurrence=number "recurrenceDays" input
 when (maybe False (\n -> n<1 || n>366) recurrence || recurrence/=Nothing && due==Nothing) $ reject status400 "Recurring tasks need a deadline and an interval of 1–366 days"
 liftIO $ do
  void $ execute (envConn env) "INSERT INTO tasks(lead_id,client_id,case_id,title,description,due_date,priority,assigned_to_id,recurrence_days,status,scheduled_at,due_at,notes,cancelled_at) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,CASE WHEN ? THEN datetime('now') ELSE NULL END)" (ml,mc,cs,title,field "description" input,due,priority,assigned,recurrence,if status=="Cancelled" then "Pending"::T.Text else status,scheduled,dueTime,field "notes" input,status=="Cancelled")

 pure (A.object["message".=("Task created"::T.Text)])
