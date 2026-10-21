{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}
module Main (main) where
import Control.Exception (bracket)
import Control.Concurrent.Chan
import Data.IORef
import Control.Monad (replicateM, forM_, unless)
import Data.Char (isSpace)
import qualified ECC.Store as Store
import qualified Data.Text as T
import qualified Data.ByteString as B
import qualified Data.Text.Encoding as TE
import Data.Maybe (fromMaybe)
import qualified Network.Wai.Handler.Warp as Warp
import qualified Network.Wai as Wai
import Network.Wai.Middleware.Gzip (gzip, defaultGzipSettings, GzipSettings(..), GzipFiles(..))
import System.Directory (doesFileExist)
import System.Environment (getArgs, lookupEnv, getExecutablePath)
import qualified Web.Scotty as Scotty
import Network.HTTP.Types (status503)
import ECC.Logging
import qualified Data.Aeson as A
import System.IO (hSetBuffering, stdout, stderr, BufferMode(LineBuffering))
import ECC.Server
import ECC.Config
import qualified ECC.DB as DB
import ECC.Migrations
import ECC.Routes
import ECC.Seed
import System.Exit (exitSuccess, exitFailure)
import ECC.Release (validateRelease)
import ECC.Models (NewUser(..))

main :: IO ()
main = catchSync runMain $ \err -> do
  logEvent writeLog "ERROR" "startup_exception" (exceptionFields err)
  exitFailure

runMain :: IO ()
runMain = do
  hSetBuffering stdout LineBuffering
  hSetBuffering stderr LineBuffering
  cfg <- loadConfig
  args <- getArgs
  let valid = case args of
        [] -> True
        ["verify-release"] -> True
        ["migrate"] -> True
        ["create-user-env"] -> True
        ["adduser",_,_,_,_] -> True
        ["reset-password",_,_] -> True
        ["reset-mfa",_] -> True
        _ -> False
  if valid then pure () else fail "Unknown command; no database changes were made"
  localWeb <- doesFileExist "web/dist/index.html"
  distDir <- fromMaybe (if localWeb then "web/dist" else "../web/dist") <$> lookupEnv "WEB_DIST"
  whenProduction cfg args $ getExecutablePath >>= validateRelease distDir "migrations"
  if args==["verify-release"] then getExecutablePath >>= validateRelease distDir "migrations" >> putStrLn "Verified compatible release" >> exitSuccess else pure ()
  conn <- Store.openDatabase (cfgDatabase cfg)
  if cfgProduction cfg && args/=["migrate"] then requireCurrentSchema conn "migrations" else pure ()
  runMigrations conn "migrations"
  case args of
    ["create-user-env"] -> createUserFromEnvironment conn
    ["adduser",email,name,role,pw] -> do
      if role `notElem` ["admin","consultant","viewer"] || length pw < 12 then fail "Valid role and 12+ character password required" else pure ()
      Store.withTransaction conn $ DB.addUser conn (T.toLower (T.pack email)) (T.pack name) (T.pack role) (T.pack pw)
    ["reset-password",email,pw] -> do
      if length pw<12 then fail "12+ character password required" else pure ()
      ok <- Store.withTransaction conn $ DB.setPassword conn (T.pack email) (T.pack pw)
      if ok then putStrLn "Password updated; sessions revoked" else fail "User not found"
    ["reset-mfa",email] -> Store.withTransaction conn $ do
      rows <- Store.query conn "SELECT id FROM users WHERE lower(email)=lower(?)" (Store.Only (T.pack email)) :: IO [Store.Only Int]
      case rows of
        [Store.Only uid] -> do
          _ <- Store.execute conn "UPDATE users SET mfa_secret=NULL,mfa_pending=NULL,mfa_last_step=-1 WHERE id=?" (Store.Only uid)
          _ <- Store.execute conn "DELETE FROM mfa_recovery_codes WHERE user_id=?" (Store.Only uid)
          _ <- Store.execute conn "DELETE FROM sessions WHERE user_id=?" (Store.Only uid)
          putStrLn "Authenticator reset; account sessions revoked"
        _ -> fail "User not found"
    ["migrate"] -> pure ()
    [] -> serve cfg conn
    _ -> fail "Usage: ecc-crm-api [verify-release | migrate | create-user-env | adduser EMAIL NAME ROLE PASSWORD | reset-password EMAIL PASSWORD | reset-mfa EMAIL]"

-- One-time operator setup: no passwords in process arguments and no upsert that
-- could silently replace or promote an existing account.
createUserFromEnvironment :: Store.Connection -> IO ()
createUserFromEnvironment conn = do
  email <- T.toLower . T.strip <$> required "ECC_USER_EMAIL"
  name <- T.strip <$> required "ECC_USER_NAME"
  role <- required "ECC_USER_ROLE"
  password <- required "ECC_USER_PASSWORD"
  let validEmail = case T.splitOn "@" email of
        [local,domain] -> not (T.null local || T.null domain || T.any isSpace email)
        _ -> False
  unless (validEmail && T.length email<=255 && not(T.null name) && T.length name<=255 && role `elem` ["admin","consultant","viewer"] && T.length password>=12 && B.length(TE.encodeUtf8 password)<=72 && not(T.any (=='\0') password)) $
    fail "Supply a valid account name/email, an explicit role, and a password of 12 characters to 72 UTF-8 bytes"
  created <- Store.withTransaction conn $ DB.insertUser conn (NewUser email name role password)
  case created of
    Nothing -> fail "Account already exists; existing credentials and permissions were not changed"
    Just _ -> putStrLn "Account created; verify its access before use"
 where
  required :: String -> IO T.Text
  required key = lookupEnv key >>= maybe (fail(key++" is required")) (pure . T.pack)

serve :: Config -> Store.Connection -> IO ()
serve cfg conn = do
  Store.withTransaction conn $ seedIfEmpty conn (cfgSeedDemo cfg)
  localWeb <- doesFileExist "web/dist/index.html"
  distDir <- fromMaybe (if localWeb then "web/dist" else "../web/dist") <$> lookupEnv "WEB_DIST"
  exists <- doesFileExist (distDir ++ "/index.html")
  if not exists then fail "WEB_DIST must contain the compiled frontend" else pure ()
  connections <- (conn:) <$> replicateM (cfgPoolSize cfg-1) (Store.openDatabase (cfgDatabase cfg))
  available <- newChan
  forM_ connections $ \cn -> do
    let env = DB.Env cn (cfgJwtSecret cfg) (cfgProduction cfg) (cfgPublicUrl cfg) (cfgAssignedOnly cfg)
    application <- Scotty.scottyApp (app env)
    writeChan available (cn,application)
  admission <- newIORef (cfgPoolSize cfg * 2)
  bodyGuard <- boundedBodies (cfgPoolSize cfg * 2) (15*1000000)
  let api req respond = withPermit admission
        (respond (jsonBusy)) $
        bracket (readChan available) (writeChan available) $ \(cn,application) ->
          transactionalApplication cn application req respond
      jsonBusy = Wai.responseLBS status503 [("Content-Type","application/json"),("Retry-After","1")] "{\"error\":\"API busy. Try again shortly.\"}"
  logEvent writeLog "INFO" "server_started" ["port" A..= cfgPort cfg]
  Warp.runSettings (Warp.setOnException (\request err -> logEvent writeLog "ERROR" "transport_exception" (maybe [] (requestFields . (\r -> r { Wai.requestHeaders = [] })) request ++ exceptionFields err)) (Warp.setPort (cfgPort cfg) (Warp.setTimeout 60 Warp.defaultSettings))) (operational cfg (gzip defaultGzipSettings { gzipFiles = GzipCompress } (staticFiles distDir (bodyGuard api))))


whenProduction :: Config -> [String] -> IO () -> IO ()
whenProduction cfg args check = if cfgProduction cfg && null args then check else pure ()
