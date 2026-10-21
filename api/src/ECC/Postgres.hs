{-# LANGUAGE OverloadedStrings #-}
-- | PostgreSQL transport. Keep the existing field codecs so HTTP date/text and
-- integer representations remain identical across the two database backends.
module ECC.Postgres (open, close, run, script, decodeRow) where

import Control.Exception (throwIO)
import Control.Monad (forM, unless)
import Control.Monad.Trans.Reader (runReaderT)
import Control.Monad.Trans.State.Strict (runStateT)
import qualified Data.ByteString as B
import qualified Data.ByteString.Char8 as BC
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import qualified Database.PostgreSQL.LibPQ as P
import qualified Database.SQLite3 as D
import Database.SQLite.Simple.FromRow (FromRow(..))
import Database.SQLite.Simple.Internal (unRP, RowParseRO(..))
import Database.SQLite.Simple.Ok (Ok(..))
import Data.Int (Int64)
import Text.Read (readMaybe)
import ECC.PostgresSQL (postgresQuery)
import ECC.Config (normalizeDatabaseUrl)

open :: T.Text -> IO P.Connection
open url = do
 secured<-either (fail . T.unpack) pure(normalizeDatabaseUrl False url)
 cn<-P.connectdb(TE.encodeUtf8 secured)
 state<-P.status cn
 unless (state==P.ConnectionOk) $ P.finish cn >> fail "Cannot connect to PostgreSQL; check DATABASE_URL and network access"
 _<-script cn "SET TIME ZONE 'UTC'; SET statement_timeout='60s'; SET lock_timeout='10s'; SET client_encoding='UTF8'"
 pure cn

close :: P.Connection -> IO ()
close=P.finish

script :: P.Connection -> T.Text -> IO ()
script cn sql = P.exec cn (TE.encodeUtf8 sql) >>= checked >> pure ()

run :: P.Connection -> T.Text -> [D.SQLData] -> IO (Int64,[[D.SQLData]])
run cn sql params=do
 result<-P.execParams cn (TE.encodeUtf8(postgresQuery sql (map (==D.SQLNull) params))) (map parameter (filter (/=D.SQLNull) params)) P.Text >>= checked
 count<-maybe 0 (maybe 0 id . readMaybe . BC.unpack) <$> P.cmdTuples result
 nr<-P.ntuples result
 nc<-P.nfields result
 rows<-forM [0..nr-1] $ \r -> forM [0..nc-1] $ \c -> do
  oid<-P.ftype result c
  value<-P.getvalue result r c
  case value of
   Nothing->pure D.SQLNull
   Just bytes
    | oid==P.Oid 17 -> do
       decoded<-P.unescapeBytea bytes
       maybe (fail "Invalid PostgreSQL binary field") (pure . D.SQLBlob) decoded
    | oid==P.Oid 16 -> pure(D.SQLInteger(if bytes=="t" then 1 else 0))
    | oid `elem` map P.Oid [20,21,23] -> maybe (fail "Invalid PostgreSQL integer") (pure . D.SQLInteger) (readMaybe(BC.unpack bytes))
    | oid `elem` map P.Oid [700,701,1700] ->
       case readMaybe(BC.unpack bytes) of
        Just n -> pure(D.SQLInteger n)
        Nothing -> maybe (fail "Invalid PostgreSQL number") (pure . D.SQLFloat) (readMaybe(BC.unpack bytes))
    | otherwise -> pure(D.SQLText(TE.decodeUtf8 bytes))
 pure(count,rows)

parameter :: D.SQLData -> Maybe (P.Oid,B.ByteString,P.Format)
parameter D.SQLNull=Nothing
parameter (D.SQLInteger n)=Just(P.Oid 20,BC.pack(show n),P.Text)
parameter (D.SQLFloat n)=Just(P.Oid 701,BC.pack(show n),P.Text)
parameter (D.SQLText t)=Just(P.Oid 25,TE.encodeUtf8 t,P.Text)
parameter (D.SQLBlob b)=Just(P.Oid 17,b,P.Binary)

checked :: Maybe P.Result -> IO P.Result
checked Nothing=throwIO(D.SQLError D.ErrorCan'tOpen "PostgreSQL connection unavailable" "PostgreSQL")
checked (Just result)=do
 state<-P.resultStatus result
 if state `elem` [P.CommandOk,P.TuplesOk, P.EmptyQuery] then pure result else do
  code<-maybe "08000" id <$> P.resultErrorField result P.DiagSqlstate
  -- Do not expose server messages: they can contain record data or credentials.
  let kind | "23" `B.isPrefixOf` code=D.ErrorConstraint
           | "22" `B.isPrefixOf` code=D.ErrorMismatch
           | otherwise=D.ErrorError
  throwIO(D.SQLError kind ("PostgreSQL SQLSTATE "<>TE.decodeUtf8 code) "PostgreSQL")

decodeRow :: FromRow a => [D.SQLData] -> IO a
decodeRow fields=case runStateT (runReaderT (unRP fromRow) (RowParseRO(length fields))) (0,fields) of
 Ok (value,(used,_)) | used==length fields -> pure value
 Ok _ -> fail "PostgreSQL row has an unexpected field count"
 Errors (err:_) -> throwIO err
 Errors [] -> fail "Cannot decode PostgreSQL row"
