{-# LANGUAGE OverloadedStrings #-}
module HardeningTests (run) where
import Control.Exception (bracket)
import qualified Data.ByteString.Char8 as BC
import qualified Data.ByteString.Lazy as BL
import System.Directory
import System.FilePath ((</>))
import ECC.Auth (randomToken, makeToken, verifyToken, checkLoginPassword, checkPassword, hashPassword, hmacSha256)
import qualified Data.ByteString.Base64.URL as B64
import Data.Time.Clock.POSIX (getPOSIXTime)
import ECC.Release (releaseContract)
import qualified Data.Text.Encoding as TE
import Control.Concurrent (forkIO, newEmptyMVar, putMVar, takeMVar, threadDelay)
import Control.Monad (unless, void, forM_)
import qualified Data.ByteString as B
import Data.IORef
import qualified Data.Text as T
import qualified Network.Wai as W
import qualified Network.Wai.Test as WT
import Network.Wai.Internal (ResponseReceived(..))
import Network.HTTP.Types
import ECC.Config (normalizePublicUrl, normalizeDatabaseUrl)
import ECC.Server (boundedBodies,operational,staticFiles)
import ECC.Config (Config(..))

run :: IO ()
run = do
 let secure = normalizeDatabaseUrl True "postgresql://test@example.invalid/ecc"
 unless (secure==Right "postgresql://test@example.invalid/ecc?sslmode=require") $ fail "PostgreSQL defaults to encrypted connections"
 forM_ ["disable","prefer","allow",""] $ \mode ->
  case normalizeDatabaseUrl True ("postgresql://test@example.invalid/ecc?sslmode="<>mode) of
   Left _ -> pure ()
   Right _ -> fail "Production must reject plaintext PostgreSQL fallback"
 let assert label good=unless good(fail label)
 mapM_ (\(raw,expected)->assert "PUBLIC_URL canonical origin" (normalizePublicUrl raw==Right expected))
  [(" https://CRM.Example:443/ ","https://crm.example"),("http://LOCALHOST:80/","http://localhost"),("https://[::1]:444/","https://[::1]:444")]
 mapM_ (\raw->assert "Invalid PUBLIC_URL rejected" (case normalizePublicUrl raw of Left _->True;_->False))
  ["https://user:password@example.com","https://example.com/path","https://example.com?secret=1","https://example.com/#x","ftp://example.com","https://example.com:0","https://"]
 let config=Config 4000 ":memory:" "test-secret-at-least-32-bytes-long" False False 2 "http://localhost:4000" False
     versioned=operational config (\_ respond->respond(W.responseLBS status200 [] "ok"))
 stale<-WT.runSession(WT.srequest(WT.SRequest W.defaultRequest{W.requestMethod="POST",W.requestHeaders=[("X-ECC-Contract","old-version")]} "")) versioned
 assert "Incompatible frontend cannot mutate data" (WT.simpleStatus stale==status426)
 -- State-changing cookie requests need the custom same-origin app header.
 let call headers method path size body=WT.runSession(WT.srequest(WT.SRequest ((WT.setPath W.defaultRequest path){W.requestMethod=method,W.requestHeaders=headers,W.requestBodyLength=W.KnownLength size}) body)) versioned
     cookie=[("Cookie","ecc-session=fixture")]
     contract=[("X-ECC-Contract",TE.encodeUtf8 releaseContract)]
 forM_ ["https://evil.example","null","http://localhost:4000.evil.example"] $ \origin -> do
  rejected<-call (("Origin",origin):contract) "POST" "/api/test" 2 "{}"
  assert "Untrusted and opaque origins cannot mutate" (WT.simpleStatus rejected==status403)
 forM_ ["cross-site","same-site"] $ \site -> do
  rejected<-call (("Sec-Fetch-Site",site):contract) "POST" "/api/test" 2 "{}"
  assert "Sibling sites cannot mutate through browser requests" (WT.simpleStatus rejected==status403)
 missingHeader<-call cookie "POST" "/api/test" 2 "{}"
 assert "Cookies alone cannot authorize a browser mutation" (WT.simpleStatus missingHeader==status403)
 sameOrigin<-call (("Origin","http://localhost:4000"):("Content-Type","application/json"):cookie++contract) "POST" "/api/test" 2 "{}"
 assert "Same-origin app requests still work" (WT.simpleStatus sameOrigin==status200)
 forM_ ["text/plain","application/x-www-form-urlencoded","application/xml"] $ \media -> do
  rejected<-call [("Content-Type",media)] "POST" "/api/auth/login" 2 "{}"
  assert "Simple forms and unsupported parsers cannot reach JSON API writes" (WT.simpleStatus rejected==status415)
 oversized<-call [("Content-Type","application/json")] "POST" "/api/test" (1024*1024+1) ""
 assert "Oversized JSON rejected before application work" (WT.simpleStatus oversized==status413)
 let production=operational config{cfgProduction=True} (\_ respond->respond(W.responseLBS status200 [("Cache-Control","public"),("X-Frame-Options","ALLOWALL")] "ok"))
 secured<-WT.runSession(WT.request W.defaultRequest) production
 assert "Sensitive responses cannot override security headers" (lookup "Cache-Control" (WT.simpleHeaders secured)==Just "no-store" && length(filter((=="Cache-Control").fst)(WT.simpleHeaders secured))==1 && lookup "X-Frame-Options" (WT.simpleHeaders secured)==Just "DENY")
 assert "HSTS and cross-origin protections enabled" (lookup "Strict-Transport-Security" (WT.simpleHeaders secured)/=Nothing && lookup "Cross-Origin-Resource-Policy" (WT.simpleHeaders secured)==Just "same-origin")
 assert "Embedded active objects disabled by CSP" (maybe False (B.isInfixOf "object-src 'none'") (lookup "Content-Security-Policy" (WT.simpleHeaders secured)))
 -- Correctly signed tokens with unapproved algorithms/headers remain invalid.
 now<-floor <$> getPOSIXTime::IO Int
 let encode=B.filter(/=61).B64.encode
     claims=encode(BC.pack("{\"sub\":1,\"exp\":"++show(now+3600)++",\"jti\":\"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA\"}"))
     signed header=let payload=encode header<>"."<>claims in payload<>"."<>encode(hmacSha256 "hardening-secret" payload)
 validSigned<-verifyToken "hardening-secret" (signed "{\"alg\":\"HS256\",\"typ\":\"JWT\"}")
 assert "Signed canonical control token is valid" (validSigned==Just 1)
 forM_ ["{\"alg\":\"none\",\"typ\":\"JWT\"}","{\"alg\":\"HS512\",\"typ\":\"JWT\"}"] $ \header -> do
  result<-verifyToken "hardening-secret" (signed header)
  assert "JWT algorithm/header confusion rejected even with a matching signature" (result==Nothing)
 token<-makeToken "hardening-secret" 1
 canonical<-verifyToken "hardening-secret" token
 padded<-verifyToken "hardening-secret" (token<>"=")
 huge<-verifyToken "hardening-secret" (B.replicate 5000 65)
 assert "Canonical sessions accepted and padded/oversized tokens rejected" (canonical==Just 1 && padded==Nothing && huge==Nothing)
 hashed<-hashPassword "a-test-password"
 assert "NUL and oversized bcrypt attempts cannot authenticate by a truncated prefix" (not(checkPassword "a-test-password\0suffix" hashed) && not(checkPassword (B.replicate 73 65) hashed))
 assert "Unknown accounts never authenticate through dummy password work" (not(checkLoginPassword "a-test-password" Nothing) && checkLoginPassword "a-test-password" (Just hashed))
 suffix<-BC.unpack <$> randomToken
 temporary<-getTemporaryDirectory
 let root=temporary</>("ecc-static-security-"++suffix)
 bracket (createDirectory root>>pure root) removeDirectoryRecursive $ \directory -> do
  let web=directory</>"web"
      static=staticFiles web (\_ respond->respond(W.responseLBS status404 [] ""))
      get path=WT.runSession(WT.request(WT.setPath W.defaultRequest path)) static
  createDirectory web
  B.writeFile (web</>"index.html") "safe app"
  B.writeFile (web</>"guide.html") "safe guide"
  B.writeFile (directory</>"private.js") "private secret"
  createFileLink (directory</>"private.js") (web</>"linked.js")
  forM_ [".env","backup.sql","data.sqlite3","settings.conf"] $ \name -> B.writeFile (web</>name) "private secret"
  forM_ ["/.env","/backup.sql","/data.sqlite3","/settings.conf","/linked.js","/../private.js"] $ \path -> do
   response<-get path
   assert "Static files never expose hidden/config/database files or symlink escapes" (WT.simpleStatus response==status404 && not(B.isInfixOf "private secret" (BL.toStrict(WT.simpleBody response))))
  guide<-get "/guide.html"
  route<-get "/clients/1"
  assert "Guide and SPA routes survive static hardening" (WT.simpleStatus guide==status200 && WT.simpleBody route=="safe app")
  blocked<-WT.runSession(WT.request((WT.setPath W.defaultRequest "/guide.html"){W.requestMethod="POST"})) static
  assert "Static pages cannot accept state-changing methods" (WT.simpleStatus blocked==status405)
  removeFile(web</>"index.html")
  createFileLink (directory</>"private.js") (web</>"index.html")
  escaped<-get "/clients/1"
  assert "SPA fallback cannot follow an index symlink outside assets" (WT.simpleStatus escaped==status404)
 bodyGuard<-boundedBodies 1 1000000
 let downstream _ respond=respond(W.responseLBS status200 [] "ok")
     jsonRequest bytes=WT.runSession(WT.srequest(WT.SRequest W.defaultRequest{W.requestMethod="POST",W.requestBodyLength=W.KnownLength(fromIntegral(BL.length bytes)),W.requestHeaders=[("Content-Type","application/json")]} bytes)) (bodyGuard downstream)
 nested<-jsonRequest (BL.replicate 65 91<>"0"<>BL.replicate 65 93)
 assert "Deep JSON cannot exhaust endpoint parser stacks" (WT.simpleStatus nested==status400)
 quotedBrackets<-jsonRequest ("\""<>BL.replicate 1000 91<>"\"")
 assert "JSON depth limits ignore characters inside strings" (WT.simpleStatus quotedBrackets==status200)

 let app=bodyGuard downstream
 started<-newEmptyMVar
 release<-newEmptyMVar
 finished<-newEmptyMVar
 first<-newIORef True
 let readChunk=do
      initial<-atomicModifyIORef' first (\value->(False,value))
      if initial then putMVar started () >> takeMVar release >> pure "x" else pure B.empty
     request=W.setRequestBodyChunks readChunk W.defaultRequest{W.requestMethod="POST",W.requestBodyLength=W.KnownLength 1,W.requestHeaders=[("Content-Type","multipart/form-data")]}
 _<-forkIO $ void $ app request (\response->putMVar finished (W.responseStatus response)>>pure ResponseReceived)
 takeMVar started
 get<-WT.runSession(WT.request W.defaultRequest) app
 assert "Slow upload does not occupy read capacity" (WT.simpleStatus get==status200)
 small<-WT.runSession(WT.srequest(WT.SRequest W.defaultRequest{W.requestMethod="POST",W.requestBodyLength=W.KnownLength 2,W.requestHeaders=[("Content-Type","application/json")]} "{}")) app
 assert "Slow upload does not occupy ordinary JSON body capacity" (WT.simpleStatus small==status200)
 busy<-WT.runSession(WT.srequest(WT.SRequest W.defaultRequest{W.requestMethod="POST",W.requestBodyLength=W.KnownLength 1,W.requestHeaders=[("Content-Type","multipart/form-data")]} "x")) app
 assert "Upload saturation rejects promptly" (WT.simpleStatus busy==status503)
 putMVar release ()
 finalStatus<-takeMVar finished
 assert "Upload can finish normally" (finalStatus==status200)
 shortGuard<-boundedBodies 1 20000
 let slow=W.setRequestBodyChunks (threadDelay 100000 >> pure B.empty) W.defaultRequest{W.requestMethod="POST",W.requestBodyLength=W.KnownLength 1}
 timed<-newEmptyMVar
 _<-shortGuard downstream slow (\response->putMVar timed(W.responseStatus response)>>pure ResponseReceived)
 timeoutStatus<-takeMVar timed
 assert "Slow request has a body deadline" (timeoutStatus==status408)
 after<-WT.runSession(WT.srequest(WT.SRequest W.defaultRequest{W.requestMethod="POST",W.requestBodyLength=W.KnownLength 1} "x")) (shortGuard downstream)
 assert "Timed-out body releases capacity" (WT.simpleStatus after==status200)
 putStrLn (T.unpack "Public URL normalization and bounded upload capacity checks passed")
