{-# LANGUAGE OverloadedStrings #-}
module AccessTests (run) where

import Control.Exception (bracket)
import Control.Monad (forM_, unless)
import qualified Data.Aeson as A
import Data.Aeson ((.=), (.:))
import Data.Aeson.Types (parseMaybe)
import qualified Data.ByteString.Char8 as B
import qualified Data.ByteString.Lazy as BL
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import Network.HTTP.Types (statusCode)
import qualified Network.Wai as W
import qualified Network.Wai.Test as WT
import qualified Web.Scotty as S
import ECC.Store
import ECC.Migrations (runMigrations)
import ECC.Server (transactionalApplication)
import qualified ECC.DB as DB
import qualified ECC.Routes as Routes
import ECC.Models

run :: IO ()
run = bracket (openDatabase ":memory:") close $ \conn -> do
 runMigrations conn "migrations"
 forM_ [("admin","admin"),("staff","consultant"),("viewer","viewer")] $ \(name,role) -> DB.addUser conn (name<>"@access.test") name role "access-password-123"
 let env=DB.Env conn "access-test-secret-32-characters-long" False "http://localhost:4000" False
 app <- S.scottyApp (Routes.app env)
 let api=transactionalApplication conn app
     call token method path body=WT.runSession (WT.srequest (WT.SRequest ((WT.setPath W.defaultRequest path){W.requestMethod=method,W.requestHeaders=[("Content-Type","application/json")]++[("Authorization","Bearer "<>token) | not(B.null token)]}) (A.encode body))) api
     expect label code response=unless (statusCode(WT.simpleStatus response)==code) (fail(label++": "++show(WT.simpleStatus response)++" "++show(WT.simpleBody response)))
     login name=do
      response<-call "" "POST" "/api/auth/login" (A.object["lrEmail".=(name<>"@access.test"::T.Text),"lrPassword".=("access-password-123"::T.Text)])
      expect "Login" 200 response
      value<-either fail pure(A.eitherDecode(WT.simpleBody response))
      maybe (fail "Missing token") (pure . TE.encodeUtf8) (parseMaybe(A.withObject "login" (.: "token")) value)
 admin<-login "admin"
 staff<-login "staff"
 viewer<-login "viewer"
 [Only uid]<-query_ conn "SELECT id FROM users WHERE email='staff@access.test'" :: IO [Only Int]
 [Only vid]<-query_ conn "SELECT id FROM users WHERE email='viewer@access.test'" :: IO [Only Int]
 [Only aid]<-query_ conn "SELECT id FROM users WHERE email='admin@access.test'" :: IO [Only Int]
 own<-DB.insertClient conn (NewClient "Assigned client" Nothing Nothing (Just uid))
 other<-DB.insertClient conn (NewClient "Other client" Nothing Nothing (Just aid))
 doc<-DB.insertDocument conn Nothing (Just(clientId own)) "test.pdf" "application/pdf" "bytes" (Just uid)
 _<-execute conn "UPDATE documents SET scan_status='Clean' WHERE id=?" (Only(documentId doc))
 let clientPath c="/api/clients/"<>B.pack(show(clientId c))
     download="/api/documents/"<>B.pack(show(documentId doc))<>"/download"
     config userId rev scope granted=A.object (["user".=userId,"expectedRevision".=rev,"accessLevel".=scope,"password".=("access-password-123"::T.Text)]++[key .= (if name `elem` granted then "allowed"::T.Text else "denied") | (key,name)<-[("edit","edit"),("delete","delete"),("download","download"),("export","export"),("email","email"),("portal","portal")]])
     save tok value=call tok "POST" "/api/workspace/security/access" value
     restricted=config uid (0::Int) ("assigned"::T.Text) ([]::[T.Text])
 call staff "GET" (clientPath other) A.Null >>=expect "Existing all-record access" 200
 call staff "GET" download A.Null >>=expect "Default download allowed" 200
 save staff restricted >>=expect "Staff cannot change access" 403
 save viewer restricted >>=expect "Viewer cannot change access" 403
 save admin (config aid (0::Int) ("assigned"::T.Text) ([]::[T.Text])) >>=expect "Admin cannot be locked out" 400
 save admin (config vid (0::Int) ("all"::T.Text) (["edit"]::[T.Text])) >>=expect "Viewer role ceiling" 400
 save admin restricted >>=expect "Admin restricts staff" 200
 save admin restricted >>=expect "Stale access update rejected" 409
 call staff "GET" (clientPath own) A.Null >>=expect "Own record remains visible" 200
 call staff "GET" (clientPath other) A.Null >>=expect "Other record hidden immediately" 404
 -- Record task queries and the next-step card must retain assignment checks
 -- even though their SQL now starts with one client rather than global lists.
 forM_ [(clientId own,uid,"Visible assigned follow-up","2020-01-02"),(clientId own,aid,"Hidden colleague follow-up","2020-01-01"),(clientId other,uid,"Hidden other client follow-up","2020-01-01")] $ \(cid,assignee,title,due) -> do
  _<-execute conn "INSERT INTO tasks(client_id,assigned_to_id,title,due_date) VALUES (?,?,?,?)" (cid,assignee,title::T.Text,due::T.Text)
  pure ()
 forM_ [clientPath own<>"/profile","/api/workspace/record/client/"<>B.pack(show(clientId own))<>"/tasks",clientPath own] $ \path -> do
  response<-call staff "GET" path A.Null
  expect "Scoped client work loads" 200 response
  let body=BL.toStrict(WT.simpleBody response)
  unless (B.isInfixOf "Visible assigned follow-up" body && not(B.isInfixOf "Hidden colleague follow-up" body) && not(B.isInfixOf "Hidden other client follow-up" body)) $ fail "Client work must retain task and owner visibility"
 call staff "GET" (clientPath other<>"/profile") A.Null >>=expect "Other client profile stays hidden" 404
 forM_ ["/api/tasks","/api/reminders","/api/stats"] $ \path -> do
  response<-call staff "GET" path A.Null
  expect "General task summaries load" 200 response
  let body=BL.toStrict(WT.simpleBody response)
  unless (not(B.isInfixOf "Hidden other client follow-up" body) && not(B.isInfixOf "Hidden colleague follow-up" body)) $ fail "Lists, reminders and dashboard must not leak hidden tasks"
 [Only colleagueTask]<-query_ conn "SELECT id FROM tasks WHERE title='Hidden colleague follow-up'" :: IO [Only Int]
 call staff "PATCH" ("/api/tasks/"<>B.pack(show colleagueTask)) (A.object["status".=("Done"::T.Text),"expectedRevision".=(1::Int)]) >>=expect "Direct task updates obey assignment scope" 404


 forM_ [("GET",download),("GET","/api/export/clients.csv"),("GET","/api/workspace/calendar.ics"),("POST","/api/clients"),("DELETE",clientPath own),("POST","/api/bulk/leads"),("POST","/api/workspace/communication/send"),("POST","/api/workspace/portal/create")] $ \(method,path) -> call staff method path (A.object[]) >>=expect ("Privilege denied: "++B.unpack path) 403
 forM_ ["/api/contacts/check","/api/workspace/milestones/save","/api/workspace/contact-log/add"] $ \path -> do
  call viewer "POST" path (A.object[]) >>=expect "Viewer cannot modify student workflows" 403
  call staff "POST" path (A.object[]) >>=expect "Denied edit includes student workflows" 403
 call staff "GET" "/api/auth/me" A.Null >>=expect "Account access retained" 200
 call staff "GET" "/api/workspace/security" A.Null >>=expect "Security access retained" 200
 [Only count]<-query conn "SELECT count(*) FROM clients WHERE id=? AND deleted_at IS NULL" (Only(clientId own)) :: IO [Only Int]
 unless(count==1) $ fail "Denied delete must not alter persistence"
 save admin (config uid (1::Int) ("assigned"::T.Text) (["edit"]::[T.Text])) >>=expect "Grant edit independently" 200
 forM_ [("DELETE",clientPath own),("POST","/api/workspace/communication/send"),("POST","/api/workspace/portal/create"),("GET",download),("GET","/api/export/clients.csv")] $ \(method,path) -> call staff method path (A.object[]) >>=expect ("Edit does not grant other privileges: "++B.unpack path) 403
 call staff "POST" "/api/clients" (A.object["ncFullName".=("Created with edit privilege"::T.Text),"ncEmail".=A.Null,"ncPhone".=A.Null,"ncCaseOfficer".=uid]) >>=expect "Edit privilege permits record creation" 200
 _<-execute conn "UPDATE clients SET email='hidden-contact@example.test' WHERE id=?" (Only(clientId other))
 hiddenMatch<-call staff "POST" "/api/contacts/check" (A.object["kind".=("clients"::T.Text),"email".=("hidden-contact@example.test"::T.Text),"phone".=(""::T.Text)])
 expect "Scoped duplicate check succeeds" 200 hiddenMatch
 unless (not(B.isInfixOf "Other client" (BL.toStrict(WT.simpleBody hiddenMatch)))) $ fail "Duplicate checks must not reveal hidden records"
 save admin (config uid (2::Int) ("all"::T.Text) (["download","export"]::[T.Text])) >>=expect "Restore selected privileges" 200
 call staff "GET" download A.Null >>=expect "Download restored for active session" 200
 call staff "GET" "/api/export/clients.csv" A.Null >>=expect "Export restored" 200
 call staff "GET" (clientPath other) A.Null >>=expect "All record access restored" 200
 [Only audits]<-query_ conn "SELECT count(*) FROM audit_log WHERE entity_name='Account access'" :: IO [Only Int]
 unless(audits==3) $ fail "Successful access updates must be audited"
 scopedApp<-S.scottyApp(Routes.app env{DB.envAssignedOnly=True})
 let scoped=transactionalApplication conn scopedApp
 response<-WT.runSession (WT.request ((WT.setPath W.defaultRequest (clientPath other)){W.requestHeaders=[("Authorization","Bearer "<>staff)]})) scoped
 expect "Global assignment restriction cannot be overridden" 404 response
 putStrLn "Access levels and privilege regression checks passed"
