{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}
module ECC.Server (operational, operationalWith, staticFiles, transactionalApplication, transactionalApplicationWith, boundedBodies, withPermit) where
import Control.Exception ( Exception, catch, bracket, throwIO, fromException, toException)
import System.Timeout (timeout)
import qualified ECC.Store as Store
import qualified Data.Aeson as A
import qualified Data.ByteString.Lazy as BL
import qualified Data.ByteString as B
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import Data.List (isSuffixOf, isPrefixOf)
import Data.IORef
import Network.HTTP.Types
import qualified Network.Wai as Wai
import Network.Wai.Internal (ResponseReceived(..))
import System.Directory (doesFileExist, canonicalizePath)
import System.FilePath (addTrailingPathSeparator)
import ECC.Logging
import ECC.Auth (randomToken)
import GHC.Clock (getMonotonicTimeNSec)
import ECC.Config
import ECC.Release (releaseContract)

transactionalApplication :: Store.Connection -> Wai.Middleware
transactionalApplication = transactionalApplicationWith writeLog

transactionalApplicationWith :: LogSink -> Store.Connection -> Wai.Middleware
transactionalApplicationWith sink cn application req respond =
        (do
            Store.prepareContext cn
            let readOnly = Wai.requestMethod req `elem` ["GET","HEAD","OPTIONS"]
                login = Wai.requestMethod req == "POST" && Wai.pathInfo req == ["api","auth","login"]
                -- Login counters are atomic upserts; bcrypt runs without a write transaction.
                transaction = if login then (\_ action -> action) else if readOnly then Store.withReadTransaction else Store.withTransaction
                clear = Store.clearContext cn (readOnly || login)
            result <- transaction cn $ do
              clear
              ref <- newIORef Nothing
              _ <- application req (\response -> writeIORef ref (Just response) >> pure ResponseReceived)
              clear
              readIORef ref
            case result of
              Just response -> respond response
              Nothing -> respond (jsonError status500 "Empty response"))
        `catch` \(e :: Store.SQLError) -> do
          let code = Store.sqlError e
              status | code == Store.ErrorConstraint = status409
                     | code == Store.ErrorMismatch = status400
                     | otherwise = status503
              message | status == status409 = "A matching record already exists"
                      | status == status400 = "Invalid record values or references"
                      | otherwise = "Database temporarily unavailable"
          logEvent sink (if statusCode status >= 500 then "ERROR" else "WARN") "database_error"
            (requestFields req ++ exceptionFields (toException e) ++ ["status" A..= statusCode status])
          respond (jsonError status message)

jsonError :: Status -> T.Text -> Wai.Response
jsonError status message = Wai.responseLBS status [("Content-Type","application/json")] (A.encode (A.object ["error" A..= message]))

requestMediaType :: Wai.Request -> Maybe B.ByteString
requestMediaType req = normalize <$> lookup hContentType (Wai.requestHeaders req)
 where
  space byte=byte==32 || byte==9
  normalize = B.map (\c -> if c>=65 && c<=90 then c+32 else c) . B.dropWhile space . B.dropWhileEnd space . B.takeWhile (/=59)

operational :: Config -> Wai.Middleware
operational = operationalWith writeLog

operationalWith :: LogSink -> Config -> Wai.Middleware
operationalWith sink cfg application original respond = do
  ident <- randomToken
  let req = original { Wai.requestHeaders = ("X-Request-ID",ident) : filter ((/= "X-Request-ID") . fst) (Wai.requestHeaders original) }
  started <- getMonotonicTimeNSec
  consumed <- newIORef (0::Int)
  let finish response = do
        ended <- getMonotonicTimeNSec
        let code = statusCode (Wai.responseStatus response)
            severity | code >= 500 = "ERROR"
                     | code >= 400 = "WARN"
                     | otherwise = "INFO"
        logEvent sink severity "request_completed" (requestFields req ++ ["status" A..= code,"durationMs" A..= (fromIntegral (ended-started)/1000000::Double)])
        let security = [("X-Request-ID",ident),("X-Content-Type-Options","nosniff"),("Referrer-Policy","no-referrer"),("X-Frame-Options","DENY"),("Cache-Control","no-store"),("Cross-Origin-Resource-Policy","same-origin"),("Cross-Origin-Opener-Policy","same-origin"),("Permissions-Policy","camera=(), microphone=(), geolocation=(), payment=(), usb=()"),("Content-Security-Policy","default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; connect-src 'self'; object-src 'none'; frame-ancestors 'none'; base-uri 'none'; form-action 'self'")]
            tls = if cfgProduction cfg then [("Strict-Transport-Security","max-age=31536000; includeSubDomains")] else []
            controlled = map fst (security ++ tls)
        respond (Wai.mapResponseHeaders (\headers -> security ++ tls ++ filter ((`notElem` controlled) . fst) headers) response)
      unsafe = Wai.requestMethod req `notElem` ["GET","HEAD","OPTIONS"]
      origin = lookup "Origin" (Wai.requestHeaders req)
      crossSite = lookup "Sec-Fetch-Site" (Wai.requestHeaders req) `elem` [Just "cross-site",Just "same-site"]
      canonical = either (const (cfgPublicUrl cfg)) id (normalizePublicUrl (cfgPublicUrl cfg))
      wrongContract = maybe False (/= TE.encodeUtf8 releaseContract) (lookup "X-ECC-Contract" (Wai.requestHeaders req))
      wrongOrigin = maybe False (/= TE.encodeUtf8 canonical) origin
      contract = lookup "X-ECC-Contract" (Wai.requestHeaders req)
      cookieAuth = any (\part -> any (`B.isPrefixOf` B.dropWhile (==32) part) ["ecc-session=","ecc-portal="]) (maybe [] (B.split 59) (lookup hCookie (Wai.requestHeaders req)))
      mediaType = requestMediaType req
      hasBody = case Wai.requestBodyLength req of Wai.KnownLength n -> n>0; Wai.ChunkedBody -> True
      apiRequest = case Wai.pathInfo req of "api":_ -> True; _ -> False
      bodyLimit = if mediaType==Just "multipart/form-data" then 27*1024*1024 else 1024*1024
      limitedRead = do
        chunk <- Wai.getRequestBodyChunk req
        total <- atomicModifyIORef' consumed (\n -> let count=n+fromIntegral (BL.length (BL.fromStrict chunk)) in (count,count))
        if total > bodyLimit then throwIO RequestBodyLimit else pure chunk
      tooLarge = case Wai.requestBodyLength req of Wai.KnownLength n -> n>fromIntegral bodyLimit; Wai.ChunkedBody -> False
  if unsafe && (crossSite || wrongOrigin) then finish (jsonError status403 "Forbidden origin")
  else if unsafe && wrongContract then finish (jsonError status426 "This page belongs to another application version. Copy any unsaved text, then reload before saving.")
  else if unsafe && cookieAuth && contract==Nothing then finish (jsonError status403 "Browser requests require the application request header")
  else if unsafe && apiRequest && hasBody && mediaType `notElem` [Just "application/json",Just "multipart/form-data"] then finish (jsonError status415 "Use application/json or multipart/form-data")
  else if tooLarge then finish (jsonError status413 "Request body too large")
  else if Wai.pathInfo req == ["api","health"] then finish (Wai.responseLBS status200 [("Content-Type","application/json")] "{\"status\":\"ok\"}")
  else catchSync (application (Wai.setRequestBodyChunks limitedRead req) finish) $ \e ->
    case fromException e :: Maybe RequestBodyLimit of
      Just _ -> finish (jsonError status413 "Request body too large")
      Nothing -> do
        logEvent sink "ERROR" "request_exception" (requestFields req ++ exceptionFields e ++ ["stage" A..= ("http_request" :: T.Text)])
        finish (Wai.responseLBS status500 [("Content-Type","application/json")]
          (A.encode (A.object ["error" A..= ("Unexpected server error. Reference: " <> requestId req),"requestId" A..= requestId req])))

data RequestBodyLimit = RequestBodyLimit deriving (Show)
instance Exception RequestBodyLimit

staticFiles :: FilePath -> Wai.Middleware
staticFiles root api req respond = case Wai.pathInfo req of
  ("api":_) -> api req respond
  segments -> do
    let safe = all (\segment -> not ("." `T.isPrefixOf` segment) && not (T.any (`elem` ['/', '\\', '\0']) segment)) segments
        rel = T.unpack (T.intercalate "/" segments)
        candidate = if null rel then root ++ "/index.html" else root ++ "/" ++ rel
    exists <- if safe then doesFileExist candidate else pure False
    canonicalRoot <- addTrailingPathSeparator <$> canonicalizePath root
    let selected = if exists then candidate else root ++ "/index.html"
    selectedExists <- doesFileExist selected
    contained <- if selectedExists then (canonicalRoot `isPrefixOf`) <$> canonicalizePath selected else pure False
    let asset = any (`isSuffixOf` rel) [".js",".css",".png",".svg",".ico",".webmanifest",".html"] || rel=="release.json"
    if not safe || not contained || (exists && not asset && not (null rel)) || (asset && not exists) then respond (jsonError status404 "Not found")
    else if Wai.requestMethod req `notElem` ["GET","HEAD"] then respond (Wai.responseLBS status405 [("Allow","GET, HEAD")] "") else do
      let fp = if exists then candidate else root ++ "/index.html"
          mime | ".webmanifest" `isSuffixOf` fp = "application/manifest+json"
               | ".css" `isSuffixOf` fp = "text/css; charset=utf-8"
               | ".js" `isSuffixOf` fp = "application/javascript"
               | ".svg" `isSuffixOf` fp = "image/svg+xml"
               | ".png" `isSuffixOf` fp = "image/png"
               | otherwise = "text/html; charset=utf-8"
      respond (Wai.responseFile status200 [("Content-Type",mime),("Cache-Control","no-cache")] fp Nothing)

-- No queue of slow body readers: uploads have their own bounded capacity.
-- Database/application capacity is acquired only after the body has arrived.
withPermit :: IORef Int -> IO a -> IO a -> IO a
withPermit permits busy action = bracket acquire release (\ok -> if ok then action else busy)
 where
 acquire = atomicModifyIORef' permits (\n -> if n>0 then (n-1,True) else (n,False))
 release ok = if ok then atomicModifyIORef' permits (\n -> (n+1,())) else pure ()

boundedBodies :: Int -> Int -> IO Wai.Middleware
boundedBodies slots deadlineMicros = do
 permits <- newIORef (max 1 slots)
 smallPermits <- newIORef (max 1 slots)
 pure $ \application req respond ->
  let hasBody = case Wai.requestBodyLength req of Wai.KnownLength n -> n>0; Wai.ChunkedBody -> True
      bulk = maybe False (\content -> "multipart/" `B.isPrefixOf` content) (lookup "Content-Type" (Wai.requestHeaders req)) || case Wai.requestBodyLength req of Wai.KnownLength n -> n>65536; Wai.ChunkedBody -> True
      busy = respond (Wai.responseLBS status503 [("Content-Type","application/json"),("Retry-After","1")] "{\"error\":\"Upload capacity busy. Try again shortly.\"}")
      readBody = do
       result <- timeout (if bulk then deadlineMicros else min deadlineMicros 3000000) (Wai.strictRequestBody req)
       case result of
        Nothing -> respond (jsonError status408 "Request body took too long")
        Just bytes | requestMediaType req==Just "application/json" && not (jsonNestingAllowed bytes) ->
          respond (jsonError status400 "JSON nesting exceeds the allowed depth")
        Just bytes -> do
         remaining <- newIORef (BL.toChunks bytes)
         application (Wai.setRequestBodyChunks (atomicModifyIORef' remaining (\chunks -> case chunks of [] -> ([],mempty); x:xs -> (xs,x))) req) respond
  in if hasBody then withPermit (if bulk then permits else smallPermits) busy readBody else application req respond

-- Bound parser stack/CPU costs while ignoring brackets inside escaped strings.
-- Syntax/type validation remains the responsibility of the endpoint decoder.
jsonNestingAllowed :: BL.ByteString -> Bool
jsonNestingAllowed bytes = let (_,_,_,allowed)=BL.foldl' step (0::Int,False,False,True) bytes in allowed
 where
  step state@(_,_,_,False) _ = state
  step (depth,True,True,ok) _ = (depth,True,False,ok)
  step (depth,True,False,ok) byte
   | byte==92 = (depth,True,True,ok)
   | byte==34 = (depth,False,False,ok)
   | otherwise = (depth,True,False,ok)
  step (depth,False,_,ok) byte
   | byte==34 = (depth,True,False,ok)
   | byte==91 || byte==123 = (depth+1,False,False,ok && depth<64)
   | byte==93 || byte==125 = (depth-1,False,False,ok && depth>0)
   | otherwise = (depth,False,False,ok)
