(ns ecc-crm.monitor
  (:refer-clojure :exclude [run!])
  (:require [clojure.string :as str] [clojure.java.io :as io] [ecc-crm.domain :as d] [ecc-crm.store :as store])
  (:import [java.time Instant Duration]))
(defn age [path]
  (try (- (.getEpochSecond (Instant/now)) (Long/parseLong (clojure.string/trim (slurp path)))) (catch Exception _ Long/MAX_VALUE)))
(defn check [s]
  (let [maximum (or (d/integer (System/getenv "MAX_BACKUP_AGE_SECONDS")) 7200)
        data (io/file (or (System/getenv "XTDB_DIR") "data/xtdb"))
        failed-mail (count (filter #(= "Failed" (:status %)) (d/rows s :mail)))
        delayed (count (filter #(and (contains? #{"Queued" "Sending"} (:status %)) (:createdAt %)
                                     (> (.getSeconds (Duration/between (Instant/parse (:createdAt %)) (Instant/now))) 1800)) (d/rows s :mail)))
        alerts (cond-> []
                 (< (.getUsableSpace data) (* 1024 1024 1024)) (conj "Disk space below 1 GB")
                 (pos? failed-mail) (conj "Mail delivery failures")
                 (pos? delayed) (conj "Mail queue delayed")
                 (and (= "true" (System/getenv "REQUIRE_BACKUP")) (> (age (or (System/getenv "LOCAL_BACKUP_STATUS_FILE") "/backup-status/local-success")) maximum)) (conj "Local backup is stale")
                 (and (= "true" (System/getenv "REQUIRE_OFFHOST_BACKUP")) (> (age (or (System/getenv "OFFHOST_BACKUP_STATUS_FILE") "/backup-status/offhost-success")) maximum)) (conj "Off-host backup is stale"))]
    {:checkedAt (d/now) :alerts alerts :failedMail failed-mail :delayedMail delayed :diskFreeBytes (.getUsableSpace data)}))
(defn run! [db]
  (store/transact! db (fn [s]
    (let [status (check s) old (:operations s) changed? (not= (:alerts old) (:alerts status))
          repeat? (or (nil? (:lastAlertAt old)) (> (.getSeconds (Duration/between (Instant/parse (:lastAlertAt old)) (Instant/now))) 3600))
          recipient (System/getenv "ALERT_TO") send? (and (seq recipient) (or changed? (and (seq (:alerts status)) repeat?)))
          [s _] (if send? (d/insert s :mail {:to recipient :subject (if (seq (:alerts status)) "ECC workspace operational alert" "ECC workspace recovered")
                                           :body (clojure.string/join "\n" (:alerts status)) :status "Queued" :attempts 0}) [s nil])]
      [(assoc s :operations (cond-> (merge old status) send? (assoc :lastAlertAt (d/now)))) status]))))
