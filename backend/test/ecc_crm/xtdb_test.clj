(ns ecc-crm.xtdb-test
  (:require [clojure.test :refer :all]
            [ecc-crm.store :as store]
            [ecc-crm.auth :as auth]
            [ecc-crm.http :as http]
            [cheshire.core :as json] [ecc-crm.transport-test])
  (:import [java.nio.file Files] [java.nio.file.attribute FileAttribute]))
(deftest durable-transactions-and-reopen
  (let [directory (str (Files/createTempDirectory "ecc-xtdb-integration-" (make-array FileAttribute 0)))]
    (with-open [db (store/open-store directory)]
      (is (= {} (store/snapshot db)))
      (is (= :committed (store/transact! db #(vector (assoc % :counter 1) :committed))))
      (is (thrown? Exception (store/transact! db (fn [_] (throw (ex-info "Business validation rejected" {}))))))
      (is (= 1 (:counter (store/snapshot db))))
      (let [jobs (doall (for [_ (range 4)] (future (dotimes [_ 3] (store/transact! db #(vector (update % :counter inc) nil))))))]
        (doseq [job jobs] @job)
        (is (= 13 (:counter (store/snapshot db))))))
    (with-open [db (store/open-store directory)]
      (is (= 13 (:counter (store/snapshot db)))))))
(deftest ring-api-over-real-xtdb
  (let [directory (str (Files/createTempDirectory "ecc-xtdb-api-" (make-array FileAttribute 0)))]
    (with-open [db (store/open-store directory)]
      (store/transact! db #(auth/create-user % nil {:name "Admin" :email "admin@example.com" :role "admin" :password "a-long-enough-password"}))
      (let [login (auth/login! db {:email "admin@example.com" :password "a-long-enough-password"} "integration")
            app (http/app db {:public-url "http://localhost:4000"})
            headers {"authorization" (str "Bearer " (:token login)) "content-type" "application/json"}
            created (app {:request-method :post :uri "/api/leads" :headers headers
                          :body (java.io.ByteArrayInputStream. (.getBytes "{\"fullName\":\"Durable student\"}" "UTF-8"))})
            listed (app {:request-method :get :uri "/api/leads" :headers headers})]
        (is (= 200 (:status created)))
        (is (= "Durable student" (:fullName (json/parse-string (:body created) true))))
        (is (= 1 (:total (json/parse-string (:body listed) true))))))))
(defn -main [& _]
  (let [r (run-tests 'ecc-crm.xtdb-test 'ecc-crm.transport-test)] (shutdown-agents) (System/exit (if (zero? (+ (:fail r) (:error r))) 0 1))))
