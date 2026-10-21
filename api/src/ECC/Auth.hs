{-# LANGUAGE OverloadedStrings #-}

-- | Minimal HS256 JSON Web Tokens (sign \/ verify), bcrypt password hashing
-- helpers and bearer-token extraction.
--
-- Only @sub@ and @exp@ claims are used; enough for this API without pulling
-- in a full JWT framework.
module ECC.Auth
  ( constTimeEq
  , hmacSha256
  , makeToken
  , verifyToken
  , bearerToken
  , hashPassword
  , randomToken
  , tokenHash
  , checkPassword
  , checkLoginPassword
  ) where

import Control.Monad (guard)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import Crypto.Hash.SHA256 (hash)
import Data.Aeson (ToJSON (..), FromJSON (..), object, withObject, encode,
                   decode', (.=), (.:))
import Data.Bits (xor)
import System.IO (withBinaryFile, IOMode(ReadMode))
import qualified Crypto.BCrypt as Bcrypt
import Data.ByteString (ByteString)
import qualified Data.ByteString as B
import qualified Data.ByteString.Base64.URL as B64
import qualified Data.ByteString.Char8 as BC
import qualified Data.ByteString.Lazy as BL
import Data.Time.Clock.POSIX (getPOSIXTime)
import Network.HTTP.Types.Header (HeaderName, hAuthorization)

b64url :: ByteString -> ByteString
b64url = B.filter (/= 61 {- '=' -}) . B64.encode

unb64url :: ByteString -> ByteString
unb64url t = B64.decodeLenient padded
  where
    r = B.length t `mod` 4
    padding = BC.replicate (if r == 0 then 0 else 4 - r) '='
    padded = B.append t padding

signPayload :: ByteString -> ByteString -> ByteString
signPayload secret payload = b64url (hmacSha256 secret payload)

-- | HMAC-SHA256 (RFC 2104) built directly on the raw SHA-256 primitive.
hmacSha256 :: ByteString -> ByteString -> ByteString
hmacSha256 key msg = hash (B.append opad (hash (B.append ipad msg)))
  where
    k = if B.length key > blockSize then hash key else key
    kPadded = B.append k (B.replicate (blockSize - B.length k) 0)
    ipad = B.map (xor 0x36) kPadded
    opad = B.map (xor 0x5c) kPadded
    blockSize = 64

data Claims = Claims { cSub :: Int, cExp :: Int, cNonce :: ByteString }

instance ToJSON Claims where
  toJSON c = object [("sub" .= cSub c), ("exp" .= cExp c), ("jti" .= BC.unpack (cNonce c))]

instance FromJSON Claims where
  parseJSON = withObject "Claims" $ \o ->
    Claims <$> o .: "sub" <*> o .: "exp" <*> (BC.pack <$> o .: "jti")

-- | Mint a unique token valid for eight hours for the given user id.
makeToken :: ByteString -> Int -> IO ByteString
makeToken secret uid = do
  now <- floor <$> getPOSIXTime :: IO Int
  nonce <- randomToken
  let headerP = b64url "{\"alg\":\"HS256\",\"typ\":\"JWT\"}"
      claimsP = b64url (BL.toStrict (encode (Claims uid (now + 8 * 3600) nonce)))
      payload = B.concat [headerP, ".", claimsP]
  pure (B.concat [payload, ".", signPayload secret payload])

-- | Check signature + expiry; return the subject user id on success.
verifyToken :: ByteString -> ByteString -> IO (Maybe Int)
verifyToken secret tok = do
  now <- floor <$> getPOSIXTime :: IO Int
  pure $ if B.length tok>4096 then Nothing else case BC.split '.' tok of
    [h, p, s] | not (B.null h), not (B.null p) -> check now h p s
    _ -> Nothing
  where
    check now h p s = do
      guard (h==b64url "{\"alg\":\"HS256\",\"typ\":\"JWT\"}")
      guard (all canonicalPart [h,p,s])
      let payload = B.concat [h, ".", p]
      guard (constTimeEq (signPayload secret payload) s)
      claims <- decode' (BL.fromStrict (unb64url p)) :: Maybe Claims
      guard (cExp claims > now)
      guard (cSub claims>0 && B.length (cNonce claims)==43 && canonicalPart (cNonce claims))
      pure (cSub claims)
    canonicalPart value = not (B.null value) && B.all (\c -> c>=65 && c<=90 || c>=97 && c<=122 || c>=48 && c<=57 || c==45 || c==95) value && b64url (unb64url value)==value

constTimeEq :: ByteString -> ByteString -> Bool
constTimeEq a b = B.length a == B.length b && B.foldl' (\acc byte -> acc + fromIntegral byte) (0 :: Int) (B.pack (B.zipWith xor a b)) == 0

-- | Extract the raw JWT from an @Authorization: Bearer …@ header list.
bearerToken :: [(HeaderName, ByteString)] -> Maybe ByteString
bearerToken hdrs = lookup hAuthorization hdrs >>= B.stripPrefix "Bearer "

-- | Hash with bcrypt (cost 10).
hashPassword :: ByteString -> IO ByteString
hashPassword pw = do
    if B.null pw || B.length pw>72 || B.elem 0 pw then fail "Password must use 1–72 bytes without NUL characters" else pure ()
    mh <- Bcrypt.hashPasswordUsingPolicy policy pw
    maybe (fail "Password hashing failed") pure mh
  where
    policy = Bcrypt.HashingPolicy { Bcrypt.preferredHashCost = 10
                                  , Bcrypt.preferredHashAlgorithm = "$2a$"
                                  }

-- | Arguments: password attempt, then the stored hash.
checkPassword :: ByteString -> ByteString -> Bool
checkPassword pw h = not (B.null pw) && B.length pw<=72 && not (B.elem 0 pw) && Bcrypt.validatePassword h pw

-- Unknown accounts still perform a bcrypt check so the password endpoint does
-- not expose account existence simply by skipping the expensive hash work.
checkLoginPassword :: ByteString -> Maybe ByteString -> Bool
checkLoginPassword pw stored =
  let dummy = "$2a$10$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy"
      matched = checkPassword pw (maybe dummy id stored)
  in matched `seq` maybe False (const matched) stored

randomToken :: IO ByteString
randomToken = b64url <$> withBinaryFile "/dev/urandom" ReadMode (\h -> B.hGet h 32)

tokenHash :: ByteString -> T.Text
tokenHash = TE.decodeUtf8 . b64url . hash
