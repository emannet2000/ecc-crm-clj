(ns ecc-crm.completion-test
  (:require [clojure.test :refer :all] [cheshire.core :as json]
            [ecc-crm.domain :as d] [ecc-crm.auth :as auth] [ecc-crm.store :as store]
            [ecc-crm.crm-extra :as crm] [ecc-crm.finance :as f] [ecc-crm.finance-extra :as controls]
            [ecc-crm.reports :as reports] [ecc-crm.integrations :as integrations]
            [ecc-crm.workers :as workers] [ecc-crm.workflows :as workflows]
            [ecc-crm.http :as http] [ecc-crm.mfa :as mfa] [ecc-crm.migration :as migration] [ecc-crm.markup :as markup] [ecc-crm.release :as release] [ecc-crm.backup :as backup] [ecc-crm.files :as files]
            [clojure.java.io :as io] [ecc-crm.domain-test :refer [request]])
  (:import [java.time Instant LocalDate]))
(def admin {:id 1 :name "Admin" :role "admin"})
(defn status [f] (try (f) 200 (catch clojure.lang.ExceptionInfo e (:status (ex-data e)))))
(defn prepared []
  (let [[s c] (d/save-person {} admin :clients {:fullName "Student" :email "student@example.com"})
        [s invoice] (f/invoice-save s admin {:clientId (:id c) :subtotal "100" :currency "PHP" :dueDate "2027-01-01"})
        [s _] (f/issue-invoice s admin {:id (:id invoice)})]
    [s c invoice]))
(deftest reconciliation-and-export
  (let [[s c invoice] (prepared)
        [s receipt] (f/payment s admin "record" {:invoiceId (:id invoice) :amount "100" :paidOn (d/today) :submissionKey "payment"})
        input {:account "Operating" :csv (str "date,amount,currency,reference\n" (d/today) ",100.00,PHP,BANK-1\n")}
        [s imported] (controls/reconciliation s admin "import" input)
        [s duplicate] (controls/reconciliation s admin "import" input)
        [s line] (controls/reconciliation s admin "match" {:id (:id (first imported)) :entryId (:id receipt) :kind "payment"})]
    (is (= 1 (count imported))) (is (empty? duplicate)) (is (= "Matched" (:status line)))
    (is (= 409 (status #(controls/reconciliation s admin "match" {:id (:id line) :entryId (:id receipt)}))))
    (is (= 403 (status #(controls/reconciliation s {:id 2 :role "viewer"} "ignore" {:id (:id line)}))))
    (is (= 400 (status #(controls/reconciliation s admin "unmatch" {:id (:id line)}))))
    (let [[s row] (controls/reconciliation s admin "unmatch" {:id (:id line) :reason "Correction"})]
      (is (= "Unmatched" (:status row))))
    (is (= "100.00" (:collected (first (reports/finance-summary s admin "")))))
    (is (seq (controls/history s admin :invoices (:id invoice))))
    (is (= false (get (controls/permissions {:id 2 :role "viewer"}) "record")))))
(deftest templates-profiles-saved-views-and-conflicts
  (let [[s client] (d/save-person {} admin :clients {:fullName "Student"})
        [s app] (d/insert s :cases {:clientId (:id client) :title "Application"})
        [s template] (d/insert s :templates {:title "Visa" :items [{:title "Passport"} {:title "Transcript"}]})
        [s created] (crm/apply-template s admin {:applicationId (:id app) :templateId (:id template)})
        [s duplicate] (crm/apply-template s admin {:applicationId (:id app) :templateId (:id template)})
        [s profile] (crm/profile s admin {:clientId (:id client) :nationality "Filipino"})
        [s view] (crm/saved-view s admin "save" {:title "Students" :entity "clients" :query "Student"})]
    (is (= 2 (count created))) (is (empty? duplicate))
    (is (= "Filipino" (:nationality profile)))
    (is (= 409 (status #(crm/profile s admin {:clientId (:id client) :nationality "Changed" :revision 0}))))
    (is (= 1 (count (:rows (second (crm/saved-view s admin "apply" {:id (:id view)}))))))
    (is (= 404 (status #(crm/saved-view s {:id 2} "apply" {:id (:id view)}))))
    (is (= (:revision client) (:revision (crm/conflict s admin :clients (:id client)))))))
(deftest invitation-and-recovery-code-consumption
  (let [db (store/memory-store)
        _ (store/transact! db #(auth/create-user % nil {:name "Admin" :role "admin" :email "admin@example.com" :password "a-long-enough-password"}))
        raw "RECOVERY-ONE"
        _ (store/transact! db #(vector (-> % (assoc-in [:users 1 :mfaSecret] "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ")
                                           (assoc-in [:users 1 :recoveryCodes] [(auth/digest raw)])) nil))
        login (auth/login! db {:email "admin@example.com" :password "a-long-enough-password" :recoveryCode raw} "test")]
    (is (= 1 (get-in login [:user :id])))
    (is (empty? (get-in (store/snapshot db) [:users 1 :recoveryCodes])))
    (is (= 401 (status #(auth/login! db {:email "admin@example.com" :password "a-long-enough-password" :recoveryCode raw} "test"))))
    (let [[s response] (crm/invite (store/snapshot db) admin {:email "invite@example.com" :name "Invited" :role "consultant"} "https://example.com")]
      (is (= 1 (count (:mail s)))) (is (= 2 (count (:users s))))
      (is (not (contains? response :token)))
      (is (= 403 (status #(crm/security-admin s admin "reset-mfa" {:user 2 :password "wrong"}))))
      (let [[s _] (crm/security-admin s admin "suspend" {:user 2 :password "a-long-enough-password"})]
        (is (true? (get-in s [:users 2 :suspended])))))))
(deftest reminders-email-and-preference-deduplication
  (let [db (store/memory-store)
        _ (store/transact! db #(vector (assoc % :users {1 (assoc admin :email "admin@example.com")}
                                             :tasks {1 {:id 1 :title "Deadline" :assignedTo 1 :status "Pending" :dueDate (d/today)}}
                                             :reminderRules {1 {:id 1 :taskId 1 :daysBefore 1 :enabled true}}) nil))]
    (workers/reminders! db) (workers/reminders! db)
    (is (= 1 (count (:mail (store/snapshot db)))))
    (is (= 3 (count (:notifications (store/snapshot db)))))
    (store/transact! db #(vector (assoc-in % [:preferences 1] {:emailEnabled false}) nil))
    (store/transact! db #(vector (assoc-in % [:tasks 1 :dueDate] (str (.plusDays (LocalDate/parse (d/today)) 1))) nil))
    (workers/reminders! db)
    (is (= 1 (count (:mail (store/snapshot db)))))))
(deftest signed-webhook-deduplicates-payments
  (with-redefs [integrations/namespace-id (constantly "test")]
    (let [[s client invoice] (prepared)
          [s link] (d/insert s :integrationLinks {:provider "stripe" :remoteId "cs_test" :recordId (:id invoice) :clientId (:id client)
                                                 :jobId 4 :amountMinor 10000 :currency "PHP" :status "Open"})
          event {:id "evt_one" :type "checkout.session.completed" :data {:object {:id "cs_test" :payment_status "paid" :amount_total 10000
                  :currency "php" :payment_intent "pi_test" :metadata {:ecc_namespace "test" :ecc_invoice (str (:id invoice)) :ecc_job "4"}}}}
          raw (json/generate-string event) timestamp (.getEpochSecond (Instant/now))
          signature (str "t=" timestamp ",v1=" (integrations/hmac "secret" (str timestamp "." raw)))
          verified (integrations/verify-stripe raw signature "secret")
          [s _] (integrations/webhook s verified) [s _] (integrations/webhook s verified)]
      (is (= 1 (count (:payments s)))) (is (= "Paid" (get-in s [:integrationLinks (:id link) :status])))
      (is (= 400 (status #(integrations/verify-stripe (str raw " ") signature "secret"))))
      (is (= 409 (status #(integrations/stripe-payment s (assoc-in (get-in event [:data :object]) [:metadata :ecc_namespace] "other"))))))))
(deftest provider-retry-does-not-repeat-uncertain-create
  (let [calls (atom []) job {:id 1 :attempts 2 :provider "zoom"} record {:id 1 :title "Meeting" :startsAt "2026-10-24T01:00:00Z" :endsAt "2026-10-24T02:00:00Z"}]
    (with-redefs [integrations/namespace-id (constantly "test") integrations/env (fn [_] "fixture")
                  integrations/api (fn [provider method path options] (swap! calls conj [method path options]) {:meetings []})]
      (is (try (integrations/remote-operation job record {} nil) false (catch clojure.lang.ExceptionInfo e (:uncertain? (ex-data e)))))
      (is (every? #(= "GET" (first %)) @calls)))))
(deftest workspace-route-precedence-and-permission-enforcement
  (let [db (store/memory-store)
        _ (store/transact! db #(auth/create-user % nil {:name "Admin" :email "admin@example.com" :role "admin" :password "a-long-enough-password"}))
        token (:token (auth/login! db {:email "admin@example.com" :password "a-long-enough-password"} "test"))
        app (http/app db {:public-url "http://localhost:4000"})]
    (is (= 200 (:status (request app :get "/api/workspace/team-access" nil token))))
    (is (= 200 (:status (request app :get "/api/workspace/calendar.ics" nil token))))
    (is (= 200 (:status (request app :get "/api/workspace/reports.csv" nil token))))
    (is (= 200 (:status (request app :get "/api/workspace/finance-export/cashflow" nil token))))))

(deftest streaming-backup-and-empty-target-restore
  (let [directory (str (java.nio.file.Files/createTempDirectory "ecc-backup-test-" (make-array java.nio.file.attribute.FileAttribute 0)))
        source (store/memory-store) target (store/memory-store)]
    (store/transact! source #(d/save-person % admin :clients {:fullName "Backup student"}))
    (let [result (backup/write! source (str directory "/snapshot.zip"))]
      (is (= 64 (count (:sha256 result))))
      (is (= 409 (status #(backup/write! source (str directory "/snapshot.zip")))))
      (is (:restored (backup/restore! target (:path result))))
      (is (= (store/snapshot source) (store/snapshot target))))))

(deftest printed-documents-escape-client-text
  (let [document (markup/html [:html [:body [:h1 "<script>alert(1)</script>"] [:pre "<img src=x onerror=alert(1)>"]]])]
    (is (not (clojure.string/includes? document "<script>")))
    (is (clojure.string/includes? document "&lt;script&gt;"))))
(deftest deterministic-calendar-and-signature-recovery
  (let [calls (atom []) existing (atom false)
        record {:id 7 :title "Meeting" :notes "Private staff notes" :startsAt "2026-10-24T01:00:00Z" :endsAt "2026-10-24T02:00:00Z" :status "Scheduled"}]
    (with-redefs [integrations/namespace-id (constantly "fixture") integrations/env (fn [_] "fixture")
                  integrations/api (fn [provider method path options]
                                     (swap! calls conj [provider method path options])
                                     (if (= method "GET")
                                       (if @existing {:etag "etag" :extendedProperties {:private {:eccNamespace "fixture"}}}
                                         (throw (ex-info "missing" {:provider-status 404})))
                                       (do (reset! existing true) {:etag "next"}))) ]
      (let [first (integrations/remote-operation {:id 1 :provider "google" :attempts 1} record {} nil)
            retried (integrations/remote-operation {:id 1 :provider "google" :attempts 2} record {} first)]
        (is (= (:remoteId first) (:remoteId retried)))
        (is (= 1 (count (filter #(= "POST" (second %)) @calls))))
        (is (not (clojure.string/includes? (pr-str @calls) "Private staff notes"))))))
  (let [calls (atom [])]
    (with-redefs [integrations/namespace-id (constantly "fixture")
                  integrations/api (fn [provider method path options] (swap! calls conj method) {:envelopes [{:envelopeId "existing-envelope"}]})]
      (let [result (integrations/remote-operation {:id 9 :provider "docusign" :attempts 2 :createdAt (d/now)}
                                                {:title "Contract" :body "Terms" :validUntil "2027-12-31" :currency "PHP" :totalMinor 100}
                                                {:email "fixture@example.com" :fullName "Fixture"} nil)]
        (is (= "existing-envelope" (:remoteId result)))
        (is (= ["GET"] @calls))))))
(deftest release-manifest-detects-changed-files
  (let [directory (str (java.nio.file.Files/createTempDirectory "ecc-release-check-" (make-array java.nio.file.attribute.FileAttribute 0)))
        backend (io/file directory "backend/src/ecc_crm/main.clj") deps (io/file directory "backend/deps.edn")
        frontend (io/file directory "frontend/public/js/main.js") manifest (str directory "/release.json")]
    (.mkdirs (.getParentFile backend)) (.mkdirs (.getParentFile frontend))
    (spit backend "(ns fixture)") (spit deps "{}") (spit frontend "console.log('fixture')")
    (release/generate! directory manifest)
    (is (:verified (release/verify! directory manifest)))
    (spit frontend "changed")
    (is (= 500 (status #(release/verify! directory manifest))))))

(deftest static-files-are-mounted-outside-the-router
  (let [directory (str (java.nio.file.Files/createTempDirectory "ecc-static-test-" (make-array java.nio.file.attribute.FileAttribute 0)))
        _ (spit (io/file directory "index.html") "<!doctype html><p>Static fixture</p>")
        _ (spit (io/file directory "app.css") "body{color:green}")
        app (http/app (store/memory-store) {:public-url "http://localhost:4000" :web-dist directory})
        root (request app :get "/" nil nil) css (request app :get "/app.css" nil nil)]
    (is (= 200 (:status root)))
    (is (clojure.string/includes? (slurp (:body root)) "Static fixture"))
    (is (= 200 (:status css)))
    (is (clojure.string/includes? (get-in css [:headers "Content-Type"] (get-in css [:headers "content-type"] "")) "text/css"))
    (is (not= 200 (:status (request app :get "/../deps.edn" nil nil))))))

(deftest imported-ledgers-periods-profiles-and-authenticators
  (let [secret "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ" password "legacy-fixture-password" raw "Legacy_Code_One"
        legacy-hash (.encodeToString (.withoutPadding (java.util.Base64/getUrlEncoder))
                         (.digest (java.security.MessageDigest/getInstance "SHA-256") (.getBytes raw "UTF-8")))
        input {:format "ecc-sqlite-v1" :tables
               {:users [{:id 1 :name "Legacy Admin" :email "legacy@example.com" :role "admin" :password_hash (auth/hash-password password)
                         :suspended 0 :mfa_secret secret :mfa_last_step -1}]
                :mfa_recovery_codes [{:user_id 1 :code_hash legacy-hash}]
                :clients [{:id 1 :full_name "Legacy student" :case_officer_id 1}]
                :cases [{:id 1 :client_id 1}]
                :student_profiles [{:client_id 1 :birth_date "2000-01-01" :nationality "Filipino" :revision 2}]
                :invoices [{:id 1 :client_id 1 :currency "PHP" :amount_minor 100000 :status "Issued" :due_date "2027-01-01"}]
                :invoice_payments [{:id 1 :invoice_id 1 :amount_minor 40000 :paid_on "2026-10-24"}]
                :expenses [{:id 1 :supplier "Vendor" :currency "PHP" :amount_minor 1000 :status "Paid"}]
                :expense_entries [{:id 1 :expense_id 1 :amount_minor 1000 :posted_on "2026-10-24"}]
                :financial_periods [{:month "2026-01" :closed 1 :revision 3}]
                :commercial_documents [{:id 3 :kind "proposal" :client_id 1 :case_id 1 :title "Proposal" :total_minor 100000 :currency "PHP" :status "Issued"}
                                       {:id 4 :kind "contract" :client_id 1 :case_id 1 :title "Contract" :total_minor 100000 :currency "PHP" :status "Accepted"}]
                :bank_lines [{:id 1 :posted_on "2026-10-24" :amount_minor 40000 :currency "PHP"}]
                :bank_matches [{:bank_line_id 1 :payment_id 1 :ignored 0 :reason "Original match"}]
                :appointments [{:id 1 :client_id 1 :client_visible 0}]
                :notification_preferences [{:user_id 1 :email_enabled 0 :assignments 1}]}}
        state (migration/import-state input) db (store/memory-store)
        _ (store/transact! db (fn [_] [state nil]))
        counter (quot (.getEpochSecond (Instant/now)) 30)
        code (mfa/code secret counter "HmacSHA256")]
    (is (= "HmacSHA256" (get-in state [:users 1 :mfaAlgorithm])))
    (is (= "2000-01-01" (get-in state [:profiles 1 :dateOfBirth])))
    (is (= "PHP" (get-in state [:payments 1 :currency])))
    (is (= 60000 (:balanceMinor (f/balance state (d/record state :invoices 1)))))
    (is (= "Closed" (get-in state [:periods 1 :status])))
    (is (= 409 (status #(f/open-period! state "2026-01-10"))))
    (is (= "Proposal" (get-in state [:proposals 3 :title])))
    (is (= "Accepted" (get-in state [:contracts 4 :status])))
    (is (= "Matched" (get-in state [:bankEntries 1 :status])))
    (is (= 1 (get-in state [:bankEntries 1 :entryId])))
    (is (false? (get-in state [:appointments 1 :clientVisible])))
    (is (false? (get-in state [:preferences 1 :emailEnabled])))
    (is (= 1 (get-in (auth/login! db {:email "legacy@example.com" :password password :otp code} "fixture") [:user :id])))
    (is (= 401 (status #(auth/login! db {:email "legacy@example.com" :password password :otp code} "fixture"))))
    (is (= 1 (get-in (auth/login! db {:email "legacy@example.com" :password password :recoveryCode raw} "fixture") [:user :id])))
    (is (empty? (get-in (store/snapshot db) [:users 1 :recoveryCodes])))))

(deftest profile-photo-is-normalized-and-quarantined
  (let [directory (str (java.nio.file.Files/createTempDirectory "ecc-photo-test-" (make-array java.nio.file.attribute.FileAttribute 0)))
        image (java.awt.image.BufferedImage. 2 2 java.awt.image.BufferedImage/TYPE_INT_RGB)
        out (java.io.ByteArrayOutputStream.) _ (javax.imageio.ImageIO/write image "png" out)
        [s client] (d/save-person {} admin :clients {:fullName "Photo fixture"})]
    (with-redefs [files/directory (constantly directory)]
      (let [[s response] (crm/photo s admin (:id client) {:content (.encodeToString (java.util.Base64/getEncoder) (.toByteArray out))})
            document (get-in s [:documents (:documentId response)])]
        (is (= "Quarantined" (:scanStatus document)))
        (is (:photo document))
        (is (= (:id document) (get-in s [:clients (:id client) :photoId])))
        (is (some? (javax.imageio.ImageIO/read (files/blob-path (:hash document)))))))))

(deftest personal-security-and-communication-dont-leak-records
  (let [[s lead] (d/save-person {} admin :leads {:fullName "Private student"})
        [s mail] (workflows/action s admin "communication" "send" {:leadId (:id lead) :to "fixture@example.com" :subject "Fixture" :body "Fixture body"})]
    (is (empty? (:options (workflows/section s admin "security" {}))))
    (is (= 1 (count (:rows (workflows/section s admin "communication" {})))))
    (is (empty? (:rows (workflows/section s {:id 2 :role "consultant"} "communication" {}))))
    (is (not (workflows/visible-row? s {:id 2 :role "consultant"} :integrations {:provider "stripe" :clientId 1})))))
