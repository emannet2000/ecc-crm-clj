(ns ecc-crm.extra-routes
  (:require [clojure.string :as str] [ecc-crm.markup :as html] [ecc-crm.domain :as d]
            [ecc-crm.auth :as auth] [ecc-crm.crm-extra :as crm] [ecc-crm.finance-extra :as controls]
            [ecc-crm.finance :as finance] [ecc-crm.reports :as reports] [ecc-crm.files :as files]
            [ecc-crm.portal :as portal] [ecc-crm.integrations :as integrations] [ecc-crm.backup :as backup] [clojure.java.io :as io] [ecc-crm.store :as store]))
(defn printed [kind row client]
  (let [content [:html [:head [:meta {:charset "utf-8"}] [:title (str "ECC " kind " #" (:id row))]]
                 [:body [:h1 (str "ECC " kind " #" (:id row))] [:p (:fullName client)] [:h2 (:title row)]
                  [:pre (or (:body row) (:description row))]
                  [:p (str (:currency row) " " (finance/money (or (:amountMinor row) (:totalMinor row) 0)))]
                  [:p (str "Status: " (:status row))] [:p (str "Date: " (or (:paidOn row) (:createdAt row)))]]]]
    {:status 200 :headers {"content-type" "text/html; charset=utf-8"
                          "content-disposition" (str "inline; filename=" kind "-" (:id row) ".html")}
     :body (str "<!doctype html>" (html/html content))}))
(defonce backup-lock (Object.))
(defn routes [db config {:keys [read-handler write-handler require-user csv-response]}]
  (let [read! #(read-handler db %) write! #(write-handler db %) id #(get-in % [:path-params :id])]
    [["/api/options" {:get (read! (fn [s u req]
                    (let [q (get-in req [:query-params "q"] "")]
                      (vec (concat (for [table [:leads :clients :cases] row (:rows (d/list-records s u table {"q" q "limit" "100"}))]
                                     {:value (str (case table :leads "lead:" :clients "client:" :cases "case:") (:id row)) :label (or (:fullName row) (:title row) (str "Application #" (:id row)))})
                                   (for [row (d/rows s :users) :when (not (:suspended row))] {:value (str "staff:" (:id row)) :label (:name row)}))))))}]
     ["/internal/backup" {:get (fn [req]
                 (let [secret (System/getenv "BACKUP_TOKEN") supplied (get-in req [:headers "authorization"] "")]
                   (when (or (nil? secret) (< (count secret) 32)) (d/fail 503 "Backup service is not configured"))
                   (when-not (java.security.MessageDigest/isEqual (.getBytes (auth/digest (str "Bearer " secret)) "UTF-8") (.getBytes (auth/digest supplied) "UTF-8"))
                     (d/fail 401 "Backup authorization required"))
                   (locking backup-lock
                     (let [directory (io/file (or (System/getenv "BACKUP_DIR") "data/backups")) _ (.mkdirs directory)
                           pending (io/file directory (str (auth/token) ".zip")) target (io/file directory "latest.zip")
                           result (backup/write! db (str pending))]
                       (java.nio.file.Files/move (.toPath pending) (.toPath target)
                         (into-array java.nio.file.CopyOption [java.nio.file.StandardCopyOption/ATOMIC_MOVE java.nio.file.StandardCopyOption/REPLACE_EXISTING]))
                       {:status 200 :headers {"content-type" "application/zip" "content-disposition" "attachment; filename=ecc-backup.zip" "x-backup-sha256" (:sha256 result)} :body target}))))}]
     ["/api/users/:id/invite" {:post (write! (fn [s u req] (crm/invite s u {:id (id req)} (:public-url config))))}]
     ["/api/workspace/team-access" {:get (read! (fn [s u _] (d/admin! u) (mapv #(assoc (d/public-user %) :suspended (:suspended %) :mfaEnabled (boolean (:mfaSecret %))) (d/rows s :users))))}]
     ["/api/workspace/reconciliation/candidates/:id" {:get (read! (fn [s u req] (controls/candidates s u (id req))))}]
     ["/api/workspace/payment-history/:id" {:get (read! (fn [s u req] (controls/history s u :invoices (id req))))}]
     ["/api/finance/expenses/:id/history" {:get (read! (fn [s u req] (controls/history s u :expenses (id req))))}]
     ["/api/finance/expenses/:id/attachments" {:post (write! (fn [s u req] (controls/expense-file s u (id req) (:json req))))
                                             :get (read! (fn [s u req] (d/privilege! u "finance_view") (d/record s :expenses (id req))
                                                           (vec (store/matching (:documents s {}) :expenseId (d/integer (id req))))))}]
     ["/api/finance/attachments/:id" {:get (fn [req] (let [s (store/snapshot db) u (require-user s req) doc (d/record s :documents (id req))]
                                                          (d/privilege! u "finance_view") (when-not (:expenseId doc) (d/fail 404 "Attachment not found"))
                                                          (files/download s u (id req))))}]
     ["/api/finance/attachments/:id/rescan" {:post (write! (fn [s u req] (d/privilege! u "expenses_record") (d/writer! u)
                                                                  (let [r (d/record s :documents (id req))]
                                                                    (when-not (:expenseId r) (d/fail 404 "Attachment not found"))
                                                                    (d/replace-row s :documents r {:scanStatus "Quarantined" :scanAttempts 0}))))}]
     ["/api/clients/:id/profile" {:get (read! (fn [s u req] (d/accessible! s u :clients (id req)) (get-in s [:profiles (d/integer (id req))] {})))
                                  :put (write! (fn [s u req] (crm/profile s u (assoc (:json req) :clientId (d/integer (id req))))))}]
     ["/api/clients/:id/photo" {:post (write! (fn [s u req] (crm/photo s u (id req) (:json req))))
                                :get (fn [req] (let [s (store/snapshot db) u (require-user s req) _ (d/privilege! u "download") client (d/accessible! s u :clients (id req))
                                                    doc (d/record s :documents (:photoId client))]
                                                (when-not (and (:photo doc) (= "Clean" (:scanStatus doc))) (d/fail 409 "Photo is awaiting scanning"))
                                                {:status 200 :headers {"content-type" "image/png"} :body (files/blob-path (:hash doc))}))}]
     ["/api/clients/:id/photo/retry" {:post (write! (fn [s u req] (d/writer! u) (d/privilege! u "edit")
                                                     (let [client (d/accessible! s u :clients (id req)) doc (d/record s :documents (:photoId client))]
                                                       (d/replace-row s :documents doc {:scanStatus "Quarantined" :scanAttempts 0}))))}]
     ["/api/workspace/conflict/:section/:id" {:get (read! (fn [s u req]
                          (let [table (get {"leads" :leads "clients" :clients "tasks" :tasks "applications" :cases "appointments" :appointments
                                            "documents" :checklists "invoices" :invoices "expenses" :expenses "proposals" :proposals "contracts" :contracts}
                                           (get-in req [:path-params :section]))]
                            (when-not table (d/fail 404 "Unknown record kind"))
                            (when (contains? #{:invoices :expenses} table) (d/privilege! u "finance_view"))
                            (crm/conflict s u table (id req)))))}]
     ["/api/workspace/record/:kind/:id/:section" {:get (read! (fn [s u req]
                         (let [kind (get-in req [:path-params :kind]) section (get-in req [:path-params :section])
                               table (get {"lead" :leads "client" :clients "case" :cases} kind)
                               _ (when-not table (d/fail 404 "Unknown record kind")) owner (d/accessible! s u table (id req))
                               fk (case kind "lead" :leadId "client" :clientId "case" :caseId)
                               target (get {"applications" :cases "tasks" :tasks "documents" :checklists "history" :activities "appointments" :appointments
                                            "milestones" :milestones "contact-log" :contacts "invoices" :invoices "proposals" :proposals "contracts" :contracts
                                            "client-messages" :messages "integrations" :integrations} section)]
                           (when-not target (d/fail 404 "Unknown record section"))
                           (when (= target :invoices) (d/privilege! u "finance_view"))
                           {:rows (vec (take 200 (filter #(d/visible? s u target %) (store/matching (get s target {}) fk (:id owner))))) :owner owner})))}]
     ["/api/workspace/documents/:id/upload" {:post (write! (fn [s u req] (let [r (d/accessible! s u :checklists (id req))]
                                  (files/upload s u (if (:clientId r) :clients :leads) (or (:clientId r) (:leadId r)) (assoc (:json req) :requestId (:id r))))))}]
     ["/api/workspace/documents/rescan" {:post (write! (fn [s u req] (d/admin! u) (let [r (d/record s :documents (:id (:json req)))]
                                                                                (d/replace-row s :documents r {:scanStatus "Quarantined" :scanAttempts 0}))))}]
     ["/api/workspace/mail/retry" {:post (write! (fn [s u req] (d/admin! u) (let [r (d/record s :mail (:id (:json req)))]
                                                     (when (= "Sent" (:status r)) (d/fail 409 "Delivered mail cannot be retried"))
                                                     (d/replace-row s :mail r {:status "Queued" :attempts 0 :leaseUntil nil}))))}]
     ["/api/workspace/calendar.ics" {:get (fn [req] (let [s (store/snapshot db) u (require-user s req)]
                                                            {:status 200 :headers {"content-type" "text/calendar; charset=utf-8" "content-disposition" "attachment; filename=calendar.ics"}
                                                             :body (reports/calendar s u)}))}]
     ["/api/workspace/reports.csv" {:get (fn [req] (let [s (store/snapshot db) u (require-user s req)]
                                                    (d/privilege! u "export") (csv-response (reports/rows s u "reports" (get-in req [:query-params "q"] "")))))}]
     ["/api/workspace/report-export/:kind" {:get (fn [req] (let [s (store/snapshot db) u (require-user s req)]
                          (d/privilege! u "export") (csv-response (reports/rows s u (get-in req [:path-params :kind]) (get-in req [:query-params "q"] "")))))}]
     ["/api/workspace/finance-export/:section" {:get (fn [req] (let [s (store/snapshot db) u (require-user s req)]
                          (d/privilege! u "finance_view") (d/privilege! u "export")
                          (csv-response (reports/rows s u (get-in req [:path-params :section]) (get-in req [:query-params "q"] "")))))}]
     ["/api/finance/print/payments/:id" {:get (fn [req] (let [s (store/snapshot db) u (require-user s req) _ (d/privilege! u "finance_view")
                             r (d/record s :payments (id req)) invoice (d/accessible! s u :invoices (:invoiceId r))]
                         (printed "receipt" r (d/record s :clients (:clientId invoice)))))}]
     ["/api/portal/invoices/:id/download" {:get (fn [req] (let [s (store/snapshot db) p (portal/session s (get-in req [:cookies "ecc_portal" :value]))
                                  r (d/record s :invoices (id req))]
                         (when (or (not= (:clientId p) (:clientId r)) (= "Draft" (:status r))) (d/fail 404 "Invoice not found"))
                         (printed "invoice" r (d/record s :clients (:clientId p)))))}]
     ["/api/portal/receipts/:id/download" {:get (fn [req] (let [s (store/snapshot db) p (portal/session s (get-in req [:cookies "ecc_portal" :value]))
                                 r (d/record s :payments (id req)) invoice (d/record s :invoices (:invoiceId r))]
                         (when-not (= (:clientId p) (:clientId invoice)) (d/fail 404 "Receipt not found"))
                         (printed "receipt" r (d/record s :clients (:clientId p)))))}]
     ["/api/portal/commercial/:id/download" {:get (fn [req] (let [s (store/snapshot db) p (portal/session s (get-in req [:cookies "ecc_portal" :value]))
                                  kind (get-in req [:query-params "kind"] "contracts") table (case kind "contracts" :contracts "proposals" :proposals (d/fail 404 "Unknown document"))
                                  r (d/record s table (id req))]
                         (when (or (not= (:clientId p) (:clientId r)) (= "Draft" (:status r))) (d/fail 404 "Document not found"))
                         (printed (name table) r (d/record s :clients (:clientId p)))))}]
     ["/api/portal/signatures/:id/download" {:get (fn [req] (let [s (store/snapshot db) p (portal/session s (get-in req [:cookies "ecc_portal" :value]))
                                link (d/record s :integrationLinks (id req)) doc (d/record s :documents (:signedDocumentId link))]
                         (when-not (and (= "docusign" (:provider link)) (= "Completed" (:status link)) (= (:clientId p) (:clientId link)) (= (:clientId p) (:clientId doc)))
                           (d/fail 404 "Signature not found")) (files/download s {:role "admin"} (:id doc))))}]
     ["/api/webhooks/stripe" {:post (fn [req]
                         (let [event (integrations/verify-stripe (:raw-body req) (get-in req [:headers "stripe-signature"]) (integrations/env "STRIPE_WEBHOOK_SECRET"))]
                           {:status 200 :body (store/transact! db #(integrations/webhook % event))}))}]]))
