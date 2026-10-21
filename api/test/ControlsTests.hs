{-# LANGUAGE OverloadedStrings #-}
module ControlsTests (run) where
import Control.Exception (bracket)
import Control.Monad (forM_, unless, void)
import qualified Data.Aeson as A
import Data.Aeson ((.=), (.:))
import Data.Aeson.Types (parseMaybe)
import qualified Data.ByteString.Char8 as B
import qualified Data.ByteString.Lazy.Char8 as BL
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import qualified Network.Wai as W
import qualified Network.Wai.Test as WT
import Network.HTTP.Types (statusCode)
import qualified Web.Scotty as S
import ECC.Store
import ECC.Migrations
import ECC.Server (transactionalApplication)
import qualified ECC.DB as DB
import ECC.Models
import qualified ECC.Routes as Routes

run :: IO ()
run=bracket(openDatabase ":memory:") close $ \conn -> do
 let assert label good=unless good(fail label)
 runMigrations conn "migrations"
 forM_ [("admin","admin"),("staff","consultant"),("viewer","viewer")] $ \(name,role)->DB.addUser conn (name<>"@controls.test") name role "controls-password-123"
 app<-S.scottyApp(Routes.app(DB.Env conn "controls-secret-32-bytes-long-12345" False "http://localhost:4000" False))
 let api=transactionalApplication conn app
     call token method path body=WT.runSession(WT.srequest(WT.SRequest ((WT.setPath W.defaultRequest path){W.requestMethod=method,W.requestHeaders=[("Content-Type","application/json"),("Authorization","Bearer "<>token)]}) (A.encode body))) api
     expect label code response=assert(label++": "++show(WT.simpleStatus response)++" "++show(WT.simpleBody response))(statusCode(WT.simpleStatus response)==code)
     field key response=do
      value<-either fail pure(A.eitherDecode(WT.simpleBody response))
      maybe(fail "Missing JSON field") pure(parseMaybe(A.withObject "response" (.: key)) value)
     login name=do
      response<-call "" "POST" "/api/auth/login" (A.object["lrEmail".=(name<>"@controls.test"::T.Text),"lrPassword".=("controls-password-123"::T.Text)])
      expect "Login" 200 response
      TE.encodeUtf8 <$> (field "token" response :: IO T.Text)
     post tok path fields=call tok "POST" ("/api/workspace/"<>path) (A.object fields)
     get tok path=call tok "GET" path A.Null
 admin<-login "admin";staff<-login "staff";viewer<-login "viewer"
 _<-execute_ conn "INSERT INTO user_access(user_id,access_level,privileges) VALUES (2,'assigned','[\"finance_view\",\"payments_record\",\"finance_reconcile\",\"finance_periods\",\"export\",\"download\"]'),(3,'all','[\"finance_view\",\"export\",\"finance_periods\",\"finance_reconcile\"]')"
 client<-DB.insertClient conn(NewClient "<script>unsafe client</script>" Nothing Nothing(Just 2))
 [Only iid]<-query conn "INSERT INTO invoices(client_id,description,currency,amount_minor,due_date) VALUES (?,'Service','PHP',100000,'2020-01-01') RETURNING id" (Only(clientId client)) :: IO [Only Int]
 _<-execute conn "UPDATE invoices SET status='Issued' WHERE id=?" (Only iid)
 forM_ [1..521::Int] $ \n ->void $ execute conn "INSERT INTO invoice_payments(invoice_id,amount_minor,paid_on,method,reference,actor_id,actor_name) VALUES (?,1,'2020-01-15','Bank transfer',?,1,'admin')" (iid,if n==2 then "BANK-OLD"::T.Text else if n<5 then "DUPLICATE" else "")
 history<-get staff "/api/workspace/payment-history?offset=500";expect "Old receipts remain paginated" 200 history
 entries<-field "rows" history :: IO [A.Value]
 assert "History includes entries beyond the former 500 receipt limit" (length entries==21)
 duplicates<-get staff "/api/workspace/payment-history?q=DUPLICATE"
 assert "Repeated references are flagged" ("\"duplicateReference\":1" `contains` WT.simpleBody duplicates)
 [Only rev]<-query conn "SELECT revision FROM invoices WHERE id=?" (Only iid) :: IO [Only Int]
 post staff "payments/reverse" ["id".=iid,"payment".=(1::Int),"expectedRevision".=rev,"paidOn".=("2020-01-16"::T.Text),"reason".=("Correct oldest receipt"::T.Text)] >>=expect "Old receipt can be reversed" 200
 printInvoice<-get admin ("/api/finance/print/invoices/"<>B.pack(show iid));expect "Printable invoice" 200 printInvoice
 assert "Print document escapes client HTML" ("&lt;script&gt;" `contains` WT.simpleBody printInvoice && not("<script>unsafe client" `contains` WT.simpleBody printInvoice))
 get staff "/api/finance/print/payments/2" >>=expect "Printable payment acknowledgement" 200
 get staff "/api/workspace/periods" >>=expect "Assigned-only user cannot close company books" 403
 get viewer "/api/workspace/periods" >>=expect "Viewer cannot acquire closing permission" 403
 let period action revision reason=post admin ("periods/"<>action) ["month".=("2020-01"::T.Text),"expectedRevision".=revision,"reason".=(reason::T.Text)]
 period "close" (0::Int) "January verified" >>=expect "Close a completed month" 200
 [Only lockedRev]<-query conn "SELECT revision FROM invoices WHERE id=?" (Only iid) :: IO [Only Int]
 let receipt date=post admin "payments/record" ["id".=iid,"expectedRevision".=lockedRev,"amount".=("0.01"::T.Text),"paidOn".=(date::T.Text),"method".=("Cash"::T.Text)]
 receipt "2020-01-20" >>=expect "Closed month blocks backdated receipt" 409
 period "reopen" (1::Int) "" >>=expect "Reopening needs an audit reason" 400
 period "reopen" (1::Int) "Correct missing evidence" >>=expect "Authorized reopening" 200
 receipt "2020-01-20" >>=expect "Reopened month accepts corrections" 200
 period "close" (2::Int) "January corrected and verified" >>=expect "Close corrected month" 200
 let csv="transactionId,date,amount,reference,description\nBANK-TXN-1,2020-02-01,0.01,BANK-OLD,Client transfer\n"::T.Text
     statement text=post admin "reconciliation/import" ["account".=("Operating account"::T.Text),"currency".=("PHP"::T.Text),"csv".=text]
 statement csv >>=expect "Import bank statement" 200
 statement csv >>=expect "Duplicate statement is idempotent" 200
 statement(T.replace "0.01" "0.02" csv) >>=expect "Changed bank transaction ID rejected" 409
 [Only bankCount]<-query_ conn "SELECT count(*) FROM bank_lines" :: IO [Only Int]
 assert "Duplicate import creates no extra rows" (bankCount==1)
 candidates<-get admin "/api/workspace/reconciliation/candidates/1?q=BANK-OLD"
 expect "Bank match candidates" 200 candidates
 assert "Candidates include exact amount and currency" ("payment:2" `contains` WT.simpleBody candidates)
 let match revision=post admin "reconciliation/match" ["id".=(1::Int),"expectedRevision".=revision,"match".=("payment:2"::T.Text),"reason".=("Verified against bank statement"::T.Text)]
 match (1::Int) >>=expect "Reconcile a bank transaction" 200
 match (1::Int) >>=expect "Repeated match is rejected" 409
 [Only matchedRev]<-query conn "SELECT revision FROM invoices WHERE id=?" (Only iid) :: IO [Only Int]
 post admin "payments/reverse" ["id".=iid,"expectedRevision".=matchedRev,"payment".=(2::Int),"paidOn".=("2020-02-02"::T.Text),"reason".=("Must unmatch first"::T.Text)] >>=expect "Matched receipts cannot be reversed silently" 409
 post admin "periods/close" ["month".=("2020-02"::T.Text),"expectedRevision".=(0::Int),"reason".=("Bank month reconciled"::T.Text)] >>=expect "Reconciled month closes" 200
 post admin "reconciliation/unmatch" ["id".=(1::Int),"expectedRevision".=(2::Int),"reason".=("Closed month correction"::T.Text)] >>=expect "Closed-month bank match is locked" 409
 -- Supporting documents are quarantined and carry independent access checks.
 post admin "expenses/submit" ["supplier".=("Supplier"::T.Text),"description".=("Receipt evidence"::T.Text),"category".=("Office"::T.Text),"currency".=("PHP"::T.Text),"amount".=("1.00"::T.Text),"expenseOn".=("2020-03-01"::T.Text),"submissionKey".=("evidence-1"::T.Text)] >>=expect "Create expense for evidence" 200
 let upload=WT.runSession(WT.srequest(WT.SRequest ((WT.setPath W.defaultRequest "/api/finance/expenses/1/attachments"){W.requestMethod="POST",W.requestHeaders=[("Authorization","Bearer "<>admin),("Content-Type","multipart/form-data; boundary=ecc-evidence")]}) "--ecc-evidence\r\nContent-Disposition: form-data; name=\"expectedRevision\"\r\n\r\n1\r\n--ecc-evidence\r\nContent-Disposition: form-data; name=\"file\"; filename=\"receipt.pdf\"\r\nContent-Type: application/pdf\r\n\r\n%PDF-1.4 supporting evidence\r\n--ecc-evidence--\r\n")) api
 upload >>=expect "Upload supporting evidence" 200
 upload >>=expect "Supporting upload respects expense revision" 409
 get admin "/api/finance/attachments/1" >>=expect "Pending evidence cannot be downloaded" 423
 get staff "/api/finance/attachments/1" >>=expect "Evidence respects expense ownership" 404
 _<-execute_ conn "UPDATE financial_files SET scan_status='Clean' WHERE id=1"
 clean<-get admin "/api/finance/attachments/1";expect "Scanned supporting evidence can be downloaded" 200 clean
 assert "Downloaded evidence preserves bytes" ("%PDF-1.4 supporting evidence" `contains` WT.simpleBody clean)
 audit<-get admin "/api/workspace/finance-audit";expect "Control audit is visible" 200 audit
 assert "Closing and bank operations are audited" ("\"kind\":\"bank\"" `contains` WT.simpleBody audit && "\"kind\":\"period\"" `contains` WT.simpleBody audit)
 putStrLn "Period closing, bank reconciliation, old payment history, print and supporting evidence checks passed"

contains :: BL.ByteString -> BL.ByteString -> Bool
contains needle haystack = BL.toStrict needle `B.isInfixOf` BL.toStrict haystack
