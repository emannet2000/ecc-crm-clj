{-# LANGUAGE OverloadedStrings #-}

-- | Domain types shared by the DB layer and the HTTP routes.
--
-- Wire format is camelCase JSON.  Types whose fields share a common Haskell
-- prefix (user, task, activity, client, case) get that prefix stripped and
-- the remainder lower-cased, e.g. @taskDueDate -> "dueDate"@.
module ECC.Models
  ( User(..)
  , Lead(..)
  , LeadDetail(..)
  , NewLead(..)
  , UpdateLead(..)
  , Task(..)
  , NewTask(..)
  , Activity(..)
  , Client(..)
  , ClientDetail(..)
  , NewClient(..)
  , CaseRow(..)
  , CaseInput(..)
  , Document(..)
  , StageCount(..)
  , SourceCount(..)
  , Stats(..)
  , LoginRequest(..)
  , LoginResponse(..)
  , NoteRequest(..)
  , TaskStatusRequest(..)
  , NewUser(..)
  , UpdateUser(..)
  , PasswordChange(..)
  , AuditEntry(..)
  , BulkOp(..)
  , BulkRequest(..)
  , ImportRowError(..)
  , ImportResult(..)
  ) where

import Data.Aeson (ToJSON (..), FromJSON (..), Value (..), object, (.=), genericToJSON,
                   withText, genericToEncoding, genericParseJSON, defaultOptions,
                   Options (..))
import Data.Char (toLower)
import Data.List (isPrefixOf)
import GHC.Generics (Generic)
import Data.Text (Text)
import Data.Time (Day, UTCTime)

-- | @taskDueDate@ -> "dueDate": drop the prefix when present and lower-case
-- the first letter of what remains.
prefixOpts :: String -> Options
prefixOpts p = defaultOptions { fieldLabelModifier = mod }
  where
    mod f
      | p `isPrefixOf` f = lowerFirst (drop (length p) f)
      | otherwise        = f
    lowerFirst [] = []
    lowerFirst (c:cs) = toLower c : cs

-- | Users of the CRM. Roles: "admin" > "consultant" > "viewer" (read-only).
data User = User
  { userId    :: Int
  , userEmail :: Text
  , userName  :: Text
  , userRole  :: Text
  } deriving (Show, Eq, Generic)

instance ToJSON User where
  toEncoding = genericToEncoding (prefixOpts "user")
  toJSON = genericToJSON (prefixOpts "user")
instance FromJSON User where parseJSON = genericParseJSON (prefixOpts "user")

data Lead = Lead
  { leadId            :: Int
  , leadNumber        :: Text
  , fullName          :: Text
  , email             :: Maybe Text
  , phone             :: Maybe Text
  , source            :: Maybe Text
  , consultantId      :: Maybe Int
  , consultantName    :: Maybe Text
  , quality           :: Maybe Text
  , stage             :: Text
  , destination       :: Maybe Text
  , service           :: Maybe Text
  , notes             :: Maybe Text
  , lastContact       :: Maybe Day
  , nextFollowup      :: Maybe Day
  , createdAt         :: UTCTime
  , updatedAt         :: UTCTime
  } deriving (Show, Eq, Generic, ToJSON, FromJSON)

-- | Composite payload for the lead detail page.
data LeadDetail = LeadDetail
  { ldLead         :: Lead
  , ldTasks        :: [Task]
  , ldActivities   :: [Activity]
  , ldDocuments    :: [Document]
  } deriving (Show, Eq, Generic)

instance ToJSON LeadDetail where
  toJSON ld = object
    [ "lead" .= ldLead ld
    , "tasks" .= ldTasks ld
    , "activities" .= ldActivities ld
    , "documents" .= ldDocuments ld
    ]

data NewLead = NewLead
  { nlFullName     :: Text
  , nlEmail        :: Maybe Text
  , nlPhone        :: Maybe Text
  , nlSource       :: Maybe Text
  , nlQuality      :: Maybe Text
  , nlStage        :: Maybe Text
  , nlDestination  :: Maybe Text
  , nlService      :: Maybe Text
  , nlNotes        :: Maybe Text
  , nlNextFollowup :: Maybe Day
  , nlConsultantId :: Maybe Int
  } deriving (Show, Eq, Generic, FromJSON)

data UpdateLead = UpdateLead
  { ulFullName     :: Maybe Text
  , ulEmail        :: Maybe Text
  , ulPhone        :: Maybe Text
  , ulSource       :: Maybe Text
  , ulConsultantId :: Maybe Int
  , ulQuality      :: Maybe Text
  , ulStage        :: Maybe Text
  , ulDestination  :: Maybe Text
  , ulService      :: Maybe Text
  , ulNotes        :: Maybe Text
  , ulLastContact  :: Maybe Day
  , ulNextFollowup :: Maybe Day
  } deriving (Show, Eq, Generic, FromJSON)

data Task = Task
  { taskId           :: Int
  , taskLeadId       :: Int
  , taskLeadName     :: Maybe Text
  , taskTitle        :: Text
  , taskDescription  :: Maybe Text
  , taskDueDate      :: Maybe Day
  , taskPriority     :: Text
  , taskStatus       :: Text
  , taskAssignedTo   :: Maybe Int
  , taskAssigneeName :: Maybe Text
  , taskCreatedAt    :: UTCTime
  , taskClientId     :: Maybe Int
  } deriving (Show, Eq, Generic)

instance ToJSON Task where
  toEncoding = genericToEncoding (prefixOpts "task")
  toJSON = genericToJSON (prefixOpts "task")
instance FromJSON Task where parseJSON = genericParseJSON (prefixOpts "task")

data NewTask = NewTask
  { ntLeadId      :: Maybe Int
  , ntClientId    :: Maybe Int
  , ntTitle       :: Text
  , ntDescription :: Maybe Text
  , ntDueDate     :: Maybe Day
  , ntPriority    :: Maybe Text
  } deriving (Show, Eq, Generic, FromJSON)

data Activity = Activity
  { activityId          :: Int
  , activityLeadId      :: Int
  , activityLeadName    :: Maybe Text
  , activityKind        :: Text
  , activityDescription :: Maybe Text
  , activityDate        :: Day
  } deriving (Show, Eq, Generic)

instance ToJSON Activity where
  toEncoding = genericToEncoding (prefixOpts "activity")
  toJSON = genericToJSON (prefixOpts "activity")
instance FromJSON Activity where parseJSON = genericParseJSON (prefixOpts "activity")

data Client = Client
  { clientId        :: Int
  , clientNumber    :: Text
  , clientFullName  :: Text
  , clientEmail     :: Maybe Text
  , clientPhone     :: Maybe Text
  , caseOfficerId   :: Maybe Int
  , caseOfficerName :: Maybe Text
  , clientCreatedAt :: UTCTime
  } deriving (Show, Eq, Generic)

instance ToJSON Client where
  toEncoding = genericToEncoding (prefixOpts "client")
  toJSON = genericToJSON (prefixOpts "client")
instance FromJSON Client where parseJSON = genericParseJSON (prefixOpts "client")

data CaseRow = CaseRow
  { caseId         :: Int
  , caseClientId   :: Int
  , caseCategory   :: Maybe Text
  , caseDestination:: Maybe Text
  , caseStage      :: Text
  , caseDeadline   :: Maybe Day
  , caseCreatedAt  :: UTCTime
  } deriving (Show, Eq, Generic)

instance ToJSON CaseRow where
  toEncoding = genericToEncoding (prefixOpts "case")
  toJSON = genericToJSON (prefixOpts "case")
instance FromJSON CaseRow where parseJSON = genericParseJSON (prefixOpts "case")

data ClientDetail = ClientDetail
  { cdClient    :: Client
  , cdCases     :: [CaseRow]
  , cdDocuments :: [Document]
  , cdTasks :: [Task]
  , cdActivities :: [Activity]
  } deriving (Show, Eq, Generic)

-- | Nested payload: {client: {...}, cases: [...], documents: [...]}
instance ToJSON ClientDetail where
  toJSON cd = object
    [ "client" .= cdClient cd
    , "cases" .= cdCases cd
    , "tasks" .= cdTasks cd
    , "activities" .= cdActivities cd
    , "documents" .= cdDocuments cd
    ]

data NewClient = NewClient
  { ncFullName    :: Text
  , ncEmail       :: Maybe Text
  , ncPhone       :: Maybe Text
  , ncCaseOfficer :: Maybe Int
  } deriving (Show, Eq, Generic, FromJSON)

data CaseInput = CaseInput
  { ciServiceCategory :: Maybe Text
  , ciDestination     :: Maybe Text
  , ciStage           :: Maybe Text
  , ciNextDeadline    :: Maybe Day
  , ciCaseId          :: Maybe Int  -- ^ present => update that case instead of insert
  } deriving (Show, Eq, Generic, FromJSON)

-- | Metadata for an uploaded file; the raw bytes never reach the JSON layer.
data Document = Document
  { documentId        :: Int
  , documentLeadId    :: Maybe Int
  , documentClientId  :: Maybe Int
  , documentFilename  :: Text
  , documentMimeType  :: Text
  , documentSize      :: Int
  , documentUploader  :: Maybe Text  -- ^ uploader display name
  , documentCreatedAt :: UTCTime
  } deriving (Show, Eq, Generic)

instance ToJSON Document where
  toEncoding = genericToEncoding (prefixOpts "document")
  toJSON = genericToJSON (prefixOpts "document")

data StageCount = StageCount { scStage :: Text, scCount :: Int }
  deriving (Show, Eq, Generic, ToJSON)

data SourceCount = SourceCount { srcSource :: Text, srcCount :: Int }
  deriving (Show, Eq, Generic, ToJSON)

data Stats = Stats
  { stTotalLeads     :: Int
  , stHotLeads       :: Int
  , stTotalClients   :: Int
  , stOpenTasks      :: Int
  , stOverdueTasks   :: Int
  , stStageCounts    :: [StageCount]
  , stSourceCounts   :: [SourceCount]
  , stUpcomingTasks  :: [Task]
  , stRecentActivity :: [Activity]
  } deriving (Show, Eq, Generic, ToJSON)

data LoginRequest = LoginRequest { lrEmail :: Text, lrPassword :: Text, lrOtp :: Maybe Text }
  deriving (Show, Eq, Generic, FromJSON)

data LoginResponse = LoginResponse { token :: Text, user :: User }
  deriving (Show, Eq, Generic, ToJSON)

data NoteRequest = NoteRequest { nrNote :: Text }
  deriving (Show, Eq, Generic, FromJSON)

data TaskStatusRequest = TaskStatusRequest { tsrStatus :: Text }
  deriving (Show, Eq, Generic, FromJSON)

-- | Admin-only user creation.
data NewUser = NewUser
  { nuEmail    :: Text
  , nuName     :: Text
  , nuRole     :: Text
  , nuPassword :: Text
  } deriving (Show, Eq, Generic, FromJSON)

-- | Partial update; empty password means "keep current".
data UpdateUser = UpdateUser
  { uuName     :: Maybe Text
  , uuRole     :: Maybe Text
  , uuPassword :: Maybe Text
  } deriving (Show, Eq, Generic, FromJSON)

-- | Self-service password change: current password must match.
data PasswordChange = PasswordChange
  { pcCurrent :: Text
  , pcNew     :: Text
  } deriving (Show, Eq, Generic, FromJSON)

-- | One audit-trail row.  @auditChanges@ holds @{"Field":{"from":…,"to":…}}@
-- for updates and is Nothing for deletes.
data AuditEntry = AuditEntry
  { auditId         :: Int
  , auditEntityType :: Text
  , auditEntityId   :: Int
  , auditEntityName :: Maybe Text
  , auditAction     :: Text        -- ^ "created" | "updated" | "deleted"
  , auditChanges    :: Maybe Value
  , auditActorName  :: Maybe Text
  , auditCreatedAt  :: UTCTime
  } deriving (Show, Eq, Generic)

instance ToJSON AuditEntry where
  toEncoding = genericToEncoding (prefixOpts "audit")
  toJSON = genericToJSON (prefixOpts "audit")

data BulkOp = BulkAdvance | BulkAssign | BulkDelete
  deriving (Show, Eq, Generic)

instance ToJSON BulkOp where
  toJSON op = toJSON (case op of
    BulkAdvance -> "advance" :: Text
    BulkAssign  -> "assign"
    BulkDelete  -> "delete")

instance FromJSON BulkOp where
  parseJSON = withText "BulkOp" $ \t -> case t of
    "advance" -> pure BulkAdvance
    "assign"  -> pure BulkAssign
    "delete"  -> pure BulkDelete
    _         -> fail ("unknown bulk op: " <> show t)

data BulkRequest = BulkRequest
  { brOp           :: BulkOp
  , brIds          :: [Int]
  , brConsultantId :: Maybe Int
  } deriving (Show, Eq, Generic, FromJSON)

data ImportRowError = ImportRowError
  { ireRow   :: Int    -- ^ 1-based data-row number (header excluded)
  , ireError :: Text
  } deriving (Show, Eq, Generic)

instance ToJSON ImportRowError where
  toEncoding = genericToEncoding (prefixOpts "ire")
  toJSON = genericToJSON (prefixOpts "ire")

data ImportResult = ImportResult
  { imrImported :: Int
  , imrFailed   :: [ImportRowError]
  } deriving (Show, Eq, Generic)

instance ToJSON ImportResult where
  toEncoding = genericToEncoding (prefixOpts "imr")
  toJSON = genericToJSON (prefixOpts "imr")
