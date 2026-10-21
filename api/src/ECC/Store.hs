{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE FlexibleInstances #-}
{-# OPTIONS_GHC -Wno-orphans #-}
module ECC.Store
  ( Connection, Query(..), Only(..), ToRow, FromRow
  , SQLError(..), Error(..), Binary(..), query, query_, execute, execute_
  , returning, withTransaction, withReadTransaction, openDatabase, close, execScript, isPostgres, migrationDirectory, prepareContext, clearContext ) where
import qualified Database.SQLite.Simple as S
import Database.SQLite.Simple (Query(..), Only(..), ToRow(..), FromRow(..), SQLError(..), Error(..))
import qualified Database.PostgreSQL.LibPQ as P
import qualified ECC.Postgres as PG
import Control.Exception (bracketOnError, mask, onException)
import Control.Monad (when)
import Data.Time (timeZoneName)
import Database.SQLite.Simple.FromField
import Database.SQLite.Simple.ToField
import qualified Database.SQLite3 as SQLite
import qualified Data.Aeson as A
import qualified Data.ByteString as B
import qualified Data.ByteString.Lazy as BL
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import Data.Int (Int64)
import ECC.Clock (businessZone, zoneModifier)
import Control.Monad (forM, void)

newtype Binary a = Binary a
instance ToField (Binary B.ByteString) where toField (Binary bytes) = S.SQLBlob bytes
instance FromField (Binary B.ByteString) where fromField field = Binary <$> fromField field
instance FromField A.Value where
  fromField field = do
    value <- fromField field
    case A.eitherDecodeStrict (TE.encodeUtf8 value) of
      Right parsed -> pure parsed
      Left message -> returnError ConversionFailed field message
instance ToField A.Value where toField = S.SQLText . TE.decodeUtf8 . BL.toStrict . A.encode

-- SQLite remains available for existing installations and regression fixtures.
-- PostgreSQL URLs always use libpq; never interpret them as local filenames.
data Connection = Local S.Connection | Postgres P.Connection

isPostgres :: Connection -> Bool
isPostgres (Postgres _)=True
isPostgres _=False

migrationDirectory :: Connection -> FilePath -> FilePath
migrationDirectory cn root=if isPostgres cn then root ++ "/postgresql" else root

query :: (ToRow q, FromRow r) => Connection -> Query -> q -> IO [r]
query (Local cn) sql args=S.query cn sql args
query (Postgres cn) (Query sql) args=snd <$> PG.run cn sql (toRow args) >>= mapM PG.decodeRow

query_ :: FromRow r => Connection -> Query -> IO [r]
query_ cn sql=query cn sql ()

execute :: ToRow q => Connection -> Query -> q -> IO Int64
execute (Local cn) sql params = S.execute cn sql params >> fromIntegral <$> S.changes cn
execute (Postgres cn) (Query sql) params=fst <$> PG.run cn sql (toRow params)

execute_ :: Connection -> Query -> IO Int64
execute_ cn sql=execute cn sql ()

returning :: ToRow q => Connection -> Query -> [q] -> IO [[Int]]
returning conn sql rows = forM rows $ \row -> map S.fromOnly <$> (query conn sql row :: IO [Only Int])

withTransaction :: Connection -> IO a -> IO a
withTransaction (Local cn)=S.withImmediateTransaction cn
withTransaction cn=transaction cn "BEGIN; SELECT pg_advisory_xact_lock(1162036050)"

withReadTransaction :: Connection -> IO a -> IO a
withReadTransaction (Local cn)=S.withTransaction cn
withReadTransaction cn=transaction cn "BEGIN ISOLATION LEVEL REPEATABLE READ"

-- Serialize CRM mutations across services, preserving revision checks and
-- cross-row financial invariants while allowing concurrent read snapshots.
transaction :: Connection -> T.Text -> IO a -> IO a
transaction cn begin action=mask $ \restore -> do
 execScript cn begin
 result<-restore action `onException` execScript cn "ROLLBACK"
 execScript cn "COMMIT" `onException` execScript cn "ROLLBACK"
 pure result

execScript :: Connection -> T.Text -> IO ()
execScript (Local cn)=SQLite.exec(S.connectionHandle cn)
execScript (Postgres cn)=PG.script cn

close :: Connection -> IO ()
close (Local cn)=S.close cn
close (Postgres cn)=PG.close cn

openDatabase :: FilePath -> IO Connection
openDatabase path
 | any (`T.isPrefixOf` T.pack path) ["postgresql://","postgres://"] = do
    zone<-businessZone
    bracketOnError (PG.open(T.pack path)) PG.close $ \cn -> do
     _<-PG.run cn "SELECT set_config('ecc.timezone',?,false)" [SQLite.SQLText(T.pack(timeZoneName zone))]
     -- Every pooled session gets its own authorization context. SQL triggers use
     -- this shadow too; no global actor row is shared between requests.
     PG.script cn "CREATE TEMP TABLE request_context(id BIGINT PRIMARY KEY,actor_id BIGINT,role TEXT,assigned_only TEXT); INSERT INTO request_context VALUES(1,NULL,NULL,'false')"
     pure(Postgres cn)
 | otherwise = do
    zone <- businessZone
    cn <- S.open path
    SQLite.createFunction (S.connectionHandle cn) "business_offset" (Just 0) True (\ctx _ -> SQLite.funcResultText ctx (zoneModifier zone))
    S.execute_ cn "PRAGMA busy_timeout=10000"
    _ <- (S.query_ cn "PRAGMA journal_mode=WAL" :: IO [Only T.Text])
    S.execute_ cn "PRAGMA foreign_keys=ON"
    S.execute_ cn "PRAGMA synchronous=FULL"
    pure(Local cn)

prepareContext :: Connection -> IO ()
prepareContext cn=when (not(isPostgres cn)) $ do
 _<-execute_ cn "CREATE TEMP TABLE IF NOT EXISTS request_context (id INTEGER PRIMARY KEY,actor_id INTEGER,role TEXT,assigned_only TEXT)"
 _<-execute_ cn "INSERT OR IGNORE INTO temp.request_context VALUES (1,NULL,NULL,'false')"
 pure ()

clearContext :: Connection -> Bool -> IO ()
clearContext cn readOnly=do
 _<-execute_ cn "UPDATE request_context SET actor_id=NULL,role=NULL,assigned_only='false' WHERE id=1"
 when (not(isPostgres cn) && not readOnly) $ void $ execute_ cn "UPDATE main.request_context SET actor_id=NULL,role=NULL,assigned_only='false' WHERE id=1"

instance (FromField a, FromField b, FromField c, FromField d, FromField e, FromField f, FromField g, FromField h, FromField i, FromField j, FromField k) => FromRow (a,b,c,d,e,f,g,h,i,j,k) where
  fromRow = (,,,,,,,,,,) <$> S.field <*> S.field <*> S.field <*> S.field <*> S.field <*> S.field <*> S.field <*> S.field <*> S.field <*> S.field <*> S.field
instance (ToField a, ToField b, ToField c, ToField d, ToField e, ToField f, ToField g, ToField h, ToField i, ToField j, ToField k) => ToRow (a,b,c,d,e,f,g,h,i,j,k) where
  toRow (a,b,c,d,e,f,g,h,i,j,k) = [toField a, toField b, toField c, toField d, toField e, toField f, toField g, toField h, toField i, toField j, toField k]

instance (FromField a, FromField b, FromField c, FromField d, FromField e, FromField f, FromField g, FromField h, FromField i, FromField j, FromField k, FromField l) => FromRow (a,b,c,d,e,f,g,h,i,j,k,l) where
  fromRow = (,,,,,,,,,,,) <$> S.field <*> S.field <*> S.field <*> S.field <*> S.field <*> S.field <*> S.field <*> S.field <*> S.field <*> S.field <*> S.field <*> S.field
instance (ToField a, ToField b, ToField c, ToField d, ToField e, ToField f, ToField g, ToField h, ToField i, ToField j, ToField k, ToField l) => ToRow (a,b,c,d,e,f,g,h,i,j,k,l) where
  toRow (a,b,c,d,e,f,g,h,i,j,k,l) = [toField a, toField b, toField c, toField d, toField e, toField f, toField g, toField h, toField i, toField j, toField k, toField l]

instance (FromField a, FromField b, FromField c, FromField d, FromField e, FromField f, FromField g, FromField h, FromField i, FromField j, FromField k, FromField l, FromField m) => FromRow (a,b,c,d,e,f,g,h,i,j,k,l,m) where
  fromRow = (,,,,,,,,,,,,) <$> S.field <*> S.field <*> S.field <*> S.field <*> S.field <*> S.field <*> S.field <*> S.field <*> S.field <*> S.field <*> S.field <*> S.field <*> S.field
instance (ToField a, ToField b, ToField c, ToField d, ToField e, ToField f, ToField g, ToField h, ToField i, ToField j, ToField k, ToField l, ToField m) => ToRow (a,b,c,d,e,f,g,h,i,j,k,l,m) where
  toRow (a,b,c,d,e,f,g,h,i,j,k,l,m) = [toField a, toField b, toField c, toField d, toField e, toField f, toField g, toField h, toField i, toField j, toField k, toField l, toField m]

instance (FromField a, FromField b, FromField c, FromField d, FromField e, FromField f, FromField g, FromField h, FromField i, FromField j, FromField k, FromField l, FromField m, FromField n) => FromRow (a,b,c,d,e,f,g,h,i,j,k,l,m,n) where
  fromRow = (,,,,,,,,,,,,,) <$> S.field <*> S.field <*> S.field <*> S.field <*> S.field <*> S.field <*> S.field <*> S.field <*> S.field <*> S.field <*> S.field <*> S.field <*> S.field <*> S.field
instance (ToField a, ToField b, ToField c, ToField d, ToField e, ToField f, ToField g, ToField h, ToField i, ToField j, ToField k, ToField l, ToField m, ToField n) => ToRow (a,b,c,d,e,f,g,h,i,j,k,l,m,n) where
  toRow (a,b,c,d,e,f,g,h,i,j,k,l,m,n) = [toField a, toField b, toField c, toField d, toField e, toField f, toField g, toField h, toField i, toField j, toField k, toField l, toField m, toField n]

instance (FromField a, FromField b, FromField c, FromField d, FromField e, FromField f, FromField g, FromField h, FromField i, FromField j, FromField k, FromField l, FromField m, FromField n, FromField o) => FromRow (a,b,c,d,e,f,g,h,i,j,k,l,m,n,o) where
  fromRow = (,,,,,,,,,,,,,,) <$> S.field <*> S.field <*> S.field <*> S.field <*> S.field <*> S.field <*> S.field <*> S.field <*> S.field <*> S.field <*> S.field <*> S.field <*> S.field <*> S.field <*> S.field
instance (ToField a, ToField b, ToField c, ToField d, ToField e, ToField f, ToField g, ToField h, ToField i, ToField j, ToField k, ToField l, ToField m, ToField n, ToField o) => ToRow (a,b,c,d,e,f,g,h,i,j,k,l,m,n,o) where
  toRow (a,b,c,d,e,f,g,h,i,j,k,l,m,n,o) = [toField a, toField b, toField c, toField d, toField e, toField f, toField g, toField h, toField i, toField j, toField k, toField l, toField m, toField n, toField o]

instance (FromField a, FromField b, FromField c, FromField d, FromField e, FromField f, FromField g, FromField h, FromField i, FromField j, FromField k, FromField l, FromField m, FromField n, FromField o, FromField p) => FromRow (a,b,c,d,e,f,g,h,i,j,k,l,m,n,o,p) where
  fromRow = (,,,,,,,,,,,,,,,) <$> S.field <*> S.field <*> S.field <*> S.field <*> S.field <*> S.field <*> S.field <*> S.field <*> S.field <*> S.field <*> S.field <*> S.field <*> S.field <*> S.field <*> S.field <*> S.field
instance (ToField a, ToField b, ToField c, ToField d, ToField e, ToField f, ToField g, ToField h, ToField i, ToField j, ToField k, ToField l, ToField m, ToField n, ToField o, ToField p) => ToRow (a,b,c,d,e,f,g,h,i,j,k,l,m,n,o,p) where
  toRow (a,b,c,d,e,f,g,h,i,j,k,l,m,n,o,p) = [toField a, toField b, toField c, toField d, toField e, toField f, toField g, toField h, toField i, toField j, toField k, toField l, toField m, toField n, toField o, toField p]

instance (FromField a, FromField b, FromField c, FromField d, FromField e, FromField f, FromField g, FromField h, FromField i, FromField j, FromField k, FromField l, FromField m, FromField n, FromField o, FromField p, FromField q) => FromRow (a,b,c,d,e,f,g,h,i,j,k,l,m,n,o,p,q) where
  fromRow = (,,,,,,,,,,,,,,,,) <$> S.field <*> S.field <*> S.field <*> S.field <*> S.field <*> S.field <*> S.field <*> S.field <*> S.field <*> S.field <*> S.field <*> S.field <*> S.field <*> S.field <*> S.field <*> S.field <*> S.field
instance (ToField a, ToField b, ToField c, ToField d, ToField e, ToField f, ToField g, ToField h, ToField i, ToField j, ToField k, ToField l, ToField m, ToField n, ToField o, ToField p, ToField q) => ToRow (a,b,c,d,e,f,g,h,i,j,k,l,m,n,o,p,q) where
  toRow (a,b,c,d,e,f,g,h,i,j,k,l,m,n,o,p,q) = [toField a, toField b, toField c, toField d, toField e, toField f, toField g, toField h, toField i, toField j, toField k, toField l, toField m, toField n, toField o, toField p, toField q]
