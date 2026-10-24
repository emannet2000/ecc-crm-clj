{-# LANGUAGE OverloadedStrings #-}
-- | Connected additions to the existing Client -> Case workflow.
module ECC.Journey where

import Control.Monad (forM, forM_, unless, void, when)
import Control.Monad.IO.Class (liftIO)
import qualified Data.Aeson as A
import qualified Data.ByteString.Char8 as BC
import qualified Data.ByteString.Lazy as BL
import Data.Char (ord)
import Data.List (mapAccumL)
import Data.Aeson ((.=))
import qualified Data.Text as T
import qualified Data.Text.Lazy as TL
import Data.Time (UTCTime, defaultTimeLocale, parseTimeM, formatTime)
import Network.HTTP.Types hiding (Query)
import qualified Web.Scotty as S
import ECC.DB (Env(..))
import ECC.Models
import ECC.Store
import ECC.WorkflowSupport
import ECC.Security (reject)
import qualified ECC.Access as Access
import qualified ECC.Money as Money
import qualified ECC.Csv as Csv

commercialSection :: T.Text -> Bool
commercialSection section = section `elem` ["proposals","contracts","payment-details"]

-- A commercial action always belongs to a particular application, including
-- when the staff member has opened the whole-client workspace.
applicationOwner :: Env -> User -> A.Value -> S.ActionM (Int,Int)
applicationOwner env u input = do
 (_,mc,cs)<-owner env u input
 cid<-maybe (reject status400 "Choose a client application") pure mc
 app<-case cs of
  Just i->pure i
  Nothing->do
   rows<-liftIO $ query (envConn env) "SELECT id FROM cases WHERE client_id=? ORDER BY id" (Only cid) :: S.ActionM [Only Int]
   case rows of [Only i]->pure i; _->reject status400 "Select an application in Scope first"
 pure(cid,app)

commercialRows :: Env -> User -> T.Text -> Maybe Int -> Maybe Int -> T.Text -> Int -> S.ActionM [A.Value]
commercialRows env u section cid app q offset = do
 Access.requirePrivilege env u "finance_view"
 liftIO $ if section=="payment-details"
  then jsonRows env ("SELECT json_object('id',p.id,'title','Payment instructions · INV-'||p.invoice_id,'owner','case:'||p.case_id,'invoice',p.invoice_id,'bank',p.bank,'accountName',p.account_name,'accountNumber',p.account_number,'method',p.method,'instructions',p.instructions,'clientVisible',p.client_visible=1,'revision',p.revision) FROM payment_instructions p WHERE p.client_id IN ("<>visibleClients<>") AND (? IS NULL OR p.client_id=?) AND (? IS NULL OR p.case_id=?) ORDER BY p.id DESC LIMIT 50 OFFSET ?") (cid,cid,app,app,offset)
  else jsonRows env ("SELECT json_object('id',d.id,'title',d.title,'number',CASE WHEN kind='proposal' THEN 'PR-' ELSE 'CT-' END||printf('%06d',d.id),'owner','case:'||d.case_id,'body',d.body,'currency',d.currency,'fee',printf('%.2f',d.fee_minor/100.0),'thirdParty',printf('%.2f',d.third_party_minor/100.0),'otherCharges',printf('%.2f',d.other_minor/100.0),'discount',printf('%.2f',d.discount_minor/100.0),'tax',printf('%.2f',d.tax_minor/100.0),'total',printf('%.2f',d.total_minor/100.0),'validUntil',d.valid_until,'status',CASE WHEN d.status IN ('Issued','Viewed') AND d.valid_until<date('now',business_offset()) THEN 'Expired' ELSE d.status END,'acceptedAt',d.accepted_at,'revision',d.revision) FROM commercial_documents d WHERE d.kind=? AND d.client_id IN ("<>visibleClients<>") AND (? IS NULL OR d.client_id=?) AND (? IS NULL OR d.case_id=?) AND d.title LIKE ? ORDER BY d.id DESC LIMIT 50 OFFSET ?") (if section=="proposals" then "proposal"::T.Text else "contract",cid,cid,app,app,"%"<>q<>"%",offset)

commercialAction :: Env -> User -> T.Text -> T.Text -> A.Value -> S.ActionM A.Value
commercialAction env u section action input = do
 Access.requirePrivilege env u "finance_view"
 (cid,app)<-applicationOwner env u input
 if section=="payment-details" then saveInstructions cid app else saveCommercial cid app
 where
  saveInstructions cid app = do
   unless(action=="save") $ reject status404 "Action not found"
   invoice<-intField "invoice" input
   allowed<-liftIO $ query (envConn env) "SELECT id FROM invoices WHERE id=? AND client_id=? AND case_id=? AND status IN ('Issued','Paid')" (invoice,cid,app) :: S.ActionM [Only Int]
   when(null allowed) $ reject status400 "Choose an issued invoice belonging to this application"
   bank<-bounded "bank" 200 input
   accountName<-bounded "accountName" 200 input
   accountNumber<-bounded "accountNumber" 100 input
   method<-bounded "method" 100 input
   instructions<-bounded "instructions" 5000 input
   existing<-liftIO $ query (envConn env) "SELECT id,revision,case_id FROM payment_instructions WHERE invoice_id=?" (Only invoice) :: S.ActionM [(Int,Int,Int)]
   forM_ existing $ \(ident,rev,oldApp)->do
    when(number "id" input/=Just ident || oldApp/=app) $ reject status409 "Select the existing instructions for this invoice"
    checkOwnRevision rev input
   let visible=field "clientVisible" input=="true"
   liftIO $ do
    void $ execute (envConn env) "INSERT INTO payment_instructions(client_id,case_id,invoice_id,bank,account_name,account_number,method,instructions,client_visible,created_by) VALUES (?,?,?,?,?,?,?,?,?,?) ON CONFLICT(invoice_id) DO UPDATE SET bank=excluded.bank,account_name=excluded.account_name,account_number=excluded.account_number,method=excluded.method,instructions=excluded.instructions,client_visible=excluded.client_visible,revision=payment_instructions.revision+1" (cid,app,invoice,bank,accountName,accountNumber,method,instructions,visible,userId u)
    recordHistory env u Nothing (Just cid) (Just app) "payment.requested" ("Payment instructions updated for INV-"<>T.pack(show invoice)<>if visible then " · Client visible" else " · Internal only")
   pure(A.object["message".=("Payment instructions saved"::T.Text)])
  saveCommercial cid app = do
   let kind=if section=="proposals" then "proposal"::T.Text else "contract"
       ident=number "id" input
   old<-case ident of
    Nothing->pure Nothing
    Just i->do
     rows<-liftIO $ query (envConn env) "SELECT status,revision FROM commercial_documents WHERE id=? AND client_id=? AND case_id=? AND kind=?" (i,cid,app,kind) :: S.ActionM [(T.Text,Int)]
     case rows of
      [(status,rev)]->checkOwnRevision rev input >> pure(Just status)
      _->reject status404 "Document not found for this application"
   case action of
    "save"->do
     when(maybe False (/="Draft") old) $ reject status409 "Issued documents are immutable. Create a new draft for revised terms."
     title<-bounded "title" 255 input
     body<-bounded "body" 20000 input
     currency<-choice "currency" ["PHP","USD","EUR","GBP","AUD","CAD","NZD"] input
     valid<-dateField "validUntil" True input
     let money key=let raw=field key input in if T.null raw || raw=="0" || raw=="0.00" then pure 0 else maybe (reject status400 ("Enter a nonnegative amount with at most two decimals for "<>key)) pure (Money.amountMinor raw)
     fee<-money "fee"; third<-money "thirdParty"; other<-money "otherCharges"; discount<-money "discount"; tax<-money "tax"
     let total=fee+third+other-discount+tax
     when(total<0 || total>100000000000) $ reject status400 "Discount must not exceed charges and tax; total is too large"
     liftIO $ do
      case ident of
       Nothing->void $ execute (envConn env) "INSERT INTO commercial_documents(client_id,case_id,kind,title,body,currency,fee_minor,third_party_minor,other_minor,discount_minor,tax_minor,total_minor,valid_until,created_by) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)" (cid,app,kind,title,body,currency,fee,third,other,discount,tax,total,valid,userId u)
       Just i->void $ execute (envConn env) "UPDATE commercial_documents SET title=?,body=?,currency=?,fee_minor=?,third_party_minor=?,other_minor=?,discount_minor=?,tax_minor=?,total_minor=?,valid_until=?,revision=revision+1 WHERE id=?" (title,body,currency,fee,third,other,discount,tax,total,valid,i)
      recordHistory env u Nothing (Just cid) (Just app) (kind<>".draft") ("Saved "<>kind<>" draft: "<>title)
    "issue"->do
     unless(old==Just "Draft") $ reject status409 "Select a draft to issue"
     i<-intField "id" input
     changed<-liftIO $ execute (envConn env) "UPDATE commercial_documents SET status='Issued',issued_at=datetime('now'),revision=revision+1 WHERE id=? AND valid_until>=date('now',business_offset())" (Only i)
     when(changed/=1) $ reject status400 "The document has expired. Update its validity before issuing."
     liftIO $ recordHistory env u Nothing (Just cid) (Just app) (kind<>".issued") (T.toTitle kind<>" issued · #"<>T.pack(show i))
    "complete"->do
     unless(kind=="contract" && old==Just "Accepted") $ reject status409 "Only an accepted contract can be completed"
     i<-intField "id" input
     liftIO $ do
      void $ execute (envConn env) "UPDATE commercial_documents SET status='Completed',revision=revision+1 WHERE id=?" (Only i)
      recordHistory env u Nothing (Just cid) (Just app) "contract.completed" ("Contract completed · #"<>T.pack(show i))
    _->reject status404 "Action not found"
   pure(A.object["message".=("Document updated"::T.Text)])

-- This response deliberately enumerates portal fields; staff notes and drafts
-- never enter a client response. The same ownership checks guard downloads.
portalCommercial :: Env -> Int -> IO [A.Value]
portalCommercial env cid = jsonRows env "SELECT json_object('id',id,'title',title,'kind',kind,'number',CASE WHEN kind='proposal' THEN 'PR-' ELSE 'CT-' END||printf('%06d',id),'application',case_id,'currency',currency,'total',printf('%.2f',total_minor/100.0),'validUntil',valid_until,'status',CASE WHEN status IN ('Issued','Viewed') AND valid_until<date('now',business_offset()) THEN 'Expired' ELSE status END) FROM commercial_documents WHERE client_id=? AND status<>'Draft' ORDER BY id DESC" (Only cid)

portalRespond :: Env -> Int -> Int -> T.Text -> S.ActionM ()
portalRespond env cid ident action = do
 unless(action `elem` ["accept","reject"]) $ reject status404 "Action not found"
 rows<-liftIO $ query (envConn env) "SELECT kind,case_id,status FROM commercial_documents WHERE id=? AND client_id=? AND status<>'Draft'" (ident,cid) :: S.ActionM [(T.Text,Int,T.Text)]
 (kind,app,status)<-case rows of [row]->pure row; _->reject status404 "Document not found"
 when(action=="reject" && kind/="proposal") $ reject status400 "Contact your consultant about contract changes"
 unless(status `elem` ["Issued","Viewed"]) $ reject status409 "This document has already been answered or is no longer open"
 when(kind=="contract") $ do
  signing<-liftIO $ query (envConn env) "SELECT id FROM integration_jobs WHERE provider='docusign' AND record_id=? AND record_kind='contract' AND status IN ('Queued','Running','Review') UNION ALL SELECT id FROM integration_links WHERE provider='docusign' AND record_id=? AND record_kind='contract' AND status IN ('Sent','Review','Completed')" (ident,ident) :: S.ActionM [Only Int]
  unless(null signing) $ reject status409 "This contract uses electronic signatures. Follow the DocuSign email to sign it."
 let next=if action=="accept" then "Accepted"::T.Text else "Rejected"
 changed<-liftIO $ execute (envConn env) "UPDATE commercial_documents SET status=?,accepted_at=CASE WHEN ?='Accepted' THEN datetime('now') ELSE NULL END,revision=revision+1 WHERE id=? AND valid_until>=date('now',business_offset())" (next,next,ident)
 when(changed/=1) $ reject status409 "This document has expired. Ask your consultant for a replacement."
 liftIO $ do
  void $ execute (envConn env) "INSERT INTO work_history(client_id,case_id,kind,note) VALUES (?,?,?,?)" (cid,app,kind<>"."<>T.toLower next,T.toTitle kind<>" "<>T.toLower next<>" by client · #"<>T.pack(show ident))
  notify env cid app (kind<>" "<>T.toLower next<>" · #"<>T.pack(show ident)) (kind<>":"<>T.pack(show ident)<>":"<>next)
 S.json(A.object["message".=next])

notify :: Env -> Int -> Int -> T.Text -> T.Text -> IO ()
notify env cid app title key = void $ execute (envConn env) "INSERT INTO notifications(user_id,kind,title,client_id,case_id,event_key) SELECT case_officer_id,'documents',?,?,?,? FROM clients WHERE id=? AND case_officer_id IS NOT NULL ON CONFLICT(user_id,event_key) DO NOTHING" (title,cid,app,key,cid)

-- Portal financial projections contain customer receipt fields only. The ledger's
-- staff identities, reversal reasons and internal audit entries remain private.
portalReceipts :: Env -> Int -> IO [A.Value]
portalReceipts env cid = jsonRows env "SELECT json_object('id',p.id,'invoice',i.id,'application',i.case_id,'currency',i.currency,'amount',printf('%.2f',p.amount_minor/100.0),'date',p.paid_on,'method',p.method,'reference',p.reference,'status',CASE WHEN EXISTS(SELECT 1 FROM invoice_payments r WHERE r.reverses_id=p.id) THEN 'Reversed' ELSE 'Received' END) FROM invoice_payments p JOIN invoices i ON i.id=p.invoice_id WHERE i.client_id=? AND i.status IN ('Issued','Paid') AND p.reverses_id IS NULL ORDER BY p.id DESC" (Only cid)

portalInvoiceDownload :: Env -> Int -> Int -> S.ActionM ()
portalInvoiceDownload env cid ident = do
 rows<-liftIO $ query (envConn env) "SELECT c.full_name,i.description,i.currency,i.amount_minor,i.paid_minor,i.balance_minor,i.due_date FROM invoice_balances i JOIN clients c ON c.id=i.client_id WHERE i.id=? AND i.client_id=? AND i.status IN ('Issued','Paid')" (ident,cid) :: S.ActionM [(T.Text,T.Text,T.Text,Int,Int,Int,T.Text)]
 case rows of
  [(name,description,currency,total,paid,balance,due)]->do
   breakdown<-liftIO $ invoiceBreakdown env ident
   portalPdf ("invoice-"<>T.pack(show ident)) ("ECC Consulting\nInvoice INV-"<>T.pack(show ident)<>"\nClient: "<>name<>"\n\n"<>description<>"\n\n"<>breakdown<>"\nTotal: "<>currency<>" "<>minorText total<>"\nAmount paid: "<>currency<>" "<>minorText paid<>"\nBalance: "<>currency<>" "<>minorText balance<>"\nDue: "<>due)
  _->reject status404 "Invoice not found"

portalReceiptDownload :: Env -> Int -> Int -> S.ActionM ()
portalReceiptDownload env cid ident = do
 rows<-liftIO $ query (envConn env) "SELECT c.full_name,i.id,i.currency,p.amount_minor,p.paid_on,p.method,p.reference,EXISTS(SELECT 1 FROM invoice_payments r WHERE r.reverses_id=p.id) FROM invoice_payments p JOIN invoices i ON i.id=p.invoice_id JOIN clients c ON c.id=i.client_id WHERE p.id=? AND i.client_id=? AND i.status IN ('Issued','Paid') AND p.reverses_id IS NULL" (ident,cid) :: S.ActionM [(T.Text,Int,T.Text,Int,Maybe T.Text,T.Text,T.Text,Bool)]
 case rows of
  [(name,invoice,currency,amount,paid,method,reference,reversed)]->portalPdf ("receipt-"<>T.pack(show ident)) ("ECC Consulting\nPayment receipt RC-"<>T.pack(show ident)<>"\nInvoice INV-"<>T.pack(show invoice)<>"\nClient: "<>name<>"\n\nAmount: "<>currency<>" "<>minorText amount<>"\nDate: "<>maybe "Legacy receipt (date unavailable)" id paid<>"\nMethod: "<>method<>"\nReference: "<>reference<>"\nStatus: "<>if reversed then "Reversed" else "Received")
  _->reject status404 "Receipt not found"

minorText :: Int -> T.Text
minorText amount = T.pack(show(amount `div` 100))<>"."<>T.justifyRight 2 '0' (T.pack(show(amount `mod` 100)))

portalPdf :: T.Text -> T.Text -> S.ActionM ()
portalPdf filename contents = do
 S.setHeader "Content-Type" "application/pdf"
 S.setHeader "Content-Disposition" ("attachment; filename="<>TL.fromStrict filename<>".pdf")
 S.setHeader "Cache-Control" "private, no-store"
 S.raw(renderPdf contents)

-- UTC minute precision is shared by tasks and appointments.
timeField :: T.Text -> A.Value -> S.ActionM (Maybe T.Text)
timeField key input = if T.null(field key input) then pure Nothing else
 case parseTimeM True defaultTimeLocale "%FT%R" (T.unpack(field key input)) :: Maybe UTCTime of
  Nothing->reject status400 (key<>" must be a valid UTC date and time")
  Just time->pure(Just(T.pack(formatTime defaultTimeLocale "%F %T" time)))

taskTimes :: A.Value -> S.ActionM (Maybe T.Text,Maybe T.Text)
taskTimes input = do
 scheduled<-timeField "scheduledAt" input
 due<-timeField "dueAt" input
 when(maybe False id ((>) <$> scheduled <*> due)) $ reject status400 "Due time must be on or after the scheduled time"
 pure(scheduled,due)

refreshOverdue :: Env -> IO ()
refreshOverdue env = do
 void $ execute_ (envConn env) "INSERT INTO work_history(lead_id,client_id,case_id,task_id,kind,note,event_key) SELECT t.lead_id,t.client_id,t.case_id,t.id,'task.overdue','Task overdue: '||t.title||' · Due: '||coalesce(t.due_at,t.due_date),'task.overdue:'||t.id||':'||coalesce(t.due_at,t.due_date) FROM tasks t WHERE t.cancelled_at IS NULL AND t.status<>'Done' AND ((t.due_at IS NOT NULL AND t.due_at<datetime('now')) OR (t.due_at IS NULL AND t.due_date<date('now',business_offset()))) ON CONFLICT(event_key) DO NOTHING"
 void $ execute_ (envConn env) "INSERT INTO notifications(user_id,kind,title,lead_id,client_id,case_id,event_key) SELECT t.assigned_to_id,'escalations','Overdue task: '||t.title||' · Due: '||coalesce(t.due_at,t.due_date),t.lead_id,t.client_id,t.case_id,'journey-overdue:'||t.id||':'||coalesce(t.due_at,t.due_date) FROM tasks t WHERE t.assigned_to_id IS NOT NULL AND t.cancelled_at IS NULL AND t.status<>'Done' AND ((t.due_at IS NOT NULL AND t.due_at<datetime('now')) OR (t.due_at IS NULL AND t.due_date<date('now',business_offset()))) ON CONFLICT(user_id,event_key) DO NOTHING"

commercialDownload :: Env -> Int -> Int -> S.ActionM ()
commercialDownload env cid ident = do
 rows<-liftIO $ query (envConn env) "SELECT title,body,currency,total_minor,valid_until,status,case_id FROM commercial_documents WHERE id=? AND client_id=? AND status<>'Draft'" (ident,cid) :: S.ActionM [(T.Text,T.Text,T.Text,Int,T.Text,T.Text,Int)]
 case rows of
  [(title,body,currency,total,valid,status,app)]->do
   components<-liftIO $ query (envConn env) "SELECT fee_minor,third_party_minor,other_minor,discount_minor,tax_minor FROM commercial_documents WHERE id=? AND client_id=?" (ident,cid) :: S.ActionM [(Int,Int,Int,Int,Int)]
   breakdown<-case components of
    [(fee,thirdParty,other,discount,tax)]->pure $ T.intercalate "\n"
     ["Service fees: "<>currency<>" "<>minorText fee
     ,"Third-party fees: "<>currency<>" "<>minorText thirdParty
     ,"Other charges: "<>currency<>" "<>minorText other
     ,"Subtotal: "<>currency<>" "<>minorText(fee+thirdParty+other)
     ,"Discount: "<>currency<>" "<>minorText discount
     ,"Tax: "<>currency<>" "<>minorText tax]
    _->reject status404 "Document not found"
   when(status=="Issued") $ liftIO $ do
    void $ execute (envConn env) "UPDATE commercial_documents SET status='Viewed',viewed_at=datetime('now'),revision=revision+1 WHERE id=?" (Only ident)
    void $ execute (envConn env) "INSERT INTO work_history(client_id,case_id,kind,note) VALUES (?,?,'document.viewed',?)" (cid,app,"Client viewed commercial document #"<>T.pack(show ident))
   S.setHeader "Content-Type" "application/pdf"
   S.setHeader "Content-Disposition" "attachment; filename=ecc-document.pdf"
   S.raw (renderPdf (title<>"\nDocument #"<>T.pack(show ident)<>" · Application APP-"<>T.pack(show app)<>"\n\n"<>body<>"\n\n"<>breakdown<>"\nTotal: "<>currency<>" "<>minorText total<>"\nValid until: "<>valid))
  _->reject status404 "Document not found"

-- A small, dependency-free PDF writer. Text is escaped, wrapped and paginated;
-- byte offsets are calculated after encoding, including non-ASCII Latin names.
renderPdf :: T.Text -> BL.ByteString
renderPdf input = BL.fromStrict (BC.concat (header : encoded ++ [xref,trailer]))
 where
  header="%PDF-1.4\n"
  wrap line | T.length line<=88 = [line]
            | otherwise = T.take 88 line : wrap(T.drop 88 line)
  linesOfText=concatMap wrap (T.lines input)
  chunks []=[[]]
  chunks xs=take 48 xs : if length xs>48 then chunks(drop 48 xs) else []
  pages=chunks linesOfText
  n=length pages
  escape=BC.pack . concatMap (\c -> if c `elem` ['(',')','\\'] then ['\\',c] else if ord c>=32 && ord c<=255 then [c] else "?") . T.unpack
  stream ls=BC.concat (["BT /F1 11 Tf 50 790 Td 14 TL\n"] ++ map (\line -> "("<>escape line<>") Tj T*\n") ls ++ ["ET\n"])
  pageObjects=concat [let page=4+2*i; content=page+1; body=stream ls in
    ["<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Resources << /Font << /F1 3 0 R >> >> /Contents "<>num content<>" 0 R >>"
    ,"<< /Length "<>num(BC.length body)<>" >>\nstream\n"<>body<>"endstream"] | (i,ls)<-zip [0..] pages]
  objects=["<< /Type /Catalog /Pages 2 0 R >>","<< /Type /Pages /Count "<>num n<>" /Kids ["<>BC.concat [num(4+2*i)<>" 0 R " | i<-[0..n-1]]<>"] >>","<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>"]++pageObjects
  encoded=[num i<>" 0 obj\n"<>body<>"\nendobj\n" | (i,body)<-zip [1..] objects]
  (end,offsets)=mapAccumL (\offset bytes -> (offset+BC.length bytes,offset)) (BC.length header) encoded
  pad offset=BC.pack(replicate (10-length(show offset)) '0'++show offset)
  xref="xref\n0 "<>num(length objects+1)<>"\n0000000000 65535 f \n"<>BC.concat [pad offset<>" 00000 n \n" | offset<-offsets]
  trailer="trailer\n<< /Size "<>num(length objects+1)<>" /Root 1 0 R >>\nstartxref\n"<>num end<>"\n%%EOF\n"
  num=BC.pack . show

-- Explicit staff approval is the only path into the client-visible update feed.
messageRows :: Env -> Maybe Int -> Maybe Int -> Int -> IO [A.Value]
messageRows env cid app offset = jsonRows env ("SELECT json_object('id',m.id,'title',m.title,'body',m.body,'owner',CASE WHEN m.case_id IS NULL THEN 'client:'||m.client_id ELSE 'case:'||m.case_id END,'status',m.status,'publishedAt',m.published_at,'revision',m.revision) FROM client_messages m WHERE m.client_id IN ("<>visibleClients<>") AND (? IS NULL OR m.client_id=?) AND (? IS NULL OR m.case_id=?) ORDER BY m.id DESC LIMIT 50 OFFSET ?") (cid,cid,app,app,offset)

messageAction :: Env -> User -> T.Text -> A.Value -> S.ActionM A.Value
messageAction env u action input = do
 (_,mc,cs)<-owner env u input
 cid<-maybe (reject status400 "Choose a client") pure mc
 let ident=number "id" input
 old<-case ident of
  Nothing->pure Nothing
  Just i->do
   rows<-liftIO $ query (envConn env) "SELECT status,revision FROM client_messages WHERE id=? AND client_id=? AND case_id IS ?" (i,cid,cs) :: S.ActionM [(T.Text,Int)]
   case rows of [(state,rev)]->checkOwnRevision rev input >> pure(Just state); _->reject status404 "Client update not found"
 case action of
  "save"->do
   when(maybe False (/="Draft") old) $ reject status409 "Published updates are retained. Withdraw this update and create a new draft."
   title<-bounded "title" 255 input
   body<-bounded "body" 20000 input
   liftIO $ case ident of
    Nothing->void $ execute (envConn env) "INSERT INTO client_messages(client_id,case_id,title,body,created_by) VALUES (?,?,?,?,?)" (cid,cs,title,body,userId u)
    Just i->void $ execute (envConn env) "UPDATE client_messages SET title=?,body=?,revision=revision+1 WHERE id=?" (title,body,i)
  _ | action `elem` ["publish","withdraw"] ->do
   i<-intField "id" input
   unless(if action=="publish" then old==Just "Draft" else old==Just "Published") $ reject status409 "Select a draft to publish or a published update to withdraw"
   let next=if action=="publish" then "Published"::T.Text else "Withdrawn"
   liftIO $ do
    void $ execute (envConn env) "UPDATE client_messages SET status=?,approved_by=?,published_at=CASE WHEN ?='Published' THEN datetime('now') ELSE published_at END,revision=revision+1 WHERE id=?" (next,userId u,next,i)
    recordHistory env u Nothing (Just cid) cs ("message."<>T.toLower next) ("Client update "<>T.toLower next<>" · #"<>T.pack(show i))
  _->reject status404 "Action not found"
 pure(A.object["message".=("Client update saved"::T.Text)])

profileRows :: Env -> Maybe Int -> Maybe Int -> IO [A.Value]
profileRows env ml mc = case (ml,mc) of
 (Just rid,Nothing)->rows "leads" "lead" rid
 (_,Just rid)->rows "clients" "client" rid
 _->pure []
 where
  rows table kind rid=jsonRows env (Query("SELECT json_object('id',p.id,'title','Address','owner','"<>kind<>":'||p.id,'addressLine1',address_line1,'addressLine2',address_line2,'city',city,'province',province,'postalCode',postal_code,'country',address_country,'revision',v.revision) FROM "<>table<>" p JOIN record_versions v ON v.kind='"<>table<>"' AND v.record_id=p.id WHERE p.id=?")) (Only rid)

profileAction :: Env -> User -> A.Value -> S.ActionM A.Value
profileAction env u input = do
 (ml,mc,_)<-owner env u input
 let (table,rid)=case (ml,mc) of (Just i,Nothing)->("leads",i); (_,Just i)->("clients",i); _->("clients",0)
 checkRevision env table rid input
 let value key=field key input
 forM_ ["addressLine1","addressLine2","city","province","postalCode","country"] $ \key->when(T.length(value key)>255) $ reject status400 (key<>" is too long")
 liftIO $ do
  void $ execute (envConn env) (Query("UPDATE "<>table<>" SET address_line1=?,address_line2=?,city=?,province=?,postal_code=?,address_country=? WHERE id=?")) (value "addressLine1",value "addressLine2",value "city",value "province",value "postalCode",value "country",rid)
  recordHistory env u ml mc Nothing "profile.updated" "Address updated"
 pure(A.object["message".=("Address saved"::T.Text)])

-- Item quantities have at most two decimal places. All arithmetic is integral,
-- and each line is rounded half up to a currency minor unit before summing.
invoiceAmounts :: A.Value -> S.ActionM (T.Text,Int,Int,Int,Int)
invoiceAmounts input = do
 let raw=field "lineItems" input
     nonnegative key=let value=field key input in if value `elem` ["","0","0.00"] then pure 0 else maybe (reject status400 ("Enter a nonnegative amount for "<>key)) pure (Money.amountMinor value)
 discount<-nonnegative "discount"
 tax<-nonnegative "tax"
 subtotal<-if T.null raw then maybe (reject status400 "Enter an amount or itemized lines") pure (Money.amountMinor(field "amount" input)) else do
  let rows=Csv.parseCsv raw
  when(null rows || length rows>100) $ reject status400 "Enter between 1 and 100 invoice lines"
  amounts<-forM rows $ \row->case row of
   [description,quantity,unitPrice] | not(T.null(T.strip description)) && T.length description<=255 ->do
    q<-maybe (reject status400 "Each quantity must be positive with at most two decimals") pure (Money.amountMinor(T.strip quantity))
    price<-maybe (reject status400 "Each unit price must be positive with at most two decimals") pure (Money.amountMinor(T.strip unitPrice))
    when(q>100000000 || price>100000000000) $ reject status400 "Invoice line exceeds the supported limit"
    pure((toInteger q*toInteger price+50) `div` 100)
   _->reject status400 "Each invoice line must contain description, quantity, unit price (CSV)"
  let total=sum amounts
  when(total>100000000000) $ reject status400 "Invoice subtotal exceeds the supported limit"
  pure(fromInteger total)
 let total=subtotal-discount+tax
 when(total<=0 || total>100000000000 || discount>subtotal) $ reject status400 "Invoice total must be positive; discount cannot exceed subtotal"
 pure(raw,subtotal,discount,tax,total)

invoiceBreakdown :: Env -> Int -> IO T.Text
invoiceBreakdown env ident = do
 rows<-query (envConn env) "SELECT line_items,subtotal_minor,discount_minor,tax_minor FROM invoices WHERE id=?" (Only ident) :: IO [(T.Text,Int,Int,Int)]
 pure $ case rows of
  [(raw,subtotal,discount,tax)]->T.intercalate "\n" ((if T.null raw then [] else ["Items (description, quantity, unit price):",raw])++["Subtotal: "<>minorText subtotal,"Discount: "<>minorText discount,"Tax: "<>minorText tax])
  _->""
