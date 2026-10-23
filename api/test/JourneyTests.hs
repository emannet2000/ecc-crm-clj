{-# LANGUAGE OverloadedStrings #-}
module JourneyTests (run) where

import Control.Monad (forM_, unless, void)
import Control.Exception (bracket)
import System.Environment (lookupEnv, setEnv, unsetEnv)
import qualified Data.Aeson as A
import Data.Aeson ((.=),(.:))
import Data.Aeson.Types (parseMaybe)
import qualified Data.ByteString.Char8 as B
import qualified Data.ByteString.Lazy.Char8 as BL
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import qualified Network.Wai as W
import qualified Network.Wai.Test as WT
import Network.HTTP.Types (statusCode)
import ECC.Store
import ECC.Models
import qualified ECC.DB as DB
import ECC.Release (releaseContract)

assert :: String -> Bool -> IO ()
assert label ok=unless ok (fail label)
expect :: Int -> WT.SResponse -> IO ()
expect code response=assert ("Expected "++show code++", got "++show(WT.simpleStatus response)++": "++show(WT.simpleBody response)) (statusCode(WT.simpleStatus response)==code)
field :: A.FromJSON a => A.Key -> WT.SResponse -> IO a
field key response=do
 value<-either fail pure(A.eitherDecode(WT.simpleBody response))
 maybe (fail("Missing field "++show key)) pure(parseMaybe(A.withObject "response" (.:key)) value)

run :: Connection -> W.Application -> IO ()
run conn api=do
 let call headers method path body=WT.runSession (WT.srequest(WT.SRequest ((WT.setPath W.defaultRequest path){W.requestMethod=method,W.requestHeaders=("X-ECC-Contract",TE.encodeUtf8 releaseContract):("Content-Type","application/json"):headers}) (A.encode body))) api
 logged<-call [] "POST" "/api/auth/login" (A.object["lrEmail".=("admin@example.com"::T.Text),"lrPassword".=("correct-password-123"::T.Text)])
 expect 200 logged
 token<-TE.encodeUtf8 <$> (field "token" logged::IO T.Text)
 let admin=call [("Authorization","Bearer "<>token)]
 client<-DB.insertClient conn (NewClient "Journey Maria" (Just "journey@example.test") Nothing (Just 1))
 other<-DB.insertClient conn (NewClient "Journey other" Nothing Nothing (Just 1))
 let cid=clientId client
 [Only app]<-query conn "INSERT INTO cases(client_id,service_category,destination,stage) VALUES (?,'Student Visa','Canada','New Client') RETURNING id" (Only cid)::IO[Only Int]
 let own="case:"<>T.pack(show app)
     post section pairs=admin "POST" ("/api/workspace/"<>section) (A.object pairs)
     record section=admin "GET" ("/api/workspace/record/case/"<>B.pack(show app)<>"/"<>section) A.Null
     draft kind name=post (kind<>"/save") ["owner".=own,"title".=(name::T.Text),"body".=("Consulting terms (review carefully).\nService and government fees."::T.Text),"currency".=("PHP"::T.Text),"fee".=("25000.00"::T.Text),"thirdParty".=("1000"::T.Text),"discount".=("500"::T.Text),"tax".=("100"::T.Text),"validUntil".=("2099-12-31"::T.Text)]
 draft "proposals" "Canada study proposal" >>=expect 200
 draft "contracts" "Consulting agreement" >>=expect 200
 [Only proposal]<-query conn "SELECT id FROM commercial_documents WHERE client_id=? AND kind='proposal'" (Only cid)::IO[Only Int]
 [Only contract]<-query conn "SELECT id FROM commercial_documents WHERE client_id=? AND kind='contract'" (Only cid)::IO[Only Int]
 forM_ ["proposals","contracts","payment-details","appointments","payments","invoices"] $ \section->record section >>=expect 200
 [Only total]<-query conn "SELECT total_minor FROM commercial_documents WHERE id=?" (Only proposal)::IO[Only Int]
 assert "Proposal total uses exact minor-unit arithmetic" (total==2560000)
 let issue section ident=post (section<>"/issue") ["owner".=own,"id".=ident,"expectedRevision".=(1::Int)]
 issue "proposals" proposal >>=expect 200
 issue "proposals" proposal >>=expect 409
 post "proposals/save" ["owner".=own,"id".=proposal,"expectedRevision".=(2::Int)] >>=expect 409
 -- Private portal sessions cannot see drafts or another client's records.
 let portalFor ident=do
      link<-post "portal/create" ["owner".=("client:"<>T.pack(show ident))]
      expect 200 link
      url<-field "url" link::IO T.Text
      let secret=T.drop 7(snd(T.breakOn "#token=" url))
      exchanged<-call [] "POST" "/api/portal/exchange" (A.object["token".=secret])
      expect 200 exchanged
      cookie<-maybe(fail "Missing portal cookie") pure(lookup "Set-Cookie" (WT.simpleHeaders exchanged))
      pure(call [("Cookie",B.takeWhile (/=';') cookie)])
 portal<-portalFor cid
 stranger<-portalFor(clientId other)
 initial<-portal "GET" "/api/portal" A.Null
 expect 200 initial
 documents<-field "commercial" initial::IO[A.Value]
 assert "Portal omits drafts" (length documents==1 && not("Consulting agreement" `B.isInfixOf` BL.toStrict(WT.simpleBody initial)))
 let path ident="/api/portal/commercial/"<>B.pack(show ident)
 portal "GET" (path contract<>"/download") A.Null >>=expect 404
 stranger "GET" (path proposal<>"/download") A.Null >>=expect 404
 stranger "POST" (path proposal<>"/accept") A.Null >>=expect 404
 pdf<-portal "GET" (path proposal<>"/download") A.Null
 expect 200 pdf
 assert "Portal commercial download is a PDF" (lookup "Content-Type" (WT.simpleHeaders pdf)==Just "application/pdf" && "%PDF-1.4" `BL.isPrefixOf` WT.simpleBody pdf && "startxref" `B.isInfixOf` BL.toStrict(WT.simpleBody pdf))
 portal "POST" (path proposal<>"/accept") A.Null >>=expect 200
 portal "POST" (path proposal<>"/accept") A.Null >>=expect 409
 issue "contracts" contract >>=expect 200
 portal "POST" (path contract<>"/reject") A.Null >>=expect 400
 portal "POST" (path contract<>"/accept") A.Null >>=expect 200
 post "contracts/complete" ["owner".=own,"id".=contract,"expectedRevision".=(3::Int)] >>=expect 200
 -- Task times persist; rescheduling preserves previous and new times.
 let task status due rev= ["owner".=own,"title".=("Document review"::T.Text),"description".=("Internal-only follow-up"::T.Text),"scheduledAt".=("2020-01-01T08:00"::T.Text),"dueAt".=(due::T.Text),"status".=(status::T.Text),"priority".=("High"::T.Text),"assignee".=(1::Int)]++rev
 post "tasks/create" (task "Pending" "2020-01-01T07:00" []) >>=expect 400
 post "tasks/create" (task "Pending" "2020-01-01T10:00" []) >>=expect 200
 [Only tid]<-query conn "SELECT id FROM tasks WHERE client_id=?" (Only cid)::IO[Only Int]
 post "tasks/save" (task "Pending" "2020-01-02T14:00" ["id".=tid,"expectedRevision".=(1::Int)]) >>=expect 200
 [Only scheduled]<-query conn "SELECT count(*) FROM work_history WHERE client_id=? AND kind='task.rescheduled' AND note LIKE '%2020-01-01 10:00%' AND note LIKE '%2020-01-02 14:00%'" (Only cid)::IO[Only Int]
 assert "Task timeline preserves previous and new schedule" (scheduled==1)
 admin "GET" "/api/workspace/notifications" A.Null >>=expect 200
 admin "GET" "/api/workspace/notifications" A.Null >>=expect 200
 [Only notification]<-query conn "SELECT id FROM notifications WHERE client_id=? AND event_key LIKE 'journey-overdue:%'" (Only cid)::IO[Only Int]
 post "notifications/archive" ["id".=notification] >>=expect 200
 admin "GET" "/api/workspace/notifications" A.Null >>=expect 200
 [Only stillOpen]<-query conn "SELECT status FROM tasks WHERE id=?" (Only tid)::IO[Only T.Text]
 [Only overdueCount]<-query conn "SELECT count(*) FROM notifications WHERE client_id=? AND event_key LIKE 'journey-overdue:%'" (Only cid)::IO[Only Int]
 assert "Dismiss neither completes a task nor regenerates the same overdue alert" (stillOpen=="Pending" && overdueCount==1)
 post "tasks/save" (task "Done" "2020-01-02T14:00" ["id".=tid,"expectedRevision".=(2::Int)]) >>=expect 200
 [Only completed]<-query conn "SELECT completed_at IS NOT NULL FROM tasks WHERE id=?" (Only tid)::IO[Only Bool]
 assert "Task completion retains its timestamp" completed
 -- Meeting links default to internal and must be explicitly shared.
 let meeting visible url=["owner".=own,"title".=("Initial consultation"::T.Text),"assignee".=(1::Int),"startsAt".=("2099-01-01T10:00"::T.Text),"endsAt".=("2099-01-01T11:00"::T.Text),"meetingUrl".=(url::T.Text),"passcode".=("private-passcode"::T.Text),"clientVisible".=visible,"status".=("Scheduled"::T.Text)]
 post "appointments/save" (meeting True "javascript:alert(1)") >>=expect 400
 post "appointments/save" (meeting False "https://zoom.us/j/123456") >>=expect 200
 [Only mid]<-query conn "SELECT id FROM appointments WHERE client_id=?" (Only cid)::IO[Only Int]
 hidden<-portal "GET" "/api/portal" A.Null
 assert "Internal Zoom credentials never enter portal responses" (not("private-passcode" `B.isInfixOf` BL.toStrict(WT.simpleBody hidden)))
 post "appointments/save" (meeting True "https://zoom.us/j/123456"++["id".=mid,"expectedRevision".=(1::Int)]) >>=expect 200
 shared<-portal "GET" "/api/portal" A.Null
 meetings<-field "meetings" shared::IO[A.Value]
 assert "Explicitly shared upcoming meeting appears in portal" (length meetings==1)
 otherPortal<-stranger "GET" "/api/portal" A.Null
 assert "Other client cannot see Zoom credentials or staff tasks" (not("private-passcode" `B.isInfixOf` BL.toStrict(WT.simpleBody otherPortal)) && not("Internal-only follow-up" `B.isInfixOf` BL.toStrict(WT.simpleBody shared)))
 -- Payment instructions belong to the invoice client and application.
 [Only invoice]<-query conn "INSERT INTO invoices(client_id,case_id,description,currency,amount_minor,due_date) VALUES (?,?,'Consulting','PHP',2500000,'2099-12-31') RETURNING id" (cid,app)::IO[Only Int]
 void $ execute conn "UPDATE invoices SET status='Issued' WHERE id=?" (Only invoice)
 let instructions visible=["owner".=own,"invoice".=invoice,"bank".=("Example Bank"::T.Text),"accountName".=("ECC Consulting"::T.Text),"accountNumber".=("private-bank-reference"::T.Text),"method".=("Bank transfer"::T.Text),"instructions".=("Use the invoice reference"::T.Text),"clientVisible".=visible]
 post "payment-details/save" (instructions False) >>=expect 200
 [Only instructionId]<-query conn "SELECT id FROM payment_instructions WHERE invoice_id=?" (Only invoice)::IO[Only Int]
 bankHidden<-portal "GET" "/api/portal" A.Null
 assert "Payment configuration is internal until explicitly exposed" (not("private-bank-reference" `B.isInfixOf` BL.toStrict(WT.simpleBody bankHidden)))
 post "payment-details/save" (instructions True++["id".=instructionId,"expectedRevision".=(1::Int)]) >>=expect 200
 bankShared<-portal "GET" "/api/portal" A.Null
 assert "Shared payment instructions appear for the owning client" ("private-bank-reference" `B.isInfixOf` BL.toStrict(WT.simpleBody bankShared))
 [Only secondApp]<-query conn "INSERT INTO cases(client_id,service_category,destination,stage) VALUES (?,'Visitor Visa','Canada','New Client') RETURNING id" (Only cid)::IO[Only Int]
 post "payment-details/save" (["owner".=("case:"<>T.pack(show secondApp))]++filter (\(key,_)->key/="owner") (instructions True)) >>=expect 400
 -- Invoice and receipt downloads use the same portal ownership boundary.
 let invoicePath="/api/portal/invoices/"<>B.pack(show invoice)<>"/download"
 invoicePdf<-portal "GET" invoicePath A.Null
 expect 200 invoicePdf
 assert "Invoice download is a PDF" ("%PDF-1.4" `BL.isPrefixOf` WT.simpleBody invoicePdf)
 stranger "GET" invoicePath A.Null >>=expect 404
 call [] "GET" invoicePath A.Null >>=expect 401
 [Only today]<-query_ conn "SELECT date('now',business_offset())"::IO[Only T.Text]
 [Only invoiceRevision]<-query conn "SELECT revision FROM invoices WHERE id=?" (Only invoice)::IO[Only Int]
 post "payments/record" ["id".=invoice,"expectedRevision".=invoiceRevision,"amount".=("10000.00"::T.Text),"paidOn".=today,"method".=("Bank transfer"::T.Text),"reference".=("client-reference"::T.Text)] >>=expect 200
 [Only receipt]<-query conn "SELECT id FROM invoice_payments WHERE invoice_id=?" (Only invoice)::IO[Only Int]
 [Only paymentEvents]<-query conn "SELECT count(*) FROM work_history WHERE client_id=? AND case_id=? AND kind='payment.received'" (cid,app)::IO[Only Int]
 assert "Recorded payments appear in the application timeline" (paymentEvents==1)
 let receiptPath="/api/portal/receipts/"<>B.pack(show receipt)<>"/download"
 receiptPdf<-portal "GET" receiptPath A.Null
 expect 200 receiptPdf
 assert "Receipt download contains customer reference without staff identity" ("client-reference" `B.isInfixOf` BL.toStrict(WT.simpleBody receiptPdf) && not("Admin" `B.isInfixOf` BL.toStrict(WT.simpleBody receiptPdf)))
 stranger "GET" receiptPath A.Null >>=expect 404
 call [] "GET" receiptPath A.Null >>=expect 401
 partial<-portal "GET" "/api/portal" A.Null
 assert "Portal shows partial payment and receipts without internal financial fields" ("Partially Paid" `B.isInfixOf` BL.toStrict(WT.simpleBody partial) && "client-reference" `B.isInfixOf` BL.toStrict(WT.simpleBody partial) && not("Admin" `B.isInfixOf` BL.toStrict(WT.simpleBody partial)))
 [Only draftInvoice]<-query conn "INSERT INTO invoices(client_id,case_id,description,currency,amount_minor,due_date) VALUES (?,?,'Private draft','PHP',100,'2099-12-31') RETURNING id" (cid,app)::IO[Only Int]
 portal "GET" ("/api/portal/invoices/"<>B.pack(show draftInvoice)<>"/download") A.Null >>=expect 404
 -- Missing authentication and staff-token misuse cannot bypass portal checks.
 call [] "GET" (path proposal<>"/download") A.Null >>=expect 401
 admin "GET" (path proposal<>"/download") A.Null >>=expect 401
 -- Provider commands are authorized, revision checked and durable. No network
 -- or provider secrets are used by these API tests.
 bracket (lookupEnv "INTEGRATIONS_ENABLED") (\previous->maybe (unsetEnv "INTEGRATIONS_ENABLED") (setEnv "INTEGRATIONS_ENABLED") previous) $ \_ -> do
  setEnv "INTEGRATIONS_ENABLED" ""
  post "appointments/calendar" ["owner".=own,"id".=mid,"expectedRevision".=(2::Int)] >>=expect 503
  setEnv "INTEGRATIONS_ENABLED" "zoom,google,stripe,docusign"
  post "appointments/calendar" ["owner".=own,"id".=mid,"expectedRevision".=(1::Int)] >>=expect 409
  post "appointments/calendar" ["owner".=own,"id".=mid,"expectedRevision".=(2::Int)] >>=expect 200
  post "appointments/calendar" ["owner".=own,"id".=mid,"expectedRevision".=(2::Int)] >>=expect 409
  post "appointments/zoom" ["owner".=("client:"<>T.pack(show(clientId other))),"id".=mid,"expectedRevision".=(2::Int)] >>=expect 404
  record "integrations" >>=expect 200
  [Only checkoutRev]<-query conn "SELECT revision FROM invoices WHERE id=?" (Only invoice)::IO[Only Int]
  post "invoices/checkout" ["owner".=own,"id".=invoice,"expectedRevision".=checkoutRev] >>=expect 200
  [Only pendingJobs]<-query conn "SELECT count(*) FROM integration_jobs WHERE client_id=?" (Only cid)::IO[Only Int]
  assert "Provider requests are durable and duplicates do not enqueue twice" (pendingJobs==2)
  void $ execute conn "UPDATE integration_jobs SET status='Failed',attempts=5 WHERE provider='stripe' AND record_id=?" (Only invoice)
  post "invoices/checkout" ["owner".=own,"id".=invoice,"expectedRevision".=checkoutRev] >>=expect 409
  draft "contracts" "Electronic signature agreement" >>=expect 200
  [Only electronic]<-query conn "SELECT max(id) FROM commercial_documents WHERE client_id=? AND kind='contract'" (Only cid)::IO[Only Int]
  issue "contracts" electronic >>=expect 200
  post "contracts/sign" ["owner".=own,"id".=electronic,"expectedRevision".=(2::Int)] >>=expect 200
  portal "POST" (path electronic<>"/accept") A.Null >>=expect 409
  [Only signatureJob]<-query conn "SELECT id FROM integration_jobs WHERE record_kind='contract' AND record_id=?" (Only electronic)::IO[Only Int]
  void $ execute conn "UPDATE integration_jobs SET status='Succeeded' WHERE id=?" (Only signatureJob)
  [Only signedDoc]<-query conn "INSERT INTO documents(client_id,filename,mime_type,size,content) VALUES (?,'signed.pdf','application/pdf',8,?) RETURNING id" (cid,Binary(B.pack "%PDF-1.4"))::IO[Only Int]
  [Only signatureLink]<-query conn "INSERT INTO integration_links(job_id,provider,record_kind,record_id,client_id,case_id,remote_id,status,source_revision,signed_document_id) VALUES (?,'docusign','contract',?,?,?,'envelope-fixture','Completed',2,?) RETURNING id" (signatureJob,electronic,cid,app,signedDoc)::IO[Only Int]
  let signedPath="/api/portal/signatures/"<>B.pack(show signatureLink)<>"/download"
  portal "GET" signedPath A.Null >>=expect 404
  void $ execute conn "UPDATE documents SET scan_status='Clean' WHERE id=?" (Only signedDoc)
  portal "GET" signedPath A.Null >>=expect 200
  stranger "GET" signedPath A.Null >>=expect 404
  call [] "GET" signedPath A.Null >>=expect 401
 putStrLn "Connected journey: proposal/contract lifecycle, PDF, portal isolation, timed tasks, overdue dismissal, Zoom sharing and payment instructions passed"
