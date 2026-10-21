{-# LANGUAGE OverloadedStrings #-}
module ECC.Applications (routes, applicationRows, applicationForm, templateForm) where

import Control.Monad (forM, forM_, void, when)
import Control.Monad.IO.Class (liftIO)
import qualified Data.Aeson as A
import qualified Data.Aeson.KeyMap as KM
import qualified Data.Aeson.Key as K
import Data.Aeson ((.=))
import Data.List (nub)
import qualified Data.ByteString.Lazy as BL
import qualified Data.Text.Encoding as TE
import Database.SQLite.Simple.ToField (toField)
import Database.SQLite3 (SQLData)
import qualified Data.Text as T
import Data.Time (Day, defaultTimeLocale, parseTimeM)
import Network.HTTP.Types hiding (Query)
import qualified Web.Scotty as S
import ECC.DB (Env(..))
import ECC.Models
import ECC.Security (reject)
import ECC.Store
import ECC.WorkflowSupport

type Guard = (User -> S.ActionM ()) -> S.ActionM ()
type Filters = (Maybe Int,Maybe Int,T.Text,T.Text,T.Text)
type FilterParams = [SQLData]

filterSql :: Query
filterSql = " FROM cases a JOIN clients c ON c.id=a.client_id JOIN record_versions v ON v.kind='cases' AND v.record_id=a.id WHERE c.id IN ("<>visibleClients<>") AND (? IS NULL OR a.client_id=?) AND (? IS NULL OR c.case_officer_id=?) AND (?='' OR a.destination=?) AND (?='' OR a.stage=?) AND (?='' OR substr(a.intake_date,1,7)=?) AND (c.full_name LIKE ? OR c.client_number LIKE ? OR a.service_category LIKE ? OR a.destination LIKE ? OR a.stage LIKE ? OR a.institution LIKE ? OR a.program LIKE ?)"

filterParams :: Filters -> T.Text -> FilterParams
filterParams (cid,officer,destination,stage,intake) q = [toField cid,toField cid,toField officer,toField officer,toField destination,toField destination,toField stage,toField stage,toField intake,toField intake,toField term,toField term,toField term,toField term,toField term,toField term,toField term]
 where term="%"<>q<>"%"

rowSql :: Query
rowSql = "SELECT json_object('id',a.id,'title',c.full_name||' · '||coalesce(a.service_category,'Application'),'owner','client:'||a.client_id,'clientName',c.full_name,'category',coalesce(a.service_category,''),'destination',coalesce(a.destination,''),'stage',a.stage,'deadline',coalesce(a.next_deadline,''),'intakeDate',coalesce(a.intake_date,''),'institution',a.institution,'program',a.program,'offerStatus',a.offer_status,'enrollmentStatus',a.enrollment_status,'officer',coalesce(u.name,'Unassigned'),'revision',v.revision,'path','/clients/'||c.id)"

-- Include the staff name without broadening record visibility.
withOfficer :: Query -> Query
withOfficer (Query sql) = Query (T.replace " JOIN record_versions" " LEFT JOIN users u ON u.id=c.case_officer_id JOIN record_versions" sql)

applicationRows :: Env -> Maybe Int -> T.Text -> Int -> IO [A.Value]
applicationRows env cid = filteredRows env (cid,Nothing,"","","")

filteredRows :: Env -> Filters -> T.Text -> Int -> IO [A.Value]
filteredRows env filters q offset = jsonRows env (rowSql<>withOfficer filterSql<>" ORDER BY a.next_deadline NULLS LAST,a.id DESC LIMIT 50 OFFSET ?") (filterParams filters q ++ [toField(max 0 offset)])

applicationForm :: Env -> User -> Int -> IO [A.Value]
applicationForm env _ rid = jsonRows env (rowSql<>withOfficer filterSql<>" AND a.id=?") (filterParams (Nothing,Nothing,"","","") "" ++ [toField rid])

routes :: Env -> Guard -> Guard -> Guard -> S.ScottyM ()
routes env reader writer admin = do
 S.get "/api/workspace/applications" $ reader $ \_ -> do
  q<-maybe "" id <$> (S.queryParamMaybe "q" :: S.ActionM (Maybe T.Text))
  offset<-maybe 0 id <$> (S.queryParamMaybe "offset" :: S.ActionM (Maybe Int))
  cid<-S.queryParamMaybe "client"
  officer<-S.queryParamMaybe "officer"
  destination<-maybe "" id <$> S.queryParamMaybe "destination"
  stage<-maybe "" id <$> S.queryParamMaybe "stage"
  intake<-maybe "" id <$> S.queryParamMaybe "intake"
  when (not(T.null intake) && (parseTimeM True defaultTimeLocale "%F" (T.unpack(intake<>"-01")) :: Maybe Day)==Nothing) $ reject status400 "Choose a valid intake month"
  let filters=(cid,officer,destination,stage,intake); params=filterParams filters q
  rows<-liftIO $ filteredRows env filters q offset
  summary<-liftIO $ jsonRows env ("SELECT json_object('total',count(*),'overdue',coalesce(sum(a.stage NOT IN ('Approved','Rejected','Completed') AND a.next_deadline<date('now',business_offset())),0),'upcoming',coalesce(sum(a.stage NOT IN ('Approved','Rejected','Completed') AND a.next_deadline BETWEEN date('now',business_offset()) AND date('now',business_offset(),'+7 days')),0))"<>filterSql) params
  stages<-liftIO $ jsonRows env ("SELECT json_object('stage',a.stage,'count',count(*))"<>filterSql<>" GROUP BY a.stage ORDER BY a.stage") params
  upcoming<-liftIO $ jsonRows env (rowSql<>withOfficer filterSql<>" AND a.stage NOT IN ('Approved','Rejected','Completed') AND a.next_deadline BETWEEN date('now',business_offset()) AND date('now',business_offset(),'+7 days') ORDER BY a.next_deadline,a.id LIMIT 5") params
  overdue<-liftIO $ jsonRows env (rowSql<>withOfficer filterSql<>" AND a.stage NOT IN ('Approved','Rejected','Completed') AND a.next_deadline<date('now',business_offset()) ORDER BY a.next_deadline,a.id LIMIT 5") params
  options<-liftIO $ clientOptions env q
  staffOptions<-liftIO $ jsonRows env "SELECT json_object('value','staff:'||id,'label',name) FROM users WHERE role<>'viewer' ORDER BY name" ()
  templates<-liftIO $ jsonRows env "SELECT json_object('value','template:'||id,'label',name||' · '||category||CASE WHEN destination='' THEN '' ELSE ' · '||destination END) FROM checklist_templates ORDER BY name" ()
  respondJson env (A.object["rows".=rows,"options".=(options++staffOptions++templates),"summary".=summary,"stages".=stages,"upcoming".=upcoming,"overdue".=overdue])
 S.post "/api/workspace/applications/save" $ writer $ \u -> do
  input<-bodyObject
  (_,mc,_)<-owner env u input
  cid<-maybe (reject status400 "Choose a client") pure mc
  category<-bounded "category" 100 input
  destination<-bounded "destination" 100 input
  stage<-choice "stage" ["Documents Under Review","Submitted","Decision Pending","Approved","Rejected"] input
  deadline<-dateField "deadline" False input
  intake<-dateField "intakeDate" False input
  let rid=number "id" input
  case rid of
   Just ident -> do
    old<-liftIO $ query (envConn env) "SELECT client_id FROM cases WHERE id=?" (Only ident) :: S.ActionM [Only Int]
    when (old/=[Only cid]) $ reject status404 "Application not found for this client"
    checkRevision env "cases" ident input
    previous<-liftIO $ query (envConn env) "SELECT institution,program,offer_status,enrollment_status FROM cases WHERE id=?" (Only ident) :: S.ActionM [(T.Text,T.Text,T.Text,T.Text)]
    extras<-applicationExtras input (case previous of row:_->row; _->("","","Not requested","Not enrolled"))
    let (institution,program,offerStatus,enrollmentStatus)=extras
    liftIO $ void $ execute (envConn env) "UPDATE cases SET service_category=?,destination=?,stage=?,next_deadline=?,intake_date=?,institution=?,program=?,offer_status=?,enrollment_status=? WHERE id=? AND client_id=?" (category,destination,stage,deadline,intake,institution,program,offerStatus,enrollmentStatus,ident,cid)
   Nothing -> do
    (institution,program,offerStatus,enrollmentStatus)<-applicationExtras input ("","","Not requested","Not enrolled")
    liftIO $ void $ execute (envConn env) "INSERT INTO cases(client_id,service_category,destination,stage,next_deadline,intake_date,institution,program,offer_status,enrollment_status) VALUES (?,?,?,?,?,?,?,?,?,?)" (cid,category,destination,stage,deadline,intake,institution,program,offerStatus,enrollmentStatus)
  respondJson env (A.object["message".=("Application saved"::T.Text)])
 S.post "/api/workspace/applications/checklist" $ writer $ \u -> do
  input<-bodyObject
  ident<-intField "id" input
  template<-intField "template" input
  old<-liftIO $ query (envConn env) "SELECT client_id,service_category,destination FROM cases WHERE id=?" (Only ident) :: S.ActionM [(Int,Maybe T.Text,Maybe T.Text)]
  (cid,category,destination)<-case old of [row]->pure row; _->reject status404 "Application not found"
  checkOwner env u Nothing (Just cid)
  checkRevision env "cases" ident input
  matches<-liftIO $ query (envConn env) "SELECT id FROM checklist_templates WHERE id=? AND (category='Any' OR category=?) AND (destination='' OR destination=?)" (template,category,destination) :: S.ActionM [Only Int]
  when(null matches) $ reject status400 "Choose a checklist matching this application type and destination"
  requirements<-liftIO $ query (envConn env) "SELECT title,required FROM checklist_template_items WHERE template_id=? ORDER BY id" (Only template) :: S.ActionM [(T.Text,Bool)]
  created<-liftIO $ forM requirements $ \(title,required) -> do
   seen<-query (envConn env) "SELECT request_id FROM applied_checklist_items WHERE case_id=? AND template_id=? AND title_key=?" (ident,template,T.toCaseFold(T.strip title)) :: IO [Only Int]
   if not(null seen) then pure(0::Int) else do
    existing<-query (envConn env) "SELECT id FROM document_requests WHERE case_id=? AND lower(trim(title))=lower(trim(?)) ORDER BY id LIMIT 1" (ident,title) :: IO [Only Int]
    (requestId,n)<-case existing of
     Only found:_ ->pure(found,0)
     _ ->do
      [Only found]<-query (envConn env) "INSERT INTO document_requests(client_id,case_id,title,required,status) VALUES (?,?,?,?,'Missing') RETURNING id" (cid,ident,title,required) :: IO [Only Int]
      pure(found,1)
    void $ execute (envConn env) "INSERT INTO applied_checklist_items(case_id,template_id,title_key,request_id) VALUES (?,?,?,?)" (ident,template,T.toCaseFold(T.strip title),requestId)
    pure n
  liftIO $ recordHistory env u Nothing (Just cid) (Just ident) "checklist_applied" ("Applied document checklist; added "<>T.pack(show(sum created))<>" requirements")
  respondJson env (A.object["message".=("Checklist applied: "<>T.pack(show(sum created))<>" new requirements. Existing requirements and reviews were preserved.")])
 S.get "/api/workspace/checklist-templates" $ reader $ \_ -> do
  q<-maybe "" id <$> (S.queryParamMaybe "q" :: S.ActionM (Maybe T.Text))
  offset<-maybe 0 id <$> (S.queryParamMaybe "offset" :: S.ActionM (Maybe Int))
  rows<-liftIO $ jsonRows env "SELECT json_object('id',t.id,'title',t.name,'name',t.name,'category',t.category,'destination',t.destination,'revision',t.revision,'requiredDocuments',coalesce((SELECT group_concat(title,char(10)) FROM checklist_template_items WHERE template_id=t.id AND required=1),''),'optionalDocuments',coalesce((SELECT group_concat(title,char(10)) FROM checklist_template_items WHERE template_id=t.id AND required=0),'')) FROM checklist_templates t WHERE name LIKE ? OR category LIKE ? ORDER BY name LIMIT 50 OFFSET ?" ("%"<>q<>"%","%"<>q<>"%",max 0 offset)
  respondJson env (A.object["rows".=rows,"options".= ([]::[A.Value])])
 S.post "/api/workspace/checklist-templates/save" $ admin $ \u -> do
  input<-bodyObject
  name<-bounded "name" 150 input
  category<-choice "category" ["Any","Student Visa","Work Visa","Tourist Visa","Immigration Consultation","School Admission"] input
  let destination=T.strip(field "destination" input)
      linesFor key required=[(T.strip line,required) | line<-T.lines(field key input),not(T.null(T.strip line))]
      requirements=linesFor "requiredDocuments" True++linesFor "optionalDocuments" False
      names=map (T.toCaseFold . fst) requirements
  when(T.length destination>100 || null requirements || length requirements>80 || any ((>255).T.length.fst) requirements || length(nub names)/=length names) $ reject status400 "Use 1–80 unique document names, each up to 255 characters"
  tid<-case number "id" input of
   Just ident ->do
    versions<-liftIO $ query (envConn env) "SELECT revision FROM checklist_templates WHERE id=?" (Only ident) :: S.ActionM [Only Int]
    case versions of [Only rev]->checkOwnRevision rev input; _->reject status404 "Checklist template not found"
    liftIO $ void $ execute (envConn env) "UPDATE checklist_templates SET name=?,category=?,destination=?,revision=revision+1 WHERE id=?" (name,category,destination,ident)
    pure ident
   Nothing ->do
    [Only ident]<-liftIO $ query (envConn env) "INSERT INTO checklist_templates(name,category,destination) VALUES (?,?,?) RETURNING id" (name,category,destination) :: S.ActionM [Only Int]
    pure ident
  liftIO $ do
   void $ execute (envConn env) "DELETE FROM checklist_template_items WHERE template_id=?" (Only tid)
   forM_ requirements $ \(title,required) -> void $ execute (envConn env) "INSERT INTO checklist_template_items(template_id,title,required) VALUES (?,?,?)" (tid,title,required)
   void $ execute (envConn env) "INSERT INTO audit_log(entity_type,entity_id,entity_name,action,changes,actor_id) VALUES ('user',?,'Checklist template updated','updated',?,?)" (userId u,TE.decodeUtf8(BL.toStrict(A.encode(A.object["templateId".=tid,"name".=name]))),userId u)
  respondJson env (A.object["message".=("Checklist template saved. Previously applied requirements remain unchanged."::T.Text)])

templateForm :: Env -> User -> Int -> IO [A.Value]
templateForm env _ ident = jsonRows env "SELECT json_object('id',t.id,'title',t.name,'name',t.name,'category',t.category,'destination',t.destination,'revision',t.revision,'requiredDocuments',coalesce((SELECT group_concat(title,char(10)) FROM checklist_template_items WHERE template_id=t.id AND required=1),''),'optionalDocuments',coalesce((SELECT group_concat(title,char(10)) FROM checklist_template_items WHERE template_id=t.id AND required=0),'')) FROM checklist_templates t WHERE t.id=?" (Only ident)


clientOptions :: Env -> T.Text -> IO [A.Value]
clientOptions env q = jsonRows env ("SELECT json_object('value','client:'||id,'label',full_name||' · '||client_number) FROM clients WHERE id IN ("<>visibleClients<>") AND (full_name LIKE ? OR client_number LIKE ?) ORDER BY full_name LIMIT 200") ("%"<>q<>"%","%"<>q<>"%")


applicationExtras :: A.Value -> (T.Text,T.Text,T.Text,T.Text) -> S.ActionM (T.Text,T.Text,T.Text,T.Text)
applicationExtras input (oldSchool,oldProgram,oldOffer,oldEnrollment) = do
 let get key fallback = case input of
      A.Object fields | KM.member (K.fromText key) fields -> field key input
      _ -> fallback
     school=get "institution" oldSchool
     program=get "program" oldProgram
     offer=get "offerStatus" oldOffer
     enrollment=get "enrollmentStatus" oldEnrollment
 when (T.length school>255 || T.length program>255) $ reject status400 "School and program must each be at most 255 characters"
 when (offer `notElem` ["Not requested","Requested","Conditional offer","Unconditional offer","Declined"]) $ reject status400 "Choose a valid offer status"
 when (enrollment `notElem` ["Not enrolled","Pending","Confirmed","Deferred","Withdrawn"]) $ reject status400 "Choose a valid enrollment status"
 pure(school,program,offer,enrollment)
