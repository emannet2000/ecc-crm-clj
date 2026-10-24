(ns ecc-crm.domain
  (:require [clojure.string :as str] [ecc-crm.store :as store])
  (:import [java.time Instant LocalDate ZoneId]
           [java.util UUID]))

(defn fail [status message] (throw (ex-info message {:status status})))
(defn now [] (str (Instant/now)))
(defn today [] (str (LocalDate/now (ZoneId/of "Asia/Manila"))))
(defn integer [x] (try (Long/parseLong (str x)) (catch Exception _ nil)))
(defn required [input field maximum]
  (let [value (str/trim (str (get input field "")))]
    (when (or (str/blank? value) (> (count value) maximum))
      (fail 400 (str (name field) " is required (maximum " maximum " characters)"))) value))
(defn choice [value choices]
  (when-not (some #{value} choices) (fail 400 (str "Choose one of: " (str/join ", " choices)))) value)
(defn rows [s table] (vals (get s table {})))
(defn record [s table id] (or (get-in s [table (integer id)]) (fail 404 "Record not found")))
(defn public-user [u] (select-keys u [:id :email :name :role :revision :accessLevel :privileges]))
(defn admin! [u] (when-not (= "admin" (:role u)) (fail 403 "Administrator access required")))
(defn writer! [u] (when (= "viewer" (:role u)) (fail 403 "This account has read access")))
(def privileges ["edit" "delete" "download" "export" "email" "portal" "sales_view" "finance_view"
                 "payments_record" "expenses_record" "expenses_approve" "finance_periods" "finance_reconcile"])
(defn privilege! [u p]
  (when-not (or (= "admin" (:role u))
                (some #{p} (:privileges u (if (= "viewer" (:role u)) ["download" "export"]
                                            ["edit" "delete" "download" "export" "email" "portal"]))))
    (fail 403 "Your account does not have the required privilege")))

(defn visible? [s u table r]
  (and r (not (:deletedAt r))
       (or (not (:expenseId r)) (try (privilege! u "finance_view") true (catch clojure.lang.ExceptionInfo _ false)))
       (or (= "admin" (:role u))
           (and (not (or (:assignedOnly s) (= "true" (System/getenv "ASSIGNED_ONLY")))) (not= "assigned" (:accessLevel u)))
           (case table
             :leads (= (:id u) (:consultantId r))
             :clients (= (:id u) (:consultantId r))
             (or (when-let [id (:clientId r)] (when-let [owner (get-in s [:clients id])] (visible? s u :clients owner)))
                 (when-let [id (:leadId r)] (when-let [owner (get-in s [:leads id])] (visible? s u :leads owner)))
                 (= (:id u) (:assignedTo r))
                 (when-let [app (get-in s [:cases (:caseId r)])]
                   (when-let [client (get-in s [:clients (:clientId app)])] (visible? s u :clients client)))
                 (when-let [task (get-in s [:tasks (:taskId r)])] (visible? s u :tasks task)))))))
(defn accessible! [s u table id]
  (let [r (record s table id)]
    (when-not (visible? s u table r) (fail 404 "Record not found")) r))
(defn version! [old input]
  (when (and (:revision input) (not= (:revision old) (integer (:revision input))))
    (fail 409 "This record has changed. Reload before saving.")))
(defn insert [s table data]
  (let [id (inc (get-in s [:counters table] 0))
        row (assoc data :id id :revision 1 :createdAt (or (:createdAt data) (now)) :updatedAt (now))]
    [(-> s (assoc-in [:counters table] id) (assoc-in [table id] row)) row]))
(defn replace-row [s table old data]
  (let [r (merge old data {:id (:id old) :createdAt (:createdAt old)
                         :updatedAt (now) :revision (inc (:revision old 0))})]
    [(assoc-in s [table (:id old)] r) r]))
(defn audit [s u table r action]
  (first (insert s :audit {:entityType (name table) :entityId (:id r) :entityName (or (:fullName r) (:title r) (:name r))
                           :action action :actorId (:id u) :date (now)})))
(defn save! [s u table input fields defaults]
  (writer! u) (privilege! u "edit")
  (let [id (integer (:id input)) old (when id (accessible! s u table id))
        _ (when old (version! old input))
        data (merge (when-not old defaults) (select-keys input fields))
        [s row] (if old (replace-row s table old data) (insert s table data))]
    [(audit s u table row (if old "updated" "created")) row]))

(def stages ["New Lead" "Contacted" "Initial Assessment" "Qualified" "Consultation Booked" "Proposal Sent" "Converted" "Closed/Lost"])
(def record-fields [:fullName :email :phone :source :consultantId :quality :stage :destination :service
                    :notes :lastContact :nextFollowup :address :dateOfBirth :nationality :passportNumber])
(defn save-person [s u table input]
  (when (or (not (:id input)) (contains? input :fullName)) (required input :fullName 255))
  (when (and (= table :leads) (:stage input)) (choice (:stage input) stages))
  (when-let [email (:email input)]
    (when (and (not (str/blank? email)) (not (re-matches #"[^\s@]+@[^\s@]+\.[^\s@]+" email)))
      (fail 400 "Enter a valid email address")))
  (when-let [quality (:quality input)] (when-not (str/blank? quality) (choice quality ["Hot" "Warm" "Cold"])))
  (when-let [phone (:phone input)]
    (when (and (not (str/blank? phone))
               (or (> (count phone) 50) (not (<= 7 (count (re-seq #"[0-9]" phone)) 20))
                   (not (re-matches #"[0-9+() .-]+" phone)))) (fail 400 "Enter a phone number with 7–20 digits")))
  (when (> (count (:notes input "")) 20000) (fail 400 "Notes must use no more than 20,000 characters"))
  (when (and (:consultantId input) (seq (:users s)))
    (let [staff (get-in s [:users (integer (:consultantId input))])]
      (when (or (nil? staff) (= "viewer" (:role staff)) (:suspended staff)) (fail 400 "Select an active staff member"))))
  (let [[s row] (save! s u table input record-fields
                       {:stage (if (= table :leads) "New Lead" "New Client") :consultantId (:id u)})
        field (if (= table :leads) :leadNumber :clientNumber)
        number (or (field row) (format (if (= table :leads) "L-%06d" "C-%06d") (:id row)))
        row (assoc row field number)]
    [(assoc-in s [table (:id row)] row) row]))

(defn archive [s u table id]
  (writer! u) (privilege! u "delete")
  (let [old (accessible! s u table id) [s row] (replace-row s table old {:deletedAt (now)})]
    [(audit s u table row "archived") {:archived true}]))
(defn restore-record [s u table id]
  (admin! u)
  (let [old (record s table id) [s row] (replace-row s table old {:deletedAt nil})]
    [(audit s u table row "restored") row]))
(defn related [s table fk id] (remove :deletedAt (store/matching (get s table {}) fk id)))
(defn detail [s u table id]
  (let [r (accessible! s u table id) fk (if (= table :leads) :leadId :clientId)]
    {(if (= table :leads) :lead :client) r
     :tasks (vec (related s :tasks fk (:id r))) :activities (vec (concat (related s :activities fk (:id r)) (map #(assoc % :id (str "history-" (:id %)) :description (:note %)) (related s :history fk (:id r)))))
     :documents (mapv #(dissoc % :content) (related s :documents fk (:id r)))
     :cases (vec (related s :cases fk (:id r)))}))
(defn convert [s u id]
  (writer! u) (privilege! u "edit")
  (let [lead (accessible! s u :leads id)]
    (if (:convertedClientId lead)
      [s (record s :clients (:convertedClientId lead))]
      (let [[s client] (save-person s u :clients (dissoc lead :id :revision :leadNumber :stage))
            [s app] (insert s :cases {:clientId (:id client) :status "Open" :serviceCategory (:service lead)})
            [s lead] (replace-row s :leads lead {:stage "Converted" :convertedClientId (:id client)})
            s (reduce (fn [s table]
                        (reduce (fn [s r] (assoc-in s [table (:id r)] (assoc r :clientId (:id client))))
                                s (related s table :leadId (:id lead)))) s [:tasks :documents :activities :checklists :appointments :history :milestones :contacts :messages :reminderRules])]
        [(audit s u :leads lead "converted") (assoc client :caseId (:id app))]))))

(defn owner-input [s u input]
  (let [[kind id] (str/split (str (:owner input)) #":" 2)
        input (if (= kind "case")
                (let [app (accessible! s u :cases id)] (assoc input :caseId (:id app) :clientId (:clientId app))) input)
        input (if (and (:caseId input) (nil? (:clientId input)))
                (let [app (accessible! s u :cases (:caseId input))] (assoc input :clientId (:clientId app))) input)
        input (cond-> input
                (= kind "lead") (assoc :leadId (integer id))
                (= kind "client") (assoc :clientId (integer id)))]
    (cond (:clientId input) (accessible! s u :clients (:clientId input))
          (:leadId input) (accessible! s u :leads (:leadId input))
          :else (fail 400 "Choose a lead or client")) input))
(defn save-task [s u input]
  (let [old (when (:id input) (accessible! s u :tasks (:id input)))
        input (owner-input s u (merge old input))
        input (if (seq (:dueAt input)) (assoc input :dueDate (str (.toLocalDate (.atZone (Instant/parse (:dueAt input)) (ZoneId/of "Asia/Manila"))))) input)
        _ (required input :title 255)
        _ (when (:status input) (choice (:status input) ["Pending" "In Progress" "Done" "Cancelled"]))
        _ (when-let [days (integer (:recurrenceDays input))]
            (when (or (< days 1) (> days 366) (str/blank? (:dueDate input)))
              (fail 400 "Recurring tasks require a due date and an interval of 1–366 days")))
        [s row] (save! s u :tasks input [:title :description :notes :leadId :clientId :dueDate :priority :status
                                        :assignedTo :recurrenceDays :scheduledAt :dueAt]
                       {:status "Pending" :priority "Medium" :assignedTo (:id u)})
        completed? (and (= "Done" (:status row)) (not= "Done" (:status old)))
        [s row] (if completed? (replace-row s :tasks row {:completedAt (now)}) [s row])
        s (if (and completed? (integer (:recurrenceDays row)))
            (first (insert s :tasks (-> row (dissoc :id :revision :createdAt :completedAt)
                                       (assoc :status "Pending" :previousTaskId (:id row)
                                              :dueDate (str (.plusDays (LocalDate/parse (:dueDate row))
                                                                      (integer (:recurrenceDays row)))))))) s)]
    [s row]))

(defn add-note [s u table id input]
  (writer! u) (privilege! u "edit")
  (let [r (accessible! s u table id) note (required input :note 20000)
        [s row] (insert s :activities {(if (= table :leads) :leadId :clientId) (:id r)
                                      :kind "Note" :description note :actorId (:id u) :date (today)})]
    [(audit s u :activities row "created") row]))
(defn list-records [s u table params]
  (let [q (str/lower-case (get params "q" ""))
        offset (max 0 (or (integer (get params "offset")) 0))
        limit (max 1 (min 200 (or (integer (get params "limit")) 50)))
        indexed? (instance? ecc_crm.store.EntityTable (get s table))
        result (when-not indexed? (->> (rows s table)
                    (filter #(visible? s u table %))
                    (filter #(str/includes? (str/lower-case (str (or (:fullName %) (:title %) "") " " (:email %) " " (:phone %))) q))
                    (filter #(every? (fn [field] (let [v (get params (name field))]
                                                  (or (str/blank? v) (= v (str (field %)))))) [:stage :quality :source :status]))
                    (sort-by :id >)))]
    (if indexed?
      (store/paged (get s table) {:query q :offset offset :limit limit :user-id (:id u)
                                 :assigned? (and (not= "admin" (:role u)) (or (:assignedOnly s) (= "true" (System/getenv "ASSIGNED_ONLY")) (= "assigned" (:accessLevel u))))
                                 :filters (into {} (for [key [:stage :quality :source :status]] [key (get params (name key) "")]))})
      {:rows (vec (take limit (drop offset result))) :total (count result) :offset offset :limit limit})))
