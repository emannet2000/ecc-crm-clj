{-# LANGUAGE OverloadedStrings #-}
module Main where
import Control.Monad (unless, when, forM, forM_)
import Control.Exception (SomeException, bracket, try, throwIO)
import Control.Concurrent
import Data.List (nub)
import qualified Data.Aeson as A
import Data.Aeson ((.=), (.:))
import Data.Aeson.Types (parseMaybe)
import qualified Data.Text.Encoding as TE
import System.Environment (setEnv, unsetEnv)
import System.Directory
import System.FilePath ((</>))
import qualified Network.Wai as Wai
import qualified Network.Wai.Test as WT
import Network.Wai.Middleware.Gzip (gzip, defaultGzipSettings, GzipSettings(..), GzipFiles(..))
import Network.HTTP.Types (statusCode, status404)
import qualified Web.Scotty as Scotty
import ECC.Store
import qualified ECC.DB as DB
import ECC.Models
import ECC.Config
import ECC.Migrations
import qualified ECC.Routes as Routes
import ECC.Server
import qualified Data.ByteString.Char8 as B
import qualified Data.Text as T
import ECC.Auth
import qualified ConfigTests
import qualified LoggingTests
import qualified ReleaseTests
import qualified ConcurrencyTests
import qualified ClockTests
import ECC.Clock (businessDay)
import Data.Time.Clock.POSIX (getPOSIXTime)
import qualified ControlsTests
import qualified HardeningTests
import qualified FinanceTests
import qualified AccessTests
import qualified ClientApplicationTests
import qualified JourneyTests
import qualified GeneratedTests
import qualified FeatureTests
import ECC.Release (releaseContract)
import ECC.Csv

assert :: String -> Bool -> IO ()
assert label condition = unless condition (fail label)
main :: IO ()
main = do
  let staticApp = staticFiles "web/dist" (\_ respond -> respond (Wai.responseLBS status404 [] ""))
  let compressedApp = gzip defaultGzipSettings { gzipFiles = GzipCompress } staticApp
  compressed <- WT.runSession (WT.request ((WT.setPath Wai.defaultRequest "/main.js") { Wai.requestHeaders = [("Accept-Encoding","gzip")] })) compressedApp
  assert "Elm bundle is compressed for browsers accepting gzip" (lookup "Content-Encoding" (WT.simpleHeaders compressed) == Just "gzip")
  manifest <- WT.runSession (WT.request (WT.setPath Wai.defaultRequest "/manifest.webmanifest")) staticApp
  assert "PWA manifest has installable MIME type" (lookup "Content-Type" (WT.simpleHeaders manifest) == Just "application/manifest+json")
  worker <- WT.runSession (WT.request (WT.setPath Wai.defaultRequest "/sw.js")) staticApp
  assert "PWA worker served as JavaScript and revalidated" (lookup "Content-Type" (WT.simpleHeaders worker) == Just "application/javascript" && lookup "Cache-Control" (WT.simpleHeaders worker) == Just "no-cache")
  missingManifest <- WT.runSession (WT.request (WT.setPath Wai.defaultRequest "/missing.webmanifest")) staticApp
  assert "Missing manifest returns 404 instead of app HTML" (statusCode (WT.simpleStatus missingManifest) == 404)
  let secret = "test-secret-for-auth-regressions-123"
  token <- makeToken secret 42
  second <- makeToken secret 42
  assert "tokens must have independent nonces" (token /= second)
  uid <- verifyToken secret token
  assert "signed session verifies" (uid == Just 42)
  wrong <- verifyToken "wrong-secret" token
  assert "wrong key is rejected" (wrong == Nothing)
  altered <- verifyToken secret (token <> "x")
  assert "tampered signature is rejected" (altered == Nothing)
  malformed <- mapM (verifyToken secret) ["", "a", "a.b", "a.b.c", "...", "a..c"]
  assert "malformed tokens are rejected" (all (==Nothing) malformed)
  random <- randomToken
  assert "reset tokens contain 256 bits of randomness" (B.length random == 43)
  assert "tokens are URL safe" (B.all (\c -> c `elem` (['A'..'Z']++['a'..'z']++['0'..'9']++"-_")) random)
  hashed <- hashPassword "correct-password"
  assert "bcrypt verifies the correct password" (checkPassword "correct-password" hashed)
  assert "bcrypt rejects the wrong password" (not (checkPassword "incorrect-password" hashed))
  assert "CSV quoted commas and escaped quotes" (parseCsv "Name,Notes\r\n\"Chen, Maya\",\"Said \"\"hello\"\"\"\r\n" == [["Name","Notes"],["Chen, Maya","Said \"hello\""]])
  assert "CSV multiline fields and BOM" (parseCsv "\xFEFFName,Notes\nMaya,\"first\nsecond\"\n" == [["Name","Notes"],["Maya","first\nsecond"]])
  assert "CSV empty rows are ignored" (parseCsv "\n,\nName,Email\n" == [["Name","Email"]])
  assert "hashes do not contain raw tokens" (not (T.isInfixOf (T.pack (B.unpack random)) (tokenHash random)))
  putStrLn "Auth and CSV regression checks passed"
  ConfigTests.run
  LoggingTests.run
  leadNumberTests
  integrationTests
  AccessTests.run
  FinanceTests.run
  ReleaseTests.run
  ConcurrencyTests.run
  ClockTests.run
  HardeningTests.run
  ControlsTests.run
  GeneratedTests.run

leadNumberTests :: IO ()
leadNumberTests = bracket (openDatabase ":memory:") close $ \conn -> do
  runMigrations conn "migrations"
  withTransaction conn $ do
    DB.addUser conn "numbers@example.com" "Numbers" "admin" "correct-password-123"
    _ <- execute_ conn "DELETE FROM schema_migrations WHERE version='0016_lead_number_prefix.sql'"
    _ <- execute_ conn "INSERT INTO leads(lead_number,full_name) VALUES ('L-2026-0002','Existing lead')"
    _ <- execute_ conn "INSERT INTO leads(lead_number,full_name,deleted_at) VALUES ('L-2026-0007','Archived lead','2026-10-18')"
    _ <- execute_ conn "INSERT INTO reference_counters(prefix,year,value) VALUES ('L',2026,9),('ECC',2026,50)"
    pure ()
  runMigrations conn "migrations"
  runMigrations conn "migrations"
  numbers <- query_ conn "SELECT lead_number FROM leads ORDER BY id" :: IO [Only T.Text]
  assert "Migration preserves existing and archived lead sequences" (numbers == map Only ["ECC-2026-0002","ECC-2026-0007"])
  counters <- query_ conn "SELECT prefix,value FROM reference_counters WHERE year=2026 ORDER BY prefix" :: IO [(T.Text,Int)]
  assert "Lead migration preserves allocated gaps and separate student counter" (counters == [("ECC",50),("L",9)])
  withTransaction conn $ do
    yearRows <- query_ conn "SELECT CAST(strftime('%Y','now',business_offset()) AS INTEGER)" :: IO [Only Int]
    let year = fromOnly (head yearRows)
        expected = "ECC-" <> T.pack (show year) <> if year == 2026 then "-0010" else "-0001"
    lead <- DB.insertLead conn (NewLead "New numbered lead" Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing) 1
    assert "New leads use uppercase ECC and continue their own sequence" (leadNumber lead == expected)

-- Exercise the real WAI application and SQLite transactions without opening sockets.
integrationTests :: IO ()
integrationTests = do
  suffix <- randomToken
  directory <- getTemporaryDirectory
  let file = directory </> ("ecc-regression-" ++ B.unpack suffix ++ ".sqlite3")
      secret = "integration-secret-32-bytes-123456"
  bracket (openDatabase file) (\conn -> close conn >> mapM_ removeIfPresent [file,file++"-wal",file++"-shm"]) $ \conn -> do
    runMigrations conn "migrations"
    runMigrations conn "migrations"
    withTransaction conn $ DB.addUser conn "admin@example.com" "Admin" "admin" "correct-password-123"
    application <- Scotty.scottyApp (Routes.app (DB.Env conn secret False "http://localhost:4000" True))
    let cfg = Config 4000 file secret False False 2 "http://localhost:4000" True
        api = operational cfg (transactionalApplication conn application)
        call = callHeaders []
        callHeaders headers method path auth body = WT.runSession (WT.srequest (WT.SRequest
          ((WT.setPath Wai.defaultRequest path) { Wai.requestMethod=method, Wai.requestHeaders=headers ++ [("Content-Type","application/json")] ++ maybe [] (\token -> [("Authorization","Bearer "<>token)]) auth }) (A.encode body))) api
        expect code response = assert ("Expected HTTP "++show code++", got "++show (WT.simpleStatus response)++": "++show (WT.simpleBody response)) (statusCode (WT.simpleStatus response)==code)
        json = A.object
    login <- call "POST" "/api/auth/login" Nothing (json ["lrEmail" .= ("admin@example.com"::T.Text),"lrPassword" .= ("correct-password-123"::T.Text)])
    expect 200 login
    tok <- TE.encodeUtf8 <$> jsonField "token" login
    let admin method path body = call method path (Just tok) body
    clock <- call "GET" "/api/time" Nothing A.Null
    expect 200 clock
    millis <- jsonField "unixMillis" clock :: IO Integer
    actualMillis <- floor . (*1000) <$> getPOSIXTime
    businessDate <- T.pack . show <$> businessDay
    returnedDate <- jsonField "date" clock
    assert "Public clock is current and uses business date" (abs (millis-actualMillis)<5000 && returnedDate==businessDate)
    assert "Clock responses cannot be cached" (lookup "Cache-Control" (WT.simpleHeaders clock)==Just "no-store")
    ready <- call "GET" "/api/ready" Nothing A.Null
    expect 200 ready
    bracket (openDatabase file) close $ \writer -> withTransaction writer $ do
      concurrentRead <- admin "GET" "/api/leads" A.Null
      expect 200 concurrentRead
      concurrentReady <- call "GET" "/api/ready" Nothing A.Null
      expect 200 concurrentReady
    assert "Security headers are present" (lookup "X-Content-Type-Options" (WT.simpleHeaders ready)==Just "nosniff")
    lead <- admin "POST" "/api/leads" (json ["nlFullName" .= ("Maya Chen"::T.Text),"nlService" .= ("Student Visa"::T.Text),"nlDestination" .= ("Canada"::T.Text),"nlEmail" .= ("maya@example.com"::T.Text),"nlNextFollowup" .= ("2020-01-01"::T.Text)])
    expect 200 lead
    lid <- jsonField "leadId" lead :: IO Int
    let leadPath = B.pack ("/api/leads/"++show lid)
    note <- admin "POST" (leadPath<>"/notes") (json ["nrNote" .= ("Preserve this conversation"::T.Text)])
    expect 200 note
    task <- admin "POST" "/api/tasks" (json ["ntLeadId" .= lid,"ntTitle" .= ("Prepare documents"::T.Text)])
    expect 200 task
    doc <- withTransaction conn $ DB.insertDocument conn (Just lid) Nothing "proof.txt" "application/octet-stream" "preserved bytes" (Just 1)
    converted <- admin "POST" (leadPath<>"/convert") A.Null
    expect 200 converted
    cid <- jsonField "id" converted :: IO Int
    detail <- admin "GET" (B.pack ("/api/clients/"++show cid)) A.Null
    expect 200 detail
    listedClients <- admin "GET" "/api/clients" A.Null
    expect 200 listedClients
    clientRows <- either fail pure (A.eitherDecode (WT.simpleBody listedClients)) :: IO [A.Value]
    forM_ clientRows $ \row -> do
      rowId <- maybe (fail "Client list id missing") pure (parseMaybe (A.withObject "client" (.: "id")) row) :: IO Int
      actualRevision <- maybe (fail "Client list revision missing") pure (parseMaybe (A.withObject "client" (.: "revision")) row) :: IO Int
      expectedRevisions <- query conn "SELECT revision FROM record_versions WHERE kind='clients' AND record_id=?" (Only rowId) :: IO [Only Int]
      assert "Batched client revisions match persisted revisions" (expectedRevisions == [Only actualRevision])
    value <- decodeResponse detail
    inlineTasks <- admin "GET" (B.pack ("/api/workspace/record/client/"++show cid++"/tasks")) A.Null
    expect 200 inlineTasks
    inlineRows <- jsonField "rows" inlineTasks :: IO [A.Value]
    assert "Converted lead tasks appear in inline client work" (not(null inlineRows))
    let documents = parseMaybe (A.withObject "detail" (.: "documents")) value :: Maybe [A.Value]
        tasks = parseMaybe (A.withObject "detail" (.: "tasks")) value :: Maybe [A.Value]
        activities = parseMaybe (A.withObject "detail" (.: "activities")) value :: Maybe [A.Value]
    assert "Conversion preserves documents, tasks and history" (maybe False (not.null) documents && maybe False (not.null) tasks && maybe False ((>=2).length) activities)
    _ <- execute conn "UPDATE documents SET scan_status='Clean' WHERE id=?" (Only (documentId doc))
    download <- admin "GET" (B.pack ("/api/documents/"++show (documentId doc)++"/download")) A.Null
    expect 200 download
    assert "Document bytes survive conversion" (WT.simpleBody download == "preserved bytes")
    clientTask <- admin "POST" "/api/tasks" (json ["ntClientId" .= cid,"ntTitle" .= ("Client-only task"::T.Text)])
    expect 200 clientTask
    assignedClient <- jsonField "clientId" clientTask
    assert "New tasks can attach directly to a client" (assignedClient == cid)
    retry <- admin "POST" (leadPath<>"/convert") A.Null
    expect 200 retry
    retryId <- jsonField "id" retry
    assert "Conversion retries are idempotent" (retryId == cid)
    hidden <- admin "GET" leadPath A.Null
    expect 404 hidden
    -- A failure after client creation must roll the entire request back.
    rollbackLead <- admin "POST" "/api/leads" (json ["nlFullName" .= ("Rollback"::T.Text),"nlService" .= ("Student Visa"::T.Text)])
    rid <- jsonField "leadId" rollbackLead :: IO Int
    execScript conn "CREATE TRIGGER fail_case BEFORE INSERT ON cases BEGIN SELECT RAISE(ABORT,'simulated failure'); END;"
    failed <- admin "POST" (B.pack ("/api/leads/"++show rid++"/convert")) A.Null
    assert "Conversion failure is reported" (statusCode (WT.simpleStatus failed)>=400)
    execScript conn "DROP TRIGGER fail_case;"
    rows <- query_ conn "SELECT count(*) FROM clients WHERE full_name='Rollback'" :: IO [Only Int]
    assert "Failed conversion rolls back the inserted client" (rows == [Only 0])
    preserved <- admin "GET" (B.pack ("/api/leads/"++show rid)) A.Null
    expect 200 preserved
    -- Archive and restore preserve dependent records.
    deleted <- admin "DELETE" (B.pack ("/api/leads/"++show rid)) A.Null
    expect 200 deleted
    archive <- admin "GET" "/api/archive" A.Null
    expect 200 archive
    restored <- admin "POST" (B.pack ("/api/leads/"++show rid++"/restore")) A.Null
    expect 200 restored
    -- Validate all list, aggregate and operational queries against SQLite.
    forM_ ["/api/leads?limit=1","/api/tasks","/api/clients","/api/stats","/api/activities","/api/duplicates","/api/reminders","/api/audit","/api/metrics"] $ \path -> admin "GET" path A.Null >>= expect 200
    invalid <- admin "POST" "/api/leads" (json ["nlFullName" .= (" "::T.Text)])
    expect 400 invalid
    -- Role checks and record ownership are enforced by the server.
    viewer <- admin "POST" "/api/users" (json ["nuName" .= ("Viewer"::T.Text),"nuEmail" .= ("viewer@example.com"::T.Text),"nuRole" .= ("viewer"::T.Text),"nuPassword" .= ("correct-password-123"::T.Text)])
    expect 200 viewer
    viewerLogin <- call "POST" "/api/auth/login" Nothing (json ["lrEmail" .= ("viewer@example.com"::T.Text),"lrPassword" .= ("correct-password-123"::T.Text)])
    viewerToken <- TE.encodeUtf8 <$> jsonField "token" viewerLogin
    forbidden <- call "POST" "/api/leads" (Just viewerToken) (json ["nlFullName" .= ("Forbidden"::T.Text)])
    expect 403 forbidden
    scoped <- call "GET" (B.pack ("/api/leads/"++show rid)) (Just viewerToken) A.Null
    expect 404 scoped
    -- Recovery responses do not disclose account existence; expired links fail.
    recoveryUser <- admin "POST" "/api/users" (json ["nuName" .= ("Recovery checks"::T.Text),"nuEmail" .= ("recovery-check@example.com"::T.Text),"nuRole" .= ("consultant"::T.Text),"nuPassword" .= ("recovery-old-password"::T.Text)])
    expect 200 recoveryUser
    knownRecovery <- call "POST" "/api/auth/recover" Nothing (json ["email" .= ("recovery-check@example.com"::T.Text)])
    unknownRecovery <- call "POST" "/api/auth/recover" Nothing (json ["email" .= ("nobody-recovery@example.com"::T.Text)])
    expect 200 knownRecovery
    expect 200 unknownRecovery
    assert "Recovery response does not enumerate accounts" (WT.simpleBody knownRecovery == WT.simpleBody unknownRecovery)
    [Only beforeHash] <- query_ conn "SELECT token_hash FROM account_tokens WHERE user_id=(SELECT id FROM users WHERE email='recovery-check@example.com')" :: IO [Only T.Text]
    _ <- call "POST" "/api/auth/recover" Nothing (json ["email" .= ("recovery-check@example.com"::T.Text)])
    [Only afterHash] <- query_ conn "SELECT token_hash FROM account_tokens WHERE user_id=(SELECT id FROM users WHERE email='recovery-check@example.com')" :: IO [Only T.Text]
    [Only queuedLinks] <- query_ conn "SELECT count(*) FROM mail_outbox WHERE recipient='recovery-check@example.com'" :: IO [Only Int]
    assert "Repeated recovery preserves the emailed token and avoids duplicate mail" (beforeHash==afterHash && queuedLinks==1)
    [Only recoveryBody] <- query_ conn "SELECT body FROM mail_outbox WHERE recipient='recovery-check@example.com' ORDER BY id DESC LIMIT 1" :: IO [Only T.Text]
    let expiredResetToken = T.takeWhile (/='\n') (T.drop 7 (snd (T.breakOn "?reset=" recoveryBody)))
    _ <- execute_ conn "UPDATE account_tokens SET expires_at=datetime('now','-1 second') WHERE user_id=(SELECT id FROM users WHERE email='recovery-check@example.com')"
    expiredReset <- call "POST" "/api/auth/reset" Nothing (json ["token" .= expiredResetToken,"password" .= ("recovery-new-password"::T.Text)])
    expect 400 expiredReset

    -- Single-use invitations and password reset invalidate previous sessions.
    invite <- admin "POST" "/api/users" (json ["nuName" .= ("Invited"::T.Text),"nuEmail" .= ("invited@example.com"::T.Text),"nuRole" .= ("consultant"::T.Text),"nuPassword" .= (""::T.Text)])
    expect 200 invite
    [Only emailBody] <- query_ conn "SELECT body FROM mail_outbox WHERE recipient='invited@example.com'" :: IO [Only T.Text]
    let resetToken = T.takeWhile (/='\n') (T.drop 7 (snd (T.breakOn "?reset=" emailBody)))
    reset <- call "POST" "/api/auth/reset" Nothing (json ["token" .= resetToken,"password" .= ("new-password-12345"::T.Text)])
    expect 200 reset
    again <- call "POST" "/api/auth/reset" Nothing (json ["token" .= resetToken,"password" .= ("new-password-12345"::T.Text)])
    expect 400 again
    -- Revoked bearer tokens and URL tokens cannot authenticate.
    logout <- admin "POST" "/api/auth/logout" A.Null
    expect 200 logout
    revoked <- admin "GET" "/api/auth/me" A.Null
    expect 401 revoked
    queryToken <- call "GET" ("/api/export/leads.csv?token="<>tok) Nothing A.Null
    expect 401 queryToken
    cookieLogin <- call "POST" "/api/auth/login" Nothing (json ["lrEmail" .= ("admin@example.com"::T.Text),"lrPassword" .= ("correct-password-123"::T.Text)])
    cookie <- maybe (fail "Login must set an HttpOnly cookie") pure (lookup "Set-Cookie" (WT.simpleHeaders cookieLogin))
    assert "Cookie is HttpOnly and SameSite Strict" ("HttpOnly" `B.isInfixOf` cookie && "SameSite=Strict" `B.isInfixOf` cookie)
    let cookieCall method path = WT.runSession (WT.request ((WT.setPath Wai.defaultRequest path) { Wai.requestMethod=method, Wai.requestHeaders=[("Cookie",B.takeWhile (/=';') cookie),("X-ECC-Contract",TE.encodeUtf8 releaseContract)] })) api
    cookieMe <- cookieCall "GET" "/api/auth/me"
    expect 200 cookieMe
    cookieLogout <- cookieCall "POST" "/api/auth/logout"
    expect 200 cookieLogout
    cookieRevoked <- cookieCall "GET" "/api/auth/me"
    expect 401 cookieRevoked
    forM_ [1..20::Int] $ \_ -> call "POST" "/api/auth/recover" Nothing (json ["email" .= ("unknown@example.com"::T.Text)]) >>= expect 200
    throttled <- call "POST" "/api/auth/recover" Nothing (json ["email" .= ("unknown@example.com"::T.Text)])
    expect 429 throttled
    otherAccount <- call "POST" "/api/auth/recover" Nothing (json ["email" .= ("independent@example.com"::T.Text)])
    expect 200 otherAccount
    setEnv "PROXY_TOKEN" "test-proxy-shared-secret-32-bytes-123456"
    let trusted ip = [("X-ECC-Proxy-Token","test-proxy-shared-secret-32-bytes-123456"),("X-ECC-Client-IP",ip)]
    forM_ [1..20::Int] $ \_ -> callHeaders (trusted "192.0.2.1") "POST" "/api/auth/reset" Nothing (json ["token" .= ("invalid"::T.Text),"password" .= ("new-password-123"::T.Text)]) >>= expect 400
    blockedSource <- callHeaders (trusted "192.0.2.1") "POST" "/api/auth/reset" Nothing A.Null
    expect 429 blockedSource
    independentSource <- callHeaders (trusted "192.0.2.2") "POST" "/api/auth/reset" Nothing (json ["token" .= ("invalid"::T.Text),"password" .= ("new-password-123"::T.Text)])
    expect 400 independentSource
    _ <- execute_ conn "DELETE FROM login_attempts WHERE key LIKE 'reset:%'"
    -- Without the secret, spoofed client addresses still share the socket source.
    forM_ [1..20::Int] $ \_ -> call "POST" "/api/auth/reset" Nothing (json ["token" .= ("invalid"::T.Text),"password" .= ("new-password-123"::T.Text)]) >>= expect 400
    spoofed <- callHeaders [("X-ECC-Client-IP","192.0.2.3")] "POST" "/api/auth/reset" Nothing A.Null
    expect 429 spoofed
    unsetEnv "PROXY_TOKEN"
    -- A fresh session after the logout checks above.
    newLogin <- call "POST" "/api/auth/login" Nothing (json ["lrEmail" .= ("admin@example.com"::T.Text),"lrPassword" .= ("correct-password-123"::T.Text)])
    newToken <- TE.encodeUtf8 <$> jsonField "token" newLogin
    withTransaction conn $ forM_ [1..205::Int] $ \n -> do
      _ <- execute conn "INSERT INTO leads(lead_number,full_name,deleted_at) VALUES (?,?,'2026-10-18')" ("archive-"<>T.pack (show n),"Archived "<>T.pack (show n))
      pure ()
    laterArchive <- call "GET" "/api/archive?limit=50&offset=200" (Just newToken) A.Null
    expect 200 laterArchive
    let archiveRows = A.decode' (WT.simpleBody laterArchive) :: Maybe [A.Value]
    assert "Archive exposes records beyond the former 200-record cap" (maybe False ((>=5).length) archiveRows)
    withTransaction conn $ forM_ [1..105::Int] $ \n -> forM_ [1..2::Int] $ \copy -> do
      _ <- execute conn "INSERT INTO leads(lead_number,full_name,email,next_followup) VALUES (?,?,?,'2026-10-18')" ("duplicate-"<>T.pack (show n)<>"-"<>T.pack (show copy),"Duplicate "<>T.pack (show n),"duplicate"<>T.pack (show n)<>"@example.com")
      pure ()
    forM_ ["/api/duplicates?limit=50&offset=100","/api/reminders?limit=50&offset=200"] $ \path -> do
      later <- call "GET" path (Just newToken) A.Null
      expect 200 later
      assert "Operational pages expose later results" (maybe False (not.null) (A.decode' (WT.simpleBody later) :: Maybe [A.Value]))
    -- Independent SQLite connections allocate references atomically.
    boxes <- forM [1..8::Int] $ \n -> do
      box <- newEmptyMVar
      _ <- forkIO $ do
        result <- try $ bracket (openDatabase file) close $ \other -> withTransaction other $
          DB.insertLead other (NewLead ("Concurrent "<>T.pack (show n)) Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing) 1
        putMVar box (result :: Either SomeException Lead)
      pure box
    results <- mapM takeMVar boxes
    numbers <- forM results $ \result -> either throwIO (pure.leadNumber) result
    assert "Concurrent references are unique" (length (nub numbers)==8)
    FeatureTests.run conn api
    ClientApplicationTests.run conn api
    JourneyTests.run conn api
    putStrLn "SQLite/WAI integration checks passed"

removeIfPresent :: FilePath -> IO ()
removeIfPresent file = doesFileExist file >>= \exists -> when exists (removeFile file)
decodeResponse :: WT.SResponse -> IO A.Value
decodeResponse response = either fail pure (A.eitherDecode (WT.simpleBody response))
jsonField :: A.FromJSON a => A.Key -> WT.SResponse -> IO a
jsonField key response = do
  value <- decodeResponse response
  maybe (fail ("Missing JSON field: "++show key++" in "++show value)) pure (parseMaybe (A.withObject "response" (.: key)) value)
