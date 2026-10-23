{-# LANGUAGE OverloadedStrings #-}
module ECC.Integrations (request, retry, portalLinks, staffRows, downloadSigned) where

import Control.Monad (unless, void, when)
import Control.Monad.IO.Class (liftIO)
import qualified Data.Aeson as A
import Data.Aeson ((.=))
import qualified Data.ByteString as B
import qualified Data.ByteString.Lazy as BL
import qualified Data.Text as T
import System.Environment (lookupEnv)
import Network.HTTP.Types hiding (Query)
import qualified Web.Scotty as S
import ECC.DB (Env(..))
import ECC.Models
import ECC.Store
import ECC.WorkflowSupport
import ECC.Security (reject)
import qualified ECC.Access as Access

-- Only server-selected business records reach the queue. Provider credentials
-- and arbitrary URLs never come from browser input.
request :: Env -> User -> T.Text -> T.Text -> A.Value -> S.ActionM A.Value
request env u section action input = do
 let provider=case action of "zoom"->"zoom"; "calendar"->"google"; "checkout"->"stripe"; _->"docusign"
     kind=case section of "appointments"->"appointment"; "invoices"->"invoice"; _->"contract"
 unless ((section,action) `elem` [("appointments","zoom"),("appointments","calendar"),("invoices","checkout"),("contracts","sign")]) $ reject status404 "Integration action not found"
 when (provider `elem` ["stripe","docusign"]) $ Access.requirePrivilege env u "finance_view"
 when (provider=="stripe") $ Access.requirePrivilege env u "payments_record"
 when (provider=="docusign") $ Access.requirePrivilege env u "email"
 enabled<-liftIO $ maybe [] (T.splitOn "," . T.pack) <$> lookupEnv "INTEGRATIONS_ENABLED"
 unless (provider `elem` enabled) $ reject status503 "This provider is not enabled. Configure the integration worker and provider account first."
 ident<-intField "id" input
 rows<-liftIO $ case kind of
  "appointment"->query (envConn env) "SELECT client_id,case_id,revision,status FROM appointments WHERE id=? AND client_id IS NOT NULL" (Only ident)
  "invoice"->query (envConn env) "SELECT client_id,case_id,revision,status FROM invoices WHERE id=?" (Only ident)
  _->query (envConn env) "SELECT client_id,case_id,revision,status FROM commercial_documents WHERE id=? AND kind='contract'" (Only ident)
 (cid,app,rev,status)<-case rows :: [(Int,Maybe Int,Int,T.Text)] of [row]->pure row; _->reject status404 "Choose a saved client record"
 checkOwner env u Nothing (Just cid)
 checkOwnRevision rev input
 (_,scopeClient,scopeCase)<-owner env u input
 when(scopeClient/=Just cid || (scopeCase/=Nothing && scopeCase/=app)) $ reject status404 "Record not found in this application"
 when(kind=="appointment" && status/="Scheduled") $ reject status409 "Only scheduled appointments can be connected"
 when(kind=="invoice" && status/="Issued") $ reject status409 "Issue an unpaid invoice before creating checkout"
 when(kind=="contract" && status `notElem` ["Issued","Viewed"]) $ reject status409 "Issue an unsigned contract before requesting a signature"
 active<-liftIO $ query (envConn env) "SELECT id FROM integration_jobs WHERE provider=? AND record_kind=? AND record_id=? AND status IN ('Queued','Running','Review') UNION ALL SELECT id FROM integration_links WHERE provider=? AND record_kind=? AND record_id=? AND status IN ('Open','Sent','Completed')" (provider,kind,ident,provider,kind,ident) :: S.ActionM [Only Int]
 when(not(null active)) $ reject status409 "This record already has an active integration request. Check its integration status."
 changed<-liftIO $ execute (envConn env) "INSERT INTO integration_jobs(provider,record_kind,record_id,source_revision,client_id,case_id,actor_id) VALUES (?,?,?,?,?,?,?) ON CONFLICT(provider,record_kind,record_id,source_revision) DO UPDATE SET status='Queued',error_code=NULL,next_attempt_at=NULL WHERE integration_jobs.status='Failed' AND integration_jobs.attempts<5" (provider,kind,ident,rev,cid,app,userId u)
 when(changed/=1) $ reject status409 "This operation cannot be queued again. Review its integration status before continuing."
 liftIO $ recordHistory env u Nothing (Just cid) app "integration.requested" ("Requested "<>provider<>" for "<>kind<>" #"<>T.pack(show ident))
 pure(A.object["message".=("Integration queued. Refresh this workspace to see provider status."::T.Text)])

-- Retry preserves the provider operation identity. Unknown create outcomes are
-- reconciled before any further create attempt; a retry cannot mint a new key.
retry :: Env -> User -> A.Value -> S.ActionM A.Value
retry env u input = do
 ident<-intField "id" input
 rows<-liftIO $ query (envConn env) "SELECT client_id,provider,status,attempts FROM integration_jobs WHERE id=?" (Only ident) :: S.ActionM [(Int,T.Text,T.Text,Int)]
 (cid,provider,status,attempts)<-case rows of [record]->pure record; _->reject status404 "Integration request not found"
 checkOwner env u Nothing (Just cid)
 when(provider `elem` ["stripe","docusign"]) $ Access.requirePrivilege env u "finance_view"
 when(provider=="stripe") $ Access.requirePrivilege env u "payments_record"
 when(provider=="docusign") $ Access.requirePrivilege env u "email"
 unless(status `elem` ["Failed","Review"] && attempts<5) $ reject status409 "Only failed requests with fewer than five attempts can be retried"
 liftIO $ void $ execute (envConn env) "UPDATE integration_jobs SET status='Queued',error_code=NULL,next_attempt_at=NULL,updated_at=datetime('now') WHERE id=?" (Only ident)
 pure(A.object["message".=("Retry queued using the original provider operation identity"::T.Text)])

staffRows :: Env -> User -> Maybe Int -> Maybe Int -> IO [A.Value]
staffRows env u cid app = do
 financial<-Access.hasPrivilege env u "finance_view"
 jsonRows env ("SELECT json_object('id',j.id,'title',j.provider||' · '||j.record_kind||' #'||j.record_id,'provider',j.provider,'owner',CASE WHEN j.case_id IS NULL THEN 'client:'||j.client_id ELSE 'case:'||j.case_id END,'record',j.record_id,'status',j.status,'providerStatus',l.status,'errorCode',j.error_code,'date',j.updated_at) FROM integration_jobs j LEFT JOIN integration_links l ON l.job_id=j.id WHERE (j.provider IN ('zoom','google') OR ?) AND j.client_id IN ("<>visibleClients<>") AND (? IS NULL OR j.client_id=?) AND (? IS NULL OR j.case_id=?) ORDER BY j.id DESC LIMIT 50") (financial,cid,cid,app,app)

portalLinks :: Env -> Int -> IO [A.Value]
portalLinks env cid = jsonRows env "SELECT json_object('id',l.id,'kind',l.record_kind,'record',l.record_id,'status',l.status,'url',CASE WHEN l.provider='stripe' AND l.status='Open' AND i.status='Issued' AND i.balance_minor=l.amount_minor THEN l.url ELSE '' END,'signedPdfReady',d.scan_status='Clean') FROM integration_links l LEFT JOIN invoice_balances i ON l.record_kind='invoice' AND i.id=l.record_id LEFT JOIN documents d ON d.id=l.signed_document_id WHERE l.client_id=? AND l.provider IN ('stripe','docusign')" (Only cid)

downloadSigned :: Env -> Int -> Int -> S.ActionM ()
downloadSigned env cid ident = do
 rows<-liftIO $ query (envConn env) "SELECT d.content FROM integration_links l JOIN documents d ON d.id=l.signed_document_id WHERE l.id=? AND l.client_id=? AND d.client_id=? AND l.provider='docusign' AND l.status='Completed' AND d.scan_status='Clean'" (ident,cid,cid) :: S.ActionM [Only(Binary B.ByteString)]
 case rows of
  [Only(Binary bytes)]->do
   S.setHeader "Content-Type" "application/pdf"
   S.setHeader "Content-Disposition" "attachment; filename=signed-contract.pdf"
   S.setHeader "Cache-Control" "private, no-store"
   S.raw(BL.fromStrict bytes)
  _->reject status404 "Signed document is unavailable or awaiting malware scanning"
