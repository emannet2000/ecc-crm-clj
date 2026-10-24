(ns ecc-crm.integrations
  (:require [cheshire.core :as json] [clojure.string :as str] [clojure.java.io :as io]
            [ecc-crm.domain :as d] [ecc-crm.auth :as auth] [ecc-crm.finance :as finance]
            [ecc-crm.files :as files] [ecc-crm.store :as store] [ecc-crm.markup :as html])
  (:import [java.net URI URLEncoder] [java.net.http HttpClient HttpClient$Redirect HttpRequest HttpRequest$BodyPublishers HttpResponse$BodyHandlers]
           [java.time Instant Duration] [java.util Base64] [javax.crypto Mac] [javax.crypto.spec SecretKeySpec]
           [java.security MessageDigest] [java.nio.file Files StandardCopyOption CopyOption]))
(defn env [key] (let [v (System/getenv key)] (when (str/blank? v) (d/fail 503 (str "Configure " key))) v))
(defn namespace-id [] (env "INTEGRATION_NAMESPACE"))
(defn encode [s] (URLEncoder/encode (str s) "UTF-8"))
(defn form [m] (str/join "&" (map (fn [[k v]] (str (encode (name k)) "=" (encode v))) m)))
(defn error [code status uncertain?] (throw (ex-info code {:code code :provider-status status :uncertain? uncertain?})))
(def allowed-hosts #{"zoom.us" "api.zoom.us" "oauth2.googleapis.com" "www.googleapis.com" "api.stripe.com" "account.docusign.com" "account-d.docusign.com"})
(defn transport [{:keys [method url headers payload form-data binary?]}]
  (let [uri (URI/create url) host (.getHost uri)]
    (when-not (and (= "https" (.getScheme uri)) (nil? (.getUserInfo uri))
                   (or (allowed-hosts host) (and host (str/ends-with? host ".docusign.net")))) (error "provider_host_rejected" nil false))
    (let [client (-> (HttpClient/newBuilder) (.followRedirects HttpClient$Redirect/NEVER) (.connectTimeout (Duration/ofSeconds 10)) .build)
          builder (-> (HttpRequest/newBuilder uri) (.timeout (Duration/ofSeconds 30)))
          content (cond form-data (form form-data) payload (json/generate-string payload) :else "")]
      (doseq [[k v] (merge {"Accept" "application/json"} headers
                          (when (or payload form-data) {"Content-Type" (if form-data "application/x-www-form-urlencoded" "application/json")}))]
        (.header builder k (str v)))
      (.method builder method (if (seq content) (HttpRequest$BodyPublishers/ofString content) (HttpRequest$BodyPublishers/noBody)))
      (try
        (let [r (.send client (.build builder) (HttpResponse$BodyHandlers/ofInputStream)) code (.statusCode r)
              bytes (with-open [stream (.body r)] (.readNBytes stream (inc (* 25 1024 1024))))]
          (when (> (alength bytes) (* 25 1024 1024)) (error "provider_response_too_large" code true))
          (when-not (<= 200 code 299) (error (str "provider_http_" code) code (>= code 500)))
          (if binary? bytes (if (zero? (alength bytes)) {} (json/parse-string (String. bytes "UTF-8") true))))
        (catch java.io.IOException _ (error "provider_transport_failure" nil (= method "POST")))))))
(def ^:dynamic *transport* transport)
(defonce tokens (atom {}))
(defn basic [a b] (str "Basic " (.encodeToString (Base64/getEncoder) (.getBytes (str a ":" b) "UTF-8"))))
(defn access-token [provider]
  (if (= provider "stripe") (env "STRIPE_SECRET_KEY")
    (let [cached (get @tokens provider)]
      (if (and cached (> (:expires cached) (+ 60 (.getEpochSecond (Instant/now))))) (:token cached)
        (let [request (case provider
                        "zoom" {:url "https://zoom.us/oauth/token" :headers {"Authorization" (basic (env "ZOOM_CLIENT_ID") (env "ZOOM_CLIENT_SECRET"))}
                                :form-data {:grant_type "account_credentials" :account_id (env "ZOOM_ACCOUNT_ID")}}
                        "google" {:url "https://oauth2.googleapis.com/token" :form-data {:grant_type "refresh_token" :client_id (env "GOOGLE_CLIENT_ID")
                                  :client_secret (env "GOOGLE_CLIENT_SECRET") :refresh_token (env "GOOGLE_REFRESH_TOKEN")}}
                        "docusign" (let [host (or (System/getenv "DOCUSIGN_AUTH_HOST") "account-d.docusign.com")
                                         _ (when-not (contains? #{"account-d.docusign.com" "account.docusign.com"} host) (error "invalid_docusign_auth_host" nil false))
                                         file (io/file (env "DOCUSIGN_REFRESH_TOKEN_FILE")) path (.toPath file)]
                                     (when (or (Files/isSymbolicLink path)
                                               (some #(contains? #{java.nio.file.attribute.PosixFilePermission/GROUP_READ java.nio.file.attribute.PosixFilePermission/OTHERS_READ
                                                                  java.nio.file.attribute.PosixFilePermission/GROUP_WRITE java.nio.file.attribute.PosixFilePermission/OTHERS_WRITE} %)
                                                     (Files/getPosixFilePermissions path (make-array java.nio.file.LinkOption 0))))
                                       (error "insecure_docusign_token_file" nil false))
                                     {:url (str "https://" host "/oauth/token") :headers {"Authorization" (basic (env "DOCUSIGN_CLIENT_ID") (env "DOCUSIGN_CLIENT_SECRET"))}
                                      :form-data {:grant_type "refresh_token" :refresh_token (str/trim (slurp file))}}))
              r (*transport* (assoc request :method "POST")) token (:access_token r)]
          (when-not token (error "provider_token_missing" nil false))
          (when (and (= provider "docusign") (:refresh_token r))
            (let [path (.toPath (io/file (env "DOCUSIGN_REFRESH_TOKEN_FILE")))
                  tmp (Files/createTempFile (.getParent path) ".oauth-" ".tmp" (make-array java.nio.file.attribute.FileAttribute 0))]
              (try (spit (.toFile tmp) (:refresh_token r))
                   (Files/setPosixFilePermissions tmp (java.nio.file.attribute.PosixFilePermissions/fromString "rw-------"))
                   (Files/move tmp path (into-array CopyOption [StandardCopyOption/ATOMIC_MOVE StandardCopyOption/REPLACE_EXISTING]))
                   (finally (Files/deleteIfExists tmp)))))
          (swap! tokens assoc provider {:token token :expires (+ (.getEpochSecond (Instant/now)) (:expires_in r 300))}) token)))))
(defn api [provider method path options]
  (let [root (case provider "zoom" "https://api.zoom.us/v2" "google" "https://www.googleapis.com/calendar/v3" "stripe" "https://api.stripe.com/v1"
                  "docusign" (let [root (env "DOCUSIGN_BASE_URL") uri (URI/create root)]
                               (when-not (and (= "https" (.getScheme uri)) (str/ends-with? (.getHost uri) ".docusign.net") (= "/restapi" (.getPath uri))
                                              (nil? (.getUserInfo uri)) (nil? (.getQuery uri))) (error "invalid_docusign_base_url" nil false))
                               (str root "/v2.1/accounts/" (encode (env "DOCUSIGN_ACCOUNT_ID")))))]
    (*transport* (-> options (assoc :method method :url (str root path))
                     (update :headers merge {"Authorization" (str "Bearer " (access-token provider))})))))
(defn request [s u section action input]
  (d/writer! u) (d/privilege! u "edit")
  (let [[provider table] (case [section action] ["appointments" "zoom"] ["zoom" :appointments] ["appointments" "calendar"] ["google" :appointments]
                             ["invoices" "checkout"] ["stripe" :invoices] ["contracts" "sign"] ["docusign" :contracts] (d/fail 404 "Unknown provider action"))
        _ (when-not (contains? (set (str/split (or (System/getenv "INTEGRATIONS_ENABLED") "") #",")) provider) (d/fail 503 "This provider is not enabled"))
        _ (when (contains? #{"stripe" "docusign"} provider) (d/privilege! u "finance_view"))
        _ (when (= provider "stripe") (d/privilege! u "payments_record"))
        _ (when (= provider "docusign") (d/privilege! u "email"))
        r (d/accessible! s u table (:id input)) _ (d/version! r input)
        _ (when-not (contains? (case table :appointments #{"Scheduled"} :invoices #{"Issued"} :contracts #{"Issued" "Viewed"}) (:status r))
            (d/fail 409 "Record state does not allow this provider operation"))
        _ (when-not (:clientId r) (d/fail 400 "Save a client record before connecting a provider"))
        _ (when (some #(and (= provider (:provider %)) (= table (:table %)) (= (:id r) (:recordId %))
                           (contains? #{"Queued" "Running" "Review"} (:status %))) (d/rows s :integrations))
            (d/fail 409 "An active provider operation already exists"))
        _ (when (some #(and (= provider (:provider %)) (= table (:table %)) (= (:id r) (:recordId %))
                            (contains? #{"Active" "Open" "Sent" "Completed"} (:status %))) (d/rows s :integrationLinks))
            (d/fail 409 "This record already has an active provider connection"))
        [s job] (d/insert s :integrations {:provider provider :table table :recordId (:id r) :clientId (:clientId r) :caseId (:caseId r)
                                          :sourceRevision (:revision r) :actorId (:id u) :status "Queued" :attempts 0})]
    [(d/audit s u :integrations job "queued") job]))
(defn retry-job [s u input]
  (d/writer! u) (d/privilege! u "edit")
  (let [r (d/accessible! s u :integrations (:id input))]
    (when (contains? #{"stripe" "docusign"} (:provider r)) (d/privilege! u "finance_view"))
    (when (= "stripe" (:provider r)) (d/privilege! u "payments_record"))
    (when (= "docusign" (:provider r)) (d/privilege! u "email"))
    (when-not (and (contains? #{"Failed" "Review"} (:status r)) (< (:attempts r) 5)) (d/fail 409 "Only failed operations with fewer than five attempts can be retried"))
    (d/replace-row s :integrations r {:status "Queued" :nextAttemptAt nil})))
(defn remote-operation [job r client link]
  (case (:provider job)
    "zoom" (let [marker (subs (auth/digest (str (namespace-id) ":zoom:" (:id job))) 0 24)
                 body {:topic (str (:title r) " [ECC-" marker "]") :type 2 :start_time (:startsAt r) :timezone "UTC"
                       :duration (max 1 (quot (.getSeconds (Duration/between (Instant/parse (:startsAt r)) (Instant/parse (:endsAt r)))) 60))
                       :settings {:waiting_room true :join_before_host false}}
                 host (encode (env "ZOOM_HOST_USER"))
                 found (when (and (not link) (> (:attempts job) 1))
                         (loop [page "" n 0]
                           (let [result (api "zoom" "GET" (str "/users/" host "/meetings?type=scheduled&page_size=300&next_page_token=" (encode page)) {})
                                 found (some #(when (str/includes? (:topic % "") marker) %) (:meetings result))]
                             (if found found (when (and (< n 20) (seq (:next_page_token result))) (recur (:next_page_token result) (inc n)))))))
                 _ (when (and (not link) (> (:attempts job) 1) (not found)) (error "zoom_create_outcome_unknown" nil true))
                 remote-id (or (:remoteId link) (:id found))
                 result (if remote-id
                          (if (= "Cancelled" (:status r)) (do (api "zoom" "DELETE" (str "/meetings/" remote-id) {}) {:id remote-id :join_url ""})
                            (do (api "zoom" "PATCH" (str "/meetings/" remote-id) {:payload body}) (api "zoom" "GET" (str "/meetings/" remote-id) {})))
                          (api "zoom" "POST" (str "/users/" host "/meetings") {:payload body}))]
             (when-not (:id result) (error "invalid_zoom_response" nil true))
             {:remoteId (str (:id result)) :url (:join_url result) :passcode (:password result) :status (if (= "Cancelled" (:status r)) "Cancelled" "Active")})
    "google" (let [remote (or (:remoteId link) (auth/digest (str (namespace-id) ":appointment:" (:id r))))
                   base (str "/calendars/" (encode (env "GOOGLE_CALENDAR_ID")) "/events") path (str base "/" remote)
                   old (try (api "google" "GET" path {}) (catch clojure.lang.ExceptionInfo e (if (contains? #{404 410} (:provider-status (ex-data e))) nil (throw e))))
                   _ (when (and old (not= (namespace-id) (get-in old [:extendedProperties :private :eccNamespace]))) (error "calendar_namespace_mismatch" nil false))
                   body {:summary (:title r) :start {:dateTime (:startsAt r)} :end {:dateTime (:endsAt r)} :location (or (:meetingUrl r) (:location r) "")
                         :visibility "private" :extendedProperties {:private {:eccNamespace (namespace-id) :eccAppointment (str (:id r))}}}
                   result (if (= "Cancelled" (:status r)) (do (when old (api "google" "DELETE" path {})) {})
                            (if old (api "google" "PATCH" path {:payload body :headers {"If-Match" (:etag old)}})
                              (api "google" "POST" base {:payload (assoc body :id remote)})))]
               {:remoteId remote :status (if (= "Cancelled" (:status r)) "Cancelled" "Active") :remoteEtag (:etag result)})
    "stripe" (let [amount (:balanceMinor r) _ (when-not (pos? amount) (error "invoice_not_payable" nil false))
                   _ (when (and (> (:attempts job) 1) (> (.getSeconds (Duration/between (Instant/parse (:createdAt job)) (Instant/now))) (* 23 3600)))
                       (error "checkout_outcome_requires_review" nil true))
                   result (api "stripe" "POST" "/checkout/sessions"
                               {:headers {"Idempotency-Key" (str (namespace-id) ":checkout:" (:id job))}
                                :form-data {"mode" "payment" "client_reference_id" (:id r) "metadata[ecc_namespace]" (namespace-id)
                                            "metadata[ecc_invoice]" (:id r) "metadata[ecc_job]" (:id job)
                                            "line_items[0][price_data][currency]" (str/lower-case (:currency r))
                                            "line_items[0][price_data][unit_amount]" amount "line_items[0][price_data][product_data][name]" (str "ECC invoice #" (:id r))
                                            "line_items[0][quantity]" 1 "success_url" (str (env "PUBLIC_URL") "/#/portal?checkout=returned")
                                            "cancel_url" (str (env "PUBLIC_URL") "/#/portal?checkout=cancelled")}})]
               (when-not (and (:id result) (= "https" (.getScheme (URI/create (:url result)))) (= "checkout.stripe.com" (.getHost (URI/create (:url result)))))
                 (error "invalid_checkout_response" nil true))
               {:remoteId (:id result) :url (:url result) :amountMinor amount :currency (:currency r) :status "Open"})
    "docusign" (let [transaction (auth/digest (str (namespace-id) ":contract:" (:id job)))
                     _ (when (and (:validUntil r) (neg? (compare (:validUntil r) (d/today)))) (error "contract_expired" nil false))
                     _ (when (str/blank? (:email client)) (error "client_email_required" nil false))
                     prior (when (> (:attempts job) 1)
                             (when (> (.getSeconds (Duration/between (Instant/parse (:createdAt job)) (Instant/now))) (* 6 86400))
                               (error "signature_outcome_requires_review" nil true))
                             (first (:envelopes (api "docusign" "GET" (str "/envelopes?transaction_ids=" transaction) {}))))
                     document (html/html [:html [:body [:h1 (:title r)] [:pre (:body r)] [:p (str (:currency r) " " (finance/money (:totalMinor r)))] [:p "Signature: /ecc_sign_here/"]]])
                     result (or prior (api "docusign" "POST" "/envelopes"
                                           {:payload {:emailSubject "ECC contract agreement" :transactionId transaction :status "sent"
                                                      :documents [{:documentBase64 (.encodeToString (Base64/getEncoder) (.getBytes document "UTF-8"))
                                                                   :name "ECC contract" :fileExtension "html" :documentId "1"}]
                                                      :recipients {:signers [{:email (:email client) :name (:fullName client) :recipientId "1" :routingOrder "1"
                                                                             :tabs {:signHereTabs [{:anchorString "/ecc_sign_here/" :anchorUnits "pixels" :anchorXOffset "0" :anchorYOffset "0"}]}}]}}}))]
                 (when-not (:envelopeId result) (error "invalid_signature_response" nil true))
                 {:remoteId (:envelopeId result) :status "Sent"})))
(defn stripe-payment [s session]
  (let [link (some #(when (and (= "stripe" (:provider %)) (= (:id session) (:remoteId %))) %) (d/rows s :integrationLinks))]
    (when-not link (d/fail 409 "Unknown checkout session"))
    (let [meta (:metadata session) invoice (d/record s :invoices (:recordId link))]
      (when-not (and (= (namespace-id) (:ecc_namespace meta)) (= (str (:recordId link)) (:ecc_invoice meta)) (= (str (:jobId link)) (:ecc_job meta))
                     (= (:amount_total session) (:amountMinor link)) (= (str/upper-case (:currency session "")) (:currency link)) (:payment_intent session))
        (d/fail 409 "Checkout identity or amount does not match"))
      (if (or (:paymentId link) (not= "paid" (:payment_status session))) [s {:received true}]
        (let [[s receipt] (finance/payment s {:id 0 :role "admin"} "record"
                                         {:invoiceId (:id invoice) :amount (finance/money (:amountMinor link)) :paidOn (d/today) :method "Card"
                                          :reference (:payment_intent session) :submissionKey (str "stripe:" (:remoteId link))})
              s (update-in s [:integrationLinks (:id link)] merge {:paymentId (:id receipt) :status "Paid" :checkedAt (d/now)})]
          [s {:received true :paymentId (:id receipt)}])))))
(defn hmac [secret text]
  (let [mac (Mac/getInstance "HmacSHA256")] (.init mac (SecretKeySpec. (.getBytes secret "UTF-8") "HmacSHA256"))
    (.formatHex (java.util.HexFormat/of) (.doFinal mac (.getBytes text "UTF-8")))))
(defn verify-stripe [raw header secret]
  (let [pairs (map #(str/split % #"=" 2) (str/split (or header "") #",")) timestamp (some #(when (= "t" (first %)) (d/integer (second %))) pairs)]
    (when-not (and timestamp (<= (abs (- (.getEpochSecond (Instant/now)) timestamp)) 300)
                   (some #(and (= "v1" (first %))
                               (MessageDigest/isEqual (.getBytes (hmac secret (str timestamp "." raw)) "UTF-8") (.getBytes (second %) "UTF-8"))) pairs))
      (d/fail 400 "Invalid webhook signature"))
    (json/parse-string raw true)))
(defn webhook [s event]
  (let [id (d/required event :id 255)]
    (if (get-in s [:providerEvents id]) [s {:received true}]
      (let [[s result] (if (contains? #{"checkout.session.completed" "checkout.session.async_payment_succeeded"} (:type event))
                         (stripe-payment s (get-in event [:data :object])) [s {:received true}])]
        [(assoc-in s [:providerEvents id] {:id id :type (:type event) :receivedAt (d/now)}) result]))))
(declare queue-changes!)
(defn run-jobs! [db]
  (queue-changes! db)
  (doseq [candidate (take 20 (filter #(contains? #{"Queued" "Running"} (:status %)) (d/rows (store/snapshot db) :integrations)))]
    (let [lease (auth/token)
          job (store/transact! db (fn [s]
                                   (let [r (get-in s [:integrations (:id candidate)])
                                         stale? (and (= "Running" (:status r)) (:leaseUntil r) (.isBefore (Instant/parse (:leaseUntil r)) (Instant/now)))
                                         ready? (or (nil? (:nextAttemptAt r)) (.isBefore (Instant/parse (:nextAttemptAt r)) (Instant/now)))]
                                     (if (and (< (:attempts r 0) 5) ready? (or (= "Queued" (:status r)) stale?))
                                       (let [r (assoc r :status "Running" :lease lease :leaseUntil (str (.plusSeconds (Instant/now) 300)) :attempts (inc (:attempts r 0)))]
                                         [(assoc-in s [:integrations (:id r)] r) r]) [s nil]))))]
      (when job
        (try
          (let [s (store/snapshot db) r (d/record s (:table job) (:recordId job))
                _ (when-not (= (:sourceRevision job) (:revision r)) (error "record_changed_before_delivery" nil false))
                r (if (= :invoices (:table job)) (finance/balance s r) r)
                link (some #(when (and (= (:provider job) (:provider %)) (= (:recordId job) (:recordId %))) %) (d/rows s :integrationLinks))
                result (remote-operation job r (d/record s :clients (:clientId job)) link)]
            (store/transact! db (fn [s]
                                 (when-not (= lease (get-in s [:integrations (:id job) :lease])) (d/fail 409 "Provider lease changed"))
                                 (let [data (merge result (select-keys job [:provider :table :recordId :clientId :caseId :sourceRevision]) {:jobId (:id job)})
                                       [s _] (if link (d/replace-row s :integrationLinks (d/record s :integrationLinks (:id link)) data) (d/insert s :integrationLinks data))
                                       s (assoc-in s [:integrations (:id job) :status] "Succeeded")
                                       s (if (= (:provider job) "zoom") (update-in s [:appointments (:recordId job)] merge {:meetingUrl (:url result) :meetingId (:remoteId result) :passcode (:passcode result)}) s)]
                                   [(d/audit s {:id (:actorId job)} :integrations job "delivered") nil]))))
          (catch Exception e
            (store/transact! db (fn [s]
                                 (if (= lease (get-in s [:integrations (:id job) :lease]))
                                   [(update-in s [:integrations (:id job)] merge
                                               {:status (cond (:uncertain? (ex-data e)) "Review" (>= (:attempts job) 5) "Failed" :else "Queued")
                                                :errorCode (or (:code (ex-data e)) "provider_operation_failed")
                                                :nextAttemptAt (str (.plusSeconds (Instant/now) (* 60 (:attempts job))))}) nil] [s nil])))))))))

(defn reconcile! [db]
  (doseq [link (take 50 (filter #(or (and (= "stripe" (:provider %)) (= "Open" (:status %)))
                                    (and (= "docusign" (:provider %)) (= "Sent" (:status %))
                                         (or (nil? (:checkedAt %)) (> (.getSeconds (Duration/between (Instant/parse (:checkedAt %)) (Instant/now))) 960)))
                                    (and (= "google" (:provider %)) (= "Active" (:status %))))
                              (d/rows (store/snapshot db) :integrationLinks)))]
    (try
      (case (:provider link)
        "stripe" (let [result (api "stripe" "GET" (str "/checkout/sessions/" (encode (:remoteId link))) {})]
                   (if (= "paid" (:payment_status result)) (store/transact! db #(stripe-payment % result))
                     (let [s (store/snapshot db) invoice (d/record s :invoices (:recordId link))
                           stale? (or (not= "Issued" (:status invoice)) (not= (:amountMinor link) (:balanceMinor (finance/balance s invoice))) (:deletedAt (get-in s [:clients (:clientId link)])))]
                       (when (and stale? (= "open" (:status result))) (api "stripe" "POST" (str "/checkout/sessions/" (encode (:remoteId link)) "/expire") {}))
                       (store/transact! db #(vector (update-in % [:integrationLinks (:id link)] merge {:checkedAt (d/now)
                                                       :status (if (or stale? (= "expired" (:status result))) "Expired" "Open")}) nil)))))
        "docusign" (let [path (str "/envelopes/" (encode (:remoteId link))) result (api "docusign" "GET" path {})
                         _ (when-not (= (:remoteId link) (:envelopeId result)) (error "signature_identity_mismatch" nil false))
                         status (:status result) pdf (when (= "completed" status) (api "docusign" "GET" (str path "/documents/combined?certificate=true") {:binary? true}))]
                     (store/transact! db (fn [s]
                        (let [current (d/record s :integrationLinks (:id link)) contract (d/record s :contracts (:recordId link))]
                          (if (not= "Sent" (:status current)) [s nil]
                            (let [[s document] (if pdf
                                                (do (when-not (contains? #{"Issued" "Viewed"} (:status contract)) (d/fail 409 "Contract state changed"))
                                                    (files/upload s {:role "admin"} :clients (:clientId link)
                                                                  {:filename (str "signed-contract-" (:recordId link) ".pdf") :content (.encodeToString (Base64/getEncoder) pdf)})) [s nil])
                                  terminal (get {"completed" "Completed" "declined" "Declined" "voided" "Voided"} status "Sent")
                                  s (cond-> s document (update-in [:contracts (:id contract)] merge {:status "Accepted" :acceptedAt (d/now) :revision (inc (:revision contract))}))
                                  [s row] (d/replace-row s :integrationLinks current {:status terminal :checkedAt (d/now) :signedDocumentId (:id document)})]
                              [(if (= terminal "Sent") s (d/audit s nil :contracts contract (str "provider." status))) nil]))))))
        "google" (let [path (str "/calendars/" (encode (env "GOOGLE_CALENDAR_ID")) "/events/" (:remoteId link))
                       remote (try (api "google" "GET" path {}) (catch clojure.lang.ExceptionInfo e (if (contains? #{404 410} (:provider-status (ex-data e))) {:status "cancelled"} (throw e))))]
                   (when (and (not= "cancelled" (:status remote)) (not= (namespace-id) (get-in remote [:extendedProperties :private :eccNamespace])))
                     (error "calendar_namespace_mismatch" nil false))
                   (store/transact! db (fn [s]
                      (let [app (d/record s :appointments (:recordId link)) current (d/record s :integrationLinks (:id link))]
                        (cond
                          (not= (:sourceRevision current) (:revision app))
                          (if (some #(and (= "google" (:provider %)) (= (:id app) (:recordId %)) (contains? #{"Queued" "Running" "Review"} (:status %))) (d/rows s :integrations)) [s nil]
                            (let [[s job] (d/insert s :integrations {:provider "google" :table :appointments :recordId (:id app) :clientId (:clientId app)
                                                                   :sourceRevision (:revision app) :status "Queued" :attempts 0})] [s job]))
                          (= (:remoteEtag current) (:etag remote)) [s nil]
                          :else
                          (let [cancelled? (= "cancelled" (:status remote))
                                _ (when-not cancelled? (let [start (Instant/parse (get-in remote [:start :dateTime])) end (Instant/parse (get-in remote [:end :dateTime]))]
                                                        (when-not (.isAfter end start) (error "calendar_invalid_duration" nil false))))
                                [s row] (d/replace-row s :appointments app (if cancelled? {:status "Cancelled"}
                                                                          {:title (:summary remote) :startsAt (get-in remote [:start :dateTime]) :endsAt (get-in remote [:end :dateTime])}))
                                s (update-in s [:integrationLinks (:id link)] merge {:sourceRevision (:revision row) :remoteEtag (:etag remote) :checkedAt (d/now)
                                                                                    :status (if cancelled? "Cancelled" "Active")})]
                            [(d/audit s nil :appointments row "calendar.updated") nil]))))))
        nil)
      (catch Exception e
        (store/transact! db #(vector (update-in % [:integrationLinks (:id link)] merge {:checkedAt (d/now) :errorCode (or (:code (ex-data e)) "provider_reconciliation_failed")}) nil))))))

(defn queue-changes! [db]
  (store/transact! db (fn [s]
    [(reduce (fn [s link]
               (let [app (get-in s [:appointments (:recordId link)])]
                 (if (and (contains? #{"zoom" "google"} (:provider link)) (= "Active" (:status link)) app
                          (not= (:sourceRevision link) (:revision app))
                          (not (some #(and (= (:provider link) (:provider %)) (= (:id app) (:recordId %))
                                           (contains? #{"Queued" "Running" "Review"} (:status %))) (d/rows s :integrations))))
                   (first (d/insert s :integrations {:provider (:provider link) :table :appointments :recordId (:id app) :clientId (:clientId app)
                                                     :caseId (:caseId app) :sourceRevision (:revision app) :status "Queued" :attempts 0})) s)))
             s (d/rows s :integrationLinks)) nil])))
