{-# LANGUAGE OverloadedStrings #-}
module ReleaseTests (run) where

import Control.Exception (bracket, try)
import Control.Monad (forM, unless, void)
import qualified Data.Aeson as A
import Data.Aeson ((.=))
import qualified Data.ByteString as B
import qualified Data.ByteString.Char8 as BC
import qualified Data.ByteString.Lazy as BL
import qualified Data.Map.Strict as Map
import qualified Data.Text as T
import System.Directory
import System.FilePath ((</>),takeDirectory)
import Data.List (isSuffixOf)
import ECC.Auth (tokenHash,randomToken)
import ECC.Release
import ECC.Store
import ECC.Migrations (runMigrations,requireCurrentSchema)

run :: IO ()
run = do
  temporary <- getTemporaryDirectory
  suffix <- BC.unpack <$> randomToken
  let root=temporary </> ("ecc-release-"++suffix)
      web=root </> "web"
      schemas=root </> "migrations"
      binary=root </> "api"
      assert label good=unless good(fail label)
      rejects label action=do
        result<-try action :: IO (Either IOError ())
        assert label (case result of Left _->True; _->False)
  bracket (createDirectory root >> pure root) removeDirectoryRecursive $ \_ -> do
    createDirectory web
    createDirectory schemas
    let names=["index.html","main.js","bootstrap.js","reports.js","finance-print.js","css/app.css","manifest.webmanifest","sw.js","offline.html","icons/icon-192.png","icons/icon-512.png","brand/ecc-emblem.png","guide.html"]
    assets<-Map.fromList <$> forM names (\name->do
      let file=web </> name
      createDirectoryIfMissing True (takeDirectory file)
      B.writeFile file "fixture asset"
      pure(name,tokenHash "fixture asset"))
    legacy<-filter (".sql" `isSuffixOf`) <$> listDirectory "migrations"
    pg<-map ("postgresql/"++) . filter (".sql" `isSuffixOf`) <$> listDirectory "migrations/postgresql"
    let files=legacy++pg
    migrations<-Map.fromList <$> forM files (\name->do
      bytes<-B.readFile ("migrations" </> name)
      createDirectoryIfMissing True (takeDirectory (schemas </> name))
      B.writeFile (schemas </> name) bytes
      pure(name,tokenHash bytes))
    B.writeFile binary "fixture binary"
    let write verified contract selected=BL.writeFile (web </> "release.json") $ A.encode $ A.object
          ["contract".=contract,"verified".=verified,"backend".=tokenHash "fixture binary","assets".=selected,"migrations".=migrations]
        valid=write True releaseContract assets
        check=validateRelease web schemas binary
    valid
    check
    write False releaseContract assets
    rejects "Unverified release cannot start production" check
    write True ("wrong-contract"::T.Text) assets
    rejects "Frontend/API contract mismatch is rejected" check
    write True releaseContract (Map.delete "main.js" assets)
    rejects "Missing release assets are rejected" check
    valid
    B.writeFile binary "different binary"
    rejects "A binary rebuilt after verification is rejected" check
    B.writeFile binary "fixture binary"
    B.writeFile (web </> "main.js") "changed asset"
    rejects "Changed frontend is rejected" check
    B.writeFile (web </> "main.js") "fixture asset"
    B.appendFile (schemas </> "0014_business_clock.sql") "\n-- changed"
    rejects "Changed migration is rejected" check
  bracket (openDatabase ":memory:") close $ \conn -> do
    rejects "Uninitialized production schema is rejected" (requireCurrentSchema conn "migrations")
    runMigrations conn "migrations"
    requireCurrentSchema conn "migrations"
    void $ execute_ conn "INSERT INTO schema_migrations(version) VALUES ('9999_future.sql')"
    rejects "Database newer than release is rejected" (runMigrations conn "migrations")
  putStrLn "Release verification, asset/binary/migration mismatch and schema downgrade checks passed"
