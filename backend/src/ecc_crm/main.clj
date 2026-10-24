(ns ecc-crm.main
  (:require [clojure.edn :as edn]
            [clojure.java.io :as io]
            [clojure.string :as str]
            [cheshire.core :as json]
            [ecc-crm.auth :as auth]
            [ecc-crm.domain :as d]
            [ecc-crm.http :as http]
            [ecc-crm.store :as store]
            [ecc-crm.workers :as workers]
            [ecc-crm.migration :as migration]
            [ecc-crm.files :as files]
            [ecc-crm.postgres-export :as postgres]
            [ecc-crm.backup :as backup]
            [ecc-crm.release :as release]
            [org.httpkit.server :as server])
  (:gen-class))

(defn config []
  (let [production? (= "production" (System/getenv "APP_ENV"))
        url (or (System/getenv "PUBLIC_URL") "http://localhost:4000")
        directory (or (System/getenv "XTDB_DIR") "data/xtdb")]
    (when (and production? (not (str/starts-with? url "https://")))
      (d/fail 500 "Production requires an HTTPS PUBLIC_URL"))
    {:production? production? :public-url url :xtdb-dir directory
     :web-dist (or (System/getenv "WEB_DIST") "../frontend/public")
     :port (or (d/integer (System/getenv "PORT")) 4000)
     :bind (or (System/getenv "BIND_HOST") "127.0.0.1")}))
(defn private-write! [path data]
  (let [p (.toPath (io/file path))]
    (java.nio.file.Files/createFile p (into-array java.nio.file.attribute.FileAttribute
                                     [(java.nio.file.attribute.PosixFilePermissions/asFileAttribute
                                        (java.nio.file.attribute.PosixFilePermissions/fromString "rw-------"))]))
    (spit path data)))
(defn -main [& [command & args]]
  (let [config (config)]
    (if (= command "export-postgres")
      (do (private-write! (first args) (json/generate-string (postgres/export (or (System/getenv "SOURCE_JDBC_URL") (d/fail 400 "Set SOURCE_JDBC_URL")))))
          (println "PostgreSQL snapshot exported"))
      (with-open [db (store/open-store (:xtdb-dir config))]
      (case command
        "adduser" (let [[email name role] args password (or (System/getenv "ECC_ADMIN_PASSWORD")
                                                          (when-let [console (System/console)] (String. (.readPassword console "Password: " (object-array 0)))))]
                    (when-not password (d/fail 400 "Set ECC_ADMIN_PASSWORD or run in a terminal with a password prompt"))
                    (store/transact! db #(auth/create-user % {:id 0 :role "admin"}
                                                          {:email email :name name :role role :password password}))
                    (println "Account created"))
        "backup" (println (pr-str (backup/write! db (first args))))
        "restore" (println (pr-str (backup/restore! db (first args))))
        "restore-legacy" (let [backup (edn/read-string (slurp (first args)))]
                    (when-not (= "ecc-clojure-v1" (:format backup)) (d/fail 400 "Unsupported backup format"))
                    (when (seq (store/snapshot db)) (d/fail 409 "Restore requires an empty XTDB workspace"))
                    (doseq [hash (set (keep :hash (d/rows (:state backup) :documents)))]
                      (let [content (get-in backup [:blobs hash])]
                        (when-not content (d/fail 400 "Backup is missing document contents"))
                        (when-not (= hash (:hash (migration/file! {:content {:$binary content}})))
                          (d/fail 400 "Document checksum verification failed"))))
                    (store/transact! db (fn [s] (when (seq s) (d/fail 409 "Restore requires an empty XTDB workspace"))
                                         [(:state backup) nil]))
                    (println "Workspace restored"))
        "export-postgres" (do (private-write! (first args) (json/generate-string (postgres/export (or (System/getenv "SOURCE_JDBC_URL")
                                                       (d/fail 400 "Set SOURCE_JDBC_URL to the read-only source database")))))
                               (println "PostgreSQL snapshot exported"))
        "import-postgres" (let [state (migration/import-state (json/parse-string (slurp (first args)) true))]
                            (store/transact! db (fn [s] (when (seq s) (d/fail 409 "Import requires an empty workspace")) [state nil]))
                            (println "PostgreSQL snapshot imported"))
        "import-sqlite" (let [state (migration/import-state (json/parse-string (slurp (first args)) true))]
                          (store/transact! db (fn [s] (when (seq s) (d/fail 409 "Import requires an empty workspace")) [state nil]))
                          (println "Imported snapshot; existing sessions require a fresh login"))
        "migrate" (println "XTDB workspace initialized")
        (let [_ (when (:production? config) (release/verify! ".." (or (System/getenv "RELEASE_FILE") "../release-clojure.json")))
              _ (when (:restoreProgress (store/snapshot db)) (d/fail 503 "Complete the interrupted restore before starting the server"))
              jobs (workers/start! db)
              stop (server/run-server (http/app db config)
                                     {:ip (:bind config) :port (:port config) :max-body http/max-body})
              done (promise)]
          (.addShutdownHook (Runtime/getRuntime) (Thread. #(do (.shutdownNow jobs) (stop :timeout 5000) (deliver done true))))
          (println "ECC Clojure listening on" (:bind config) (:port config))
          @done))))))
