{-# LANGUAGE OverloadedStrings #-}
module ECC.FinanceControls (routes) where

import Control.Monad (forM, forM_, unless, void, when)
import Control.Monad.IO.Class (liftIO)
import qualified Data.Aeson as A
import Data.Aeson ((.=))
import qualified Data.ByteString as B
import qualified Data.ByteString.Lazy as BL
import qualified Data.Text as T
import qualified Data.Text.Lazy as TL
import qualified Data.Text.Encoding as TE
import Data.List (nub, elemIndex)
import Data.Time (Day,  defaultTimeLocale, parseTimeM)
import Network.HTTP.Types hiding (Query)
import Network.Wai.Parse (FileInfo(..))
import qualified Web.Scotty as S
import ECC.Auth (tokenHash)
import ECC.DB (Env(..))
import ECC.Clock (businessDay)
import ECC.Models
import ECC.Store
import qualified ECC.Journey as Journey
import ECC.Security (reject)
import ECC.WorkflowSupport
import ECC.FinanceCommon
import ECC.Money (amountMinor)
import qualified ECC.Access as Access
import qualified ECC.Csv as Csv

type Guard = (User -> S.ActionM ()) -> S.ActionM ()

routes :: Env -> Guard -> Guard -> S.ScottyM ()
routes env reader writer = do
 S.get "/api/workspace/payment-history" $ reader $ \u -> do
  Access.requirePrivilege env u "finance_view"
  q <- maybe "" id <$> (S.queryParamMaybe "q" :: S.ActionM (Maybe T.Text))
  offset <- max 0 . maybe 0 id <$> (S.queryParamMaybe "offset" :: S.ActionM (Maybe Int))
  invoice <- S.queryParamMaybe "invoice" :: S.ActionM (Maybe Int)
  let term="%"<>q<>"%"
  rows <- liftIO $ jsonRows env ("SELECT json_object('id',i.id,'payment',p.id,'title','Receipt '||p.id||' · INV-'||i.id||' · '||c.full_name,'revision',i.revision,'currency',i.currency,'amount',printf('%.2f',p.amount_minor/100.0),'paidOn',coalesce(p.paid_on,''),'method',p.method,'reference',p.reference,'reason',p.reason,'actor',p.actor_name,'reversesId',p.reverses_id,'reversed',EXISTS(SELECT 1 FROM invoice_payments r WHERE r.reverses_id=p.id),'printUrl','/api/finance/print/payments/'||p.id,'duplicateReference',p.reference<>'' AND p.reverses_id IS NULL AND (SELECT count(*) FROM invoice_payments x JOIN invoices xi ON xi.id=x.invoice_id WHERE xi.client_id IN ("<>financialClients<>") AND x.reverses_id IS NULL AND lower(trim(x.reference))=lower(trim(p.reference)))>1) FROM invoice_payments p JOIN invoices i ON i.id=p.invoice_id JOIN clients c ON c.id=i.client_id WHERE i.client_id IN ("<>financialClients<>") AND (? IS NULL OR i.id=?) AND (c.full_name LIKE ? OR p.reference LIKE ? OR p.actor_name LIKE ? OR CAST(p.id AS TEXT)=?) ORDER BY p.id DESC LIMIT 50 OFFSET ?") (invoice,invoice,term,term,term,q,offset)
  record <- liftIO $ Access.hasPrivilege env u "payments_record"
  export <- liftIO $ Access.hasPrivilege env u "export"
  S.json (A.object ["rows".=rows,"options".= ([]::[A.Value]),"permissions".=A.object["reverse".=(record && userRole u/="viewer"),"export".=export]])
 S.get "/api/workspace/periods" $ reader $ \u -> do
  companyPermission env u "finance_periods"
  rows <- liftIO $ jsonRows env "SELECT json_object('id',month,'month',month,'title',month,'status',CASE WHEN closed=1 THEN 'Closed' ELSE 'Open' END,'revision',revision,'reason',reason,'changedBy',changed_name,'changedAt',changed_at,'snapshot',json(snapshot)) FROM financial_periods ORDER BY month DESC LIMIT 120" ()
  S.json (A.object ["rows".=rows,"options".= ([]::[A.Value]),"permissions".=A.object["close".=True,"reopen".=True]])
 forM_ ["close","reopen"] $ \action -> S.post (S.capture ("/api/workspace/periods/"<>T.unpack action)) $ writer $ \u -> do
  companyPermission env u "finance_periods"
  input <- bodyObject
  month <- bounded "month" 7 input
  unless (T.length month==7 && (parseTimeM True defaultTimeLocale "%F" (T.unpack(month<>"-01")) :: Maybe Day)/=Nothing) $ reject status400 "Choose a valid month (YYYY-MM)"
  today <- T.pack . show <$> liftIO businessDay
  when (action=="close" && month>=T.take 7 today) $ reject status400 "Only completed months can be closed"
  reason <- bounded "reason" 1000 input
  old <- liftIO $ query (envConn env) "SELECT closed,revision FROM financial_periods WHERE month=?" (Only month) :: S.ActionM [(Bool,Int)]
  let (closed,rev)=case old of [row]->row; _->(False,0)
  checkOwnRevision rev input
  when ((action=="close" && closed) || (action=="reopen" && not closed)) $ reject status409 "The month is already in that state"
  when (action=="close") $ do
   [Only unmatched] <- liftIO $ query (envConn env) "SELECT count(*) FROM bank_lines b WHERE substr(b.posted_on,1,7)=? AND NOT EXISTS(SELECT 1 FROM bank_matches m WHERE m.bank_line_id=b.id)" (Only month) :: S.ActionM [Only Int]
   when (unmatched>0) $ reject status409 "Reconcile or explicitly exclude all imported bank entries in this month first"
  snapshot <- if action=="close" then liftIO $ jsonRows env "WITH entries AS (SELECT currency,amount_minor invoiced,0 receipts,0 expenses FROM invoices WHERE strftime('%Y-%m',issued_at,business_offset())=? AND status IN ('Issued','Paid') UNION ALL SELECT i.currency,0,p.amount_minor,0 FROM invoice_payments p JOIN invoices i ON i.id=p.invoice_id WHERE substr(p.paid_on,1,7)=? UNION ALL SELECT e.currency,0,0,p.amount_minor FROM expense_entries p JOIN expenses e ON e.id=p.expense_id WHERE substr(p.posted_on,1,7)=?) SELECT json_object('currency',currency,'invoiced',printf('%.2f',sum(invoiced)/100.0),'receipts',printf('%.2f',sum(receipts)/100.0),'expenses',printf('%.2f',sum(expenses)/100.0)) FROM entries GROUP BY currency ORDER BY currency" (month,month,month) else pure []
  liftIO $ do
   void $ execute (envConn env) "INSERT INTO financial_periods(month,closed,reason,snapshot,changed_by,changed_name) VALUES (?,?,?,?,?,?) ON CONFLICT(month) DO UPDATE SET closed=excluded.closed,reason=excluded.reason,snapshot=CASE WHEN excluded.closed=1 THEN excluded.snapshot ELSE financial_periods.snapshot END,changed_by=excluded.changed_by,changed_name=excluded.changed_name,changed_at=datetime('now'),revision=financial_periods.revision+1" (month,action=="close",reason,TE.decodeUtf8(BL.toStrict(A.encode snapshot)),userId u,userName u)
   auditControl env u "period" 0 action (A.object["month".=month,"reason".=reason,"snapshot".=snapshot])
  S.json(A.object["message".=(if action=="close" then "Month closed and totals saved"::T.Text else "Month reopened; the reason is in the financial audit")])
 S.get "/api/workspace/reconciliation" $ reader $ \u -> do
  companyPermission env u "finance_reconcile"
  q <- maybe "" id <$> (S.queryParamMaybe "q" :: S.ActionM (Maybe T.Text))
  offset <- max 0 . maybe 0 id <$> (S.queryParamMaybe "offset" :: S.ActionM (Maybe Int))
  rows <- liftIO $ jsonRows env "SELECT json_object('id',b.id,'title',b.account||' · '||b.transaction_id,'currency',b.currency,'amount',printf('%.2f',b.amount_minor/100.0),'postedOn',b.posted_on,'reference',b.reference,'description',b.description,'revision',b.revision,'status',CASE WHEN m.ignored=1 THEN 'Excluded' WHEN m.bank_line_id IS NOT NULL THEN 'Matched' ELSE 'Unmatched' END,'match',CASE WHEN m.payment_id IS NOT NULL THEN 'payment:'||m.payment_id WHEN m.expense_entry_id IS NOT NULL THEN 'expense:'||m.expense_entry_id ELSE '' END,'reason',coalesce(m.reason,'')) FROM bank_lines b LEFT JOIN bank_matches m ON m.bank_line_id=b.id WHERE b.account LIKE ? OR b.reference LIKE ? OR b.transaction_id LIKE ? ORDER BY b.posted_on DESC,b.id DESC LIMIT 50 OFFSET ?" ("%"<>q<>"%","%"<>q<>"%","%"<>q<>"%",offset)
  S.json(A.object["rows".=rows,"options".= ([]::[A.Value]),"permissions".=A.object["import".=True,"match".=True,"unmatch".=True,"ignore".=True]])
 S.get "/api/workspace/reconciliation/candidates/:id" $ reader $ \u -> do
  companyPermission env u "finance_reconcile"
  bid <- S.pathParam "id"
  q <- maybe "" id <$> (S.queryParamMaybe "q" :: S.ActionM (Maybe T.Text))
  offset <- max 0 . maybe 0 id <$> (S.queryParamMaybe "offset" :: S.ActionM (Maybe Int))
  rows <- liftIO $ jsonRows env "WITH candidates AS (SELECT 'payment:'||p.id value,'Receipt '||p.id||' · INV-'||p.invoice_id||' · '||p.reference label,p.paid_on date,p.reference reference,i.currency currency,p.amount_minor amount FROM invoice_payments p JOIN invoices i ON i.id=p.invoice_id WHERE NOT EXISTS(SELECT 1 FROM bank_matches m WHERE m.payment_id=p.id) AND NOT EXISTS(SELECT 1 FROM invoice_payments r WHERE r.reverses_id=p.id) UNION ALL SELECT 'expense:'||p.id,'Expense payment '||p.id||' · '||e.supplier||' · '||p.reference,p.posted_on,p.reference,e.currency,-p.amount_minor FROM expense_entries p JOIN expenses e ON e.id=p.expense_id WHERE NOT EXISTS(SELECT 1 FROM bank_matches m WHERE m.expense_entry_id=p.id) AND NOT EXISTS(SELECT 1 FROM expense_entries r WHERE r.reverses_id=p.id)) SELECT json_object('title',c.label,'value',c.value,'label',c.label,'date',c.date,'reference',c.reference) FROM candidates c JOIN bank_lines b ON b.id=? AND b.amount_minor=c.amount AND b.currency=c.currency WHERE c.label LIKE ? ORDER BY c.date DESC,c.value LIMIT 50 OFFSET ?" (bid::Int,"%"<>q<>"%",offset)
  S.json(A.object["rows".=rows])
 S.post "/api/workspace/reconciliation/import" $ writer $ \u -> do
  companyPermission env u "finance_reconcile"
  input <- bodyObject
  importStatement env u input
 forM_ ["match","unmatch","ignore"] $ \action -> S.post (S.capture ("/api/workspace/reconciliation/"<>T.unpack action)) $ writer $ \u -> do
  companyPermission env u "finance_reconcile"
  input <- bodyObject
  bid <- intField "id" input
  rows <- liftIO $ query (envConn env) "SELECT posted_on,revision FROM bank_lines WHERE id=?" (Only bid) :: S.ActionM [(T.Text,Int)]
  (date,rev) <- case rows of [row]->pure row; _->reject status404 "Bank transaction not found"
  checkOwnRevision rev input
  requireOpenDate env date
  reason <- bounded "reason" 1000 input
  matches <- liftIO $ query (envConn env) "SELECT bank_line_id FROM bank_matches WHERE bank_line_id=?" (Only bid) :: S.ActionM [Only Int]
  if action=="unmatch" then do
   when(null matches) $ reject status409 "This transaction is not matched or excluded"
   liftIO $ void $ execute (envConn env) "DELETE FROM bank_matches WHERE bank_line_id=?" (Only bid)
  else do
   unless(null matches) $ reject status409 "Unmatch the current reconciliation first"
   (payment,expense) <- if action=="ignore" then pure(Nothing,Nothing) else do
    selected <- needed "match" input
    case T.splitOn ":" selected of
     [kind,sid] | Just ident <- number "id" (A.object["id".=sid]), ident>0 -> case kind of
      "payment"->pure(Just ident,Nothing)
      "expense"->pure(Nothing,Just ident)
      _->reject status400 "Select a receipt or expense payment"
     _->reject status400 "Select a receipt or expense payment"
   liftIO $ void $ execute (envConn env) "INSERT INTO bank_matches(bank_line_id,payment_id,expense_entry_id,ignored,reason,actor_id,actor_name) VALUES (?,?,?,?,?,?,?)" (bid,payment,expense,action=="ignore",reason,userId u,userName u)
  liftIO $ do
   void $ execute (envConn env) "UPDATE bank_lines SET revision=revision+1 WHERE id=?" (Only bid)
   auditControl env u "bank" bid action (A.object["reason".=reason,"match".=field "match" input])
  S.json(A.object["message".=("Bank reconciliation saved"::T.Text)])
 attachmentRoutes env reader writer
 printRoutes env reader

importStatement :: Env -> User -> A.Value -> S.ActionM ()
importStatement env u input = do
 account <- T.toCaseFold <$> bounded "account" 100 input
 currency <- choice "currency" ["PHP","USD","EUR","GBP","AUD","CAD","NZD"] input
 csv <- bounded "csv" 20000 input
 let parsed=Csv.parseCsv csv
 (headers,rawRows) <- case parsed of h:rs | not(null rs),length rs<=1000 ->pure(map(T.toLower . T.strip) h,rs); _->reject status400 "Paste a CSV header and 1–1000 transaction rows"
 unless(length(nub headers)==length headers && all (`elem` headers) ["transactionid","date","amount","reference","description"]) $ reject status400 "CSV columns: transactionId,date,amount,reference,description"
 rows <- forM rawRows $ \row -> do
  let get key=case elemIndex key headers of Just i | i<length row ->T.strip(row!!i); _->""
      date=get "date"; rawAmount=get "amount"
  unless(length row==length headers) $ reject status400 "Every CSV row must match the header"
  let signed=case T.stripPrefix "-" rawAmount of Just value->negate <$> amountMinor value; Nothing->amountMinor (maybe rawAmount id(T.stripPrefix "+" rawAmount))
  amount <- maybe(reject status400 "Bank amounts must be nonzero decimals with at most two places") pure signed
  unless((parseTimeM True defaultTimeLocale "%F" (T.unpack date) :: Maybe Day)/=Nothing) $ reject status400 "Bank dates must be YYYY-MM-DD"
  today <- T.pack . show <$> liftIO businessDay
  when(date>today) $ reject status400 "Bank transactions cannot have a future date"
  requireOpenDate env date
  let ident=get "transactionid"; reference=get "reference"; description=get "description"
  when(T.null ident || any ((>255).T.length) [ident,reference,description]) $ reject status400 "Transaction IDs are required; fields must be at most 255 characters"
  old <- liftIO $ query (envConn env) "SELECT posted_on,amount_minor,reference,description FROM bank_lines WHERE account=? AND currency=? AND transaction_id=?" (account,currency,ident) :: S.ActionM [(T.Text,Int,T.Text,T.Text)]
  unless(null old || old==[(date,amount,reference,description)]) $ reject status409 "An imported transaction ID has conflicting data"
  pure(ident,date,amount,reference,description,null old)
 unless(length(nub [ident|(ident,_,_,_,_,_)<-rows])==length rows) $ reject status400 "The CSV repeats a transaction ID"
 let fresh=[(ident,date,amount,reference,description)|(ident,date,amount,reference,description,True)<-rows]
 if null fresh then S.json(A.object["message".=("No new transactions; matching imports were already present"::T.Text)]) else do
  liftIO $ do
   [Only sid] <- query (envConn env) "INSERT INTO bank_statements(account,currency,import_hash,imported_by) VALUES (?,?,?,?) RETURNING id" (account,currency,tokenHash(TE.encodeUtf8(account<>"\n"<>currency<>"\n"<>csv)),userId u) :: IO [Only Int]
   forM_ fresh $ \(ident,date,amount,reference,description) ->void $ execute (envConn env) "INSERT INTO bank_lines(statement_id,account,currency,transaction_id,posted_on,amount_minor,reference,description) VALUES (?,?,?,?,?,?,?,?)" (sid,account,currency,ident,date,amount,reference,description)
   auditControl env u "bank" sid "import" (A.object["account".=account,"currency".=currency,"newTransactions".=length fresh])
  S.json(A.object["message".=("Bank statement imported; existing identical transactions were skipped"::T.Text),"imported".=length fresh])

attachmentRoutes :: Env -> Guard -> Guard -> S.ScottyM ()
attachmentRoutes env reader writer = do
 S.post "/api/finance/expenses/:id/attachments" $ writer $ \u -> do
  Access.requirePrivilege env u "expenses_record"
  eid <- S.pathParam "id"
  rev <- expenseAccess env u eid
  expected <- S.formParam "expectedRevision" :: S.ActionM Int
  checkOwnRevision rev (A.object["expectedRevision".=expected])
  [Only count] <- liftIO $ query (envConn env) "SELECT count(*) FROM financial_files WHERE expense_id=?" (Only eid) :: S.ActionM [Only Int]
  when(count>=20) $ reject status400 "An expense can have at most 20 supporting files"
  files <- S.files
  case files of
   [(_,fi)] -> do
    let bytes=BL.toStrict(fileContent fi)
        filename=T.take 200(T.filter(\c->c `notElem` ['\r','\n','/','\\','\0','"']) (TE.decodeUtf8With(\_ _->Just '_')(fileName fi)))
        recognized=any (`B.isPrefixOf` bytes) ["%PDF-",B.pack[137,80,78,71,13,10,26,10],B.pack[255,216,255]]
    when(B.null bytes || B.length bytes>10*1024*1024 || T.null filename || not recognized) $ reject status400 "Choose a PDF, PNG or JPEG up to 10 MB"
    liftIO $ do
     [Only fid] <- query (envConn env) "INSERT INTO financial_files(expense_id,filename,content,size,uploaded_by,uploaded_name) VALUES (?,?,?,?,?,?) RETURNING id" (eid,filename,Binary bytes,B.length bytes,userId u,userName u) :: IO [Only Int]
     void $ execute (envConn env) "UPDATE expenses SET revision=revision+1 WHERE id=?" (Only eid)
     auditControl env u "expense" eid "attachment" (A.object["fileId".=fid,"filename".=filename])
    S.json(A.object["message".=("Supporting file uploaded and quarantined for scanning"::T.Text)])
   _->reject status400 "Choose exactly one file"
 S.get "/api/finance/attachments/:id" $ reader $ \u -> do
  Access.requirePrivilege env u "download"
  fid <- S.pathParam "id"
  rows <- liftIO $ query (envConn env) "SELECT expense_id,filename,content,scan_status FROM financial_files WHERE id=?" (Only(fid::Int)) :: S.ActionM [(Int,T.Text,Binary B.ByteString,T.Text)]
  case rows of
   [(eid,name,Binary bytes,scan)] -> do
    _ <- expenseAccess env u eid
    unless(scan=="Clean") $ reject (mkStatus 423 "Locked") "This supporting file is quarantined until scanning succeeds"
    S.setHeader "Content-Type" "application/octet-stream"
    S.setHeader "Content-Disposition" ("attachment; filename=\""<>TL.fromStrict name<>"\"")
    S.raw(BL.fromStrict bytes)
   _->reject status404 "Supporting file not found"
 S.post "/api/finance/attachments/:id/rescan" $ writer $ \u -> do
  companyPermission env u "expenses_approve"
  fid <- S.pathParam "id"
  n <- liftIO $ execute (envConn env) "UPDATE financial_files SET scan_status='Pending',scan_attempts=0,scan_lease=NULL,scan_until=NULL WHERE id=? AND scan_status='Error'" (Only(fid::Int))
  unless(n==1) $ reject status409 "Only failed scans can be queued again"
  S.json(A.object["message".=("Supporting file queued for scanning"::T.Text)])

printRoutes :: Env -> Guard -> S.ScottyM ()
printRoutes env reader = do
 S.get "/api/finance/print/invoices/:id" $ reader $ \u -> do
  Access.requirePrivilege env u "finance_view"
  Access.requirePrivilege env u "export"
  iid <- S.pathParam "id"
  rows <- liftIO $ query (envConn env) ("SELECT c.full_name,i.description,i.currency,i.amount_minor,i.paid_minor,i.balance_minor,i.due_date,i.status FROM invoice_balances i JOIN clients c ON c.id=i.client_id WHERE i.id=? AND i.client_id IN ("<>financialClients<>")") (Only(iid::Int)) :: S.ActionM [(T.Text,T.Text,T.Text,Int,Int,Int,T.Text,T.Text)]
  case rows of
   [(name,description,currency,total,paid,balance,due,status)] -> do
    breakdown<-liftIO $ Journey.invoiceBreakdown env iid
    printPage ("Invoice INV-"<>T.pack(show iid)) [("Itemized charges",breakdown),("Student",name),("Description",description),("Currency",currency),("Invoice total",money total),("Net payments",money paid),("Outstanding balance",money balance),("Due date",due),("Status",status)]
   _->reject status404 "Invoice not found"
 S.get "/api/finance/print/payments/:id" $ reader $ \u -> do
  Access.requirePrivilege env u "finance_view"
  Access.requirePrivilege env u "export"
  pid <- S.pathParam "id"
  rows <- liftIO $ query (envConn env) ("SELECT p.invoice_id,c.full_name,i.currency,p.amount_minor,coalesce(p.paid_on,'Unknown — legacy payment'),p.method,p.reference,p.actor_name,p.reason FROM invoice_payments p JOIN invoices i ON i.id=p.invoice_id JOIN clients c ON c.id=i.client_id WHERE p.id=? AND i.client_id IN ("<>financialClients<>")") (Only(pid::Int)) :: S.ActionM [(Int,T.Text,T.Text,Int,T.Text,T.Text,T.Text,T.Text,T.Text)]
  case rows of
   [(iid,name,currency,amount,date,method,reference,actor,reason)] -> printPage ((if amount>0 then "Payment acknowledgement #" else "Payment reversal #")<>T.pack(show pid)) [("Invoice","INV-"<>T.pack(show iid)),("Student",name),("Currency",currency),("Amount",money amount),("Posting date",date),("Method",method),("Reference",reference),("Recorded by",actor),("Reason",reason)]
   _->reject status404 "Payment not found"

money :: Int -> T.Text
money amount = (if amount<0 then "-" else "")<>T.pack(show(abs amount `div`100))<>"."<>T.justifyRight 2 '0' (T.pack(show(abs amount `mod`100)))

printPage :: T.Text -> [(T.Text,T.Text)] -> S.ActionM ()
printPage title fields = do
 let escape=T.concatMap(\c->case c of '&'->"&amp;"; '<'->"&lt;"; '>'->"&gt;"; '"'->"&quot;"; '\''->"&#39;"; _->T.singleton c)
     html="<!doctype html><html lang=\"en\"><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width,initial-scale=1\"><title>"<>escape title<>"</title><style>body{font:16px sans-serif;max-width:800px;margin:32px auto;padding:16px;color:#172033}dt{font-weight:bold;margin-top:16px}dd{margin:4px 0;white-space:pre-wrap;overflow-wrap:anywhere}button{padding:12px}@media print{button{display:none}body{margin:0}}</style><script src=\"/finance-print.js\" defer></script></head><body><p>ECC CRM</p><h1>"<>escape title<>"</h1><dl>"<>T.concat["<dt>"<>escape key<>"</dt><dd>"<>escape value<>"</dd>"|(key,value)<-fields]<>"</dl><button id=\"print-document\" type=\"button\">Print / Save as PDF</button><p>"<>"This document acknowledges a CRM record; it does not initiate a payment."<>"</p></body></html>"
 S.setHeader "Content-Type" "text/html; charset=utf-8"
 S.raw(BL.fromStrict(TE.encodeUtf8 html))
