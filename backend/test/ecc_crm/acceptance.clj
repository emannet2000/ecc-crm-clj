(ns ecc-crm.acceptance
  (:require [ecc-crm.store :as store] [ecc-crm.auth :as auth] [ecc-crm.http :as http] [ecc-crm.files :as files]
            [org.httpkit.server :as server])
  (:import [java.net ServerSocket] [java.nio.file Files] [java.nio.file.attribute FileAttribute]))
(defn -main [& _]
  (let [directory (str (Files/createTempDirectory "ecc-live-journey-" (make-array FileAttribute 0)))
        port (with-open [socket (ServerSocket. 0)] (.getLocalPort socket)) url (str "http://127.0.0.1:" port)
        password "journey-fixture-password"]
    (with-redefs [files/directory (constantly (str directory "/blobs"))]
      (with-open [db (store/open-store (str directory "/xtdb"))]
        (store/transact! db #(auth/create-user % nil {:name "Journey Admin" :email "journey@example.com" :role "admin" :password password}))
        (let [stop (server/run-server (http/app db {:public-url url :web-dist "../frontend/public"}) {:ip "127.0.0.1" :port port})]
          (try
            (let [builder (doto (ProcessBuilder. ^java.util.List ["node" "--test" "scripts/clojure/journey.browser.cjs"])
                            (.directory (java.io.File. "..")) .inheritIO)
                  environment (.environment builder)]
              (.put environment "ECC_TEST_URL" url) (.put environment "ECC_TEST_PASSWORD" password)
              (let [process (.start builder) code (.waitFor process)]
                (when-not (zero? code) (throw (ex-info "Live browser acceptance failed" {:exit code})))))
            (finally (stop :timeout 5000))))))
    (shutdown-agents)))
