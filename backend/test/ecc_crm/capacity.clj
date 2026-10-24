(ns ecc-crm.capacity
  (:require [clojure.test :refer :all] [cheshire.core :as json]
            [ecc-crm.domain :as d] [ecc-crm.store :as store] [ecc-crm.backup :as backup] [ecc-crm.files :as files])
  (:import [java.nio.file Files] [java.nio.file.attribute FileAttribute]))
(defn measured [f] (let [start (System/nanoTime) result (f)] [result (/ (- (System/nanoTime) start) 1000000.0)]))
(defn -main [& _]
  (let [n (or (d/integer (System/getenv "ECC_CAPACITY_RECORDS")) 10000)
        directory (str (Files/createTempDirectory "ecc-capacity-" (make-array FileAttribute 0)))
        report (atom {:records n})]
    (when (< n 1000) (d/fail 400 "Capacity check requires at least 1000 records"))
    (with-redefs [files/directory (constantly (str directory "/blobs"))]
      (with-open [db (store/open-store (str directory "/source"))]
        (let [[_ seed-ms] (measured #(store/transact! db (fn [s]
                   [(assoc s :leads (into {} (for [id (range 1 (inc n))]
                                              [id {:id id :fullName (str "Capacity student " id) :leadNumber (str "L-" id) :stage "Qualified" :consultantId 1 :revision 1
                                                   :createdAt "2026-01-01T00:00:00Z" :updatedAt "2026-01-01T00:00:00Z"}])) :counters {:leads n}) nil])))
              [page page-ms] (measured #(d/list-records (store/snapshot db) {:id 1 :role "admin"} :leads {"offset" (str (- n 50)) "limit" "50"}))
              old (store/snapshot db) old-row (get-in old [:leads n])
              [_ update-ms] (measured #(store/transact! db (fn [s] (d/save-person s {:id 1 :role "admin"} :leads {:id n :fullName "Updated capacity student" :revision 1}))))
              _ (assert (= (:fullName old-row) (:fullName (get-in old [:leads n]))))
              _ (assert (= n (:total page))) _ (assert (= 50 (count (:rows page))))
              [archive backup-ms] (measured #(backup/write! db (str directory "/snapshot.zip")))]
          (swap! report merge {:seedMs seed-ms :pageMs page-ms :updateMs update-ms :backupMs backup-ms :backupBytes (.length (java.io.File. (:path archive)))})
          (with-open [restored (store/open-store (str directory "/restored"))]
            (let [[result restore-ms] (measured #(backup/restore! restored (:path archive)))
                  state (store/snapshot restored)]
              (assert (= n (:total (d/list-records state {:id 1 :role "admin"} :leads {"limit" "1"}))))
              (assert (= "Updated capacity student" (get-in state [:leads n :fullName])))
              (assert (nil? (:restoreProgress state)))
              (swap! report assoc :restoreMs restore-ms :roundTrip true :sha256 (:sha256 result)))))))
    (spit "/tmp/ecc-clojure-capacity.json" (json/generate-string @report {:pretty true}))
    (println (json/generate-string @report)) (shutdown-agents)))
