{-# LANGUAGE OverloadedStrings #-}
-- Deterministic property corpus: every case has a stable group/seed identifier.
-- No external generator dependency; inputs include boundary values deliberately.
module GeneratedTests (run) where

import Control.Exception (IOException, bracket, try)
import Control.Monad (forM_, unless, void, when)
import qualified Data.ByteString as B
import qualified Data.ByteString.Char8 as BC
import qualified Data.ByteString.Lazy as BL
import Data.Bits (shiftR)
import Data.List (nub)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import System.Directory (doesFileExist, getTemporaryDirectory, removeFile)
import System.FilePath ((</>))
import ECC.Auth
import ECC.Csv
import qualified ECC.DB as DB
import ECC.MFA (base32, unbase32)
import ECC.Migrations (runMigrations)
import ECC.Models (Client(..))
import ECC.ProfilePhotos (photoMime)
import ECC.Store

check :: String -> Int -> Bool -> IO ()
check group seed ok = do
  unless ok (fail ("Generated property failed: " ++ group ++ "/" ++ show seed))
  putStrLn ("PASS generated/" ++ group ++ "/" ++ show seed)

-- A stable mixed Unicode/control-character corpus with increasing input lengths.
sample :: Int -> T.Text
sample seed = T.pack (take (seed `mod` 97 + 1) (map pick (iterate step (toInteger seed + 1))))
  where
    alphabet = "abcXYZ019 ,\"\r\n\t=+-@'é中🙂"
    step n = (1664525*n + 1013904223) `mod` 4294967296
    pick n = alphabet !! fromInteger (n `mod` toInteger (length alphabet))

-- Independent model of spreadsheet neutralization; quoting is verified by parsing.
safeText :: T.Text -> T.Text
safeText input =
  let trimmed = T.stripEnd input
  in case T.uncons (T.dropWhile (`elem` [' ', '\t', '\r', '\n']) trimmed) of
    Just (c,_) | c `elem` ("=+-@" :: String) -> "'" <> trimmed
    _ -> trimmed

run :: IO ()
run = do
  forM_ [1..200] $ \seed -> do
    let raw = ["name-" <> T.pack (show seed), sample seed, sample (seed+211), "", "tail"]
        encoded = TE.decodeUtf8 (BL.toStrict (renderCsv [map cell raw]))
    check "csv-roundtrip" seed (parseCsv encoded == [map safeText raw])
  forM_ [1..100] $ \seed -> do
    let op = ("=+-@" :: String) !! (seed `mod` 4)
        raw = T.replicate (seed `mod` 5) " " <> T.singleton op <> sample seed
        encoded = TE.decodeUtf8 (BL.toStrict (renderCsv [[cell raw]]))
    check "formula-guard" seed (parseCsv encoded == [["'" <> T.stripEnd raw]])
  forM_ [1..100] $ \seed -> do
    let bytes = TE.encodeUtf8 (sample seed)
        different = bytes <> B.singleton (fromIntegral seed)
    check "constant-equality" seed
      (constTimeEq bytes bytes && not (constTimeEq bytes different)
       && not (constTimeEq different bytes) && not (constTimeEq bytes (B.reverse bytes <> "x")))
  forM_ [1..100] $ \seed -> do
    let bytes = B.pack (take seed (cycle [0..255]))
    check "base32-roundtrip" seed (unbase32 (base32 bytes) == bytes)
  let hashes = [tokenHash (TE.encodeUtf8 ("token-" <> T.pack (show seed))) | seed <- [1..100::Int]]
  forM_ (zip [1..100] hashes) $ \(seed,hashed) ->
    check "token-hash" seed (T.length hashed == 43 && T.all (`elem` (['A'..'Z']++['a'..'z']++['0'..'9']++"-_")) hashed
      && length (filter (==hashed) hashes) == 1 && length (nub hashes) == 100)
  forM_ [1..100] $ \seed -> do
    let secret = TE.encodeUtf8 ("generated-secret-" <> T.pack (show seed))
    token <- makeToken secret seed
    valid <- verifyToken secret token
    wrong <- verifyToken (secret <> "wrong") token
    tampered <- verifyToken secret (token <> "x")
    check "jwt-integrity" seed (valid == Just seed && wrong == Nothing && tampered == Nothing)
  forM_ [1..100] $ \seed -> do
    let dimensions = [0,1,2,255,256,4095,4096,4097,65535,4294967295] :: [Integer]
        w = dimensions !! ((seed-1) `mod` 10)
        h = dimensions !! ((seed-1) `div` 10)
        be n = B.pack [fromIntegral (shiftR n k) | k <- [24,16,8,0]]
        png = B.pack [137,80,78,71,13,10,26,10,0,0,0,13] <> "IHDR" <> be w <> be h
              <> B.replicate 9 0 <> B.pack [0,0,0,0,73,69,78,68,174,66,96,130]
        expected = if w>0 && w<=4096 && h>0 && h<=4096 then Just "image/png" else Nothing
    check "png-dimensions" seed (photoMime png == expected && photoMime (B.take 24 png) == Nothing)
  databaseProperties
  putStrLn "Generated properties: 1000/1000 passed (fixed reproducible corpus)"

databaseProperties :: IO ()
databaseProperties = do
  directory <- getTemporaryDirectory
  nonce <- randomToken
  let file = directory </> ("ecc-properties-" ++ BC.unpack nonce ++ ".sqlite3")
      cleanup conn = close conn >> mapM_ remove [file,file++"-wal",file++"-shm"]
      remove path = doesFileExist path >>= \exists -> when exists (removeFile path)
  bracket (openDatabase file) cleanup $ \conn -> do
    runMigrations conn "migrations"
    -- Check migration replay before exercising the generated database states.
    runMigrations conn "migrations"
    withTransaction conn $ forM_ [1..137::Int] $ \n -> void $ execute conn
      "INSERT INTO clients(client_number,full_name) VALUES (?,?)"
      ("PROP-" <> T.pack (show n), "Property Client " <> T.pack (show n))
    forM_ [1..100] $ \seed -> do
      let limit = seed `mod` 53 + 1
          offset = (seed*7) `mod` 160
          expected = take limit (drop offset [137,136..1])
      clients <- DB.listClientsPage conn limit offset ""
      check "pagination-model" seed (map clientId clients == expected)
    forM_ [1..100] $ \seed -> do
      before <- query_ conn "SELECT count(*) FROM clients" :: IO [Only Int]
      audits <- query_ conn "SELECT count(*) FROM audit_log" :: IO [Only Int]
      outcome <- try (withTransaction conn $ do
        void $ execute conn "INSERT INTO clients(client_number,full_name) VALUES (?,?)"
          ("ROLLBACK-" <> T.pack (show seed), sample seed)
        ioError (userError "injected transaction failure")) :: IO (Either IOException ())
      after <- query_ conn "SELECT count(*) FROM clients" :: IO [Only Int]
      auditsAfter <- query_ conn "SELECT count(*) FROM audit_log" :: IO [Only Int]
      check "rollback-atomicity" seed (either (const True) (const False) outcome && before == after && audits == auditsAfter)
