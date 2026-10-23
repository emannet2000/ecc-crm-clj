{-# LANGUAGE OverloadedStrings #-}
module ECC.Release (releaseContract, validateRelease) where

import Control.Monad (forM_, unless)
import qualified Data.Aeson as A
import Data.Aeson ((.:))
import Data.Aeson.Types (parseEither)
import qualified Data.ByteString as B
import qualified Data.Text as T
import qualified Data.Map.Strict as Map
import Data.List (sort, isSuffixOf)
import System.Directory (listDirectory, doesDirectoryExist)
import System.FilePath ((</>))
import ECC.Auth (tokenHash)

releaseContract :: T.Text
releaseContract = "ecc-crm-20261022-v2"

validateRelease :: FilePath -> FilePath -> FilePath -> IO ()
validateRelease web migrations binary = do
  bytes <- B.readFile (web </> "release.json")
  value <- either (fail . ("Invalid release manifest: "++)) pure (A.eitherDecodeStrict bytes)
  (contract,verified,backend,assets,schemas) <- either fail pure $ parseEither
    (A.withObject "release" (\o -> (,,,,) <$> o .: "contract" <*> o .: "verified" <*> o .: "backend" <*> o .: "assets" <*> o .: "migrations")) value
  unless (contract==releaseContract && verified) $ fail "Production requires a compatible release that passed the complete quality gate"
  actualBinary <- tokenHash <$> B.readFile binary
  unless (backend==actualBinary) $ fail "The API binary differs from the verified release"
  let expectedAssets = ["index.html","main.js","bootstrap.js","reports.js","finance-print.js","css/app.css","manifest.webmanifest","sw.js","offline.html","icons/icon-192.png","icons/icon-512.png","brand/ecc-emblem.png","guide.html"]
  unless (sort (Map.keys assets)==sort expectedAssets) $ fail "Release assets are incomplete"
  legacySchemas <- sort . filter (".sql" `isSuffixOf`) <$> listDirectory migrations
  pgExists <- doesDirectoryExist (migrations </> "postgresql")
  pgSchemas <- if pgExists then map ("postgresql/"++) . sort . filter (".sql" `isSuffixOf`) <$> listDirectory (migrations </> "postgresql") else pure []
  let diskSchemas=sort(legacySchemas++pgSchemas)
  unless (Map.keys schemas==diskSchemas && not (null legacySchemas) && last legacySchemas=="0018_provider_integrations.sql" && pgSchemas==["postgresql/0001_postgresql.sql","postgresql/0002_student_workflows.sql","postgresql/0003_lead_number_prefix.sql","postgresql/0004_client_journey.sql","postgresql/0005_provider_integrations.sql"]) $ fail "Migration files are incompatible with this API release"
  forM_ [(web,assets),(migrations,schemas)] $ \(root,files) ->
    forM_ (Map.toList (files :: Map.Map FilePath T.Text)) $ \(name,expected) -> do
      -- Only enumerated assets/migration filenames reach the filesystem.
      digest <- tokenHash <$> B.readFile (root </> name)
      unless (digest==expected) $ fail ("Release file changed after verification: "++name)
