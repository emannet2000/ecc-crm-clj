{-# LANGUAGE OverloadedStrings #-}
module ECC.Finance (routes, invoiceRowsScoped) where

import Control.Monad (forM, unless, void, when)
import Control.Monad.IO.Class (liftIO)
import qualified Data.Aeson as A
import Data.Aeson ((.=))
import qualified Data.Aeson.Key as K
import qualified Data.Aeson.KeyMap as KM
import qualified Data.ByteString.Lazy as BL
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import Data.Time (Day, defaultTimeLocale,  parseTimeM)
import Network.HTTP.Types hiding (Query)
import qualified Web.Scotty as S
import ECC.DB (Env(..))
import ECC.Clock (businessDay)
import ECC.Models
import ECC.Store
import ECC.Security (reject)
import ECC.Auth (randomToken)
import ECC.WorkflowSupport
import qualified ECC.Access as Access
import ECC.Money (amountMinor)
import qualified ECC.Journey as Journey
import ECC.FinanceCommon
import qualified ECC.FinanceControls as Controls
import qualified ECC.Csv as Csv

type Guard = (User -> S.ActionM ()) -> S.ActionM ()

sections :: [T.Text]
sections = ["sales","payments","balances","expenses","cashflow","finance-audit"]

routes :: Env -> Guard -> Guard -> S.ScottyM ()
routes env reader writer = do
 Controls.routes env reader writer
 S.get "/api/workspace/finance-export/:section" $ reader $ \u -> do
  section <- S.pathParam "section"
  unless (section `elem` sections) $ reject status404 "Financial report not found"
  Access.requirePrivilege env u (if section=="sales" then "sales_view" else "finance_view")
  Access.requirePrivilege env u "export"
  q <- maybe "" id <$> S.queryParamMaybe "q"
  rows <- if section=="payments" then liftIO $ paymentExport env q else rowsFor env u section q 0 10001
  when (length rows>10000) $ reject status400 "Export exceeds 10,000 rows. Narrow the date range or search before exporting."
  let columns = case section of
       "sales" -> ["kind","title","leads","converted","conversionRate","currency","invoiced","collected","outstanding","overdue","legacyUndated"]
       "cashflow" -> ["currency","invoiced","collected","expenses","net","outstanding","overdue","legacyUndated"]
       "payments" -> ["id","invoiceId","client","currency","amount","paidOn","method","reference","reason","reversesId","legacy","actor"]
       "balances" -> ["id","title","currency","total","paid","balance","dueDate","overdueDays","status"]
       "expenses" -> ["id","supplier","description","category","currency","amount","expenseOn","status","reference","createdBy","reviewNote","history"]
       _ -> ["id","kind","recordId","action","details","actor","date"]
      value row key = case row of
       A.Object obj -> case KM.lookup (K.fromText key) obj of
        Just (A.String t) -> t
        Just A.Null -> ""
        Just v -> TE.decodeUtf8(BL.toStrict(A.encode v))
        Nothing -> ""
       _ -> ""
  S.setHeader "Content-Type" "text/csv; charset=utf-8"
  S.setHeader "Content-Disposition" "attachment; filename=financial-report.csv"
  S.raw (Csv.renderCsv (map (Csv.cell . (\key -> if key=="client" then "student" else key)) columns : map (\row -> map (Csv.cell . value row) columns) rows))
 -- Exact routes precede the generic workspace dispatch.
 mapM_ (\section -> do
  S.get (S.capture ("/api/workspace/"<>T.unpack section)) $ reader $ \u -> do
   Access.requirePrivilege env u (if section=="sales" then "sales_view" else "finance_view")
   q <- maybe "" id <$> S.queryParamMaybe "q"
   offset <- max 0 . maybe 0 id <$> (S.queryParamMaybe "offset" :: S.ActionM (Maybe Int))
   rows <- rowsFor env u section q offset 50
   let options=[] :: [A.Value]
   permissions <- forM [("record","payments_record"),("reverse","payments_record"),("submit","expenses_record"),("pay","expenses_record"),("approve","expenses_approve"),("reject","expenses_approve"),("reverse-expense","expenses_approve"),("export","export"),("download","download")] $ \(action,privilege) -> do
    allowed <- liftIO $ Access.hasPrivilege env u privilege
    pure (K.fromText action .= (allowed && (action=="export" || userRole u/="viewer")))
   summary <- if section `elem` ["payments","balances"] then moneySummary env u "0001-01-01" "9999-12-31" False else pure []
   key <- TE.decodeUtf8 <$> liftIO randomToken
   S.json (A.object ["submissionKey".=key,"rows".=rows,"options".=options,"permissions".=A.object permissions,"summary".=summary])
  ) sections
 mapM_ (\(section,action,privilege) ->
  S.post (S.capture ("/api/workspace/"<>T.unpack section<>"/"<>T.unpack action)) $ writer $ \u -> do
   Access.requirePrivilege env u "finance_view"
   Access.requirePrivilege env u privilege
   input <- bodyObject
   if section=="payments" then paymentAction env u action input else expenseAction env u action input
   duplicates <- if section=="payments" && action=="record" && not(T.null(field "reference" input)) then liftIO $ query (envConn env) ("SELECT count(*) FROM invoice_payments p JOIN invoices i ON i.id=p.invoice_id WHERE i.client_id IN ("<>financialClients<>") AND lower(trim(p.reference))=lower(trim(?)) AND p.reverses_id IS NULL AND NOT EXISTS(SELECT 1 FROM invoice_payments r WHERE r.reverses_id=p.id)") (Only(field "reference" input)) else pure [Only (0::Int)]
   let warning=if any ((>1).fromOnly) duplicates then " Warning: this payment reference is used by multiple receipts. Verify it against the bank statement." else ""
   S.json (A.object ["message".=(("Financial entry saved. Posted history is retained."::T.Text)<>warning)])
  ) [("payments","record","payments_record"),("payments","reverse","payments_record"),("expenses","submit","expenses_record"),("expenses","approve","expenses_approve"),("expenses","reject","expenses_approve"),("expenses","pay","expenses_record"),("expenses","reverse-expense","expenses_approve")]

reportRange :: T.Text -> S.ActionM (T.Text,T.Text)
reportRange q
 | T.null q = pure ("0001-01-01","9999-12-31")
 | otherwise = case T.splitOn "," q of
  [a,b] -> do
   let start=if T.null a then "0001-01-01" else a
       end=if T.null b then "9999-12-31" else b
       valid t = (parseTimeM True defaultTimeLocale "%F" (T.unpack t) :: Maybe Day)/=Nothing
   unless (valid start && valid end && start<=end) $ reject status400 "Choose a valid start and end date"
   pure (start,end)
  _ -> reject status400 "Choose a start and end date"

rowsFor :: Env -> User -> T.Text -> T.Text -> Int -> Int -> S.ActionM [A.Value]
rowsFor env u section q offset limit = case section of
 "sales" -> do
  (start,end) <- reportRange q
  let visible="l.merged_into IS NULL AND ((SELECT assigned_only FROM request_context WHERE id=1)<>'true' OR (SELECT role FROM request_context WHERE id=1)='admin' OR l.consultant_id=(SELECT actor_id FROM request_context WHERE id=1))"
      grouped kind dimension = jsonRows env ("SELECT json_object('kind',?,'title',"<>dimension<>",'leads',count(*),'converted',sum(l.converted_client_id IS NOT NULL),'conversionRate',printf('%.2f',100.0*sum(l.converted_client_id IS NOT NULL)/count(*))) FROM leads l LEFT JOIN users u ON u.id=l.consultant_id WHERE "<>visible<>" AND date(l.created_at,business_offset()) BETWEEN ? AND ? GROUP BY "<>dimension<>" ORDER BY count(*) DESC LIMIT ? OFFSET ?") (kind::T.Text,start,end,10001::Int,0::Int)
  sources <- liftIO $ grouped "Source" "coalesce(nullif(l.source,''),'Unspecified')"
  staffRows <- liftIO $ grouped "Consultant" "coalesce(u.name,'Unassigned')||coalesce(' (#'||l.consultant_id||')','')"
  pipeline <- liftIO $ grouped "Pipeline" "CASE WHEN l.converted_client_id IS NOT NULL THEN 'Converted' WHEN l.deleted_at IS NOT NULL THEN 'Archived' ELSE l.stage END"
  money <- moneySummary env u start end False
  let result=sources++staffRows++pipeline++money
  when (length result>10000) $ reject status400 "Report exceeds 10,000 groups. Narrow the date range."
  pure result
 "cashflow" -> do
  (start,end) <- reportRange q
  moneySummary env u start end True
 "payments" -> liftIO $ invoiceRows env q offset limit
 "balances" -> liftIO $ invoiceRows env q offset limit
 "expenses" -> do
  allExpenses <- liftIO $ Access.hasPrivilege env u "expenses_approve"
  liftIO $ jsonRows env (expenseSelect<>" WHERE (? OR e.created_by=?) AND (e.supplier LIKE ? OR e.description LIKE ? OR e.category LIKE ?) ORDER BY e.id DESC LIMIT ? OFFSET ?") (allExpenses,userId u,term,term,term,limit,offset)
 "finance-audit" -> do
  periodAccess <- liftIO $ Access.hasPrivilege env u "finance_periods"
  bankAccess <- liftIO $ Access.hasPrivilege env u "finance_reconcile"
  scoped <- liftIO $ Access.assignedOnly env u
  let company=not scoped || userRole u=="admin"
  allExpenses <- liftIO $ Access.hasPrivilege env u "expenses_approve"
  liftIO $ jsonRows env ("SELECT json_object('id',a.id,'title',a.kind||' #'||a.record_id||' · '||a.action,'kind',a.kind,'recordId',a.record_id,'action',a.action,'details',a.details,'actor',a.actor_name,'date',a.created_at) FROM finance_audit a WHERE ((a.kind='payment' AND a.record_id IN (SELECT p.id FROM invoice_payments p JOIN invoices i ON i.id=p.invoice_id WHERE i.client_id IN ("<>financialClients<>"))) OR (a.kind='expense' AND a.record_id IN (SELECT id FROM expenses WHERE ? OR created_by=?)) OR (a.kind='period' AND ?) OR (a.kind='bank' AND ?)) AND (a.details LIKE ? OR a.actor_name LIKE ?) ORDER BY a.id DESC LIMIT ? OFFSET ?") (allExpenses,userId u,company && periodAccess,company && bankAccess,term,term,limit,offset)
 _ -> reject status404 "Financial report not found"
 where term="%"<>q<>"%"

invoiceRows :: Env -> T.Text -> Int -> Int -> IO [A.Value]
invoiceRows env = invoiceRowsScoped env Nothing Nothing

invoiceRowsScoped :: Env -> Maybe Int -> Maybe Int -> T.Text -> Int -> Int -> IO [A.Value]
invoiceRowsScoped env cid app q offset limit = jsonRows env ("SELECT json_object('id',i.id,'title','INV-'||printf('%06d',i.id)||' · '||c.full_name||CASE WHEN c.deleted_at IS NOT NULL THEN ' (Archived)' ELSE '' END||' · '||i.description,'currency',i.currency,'total',printf('%.2f',i.amount_minor/100.0),'paid',printf('%.2f',i.paid_minor/100.0),'balance',printf('%.2f',i.balance_minor/100.0),'dueDate',i.due_date,'overdueDays',CASE WHEN i.balance_minor>0 AND i.due_date<date('now',business_offset()) THEN CAST(julianday(date('now',business_offset()))-julianday(i.due_date) AS INTEGER) ELSE 0 END,'status',i.status,'revision',i.revision,'printUrl','/api/finance/print/invoices/'||i.id,'historyUrl','/work/payment-history?invoice='||i.id,'history',coalesce((SELECT json_group_array(json_object('id',p.id,'amount',printf('%.2f',p.amount_minor/100.0),'date',p.paid_on,'method',p.method,'reference',p.reference,'reason',p.reason,'actor',p.actor_name,'reversesId',p.reverses_id,'legacy',p.legacy)) FROM (SELECT * FROM invoice_payments WHERE invoice_id=i.id ORDER BY id DESC LIMIT 100) p),json('[]'))) FROM invoice_balances i JOIN clients c ON c.id=i.client_id WHERE (? IS NULL OR i.client_id=?) AND (? IS NULL OR i.case_id=?) AND i.client_id IN ("<>financialClients<>") AND i.status IN ('Issued','Paid') AND ((?='overdue' AND i.balance_minor>0 AND i.due_date<date('now',business_offset())) OR (?<>'overdue' AND (c.full_name LIKE ? OR i.description LIKE ? OR CAST(i.id AS TEXT)=?))) ORDER BY i.balance_minor>0 DESC,i.due_date,i.id LIMIT ? OFFSET ?") (cid,cid,app,app,q,q,"%"<>q<>"%","%"<>q<>"%",q,limit,offset)

paymentExport :: Env -> T.Text -> IO [A.Value]
paymentExport env q = jsonRows env ("SELECT json_object('id',p.id,'invoiceId',i.id,'client',c.full_name,'currency',i.currency,'amount',printf('%.2f',p.amount_minor/100.0),'paidOn',p.paid_on,'method',p.method,'reference',p.reference,'reason',p.reason,'reversesId',p.reverses_id,'legacy',p.legacy,'actor',p.actor_name) FROM invoice_payments p JOIN invoice_balances i ON i.id=p.invoice_id JOIN clients c ON c.id=i.client_id WHERE i.client_id IN ("<>financialClients<>") AND ((?='overdue' AND i.balance_minor>0 AND i.due_date<date('now',business_offset())) OR (?<>'overdue' AND (c.full_name LIKE ? OR i.description LIKE ? OR CAST(i.id AS TEXT)=?))) ORDER BY p.id LIMIT 10001") (q,q,"%"<>q<>"%","%"<>q<>"%",q)

expenseSelect :: Query
expenseSelect = "SELECT json_object('id',e.id,'title',e.supplier||' · '||e.description,'supplier',e.supplier,'description',e.description,'category',e.category,'currency',e.currency,'amount',printf('%.2f',e.amount_minor/100.0),'expenseOn',e.expense_on,'reference',e.reference,'status',e.status,'createdBy',e.created_name,'reviewNote',coalesce(e.review_note,''),'revision',e.revision,'files',(SELECT json_group_array(json_object('id',f.id,'filename',f.filename,'scanStatus',f.scan_status)) FROM financial_files f WHERE f.expense_id=e.id),'history',(SELECT json_group_array(json_object('id',p.id,'amount',printf('%.2f',p.amount_minor/100.0),'date',p.posted_on,'method',p.method,'reference',p.reference,'reason',p.reason,'actor',p.actor_name,'reversesId',p.reverses_id)) FROM expense_entries p WHERE p.expense_id=e.id)) FROM expenses e"

moneySummary :: Env -> User -> T.Text -> T.Text -> Bool -> S.ActionM [A.Value]
moneySummary env u start end includeExpenses = do
 allExpenses <- liftIO $ Access.hasPrivilege env u "expenses_approve"
 liftIO $ jsonRows env ("WITH totals AS (SELECT currency,sum(CASE WHEN date(issued_at,business_offset()) BETWEEN ? AND ? THEN amount_minor ELSE 0 END) invoiced,0 collected,0 expense,sum(balance_minor) outstanding,sum(CASE WHEN balance_minor>0 AND due_date<date('now',business_offset()) THEN balance_minor ELSE 0 END) overdue,0 legacy FROM invoice_balances WHERE status IN ('Issued','Paid') AND client_id IN ("<>financialClients<>") GROUP BY currency UNION ALL SELECT i.currency,0,sum(CASE WHEN p.paid_on BETWEEN ? AND ? THEN p.amount_minor ELSE 0 END),0,0,0,sum(CASE WHEN p.paid_on IS NULL THEN p.amount_minor ELSE 0 END) FROM invoice_payments p JOIN invoices i ON i.id=p.invoice_id WHERE i.client_id IN ("<>financialClients<>") GROUP BY i.currency UNION ALL SELECT e.currency,0,0,sum(p.amount_minor),0,0,0 FROM expense_entries p JOIN expenses e ON e.id=p.expense_id WHERE ? AND (? OR e.created_by=?) AND p.posted_on BETWEEN ? AND ? GROUP BY e.currency) SELECT json_object('kind','Currency','title',currency,'currency',currency,'invoiced',printf('%.2f',sum(invoiced)/100.0),'collected',printf('%.2f',sum(collected)/100.0),'expenses',printf('%.2f',sum(expense)/100.0),'net',printf('%.2f',(sum(collected)-sum(expense))/100.0),'outstanding',printf('%.2f',sum(outstanding)/100.0),'overdue',printf('%.2f',sum(overdue)/100.0),'legacyUndated',printf('%.2f',sum(legacy)/100.0)) FROM totals GROUP BY currency ORDER BY currency") (start,end,start,end,includeExpenses,allExpenses,userId u,start,end)

postingDate :: Env -> T.Text -> A.Value -> S.ActionM T.Text
postingDate env key input = do
 value <- dateField key True input
 date <- maybe (reject status400 "Choose a date") pure value
 today <- T.pack . show <$> liftIO businessDay
 when (date>today) $ reject status400 "Financial entries cannot be dated in the future"
 requireOpenDate env date
 pure date

paymentAction :: Env -> User -> T.Text -> A.Value -> S.ActionM ()
paymentAction env u action input = do
 iid <- intField "id" input
 rows <- liftIO $ query (envConn env) ("SELECT client_id,amount_minor,paid_minor,balance_minor,status,revision FROM invoice_balances WHERE id=? AND client_id IN ("<>financialClients<>")") (Only iid) :: S.ActionM [(Int,Int,Int,Int,T.Text,Int)]
 (_,_,_,balance,status,rev) <- case rows of [row] -> pure row; _ -> reject status404 "Invoice not found"
 checkOwnRevision rev input
 unless (status `elem` ["Issued","Paid"]) $ reject status400 "Issue the invoice before recording payments"
 date <- postingDate env "paidOn" input
 reference <- boundedOptional "reference" 255 input
 (amount,method,reason,reversal) <- if action=="record" then do
  amount <- maybe (reject status400 "Enter a positive amount with at most two decimal places") pure (amountMinor(field "amount" input))
  when (amount>balance) $ reject status400 "Payment exceeds the outstanding balance"
  method <- choice "method" ["Cash","Bank transfer","Card","Cheque","Other"] input
  pure (amount,method,"",Nothing)
  else do
   pid <- intField "payment" input
   reason <- bounded "reason" 1000 input
   receipts <- liftIO $ query (envConn env) "SELECT amount_minor,paid_on FROM invoice_payments WHERE id=? AND invoice_id=? AND reverses_id IS NULL AND NOT EXISTS(SELECT 1 FROM invoice_payments r WHERE r.reverses_id=invoice_payments.id)" (pid,iid) :: S.ActionM [(Int,Maybe T.Text)]
   case receipts of
    [(amount,paid)] -> do
     when (maybe False (>date) paid) $ reject status400 "Reversal date cannot precede the payment"
     pure (-amount,"Reversal",reason,Just pid)
    _ -> reject status409 "Select an unreversed receipt belonging to this invoice"
 liftIO $ do
  void $ execute (envConn env) "INSERT INTO invoice_payments(invoice_id,amount_minor,paid_on,method,reference,reason,reverses_id,actor_id,actor_name) VALUES (?,?,?,?,?,?,?,?,?)" (iid,amount,date,method,reference,reason,reversal,userId u,userName u)
  applications<-query (envConn env) "SELECT client_id,case_id,currency FROM invoices WHERE id=?" (Only iid) :: IO [(Int,Maybe Int,T.Text)]
  void $ forM applications $ \(cid,app,currency)->do
   let kind=if action=="record" then "payment.received" else "payment.reversed"
       title=(if action=="record" then "Payment received: " else "Payment reversed: ")<>currency<>" "<>Journey.minorText(abs amount)<>" · INV-"<>T.pack(show iid)
   recordHistory env u Nothing (Just cid) app kind title
   void $ forM app $ \application->Journey.notify env cid application title ("payment:"<>T.pack(show iid)<>":"<>T.pack(show(rev+1)))
  pure ()

boundedOptional :: T.Text -> Int -> A.Value -> S.ActionM T.Text
boundedOptional key limit input = do
 let value=field key input
 when (T.length value>limit) $ reject status400 (key<>" is too long")
 pure value

expenseAction :: Env -> User -> T.Text -> A.Value -> S.ActionM ()
expenseAction env u action input
 | action=="submit" = do
  supplier <- bounded "supplier" 255 input
  description <- bounded "description" 1000 input
  category <- bounded "category" 100 input
  currency <- choice "currency" ["PHP","USD","EUR","GBP","AUD","CAD","NZD"] input
  amount <- maybe (reject status400 "Enter a positive expense with at most two decimal places") pure (amountMinor(field "amount" input))
  date <- postingDate env "expenseOn" input
  reference <- boundedOptional "reference" 255 input
  -- A form key makes retries of expense submission idempotent.
  key <- bounded "submissionKey" 100 input
  prior <- liftIO $ query (envConn env) "SELECT expense_id FROM expense_submissions WHERE actor_id=? AND submission_key=?" (userId u,key) :: S.ActionM [Only Int]
  unless (null prior) $ reject status409 "This expense was already submitted. Reload the expense list."
  liftIO $ do
   [Only eid] <- query (envConn env) "INSERT INTO expenses(supplier,description,category,currency,amount_minor,expense_on,reference,created_by,created_name) VALUES (?,?,?,?,?,?,?,?,?) RETURNING id" (supplier,description,category,currency,amount,date,reference,userId u,userName u) :: IO [Only Int]
   void $ execute (envConn env) "INSERT INTO expense_submissions(actor_id,submission_key,expense_id) VALUES (?,?,?)" (userId u,key,eid)
   auditExpense env u eid "submitted" (A.object ["supplier".=supplier,"amountMinor".=amount,"currency".=currency])
 | otherwise = do
  eid <- intField "id" input
  allExpenses <- liftIO $ Access.hasPrivilege env u "expenses_approve"
  rows <- liftIO $ query (envConn env) "SELECT status,revision,created_by,amount_minor FROM expenses WHERE id=? AND (? OR created_by=?)" (eid,allExpenses,userId u) :: S.ActionM [(T.Text,Int,Int,Int)]
  (status,rev,creator,amount) <- case rows of [row] -> pure row; _ -> reject status404 "Expense not found"
  checkOwnRevision rev input
  case action of
   "approve" -> review eid status creator "Approved"
   "reject" -> review eid status creator "Rejected"
   "pay" -> do
    unless (status=="Approved") $ reject status409 "Only approved expenses can be paid"
    date <- postingDate env "paidOn" input
    method <- choice "method" ["Cash","Bank transfer","Card","Cheque","Other"] input
    reference <- boundedOptional "paymentReference" 255 input
    liftIO $ void $ execute (envConn env) "INSERT INTO expense_entries(expense_id,amount_minor,posted_on,method,reference,actor_id,actor_name) VALUES (?,?,?,?,?,?,?)" (eid,amount,date,method,reference,userId u,userName u)
   "reverse-expense" -> do
    unless (status=="Paid") $ reject status409 "Only paid expenses can be reversed"
    date <- postingDate env "paidOn" input
    reason <- bounded "reason" 1000 input
    entries <- liftIO $ query (envConn env) "SELECT id,posted_on FROM expense_entries WHERE expense_id=? AND reverses_id IS NULL" (Only eid) :: S.ActionM [(Int,T.Text)]
    case entries of
     [(pid,originalDate)] -> do
      when (date<originalDate) $ reject status400 "Reversal date cannot precede the payment"
      liftIO $ void $ execute (envConn env) "INSERT INTO expense_entries(expense_id,amount_minor,posted_on,method,reason,reverses_id,actor_id,actor_name) VALUES (?,?,?,'Reversal',?,?,?,?)" (eid,-amount,date,reason,pid,userId u,userName u)
     _ -> reject status409 "Expense payment not found"
   _ -> reject status404 "Expense action not found"
 where
 review eid status creator next = do
  unless (status=="Pending") $ reject status409 "Only pending expenses can be reviewed"
  when (next=="Approved" && creator==userId u && userRole u/="admin") $ reject status403 "Another approver must approve your expense"
  note <- if next=="Rejected" then bounded "reason" 1000 input else boundedOptional "reason" 1000 input
  liftIO $ do
   void $ execute (envConn env) "UPDATE expenses SET status=?,reviewed_by=?,review_note=?,revision=revision+1 WHERE id=?" (next,userId u,note,eid)
   auditExpense env u eid next (A.object ["note".=note])

auditExpense :: Env -> User -> Int -> T.Text -> A.Value -> IO ()
auditExpense env u eid action details = void $ execute (envConn env) "INSERT INTO finance_audit(kind,record_id,action,details,actor_id,actor_name) VALUES ('expense',?,?,?,?,?)" (eid,action,TE.decodeUtf8(BL.toStrict(A.encode details)),userId u,userName u)
