{-# LANGUAGE OverloadedStrings #-}
-- | Translate the application's shared SQL expressions to PostgreSQL. Parameters
-- remain separate libpq values; quoted strings are never rewritten.
module ECC.PostgresSQL (postgresSQL, postgresQuery) where

import qualified Data.Text as T
import Data.Char (isAlphaNum, isSpace)

data Token = Word T.Text | Quoted T.Text | Symbol T.Text | Group [Token]
  deriving (Eq, Show)

postgresSQL :: T.Text -> T.Text
postgresSQL input = numberParameters (render (rewrite (fst (tokens (T.unpack input)))))

postgresQuery :: T.Text -> [Bool] -> T.Text
postgresQuery input nulls = numberParameters (render (fst (replaceNulls nulls (rewrite (fst (tokens (T.unpack input)))))))
 where
 replaceNulls ns []=([],ns)
 replaceNulls (n:ns) (Symbol "?":rest)=let (more,end)=replaceNulls ns rest in ((if n then Word "NULL" else Symbol "?"):more,end)
 replaceNulls ns (Group xs:rest)=let (inside,next)=replaceNulls ns xs; (more,end)=replaceNulls next rest in (Group inside:more,end)
 replaceNulls ns (t:rest)=let (more,end)=replaceNulls ns rest in (t:more,end)

tokens :: String -> ([Token], String)
tokens [] = ([], [])
tokens (')':rest) = ([],rest)
tokens ('(':rest) = let (inside,after)=tokens rest; (more,end)=tokens after in (Group inside:more,end)
tokens ('-':'>':'>':rest) = let (more,end)=tokens rest in (Symbol "->>":more,end)
tokens (a:b:rest) | [a,b] `elem` ["::","<=",">=","!=","<>","||","<<",">>"] =
  let (more,end)=tokens rest in (Symbol(T.pack[a,b]):more,end)
tokens (q:rest) | q `elem` ['\'', '"'] =
  let (body,after)=quoted q rest; (more,end)=tokens after in (Quoted (T.pack(q:body)):more,end)
tokens input@(c:rest)
  | isSpace c = tokens rest
  | c>='0' && c<='9' = let (name,after)=span (\x -> isAlphaNum x || x=='.') input; (more,end)=tokens after in (Word(T.pack name):more,end)
  | isAlphaNum c || c=='_' = let (name,after)=span (\x -> isAlphaNum x || x=='_') input; (more,end)=tokens after in (Word(T.pack name):more,end)
  | otherwise = let (more,end)=tokens rest in (Symbol(T.singleton c):more,end)

quoted :: Char -> String -> (String,String)
quoted _ [] = ([],[])
quoted q (a:b:rest) | a==q && b==q = let (body,end)=quoted q rest in (a:b:body,end)
quoted q (a:rest) | a==q = ([a],rest)
quoted q (a:rest) = let (body,end)=quoted q rest in (a:body,end)

render :: [Token] -> T.Text
render = T.intercalate " " . map one
 where
 one (Word t)=t
 one (Quoted t)=t
 one (Symbol t)=t
 one (Group ts)="("<>render ts<>")"

rewrite :: [Token] -> [Token]
rewrite []=[]
rewrite (Word name:Group args:rest) =
 let key=T.toLower name
     inner=rewriteGroup args
     arguments=splitArgs inner
     call n xs=[Word n,Group xs]
     textArgs=joinArgs [[Group a]++[Symbol "::",Word "text"] | a<-arguments]
     result=case key of
       "json_object" -> call "jsonb_build_object" inner
       "json_group_array" -> call "ecc_json_group_array" inner
       "json_group_object" -> call "jsonb_object_agg" inner
       "json" -> [Group inner,Symbol "::",Word "jsonb"]
       "json_extract" -> case arguments of
         [value,[Quoted path]] ->
          let field=T.dropEnd 1(T.drop 3 path)
              extracted=[Group value,Symbol "::",Word "jsonb",Symbol "->>",Quoted("'"<>field<>"'")]
          in if field `elem` ["id"] then [Group extracted,Symbol "::",Word "bigint"] else extracted
         _ -> call name inner
       "json_each" -> call "ecc_json_each" textArgs
       "json_valid" -> call "ecc_json_valid" textArgs
       "json_type" -> call "jsonb_typeof" [Group inner,Symbol "::",Word "jsonb"]
       "datetime" -> call "ecc_datetime" textArgs
       "date" -> call "ecc_date" textArgs
       "strftime" -> call "ecc_strftime" textArgs
       "julianday" -> call "ecc_julianday" textArgs
       "printf" -> call "ecc_printf" textArgs
       "char" -> call "chr" inner
       "group_concat" -> call "string_agg" inner
       "coalesce" | [value,[Quoted "''"]]<-arguments -> call "coalesce" (joinArgs [[Group value]++[Symbol "::",Word "text"],[Quoted "''"]])
       "min" | length arguments>1 -> call "least" inner
       "max" | length arguments>1 -> call "greatest" inner
       _ -> call name inner
 in result++rewrite rest
rewrite (Word n:Symbol "?":rest) | T.toUpper n=="NOT" =
 [Group [Symbol "?",Symbol "=",Word "0"]]++rewrite rest
rewrite (Word between:Symbol "?":Word andWord:Symbol "?":rest)
 | T.toUpper between=="BETWEEN", T.toUpper andWord=="AND" =
 [Word between,Symbol "?",Word andWord,Symbol "?"]++rewrite rest
rewrite (Word clause:Symbol "?":rest)
 | T.toUpper clause `elem` ["WHERE","AND","OR","WHEN"], booleanTail rest =
 Word clause:Group [Symbol "?",Symbol "<>",Word "0"]:rewrite rest
rewrite (Word n:Symbol "?":rest) | T.toUpper n=="IS" =
 [Word "IS",Word "NOT",Word "DISTINCT",Word "FROM",Symbol "?"]++rewrite rest
rewrite (Word n:Word m:rest) | T.toUpper n=="IS", T.toUpper m=="NOT" =
 case rest of
   Word v:_ | T.toUpper v `elem` ["NULL","TRUE","FALSE","DISTINCT"] -> Word n:Word m:rewrite rest
   _ -> [Word "IS",Word "DISTINCT",Word "FROM"]++rewrite rest
rewrite (Word schema:Symbol ".":rest) | T.toLower schema `elem` ["main","temp"] = rewrite rest
rewrite (Word n:rest) | T.toUpper n=="LIKE" = Word "ILIKE":rewrite rest
rewrite (Group ts:rest)=Group(rewriteGroup ts):rewrite rest
rewrite (t:rest)=t:rewrite rest

booleanTail :: [Token] -> Bool
booleanTail []=True
booleanTail (Word op:_)=T.toUpper op `elem` ["OR","AND","THEN"]
booleanTail _=False

rewriteGroup :: [Token] -> [Token]
rewriteGroup (Symbol "?":rest) | not(null rest), booleanTail rest = Group [Symbol "?",Symbol "<>",Word "0"]:rewrite rest
rewriteGroup ts=rewrite ts

splitArgs :: [Token] -> [[Token]]
splitArgs []=[]
splitArgs ts=let (a,b)=break(==Symbol ",")ts in a:case b of []->[]; _:rest->splitArgs rest

joinArgs :: [[Token]] -> [Token]
joinArgs []=[]
joinArgs [a]=a
joinArgs (a:as)=a++[Symbol ","]++joinArgs as

numberParameters :: T.Text -> T.Text
numberParameters = T.pack . go 1 Nothing . T.unpack
 where
 go :: Int -> Maybe Char -> String -> String
 go _ _ []=[]
 go n (Just q) (a:b:rest) | a==q && b==q = a:b:go n (Just q) rest
 go n (Just q) (a:rest)=a:go n (if a==q then Nothing else Just q) rest
 go n Nothing (q:rest) | q `elem` ['\'', '"'] = q:go n (Just q) rest
 go n Nothing ('?':rest)='$':show n++go (n+1) Nothing rest
 go n Nothing (a:rest)=a:go n Nothing rest
