{-# LANGUAGE OverloadedStrings #-}
module ECC.ProfilePhotos (routes, photoMime) where

import Control.Monad (unless, void, when)
import Control.Monad.IO.Class (liftIO)
import qualified Data.Aeson as A
import Data.Aeson ((.=))
import qualified Data.ByteString as B
import qualified Data.ByteString.Lazy as BL
import qualified Data.Text as T
import qualified Data.Text.Lazy as TL
import Network.HTTP.Types hiding (Query)
import Network.Wai.Parse (FileInfo(..))
import qualified Web.Scotty as S
import ECC.DB (Env(..), insertDocument)
import ECC.Models
import ECC.Security (reject, rateLimitAccount)
import ECC.Store
import ECC.WorkflowSupport

type Guard = (User -> S.ActionM ()) -> S.ActionM ()

routes :: Env -> Guard -> Guard -> Guard -> S.ScottyM ()
routes env reader writer admin = do
 S.get "/api/clients/:id/profile" $ reader $ \u -> do
  cid<-S.pathParam "id"
  checkOwner env u Nothing (Just cid)
  photos<-liftIO $ jsonRows env "SELECT json_object('documentId',d.id,'scanStatus',d.scan_status) FROM client_photos p JOIN documents d ON d.id=p.document_id WHERE p.client_id=?" (Only(cid::Int))
  application<-liftIO $ jsonRows env "SELECT json_object('id',id,'category',coalesce(service_category,'Application'),'destination',coalesce(destination,''),'stage',stage,'institution',institution,'program',program,'offerStatus',offer_status,'enrollmentStatus',enrollment_status,'deadline',coalesce(next_deadline,'')) FROM cases WHERE client_id=? AND stage NOT IN ('Approved','Rejected','Completed') ORDER BY next_deadline NULLS LAST,id DESC LIMIT 1" (Only(cid::Int))
  milestones<-liftIO $ jsonRows env "SELECT json_object('title',m.title,'kind',m.kind,'plannedOn',coalesce(m.planned_on,'')) FROM application_milestones m JOIN cases a ON a.id=m.case_id WHERE a.client_id=? AND m.status NOT IN ('Completed','Cancelled') ORDER BY m.planned_on NULLS LAST,m.id LIMIT 5" (Only(cid::Int))
  task<-liftIO $ jsonRows env ("SELECT json_object('id',id,'title',title,'dueDate',coalesce(due_date,''),'priority',priority) FROM tasks t WHERE t.client_id=? AND t.status<>'Done' AND "<>taskVisibility<>" ORDER BY t.due_date NULLS LAST,t.id DESC LIMIT 1") (Only(cid::Int))
  [Only missing]<-liftIO $ query (envConn env) "SELECT count(*) FROM document_requests WHERE client_id=? AND required=1 AND (status<>'Approved' OR expires_on<date('now',business_offset()))" (Only(cid::Int)) :: S.ActionM [Only Int]
  requirements<-liftIO $ jsonRows env "SELECT json_object('title',title,'status',CASE WHEN expires_on<date('now',business_offset()) THEN 'Expired' ELSE status END) FROM document_requests WHERE client_id=? AND required=1 AND (status<>'Approved' OR expires_on<date('now',business_offset())) ORDER BY expires_on NULLS LAST,id LIMIT 5" (Only(cid::Int))
  respondJson env (A.object["photo".=(case photos of row:_ ->row; _->A.Null),"nextSteps".=A.object["application".=(case application of row:_ ->row; _->A.Null),"task".=(case task of row:_ ->row; _->A.Null),"outstandingDocuments".=missing,"requirements".=requirements,"milestones".=milestones]])
 S.post "/api/clients/:id/photo" $ writer $ \u -> do
  cid<-S.pathParam "id"
  checkOwner env u Nothing (Just cid)
  rateLimitAccount env "client-photo" (T.pack(show(userId u)))
  expected<-S.formParam "expectedDocumentId" :: S.ActionM Int
  checkPhotoRevision env cid expected
  files<-S.files
  case files of
   [(_,fi)] -> do
    let bytes=BL.toStrict(fileContent fi)
    when (B.null bytes || B.length bytes>2*1024*1024) $ reject status400 "Choose a nonempty PNG or JPEG up to 2 MB"
    mime<-maybe (reject status400 "Choose a valid PNG or JPEG no larger than 4096 by 4096 pixels") pure (photoMime bytes)
    liftIO $ do
     doc<-insertDocument (envConn env) Nothing (Just cid) (if mime=="image/png" then "client-photo.png" else "client-photo.jpg") mime bytes (Just(userId u))
     void $ execute (envConn env) "INSERT INTO client_photos(client_id,document_id) VALUES (?,?) ON CONFLICT(client_id) DO UPDATE SET document_id=excluded.document_id" (cid,documentId doc)
     recordHistory env u Nothing (Just cid) Nothing "client_photo" "Student photo uploaded for malware scanning"
    respondJson env (A.object["message".=("Photo uploaded. It becomes visible after malware scanning passes."::T.Text)])
   _ -> reject status400 "Choose one photo"
 S.get "/api/clients/:id/photo" $ reader $ \u -> do
  cid<-S.pathParam "id"
  checkOwner env u Nothing (Just cid)
  rows<-liftIO $ query (envConn env) "SELECT d.content,d.mime_type,d.scan_status FROM client_photos p JOIN documents d ON d.id=p.document_id WHERE p.client_id=?" (Only(cid::Int)) :: S.ActionM [(Binary B.ByteString,T.Text,T.Text)]
  case rows of
   [(Binary bytes,mime,"Clean")] -> do
    S.setHeader "Content-Type" (TL.fromStrict mime)
    S.setHeader "X-Content-Type-Options" "nosniff"
    S.setHeader "Cache-Control" "private, no-store"
    S.raw(BL.fromStrict bytes)
   [_] -> reject (mkStatus 423 "Locked") "Photo is quarantined until malware scanning passes"
   _ -> reject status404 "No photo uploaded"
 S.post "/api/clients/:id/photo/rescan" $ admin $ \u -> do
  cid<-S.pathParam "id"
  checkOwner env u Nothing (Just cid)
  rateLimitAccount env "client-photo-rescan" (T.pack(show(userId u)))
  changed<-liftIO $ execute (envConn env) "UPDATE documents SET scan_status='Pending',scan_attempts=0,scan_lease=NULL,scan_until=NULL,scan_detail=NULL WHERE id=(SELECT document_id FROM client_photos WHERE client_id=?) AND scan_status='Error'" (Only(cid::Int))
  unless(changed==1) $ reject status409 "Only a failed scan can be retried. Replace infected photos."
  liftIO $ recordHistory env u Nothing (Just cid) Nothing "client_photo" "Failed student photo scan queued again"
  respondJson env (A.object["message".=("Photo queued for scanning again"::T.Text)])

checkPhotoRevision :: Env -> Int -> Int -> S.ActionM ()
checkPhotoRevision env cid expected = do
 rows<-liftIO $ query (envConn env) "SELECT document_id FROM client_photos WHERE client_id=?" (Only cid) :: S.ActionM [Only Int]
 let current=case rows of Only did:_ ->did; _->0
 unless(current==expected) $ reject status409 "The student photo changed. Refresh before replacing it."

-- Validate raster signatures and bound decoded dimensions; SVG is never accepted.
-- Stored bytes still pass through the shared malware quarantine before display.
photoMime :: B.ByteString -> Maybe T.Text
photoMime bytes
 | B.take 8 bytes==B.pack [137,80,78,71,13,10,26,10], B.length bytes>=45, B.isSuffixOf (B.pack [0,0,0,0,73,69,78,68,174,66,96,130]) bytes, B.take 4(B.drop 12 bytes)=="IHDR", valid (be 16 4) (be 20 4) = Just "image/png"
 | B.take 3 bytes==B.pack [255,216,255], B.isSuffixOf (B.pack [255,217]) bytes, jpeg 2 = Just "image/jpeg"
 | otherwise = Nothing
 where
  be pos count=B.foldl' (\n x ->n*256+fromIntegral x) (0::Integer) (B.take count(B.drop pos bytes))
  valid width height=width>0 && height>0 && width<=4096 && height<=4096
  jpeg pos
   | pos+4>B.length bytes || B.index bytes pos/=255 = False
   | B.index bytes (pos+1)==255 = jpeg (pos+1)
   | marker `elem` [192,193,194,195,197,198,199,201,202,203,205,206,207] = size>=8 && end<=B.length bytes && valid (be (pos+7) 2) (be (pos+5) 2)
   | marker==218 || marker==217 || size<2 || end>B.length bytes = False
   | otherwise = jpeg end
   where marker=B.index bytes(pos+1);size=fromIntegral(be(pos+2) 2);end=pos+2+size
