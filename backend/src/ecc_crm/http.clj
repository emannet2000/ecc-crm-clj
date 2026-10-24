(ns ecc-crm.http
  (:require [cheshire.core :as json]
            [clojure.java.io :as io]
            [clojure.string :as str]
            [clojure.data.csv :as csv]
            [ecc-crm.markup :as html]
            [ecc-crm.auth :as auth]
            [ecc-crm.domain :as d]
            [ecc-crm.finance :as finance]
            [ecc-crm.files :as files]
            [ecc-crm.portal :as portal]
            [ecc-crm.store :as store]
            [ecc-crm.workflows :as workflows]
            [ecc-crm.extra-routes :as extra]
            [ecc-crm.crm-extra :as crm]
            [ecc-crm.diagnostics :as diagnostics]
            [reitit.ring :as ring]
            [ring.middleware.cookies :refer [wrap-cookies]]
            [ring.middleware.params :refer [wrap-params]])
  (:import [java.io ByteArrayOutputStream StringWriter]
           [java.time Instant]
           [java.util Base64]))

(def max-body (* 36 1024 1024)) ; Allows base64 encoding of a 25 MB file.
(defn response [body] {:status 200 :body body})
(defn require-user [s req]
  (let [u (or (auth/authenticate s req) (d/fail 401 "Sign in to continue"))]
    (when (and (= "true" (System/getenv "REQUIRE_ADMIN_MFA")) (= "admin" (:role u)) (not (:mfaSecret u))
               (not (or (str/starts-with? (:uri req) "/api/workspace/security")
                        (contains? #{"/api/auth/me" "/api/auth/logout"} (:uri req)))))
      (d/fail 403 "Set up an authenticator in Account security before opening workspace records")) u))
(defn read-handler [db f]
  (fn [req] (let [s (store/snapshot db) u (require-user s req)] (response (f s u req)))))
(defn write-handler [db f]
  (fn [req] (response (store/transact! db (fn [s] (f s (require-user s req) req))))))
(defn id [req] (get-in req [:path-params :id]))
(defn table-routes [db path table save]
  [[path {:get (read-handler db (fn [s u req] (d/list-records s u table (:query-params req))))
          :post (write-handler db (fn [s u req] (save s u (dissoc (:json req) :id))))}]
   [(str path "/:id")
    {:get (read-handler db (fn [s u req] (if (contains? #{:leads :clients} table)
                                         (d/detail s u table (id req)) (d/accessible! s u table (id req)))))
     :patch (write-handler db (fn [s u req] (save s u (assoc (:json req) :id (id req)))))
     :delete (write-handler db (fn [s u req] (d/archive s u table (id req))))}]] )
(defn csv-response [records]
  (let [columns (sort (set (mapcat keys records))) w (StringWriter.)
        cell (fn [v] (let [v (str v)] (if (re-find #"^[\s]*[=+@\-\t\r]" v) (str "'" v) v)))]
    (csv/write-csv w (cons (map name columns) (map #(map (fn [k] (cell (get % k))) columns) records)))
    {:status 200 :headers {"content-type" "text/csv; charset=utf-8" "content-disposition" "attachment; filename=export.csv"}
     :body (str w)}))
(defn users-save [s u input]
  (d/admin! u)
  (let [old (d/record s :users (:id input)) _ (d/version! old input)
        role (d/choice (:role input (:role old)) ["admin" "consultant" "viewer"])]
    (when (and (= "admin" (:role old)) (not= "admin" role)
               (<= (count (filter #(and (= "admin" (:role %)) (not (:suspended %))) (d/rows s :users))) 1))
      (d/fail 409 "The last administrator cannot be removed"))
    (when (and (= (:id u) (:id old)) (:suspended input)) (d/fail 400 "You cannot suspend your own account"))
    (let [[s row] (d/replace-row s :users old (merge (select-keys input [:name :suspended :accessLevel :privileges]) {:role role}))]
      [(-> s (auth/revoke-user (:id old)) (d/audit u :users row "updated")) (d/public-user row)])))
(defn routes [db {:keys [production? public-url] :as config}]
  (vec
    (concat
      (extra/routes db config {:read-handler read-handler :write-handler write-handler :require-user require-user :csv-response csv-response})
      [["/api/health" {:get (constantly (response {:status "ok" :stack "clojure-xtdb"}))}]
       ["/api/ready" {:get (fn [_] (store/snapshot db) (response {:status "ready"}))}]
       ["/api/time" {:get (fn [_] (response {:now (d/now) :businessDate (d/today) :timezone "Asia/Manila"}))}]
       ["/api/auth/login" {:post (fn [req]
                                   (let [r (auth/login! db (:json req) (:remote-addr req))]
                                     (assoc (response r) :cookies (auth/cookie (:token r) production? 28800))))}]
       ["/api/auth/recover" {:post (fn [req] (response (auth/recover! db (:json req) public-url)))}]
       ["/api/auth/reset" {:post (fn [req] (response (auth/reset! db (:json req))))}]
       ["/api/auth/logout" {:post (fn [req] (assoc (response (auth/logout! db req)) :cookies (auth/cookie "" production? 0)))}]
       ["/api/portal/exchange" {:post (fn [req] (let [r (store/transact! db #(portal/exchange % (:json req)))]
                                                      (assoc (response (dissoc r :token)) :cookies
                                                             {:ecc_portal {:value (:token r) :http-only true :secure production? :same-site :strict :path "/api/portal" :max-age 3600}})))}]
       ["/api/portal" {:get (fn [req] (let [s (store/snapshot db) r (portal/session s (get-in req [:cookies "ecc_portal" :value]))]
                                        (response (portal/view s r))))}]
       ["/api/portal/logout" {:post (fn [req]
                                      (store/transact! db #(vector (update % :portalSessions dissoc (auth/digest (get-in req [:cookies "ecc_portal" :value]))) nil))
                                      (assoc (response {:loggedOut true}) :cookies {:ecc_portal {:value "" :path "/api/portal" :max-age 0}}))}]
       ["/api/portal/documents/:id" {:get (fn [req]
                                           (let [s (store/snapshot db) r (portal/session s (get-in req [:cookies "ecc_portal" :value]))
                                                 doc (d/record s :documents (id req))]
                                             (when-not (portal/shared? s r doc) (d/fail 404 "Shared document not found"))
                                             (files/download s {:role "admin"} (id req))))}]
       ["/api/portal/commercial/:kind/:id/:action" {:post (fn [req]
                      (response (store/transact! db (fn [s]
                        (let [link (portal/session s (get-in req [:cookies "ecc_portal" :value]))
                              table (case (get-in req [:path-params :kind]) "proposals" :proposals "contracts" :contracts (d/fail 404 "Unknown document type"))]
                          (portal/commercial-action s link table (id req) (get-in req [:path-params :action]) (assoc (:json req) :publicUrl public-url)))))))}]
       ["/api/portal/requests/:id/upload" {:post (fn [req]
                        (response (store/transact! db
                          (fn [s]
                            (let [link (portal/session s (get-in req [:cookies "ecc_portal" :value]))
                                  r (d/record s :checklists (id req))]
                              (when-not (= (:clientId link) (:clientId r)) (d/fail 404 "Request not found"))
                              (files/upload s {:role "admin"} :clients (:clientId link)
                                            (assoc (:json req) :requestId (:id r))))))))}]
       ["/api/finance/print/invoices/:id" {:get (fn [req]
                         (let [s (store/snapshot db) u (require-user s req) _ (d/privilege! u "finance_view")
                               r (finance/balance s (d/accessible! s u :invoices (id req)))
                               client (d/accessible! s u :clients (:clientId r))]
                           {:status 200 :headers {"content-type" "text/html; charset=utf-8"}
                            :body (str "<!doctype html>" (html/html [:html [:head [:title (str "Invoice " (:id r))]]
                               [:body [:h1 (str "Invoice #" (:id r))] [:p (:fullName client)]
                                [:p (:description r)] [:p (str (:currency r) " " (:amount r))]
                                [:p (str "Paid: " (:paid r) " · Balance: " (:balance r))] [:p (str "Due " (:dueDate r))]]]))}))}]
       ["/api/metrics" {:get (read-handler db (fn [s u _] (d/admin! u)
                          {:activeSessions (count (filter auth/unexpired? (vals (:sessions s))))
                           :pendingMail (count (filter #(= "Queued" (:status %)) (d/rows s :mail)))
                           :failedMail (count (filter #(= "Failed" (:status %)) (d/rows s :mail)))
                           :operations (when (:operations s) (into {} (:operations s)))}))}]
       ["/api/reminders" {:get (read-handler db (fn [s u _]
                          (vec (filter #(and (= (:id u) (:userId %)) (nil? (:readAt %))) (d/rows s :notifications)))))}]
       ["/api/duplicates" {:get (read-handler db (fn [s u _]
                      (vec (for [table [:leads :clients] field [:email :phone]
                                 [value rs] (group-by #(str/lower-case (str (field %)))
                                                     (filter #(d/visible? s u table %) (d/rows s table)))
                                 :when (and (not (str/blank? value)) (> (count rs) 1))]
                             {:field (name field) :value value :kind (name table)
                              :records (mapv #(select-keys % [:id :fullName :email :phone :revision]) rs)}))))}]
       ["/api/bulk/leads" {:post (write-handler db (fn [s u req]
                         (let [input (:json req) _ (when (> (count (:ids input)) 200) (d/fail 400 "Select at most 200 leads"))
                               s (reduce (fn [s id] (first (case (:action input)
                                        "archive" (d/archive s u :leads id)
                                        "assign" (d/save-person s u :leads {:id id :consultantId (:consultantId input)})
                                        "stage" (d/save-person s u :leads {:id id :stage (:stage input)})
                                        (d/fail 400 "Unknown bulk action")))) s (:ids input))]
                           [s {:updated (count (:ids input))}])))}]
       ["/api/auth/me" {:get (read-handler db (fn [_ u _] (d/public-user u)))}]
       ["/api/auth/password" {:put (write-handler db (fn [s u req] (auth/change-password s u (:json req))))}]
       ["/api/users" {:get (read-handler db (fn [s _ _] (mapv d/public-user (d/rows s :users))))
                       :post (write-handler db (fn [s u req] (if (str/blank? (:password (:json req))) (crm/invite s u (:json req) public-url) (auth/create-user s u (:json req)))))}]
       ["/api/users/:id" {:patch (write-handler db (fn [s u req] (users-save s u (assoc (:json req) :id (id req)))))
                           :delete (write-handler db (fn [s u req]
                                                       (when (= (:id u) (d/integer (id req))) (d/fail 400 "You cannot remove your own account"))
                                                       (users-save s u {:id (id req) :role "viewer" :suspended true})))}]
       ["/api/leads/:id/convert" {:post (write-handler db (fn [s u req] (d/convert s u (id req))))}]
       ["/api/leads/:id/advance" {:post (write-handler db (fn [s u req]
                                                           (let [old (d/accessible! s u :leads (id req))
                                                                 index (.indexOf d/stages (:stage old))]
                                                             (d/save-person s u :leads {:id (id req) :stage (nth d/stages (min (dec (count d/stages)) (inc index)))}))))}]
       ["/api/activities" {:get (read-handler db (fn [s u req] (:rows (d/list-records s u :activities (:query-params req)))))}]
       ["/api/stats" {:get (read-handler db (fn [s u _] (workflows/stats s u)))}]
       ["/api/audit" {:get (read-handler db (fn [s u _] (d/admin! u) (vec (take 200 (sort-by :id > (d/rows s :audit))))))}]
       ["/api/archive" {:get (read-handler db (fn [s u _] (d/admin! u)
                                                {:leads (vec (filter :deletedAt (d/rows s :leads)))
                                                 :clients (vec (filter :deletedAt (d/rows s :clients)))}))}]
       ["/api/contacts/check" {:post (read-handler db (fn [s u req]
                                                        (let [email (str/lower-case (str (:email (:json req)))) phone (:phone (:json req))]
                                                          {:matches (vec (for [t [:leads :clients] r (d/rows s t)
                                                                               :when (and (d/visible? s u t r)
                                                                                          (or (and (not (str/blank? email)) (= email (str/lower-case (str (:email r)))))
                                                                                              (and (not (str/blank? phone)) (= phone (:phone r)))))]
                                                                           (assoc (select-keys r [:id :fullName :email :phone]) :kind (name t))))})))}]
       ["/api/workspace/:section" {:get (read-handler db (fn [s u req] (workflows/section s u (get-in req [:path-params :section]) (:query-params req))))}]
       ["/api/workspace/:section/:action" {:post (write-handler db (fn [s u req] (workflows/action s u (get-in req [:path-params :section])
                                                                                               (get-in req [:path-params :action]) (assoc (:json req) :publicUrl public-url))))}]]
      (table-routes db "/api/leads" :leads #(d/save-person %1 %2 :leads %3))
      (table-routes db "/api/clients" :clients #(d/save-person %1 %2 :clients %3))
      (table-routes db "/api/tasks" :tasks d/save-task)
      (for [[path table] [["leads" :leads] ["clients" :clients]]
            [suffix handler] [["restore" (fn [s u req] (d/restore-record s u table (id req)))]
                              ["notes" (fn [s u req] (d/add-note s u table (id req) (:json req)))]]]
        [(str "/api/" path "/:id/" suffix) {:post (write-handler db handler)}])
      [["/api/clients/:id/cases" {:post (write-handler db (fn [s u req]
                                                           (workflows/action s u "applications" "save"
                                                                             (assoc (:json req) :clientId (d/integer (id req))))))}]
       ["/api/documents/:id/download" {:get (fn [req] (let [s (store/snapshot db)] (files/download s (require-user s req) (id req))))}]
       ["/api/documents/:id" {:delete (write-handler db (fn [s u req] (d/archive s u :documents (id req))))}]
       ["/api/cases/:id" {:delete (write-handler db (fn [s u req] (d/archive s u :cases (id req))))}]]
      (for [[path table] [["leads" :leads] ["clients" :clients]]]
        [(str "/api/" path "/:id/documents") {:post (write-handler db (fn [s u req] (files/upload s u table (id req) (:json req))))}])
      (for [[path table] [["leads" :leads] ["clients" :clients]]]
        [(str "/api/export/" path ".csv") {:get (fn [req]
                                                (let [s (store/snapshot db) u (require-user s req)]
                                                  (d/privilege! u "export")
                                                  (csv-response (filter #(d/visible? s u table %) (d/rows s table)))))}]))))
(defn read-json [request]
  (if (and (:body request) (str/includes? (get-in request [:headers "content-type"] "") "application/json"))
    (let [out (ByteArrayOutputStream.) buffer (byte-array 8192)]
      (loop [total 0]
        (let [n (.read ^java.io.InputStream (:body request) buffer)]
          (when (pos? n)
            (when (> (+ total n) max-body) (d/fail 413 "Request exceeds 36 MB"))
            (.write out buffer 0 n) (recur (+ total n)))))
      (assoc request :raw-body (.toString out "UTF-8") :json (try (json/parse-string (.toString out "UTF-8") true)
                               (catch Exception _ (d/fail 400 "Invalid JSON request")))))
    request))
(defn wrap-api [handler {:keys [public-url production?]}]
  (fn [req]
    (let [started (System/nanoTime)
          headers {"x-content-type-options" "nosniff" "referrer-policy" "same-origin"
                   "x-frame-options" "DENY" "cache-control" "no-store"
                   "content-security-policy" "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; connect-src 'self'; frame-ancestors 'none'"}
          result (try
                   (when (and (not= "/api/webhooks/stripe" (:uri req))
                              (not (contains? #{:get :head :options} (:request-method req)))
                              (or (= "cross-site" (get-in req [:headers "sec-fetch-site"]))
                                  (and (get-in req [:headers "origin"])
                                       (not= (str/replace public-url #"/$" "") (get-in req [:headers "origin"])))))
                     (d/fail 403 "Request origin does not match this workspace"))
                   (handler (read-json req))
                   (catch clojure.lang.ExceptionInfo e
                     {:status (or (:status (ex-data e)) 500) :body {:error (.getMessage e)}})
                   (catch Throwable e
                     (binding [*out* *err*] (println "request_failed" (.getName (class e))))
                     {:status 500 :body {:error "The request could not be completed"}}))
          result (update result :headers #(merge headers %))]
      (diagnostics/request! req (:status result) (/ (- (System/nanoTime) started) 1000000.0))
      (if (or (map? (:body result)) (sequential? (:body result)))
        (-> result (assoc-in [:headers "content-type"] "application/json; charset=utf-8")
            (update :body json/generate-string)) result))))
(defn app [db config]
  (-> (ring/ring-handler (ring/router (mapv (fn [[path data]]
                                         [path (cond-> data (str/starts-with? path "/api/workspace/") (assoc :conflicting true))])
                                       (routes db config)))
                         (ring/routes
                           (ring/create-file-handler {:path "/" :root (:web-dist config "../frontend/public")})
                           (ring/create-default-handler {:not-found (constantly {:status 404 :body {:error "Route not found"}})})))
      (wrap-api config) wrap-params wrap-cookies))
