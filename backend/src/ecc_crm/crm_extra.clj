(ns ecc-crm.crm-extra
  (:require [clojure.string :as str] [ecc-crm.domain :as d] [ecc-crm.auth :as auth]
            [ecc-crm.files :as files] [ecc-crm.store :as store])
  (:import [java.time Instant LocalDate] [java.util Base64] [java.io ByteArrayInputStream ByteArrayOutputStream]
           [javax.imageio ImageIO]))
(defn invite [s u input public-url]
  (d/admin! u)
  (let [[s user] (if (:id input) [s (d/record s :users (:id input))]
                     (auth/create-user s u (assoc input :password (auth/token))))
        user (d/record s :users (:id user)) raw (auth/token)
        s (assoc-in s [:recovery (auth/digest raw)] {:userId (:id user) :kind "invitation"
                                                    :expiresAt (str (.plusSeconds (Instant/now) 3600))})
        [s mail] (d/insert s :mail {:to (:email user) :subject "Your ECC workspace invitation" :status "Queued" :attempts 0
                                   :body (str "Set your password to join ECC: " public-url "/#/reset?token=" raw)})]
    [(d/audit s u :users user "invited") {:message "Invitation queued" :mailId (:id mail)}]))
(defn security-admin [s u action input]
  (d/admin! u)
  (when-not (auth/password? (:password input) (:passwordHash (d/record s :users (:id u))))
    (d/fail 403 "Verify your current password"))
  (let [id (d/integer (:user input (:id input))) target (d/record s :users id)]
    (when (and (= id (:id u)) (contains? #{"suspend" "reset-mfa"} action)) (d/fail 400 "Use your own account security controls"))
    (let [s (case action
              "reset-mfa" (update-in s [:users id] dissoc :mfaSecret :mfaPending :mfaCounter :recoveryCodes)
              "suspend" (assoc-in s [:users id :suspended] true)
              "resume" (assoc-in s [:users id :suspended] false)
              "revoke-user" s
              "access" (do (when (= "admin" (:role target)) (d/fail 400 "Administrators retain full access"))
                           (d/version! target input)
                           (let [scope (d/choice (:accessLevel input) ["all" "assigned"])
                                 privileges (or (:privileges input) (vec (filter #(= "allowed" (get input (keyword %))) d/privileges)))]
                             (when-not (every? (set d/privileges) privileges) (d/fail 400 "Unknown privilege"))
                             (when (and (= "viewer" (:role target)) (some (set privileges) (remove #{"download" "export" "sales_view" "finance_view"} d/privileges)))
                               (d/fail 400 "Viewers cannot receive write privileges"))
                             (-> s (assoc-in [:users id :accessLevel] scope) (assoc-in [:users id :privileges] privileges)
                                 (update-in [:users id :revision] (fnil inc 0)))))
              (d/fail 404 "Unknown administrator action"))]
      [(-> s (auth/revoke-user id) (d/audit u :users target action)) {:message "Account security updated"}])))
(defn profile [s u input]
  (d/writer! u) (d/privilege! u "edit")
  (let [input (d/owner-input s u input) id (:clientId input) _ (when-not id (d/fail 400 "Choose a client"))
        old (get-in s [:profiles id] {:id id :revision 0}) _ (d/version! old input)
        fields [:dateOfBirth :nationality :passportNumber :passportExpiry :address :emergencyName :emergencyPhone
                :education :occupation :maritalStatus :gender :preferredName :notes :institution :program :intakeDate :qualification :status]
        row (merge old (select-keys input fields) {:clientId id :revision (inc (:revision old)) :updatedAt (d/now)})]
    [(d/audit (assoc-in s [:profiles id] row) u :profiles row "updated") row]))
(defn photo [s u id input]
  (d/accessible! s u :clients id)
  (let [bytes (try (.decode (Base64/getDecoder) (:content input)) (catch Exception _ (d/fail 400 "Invalid image data")))
        _ (when (> (alength bytes) (* 5 1024 1024)) (d/fail 413 "Photo exceeds 5 MB"))
        normalized (with-open [stream (ImageIO/createImageInputStream (ByteArrayInputStream. bytes))]
                     (let [readers (ImageIO/getImageReaders stream)]
                       (when-not (.hasNext readers) (d/fail 400 "Use a PNG or JPEG image"))
                       (let [reader (.next readers)]
                         (try (.setInput reader stream)
                              (when (or (> (.getWidth reader 0) 4096) (> (.getHeight reader 0) 4096)) (d/fail 400 "Photo dimensions exceed 4096 pixels"))
                              (let [image (.read reader 0) out (ByteArrayOutputStream.)]
                                (ImageIO/write image "png" out) (.toByteArray out))
                              (finally (.dispose reader))))))
        [s doc] (files/upload s u :clients id {:filename "profile.png" :content (.encodeToString (Base64/getEncoder) normalized)})
        s (-> s (assoc-in [:documents (:id doc) :photo] true) (assoc-in [:clients (d/integer id) :photoId] (:id doc)))]
    [s {:documentId (:id doc) :scanStatus "Quarantined"}]))
(defn apply-template [s u input]
  (d/writer! u) (d/privilege! u "edit")
  (let [app (d/accessible! s u :cases (:applicationId input (:caseId input))) template (d/record s :templates (:templateId input))
        items (or (:items template) (store/matching (:templateItems s {}) :templateId (:id template)))]
    (reduce (fn [[s result] item]
              (let [key [(:id app) (:id template) (str/lower-case (:title item))]]
                (if (get-in s [:appliedTemplates key]) [s result]
                  (let [[s row] (d/insert s :checklists {:clientId (:clientId app) :caseId (:id app) :title (d/required item :title 255)
                                                        :required (:required item true) :status "Missing" :templateId (:id template)})]
                    [(assoc-in s [:appliedTemplates key] (:id row)) (conj result row)])))) [s []] items)))
(defn saved-view [s u action input]
  (let [old (when (:id input) (d/record s :savedViews (:id input)))]
    (when (and old (not= (:id u) (:userId old))) (d/fail 404 "Saved view not found"))
    (case action
      "save" (let [data (assoc (select-keys input [:entity :query :mine :overdue]) :title (d/required input :title 100) :userId (:id u))]
               (d/choice (:entity data) ["leads" "clients" "tasks" "cases"])
               (if old (do (d/version! old input) (d/replace-row s :savedViews old data)) (d/insert s :savedViews data)))
      "apply" [s {:entity (:entity old) :query (:query old) :mine (:mine old) :overdue (:overdue old)
                   :rows (vec (filter #(and (d/visible? s u (keyword (:entity old)) %)
                                           (str/includes? (str/lower-case (pr-str %)) (str/lower-case (:query old "")))
                                           (or (not (:mine old)) (= (:id u) (or (:assignedTo %) (:consultantId %) (get-in s [:clients (:clientId %) :consultantId]))))
                                           (or (not (:overdue old)) (and (:dueDate %) (neg? (compare (:dueDate %) (d/today)))
                                                                       (not (contains? #{"Done" "Cancelled"} (:status %))))))
                                      (d/rows s (keyword (:entity old)))))}]
      "delete" [(update s :savedViews dissoc (:id old)) {:deleted true}]
      "views" [s (vec (filter #(= (:id u) (:userId %)) (d/rows s :savedViews)))]
      (d/fail 404 "Unknown saved view action"))))
(defn preferences [s u input]
  (let [old (get-in s [:preferences (:id u)] {:revision 0}) _ (d/version! old input)
        row (merge old (select-keys input [:assignments :deadlines :documents :escalations :emailEnabled])
                   {:id (:id u) :revision (inc (:revision old))})]
    [(assoc-in s [:preferences (:id u)] row) row]))
(defn conflict [s u table id]
  (let [row (d/accessible! s u table id)] {:current row :revision (:revision row) :message "Compare your draft with the current server record"}))
