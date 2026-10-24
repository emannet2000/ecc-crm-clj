(ns ecc-crm.postgres-check
  (:require [ecc-crm.postgres-export :as pg] [ecc-crm.migration :as migration]
            [ecc-crm.store :as store] [ecc-crm.domain :as d] [ecc-crm.files :as files] [ecc-crm.backup :as backup])
  (:import [java.nio.file Files] [java.nio.file.attribute FileAttribute]))
(defn -main [& _]
  (let [directory (str (Files/createTempDirectory "ecc-postgres-target-" (make-array FileAttribute 0)))
        snapshot (pg/export (System/getenv "SOURCE_JDBC_URL"))]
    (assert (= "ecc-postgresql-v1" (:format snapshot)))
    (assert (= 100 (get-in snapshot [:sequences :leads])))
    (with-redefs [files/directory (constantly (str directory "/blobs"))]
      (let [state (migration/import-state snapshot) source (store/memory-store) restored (store/memory-store)]
        (assert (= "Migrated student" (get-in state [:leads 10 :fullName])))
        (assert (= false (get-in state [:appointments 1 :clientVisible])))
        (assert (= "assigned" (get-in state [:users 1 :accessLevel])))
        (assert (= 100 (get-in state [:counters :leads])))
        (assert (= "hello" (slurp (files/blob-path (get-in state [:documents 1 :hash])))))
        (store/transact! source (fn [_] [state nil]))
        (let [archive (backup/write! source (str directory "/postgres.zip"))]
          (backup/restore! restored (:path archive))
          (assert (= state (store/snapshot restored))))
        (let [[next lead] (d/save-person state {:id 1 :role "admin"} :leads {:fullName "Next student"})]
          (assert (= 101 (:id lead))))))
    (println "PostgreSQL export, identity/sequence/BLOB migration, private flags, and backup restore passed")
    (shutdown-agents)))
