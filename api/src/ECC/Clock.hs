{-# LANGUAGE OverloadedStrings #-}
module ECC.Clock (businessZone, businessDay, dayInZone, clockPayload, zoneModifier) where

import qualified Data.Aeson as A
import Data.Aeson ((.=))
import qualified Data.Text as T
import Data.Time
import Data.Time.Clock.POSIX (utcTimeToPOSIXSeconds)
import System.Environment (lookupEnv)

-- The supported business zones have fixed offsets, including no DST in Manila.
-- Never use the host machine's local zone for financial/calendar boundaries.
businessZone :: IO TimeZone
businessZone = do
  name <- lookupEnv "CRM_TIMEZONE"
  case name of
    Nothing -> pure (TimeZone 480 False "Asia/Manila")
    Just "Asia/Manila" -> pure (TimeZone 480 False "Asia/Manila")
    Just "UTC" -> pure utc
    _ -> fail "CRM_TIMEZONE must be Asia/Manila or UTC"

dayInZone :: TimeZone -> UTCTime -> Day
dayInZone zone = localDay . utcToLocalTime zone

businessDay :: IO Day
businessDay = dayInZone <$> businessZone <*> getCurrentTime

zoneModifier :: TimeZone -> T.Text
zoneModifier zone = T.pack (show (timeZoneMinutes zone)) <> " minutes"

clockPayload :: TimeZone -> UTCTime -> A.Value
clockPayload zone now = A.object
  [ "unixMillis" .= (floor (utcTimeToPOSIXSeconds now * 1000) :: Integer)
  , "utc" .= formatTime defaultTimeLocale "%Y-%m-%dT%H:%M:%S%QZ" now
  , "date" .= show (dayInZone zone now)
  , "timezone" .= timeZoneName zone
  , "offsetMinutes" .= timeZoneMinutes zone
  ]
