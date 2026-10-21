{-# LANGUAGE OverloadedStrings #-}
module FeatureTests (run) where
import Control.Monad (unless,forM_)
import qualified Data.Aeson as A
import Data.Aeson ((.=),(.:))
import Data.Aeson.Types (parseMaybe)
import qualified Data.ByteString.Char8 as B
import qualified Data.ByteString.Lazy.Char8 as BL
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import Data.Time.Clock.POSIX (getPOSIXTime)
import System.Environment (setEnv,unsetEnv)
import qualified Network.Wai as W
import qualified Network.Wai.Test as WT
import Network.HTTP.Types (statusCode)
import ECC.Release (releaseContract)
import ECC.Store
import qualified ECC.DB as DB
import ECC.Models
import ECC.MFA
import ECC.Workflows (amountMinor,foldLine)

assert label ok=unless ok (fail label)
field key response=do
 value<-either fail pure (A.eitherDecode(WT.simpleBody response))
 maybe (fail("Missing field "++show key++" in "++show value)) pure (parseMaybe(A.withObject "response" (.: key)) value)
expect code response=assert ("Expected "++show code++", got "++show(WT.simpleStatus response)++": "++show(WT.simpleBody response)) (statusCode(WT.simpleStatus response)==code)
run :: Connection -> W.Application -> IO ()
run conn api=do
 let call headers method path body=WT.runSession (WT.srequest(WT.SRequest ((WT.setPath W.defaultRequest path){W.requestMethod=method,W.requestHeaders=("Content-Type","application/json"):headers}) (A.encode body))) api
     login otp=call [] "POST" "/api/auth/login" (A.object["lrEmail".=("admin@example.com"::T.Text),"lrPassword".=("correct-password-123"::T.Text),"lrOtp".=otp])
 logged<-login (Nothing::Maybe T.Text); expect 200 logged
 token<-TE.encodeUtf8 <$> (field "token" logged::IO T.Text)
 let admin=call [("Authorization","Bearer "<>token)]
     post section values=admin "POST" ("/api/workspace/"<>section) (A.object values)
 forM_ ["tasks","history","documents","reminders","search","reports","merge","security","appointments","invoices","portal","communication","mail","notifications","ageing","bottlenecks","trends"] $ \section ->admin "GET" ("/api/workspace/"<>section) A.Null >>=expect 200
 DB.addUser conn "workflow-staff@example.com" "Workflow staff" "consultant" "workflow-password-123"
 [Only staffId]<-query_ conn "SELECT id FROM users WHERE email='workflow-staff@example.com'"::IO[Only Int]
 client<-DB.insertClient conn (NewClient "Workflow client" (Just "workflow@example.com") (Just "+639991234567") (Just staffId))
 let cid=clientId client; owner="client:"<>T.pack(show cid)
 [Only tid]<-query conn "INSERT INTO tasks(client_id,title,due_date,assigned_to_id) VALUES (?,'Original','2020-01-01',1) RETURNING id" (Only cid)::IO[Only Int]
 let task rev=["id".=tid,"expectedRevision".=(rev::Int),"title".=("Reassigned task"::T.Text),"description".=("Follow up"::T.Text),"dueDate".=("2020-01-01"::T.Text),"priority".=("Urgent"::T.Text),"status".=("Pending"::T.Text),"assignee".=staffId,"recurrenceDays".=(7::Int)]
 post "tasks/save" (task 1)>>=expect 200
 post "tasks/save" (task 1)>>=expect 409
 assignment<-query conn "SELECT assigned_to_id,title FROM tasks WHERE id=?" (Only tid)::IO[(Int,T.Text)]
 assert "Full task update reassigns staff" (assignment==[(staffId,"Reassigned task")])
 [Only taskRev]<-query conn "SELECT revision FROM record_versions WHERE kind='tasks' AND record_id=?" (Only tid)::IO[Only Int]
 post "tasks/save" (filter ((/="assignee").fst) (task taskRev)++["assignee".=(999999::Int)])>>=expect 400
 post "reminders/save" ["task".=tid,"daysBefore".=(1::Int),"escalateAfter".=(2::Int),"enabled".=True]>>=expect 200
 [Only clientRev]<-query conn "SELECT revision FROM record_versions WHERE kind='clients' AND record_id=?" (Only cid)::IO[Only Int]
 let clientEdit=A.object["ncFullName".=("Updated workflow client"::T.Text),"expectedRevision".=clientRev]
 admin "PATCH" ("/api/clients/"<>B.pack(show cid)) clientEdit>>=expect 200
 admin "PATCH" ("/api/clients/"<>B.pack(show cid)) clientEdit>>=expect 409
 forM_ ["tasks","documents","history"] $ \section -> admin "GET" ("/api/workspace/record/client/"<>B.pack(show cid)<>"/"<>section) A.Null>>=expect 200
 forM_ [("tasks",tid),("clients",cid)] $ \(section,ident) ->admin "GET" ("/api/workspace/conflict/"<>section<>"/"<>B.pack(show ident)) A.Null>>=expect 200
 post "history/add" ["owner".=owner,"note".=("Client called; passport requested"::T.Text)]>>=expect 200
 let checklist rev status=["owner".=owner,"title".=("Passport"::T.Text),"status".=(status::T.Text),"required".=True]++rev
 post "documents/save" (checklist [] "Missing")>>=expect 200
 [Only rid]<-query conn "SELECT id FROM document_requests WHERE client_id=?" (Only cid)::IO[Only Int]
 document<-DB.insertDocument conn Nothing (Just cid) "passport.pdf" "application/pdf" "first version" (Just 1)
 let did=documentId document
 post "documents/attach" ["request".=rid,"document".=did,"expectedRevision".=(1::Int)]>>=expect 200
 admin "GET" ("/api/workspace/conflict/documents/"<>B.pack(show rid)) A.Null>>=expect 200
 admin "GET" ("/api/workspace/conflict/reminders/"<>B.pack(show tid)) A.Null>>=expect 200
 post "documents/save" (checklist ["id".=rid,"expectedRevision".=(2::Int)] "Approved")>>=expect 423
 _<-execute conn "UPDATE documents SET scan_status='Clean' WHERE id=?" (Only did)
 post "documents/save" (checklist ["id".=rid,"expectedRevision".=(2::Int)] "Approved")>>=expect 200
 admin "DELETE" ("/api/documents/"<>B.pack(show did)) A.Null>>=expect 409
 link<-post "portal/create" ["owner".=owner,"days".=(7::Int)];expect 200 link
 url<-field "url" link::IO T.Text
 let portalToken=T.drop 7(snd(T.breakOn "#token=" url))
 exchange<-call [] "POST" "/api/portal/exchange" (A.object["token".=portalToken]);expect 200 exchange
 call [] "POST" "/api/portal/exchange" (A.object["token".=portalToken])>>=expect 401
 cookie<-maybe (fail "Portal cookie absent") (pure.B.takeWhile(/=';')) (lookup "Set-Cookie" (WT.simpleHeaders exchange))
 let portal method path=call [("Cookie",cookie),("X-ECC-Contract",TE.encodeUtf8 releaseContract)] method path A.Null
 portal "GET" ("/api/portal/documents/"<>B.pack(show did))>>=expect 404
 [Only linkId]<-query conn "SELECT id FROM portal_links WHERE client_id=?" (Only cid)::IO[Only Int]
 post "portal/grant" ["id".=linkId,"document".=did]>>=expect 200
 portal "GET" ("/api/portal/documents/"<>B.pack(show did))>>=expect 200
 second<-DB.insertDocument conn Nothing (Just cid) "passport-v2.pdf" "application/pdf" "second version" (Just 1)
 post "documents/attach" ["request".=rid,"document".=documentId second,"expectedRevision".=(3::Int)]>>=expect 200
 portal "GET" ("/api/portal/documents/"<>B.pack(show did))>>=expect 404
 let upload requestId=WT.runSession (WT.srequest(WT.SRequest
       ((WT.setPath W.defaultRequest ("/api/portal/requests/"<>B.pack(show(requestId::Int))<>"/upload")){W.requestMethod="POST",W.requestHeaders=[("Cookie",cookie),("X-ECC-Contract",TE.encodeUtf8 releaseContract),("Content-Type","multipart/form-data; boundary=ecc-test-boundary")]})
       (BL.pack "--ecc-test-boundary\r\nContent-Disposition: form-data; name=\"file\"; filename=\"client.pdf\"\r\nContent-Type: application/pdf\r\n\r\nclient uploaded bytes\r\n--ecc-test-boundary--\r\n"))) api
 upload 999999>>=expect 404
 upload rid>>=expect 200
 _<-execute conn "UPDATE portal_upload_limits SET files=20 WHERE link_id=?" (Only linkId)
 upload rid>>=expect 429
 target<-DB.insertClient conn (NewClient "Merged survivor" Nothing Nothing (Just staffId))
 let merge=["entity".=("clients"::T.Text),"source".=cid,"target".=clientId target]
 preview<-post "merge/preview" merge;expect 200 preview
 sourceRev<-field "sourceRevision" preview::IO Int
 targetRev<-field "targetRevision" preview::IO Int
 _<-execute conn "INSERT INTO work_history(client_id,kind,note) VALUES (?,'note','Arrived after preview')" (Only cid)
 post "merge/confirm" (merge++["sourceRevision".=sourceRev,"targetRevision".=targetRev,"confirmation".=("MERGE"::T.Text)])>>=expect 409
 currentPreview<-post "merge/preview" merge
 currentSourceRev<-field "sourceRevision" currentPreview::IO Int
 post "merge/confirm" (merge++["sourceRevision".=currentSourceRev,"targetRevision".=targetRev,"confirmation".=("MERGE"::T.Text)])>>=expect 200
 portal "GET" "/api/portal">>=expect 401
 docs<-query conn "SELECT count(*) FROM documents WHERE client_id=?" (Only(clientId target))::IO[Only Int]
 assert "Merge preserves staff versions and client upload" (docs==[Only 3])
 billing<-DB.insertClient conn (NewClient "Billing client" (Just "billing@example.com") Nothing (Just 1))
 let invoice status=["owner".=("client:"<>T.pack(show(clientId billing))),"description".=("Consultation"::T.Text),"currency".=("PHP"::T.Text),"amount".=("125.50"::T.Text),"dueDate".=("2030-01-01"::T.Text),"status".=(status::T.Text)]
 post "invoices/save" (invoice "Draft")>>=expect 200
 [Only iid]<-query conn "SELECT id FROM invoices WHERE client_id=?" (Only(clientId billing))::IO[Only Int]
 post "invoices/save" (invoice "Issued"++["id".=iid,"expectedRevision".=(1::Int)])>>=expect 200
 post "invoices/send" ["id".=iid]>>=expect 200
 [Only caseId]<-query conn "INSERT INTO cases(client_id,stage) VALUES (?,'Submitted') RETURNING id" (Only(clientId billing))::IO[Only Int]
 let caseOwner="case:"<>T.pack(show caseId)
 post "tasks/create" ["owner".=caseOwner,"title".=("Case scoped task"::T.Text),"assignee".=(1::Int),"priority".=("High"::T.Text)]>>=expect 200
 scoped<-admin "GET" ("/api/workspace/record/case/"<>B.pack(show caseId)<>"/tasks?q=Case%20scoped") A.Null
 expect 200 scoped
 scopedRows<-field "rows" scoped::IO[A.Value]
 assert "Case scope includes its new task" (length scopedRows==1)
 admin "GET" ("/api/workspace/conflict/cases/"<>B.pack(show caseId)) A.Null>>=expect 200
 admin "GET" "/api/workspace/conflict/users/1" A.Null>>=expect 200
 admin "GET" "/api/workspace/reports.csv" A.Null>>=expect 200
 post "documents/save" ["owner".=caseOwner,"title".=("Case passport"::T.Text),"status".=("Missing"::T.Text)]>>=expect 200
 [Only caseRequest]<-query conn "SELECT id FROM document_requests WHERE case_id=?" (Only caseId)::IO[Only Int]
 let staffUpload=WT.runSession (WT.srequest(WT.SRequest
       ((WT.setPath W.defaultRequest ("/api/workspace/documents/"<>B.pack(show caseRequest)<>"/upload")){W.requestMethod="POST",W.requestHeaders=[("Authorization","Bearer "<>token),("Content-Type","multipart/form-data; boundary=staff-boundary")]})
       (BL.pack "--staff-boundary\r\nContent-Disposition: form-data; name=\"expectedRevision\"\r\n\r\n1\r\n--staff-boundary\r\nContent-Disposition: form-data; name=\"file\"; filename=\"passport.txt\"\r\nContent-Type: text/plain\r\n\r\nscan me\r\n--staff-boundary--\r\n"))) api
 staffUpload>>=expect 200
 staffUpload>>=expect 409
 [Only quarantineDoc]<-query conn "SELECT document_id FROM document_versions WHERE request_id=?" (Only caseRequest)::IO[Only Int]
 admin "GET" ("/api/documents/"<>B.pack(show quarantineDoc)<>"/download") A.Null>>=expect 423
 _<-execute conn "UPDATE documents SET scan_status='Error' WHERE id=?" (Only quarantineDoc)
 post "documents/rescan" ["id".=caseRequest]>>=expect 200
 post "documents/rescan" ["id".=caseRequest]>>=expect 400
 staffSession<-call [] "POST" "/api/auth/login" (A.object["lrEmail".=("workflow-staff@example.com"::T.Text),"lrPassword".=("workflow-password-123"::T.Text)])
 expect 200 staffSession
 staffToken<-TE.encodeUtf8 <$> (field "token" staffSession::IO T.Text)
 let staffCall=call [("Authorization","Bearer "<>staffToken)]
 staffCall "GET" ("/api/workspace/record/client/"<>B.pack(show(clientId billing))<>"/tasks") A.Null>>=expect 404
 staffCall "GET" "/api/workspace/report-export/ageing" A.Null>>=expect 403
 staffCall "POST" "/api/workspace/mail/retry" (A.object["id".=(1::Int)])>>=expect 403
 staffCall "POST" "/api/workspace/security/reset-mfa" (A.object["user".=staffId])>>=expect 403
 forM_ ["review","outstanding","expiring"] $ \mode -> admin "GET" ("/api/workspace/record/case/"<>B.pack(show caseId)<>"/documents?q="<>mode) A.Null>>=expect 200
 [Only mid]<-query_ conn "INSERT INTO mail_outbox(recipient,subject,body,attempts,last_error) VALUES ('test@example.com','Failure','Retry body',5,'ConnectionError') RETURNING id"::IO[Only Int]
 post "mail/retry" ["id".=mid]>>=expect 200
 post "mail/retry" ["id".=mid]>>=expect 409
 forM_ ["ageing","bottlenecks","trends"] $ \kind -> admin "GET" ("/api/workspace/report-export/"<>kind) A.Null>>=expect 200
 -- Printable reports must include records beyond the operational 50-row page.
 forM_ [1..55::Int] $ \n -> execute conn "INSERT INTO cases(client_id,stage,service_category,created_at) VALUES (?,'Documents Under Review',?,'2020-01-01 00:00:00')" (clientId billing,"Print fixture "<>T.pack(show n))
 printable<-admin "GET" "/api/workspace/ageing?q=2020-01-01,2020-01-01" A.Null
 expect 200 printable
 printableRows<-field "rows" printable::IO[A.Value]
 assert "Printable report includes more than the first 50 rows" (length printableRows >= 55)
 staffCall "GET" "/api/workspace/ageing" A.Null>>=expect 403
 post "notifications/preferences" ["assignments".=False,"deadlines".=True,"documents".=True,"escalations".=True,"emailEnabled".=False]>>=expect 200
 post "notifications/preferences" ["expectedRevision".=(1::Int),"assignments".=True]>>=expect 200
 post "notifications/preferences" ["expectedRevision".=(1::Int)]>>=expect 409
 _<-execute conn "INSERT INTO cases(client_id,stage,created_at) VALUES (?,'Approved','2000-01-01 00:00:00')" (Only(clientId billing))
 report<-admin "GET" "/api/workspace/reports" A.Null
 expect 200 report
 reportRows<-field "rows" report::IO[A.Value]
 assert "Reports count completion date rather than case creation date" (any (\row -> (parseMaybe(A.withObject "report" (.: "completedCases")) row::Maybe Int)==Just 1) reportRows)
 assert "Money rejects negatives and overflow" (amountMinor "125.50"==Just 12550 && amountMinor "-0.01"==Nothing && amountMinor "999999999999999999999999"==Nothing)
 let appointment start=["owner".=("client:"<>T.pack(show(clientId billing))),"title".=T.replicate 200 "界","assignee".=(1::Int),"startsAt".=(start::T.Text),"endsAt".=("2030-01-02T11:00"::T.Text),"status".=("Scheduled"::T.Text)]
 post "appointments/save" (appointment "2030-01-02T10:00")>>=expect 200
 post "appointments/save" (appointment "2030-01-02T10:30")>>=expect 409
 admin "GET" "/api/workspace/calendar.ics" A.Null>>=expect 200
 assert "Calendar folds UTF-8 without exceeding 75 octets" (all ((<=75).B.length.TE.encodeUtf8) (foldLine 75 (T.replicate 200 "界")))
 admin "GET" "/api/workspace/search?q=639991234567" A.Null>>=expect 200
 post "search/save" ["name".=("Overdue"::T.Text),"entity".=("tasks"::T.Text),"overdue".=True,"mine".=False]>>=expect 200
 [Only vid]<-query_ conn "SELECT max(id) FROM saved_views"::IO[Only Int]
 post "search/apply" ["id".=vid]>>=expect 200
 forM_ [1..55::Int] $ \n ->do
  _<-execute conn "INSERT INTO tasks(client_id,title,due_date,assigned_to_id) VALUES (?,?,'2020-01-01',1)" (clientId billing,"Later task "<>T.pack(show n))
  pure ()
 savedPage<-admin "GET" ("/api/workspace/search?q=%40view%3A"<>B.pack(show vid)<>"&offset=50") A.Null
 expect 200 savedPage
 results<-field "rows" savedPage::IO[A.Value]
 assert "Saved views expose later pages" (not(null results))
 DB.addUser conn "suspended@example.com" "Suspended" "consultant" "suspended-password-123"
 [Only suspendedId]<-query_ conn "SELECT id FROM users WHERE email='suspended@example.com'"::IO[Only Int]
 post "security/suspend" ["user".=suspendedId]>>=expect 200
 call [] "POST" "/api/auth/login" (A.object["lrEmail".=("suspended@example.com"::T.Text),"lrPassword".=("suspended-password-123"::T.Text)])>>=expect 401
 forM_ [(59,46119246),(1111111109,68084774),(1234567890,91819424),(20000000000,77737706)] $ \(time,result)->assert "RFC 6238 SHA-256 vector" (totp "12345678901234567890123456789012" (time `div`30) 8==T.pack(show(result::Int)))
 setEnv "REQUIRE_ADMIN_MFA" "true"
 admin "GET" "/api/workspace/tasks" A.Null>>=expect 403
 let password=["password".=("correct-password-123"::T.Text)]
 setup<-post "security/setup" password;expect 200 setup
 secret<-field "secret" setup::IO T.Text
 step<-floor . (/30) <$>getPOSIXTime
 enabled<-post "security/enable" (password++["code".=totp(unbase32 secret) step 6]);expect 200 enabled
 codes<-field "recoveryCodes" enabled::IO[T.Text]
 -- Administrative recovery requires fresh proof, never resets the acting admin,
 -- and revokes both existing sessions and recovery codes of the target account.
 let recoverAccount pw code uid=["user".=(uid::Int),"password".=(pw::T.Text),"code".=(code::T.Text),"reason".=("Identity verified in person; device lost"::T.Text)]
 post "security/reset-mfa" (recoverAccount "correct-password-123" (codes!!2) 1)>>=expect 400
 _<-execute conn "UPDATE users SET mfa_secret='JBSWY3DPEHPK3PXP' WHERE id=?" (Only staffId)
 _<-execute conn "INSERT INTO mfa_recovery_codes(user_id,code_hash) VALUES (?,'old-recovery-hash')" (Only staffId)
 post "security/reset-mfa" (recoverAccount "wrong-password" (codes!!2) staffId)>>=expect 403
 [Only stillEnrolled]<-query conn "SELECT mfa_secret IS NOT NULL FROM users WHERE id=?" (Only staffId)::IO[Only Bool]
 assert "Failed recovery preserves target MFA" stillEnrolled
 post "security/reset-mfa" (recoverAccount "correct-password-123" "invalid-code" staffId)>>=expect 403
 post "security/reset-mfa" (recoverAccount "correct-password-123" (codes!!2) staffId)>>=expect 200
 cleared<-query conn "SELECT mfa_secret,mfa_pending FROM users WHERE id=?" (Only staffId)::IO[(Maybe T.Text,Maybe T.Text)]
 assert "Recovery clears target enrollment" (cleared==[(Nothing,Nothing)])
 [Only remainingSessions]<-query conn "SELECT count(*) FROM sessions WHERE user_id=?" (Only staffId)::IO[Only Int]
 [Only remainingCodes]<-query conn "SELECT count(*) FROM mfa_recovery_codes WHERE user_id=?" (Only staffId)::IO[Only Int]
 assert "Recovery revokes all target sessions and recovery codes" (remainingSessions==0 && remainingCodes==0)
 [Only auditCount]<-query conn "SELECT count(*) FROM audit_log WHERE entity_type='user' AND entity_id=? AND action='mfa_changed' AND entity_name='Administrator MFA recovery' AND actor_id=1" (Only staffId)::IO[Only Int]
 [Only queuedNotice]<-query_ conn "SELECT count(*) FROM mail_outbox WHERE recipient='workflow-staff@example.com' AND subject='Your ECC authenticator was reset'"::IO[Only Int]
 assert "Recovery is audited and queues account-owner notification" (auditCount==1 && queuedNotice==1)
 assert "Eight recovery codes supplied" (length codes==8)
 admin "GET" "/api/workspace/tasks" A.Null>>=expect 200
 login (Nothing::Maybe T.Text)>>=expect 401
 login (Just(head codes))>>=expect 200
 login (Just(head codes))>>=expect 401
 post "security/disable" (password++["code".=codes!!1])>>=expect 200
 unsetEnv "REQUIRE_ADMIN_MFA"
 -- Exercise expiry, revocation and logout independently of merge invalidation.
 finalLogin<-login (Nothing::Maybe T.Text);expect 200 finalLogin
 finalToken<-TE.encodeUtf8 <$> (field "token" finalLogin::IO T.Text)
 let finalAdmin=call [("Authorization","Bearer "<>finalToken)]
 portalClient<-DB.insertClient conn (NewClient "Portal lifecycle" Nothing Nothing (Just 1))
 let portalOwner="client:"<>T.pack(show(clientId portalClient))
 created<-finalAdmin "POST" "/api/workspace/portal/create" (A.object["owner".=portalOwner,"days".=(1::Int)])
 expect 200 created
 createdUrl<-field "url" created::IO T.Text
 let lifecycleToken=T.drop 7(snd(T.breakOn "#token=" createdUrl))
 [Only lifecycleId]<-query conn "SELECT id FROM portal_links WHERE client_id=?" (Only(clientId portalClient))::IO[Only Int]
 _<-execute conn "UPDATE portal_links SET expires_at=datetime('now','-1 second') WHERE id=?" (Only lifecycleId)
 call [] "POST" "/api/portal/exchange" (A.object["token".=lifecycleToken])>>=expect 401
 _<-execute conn "UPDATE portal_links SET expires_at=datetime('now','+1 day') WHERE id=?" (Only lifecycleId)
 lifecycleExchange<-call [] "POST" "/api/portal/exchange" (A.object["token".=lifecycleToken]);expect 200 lifecycleExchange
 lifecycleCookie<-maybe (fail "Lifecycle portal cookie absent") (pure.B.takeWhile(/=';')) (lookup "Set-Cookie" (WT.simpleHeaders lifecycleExchange))
 let clientCall method path=call [("Cookie",lifecycleCookie),("X-ECC-Contract",TE.encodeUtf8 releaseContract)] method path A.Null
 clientCall "GET" "/api/portal">>=expect 200
 finalAdmin "POST" "/api/workspace/portal/revoke" (A.object["id".=lifecycleId])>>=expect 200
 clientCall "GET" "/api/portal">>=expect 401
 clientCall "POST" "/api/portal/logout">>=expect 200
 putStrLn "Workflow, inline work, conflicts, quarantine, mail retry, reports, notifications and MFA integration checks passed"
