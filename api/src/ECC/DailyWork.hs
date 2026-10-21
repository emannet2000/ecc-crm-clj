{-# LANGUAGE OverloadedStrings #-}
module ECC.DailyWork (todaySummary, contactRoutes) where

import Control.Monad (when)
import Control.Monad.IO.Class (liftIO)
import Data.Char (isDigit)
import qualified Data.Aeson as A
import Data.Aeson ((.=))
import qualified Data.Text as T
import qualified Web.Scotty as S
import Network.HTTP.Types (status400)
import ECC.DB (Env(..))
import ECC.Models (User)
import ECC.Clock (businessDay)
import ECC.Store
import ECC.WorkflowSupport
import ECC.Security (reject)

todaySummary :: Env -> IO A.Value
todaySummary env = do
 day<-businessDay
 let tasks=" FROM tasks t WHERE t.status<>'Done' AND t.due_date<date('now',business_offset()) AND "<>taskVisibility
     deadlines=" FROM cases a JOIN clients c ON c.id=a.client_id WHERE c.id IN ("<>visibleClients<>") AND a.stage NOT IN ('Approved','Rejected','Completed') AND a.next_deadline<=date('now',business_offset(),'+7 days')"
     review=" FROM document_requests d WHERE d.status='Received' AND (d.client_id IN ("<>visibleClients<>") OR d.lead_id IN ("<>visibleLeads<>"))"
     milestones=" FROM application_milestones m JOIN cases a ON a.id=m.case_id JOIN clients c ON c.id=a.client_id WHERE c.id IN ("<>visibleClients<>") AND m.status NOT IN ('Completed','Cancelled') AND m.planned_on<=date('now',business_offset(),'+7 days')"
     count sql=do
      [Only n]<-query_ (envConn env) ("SELECT count(*)"<>sql) :: IO [Only Int]
      pure n
 overdueCount<-count tasks
 deadlineCount<-count deadlines
 reviewCount<-count review
 milestoneCount<-count milestones
 milestoneRows<-jsonRows env ("SELECT json_object('id',m.id,'title',c.full_name||' · '||m.title,'detail',m.kind||' · '||m.planned_on,'path','/work/milestones')"<>milestones<>" ORDER BY m.planned_on,m.id LIMIT 5") ()
 overdueRows<-jsonRows env ("SELECT json_object('id',t.id,'title',t.title,'detail',t.due_date,'path',CASE WHEN t.client_id IS NOT NULL THEN '/clients/'||t.client_id ELSE '/leads/'||t.lead_id END)"<>tasks<>" ORDER BY t.due_date,t.id LIMIT 5") ()
 deadlineRows<-jsonRows env ("SELECT json_object('id',a.id,'title',c.full_name,'detail',coalesce(a.service_category,'Application')||' · '||a.next_deadline,'path','/clients/'||c.id,'overdue',a.next_deadline<date('now',business_offset()))"<>deadlines<>" ORDER BY a.next_deadline,a.id LIMIT 5") ()
 reviewRows<-jsonRows env ("SELECT json_object('id',d.id,'title',d.title,'detail',coalesce((SELECT full_name FROM clients WHERE id=d.client_id),(SELECT full_name FROM leads WHERE id=d.lead_id)),'path',CASE WHEN d.client_id IS NOT NULL THEN '/clients/'||d.client_id ELSE '/leads/'||d.lead_id END)"<>review<>" ORDER BY d.created_at,d.id LIMIT 5") ()
 pure(A.object["milestoneCount".=milestoneCount,"milestones".=milestoneRows,"date".=show day,"overdueCount".=overdueCount,"deadlineCount".=deadlineCount,"reviewCount".=reviewCount,"overdueTasks".=overdueRows,"deadlines".=deadlineRows,"reviewDocuments".=reviewRows])

contactRoutes :: Env -> ((User -> S.ActionM ()) -> S.ActionM ()) -> S.ScottyM ()
contactRoutes env writer = S.post "/api/contacts/check" $ writer $ \_ -> do
 input<-bodyObject
 kind<-choice "kind" ["leads","clients"] input
 let email=T.toLower(field "email" input)
     rawPhone=field "phone" input
     phone=T.filter isDigit rawPhone
     excluded=maybe 0 id(number "exclude" input)
 when (T.length email>255 || T.length rawPhone>50) $ reject status400 "Email or phone is too long"
 let normalizedPhone="replace(replace(replace(replace(replace(replace(phone,' ',''),'+',''),'-',''),'(',''),')',''),'.','')"
     matches table visibility recordKind name numberColumn =
      "SELECT json_object('id',id,'kind','"<>recordKind<>"','name',"<>name<>",'number',"<>numberColumn<>",'path','/"<>table<>"/'||id,'field',CASE WHEN ?<>'' AND lower(trim(email))=? THEN 'Email' ELSE 'Phone' END) FROM "<>table<>" WHERE id IN ("<>visibility<>") AND NOT (?='"<>table<>"' AND id=?) AND ((?<>'' AND lower(trim(email))=?) OR (?<>'' AND "<>normalizedPhone<>"=?))"
     parameters=(email,email,kind,excluded,email,email,phone,phone)
 leads<-liftIO $ jsonRows env (matches "leads" visibleLeads "lead" "full_name" "lead_number"<>" ORDER BY id LIMIT 5") parameters
 students<-liftIO $ jsonRows env (matches "clients" visibleClients "student" "full_name" "client_number"<>" ORDER BY id LIMIT 5") parameters
 respondJson env (A.object["matches".=(leads++students),"advisory".=True])
