{-# LANGUAGE OverloadedStrings #-}
module ClientApplicationTests (run) where

import Control.Monad (unless, void)
import qualified Data.Aeson as A
import Data.Aeson ((.=),(.:))
import Data.Aeson.Types (parseMaybe)
import qualified Data.ByteString as B
import qualified Data.ByteString.Char8 as BC
import qualified Data.ByteString.Lazy as BL
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import Network.HTTP.Types (statusCode)
import qualified Network.Wai as W
import qualified Network.Wai.Test as WT
import ECC.Store
import qualified ECC.DB as DB
import ECC.Models
import ECC.ProfilePhotos (photoMime)

assert :: String -> Bool -> IO ()
assert label ok = unless ok (fail label)

expect :: Int -> WT.SResponse -> IO ()
expect code response = assert ("Expected "++show code++", got "++show(WT.simpleStatus response)++": "++show(WT.simpleBody response)) (statusCode(WT.simpleStatus response)==code)

field :: A.FromJSON a => A.Key -> WT.SResponse -> IO a
field key response = do
 value<-either fail pure (A.eitherDecode(WT.simpleBody response))
 maybe (fail("Missing field "++show key)) pure (parseMaybe(A.withObject "response" (.: key)) value)

run :: Connection -> W.Application -> IO ()
run conn api = do
 let call headers method path body = WT.runSession (WT.srequest(WT.SRequest ((WT.setPath W.defaultRequest path){W.requestMethod=method,W.requestHeaders=("Content-Type","application/json"):headers}) (A.encode body))) api
 logged<-call [] "POST" "/api/auth/login" (A.object["lrEmail".=("admin@example.com"::T.Text),"lrPassword".=("correct-password-123"::T.Text)])
 expect 200 logged
 token<-TE.encodeUtf8 <$> (field "token" logged::IO T.Text)
 let headers=[("Authorization","Bearer "<>token)]
     admin=call headers
 admin "GET" "/api/ready" A.Null>>=expect 200
 call [] "GET" "/api/clients" A.Null>>=expect 401
 createdLead<-admin "POST" "/api/leads" (A.object
   ["nlFullName".=("Student conversion"::T.Text),"nlEmail".=("student-conversion@example.com"::T.Text)
   ,"nlSource".=("Website"::T.Text),"nlQuality".=("Hot"::T.Text),"nlStage".=("Qualified"::T.Text)
   ,"nlDestination".=("Canada"::T.Text),"nlService".=("Student Visa"::T.Text)])
 expect 200 createdLead
 lid<-field "leadId" createdLead::IO Int
 searched<-admin "GET" "/api/leads?q=student-conversion%40example.com" A.Null
 expect 200 searched
 matches<-either fail pure (A.eitherDecode(WT.simpleBody searched))::IO[A.Value]
 assert "HTTP lead entry persists and is searchable on either database"
   (any (\row -> (parseMaybe(A.withObject "lead" (.: "leadId")) row::Maybe Int)==Just lid) matches)
 task<-DB.insertTask conn (NewTask (Just lid) Nothing "Student task" Nothing Nothing (Just "High")) 1
 document<-DB.insertDocument conn (Just lid) Nothing "transcript.pdf" "application/pdf" "retained transcript" (Just 1)
 let convertPath="/api/leads/"<>BC.pack(show lid)<>"/convert"
 converted<-admin "POST" convertPath A.Null
 expect 200 converted
 cid<-field "id" converted::IO Int
 retried<-admin "POST" convertPath A.Null
 expect 200 retried
 again<-field "id" retried::IO Int
 assert "Client conversion retries return the same record" (cid==again)
 [Only legacyTables]<-query_ conn (if isPostgres conn then "SELECT count(*) FROM information_schema.tables WHERE table_schema=current_schema() AND table_name IN ('student_profiles','student_photos')" else "SELECT count(*) FROM sqlite_master WHERE type='table' AND name IN ('student_profiles','student_photos')")::IO[Only Int]
 assert "Client/Application migration removes the separate student tables" (legacyTables==0)
 retained<-query conn "SELECT client_id FROM documents WHERE id=?" (Only(documentId document))::IO[Only Int]
 assigned<-query conn "SELECT client_id FROM tasks WHERE id=?" (Only(taskId task))::IO[Only Int]
 [Only cases]<-query conn "SELECT count(*) FROM cases WHERE client_id=?" (Only cid)::IO[Only Int]
 assert "Client conversion retains documents, tasks and case" (retained==[Only cid] && assigned==[Only cid] && cases==1)
 [Only appId]<-query conn "SELECT id FROM cases WHERE client_id=?" (Only cid)::IO[Only Int]
 [Only appRevision]<-query conn "SELECT revision FROM record_versions WHERE kind='cases' AND record_id=?" (Only appId)::IO[Only Int]
 let owner="client:"<>T.pack(show cid)
     profile rev=A.object["id".=appId,"owner".=owner,"category".=("Student Visa"::T.Text),"destination".=("Canada"::T.Text),"stage".=("Submitted"::T.Text),"deadline".=("2020-01-01"::T.Text),"intakeDate".=("2030-09-01"::T.Text),"expectedRevision".=(rev::Int)]
 admin "POST" "/api/workspace/applications/save" (profile appRevision)>>=expect 200
 admin "POST" "/api/workspace/applications/save" (profile appRevision)>>=expect 409
 page<-admin "GET" "/api/workspace/applications?q=Student%20conversion&destination=Canada&stage=Submitted&intake=2030-09&officer=1" A.Null
 expect 200 page
 rows<-field "rows" page::IO[A.Value]
 assert "Application search combines destination, stage, intake and officer" (length rows==1)
 summary<-field "summary" page::IO[A.Value]
 assert "Filtered overview counts overdue work" (case summary of item:_ -> (parseMaybe(A.withObject "summary" (.: "total")) item::Maybe Int)==Just 1 && (parseMaybe(A.withObject "summary" (.: "overdue")) item::Maybe Int)==Just 1; _->False)
 admin "GET" ("/api/workspace/record/client/"<>BC.pack(show cid)<>"/applications") A.Null>>=expect 200
 admin "GET" ("/api/workspace/conflict/applications/"<>BC.pack(show appId)) A.Null>>=expect 200
 let template=A.object["name".=("Reusable student requirements"::T.Text),"category".=("Student Visa"::T.Text),"destination".=("Canada"::T.Text),"requiredDocuments".=("Passport\nAcademic records"::T.Text),"optionalDocuments".=("Supporting letter"::T.Text)]
 admin "POST" "/api/workspace/checklist-templates/save" template>>=expect 200
 [Only templateId]<-query_ conn "SELECT id FROM checklist_templates WHERE name='Reusable student requirements'"::IO[Only Int]
 let applyChecklist=do
      [Only rev]<-query conn "SELECT revision FROM record_versions WHERE kind='cases' AND record_id=?" (Only appId)::IO[Only Int]
      admin "POST" "/api/workspace/applications/checklist" (A.object["id".=appId,"template".=templateId,"expectedRevision".=rev])>>=expect 200
 applyChecklist
 applyChecklist
 [Only requirements]<-query conn "SELECT count(*) FROM document_requests WHERE case_id=?" (Only appId)::IO[Only Int]
 assert "Reapplying a checklist never duplicates its requirements" (requirements==3)
 admin "GET" ("/api/workspace/conflict/checklist-templates/"<>BC.pack(show templateId)) A.Null>>=expect 200
 admin "GET" "/api/workspace/applications?intake=not-a-month" A.Null>>=expect 400
 void $ execute conn "UPDATE cases SET next_deadline=date('now','+3 days') WHERE id=?" (Only appId)
 upcomingPage<-admin "GET" "/api/workspace/applications?q=Student%20conversion" A.Null
 upcomingSummary<-field "summary" upcomingPage::IO[A.Value]
 assert "Overview includes deadlines in the next seven days" (case upcomingSummary of item:_ -> (parseMaybe(A.withObject "summary" (.: "upcoming")) item::Maybe Int)==Just 1; _->False)
 void $ execute conn "UPDATE cases SET stage='Approved',next_deadline='2020-01-01' WHERE id=?" (Only appId)
 closedPage<-admin "GET" "/api/workspace/applications?q=Student%20conversion" A.Null
 closedSummary<-field "summary" closedPage::IO[A.Value]
 assert "Completed applications are excluded from overdue counts" (case closedSummary of item:_ -> (parseMaybe(A.withObject "summary" (.: "overdue")) item::Maybe Int)==Just 0; _->False)
 void $ execute conn "UPDATE cases SET stage='Submitted' WHERE id=?" (Only appId)
 nextSteps<-admin "GET" ("/api/clients/"<>BC.pack(show cid)<>"/profile") A.Null
 expect 200 nextSteps
 next<-field "nextSteps" nextSteps::IO A.Value
 assert "Client next steps report outstanding required documents" ((parseMaybe(A.withObject "steps" (.: "outstandingDocuments")) next::Maybe Int)==Just 2)
 -- School details, milestones and contact logs must persist without sending messages.
 [Only currentRev]<-query conn "SELECT revision FROM record_versions WHERE kind='cases' AND record_id=?" (Only appId)::IO[Only Int]
 let detailedProfile=A.object["id".=appId,"owner".=owner,"category".=("Student Visa"::T.Text),"destination".=("Canada"::T.Text),"stage".=("Submitted"::T.Text),"institution".=("Example College"::T.Text),"program".=("Nursing"::T.Text),"offerStatus".=("Conditional offer"::T.Text),"enrollmentStatus".=("Pending"::T.Text),"expectedRevision".=currentRev]
 admin "POST" "/api/workspace/applications/save" detailedProfile>>=expect 200
 [Only institution]<-query conn "SELECT institution FROM cases WHERE id=?" (Only appId)::IO[Only T.Text]
 assert "Application retains school details" (institution=="Example College")
 [Only schoolAudits]<-query conn "SELECT count(*) FROM audit_log WHERE entity_type='case' AND entity_id=? AND changes LIKE '%institution%' AND changes LIKE '%Example College%'" (Only appId)::IO[Only Int]
 assert "School edits appear in the audit trail" (schoolAudits>0)
 byProgram<-admin "GET" "/api/workspace/applications?q=Nursing" A.Null
 programRows<-field "rows" byProgram::IO[A.Value]
 assert "Application search includes the program" (not(null programRows))
 let milestone status date=A.object["owner".=("case:"<>T.pack(show appId)),"kind".=("Offer"::T.Text),"title".=("Review offer"::T.Text),"status".=(status::T.Text),"plannedOn".=("2020-01-01"::T.Text),"completedOn".=(date::T.Text)]
 admin "POST" "/api/workspace/milestones/save" (milestone "Completed" "")>>=expect 400
 admin "POST" "/api/workspace/milestones/save" (milestone "Planned" "")>>=expect 200
 [Only mid]<-query conn "SELECT id FROM application_milestones WHERE case_id=?" (Only appId)::IO[Only Int]
 let milestoneEdit rev=A.object["id".=mid,"owner".=("case:"<>T.pack(show appId)),"kind".=("Offer"::T.Text),"title".=("Review offer"::T.Text),"status".=("Completed"::T.Text),"completedOn".=("2020-01-02"::T.Text),"expectedRevision".=(rev::Int)]
 admin "POST" "/api/workspace/milestones/save" (milestoneEdit 1)>>=expect 200
 admin "POST" "/api/workspace/milestones/save" (milestoneEdit 1)>>=expect 409
 admin "GET" ("/api/workspace/conflict/milestones/"<>BC.pack(show mid)) A.Null>>=expect 200
 [Only beforeMail]<-query_ conn "SELECT count(*) FROM mail_outbox"::IO[Only Int]
 admin "POST" "/api/workspace/contact-log/add" (A.object["owner".=owner,"channel".=("WhatsApp"::T.Text),"direction".=("Outgoing"::T.Text),"outcome".=("Follow-up needed"::T.Text),"occurredOn".=("2020-01-01"::T.Text),"note".=("Asked student to review offer"::T.Text)])>>=expect 200
 [Only afterMail]<-query_ conn "SELECT count(*) FROM mail_outbox"::IO[Only Int]
 assert "Logging a conversation never queues a message" (beforeMail==afterMail)
 contacts<-admin "GET" "/api/workspace/contact-log?q=review%20offer" A.Null
 contactRows<-field "rows" contacts::IO[A.Value]
 assert "Contact log retains the conversation" (not(null contactRows))
 void $ execute conn "UPDATE clients SET email='duplicate@example.test',phone='+63 (917) 555-1234' WHERE id=?" (Only cid)
 let duplicate exclude=A.object["kind".=("clients"::T.Text),"email".=("DUPLICATE@example.test"::T.Text),"phone".=("+639175551234"::T.Text),"exclude".=(exclude::Int)]
 found<-admin "POST" "/api/contacts/check" (duplicate 0)
 expect 200 found
 matches<-field "matches" found::IO[A.Value]
 assert "Duplicate checks normalize email case and phone formatting" (not(null matches))
 excluded<-admin "POST" "/api/contacts/check" (duplicate cid)
 withoutSelf<-field "matches" excluded::IO[A.Value]
 assert "Editing a student excludes its own contact details" (null withoutSelf)
 -- A real 1x1 PNG. Content type is derived from bytes, not supplied filename.
 let png=B.pack [137,80,78,71,13,10,26,10,0,0,0,13,73,72,68,82,0,0,0,1,0,0,0,1,8,4,0,0,0,181,28,12,2,0,0,0,11,73,68,65,84,120,218,99,100,248,15,0,1,5,1,1,39,24,227,102,0,0,0,0,73,69,78,68,174,66,96,130]
 assert "Photo type validation accepts PNG and rejects SVG and malformed JPEG" (photoMime png==Just "image/png" && photoMime "<svg onload='alert(1)'/>"==Nothing && photoMime (B.pack[255,216,255,192,0,8])==Nothing)
 let photoPath="/api/clients/"<>BC.pack(show cid)<>"/photo"
     upload expected bytes=WT.runSession (WT.srequest(WT.SRequest
       ((WT.setPath W.defaultRequest photoPath){W.requestMethod="POST",W.requestHeaders=("Content-Type","multipart/form-data; boundary=student-photo-boundary"):headers})
       (BL.fromStrict ("--student-photo-boundary\r\nContent-Disposition: form-data; name=\"expectedDocumentId\"\r\n\r\n"<>BC.pack(show(expected::Int))<>"\r\n--student-photo-boundary\r\nContent-Disposition: form-data; name=\"file\"; filename=\"student.png\"\r\nContent-Type: image/png\r\n\r\n"<>bytes<>"\r\n--student-photo-boundary--\r\n")))) api
 upload 0 "<svg/>" >>=expect 400
 upload 0 png >>=expect 200
 upload 0 png >>=expect 409
 [Only photoId]<-query conn "SELECT document_id FROM client_photos WHERE client_id=?" (Only cid)::IO[Only Int]
 admin "GET" photoPath A.Null>>=expect 423
 void $ execute conn "UPDATE documents SET scan_status='Error' WHERE id=?" (Only photoId)
 admin "POST" (photoPath<>"/rescan") A.Null>>=expect 200
 admin "GET" photoPath A.Null>>=expect 423
 void $ execute conn "UPDATE documents SET scan_status='Clean' WHERE id=?" (Only photoId)
 displayed<-admin "GET" photoPath A.Null
 expect 200 displayed
 assert "Clean photo is served with safe content type and exact bytes" (lookup "Content-Type" (WT.simpleHeaders displayed)==Just "image/png" && BL.toStrict(WT.simpleBody displayed)==png && lookup "X-Content-Type-Options" (WT.simpleHeaders displayed)==Just "nosniff")
 -- Viewers cannot convert, edit profiles or upload photos.
 DB.addUser conn "student-viewer@example.com" "Student viewer" "viewer" "student-viewer-password"
 viewerLogin<-call [] "POST" "/api/auth/login" (A.object["lrEmail".=("student-viewer@example.com"::T.Text),"lrPassword".=("student-viewer-password"::T.Text)])
 viewerToken<-TE.encodeUtf8 <$> (field "token" viewerLogin::IO T.Text)
 let viewer=call [("Authorization","Bearer "<>viewerToken)]
 [Only viewerId]<-query_ conn "SELECT id FROM users WHERE email='student-viewer@example.com'"::IO[Only Int]
 void $ execute conn "UPDATE clients SET case_officer_id=? WHERE id=?" (viewerId,cid)
 viewer "GET" photoPath A.Null>>=expect 200
 viewer "POST" convertPath A.Null>>=expect 404
 viewer "POST" "/api/workspace/applications/save" (profile 2)>>=expect 403
 viewer "POST" photoPath A.Null>>=expect 403
 viewer "POST" "/api/workspace/checklist-templates/save" template>>=expect 403
 -- Access is still controlled by the existing assigned-record policy.
 [Only staffId]<-query_ conn "SELECT id FROM users WHERE email='workflow-staff@example.com'"::IO[Only Int]
 void $ execute conn "UPDATE clients SET case_officer_id=? WHERE id=?" (staffId,cid)
 DB.addUser conn "unrelated-student-staff@example.com" "Other staff" "consultant" "unrelated-staff-password"
 otherLogin<-call [] "POST" "/api/auth/login" (A.object["lrEmail".=("unrelated-student-staff@example.com"::T.Text),"lrPassword".=("unrelated-staff-password"::T.Text)])
 otherToken<-TE.encodeUtf8 <$> (field "token" otherLogin::IO T.Text)
 let other=call [("Authorization","Bearer "<>otherToken)]
 other "GET" photoPath A.Null>>=expect 404
 other "GET" ("/api/clients/"<>BC.pack(show cid)<>"/profile") A.Null>>=expect 404
 hidden<-other "GET" "/api/workspace/applications?q=Student%20conversion" A.Null
 expect 200 hidden
 hiddenRows<-field "rows" hidden::IO[A.Value]
 assert "Application filters do not expose another officer's records" (null hiddenRows)
 other "POST" "/api/workspace/checklist-templates/save" template>>=expect 403
 -- A case-insert failure rolls the entire lead conversion back.
 failedLead<-DB.insertLead conn ((NewLead "Blocked conversion" Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing){nlService=Just "Student Visa",nlDestination=Just "Canada"}) 1
 [Only beforeFailure]<-query_ conn "SELECT count(*) FROM clients"::IO[Only Int]
 if isPostgres conn
  then execScript conn "CREATE FUNCTION test_conversion_failure_fn() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'forced case insert failure' USING ERRCODE='23514'; END $$; CREATE TRIGGER test_conversion_failure BEFORE INSERT ON cases FOR EACH ROW EXECUTE FUNCTION test_conversion_failure_fn()"
  else void $ execute_ conn "CREATE TRIGGER test_conversion_failure BEFORE INSERT ON cases BEGIN SELECT RAISE(ABORT,'forced case insert failure'); END"
 admin "POST" ("/api/leads/"<>BC.pack(show(leadId failedLead))<>"/convert") A.Null>>=expect 409
 if isPostgres conn
  then execScript conn "DROP TRIGGER test_conversion_failure ON cases; DROP FUNCTION test_conversion_failure_fn()"
  else void $ execute_ conn "DROP TRIGGER test_conversion_failure"
 [Only rolledBack]<-query conn "SELECT converted_client_id IS NULL FROM leads WHERE id=?" (Only(leadId failedLead))::IO[Only Bool]
 [Only afterFailure]<-query_ conn "SELECT count(*) FROM clients"::IO[Only Int]
 assert "Failed conversion leaves no orphan client" (rolledBack && beforeFailure==afterFailure)
 -- Merge clients without dropping the profile photo.
 survivor<-DB.insertClient conn (NewClient "Student survivor" Nothing Nothing (Just staffId))
 let merge=A.object["entity".=("clients"::T.Text),"source".=cid,"target".=clientId survivor]
 preview<-admin "POST" "/api/workspace/merge/preview" merge
 expect 200 preview
 sourceRevision<-field "sourceRevision" preview::IO Int
 targetRevision<-field "targetRevision" preview::IO Int
 admin "POST" "/api/workspace/merge/confirm" (A.object["entity".=("clients"::T.Text),"source".=cid,"target".=clientId survivor,"sourceRevision".=sourceRevision,"targetRevision".=targetRevision,"confirmation".=("MERGE"::T.Text)])>>=expect 200
 moved<-query conn "SELECT document_id FROM client_photos WHERE client_id=?" (Only(clientId survivor))::IO[Only Int]
 assert "Merging preserves client photo" (moved==[Only photoId])
 integrity<-query_ conn (if isPostgres conn then "SELECT conname,0,conname,0 FROM pg_constraint WHERE contype='f' AND NOT convalidated" else "PRAGMA foreign_key_check")::IO[(T.Text,Int,T.Text,Int)]
 assert "Student changes preserve referential integrity" (null integrity)
 putStrLn "Client conversion, applications, filtered overview, templates, next steps, photo quarantine and permissions passed"
