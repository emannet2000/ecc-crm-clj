(ns ecc-crm.migration
  (:require [cheshire.core :as json]
            [clojure.string :as str]
            [ecc-crm.domain :as d]
            [ecc-crm.files :as files])
  (:import [java.util Base64]
           [java.time YearMonth]
           [java.nio.file Files OpenOption]
           [java.security MessageDigest]))
(def table-map
  {:users :users :leads :leads :clients :clients :cases :cases :tasks :tasks :activities :activities
   :documents :documents :audit_log :audit :work_history :history :document_requests :checklists
   :reminder_rules :reminderRules :saved_views :savedViews :appointments :appointments :invoices :invoices
   :invoice_payments :payments :expenses :expenses :financial_periods :periods :bank_lines :bankEntries
   :application_milestones :milestones :client_messages :messages :mail_outbox :mail :notifications :notifications
   :portal_links :portalLinks :checklist_templates :templates :integration_jobs :integrations :integration_links :integrationLinks :integration_events :integrationEvents
   :student_profiles :profiles :student_photos :studentPhotos :client_photos :clientPhotos
   :checklist_template_items :templateItems :applied_checklist_items :appliedTemplates :notification_preferences :preferences
   :bank_matches :bankMatches :bank_statements :bankStatements :expense_entries :expenseEntries :finance_audit :financeAudit
   :business_events :businessEvents :mfa_recovery_codes :legacyRecoveryCodes :payment_instructions :paymentInstructions :portal_document_grants :portalGrants})
(defn camel [k]
  (keyword (str/replace (name k) #"_([a-z])" (fn [[_ c]] (str/upper-case c)))))
(defn normalize [row]
  (into {} (for [[k v] row] [(camel k) (cond (contains? #{:clientVisible :required :enabled :assignments :deadlines :documents :escalations :emailEnabled :mine :overdue} (camel k)) (contains? #{true 1 "true"} v)
                            (and (string? v) (re-matches #"\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}" v))
                                 (str (str/replace v " " "T") "Z") :else v)])))
(defn file! [row]
  (let [data (get-in row [:content :$binary])
        bytes (when data (.decode (Base64/getDecoder) data))]
    (if bytes
      (let [hash (.formatHex (java.util.HexFormat/of) (.digest (MessageDigest/getInstance "SHA-256") bytes))
            f (files/blob-path hash)]
        (.mkdirs (.getParentFile f))
        (when-not (.exists f) (Files/write (.toPath f) bytes (make-array OpenOption 0)))
        (-> row (dissoc :content) (assoc :hash hash :scanStatus "Quarantined"))) row)))
(defn import-state [input]
  (when-not (contains? #{"ecc-sqlite-v1" "ecc-postgresql-v1"} (:format input)) (d/fail 400 "Unsupported export format"))
  (let [tables (:tables input)
        initial (reduce-kv
                  (fn [s source target]
                    (let [records (for [[source-index record] (map-indexed vector (get tables source))]
                                    (let [r (normalize record)
                                          r (assoc r :revision (or (:revision r) 1))
                                          r (cond-> r
                                              (contains? #{:profiles :preferences} target) (assoc :id (or (:id r) (:clientId r) (:userId r)))
                                              (= target :cases) (assoc :dueDate (:nextDeadline r) :status (or (:status r) (:stage r)))
                                              (= target :milestones) (assoc :dueDate (:plannedOn r) :description (:note r) :clientId (get-in s [:cases (:caseId r) :clientId]))
                                              (= target :profiles) (assoc :dateOfBirth (:birthDate r))
                                              (= target :bankEntries) (assoc :date (:postedOn r) :status "Unmatched")
                                              (= target :templates) (assoc :title (:name r))
                                              (= target :savedViews) (assoc :title (:name r))
                                              (= target :expenses) (assoc :status (if (= "Pending" (:status r)) "Submitted" (:status r)))
                                              (contains? #{:integrations :integrationLinks} target) (assoc :table (get {"appointment" :appointments "invoice" :invoices "contract" :contracts} (:recordKind r)) :lease (:leaseToken r))
                                              (= target :periods) (assoc :id (inc source-index) :from (str (:month r) "-01") :to (str (.atEndOfMonth (YearMonth/parse (:month r)))) :status (if (contains? #{true 1} (:closed r)) "Closed" "Open"))
                                              (:caseOfficerId r) (assoc :consultantId (:caseOfficerId r))
                                              (:assignedToId r) (assoc :assignedTo (:assignedToId r))
                                              (:mfaSecret r) (assoc :mfaAlgorithm "HmacSHA256")
                                              (:mfaLastStep r) (assoc :mfaCounter (:mfaLastStep r))
                                              (contains? r :suspended) (assoc :suspended (contains? #{1 true} (:suspended r)))
                                              (= target :activities) (assoc :kind (:type r))
                                              (= target :mail) (assoc :to (:recipient r) :status (if (:sentAt r) "Sent" "Queued")))]
                                      (if (= target :documents) (file! r) r)))
                          by-id (into {} (map-indexed (fn [index row] [(or (:id row) (:clientId row) (:userId row) (:studentId row) (str "legacy-" index)) row]) records))]
                      (-> s (assoc target by-id) (assoc-in [:counters target] (reduce max 0 (filter integer? (keys by-id)))))))
                  {:legacy (into {} (for [[table records] tables [index row] (map-indexed vector records)] [[table index] row])) :sessions {} :migration {:from (if (= "ecc-postgresql-v1" (:format input)) "postgresql" "sqlite") :importedAt (d/now)
                                                         :counts (into {} (map (fn [[k v]] [k (count v)]) tables))}} table-map)
        initial (reduce-kv (fn [s source target]
                             (update-in s [:counters target] max (get (:sequences input) source 0))) initial table-map)
        initial (reduce (fn [s r]
                          (let [r (normalize r) privileges (try (json/parse-string (:privileges r)) (catch Exception _ []))]
                            (-> s (assoc-in [:users (:userId r) :accessLevel] (:accessLevel r))
                                (assoc-in [:users (:userId r) :privileges] privileges)))) initial (:user_access tables))]
    (let [initial (assoc initial :portalGrants (into {} (for [record (:portal_document_grants tables) :let [r (normalize record)]] [[(:linkId r) (:documentId r)] r])))
          initial (reduce (fn [s [id row]] (assoc-in s [:milestones id :clientId] (get-in s [:cases (:caseId row) :clientId]))) initial (:milestones initial))
          initial (reduce (fn [s row]
                            (let [row (normalize row)]
                              (if (str/starts-with? (:kind row "") "communication_")
                                (-> s (assoc-in [:contacts (:id row)] (assoc row :description (:note row) :title (str/replace (:kind row) "_" " ") :contactedAt (:createdAt row)))
                                    (update-in [:counters :contacts] (fnil max 0) (:id row))) s))) initial (:work_history tables))
          initial (reduce (fn [s record]
                            (let [r (normalize record) [s _] (d/insert s :audit {:entityType (get {"invoice" "invoices" "payment" "payments" "expense" "expenses" "period" "periods"} (:kind r) (:kind r))
                                                                              :entityId (:recordId r) :action (:action r) :changes (:details r) :actorId (:actorId r) :date (:createdAt r)})] s)) initial (:finance_audit tables))
          initial (reduce (fn [s record]
                            (let [r (normalize record) table (if (= "proposal" (:kind r)) :proposals :contracts)
                                  r (assoc r :revision (:revision r 1))]
                              (-> s (assoc-in [table (:id r)] r) (update-in [:counters table] (fnil max 0) (:id r))))) initial (:commercial_documents tables))
          initial (reduce (fn [s [id payment]]
                            (let [invoice (get-in s [:invoices (:invoiceId payment)])]
                              (update-in s [:payments id] merge {:clientId (:clientId invoice) :currency (:currency invoice)}))) initial (:payments initial))
          initial (reduce (fn [s record]
                            (let [r (normalize record) key [(:caseId r) (:templateId r) (str/lower-case (:titleKey r))]]
                              (assoc-in s [:appliedTemplates key] (:requestId r)))) initial (:applied_checklist_items tables))
          initial (reduce (fn [s record]
                            (let [r (normalize record)]
                              (update-in s [:bankEntries (:bankLineId r)] merge {:status (if (contains? #{true 1} (:ignored r)) "Ignored" "Matched")
                                       :matchKind (if (:paymentId r) "payment" "expense")
                                       :entryId (or (:paymentId r) (get-in s [:expenseEntries (:expenseEntryId r) :expenseId])) :reason (:reason r)}))) initial (:bank_matches tables))
          initial (reduce (fn [s record]
                            (let [r (file! (normalize record)) id (inc (get-in s [:counters :documents] 0)) r (assoc r :id id :revision 1)]
                              (-> s (assoc-in [:documents id] r) (assoc-in [:legacyFileIds (:id record)] id) (assoc-in [:counters :documents] id)))) initial (:financial_files tables))
          initial (reduce (fn [s record]
                            (let [r (normalize record)]
                              (-> s (assoc-in [:clients (:clientId r) :photoId] (:documentId r)) (assoc-in [:documents (:documentId r) :photo] true))))
                          initial (concat (:student_photos tables) (:client_photos tables)))
          initial (reduce (fn [s record] (let [r (normalize record)] (update-in s [:users (:userId r) :recoveryCodes] (fnil conj []) (:codeHash r)))) initial (:mfa_recovery_codes tables))]
      (reduce (fn [s r]
                (let [r (normalize r)]
                  (-> s (assoc-in [:checklists (:requestId r) :documentId] (:documentId r))
                      (update-in [:checklists (:requestId r) :versions] (fnil conj []) (:documentId r))))) initial
              (sort-by :version (map normalize (:document_versions tables)))))))
