{-# LANGUAGE OverloadedStrings #-}
module ECC.Config (Config(..), loadConfig, normalizePublicUrl, normalizeDatabaseUrl) where
import Data.ByteString (ByteString)
import qualified Data.ByteString as B
import Data.Text.Encoding (encodeUtf8)
import qualified Data.Text as T
import System.Environment (lookupEnv)
import Text.Read (readMaybe)
import Network.URI (parseURI, URI(..), URIAuth(..), unEscapeString)

data Config = Config
  { cfgPort :: Int, cfgDatabase :: FilePath, cfgJwtSecret :: ByteString
  , cfgSeedDemo :: Bool, cfgProduction :: Bool, cfgPoolSize :: Int
  , cfgPublicUrl :: T.Text, cfgAssignedOnly :: Bool }
loadConfig :: IO Config
loadConfig = do
  prod <- (== Just "production") <$> lookupEnv "APP_ENV"
  port <- number "PORT" 4000 1 65535
  pool <- number "DB_POOL_SIZE" 2 1 16
  url <- lookupEnv "DATABASE_URL"
  local <- lookupEnv "DATABASE_PATH"
  db <- case url of
    Just value -> Just . T.unpack <$> either (fail . T.unpack) pure (normalizeDatabaseUrl prod (T.pack value))
    Nothing -> pure local
  secret <- lookupEnv "JWT_SECRET"
  seed <- (== Just "true") <$> lookupEnv "SEED_DEMO"
  assigned <- (== Just "true") <$> lookupEnv "ASSIGNED_ONLY"
  rawPublic <- maybe "http://localhost:4000" T.pack <$> lookupEnv "PUBLIC_URL"
  public <- either (fail . T.unpack) pure (normalizePublicUrl rawPublic)
  let key = encodeUtf8 (maybe "local-development-secret-only-0000" T.pack secret)
  if prod && (maybe True null db || B.length key < 32 || secret == Nothing || key == "local-development-secret-only-0000" || db == Just ":memory:" || seed || not ("https://" `T.isPrefixOf` public))
    then fail "Production requires DATABASE_URL (PostgreSQL) or DATABASE_PATH (SQLite), JWT_SECRET (32+ bytes), PUBLIC_URL=https://..., and SEED_DEMO disabled"
    else pure (Config port (maybe "ecc-crm.sqlite3" id db) key seed prod pool public assigned)
  where
    number name fallback lo hi = do
      value <- lookupEnv name
      case maybe (Just fallback) readMaybe value of
        Just n | n >= lo && n <= hi -> pure n
        _ -> fail (name ++ " is outside the allowed range")

-- The frontend is served at the origin root; URL prefixes are unsupported.
normalizePublicUrl :: T.Text -> Either T.Text T.Text
normalizePublicUrl raw = case parseURI (T.unpack (T.strip raw)) of
 Just uri | mapLower (uriScheme uri) `elem` ["http:","https:"], uriPath uri `elem` ["","/"], null (uriQuery uri), null (uriFragment uri), Just auth <- uriAuthority uri, null (uriUserInfo auth), not (null (uriRegName auth)) -> do
  let scheme=mapLower (uriScheme uri)
      port=uriPort auth
  normalizedPort <- case port of
   "" -> Right ""
   ':':digits | Just n <- (readMaybe digits :: Maybe Int), n>=1, n<=65535 ->
    Right (if scheme=="https:" && n==443 || scheme=="http:" && n==80 then "" else ":"++show n)
   _ -> Left "PUBLIC_URL contains an invalid port"
  pure (T.pack (scheme++"//"++mapLower (uriRegName auth)++normalizedPort))
 _ -> Left "PUBLIC_URL must be an http(s) origin, without credentials, path, query or fragment"
 where mapLower = T.unpack . T.toLower . T.pack

-- Always request TLS explicitly, including Render's private network. Development
-- tests may opt out for a local disposable server; production cannot.
normalizeDatabaseUrl :: Bool -> T.Text -> Either T.Text T.Text
normalizeDatabaseUrl production raw = case parseURI (T.unpack raw) of
 Just uri | uriScheme uri `elem` ["postgresql:","postgres:"], Just auth<-uriAuthority uri,
            not(null(uriRegName auth)), not(null(uriPath uri)), null(uriFragment uri) -> do
  let options=map (\part -> let (key,value)=T.breakOn "=" part in (unEscapeString(T.unpack key),unEscapeString(T.unpack(T.drop 1 value)))) (T.splitOn "&" (T.pack(drop 1(uriQuery uri))))
      modes=[value | (key,value)<-options,key=="sslmode"]
      secure=["require","verify-ca","verify-full"]
  case modes of
   [] -> Right (raw <> (if null(uriQuery uri) then "?" else "&") <> "sslmode=require")
   [mode] | mode `elem` secure || not production && mode `elem` ["disable","allow","prefer"] -> Right raw
   _ -> Left "DATABASE_URL must require TLS in production (sslmode=require, verify-ca or verify-full)"
 _ -> Left "DATABASE_URL must be a PostgreSQL connection URL"
