{-# LANGUAGE OverloadedStrings #-}
module ClockTests (run) where

import Control.Exception (bracket, finally, try)
import Control.Monad (unless, void)
import qualified Data.Text as T
import Data.Time
import Data.Int (Int64)
import System.Environment (lookupEnv, setEnv, unsetEnv)
import ECC.Clock
import ECC.Migrations (runMigrations)
import ECC.Store

run :: IO ()
run = do
  previous <- lookupEnv "CRM_TIMEZONE"
  let restore = maybe (unsetEnv "CRM_TIMEZONE") (setEnv "CRM_TIMEZONE") previous
  (do
    setEnv "CRM_TIMEZONE" "Asia/Manila"
    zone <- businessZone
    let assert label value = unless value (fail label)
        instant text = read text :: UTCTime
    assert "Manila date advances at UTC 16:00" (show (dayInZone zone (instant "2026-10-19 16:00:00 UTC")) == "2026-10-20")
    assert "Manila date before midnight" (show (dayInZone zone (instant "2026-10-19 15:59:59 UTC")) == "2026-10-19")
    assert "Business year boundary" (show (dayInZone zone (instant "2026-12-31 16:00:00 UTC")) == "2027-01-01")
    assert "Leap day boundary" (show (dayInZone zone (instant "2028-02-28 16:00:00 UTC")) == "2028-02-29")
    bracket (openDatabase ":memory:") close $ \conn -> do
      runMigrations conn "migrations"
      dates <- query_ conn "SELECT date('2026-10-19 15:59:59',business_offset()),date('2026-10-19 16:00:00',business_offset())" :: IO [(T.Text,T.Text)]
      assert "SQLite and Haskell share business midnight" (dates == [("2026-10-19","2026-10-20")])
      void $ execute_ conn "INSERT INTO users(email,password_hash,name,role) VALUES ('clock@test.local','unused-test-hash','Clock test','admin')"
      void $ execute_ conn "INSERT INTO clients(client_number,full_name) VALUES ('CLOCK-1','Clock test')"
      void $ execute_ conn "INSERT INTO invoices(client_id,description,currency,amount_minor,due_date,status,issued_at) VALUES (1,'Boundary invoice','PHP',1000,'2020-02-01','Issued','2020-01-31 16:30:00')"
      void $ execute_ conn "INSERT INTO financial_periods(month,closed,reason,changed_by,changed_name) VALUES ('2020-02',1,'Reviewed',1,'Clock test')"
      edit <- try (execute_ conn "UPDATE invoices SET description='Changed' WHERE id=1") :: IO (Either SQLError Int64)
      assert "Invoice lock uses its business issue month" (case edit of Left _ -> True; _ -> False)
      today <- businessDay
      void $ execute conn "INSERT INTO invoice_payments(invoice_id,amount_minor,paid_on,method,actor_id,actor_name) VALUES (1,100,?,'Cash',1,'Clock test')" (Only today)
      future <- try (execute conn "INSERT INTO invoice_payments(invoice_id,amount_minor,paid_on,method,actor_id,actor_name) VALUES (1,100,?,'Cash',1,'Clock test')" (Only (addDays 1 today))) :: IO (Either SQLError Int64)
      assert "Database rejects tomorrow using business date" (case future of Left _ -> True; _ -> False)
    setEnv "CRM_TIMEZONE" "UTC"
    utcZone <- businessZone
    assert "UTC can be configured explicitly" (dayInZone utcZone (instant "2026-10-19 16:00:00 UTC") == fromGregorian 2026 10 19)
    setEnv "CRM_TIMEZONE" "invalid-zone"
    invalid <- try businessZone :: IO (Either IOError TimeZone)
    assert "Invalid business zone fails explicitly" (case invalid of Left _ -> True; _ -> False)
    putStrLn "Business clock, midnight, year/leap boundaries and financial dates passed"
   ) `finally` restore
