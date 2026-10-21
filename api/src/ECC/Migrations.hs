{-# LANGUAGE OverloadedStrings #-}

-- | Applies SQL migrations from the @migrations/@ directory, tracking applied
-- versions in a @schema_migrations@ table.
module ECC.Migrations (runMigrations, requireCurrentSchema) where

import Control.Monad (forM_, unless)

import qualified Data.ByteString as B
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import Data.List (sort, isSuffixOf)
import ECC.Store

import System.Directory (listDirectory)
import System.FilePath ((</>))

runMigrations :: Connection -> FilePath -> IO ()
runMigrations conn root = withTransaction conn $ do
  let dir=migrationDirectory conn root
  _ <- execute_ conn
    "CREATE TABLE IF NOT EXISTS schema_migrations (version TEXT PRIMARY KEY, applied_at TEXT NOT NULL DEFAULT (CAST(CURRENT_TIMESTAMP AS TEXT)))"
  files <- listDirectory dir
  let sqls = sort [f | f <- files, ".sql" `isSuffixOf` f]
  applied <- map fromOnly <$>
    query_ conn "SELECT version FROM schema_migrations" :: IO [T.Text]
  unless (all ((`elem` sqls) . T.unpack) applied) $ fail "Database has migrations missing from this release; refusing a schema downgrade"
  forM_ sqls $ \f -> do
    let ver = T.pack f
    unless (ver `elem` applied) $ do
      contents <- B.readFile (dir </> f)
      do
        execScript conn (TE.decodeUtf8 contents)
        _ <- execute conn "INSERT INTO schema_migrations (version) VALUES (?)" (Only ver)
        pure ()
      putStrLn ("[migrate] applied " ++ f)

-- Production startup must never silently upgrade a database before its recovery
-- procedure has been run. Explicit deployment preparation applies migrations.
requireCurrentSchema :: Connection -> FilePath -> IO ()
requireCurrentSchema conn root = do
  let dir=migrationDirectory conn root
      sql=if isPostgres conn then "SELECT table_name FROM information_schema.tables WHERE table_schema=current_schema() AND table_name='schema_migrations'" else "SELECT name FROM sqlite_master WHERE type='table' AND name='schema_migrations'"
  tables <- query_ conn sql :: IO [Only T.Text]
  unless (not (null tables)) $ fail "Prepare and migrate this database before starting production"
  files <- sort . filter (".sql" `isSuffixOf`) <$> listDirectory dir
  applied <- map (T.unpack . fromOnly) <$> (query_ conn "SELECT version FROM schema_migrations ORDER BY version" :: IO [Only T.Text])
  unless (applied==files) $ fail "Database schema differs from release; run verified deployment preparation before starting production"
