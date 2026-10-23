{-# LANGUAGE OverloadedStrings #-}
module ConfigTests (run) where

import Control.Exception (bracket, try)
import Control.Monad (forM_, unless)
import System.Environment (lookupEnv, setEnv, unsetEnv)
import ECC.Config

withEnvironment :: [(String, Maybe String)] -> IO a -> IO a
withEnvironment values action = bracket
  (mapM (\(key, _) -> do value <- lookupEnv key; pure (key, value)) values)
  (mapM_ apply)
  (\_ -> mapM_ apply values >> action)
 where
  apply (key, Nothing) = unsetEnv key
  apply (key, Just value) = setEnv key value

run :: IO ()
run = withEnvironment baseline $ do
  good <- loadConfig
  unless (cfgProduction good) (fail "Valid production configuration loads")
  unless (cfgDatabase good == "/tmp/ecc-config-test.sqlite3")
    (fail "DATABASE_PATH selects the SQLite database")
  forM_ ["postgresql://user@localhost/ecc", "postgres://user@localhost/ecc"] $ \url ->
    withEnvironment [("DATABASE_URL", Just url)] $ do
      postgres <- loadConfig
      unless (cfgDatabase postgres == url ++ "?sslmode=require")
        (fail "PostgreSQL URL takes precedence over SQLite path and defaults to TLS")
  withEnvironment [("APP_ENV", Just "development"), ("DATABASE_PATH", Nothing)] $ do
    defaults <- loadConfig
    unless (cfgDatabase defaults == "ecc-crm.sqlite3")
      (fail "Development defaults to SQLite when neither database setting is present")
  withEnvironment [("APP_ENV", Just "development"), ("DATABASE_URL", Just "postgresql://user@localhost/ecc?sslmode=disable")] $ do
    localPostgres <- loadConfig
    unless (cfgDatabase localPostgres == "postgresql://user@localhost/ecc?sslmode=disable")
      (fail "Development supports PostgreSQL without TLS when explicitly configured")
  forM_ cases $ \(key, value, expected) -> withEnvironment [(key, value)] $ do
    result <- try loadConfig :: IO (Either ConfigurationError Config)
    unless (case result of Left actual -> actual == expected; Right _ -> False)
      (fail ("Configuration identifies invalid setting " ++ key ++ " as " ++ show expected))
  putStrLn "Configuration diagnostics regression checks passed"
 where
  baseline =
    [("APP_ENV", Just "production"), ("PORT", Just "4000"), ("DB_POOL_SIZE", Just "2")
    ,("DATABASE_URL", Nothing), ("DATABASE_PATH", Just "/tmp/ecc-config-test.sqlite3")
    ,("JWT_SECRET", Just "isolated-configuration-secret-1234567890")
    ,("SEED_DEMO", Just "false"), ("PUBLIC_URL", Just "https://crm.example")]
  cases =
    [("PORT", Just "invalid", InvalidPort), ("DB_POOL_SIZE", Just "0", InvalidPoolSize)
    ,("DATABASE_URL", Just "invalid-private-database-value", InvalidDatabaseUrl)
    ,("DATABASE_URL", Just "postgresql://user:private-password@db.example/ecc?sslmode=disable", InvalidDatabaseTls)
    ,("DATABASE_PATH", Nothing, MissingProductionDatabase)
    ,("JWT_SECRET", Nothing, InvalidJwtSecret), ("JWT_SECRET", Just "private-short-key", InvalidJwtSecret)
    ,("JWT_SECRET", Just "local-development-secret-only-0000", InvalidJwtSecret)
    ,("SEED_DEMO", Just "true", DemoSeedingEnabled)
    ,("PUBLIC_URL", Just "https://user:private-password@crm.example/path", InvalidPublicUrl)
    ,("PUBLIC_URL", Just "http://crm.example", HttpsPublicUrlRequired)]
