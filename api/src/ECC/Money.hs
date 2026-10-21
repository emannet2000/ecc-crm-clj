{-# LANGUAGE OverloadedStrings #-}
module ECC.Money (amountMinor) where
import qualified Data.Text as T
import Text.Read (readMaybe)

amountMinor :: T.Text -> Maybe Int
amountMinor text = do
 let parts=T.splitOn "." text
     digits t=not(T.null t) && T.all (\c -> c>='0' && c<='9') t
 (whole,fraction)<-case parts of
  [a] | digits a -> Just(a,"00")
  [a,b] | digits a && digits b && T.length b<=2 -> Just(a,T.justifyLeft 2 '0' b)
  _ -> Nothing
 a<-readMaybe(T.unpack whole) :: Maybe Integer
 b<-readMaybe(T.unpack fraction) :: Maybe Integer
 let value=a*100+b
 if value>0 && value<=100000000000 then Just(fromInteger value) else Nothing

