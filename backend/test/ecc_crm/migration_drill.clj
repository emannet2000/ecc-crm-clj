(ns ecc-crm.migration-drill
  (:require [cheshire.core :as json] [ecc-crm.migration :as migration] [ecc-crm.store :as store]
            [ecc-crm.backup :as backup] [ecc-crm.files :as files])
  (:import [java.nio.file Files] [java.nio.file.attribute FileAttribute]))
(defn -main [& [source]]
  (let [directory (str (Files/createTempDirectory "ecc-migration-drill-" (make-array FileAttribute 0)))
        input (json/parse-string (slurp source) true)
        source-rows (reduce + (map count (vals (:tables input))))]
    (with-redefs [files/directory (constantly (str directory "/source-blobs"))]
      (let [state (migration/import-state input)]
        (assert (= source-rows (count (:legacy state))))
        (with-open [db (store/open-store (str directory "/source-xtdb"))]
          (store/transact! db (fn [_] [state nil]))
          (assert (= state (store/materialize (store/snapshot db))))
          (let [archive (backup/write! db (str directory "/snapshot.zip"))]
            (with-redefs [files/directory (constantly (str directory "/restored-blobs"))]
              (with-open [restored (store/open-store (str directory "/restored-xtdb"))]
                (backup/restore! restored (:path archive))
                (assert (= state (store/materialize (store/snapshot restored))))))
            (let [report {:sourceTables (count (:tables input)) :sourceRows source-rows :preservedRows (count (:legacy state))
                          :typedTables (count state) :snapshotSha256 (:sha256 archive) :roundTrip true :sourceModified false}]
              (spit "/tmp/ecc-clojure-migration-drill.json" (json/generate-string report {:pretty true}))
              (println (json/generate-string report)))))))
    (shutdown-agents)))
