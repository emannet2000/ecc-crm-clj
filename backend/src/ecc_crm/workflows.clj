(ns ecc-crm.workflows
  (:require [clojure.string :as str]
            [ecc-crm.domain :as d]
            [ecc-crm.finance :as finance]
            [ecc-crm.auth :as auth]
            [ecc-crm.portal :as portal]
            [ecc-crm.crm-extra :as crm]
            [ecc-crm.finance-extra :as controls]
            [ecc-crm.reports :as reports]
            [ecc-crm.integrations :as integrations])
  (:import [java.time Instant LocalDate]))

(def sections
  {"applications" :cases "tasks" :tasks "history" :activities "documents" :checklists
   "appointments" :appointments "milestones" :milestones "contact-log" :contacts
   "checklist-templates" :templates "reminders" :reminderRules "invoices" :invoices
   "proposals" :proposals "contracts" :contracts "payments" :payments "balances" :invoices
   "expenses" :expenses "periods" :periods "reconciliation" :bankEntries
   "client-messages" :messages "communication" :mail "mail" :mail "notifications" :notifications
   "payment-instructions" :paymentInstructions "portal" :portalLinks "integrations" :integrations})
(def admin-sections #{"mail" "reports" "ageing" "bottlenecks" "trends" "merge" "finance-audit" "invoices"})
(def financial-sections #{"payments" "balances" "expenses" "periods" "reconciliation" "cashflow" "finance-audit" "payment-instructions"})
(defn options [s u]
  (vec (concat
         (for [table [:leads :clients :cases] r (:rows (d/list-records s u table {"limit" "100"}))]
           {:value (str (case table :leads "lead:" :clients "client:" :cases "case:") (:id r)) :label (or (:fullName r) (:title r) (str "Application #" (:id r)))})
         (for [r (d/rows s :users) :when (not (:suspended r))]
           {:value (str "staff:" (:id r)) :label (:name r)}))))
(defn stats [s u]
  (let [leads (filter #(d/visible? s u :leads %) (d/rows s :leads))
        clients (filter #(d/visible? s u :clients %) (d/rows s :clients))
        tasks (filter #(d/visible? s u :tasks %) (d/rows s :tasks))]
    {:totalLeads (count leads) :totalClients (count clients)
     :openTasks (count (remove #(contains? #{"Done" "Cancelled"} (:status %)) tasks))
     :convertedLeads (count (filter :convertedClientId leads))
     :byStage (mapv (fn [[stage rs]] {:stage stage :count (count rs)}) (group-by :stage leads))
     :bySource (mapv (fn [[source rs]] {:source source :count (count rs)}) (group-by :source leads))}))
(defn visible-row? [s u table row]
  (cond
    (= table :mail) (or (= "admin" (:role u)) (= (:id u) (:createdBy row)))
    (and (= table :integrations) (contains? #{"stripe" "docusign"} (:provider row)))
    (and (try (d/privilege! u "finance_view") true (catch clojure.lang.ExceptionInfo _ false)) (d/visible? s u table row))
    (= table :templates) true
    (= table :notifications) (= (:id u) (:userId row))
    (= table :periods) true
    (= table :expenses) true
    :else (d/visible? s u table row)))
(defn section [s u name params]
  (when (admin-sections name) (d/admin! u))
  (when (financial-sections name) (d/privilege! u "finance_view"))
  (let [rows (case name
               "history" (concat (filter #(d/visible? s u :activities %) (d/rows s :activities))
                                 (filter #(d/visible? s u :history %) (d/rows s :history)))
               "reports" (reports/rows s u name (get params "q" ""))
               "ageing" (reports/rows s u name "")
               "bottlenecks" (reports/rows s u name "")
               "trends" (reports/rows s u name (get params "q" ""))
               "cashflow" (reports/rows s u name (get params "q" ""))
               "sales" (reports/rows s u name (get params "q" ""))
               "payment-history" (reports/rows s u "payments" "")
               "security" (map (fn [[k r]] (assoc (dissoc r :userId) :id (subs k 0 16)))
                               (filter #(= (:id u) (:userId (val %))) (:sessions s)))
               "finance-audit" (filter #(contains? #{"payments" "invoices" "expenses" "periods"} (:entityType %)) (d/rows s :audit))
               "search" (for [t [:leads :clients :tasks :cases] r (d/rows s t) :when (d/visible? s u t r)]
                          (assoc r :kind (name t) :title (or (:fullName r) (:title r))))
               (if-let [table (sections name)]
                 (->> (d/rows s table)
                      (filter #(visible-row? s u table %))
                      (map #(if (= table :invoices) (finance/balance s %) %)))
                 (d/fail 404 "Workspace section not found")))
        q (if (contains? #{"reports" "trends" "cashflow" "sales"} name) "" (str/lower-case (get params "q" "")))
        rows (filter #(str/includes? (str/lower-case (pr-str %)) q) rows)
        offset (max 0 (or (d/integer (get params "offset")) 0))]
    {:rows (vec (take 50 (drop offset (sort-by #(str (:id %)) rows))))
     :total (count rows) :options (if (= name "security") [] (options s u)) :submissionKey (auth/token)
     :preferences (get-in s [:preferences (:id u)])
     :permissions (controls/permissions u)}))
(defn owned-save [s u table input fields defaults]
  (let [old (when (:id input) (d/accessible! s u table (:id input)))
        input (d/owner-input s u (merge old input))]
    (d/save! s u table input (into [:leadId :clientId :caseId :title] fields) defaults)))
(defn appointment [s u input]
  (let [start (try (Instant/parse (:startsAt input)) (catch Exception _ (d/fail 400 "Start time must include a timezone")))
        end (try (Instant/parse (:endsAt input)) (catch Exception _ (d/fail 400 "End time must include a timezone")))]
    (when-not (.isAfter end start) (d/fail 400 "Meeting end must follow its start"))
    (when (some #(and (not= (d/integer (:id input)) (:id %)) (= (:assignedTo input (:id u)) (:assignedTo %))
                     (not= "Cancelled" (:status %))
                     (.isBefore start (Instant/parse (:endsAt %))) (.isAfter end (Instant/parse (:startsAt %))))
                (d/rows s :appointments)) (d/fail 409 "This appointment overlaps another meeting"))
    (owned-save s u :appointments input [:startsAt :endsAt :location :notes :meetingUrl :assignedTo :clientVisible :status]
                {:status "Scheduled" :assignedTo (:id u)})))
(defn checklist [s u input]
  (d/required input :title 255)
  (let [old (when (:id input) (d/accessible! s u :checklists (:id input)))
        status (d/choice (:status input "Missing") ["Missing" "Received" "Approved" "Rejected"])
        doc (get-in s [:documents (:documentId old)])]
    (when (and (contains? #{"Received" "Approved"} status) (nil? doc)) (d/fail 400 "Attach a file before updating this status"))
    (when (and (= "Approved" status) (not= "Clean" (:scanStatus doc))) (d/fail 409 "The file must pass malware scanning"))
    (owned-save s u :checklists input [:status :expiresOn :description :required] {:status "Missing"})))
(defn commercial [s u table action input]
  (d/writer! u) (d/privilege! u "edit")
  (if (= "save" action)
    (let [old (when (:id input) (d/accessible! s u table (:id input)))]
      (when (and old (not= "Draft" (:status old))) (d/fail 409 "Only drafts can be edited"))
      (owned-save s u table (assoc input :currency (finance/currency (:currency input "PHP"))
                                  :totalMinor (finance/minor (:amount input "0")))
                  [:body :currency :totalMinor :validUntil] {:status "Draft"}))
    (let [old (d/accessible! s u table (:id input))
          _ (d/version! old input)
          next (case [action (:status old)] ["issue" "Draft"] "Issued" ["complete" "Accepted"] "Completed"
                     (d/fail 409 "Document state does not allow this action"))]
      (d/replace-row s table old {:status next}))))
(defn merge-records [s u action input]
  (d/admin! u)
  (let [table (case (:kind input) "lead" :leads "client" :clients (d/fail 400 "Choose leads or clients"))
        a (d/accessible! s u table (:sourceId input)) b (d/accessible! s u table (:targetId input))
        _ (when (= (:id a) (:id b)) (d/fail 400 "Choose two different records"))
        fk (if (= table :leads) :leadId :clientId)]
    (if (= action "preview") [s {:source a :target b}]
      (do (d/version! a input)
        (let [s (reduce (fn [s t]
                          (reduce (fn [s r] (assoc-in s [t (:id r) fk] (:id b))) s (d/related s t fk (:id a))))
                        s [:tasks :cases :documents :checklists :activities :appointments :invoices :proposals :contracts :messages])
              [s r] (d/replace-row s table a {:deletedAt (d/now) :mergedInto (:id b)})]
          [(d/audit s u table r "merged") b])))))
(defn action [s u section action input]
  (when (admin-sections section) (d/admin! u))
  (cond
    (contains? #{"zoom" "calendar" "checkout" "sign"} action) (integrations/request s u section action input)
    (= section "integrations") (integrations/retry-job s u input)
    :else (case section
    "profile" (crm/profile s u input)
    "payment-instructions" (do (d/writer! u) (d/privilege! u "finance_view") (d/privilege! u "payments_record")
                               (let [invoice (d/accessible! s u :invoices (:invoiceId input)) input (assoc input :clientId (:clientId invoice))]
                                 (owned-save s u :paymentInstructions input [:invoiceId :bank :accountName :accountNumber :method :instructions] {})))
    "reconciliation" (controls/reconciliation s u action input)
    "portal" (portal/manage s u action input)
    "security" (if (contains? #{"reset-mfa" "suspend" "resume" "revoke-user" "access"} action)
                 (crm/security-admin s u action input) (auth/security s u action input))
    "tasks" (case action "create" (d/save-task s u (dissoc input :id)) "save" (d/save-task s u input) (d/fail 404 "Unknown task action"))
    "applications" (if (= action "checklist") (crm/apply-template s u input)
                      (let [input (d/owner-input s u input)]
                        (when-not (:clientId input) (d/fail 400 "Applications require a client"))
                        (owned-save s u :cases input [:serviceCategory :destination :status :notes :institution :course :intake :applicationNumber] {:status "Open"})))
    "documents" (checklist s u input)
    "appointments" (appointment s u input)
    "milestones" (owned-save s u :milestones input [:kind :status :dueDate :completedOn :description] {:status "Pending"})
    "contact-log" (let [[s row] (owned-save s u :contacts input [:kind :description :contactedAt :outcome :nextFollowup] {})
                        [s _] (d/insert s :activities (merge (select-keys row [:leadId :clientId :caseId])
                                                              {:kind (str "communication_" (str/lower-case (:kind row "contact")))
                                                               :description (:description row) :date (d/today) :actorId (:id u)}))]
                    [s row])
    "history" (let [input (d/owner-input s u input)]
                (d/add-note s u (if (:clientId input) :clients :leads) (or (:clientId input) (:leadId input)) input))
    "invoices" (case action "save" (finance/invoice-save s u input) "send" (finance/issue-invoice s u input)
                     (d/fail 404 "Unknown invoice action"))
    "payments" (finance/payment s u action input)
    "expenses" (finance/expense s u action input)
    "periods" (finance/period s u action input)
    "proposals" (commercial s u :proposals action input)
    "contracts" (commercial s u :contracts action input)
    "merge" (merge-records s u action input)
    "client-messages" (owned-save s u :messages input [:body :clientVisible :direction] {:direction "Staff" :clientVisible true})
    "checklist-templates" (do (d/admin! u) (d/save! s u :templates input [:title :items :service] {}))
    "reminders" (owned-save s u :reminderRules input [:taskId :daysBefore :escalateAfter :enabled] {:enabled true})
    "communication" (do (d/privilege! u "email")
                         (let [input (d/owner-input s u input)]
                           (d/save! s u :mail (assoc input :to (d/required input :to 255) :subject (d/required input :subject 255))
                                    [:to :subject :body :leadId :clientId] {:status "Queued" :attempts 0 :createdBy (:id u)})))
    "notifications" (if (= action "preferences") (crm/preferences s u input) (let [r (d/record s :notifications (:id input))]
                      (when-not (= (:id u) (:userId r)) (d/fail 404 "Notification not found"))
                      (d/replace-row s :notifications r {:readAt (d/now)})))
    "search" (crm/saved-view s u action input)
    (d/fail 404 "Workspace action not found"))))
