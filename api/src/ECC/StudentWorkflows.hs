{-# LANGUAGE OverloadedStrings #-}
module ECC.StudentWorkflows (routes, milestoneRows, milestoneForm) where

import Control.Monad (void, when)
import Control.Monad.IO.Class (liftIO)
import qualified Data.Aeson as A
import Data.Aeson ((.=))
import qualified Data.Text as T
import Network.HTTP.Types hiding (Query)
import qualified Web.Scotty as S
import ECC.DB (Env(..))
import ECC.Models (User)
import ECC.Clock (businessDay)
import ECC.Store
import ECC.Security (reject)
import ECC.WorkflowSupport

type Guard = (User -> S.ActionM ()) -> S.ActionM ()

milestoneSelect :: Query
milestoneSelect = "SELECT json_object('id',m.id,'owner','case:'||m.case_id,'title',m.title,'kind',m.kind,'status',m.status,'plannedOn',coalesce(m.planned_on,''),'completedOn',coalesce(m.completed_on,''),'note',m.note,'revision',m.revision,'student',c.full_name,'application',coalesce(a.service_category,'Application'),'path','/clients/'||c.id) FROM application_milestones m JOIN cases a ON a.id=m.case_id JOIN clients c ON c.id=a.client_id WHERE c.id IN ("<>visibleClients<>")"

milestoneRows :: Env -> T.Text -> Int -> IO [A.Value]
milestoneRows env q offset = jsonRows env (milestoneSelect<>" AND (m.title LIKE ? OR c.full_name LIKE ? OR m.kind LIKE ?) ORDER BY CASE WHEN m.status IN ('Completed','Cancelled') THEN 1 ELSE 0 END,m.planned_on NULLS LAST,m.id LIMIT 50 OFFSET ?") (term,term,term,offset)
 where term="%"<>q<>"%"

milestoneForm :: Env -> Int -> IO [A.Value]
milestoneForm env rid=jsonRows env (milestoneSelect<>" AND m.id=?") (Only rid)

routes :: Env -> Guard -> Guard -> S.ScottyM ()
routes env reader writer = do
 S.get "/api/workspace/milestones" $ reader $ \_ -> do
  q<-maybe "" id <$> (S.queryParamMaybe "q" :: S.ActionM (Maybe T.Text))
  offset<-max 0 . maybe 0 id <$> (S.queryParamMaybe "offset" :: S.ActionM (Maybe Int))
  rows<-liftIO $ milestoneRows env q offset
  options<-liftIO $ jsonRows env ("SELECT json_object('value','case:'||a.id,'label',c.full_name||' · '||coalesce(a.service_category,'Application')||' · #'||a.id) FROM cases a JOIN clients c ON c.id=a.client_id WHERE c.id IN ("<>visibleClients<>") AND (c.full_name LIKE ? OR a.service_category LIKE ?) ORDER BY c.full_name,a.id DESC LIMIT 200") ("%"<>q<>"%","%"<>q<>"%")
  respondJson env(A.object["rows".=rows,"options".=options])
 S.post "/api/workspace/milestones/save" $ writer $ \u -> do
  input<-bodyObject
  (_,mc,cs)<-owner env u input
  applicationId<-maybe(reject status400 "Choose an application") pure cs
  kind<-choice "kind" ["Offer","Deposit","Visa submission","Visa decision","Arrival","Other"] input
  title<-bounded "title" 255 input
  status<-choice "status" ["Planned","In progress","Completed","Cancelled"] input
  planned<-dateField "plannedOn" False input
  completed<-dateField "completedOn" (status=="Completed") input
  day<-liftIO businessDay
  when (maybe False (>T.pack(show day)) completed) $ reject status400 "Completion date cannot be in the future"
  when (status/="Completed" && completed/=Nothing) $ reject status400 "Use Completed status when entering a completion date"
  case number "id" input of
   Just rid -> do
    old<-liftIO $ query (envConn env) "SELECT case_id,revision FROM application_milestones WHERE id=?" (Only rid) :: S.ActionM [(Int,Int)]
    case old of
     [(oldCase,rev)] -> do
      when(oldCase/=applicationId) $ reject status400 "A milestone stays with its application"
      checkOwnRevision rev input
      liftIO $ void $ execute (envConn env) "UPDATE application_milestones SET kind=?,title=?,status=?,planned_on=?,completed_on=?,note=?,revision=revision+1 WHERE id=?" (kind,title,status,planned,completed,field "note" input,rid)
     _ -> reject status404 "Milestone not found"
   Nothing -> liftIO $ void $ execute (envConn env) "INSERT INTO application_milestones(case_id,kind,title,status,planned_on,completed_on,note) VALUES(?,?,?,?,?,?,?)" (applicationId,kind,title,status,planned,completed,field "note" input)
  liftIO $ recordHistory env u Nothing mc cs "milestone" (kind<>" · "<>title<>" · "<>status)
  respondJson env(A.object["message".=("Milestone saved. Deposit milestones do not record a financial payment."::T.Text)])
 S.get "/api/workspace/contact-log" $ reader $ \_ -> do
  q<-maybe "" id <$> (S.queryParamMaybe "q" :: S.ActionM (Maybe T.Text))
  offset<-max 0 . maybe 0 id <$> (S.queryParamMaybe "offset" :: S.ActionM (Maybe Int))
  rows<-liftIO $ jsonRows env ("SELECT json_object('id',h.id,'title',coalesce(c.full_name,l.full_name),'kind',h.kind,'note',h.note,'actor',coalesce(u.name,'System'),'date',h.created_at) FROM work_history h LEFT JOIN clients c ON c.id=h.client_id LEFT JOIN leads l ON l.id=h.lead_id LEFT JOIN users u ON u.id=h.actor_id WHERE h.kind LIKE 'communication_%' AND (h.lead_id IN ("<>visibleLeads<>") OR h.client_id IN ("<>visibleClients<>")) AND (h.note LIKE ? OR coalesce(c.full_name,l.full_name) LIKE ?) ORDER BY h.id DESC LIMIT 50 OFFSET ?") ("%"<>q<>"%","%"<>q<>"%",offset)
  options<-liftIO $ jsonRows env ("SELECT json_object('value','client:'||id,'label',full_name||' · '||client_number) FROM clients WHERE id IN ("<>visibleClients<>") UNION ALL SELECT json_object('value','lead:'||id,'label',full_name||' · '||lead_number) FROM leads WHERE id IN ("<>visibleLeads<>") LIMIT 200") ()
  respondJson env(A.object["rows".=rows,"options".=options])
 S.post "/api/workspace/contact-log/add" $ writer $ \u -> do
  input<-bodyObject
  (ml,mc,cs)<-owner env u input
  channel<-choice "channel" ["Call","WhatsApp","SMS","Email","Meeting"] input
  direction<-choice "direction" ["Incoming","Outgoing"] input
  outcome<-choice "outcome" ["Completed","No answer","Follow-up needed"] input
  occurred<-dateField "occurredOn" True input
  day<-liftIO businessDay
  when(maybe False (>T.pack(show day)) occurred) $ reject status400 "Interaction date cannot be in the future"
  note<-bounded "note" 19000 input
  liftIO $ recordHistory env u ml mc cs ("communication_"<>T.toLower channel) (channel<>" · "<>direction<>" · "<>outcome<>" · "<>maybe "" id occurred<>"\n"<>note)
  respondJson env(A.object["message".=("Interaction logged. No message was sent by the CRM."::T.Text)])
