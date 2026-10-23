{-# LANGUAGE OverloadedStrings #-}
module ECC.Portal where
import Control.Monad (forM_,void,when)
import Control.Monad.IO.Class (liftIO)
import qualified Data.Aeson as A
import Data.Aeson ((.=))
import qualified Data.ByteString as B
import qualified Data.ByteString.Lazy as BL
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import qualified Data.Text.Lazy as TL
import Network.HTTP.Types hiding (Query)
import qualified Network.Wai as Wai
import Network.Wai.Parse (FileInfo(..))
import qualified Web.Scotty as S
import ECC.Auth
import ECC.Store
import ECC.DB (Env(..))
import ECC.Models
import ECC.Security
import ECC.WorkflowSupport
import qualified ECC.Journey as Journey
import qualified ECC.Integrations as Integrations

type Guard=(User -> S.ActionM ()) -> S.ActionM ()
manage :: Env -> User -> T.Text -> A.Value -> S.ActionM A.Value
manage env u action input = case action of
 "create" -> do
  (_,mc,_)<-owner env u input
  cid<-maybe(reject status400 "Choose a client") pure mc
  days<-maybe (pure 7) pure (number "days" input)
  when(days<1 || days>30) $ reject status400 "Portal access must last 1–30 days"
  token<-liftIO randomToken
  liftIO $ void $ execute (envConn env) "INSERT INTO portal_links(client_id,token_hash,expires_at,created_by) VALUES (?,?,datetime('now',?),?)" (cid,tokenHash token,"+"<>T.pack(show days)<>" days",userId u)
  liftIO $ recordHistory env u Nothing (Just cid) Nothing "portal_access" "Created a private client sign-in link"
  pure(A.object ["url".=(envPublicUrl env<>"/portal#token="<>TE.decodeUtf8 token),"message".=("Share this one-use sign-in link privately with the client. Documents remain private until explicitly granted."::T.Text)])
 "revoke" -> do
  rid<-intField "id" input
  cid<-linkClient rid
  checkOwner env u Nothing(Just cid)
  liftIO $ do
   void $ execute (envConn env) "UPDATE portal_links SET revoked=1 WHERE id=?" (Only rid)
   void $ execute (envConn env) "DELETE FROM portal_sessions WHERE link_id=?" (Only rid)
  liftIO $ recordHistory env u Nothing (Just cid) Nothing "portal_access" "Revoked client portal access"
  pure saved
 "grant" -> do
  rid<-intField "id" input
  cid<-linkClient rid
  checkOwner env u Nothing(Just cid)
  did<-selectedDocument input
  approved<-liftIO $ query (envConn env) "SELECT d.id FROM documents d JOIN document_versions v ON v.document_id=d.id JOIN document_requests r ON r.id=v.request_id WHERE d.id=? AND d.client_id=? AND r.status='Approved' AND d.scan_status='Clean' AND (r.expires_on IS NULL OR r.expires_on>=date('now',business_offset())) AND v.version=(SELECT max(version) FROM document_versions WHERE request_id=r.id)" (did,cid) :: S.ActionM [Only Int]
  when(null approved) $ reject status400 "Only the latest approved, unexpired version for this client can be shared"
  liftIO $ void $ execute (envConn env) "INSERT INTO portal_document_grants(link_id,document_id) VALUES (?,?) ON CONFLICT DO NOTHING" (rid,did)
  liftIO $ recordHistory env u Nothing (Just cid) Nothing "portal_access" ("Shared approved document "<>T.pack(show did))
  pure saved
 _ -> reject status404 "Portal action not found"
 where
  linkClient rid=do
   rows<-liftIO $ query (envConn env) "SELECT client_id FROM portal_links WHERE id=?" (Only (rid::Int)) :: S.ActionM [Only Int]
   case rows of [Only cid]->pure cid; _->reject status404 "Portal link not found"
  selectedDocument :: A.Value -> S.ActionM Int
  selectedDocument value=maybe (reject status400 "Choose a document") pure (readInt(T.replace "document:" "" (field "document" value)))
  readInt text=case reads(T.unpack text) of [(n,"")]->Just n; _->Nothing
  saved=A.object ["message".=("Portal access updated"::T.Text)]

routes :: Env -> Guard -> S.ScottyM ()
routes env _ = do
 S.post "/api/portal/exchange" $ do
  rateLimit env "portal"
  input<-bodyObject
  token<-bounded "token" 100 input
  links<-liftIO $ query (envConn env) "UPDATE portal_links SET activated_at=datetime('now') WHERE token_hash=? AND activated_at IS NULL AND revoked=0 AND expires_at>datetime('now') AND client_id IN (SELECT id FROM clients WHERE deleted_at IS NULL AND merged_into IS NULL) RETURNING id" (Only(tokenHash(TE.encodeUtf8 token))) :: S.ActionM [Only Int]
  case links of
   [Only rid] -> do
    session<-liftIO randomToken
    liftIO $ void $ execute (envConn env) "INSERT INTO portal_sessions(token_hash,link_id,expires_at) VALUES (?,?,datetime('now','+4 hours'))" (tokenHash session,rid)
    S.setHeader "Set-Cookie" ("ecc-portal="<>TL.fromStrict(TE.decodeUtf8 session)<>"; Path=/api/portal; HttpOnly; SameSite=Strict; Max-Age=14400"<>if envProduction env then "; Secure" else "")
    S.json(A.object ["message".=("Client access opened"::T.Text)])
   _ -> reject status401 "This link has expired or was already used. Ask your case officer for a new link."
 S.get "/api/portal" $ do
  (link,cid)<-portalUser env
  dataRows<-liftIO $ jsonRows env "SELECT json_object('name',full_name,'number',client_number) FROM clients WHERE id=?" (Only cid)
  checklist<-liftIO $ jsonRows env "SELECT json_object('id',id,'title',title,'status',status,'required',required,'expiresOn',expires_on,'feedback',review_note,'scanStatus',(SELECT d.scan_status FROM document_versions v JOIN documents d ON d.id=v.document_id WHERE v.request_id=document_requests.id ORDER BY v.version DESC LIMIT 1)) FROM document_requests WHERE client_id=? ORDER BY id" (Only cid)
  cases<-liftIO $ jsonRows env "SELECT json_object('id',id,'number','APP-'||printf('%06d',id),'title',coalesce(service_category,'Application'),'stage',stage,'deadline',next_deadline) FROM cases WHERE client_id=? ORDER BY id" (Only cid)
  docs<-liftIO $ jsonRows env "SELECT json_object('id',d.id,'title',d.filename) FROM documents d JOIN portal_document_grants g ON g.document_id=d.id JOIN document_versions v ON v.document_id=d.id JOIN document_requests r ON r.id=v.request_id WHERE g.link_id=? AND d.client_id=? AND r.status='Approved' AND d.scan_status='Clean' AND (r.expires_on IS NULL OR r.expires_on>=date('now',business_offset())) AND v.version=(SELECT max(version) FROM document_versions WHERE request_id=r.id)" (link,cid)
  invoices<-liftIO $ jsonRows env "SELECT json_object('id',id,'description',description,'currency',currency,'amount',printf('%.2f',amount_minor/100.0),'paid',printf('%.2f',paid_minor/100.0),'balance',printf('%.2f',balance_minor/100.0),'dueDate',due_date,'status',CASE WHEN balance_minor=0 THEN 'Paid' WHEN due_date<date('now',business_offset()) THEN 'Overdue' WHEN paid_minor>0 THEN 'Partially Paid' ELSE 'Payment Requested' END) FROM invoice_balances WHERE client_id=? AND status IN ('Issued','Paid') ORDER BY id DESC" (Only cid)
  integrations<-liftIO $ Integrations.portalLinks env cid
  receipts<-liftIO $ Journey.portalReceipts env cid
  commercial<-liftIO $ Journey.portalCommercial env cid
  meetings<-liftIO $ jsonRows env "SELECT json_object('id',id,'title',title,'application',case_id,'startsAt',starts_at,'endsAt',ends_at,'meetingUrl',meeting_url,'meetingId',meeting_id,'passcode',passcode) FROM appointments WHERE client_id=? AND client_visible=1 AND status='Scheduled' AND ends_at>=datetime('now') ORDER BY starts_at" (Only cid)
  instructions<-liftIO $ jsonRows env "SELECT json_object('invoice',p.invoice_id,'bank',p.bank,'accountName',p.account_name,'accountNumber',p.account_number,'method',p.method,'instructions',p.instructions,'currency',i.currency,'amountDue',printf('%.2f',i.balance_minor/100.0),'dueDate',i.due_date) FROM payment_instructions p JOIN invoice_balances i ON i.id=p.invoice_id WHERE p.client_id=? AND p.client_visible=1 AND i.client_id=p.client_id AND i.status IN ('Issued','Paid')" (Only cid)
  S.json(A.object ["integrations".=integrations,"receipts".=receipts,"commercial".=commercial,"meetings".=meetings,"paymentDetails".=instructions,"client".=dataRows,"checklist".=checklist,"cases".=cases,"documents".=docs,"invoices".=invoices])
 S.get "/api/portal/signatures/:id/download" $ do
  (_,cid)<-portalUser env
  ident<-S.pathParam "id"
  Integrations.downloadSigned env cid ident
 S.get "/api/portal/invoices/:id/download" $ do
  (_,cid)<-portalUser env
  ident<-S.pathParam "id"
  Journey.portalInvoiceDownload env cid ident
 S.get "/api/portal/receipts/:id/download" $ do
  (_,cid)<-portalUser env
  ident<-S.pathParam "id"
  Journey.portalReceiptDownload env cid ident
 S.get "/api/portal/commercial/:id/download" $ do
  (_,cid)<-portalUser env
  ident<-S.pathParam "id"
  Journey.commercialDownload env cid ident
 S.post "/api/portal/commercial/:id/:action" $ do
  (_,cid)<-portalUser env
  ident<-S.pathParam "id"
  action<-S.pathParam "action"
  Journey.portalRespond env cid ident action
 S.post "/api/portal/logout" $ do
  req<-S.request
  forM_ (portalToken req) $ \token -> liftIO $ void $ execute (envConn env) "DELETE FROM portal_sessions WHERE token_hash=?" (Only(tokenHash token))
  S.setHeader "Set-Cookie" ("ecc-portal=; Path=/api/portal; HttpOnly; SameSite=Strict; Max-Age=0"<>if envProduction env then "; Secure" else "")
  S.json(A.object ["message".=("Signed out"::T.Text)])
 S.post "/api/portal/requests/:id/upload" $ do
  (link,cid)<-portalUser env
  rateLimitAccount env "portal-upload" (T.pack(show cid))
  rid<-S.pathParam "id"
  allowed<-liftIO $ query (envConn env) "SELECT id FROM document_requests WHERE id=? AND client_id=?" (rid,cid) :: S.ActionM [Only Int]
  when(null allowed) $ reject status404 "Checklist item not found"
  files<-S.files
  case files of
   (_,fi):_ -> do
    let bytes=fileContent fi
        filename=T.take 255(T.filter(\c -> c/='\r' && c/='\n' && c/='/' && c/='\\' && c/='\0') (TE.decodeUtf8With (\_ _->Just '_') (fileName fi)))
    when(BL.null bytes || BL.length bytes>25*1024*1024 || T.null filename) $ reject status400 "Choose a nonempty file up to 25 MB"
    quota<-liftIO $ query (envConn env) "INSERT INTO portal_upload_limits(link_id,day,bytes,files) VALUES (?,date('now',business_offset()),?,1) ON CONFLICT(link_id,day) DO UPDATE SET bytes=portal_upload_limits.bytes+excluded.bytes,files=portal_upload_limits.files+1 WHERE portal_upload_limits.bytes+excluded.bytes<=104857600 AND portal_upload_limits.files<20 RETURNING files" (link,BL.length bytes) :: S.ActionM [Only Int]
    when(null quota) $ reject status429 "This link reached its daily upload allowance. Contact your case officer."
    liftIO $ do
     [Only did]<-query (envConn env) "INSERT INTO documents(client_id,filename,mime_type,size,content) VALUES (?,?,?, ?,?) RETURNING id" (cid,filename,"application/octet-stream"::T.Text,BL.length bytes,Binary(BL.toStrict bytes))
     void $ execute (envConn env) "INSERT INTO document_versions(request_id,document_id,version) SELECT ?,?,coalesce(max(version),0)+1 FROM document_versions WHERE request_id=?" (rid,did::Int,rid)
     void $ execute (envConn env) "UPDATE document_requests SET status='Received',review_note=NULL,reviewed_by=NULL WHERE id=?" (Only(rid::Int))
     void $ execute (envConn env) "INSERT INTO work_history(client_id,kind,note) VALUES (?,'portal_upload',?)" (cid,"Client uploaded: "<>filename)
     void $ execute (envConn env) "INSERT INTO notifications(user_id,kind,title,client_id,case_id,event_key) SELECT c.case_officer_id,'documents',?,c.id,r.case_id,? FROM clients c JOIN document_requests r ON r.client_id=c.id WHERE c.id=? AND r.id=? AND c.case_officer_id IS NOT NULL ON CONFLICT(user_id,event_key) DO NOTHING" ("Client uploaded: "<>filename,"portal-upload:"<>T.pack(show did),cid,rid)
    S.json(A.object ["message".=("File received and awaiting review"::T.Text)])
   _ -> reject status400 "Choose a file to upload"
 S.get "/api/portal/documents/:id" $ do
  (link,cid)<-portalUser env
  did<-S.pathParam "id"
  rows<-liftIO $ query (envConn env) "SELECT d.content FROM documents d JOIN portal_document_grants g ON g.document_id=d.id JOIN document_versions v ON v.document_id=d.id JOIN document_requests r ON r.id=v.request_id WHERE d.id=? AND d.client_id=? AND g.link_id=? AND r.status='Approved' AND d.scan_status='Clean' AND (r.expires_on IS NULL OR r.expires_on>=date('now',business_offset())) AND v.version=(SELECT max(version) FROM document_versions WHERE request_id=r.id)" (did::Int,cid,link) :: S.ActionM [Only(Binary B.ByteString)]
  case rows of
   [Only(Binary bytes)] -> do
    S.setHeader "Content-Type" "application/octet-stream"
    S.setHeader "Content-Disposition" "attachment; filename=client-document"
    S.raw(BL.fromStrict bytes)
   _ -> reject status404 "Shared document not found"

portalToken :: Wai.Request -> Maybe B.ByteString
portalToken req=lookup hCookie(Wai.requestHeaders req) >>= findCookie . B.split 59
 where
  findCookie []=Nothing
  findCookie(x:xs)=case B.stripPrefix "ecc-portal=" (B.dropWhile(==32)x) of Just t->Just t; _->findCookie xs
portalUser :: Env -> S.ActionM (Int,Int)
portalUser env=do
 req<-S.request
 token<-maybe(reject status401 "Open a fresh client sign-in link") pure(portalToken req)
 rows<-liftIO $ query (envConn env) "SELECT p.id,p.client_id FROM portal_sessions s JOIN portal_links p ON p.id=s.link_id JOIN clients c ON c.id=p.client_id WHERE s.token_hash=? AND s.expires_at>datetime('now') AND p.expires_at>datetime('now') AND p.revoked=0 AND c.deleted_at IS NULL AND c.merged_into IS NULL" (Only(tokenHash token)) :: S.ActionM [(Int,Int)]
 case rows of [pair]->pure pair; _->reject status401 "Client access expired. Ask for a new sign-in link."
