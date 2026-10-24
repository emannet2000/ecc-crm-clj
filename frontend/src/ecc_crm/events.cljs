(ns ecc-crm.events
  (:require [re-frame.core :as rf]))

(rf/reg-fx :http
  (fn [{:keys [method url data success failure] :or {method "GET" failure [:error]}}]
    (-> (js/fetch url (clj->js (cond-> {:method method :credentials "same-origin" :headers {"content-type" "application/json"}}
                               data (assoc :body (js/JSON.stringify (clj->js data))))))
        (.then (fn [response]
                 (-> (.json response)
                     (.then (fn [body]
                              (let [data (js->clj body :keywordize-keys true)]
                                (rf/dispatch (conj (if (.-ok response) success failure) data))))))))
        (.catch (fn [_] (rf/dispatch (conj failure {:error "Connection failed. Your changes have not been saved."})))))))
(rf/reg-event-fx :initialize
  (fn [_ [_ mode token page]]
    (let [state {:page (or page :dashboard) :rows [] :form {} :offset 0 :query "" :loading? true}]
      (case mode
        :portal (cond-> {:db (assoc state :portal? true)} token (assoc :dispatch [:portal-open token])
                  (nil? token) (assoc :dispatch [:portal-exchanged]))
        :reset {:db (assoc state :reset-token token :loading? false)}
        {:db state :http {:url "/api/auth/me" :success [:session] :failure [:signed-out]}}))))
(rf/reg-event-fx :session
  (fn [{:keys [db]} [_ user]] {:db (assoc db :user user :loading? false) :dispatch-n [[:navigate (:page db :dashboard)] [:load-staff]]}))
(rf/reg-event-db :signed-out (fn [db _] (assoc db :user nil :loading? false :rows [] :form {})))
(rf/reg-event-db :field (fn [db [_ key value]] (assoc-in db [:form key] value)))
(rf/reg-event-db :edit (fn [db [_ row]] (assoc db :form row :editing? true :error nil)))
(rf/reg-event-db :cancel (fn [db _] (assoc db :form {} :editing? false :error nil)))
(rf/reg-event-db :error (fn [db [_ error]] (assoc db :error (:error error "Request failed") :loading? false :saving? false)))
(rf/reg-event-fx :login
  (fn [{:keys [db]} _]
    {:db (assoc db :loading? true :error nil)
     :http {:method "POST" :url "/api/auth/login" :data (:form db) :success [:logged-in]}}))
(rf/reg-event-fx :logged-in
  (fn [{:keys [db]} [_ result]] {:db (assoc db :form {} :error nil) :dispatch [:session (:user result)]}))
(rf/reg-event-fx :logout
  (fn [_ _] {:http {:method "POST" :url "/api/auth/logout" :data {} :success [:signed-out]}}))
(defn page-url [page]
  (case page :dashboard "/api/stats" :leads "/api/leads" :clients "/api/clients" :team "/api/users"
        :audit "/api/audit" :archive "/api/archive" (str "/api/workspace/" (name page))))
(rf/reg-event-fx :navigate
  (fn [{:keys [db]} [_ page]]
    (let [generation (inc (:generation db 0))]
      {:db (assoc db :page page :detail nil :form {} :profile-open? false :access-target nil :financial-history nil :bank-candidates nil :template-application nil :editing? false :loading? true :offset 0 :query "" :error nil :generation generation)
       :http {:url (page-url page) :success [:loaded generation]}})))
(rf/reg-event-db :loaded
  (fn [db [_ generation data]]
    (if (not= generation (:generation db)) db
      (-> db (assoc :loading? false :data data :rows (if (= :archive (:page db)) (vec (concat (map #(assoc % :kind "leads") (:leads data)) (map #(assoc % :kind "clients") (:clients data)))) (if (vector? data) data (:rows data [])))
                    :total (:total data 0) :submissionKey (:submissionKey data) :options (:options data []) :permissions (:permissions data {}) :preferences (:preferences data {}) :form (if (= :notifications (:page db)) (merge {:assignments true :deadlines true :documents true :escalations true :emailEnabled true} (:preferences data)) (:form db)))))))
(rf/reg-event-fx :search
  (fn [{:keys [db]} [_ query offset]]
    (let [generation (inc (:generation db 0))]
      {:db (assoc db :query query :offset offset :generation generation :loading? true)
       :http {:url (str (page-url (:page db)) "?q=" (js/encodeURIComponent query) "&offset=" offset)
              :success [:loaded generation]}})))
(rf/reg-event-fx :save
  (fn [{:keys [db]} [_ action]]
    (let [page (:page db) form (:form db) id (:id form)
          base? (contains? #{:leads :clients :team} page)
          url (if base? (str (page-url page) (when id (str "/" id)))
                  (str "/api/workspace/" (name page) "/" (or action "save")))]
      {:db (assoc db :saving? true :error nil)
       :http {:method (if (and base? id) "PATCH" "POST") :url url
              :data (cond-> (assoc form :submissionKey (:submissionKey db)) (= page :checklist-templates) (assoc :items (mapv #(hash-map :title % :required true) (remove empty? (.split (:itemsText form "") "\n"))))) :success [:saved]}})))
(rf/reg-event-fx :saved
  (fn [{:keys [db]} [_ result]] {:db (assoc db :saving? false :form {} :editing? false :portal-share-target nil :profile-open? false :bank-candidates nil :template-application nil :financial-history nil :access-target nil :notice (or (:url result) (:message result) "Saved successfully"))
                       :dispatch-n (cond-> [[:search (:query db) (:offset db)]]
                                     (:detail db) (conj [:open-detail (or (get-in db [:detail :client]) (get-in db [:detail :lead]))]))}))
(rf/reg-event-fx :record-action
  (fn [{:keys [db]} [_ row action]]
    {:http {:method "POST" :url (str "/api/" (name (:page db)) "/" (:id row) "/" action)
            :data {:revision (:revision row)} :success [:saved]}}))
(rf/reg-event-fx :archive-record
  (fn [{:keys [db]} [_ row]]
    (when (js/confirm (str "Archive " (:fullName row (:title row)) "?"))
      {:http {:method "DELETE" :url (str (page-url (:page db)) "/" (:id row)) :success [:saved]}})))
(rf/reg-sub :state (fn [db _] db))

(rf/reg-event-fx :portal-open
  (fn [{:keys [db]} [_ token]]
    {:db (assoc db :portal? true :loading? true :error nil)
     :http {:method "POST" :url "/api/portal/exchange" :data {:token token} :success [:portal-exchanged]}}))
(rf/reg-event-fx :portal-exchanged
  (fn [_ _] {:http {:url "/api/portal" :success [:portal-loaded]}}))
(rf/reg-event-db :portal-loaded (fn [db [_ data]] (assoc db :portal-data data :loading? false :error nil)))
(rf/reg-event-fx :portal-action
  (fn [{:keys [db]} [_ kind id action]]
    {:http {:method "POST" :url (str "/api/portal/commercial/" kind "/" id "/" action)
            :data {:name (get-in db [:form :signature])} :success [:portal-exchanged]}}))
(rf/reg-event-fx :security
  (fn [{:keys [db]} [_ action]]
    {:http {:method "POST" :url (str "/api/workspace/security/" action) :data (:form db) :success [:security-result]}}))
(rf/reg-event-db :security-result (fn [db [_ data]] (assoc db :security data :notice (:message data) :error nil)))
(rf/reg-event-fx :recover
  (fn [{:keys [db]} _]
    {:http {:method "POST" :url "/api/auth/recover" :data (:form db) :success [:security-result]}}))
(rf/reg-event-fx :reset-password
  (fn [{:keys [db]} _]
    {:http {:method "POST" :url "/api/auth/reset" :data (assoc (:form db) :token (:reset-token db)) :success [:security-result]}}))
(rf/reg-event-db :reset-page (fn [db [_ token]] (assoc db :reset-token token)))
(rf/reg-event-fx :upload
  (fn [_ [_ owner file request-id]] {:upload-file {:owner owner :file file :request-id request-id}}))
(rf/reg-fx :upload-file
  (fn [{:keys [owner file request-id]}]
    (let [reader (js/FileReader.)]
      (set! (.-onload reader)
            (fn [_] (let [[kind id] (.split owner ":") content (second (.split (.-result reader) ","))]
                      (rf/dispatch [:upload-content (str "/api/" (case kind "lead" "leads" "expense" "finance/expenses" "portal" "portal/requests" "clients") "/" id (case kind "expense" "/attachments" "photo" "/photo" "portal" "/upload" "/documents"))
                                    {:filename (.-name file) :content content :requestId request-id}]))))
      (set! (.-onerror reader) (fn [_] (rf/dispatch [:error {:error "Unable to read this file"}])))
      (.readAsDataURL reader file))))
(rf/reg-event-fx :upload-content
  (fn [_ [_ url data]] {:http {:method "POST" :url url :data data :success (if (.startsWith url "/api/portal/") [:portal-exchanged] [:saved])}}))

(rf/reg-event-fx :workspace-action
  (fn [{:keys [db]} [_ row action]]
    (when (js/confirm (str "Confirm " action "?"))
      {:http {:method "POST" :url (str "/api/workspace/" (name (:page db)) "/" action)
              :data (cond-> (assoc row :submissionKey (str (random-uuid))) (contains? #{"reverse" "reverse-expense" "unmatch" "ignore" "reopen" "reject"} action) (assoc :reason (js/prompt "Reason for this change") :reviewNote (get-in db [:form :reviewNote]))) :success [:saved]}})))
(rf/reg-event-fx :restore-record
  (fn [_ [_ row]]
    {:http {:method "POST" :url (str "/api/" (:kind row) "/" (:id row) "/restore") :data {} :success [:saved]}}))
(rf/reg-event-fx :open-detail
  (fn [{:keys [db]} [_ row]]
    {:http {:url (str (page-url (:page db)) "/" (:id row)) :success [:detail-loaded]}}))
(rf/reg-event-db :detail-loaded (fn [db [_ data]] (assoc db :detail data :photo-error false)))
(rf/reg-event-db :close-detail (fn [db _] (dissoc db :detail)))
(rf/reg-event-fx :add-note
  (fn [{:keys [db]} _]
    (let [row (or (get-in db [:detail :lead]) (get-in db [:detail :client]))]
      {:http {:method "POST" :url (str (page-url (:page db)) "/" (:id row) "/notes")
              :data {:note (get-in db [:form :note])} :success [:note-saved row]}})))
(rf/reg-event-fx :note-saved (fn [_ [_ row _]] {:dispatch [:open-detail row]}))
(rf/reg-event-fx :password
  (fn [{:keys [db]} _] {:http {:method "PUT" :url "/api/auth/password" :data (:form db) :success [:security-result]}}))

(rf/reg-event-fx :invite-user
  (fn [_ [_ row]] {:http {:method "POST" :url (str "/api/users/" (:id row) "/invite") :data {} :success [:saved]}}))
(rf/reg-event-fx :admin-security
  (fn [{:keys [db]} [_ action]] {:http {:method "POST" :url (str "/api/workspace/security/" action) :data (:form db) :success [:security-result]}}))
(rf/reg-event-db :toggle-privilege
  (fn [db [_ privilege]] (update-in db [:form :privileges] (fn [xs] (if (some #{privilege} xs) (vec (remove #{privilege} xs)) (conj (vec xs) privilege))))))
(rf/reg-event-db :access-editor
  (fn [db [_ row]] (assoc db :access-target row :form {:user (:id row) :revision (:revision row) :accessLevel (:accessLevel row "all") :privileges (:privileges row [])})))
(rf/reg-event-fx :load-profile
  (fn [_ [_ id]] {:http {:url (str "/api/clients/" id "/profile") :success [:profile-loaded id]}}))
(rf/reg-event-db :profile-loaded (fn [db [_ id profile]] (assoc db :profile-client id :form profile :profile-open? true)))
(rf/reg-event-fx :save-profile
  (fn [{:keys [db]} _] {:http {:method "PUT" :url (str "/api/clients/" (:profile-client db) "/profile") :data (:form db) :success [:saved]}}))
(rf/reg-event-fx :templates-for
  (fn [{:keys [db]} [_ row]] {:db (assoc db :template-application row)
                             :http {:url "/api/workspace/checklist-templates" :success [:templates-loaded]}}))
(rf/reg-event-db :templates-loaded (fn [db [_ data]] (assoc db :templates (:rows data))))
(rf/reg-event-fx :apply-template
  (fn [{:keys [db]} [_ template]] {:http {:method "POST" :url "/api/workspace/applications/checklist"
                                         :data {:applicationId (get-in db [:template-application :id]) :templateId (:id template)} :success [:saved]}}))
(rf/reg-event-fx :bank-candidates
  (fn [{:keys [db]} [_ row]] {:db (assoc db :bank-line row) :http {:url (str "/api/workspace/reconciliation/candidates/" (:id row)) :success [:bank-candidates-loaded]}}))
(rf/reg-event-db :bank-candidates-loaded (fn [db [_ data]] (assoc db :bank-candidates data)))
(rf/reg-event-fx :bank-match
  (fn [{:keys [db]} [_ entry]] {:http {:method "POST" :url "/api/workspace/reconciliation/match"
                                     :data {:id (get-in db [:bank-line :id]) :revision (get-in db [:bank-line :revision]) :kind (:kind entry) :entryId (:id entry)} :success [:saved]}}))
(rf/reg-fx :read-text-file
  (fn [{:keys [file event]}] (let [reader (js/FileReader.)]
                             (set! (.-onload reader) #(rf/dispatch (conj event (.-result reader))))
                             (.readAsText reader file))))
(rf/reg-event-fx :bank-import-file (fn [_ [_ file]] {:read-text-file {:file file :event [:bank-import]}}))
(rf/reg-event-fx :bank-import
  (fn [{:keys [db]} [_ csv]] {:http {:method "POST" :url "/api/workspace/reconciliation/import" :data {:csv csv :account (get-in db [:form :account])} :success [:saved]}}))
(rf/reg-event-fx :history
  (fn [_ [_ page id]] {:http {:url (if (= page :expenses) (str "/api/finance/expenses/" id "/history") (str "/api/workspace/payment-history/" id)) :success [:history-loaded]}}))
(rf/reg-event-db :history-loaded (fn [db [_ data]] (assoc db :financial-history data)))
(rf/reg-event-fx :save-preferences
  (fn [{:keys [db]} _] {:http {:method "POST" :url "/api/workspace/notifications/preferences" :data (:form db) :success [:saved]}}))
(rf/reg-event-fx :saved-views (fn [_ _] {:http {:method "POST" :url "/api/workspace/search/views" :data {} :success [:views-loaded]}}))
(rf/reg-event-db :views-loaded (fn [db [_ data]] (assoc db :saved-views data)))
(rf/reg-event-fx :apply-view
  (fn [_ [_ row]] {:http {:method "POST" :url "/api/workspace/search/apply" :data {:id (:id row)} :success [:view-loaded]}}))
(rf/reg-event-db :view-loaded (fn [db [_ data]] (assoc db :rows (:rows data) :total (count (:rows data)) :error nil)))
(rf/reg-event-fx :saved-view-action
  (fn [{:keys [db]} [_ action row]] {:http {:method "POST" :url (str "/api/workspace/search/" action) :data (or row (:form db)) :success [:saved]}}))
(rf/reg-event-fx :conflict
  (fn [_ [_ section row]] {:http {:url (str "/api/workspace/conflict/" (name section) "/" (:id row)) :success [:conflict-loaded]}}))
(rf/reg-event-db :conflict-loaded (fn [db [_ data]] (assoc db :conflict (:current data))))
(rf/reg-event-fx :expense-upload
  (fn [_ [_ id file]] {:upload-file {:owner (str "expense:" id) :file file}}))
(rf/reg-event-fx :photo-upload
  (fn [_ [_ id file]] {:upload-file {:owner (str "photo:" id) :file file}}))

(rf/reg-event-fx :portal-upload
  (fn [_ [_ id file]] {:upload-file {:owner (str "portal:" id) :file file}}))

(rf/reg-event-fx :load-staff (fn [_ _] {:http {:url "/api/users" :success [:staff-loaded]}}))
(rf/reg-event-db :staff-loaded (fn [db [_ users]] (assoc db :staff-options (mapv #(hash-map :value (str "staff:" (:id %)) :label (:name %)) users))))
(rf/reg-event-fx :owner-search
  (fn [{:keys [db]} [_ query]] {:db (assoc db :owner-query query) :http {:url (str "/api/options?q=" (js/encodeURIComponent query)) :success [:owners-loaded query]}}))
(rf/reg-event-db :owners-loaded (fn [db [_ query rows]] (if (= query (:owner-query db)) (assoc db :owner-options rows) db)))
(rf/reg-event-fx :expense-files
  (fn [_ [_ id]] {:http {:url (str "/api/finance/expenses/" id "/attachments") :success [:expense-files-loaded]}}))
(rf/reg-event-db :expense-files-loaded (fn [db [_ rows]] (assoc db :expense-files rows)))
(rf/reg-event-fx :report-range
  (fn [{:keys [db]} _] {:dispatch [:search (str (get-in db [:form :fromDate] "") "," (get-in db [:form :toDate] "")) 0]}))

(rf/reg-event-db :photo-error (fn [db _] (assoc db :photo-error true)))

(rf/reg-event-db :portal-share (fn [db [_ row]] (assoc db :portal-share-target row :form {:id (:id row)})))
(rf/reg-event-fx :portal-document-access
  (fn [{:keys [db]} [_ action]] {:http {:method "POST" :url (str "/api/workspace/portal/" action) :data (:form db) :success [:saved]}}))

(rf/reg-event-fx :portal-logout (fn [_ _] {:http {:method "POST" :url "/api/portal/logout" :data {} :success [:portal-closed]}}))
(rf/reg-event-db :portal-closed (fn [db _] (assoc db :portal-data {} :portal-closed? true :loading? false)))
