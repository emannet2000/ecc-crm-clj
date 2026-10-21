{-# LANGUAGE OverloadedStrings #-}
module FinanceTests (run) where

import Control.Exception (bracket, try)
import Control.Monad (forM_, unless, void)
import qualified Data.Aeson as A
import Data.Aeson ((.=), (.:))
import Data.Aeson.Types (parseMaybe)
import qualified Data.ByteString.Char8 as B
import qualified Data.ByteString.Lazy as BL
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import Data.List (sort, isSuffixOf)
import System.Directory (listDirectory)
import Network.HTTP.Types (statusCode)
import qualified Network.Wai as W
import qualified Network.Wai.Test as WT
import qualified Web.Scotty as S
import Data.Int (Int64)
import ECC.Store
import ECC.Migrations (runMigrations)
import ECC.Server (transactionalApplication)
import qualified ECC.DB as DB
import qualified ECC.Routes as Routes
import ECC.Models

assert :: String -> Bool -> IO ()
assert label ok=unless ok(fail label)

run :: IO ()
run = do
 legacyMigration
 bracket (openDatabase ":memory:") close $ \conn -> do
  runMigrations conn "migrations"
  forM_ [("admin","admin"),("staff","consultant"),("approver","consultant"),("viewer","viewer")] $ \(name,role) -> DB.addUser conn (name<>"@finance.test") name role "finance-password-123"
  let env=DB.Env conn "financial-regression-secret-32-bytes" False "http://localhost:4000" False
  app<-S.scottyApp(Routes.app env)
  let api=transactionalApplication conn app
      call token method path body=WT.runSession(WT.srequest(WT.SRequest ((WT.setPath W.defaultRequest path){W.requestMethod=method,W.requestHeaders=[("Content-Type","application/json")]++[("Authorization","Bearer "<>token)|not(B.null token)]}) (A.encode body))) api
      expect label code response=assert(label++": "++show(WT.simpleStatus response)++" "++show(WT.simpleBody response))(statusCode(WT.simpleStatus response)==code)
      login name=do
       response<-call "" "POST" "/api/auth/login" (A.object["lrEmail".=(name<>"@finance.test"::T.Text),"lrPassword".=("finance-password-123"::T.Text)])
       expect "Login" 200 response
       value<-either fail pure(A.eitherDecode(WT.simpleBody response))
       maybe(fail "Missing token")(pure . TE.encodeUtf8)(parseMaybe(A.withObject "login"(.: "token")) value)
      get tok path=call tok "GET" path A.Null
      post tok path fields=call tok "POST" ("/api/workspace/"<>path) (A.object fields)
  admin<-login "admin"; staff<-login "staff"; approver<-login "approver"; viewer<-login "viewer"
  [Only aid]<-query_ conn "SELECT id FROM users WHERE role='admin'" :: IO [Only Int]
  [Only uid]<-query_ conn "SELECT id FROM users WHERE name='staff'" :: IO [Only Int]
  [Only approverId]<-query_ conn "SELECT id FROM users WHERE name='approver'" :: IO [Only Int]
  [Only vid]<-query_ conn "SELECT id FROM users WHERE name='viewer'" :: IO [Only Int]
  own<-DB.insertClient conn(NewClient "Finance client" Nothing Nothing(Just uid))
  other<-DB.insertClient conn(NewClient "Private other client" Nothing Nothing(Just aid))
  let invoice client currency amount status=["owner".=("client:"<>T.pack(show(clientId client))),"description".=("Service"::T.Text),"currency".=(currency::T.Text),"amount".=(amount::T.Text),"dueDate".=("2020-01-01"::T.Text),"status".=(status::T.Text)]
      createInvoice client currency amount=do
       post admin "invoices/save" (invoice client currency amount "Draft") >>=expect "Create invoice" 200
       [Only iid]<-query_ conn "SELECT max(id) FROM invoices" :: IO [Only Int]
       post admin "invoices/save" (invoice client currency amount "Issued"++["id".=iid,"expectedRevision".=(1::Int)]) >>=expect "Issue invoice" 200
       pure iid
      grant user privileges scope=void $ execute conn "INSERT INTO user_access(user_id,access_level,privileges) VALUES (?,?,?) ON CONFLICT(user_id) DO UPDATE SET access_level=excluded.access_level,privileges=excluded.privileges" (user,scope::T.Text,TE.decodeUtf8(BL.toStrict(A.encode(privileges::[T.Text]))))
  iid<-createInvoice own "PHP" "100.00"
  _<-createInvoice own "USD" "200.00"
  hidden<-createInvoice other "PHP" "900.00"
  post admin "invoices/save" (invoice own "PHP" "100.00" "Paid"++["id".=iid,"expectedRevision".=(2::Int)]) >>=expect "Paid cannot be manually selected" 400
  forM_ ["sales","payments","balances","expenses","cashflow","finance-audit"] $ \section -> do
   get admin ("/api/workspace/"<>section) >>=expect "Admin financial read" 200
   get staff ("/api/workspace/"<>section) >>=expect "Financial access denied by default" 403
  firstLead<-DB.insertLead conn (NewLead "Converted website lead" Nothing Nothing (Just "Website") Nothing Nothing Nothing Nothing Nothing Nothing (Just uid)) uid
  _<-DB.insertLead conn (NewLead "Open website lead" Nothing Nothing (Just "Website") Nothing Nothing Nothing Nothing Nothing Nothing (Just uid)) uid
  _<-DB.insertLead conn (NewLead "Hidden source lead" Nothing Nothing (Just "Secret source") Nothing Nothing Nothing Nothing Nothing Nothing (Just aid)) aid
  _<-execute conn "UPDATE leads SET converted_client_id=? WHERE id=?" (clientId own,leadId firstLead)
  grant uid ["sales_view"] "assigned"
  sales<-get staff "/api/workspace/sales";expect "Sales privilege works independently" 200 sales
  assert "Sales groups cohorts and computes conversion without exposing another consultant" (all (`B.isInfixOf` BL.toStrict(WT.simpleBody sales)) ["Website","50.00","Converted"] && not("Secret source" `B.isInfixOf` BL.toStrict(WT.simpleBody sales)))
  get staff "/api/workspace/balances" >>=expect "Sales does not grant financial details" 403
  grant uid ["finance_view","sales_view","payments_record","expenses_record"] "assigned"
  grant approverId ["finance_view","expenses_approve"] "all"
  grant vid ["finance_view","sales_view","payments_record"] "all"
  get staff "/api/workspace/finance-export/payments" >>=expect "Export needs separate privilege" 403
  balanceRows<-get staff "/api/workspace/balances";expect "Scoped balances" 200 balanceRows
  assert "Other clients are not exposed" (not("Private other client" `B.isInfixOf` BL.toStrict(WT.simpleBody balanceRows)))
  let payment ident rev amount=["id".=ident,"expectedRevision".=rev,"amount".=(amount::T.Text),"paidOn".=("2020-01-10"::T.Text),"method".=("Bank transfer"::T.Text),"reference".=("BANK-001"::T.Text)]
      state expected=do
       actual<-query conn "SELECT paid_minor,balance_minor,status,revision FROM invoice_balances WHERE id=?" (Only iid) :: IO [(Int,Int,T.Text,Int)]
       assert "Ledger-derived invoice state" (actual==[expected])
  post staff "payments/record" (payment hidden (2::Int) "10") >>=expect "Cannot pay inaccessible invoice" 404
  post viewer "payments/record" (payment iid (2::Int) "40") >>=expect "Viewer remains read-only" 403
  post staff "payments/record" (payment iid (2::Int) "40") >>=expect "Partial payment" 200
  state (4000,6000,"Issued",3)
  post staff "payments/record" (payment iid (2::Int) "40") >>=expect "Duplicate/stale payment rejected" 409
  forM_ ["60.01","0","-1","1.001","1000000001"] $ \amount ->post staff "payments/record" (payment iid (3::Int) amount) >>=expect "Invalid or excess amount" 400
  post staff "payments/record" (filter((/="paidOn").fst)(payment iid (3::Int) "1")++["paidOn".=("9999-01-01"::T.Text)]) >>=expect "No future receipts" 400
  state (4000,6000,"Issued",3)
  post staff "payments/record" (payment iid (3::Int) "60") >>=expect "Full settlement" 200
  state (10000,0,"Paid",4)
  [Only receipt]<-query conn "SELECT min(id) FROM invoice_payments WHERE invoice_id=?" (Only iid) :: IO [Only Int]
  let reversal rev=["id".=iid,"expectedRevision".=rev,"payment".=receipt,"paidOn".=("2020-01-11"::T.Text),"reason".=("Duplicate bank advice"::T.Text)]
  post staff "payments/reverse" (reversal (4::Int)) >>=expect "Receipt reversal" 200
  state (6000,4000,"Issued",5)
  post staff "payments/reverse" (reversal (5::Int)) >>=expect "Cannot reverse receipt twice" 409
  post admin "invoices/save" (invoice own "PHP" "100.00" "Void"++["id".=iid,"expectedRevision".=(5::Int)]) >>=expect "Cannot void while payments remain" 409
  get staff "/api/workspace/balances?q=overdue" >>=expect "Overdue filter" 200
  let expense key=["supplier".=("Office supplier"::T.Text),"description".=("Office materials"::T.Text),"category".=("Office"::T.Text),"currency".=("PHP"::T.Text),"amount".=("25.00"::T.Text),"expenseOn".=("2020-01-05"::T.Text),"reference".=("SUP-001"::T.Text),"submissionKey".=(key::T.Text)]
  _<-execute_ conn "CREATE TEMP TRIGGER test_expense_audit_failure BEFORE INSERT ON main.finance_audit WHEN NEW.kind='expense' BEGIN SELECT RAISE(ABORT,'test audit failure'); END"
  post staff "expenses/submit" (expense "rollback-request") >>=expect "Audit failure rolls back the entire submission" 409
  [Only orphanCount]<-query_ conn "SELECT (SELECT count(*) FROM expenses)+(SELECT count(*) FROM expense_submissions)" :: IO [Only Int]
  assert "Failed audit leaves no expense or submission key" (orphanCount==0)
  _<-execute_ conn "DROP TRIGGER test_expense_audit_failure"
  post staff "expenses/submit" (expense "request-1") >>=expect "Submit expense" 200
  post staff "expenses/submit" (expense "request-1") >>=expect "Duplicate expense rejected" 409
  [Only eid]<-query_ conn "SELECT max(id) FROM expenses" :: IO [Only Int]
  let selected rev=["id".=eid,"expectedRevision".=rev]
      expensePay rev=selected rev++["paidOn".=("2020-01-12"::T.Text),"method".=("Cash"::T.Text),"paymentReference".=("CASH-001"::T.Text)]
  post staff "expenses/pay" (expensePay (1::Int)) >>=expect "Approval required before expense payment" 409
  post staff "expenses/approve" (selected (1::Int)) >>=expect "Approval needs separate privilege" 403
  post approver "expenses/approve" (selected (1::Int)) >>=expect "Another approver approves" 200
  post approver "expenses/pay" (expensePay (2::Int)) >>=expect "Approval does not grant payment recording" 403
  post staff "expenses/pay" (expensePay (2::Int)) >>=expect "Pay approved expense" 200
  post staff "expenses/pay" (expensePay (2::Int)) >>=expect "Expense payment retry rejected" 409
  cash<-get admin "/api/workspace/cashflow?q=2020-01-01,2020-01-31"; expect "Cash activity" 200 cash
  assert "Cash separates invoices, receipts and paid expenses" (all (`B.isInfixOf` BL.toStrict(WT.simpleBody cash)) ["\"collected\":\"60.00\"","\"expenses\":\"25.00\"","\"net\":\"35.00\"","\"currency\":\"USD\""])
  post approver "expenses/reverse-expense" (selected (3::Int)++["paidOn".=("2020-01-13"::T.Text),"reason".=("Payment entry corrected"::T.Text)]) >>=expect "Expense reversal" 200
  post approver "expenses/reverse-expense" (selected (4::Int)++["paidOn".=("2020-01-13"::T.Text),"reason".=("Repeat"::T.Text)]) >>=expect "No duplicate expense reversal" 409
  post staff "expenses/submit" (expense "request-2") >>=expect "Another expense" 200
  [Only ownExpense]<-query_ conn "SELECT max(id) FROM expenses" :: IO [Only Int]
  grant uid ["finance_view","payments_record","expenses_record","expenses_approve","sales_view","export"] "assigned"
  post staff "expenses/approve" ["id".=ownExpense,"expectedRevision".=(1::Int)] >>=expect "Staff cannot approve their own expense" 403
  post approver "expenses/reject" ["id".=ownExpense,"expectedRevision".=(1::Int),"reason".=("Please correct the supplier reference"::T.Text)] >>=expect "Reject with explanation" 200
  forM_ ["sales","payments","balances","expenses","cashflow","finance-audit"] $ \section ->get admin ("/api/workspace/finance-export/"<>section) >>=expect "Financial CSV export" 200
  exported<-get staff "/api/workspace/finance-export/payments";expect "Granted scoped export" 200 exported
  assert "Payment CSV contains references and reversals" (all (`B.isInfixOf` BL.toStrict(WT.simpleBody exported)) ["BANK-001","Duplicate bank advice","-40.00"])
  assert "CSV does not expose other clients" (not("Private other client" `B.isInfixOf` BL.toStrict(WT.simpleBody exported)))
  get admin "/api/workspace/sales?q=2020-99-99,2020-01-01" >>=expect "Reject invalid report range" 400
  forM_ ["UPDATE invoice_payments SET amount_minor=1","DELETE FROM invoice_payments","UPDATE expense_entries SET amount_minor=1","DELETE FROM expense_entries","DELETE FROM finance_audit"] $ \sql -> do
   result<-try(execute_ conn sql) :: IO(Either SQLError Int64)
   assert "Posted ledger and audit entries are immutable" (case result of Left _->True;Right _->False)
  _<-execute conn "UPDATE clients SET deleted_at=datetime('now') WHERE id=?" (Only(clientId own))
  archived<-get staff "/api/workspace/balances";expect "Archived client finances remain visible" 200 archived
  assert "Archiving does not hide outstanding balances" (all (`B.isInfixOf` BL.toStrict(WT.simpleBody archived)) ["Archived","40.00"])
  [Only audits]<-query_ conn "SELECT count(*) FROM finance_audit" :: IO [Only Int]
  assert "Financial actions are audited" (audits>=9)
  putStrLn "Financial payments, balances, expenses, reports and authorization checks passed"

legacyMigration :: IO ()
legacyMigration=bracket(openDatabase ":memory:") close $ \conn -> do
 files<-sort . filter (\f->".sql" `isSuffixOf` f && f<"0012_finance.sql") <$> listDirectory "migrations"
 forM_ files $ \file -> readFile ("migrations/"++file) >>=execScript conn . T.pack
 DB.addUser conn "legacy@finance.test" "Legacy" "admin" "legacy-password-123"
 client<-DB.insertClient conn(NewClient "Legacy client" Nothing Nothing(Just 1))
 forM_ [("PHP",Just("2020-01-01"::T.Text)),("USD",Nothing)] $ \(currency,date) ->void $ execute conn "INSERT INTO invoices(client_id,description,currency,amount_minor,due_date,status,paid_at) VALUES (?,'Legacy invoice',?,10000,'2020-01-01','Paid',?)" (clientId client,currency::T.Text,date)
 readFile "migrations/0012_finance.sql" >>=execScript conn . T.pack
 balances<-query_ conn "SELECT paid_minor,balance_minor FROM invoice_balances ORDER BY id" :: IO[(Int,Int)]
 assert "Legacy Paid invoices preserve settled balances" (balances==[(10000,0),(10000,0)])
 [Only undated]<-query_ conn "SELECT count(*) FROM invoice_payments WHERE legacy=1 AND paid_on IS NULL" :: IO[Only Int]
 assert "Unknown legacy payment dates are not invented" (undated==1)
