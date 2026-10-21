{-# LANGUAGE OverloadedStrings #-}
module ECC.MFA where
import qualified Data.ByteString as B
import qualified Data.ByteString.Char8 as BC
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import Data.Bits
import Data.List (elemIndex)
import Data.Maybe (mapMaybe)
import Data.Time.Clock.POSIX (getPOSIXTime)
import System.IO
import ECC.Auth (hmacSha256,tokenHash,constTimeEq)
import ECC.Store
import ECC.DB (Env(..))

alphabet :: String
alphabet="ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
bits :: Int -> Int -> [Bool]
bits count value=[testBit value i | i<-[count-1,count-2..0]]
chunks :: Int -> [a] -> [[a]]
chunks _ []=[]
chunks n xs=take n xs:chunks n (drop n xs)
fromBits :: [Bool] -> Int
fromBits=foldl (\n b -> n*2+if b then 1 else 0) 0
base32 :: B.ByteString -> T.Text
base32 bytes=T.pack [alphabet !! fromBits (take 5 (chunk++repeat False)) | chunk<-chunks 5 (concatMap (bits 8 . fromIntegral) (B.unpack bytes))]
unbase32 :: T.Text -> B.ByteString
unbase32 text=B.pack [fromIntegral (fromBits chunk) | chunk<-chunks 8 (concatMap (bits 5) (mapMaybe (`elemIndex` alphabet) (T.unpack text))),length chunk==8]
newSecret :: IO T.Text
newSecret=base32 <$> withBinaryFile "/dev/urandom" ReadMode (\handle -> B.hGet handle 32)
-- RFC 6238, SHA-256; test vectors cover both six and eight digit outputs.
totp :: B.ByteString -> Integer -> Int -> T.Text
totp secret step digits =
 let counter=B.pack [fromIntegral (shiftR step i .&. 255) | i<-[56,48..0]]
     digest=hmacSha256 secret counter
     offset=fromIntegral (B.last digest .&. 15)
     value=B.foldl' (\n byte -> n*256+fromIntegral byte) (0::Integer) (B.take 4 (B.drop offset digest)) .&. 0x7fffffff
 in T.justifyRight digits '0' (T.pack (show (value `mod` (10^digits))))
verifyMfa :: Env -> Int -> T.Text -> IO Bool
verifyMfa env uid code = do
 rows<-query (envConn env) "SELECT mfa_secret,mfa_last_step FROM users WHERE id=? AND suspended=0" (Only uid) :: IO [(Maybe T.Text,Integer)]
 case rows of
  [(Nothing,_)] -> pure True
  [(Just secret,lastStep)] -> do
   now<-floor . (/30) <$> getPOSIXTime
   let matches=[step | step<-[now-1,now,now+1],step>lastStep,sameCode (totp (unbase32 secret) step 6) code]
   case matches of
    step:_ -> (>0) <$> execute (envConn env) "UPDATE users SET mfa_last_step=? WHERE id=? AND mfa_last_step<? AND mfa_secret=? AND suspended=0" (step,uid,step,secret)
    [] -> (>0) <$> execute (envConn env) "DELETE FROM mfa_recovery_codes WHERE user_id=? AND code_hash=?" (uid,tokenHash (TE.encodeUtf8 code))
  _ -> pure False

sameCode :: T.Text -> T.Text -> Bool
sameCode a b=constTimeEq (TE.encodeUtf8 a) (TE.encodeUtf8 b)
