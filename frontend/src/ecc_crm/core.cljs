(ns ecc-crm.core
  (:require [clojure.string :as str]
            [reagent.dom.client :as dom]
            [re-frame.core :as rf]
            [reitit.frontend :as routing]
            [reitit.frontend.easy :as history]
            [ecc-crm.events]))

(def navigation
  [["Workspace" [[:dashboard "Overview"] [:leads "Leads"] [:clients "Clients"] [:applications "Applications"]
                  [:tasks "Tasks"] [:appointments "Appointments"] [:documents "Documents"] [:milestones "Milestones"]
                  [:contact-log "Contact log"] [:history "Activity"]]]
   ["Communication" [[:client-messages "Client messages"] [:communication "Email"] [:portal "Client portal"] [:notifications "Notifications"]]]
   ["Commercial" [[:proposals "Proposals"] [:contracts "Contracts"] [:invoices "Invoices"] [:payments "Payments"]
                  [:balances "Balances"] [:expenses "Expenses"] [:cashflow "Cash flow"] [:payment-instructions "Payment instructions"] [:periods "Accounting periods"] [:reconciliation "Bank reconciliation"] [:finance-audit "Finance history"]]]
   ["Management" [[:reports "Reports"] [:sales "Sales"] [:ageing "Ageing"] [:bottlenecks "Bottlenecks"] [:trends "Trends"] [:integrations "Integrations"] [:search "Saved views"] [:checklist-templates "Checklist templates"] [:reminders "Reminder rules"] [:team "Team"] [:audit "Audit"] [:archive "Archive"] [:security "Account security"]]]])
(def person-fields [[:fullName "Full name" "text" true] [:email "Email" "email"] [:phone "Phone" "tel"]
                    [:source "Source" "text"] [:consultantId "Assigned consultant" "staff"] [:destination "Destination" "text"] [:service "Service" "text"]
                    [:nextFollowup "Next follow-up" "date"] [:notes "Notes" "textarea"]])
(def fields
  {:leads (conj person-fields [:stage "Stage" ["New Lead" "Contacted" "Initial Assessment" "Qualified" "Consultation Booked" "Proposal Sent" "Converted" "Closed/Lost"]] [:quality "Quality" ["Hot" "Warm" "Cold"]]) :clients person-fields
   :checklist-templates [[:title "Template name" "text" true] [:service "Service" "text"] [:itemsText "Required documents (one per line)" "textarea" true]]
   :reminders [[:owner "Record" "owner" true] [:taskId "Task ID" "number" true] [:daysBefore "Email days before deadline" "number"] [:escalateAfter "Escalate days overdue" "number"] [:enabled "Enabled" "checkbox"]]
   :tasks [[:title "Title" "text" true] [:owner "Record" "owner" true] [:description "Description" "textarea"]
           [:dueDate "Due date" "date"] [:assignedTo "Assigned staff" "staff"] [:scheduledAt "Scheduled time" "datetime-local"] [:dueAt "Deadline" "datetime-local"] [:status "Status" ["Pending" "In Progress" "Done" "Cancelled"]]
           [:priority "Priority" ["Low" "Medium" "High" "Urgent"]] [:recurrenceDays "Repeat every (days)" "number"]]
   :applications [[:title "Application" "text" true] [:owner "Client" "client" true] [:institution "Institution" "text"]
                  [:course "Course" "text"] [:destination "Destination" "text"] [:status "Status" ["Open" "Submitted" "Approved" "Rejected" "Completed"]] [:notes "Notes" "textarea"]]
   :appointments [[:title "Title" "text" true] [:owner "Record" "owner" true] [:startsAt "Starts" "datetime-local" true]
                  [:endsAt "Ends" "datetime-local" true] [:location "Location" "text"] [:notes "Notes" "textarea"]]
   :documents [[:title "Document request" "text" true] [:owner "Record" "owner" true] [:status "Status" ["Missing" "Received" "Approved" "Rejected"]] [:expiresOn "Expiry date" "date"]]
   :milestones [[:title "Milestone" "text" true] [:owner "Record" "owner" true] [:dueDate "Due date" "date"] [:status "Status" ["Pending" "Done"]]]
   :contact-log [[:title "Subject" "text" true] [:owner "Record" "owner" true] [:kind "Channel" ["Phone" "Email" "Meeting" "Message"]] [:description "Summary" "textarea"]]
   :history [[:owner "Record" "owner" true] [:note "Note" "textarea" true]]
   :invoices [[:title "Invoice" "text" true] [:owner "Client" "client" true] [:description "Description" "textarea"]
              [:subtotal "Subtotal" "text" true] [:discount "Discount" "text"] [:tax "Tax" "text"] [:currency "Currency" "text" true] [:dueDate "Due date" "date" true]]
   :payments [[:invoiceId "Invoice ID" "number" true] [:amount "Amount" "text" true] [:paidOn "Payment date" "date" true]
              [:method "Method" ["Bank transfer" "Cash" "Card"]] [:reference "Reference" "text"]]
   :expenses [[:supplier "Supplier" "text" true] [:description "Description" "textarea"] [:amount "Amount" "text" true]
              [:currency "Currency" "text" true] [:expenseOn "Date" "date" true] [:category "Category" "text"]]
   :payment-instructions [[:owner "Client" "client" true] [:invoiceId "Invoice ID" "number" true] [:bank "Bank" "text"] [:accountName "Account name" "text"] [:accountNumber "Account number" "text"] [:method "Method" "text"] [:instructions "Instructions" "textarea"]]
   :periods [[:from "From" "date" true] [:to "To" "date" true] [:reason "Reason" "textarea" true]]
   :team [[:name "Name" "text" true] [:email "Email" "email" true] [:role "Role" ["consultant" "viewer" "admin"]]
          [:password "Password (12+ characters)" "password"]]
   :client-messages [[:title "Subject" "text" true] [:owner "Client" "client" true] [:body "Message" "textarea" true]]
   :portal [[:owner "Client" "client" true]]
   :communication [[:owner "Record" "owner" true] [:to "To" "email" true] [:subject "Subject" "text" true] [:body "Message" "textarea" true]]})
(def commercial-fields [[:title "Title" "text" true] [:owner "Client" "client" true] [:body "Terms" "textarea" true]
                        [:amount "Amount" "text" true] [:currency "Currency" "text" true] [:validUntil "Valid until" "date" true]])
(defn local-datetime [value]
  (if (empty? value) "" (let [date (js/Date. value) pad #(str (when (< % 10) "0") %)]
    (str (.getFullYear date) "-" (pad (inc (.getMonth date))) "-" (pad (.getDate date)) "T" (pad (.getHours date)) ":" (pad (.getMinutes date))))))
(defn input-field [form options [key label type required?]]
  (let [attrs {:id (name key) :name (name key) :value (if (= type "datetime-local") (local-datetime (get form key "")) (or (get form key) "")) :required (boolean required?)
               :on-change #(rf/dispatch [:field key (let [v (.. % -target -value)]
                                                     (cond (and (contains? #{"number" "staff"} type) (not (str/blank? v))) (js/parseInt v 10)
                                                           (and (= type "datetime-local") (not (str/blank? v))) (.toISOString (js/Date. v)) :else v))])}]
    [:label.field {:for (name key)} [:span label]
     (cond (= type "textarea") [:textarea attrs]
           (or (vector? type) (contains? #{"owner" "client" "staff"} type))
           [:select attrs [:option {:value ""} "Choose…"]
            (for [option (cond (= type "client") (filter #(str/starts-with? (:value %) "client:") options)
                              (= type "owner") (filter #(or (str/starts-with? (:value %) "lead:") (str/starts-with? (:value %) "client:") (str/starts-with? (:value %) "case:")) options)
                              (= type "staff") (map #(assoc % :value (js/parseInt (second (str/split (:value %) #":")) 10)) (filter #(str/starts-with? (:value %) "staff:") options))
                              :else (map #(hash-map :value % :label %) type))]
              ^{:key (:value option)} [:option {:value (:value option)} (:label option)])]
           (= type "checkbox") [:input {:type "checkbox" :id (name key) :checked (boolean (get form key)) :on-change #(rf/dispatch [:field key (.. % -target -checked)])}]
           :else [:input (assoc attrs :type type)])]))
(defn login [state]
  [:main.login [:form.card {:on-submit #(do (.preventDefault %) (rf/dispatch [:login]))}
                [:div.brand "ECC"] [:h1 "Welcome to your workspace"] [:p.muted "Sign in to manage your clients and their next steps."]
                (when (:error state) [:p.error {:role "alert"} (:error state)])
                [input-field (:form state) [] [:email "Email" "email" true]]
                [input-field (:form state) [] [:password "Password" "password" true]]
                [input-field (:form state) [] [:otp "Authenticator code (if enabled)" "text"]]
                [input-field (:form state) [] [:recoveryCode "Or use a single-use recovery code" "text"]]
                [:button.primary {:type "submit" :disabled (:loading? state)} (if (:loading? state) "Signing in…" "Sign in")]
                [:button {:type "button" :on-click #(rf/dispatch [:recover])} "Send password reset email"]
                (when (:notice state) [:p.notice (:notice state)])]])
(defn dashboard [data]
  [:<> [:div.metrics
        (for [[key title] [[:totalLeads "Leads"] [:totalClients "Clients"] [:openTasks "Open tasks"] [:convertedLeads "Converted leads"]]]
          ^{:key key} [:article.card [:p.muted title] [:strong.metric (get data key 0)]])]
   [:article.card [:h2 "Lead pipeline"]
    (if (seq (:byStage data))
      [:div.pipeline (for [row (:byStage data)] ^{:key (:stage row)} [:div [:span (:stage row)] [:strong (:count row)]])]
      [:p.muted "Create your first lead to start tracking your pipeline."])]] )
(defn editor [state]
  (let [page (:page state) fs (or (fields page) (when (contains? #{:proposals :contracts} page) commercial-fields))
        action (case page :payments "record" :expenses "submit" :periods "close" :history "add" :contact-log "add" :communication "send" :portal "create" "save")]
    [:form.card.editor {:on-submit #(do (.preventDefault %) (rf/dispatch [:save action]))}
     [:h2 (if (:id (:form state)) "Edit record" "New record")]
     (when (some #(contains? #{"owner" "client"} (nth % 2)) fs)
       [:label.field [:span "Find a record"] [:input {:type "search" :placeholder "Search by name, email or phone" :value (:owner-query state "") :on-change #(rf/dispatch [:owner-search (.. % -target -value)])}]])
     [:div.form-grid (for [f fs] ^{:key (first f)} [input-field (:form state) (distinct (concat (or (:owner-options state) (:options state)) (:staff-options state))) f])]
     [:div.actions [:button.primary {:type "submit" :disabled (:saving? state)} (if (:saving? state) "Saving…" "Save")]
      [:button {:type "button" :on-click #(rf/dispatch [:cancel])} "Cancel"]]]))
(defn allowed? [state action] (get (:permissions state) (keyword action) (= "admin" (get-in state [:user :role]))))
(defn records-table [state]
  (let [page (:page state) write? (not= "viewer" (get-in state [:user :role]))]
    [:div.card.table-wrap
     (if (empty? (:rows state)) [:div.empty [:h2 "No records yet"] [:p.muted "Records will appear here as your team adds them."]]
       [:table [:thead [:tr [:th "Record"] [:th "Status"] [:th "Updated"] [:th "Actions"]]]
        [:tbody (for [r (:rows state)]
                  ^{:key (str (:id r))}
                  [:tr [:td [:strong {:on-click #(when (contains? #{:leads :clients} page) (rf/dispatch [:open-detail r])) :class (when (contains? #{:leads :clients} page) "record-link")} (or (:fullName r) (:title r) (:name r) (:supplier r) (str "#" (:id r))) ]
                        [:small (or (:email r) (:description r) (:entityType r))]
                        [:div.record-summary (for [[key label] [[:currency "Currency"] [:amount "Amount"] [:balance "Balance"] [:collected "Collected"] [:outstanding "Outstanding"]
                                                                [:net "Net"] [:leads "Leads"] [:converted "Converted"] [:openTasks "Open tasks"] [:overdueTasks "Overdue tasks"] [:applications "Applications"] [:averageDays "Average days"]
                                                                [:overdueDays "Overdue days"] [:errorCode "Provider status"] [:reference "Reference"]]
                                                    :when (some? (get r key))] ^{:key key} [:span (str label ": " (get r key))])]
                        (when (and (:amountMinor r) (not (:amount r))) [:small (str (:currency r) " " (/ (:amountMinor r) 100))])]
                   [:td [:span.badge (or (:stage r) (:status r) (:role r) (:action r) "—")]]
                   [:td (subs (or (:updatedAt r) (:createdAt r) "") 0 (min 10 (count (or (:updatedAt r) (:createdAt r) ""))))]
                   [:td [:div.actions
                         (when (and (= page :team) (= "admin" (get-in state [:user :role]))) [:<> [:button {:on-click #(rf/dispatch [:invite-user r])} "Invite"] [:button {:on-click #(rf/dispatch [:access-editor r])} "Access"]])
                         (when (= page :applications) [:button {:on-click #(rf/dispatch [:templates-for r])} "Apply checklist"])
                         (when (= page :integrations) [:button {:disabled (not (contains? #{"Failed" "Review"} (:status r))) :on-click #(rf/dispatch [:workspace-action r "retry"])} "Retry"])
                         (when (contains? #{:appointments :invoices :contracts} page)
                           [:div.actions (for [[action label] (case page :appointments [["zoom" "Zoom"] ["calendar" "Sync calendar"]] :invoices [["checkout" "Checkout"]] :contracts [["sign" "Request signature"]])]
                             ^{:key action} [:button {:on-click #(rf/dispatch [:workspace-action r action])} label])])
                         (when (= page :reconciliation)
                           [:div.actions [:button {:disabled (not (allowed? state "match")) :on-click #(rf/dispatch [:bank-candidates r])} "Match"]
                            [:button {:disabled (not (allowed? state "unmatch")) :on-click #(rf/dispatch [:workspace-action r "unmatch"])} "Unmatch"]
                            [:button {:disabled (not (allowed? state "ignore")) :on-click #(rf/dispatch [:workspace-action r "ignore"])} "Ignore"]])
                         (when (contains? #{:invoices :expenses} page) [:button {:on-click #(rf/dispatch [:history page (:id r)])} "History"])
                         (when (= page :expenses) [:button {:on-click #(rf/dispatch [:expense-files (:id r)])} "Attachments"])
                         (when (= page :invoices) [:a {:href (str "/api/finance/print/invoices/" (:id r)) :target "_blank"} "Print"])
                         (when (= page :expenses) [:label.file-button "Attach receipt" [:input {:type "file" :disabled (not (allowed? state "submit"))
                                                      :on-change #(when-let [file (aget (.. % -target -files) 0)] (rf/dispatch [:expense-upload (:id r) file]))}]])
                         (when (= page :archive) [:button {:on-click #(rf/dispatch [:restore-record r])} "Restore"])
                         (when (and write? (or (and (= page :invoices) (= "Draft" (:status r)))
                                               (and (contains? #{:proposals :contracts} page) (= "Draft" (:status r)))))
                           [:button {:on-click #(rf/dispatch [:workspace-action r (if (= page :invoices) "send" "issue")])} "Issue"])
                         (when (and write? (= page :expenses))
                           [:div.actions (for [[action label] (case (:status r) "Submitted" [["approve" "Approve"] ["reject" "Reject"]]
                                                               "Approved" [["pay" "Mark paid"]] "Paid" [["reverse-expense" "Reverse"]] [])]
                             ^{:key action} [:button {:disabled (not (allowed? state action)) :on-click #(rf/dispatch [:workspace-action r action])} label])])
                         (when (and write? (= page :payments) (not (:reversesId r)))
                           [:button {:disabled (not (allowed? state "reverse")) :on-click #(rf/dispatch [:workspace-action r "reverse"])} "Reverse"])
                         (when (and write? (= page :portal) (= "Active" (:status r)))
                           [:<> [:button {:on-click #(rf/dispatch [:portal-share r])} "Share document"] [:button {:on-click #(rf/dispatch [:workspace-action r "revoke"])} "Revoke"]])
                         (when (= page :documents)
                           [:label.file-button "Upload version" [:input {:type "file" :aria-label "Upload file version"
                                :on-change #(let [file (aget (.. % -target -files) 0)
                                                  owner (or (:owner r) (when (:clientId r) (str "client:" (:clientId r)))
                                                            (when (:leadId r) (str "lead:" (:leadId r))))]
                                              (when (and file owner) (rf/dispatch [:upload owner file (:id r)])))}]])
                         (when (and write? (or (fields page) (contains? #{:proposals :contracts} page)))
                           [:<> [:button {:on-click #(rf/dispatch [:edit r])} "Edit"] [:button {:on-click #(rf/dispatch [:conflict page r])} "Compare"]])
                         (when (and write? (= page :leads) (not (:convertedClientId r)))
                           [:button {:on-click #(rf/dispatch [:record-action r "convert"])} "Convert"])
                         (when (and write? (contains? #{:leads :clients} page))
                           [:button.danger {:on-click #(rf/dispatch [:archive-record r])} "Archive"])]]])]])]))
(declare security-panel detail-panel extra-panels)
(defn workspace [state]
  (let [page (:page state) create-action (get {:payments "record" :expenses "submit" :periods "close" :payment-instructions "record"} page)
        title (or (some (fn [[_ links]] (some #(when (= page (first %)) (second %)) links)) navigation) (name page))]
    [:div.shell
     [:aside.sidebar [:a.brand {:href "#/"} "ECC" [:span "Client workspace"]]
      [:nav (for [[group links] navigation]
              ^{:key group} [:section [:p.nav-label group]
                             (for [[key label] links]
                               ^{:key key} [:a {:href (str "#/" (when-not (= key :dashboard) (name key))) :class (when (= key page) "active")}
                                           label])])]
      [:div.account [:strong (get-in state [:user :name])] [:small (get-in state [:user :role])]
       [:button {:on-click #(rf/dispatch [:logout])} "Sign out"]]]
     [:main.content
      [:header.page-header [:div [:p.eyebrow "ECC WORKSPACE"] [:h1 title]]
       (when (and (not (:editing? state)) (not= "viewer" (get-in state [:user :role]))
                  (or (nil? create-action) (allowed? state create-action))
                  (or (not= page :team) (= "admin" (get-in state [:user :role])))
                  (or (fields page) (contains? #{:proposals :contracts} page)))
         [:button.primary {:on-click #(rf/dispatch [:edit {}])} "+ New record"])]
      (when (:error state) [:p.error {:role "alert"} (:error state)])
      (when (:notice state) [:p.notice {:role "status"} (:notice state)])
      [extra-panels state]
      (when (:detail state) [detail-panel state])
      (when (= page :security) [security-panel state])
      (when (:editing? state) [editor state])
      (if (= page :dashboard) [dashboard (:data state)]
        [:<> (when-not (contains? #{:reports :sales :trends :cashflow} page)
              [:form.search {:on-submit #(do (.preventDefault %) (rf/dispatch [:search (:query state) 0]))}
              [:input {:type "search" :aria-label "Search records" :placeholder "Search records…" :value (:query state)
                       :on-change #(rf/dispatch [:field :search (.. % -target -value)])
                       :on-input #(rf/dispatch [:search (.. % -target -value) 0])}]])
         (if (:loading? state) [:p.muted {:role "status"} "Loading…"] [records-table state])
         [:div.pagination [:button {:disabled (zero? (:offset state)) :on-click #(rf/dispatch [:search (:query state) (max 0 (- (:offset state) 50))])} "Previous"]
          [:span (str (:offset state) "–" (+ (:offset state) (count (:rows state))) " of " (:total state))]
          [:button {:disabled (< (count (:rows state)) 50) :on-click #(rf/dispatch [:search (:query state) (+ (:offset state) 50)])} "Next"]]])]]))
(defn detail-panel [state]
  (let [detail (:detail state) row (or (:lead detail) (:client detail))
        owner (str (if (:lead detail) "lead:" "client:") (:id row))]
    [:section.card.detail
     [:div.page-header [:h2 (:fullName row)] [:div.actions [:button {:on-click #(rf/dispatch [:open-detail row])} "Refresh"] [:button {:on-click #(rf/dispatch [:close-detail])} "Close"]]]
     (when (and (:client detail) (:photoId row) (not (:photo-error state)))
       [:img.profile-photo {:src (str "/api/clients/" (:id row) "/photo") :alt "Client profile photo" :on-error #(rf/dispatch [:photo-error])}])
     [:p (:email row)] [:p (:phone row)] [:p (:notes row)]
     (when (:client detail) [:div.actions [:button {:on-click #(rf/dispatch [:load-profile (:id row)])} "Student profile"]
                            [:label "Update photo" [:input {:type "file" :accept "image/png,image/jpeg" :on-change #(when-let [file (aget (.. % -target -files) 0)] (rf/dispatch [:photo-upload (:id row) file]))}]]])
     [:h3 "Applications"] (for [r (:cases detail)] ^{:key (:id r)} [:p (str (:serviceCategory r) " · " (:status r))])
     [:h3 "Tasks"] (for [r (:tasks detail)] ^{:key (:id r)} [:p (str (:title r) " · " (:status r) " · " (:dueDate r))])
     [:h3 "Documents"]
     (for [r (:documents detail)] ^{:key (:id r)} [:p (:filename r) " · " (:scanStatus r)
          (when (= "Clean" (:scanStatus r)) [:a {:href (str "/api/documents/" (:id r) "/download")} " Download"])])
     [:label.field [:span "Upload a document"] [:input {:type "file" :on-change #(when-let [file (aget (.. % -target -files) 0)]
                                                                                 (rf/dispatch [:upload owner file nil]))}]]
     [:h3 "Activity"]
     (for [r (:activities detail)] ^{:key (:id r)} [:p (str (:date r) " · " (:description r))])
     [:form {:on-submit #(do (.preventDefault %) (rf/dispatch [:add-note]))}
      [input-field (:form state) [] [:note "Add a note" "textarea" true]] [:button.primary {:type "submit"} "Add note"]]]))
(defn security-panel [state]
  [:article.card [:h2 "Authenticator and password"]
   [:p.muted "Use a TOTP authenticator. Verify your password and a current code to change enrollment."]
   (when-let [secret (get-in state [:security :secret])]
     [:div [:p "Add this secret to your authenticator:"] [:code secret] [:p (get-in state [:security :uri])]])
   [input-field (:form state) [] [:password "Current password" "password"]]
   [input-field (:form state) [] [:otp "Authenticator code" "text"]]
   [input-field (:form state) [] [:currentPassword "Current password for password change" "password"]]
   [input-field (:form state) [] [:newPassword "New password (12+ characters)" "password"]]
   [:button {:on-click #(rf/dispatch [:password])} "Change password"]
   (when-let [codes (get-in state [:security :recoveryCodes])]
     [:section [:h3 "Save these recovery codes now"] [:ul (for [code codes] ^{:key code} [:li [:code code]])]])
   (when (= "admin" (get-in state [:user :role]))
     [:section [:h3 "Manage account security"] [input-field (:form state) [] [:user "Staff account ID" "number"]]
      [:div.actions (for [[action label] [["reset-mfa" "Reset staff authenticator"] ["revoke-user" "Revoke staff sessions"] ["suspend" "Suspend account"] ["resume" "Resume account"]]]
                      ^{:key action} [:button {:on-click #(rf/dispatch [:admin-security action])} label])]])
   [:div.actions (for [[action label] [["setup" "Set up authenticator"] ["enable" "Enable authenticator"] ["disable" "Disable authenticator"]]]
                   ^{:key action} [:button {:on-click #(rf/dispatch [:security action])} label])]])
(defn portal-page [state]
  (let [data (:portal-data state)]
    [:main.portal-content
     [:header [:div.brand "ECC"] [:h1 "Your client portal"] [:p.muted (get-in data [:client :fullName])]
              [:button {:on-click #(rf/dispatch [:portal-logout])} "Close portal"]]
     (when (:error state) [:p.error {:role "alert"} (:error state)])
     (if (:portal-closed? state) [:p.notice "Portal session closed. Ask your case officer for a new link when needed."]
       (if (:loading? state) [:p "Opening your portal…"]
       [:<> [:section.card [:h2 "Applications"]
             (for [r (:applications data)] ^{:key (:id r)} [:p (str (:serviceCategory r) " · " (:status r (:stage r)))])]
        [:section.card [:h2 "Document checklist"]
         (for [r (:requests data)] ^{:key (:id r)} [:p (:title r) [:span.badge (:status r)] [:input {:type "file" :on-change #(when-let [file (aget (.. % -target -files) 0)] (rf/dispatch [:portal-upload (:id r) file]))}]])]
        [:section.card [:h2 "Files"]
         (for [r (:documents data)] ^{:key (:id r)} [:p [:a {:href (str "/api/portal/documents/" (:id r))} (:filename r)]])]
        [:section.card [:h2 "Proposals and contracts"]
         [input-field (:form state) [] [:signature "Your full name to accept a document" "text"]]
         (for [r (:commercial data)]
           ^{:key (str (:kind r) (:id r))} [:article.commercial [:h3 (:title r)] [:p (:body r)] [:p (:status r)] [:a {:href (str "/api/portal/commercial/" (:id r) "/download?kind=" (:kind r))} "Download document"]
             (when (contains? #{"Issued" "Viewed"} (:status r))
               [:div.actions [:button.primary {:on-click #(rf/dispatch [:portal-action (:kind r) (:id r) "accept"])} "Accept"]
                [:button {:on-click #(rf/dispatch [:portal-action (:kind r) (:id r) "decline"])} "Decline"]])])]
        [:section.card [:h2 "Invoices"] (for [r (:invoices data)] ^{:key (:id r)} [:p (str (:description r) " · " (:currency r) " " (/ (:amountMinor r) 100) " · " (:status r))])]
        [:section.card [:h2 "Bank payment instructions"] (for [r (:paymentInstructions data)] ^{:key (:id r)} [:article [:h3 (:bank r)] [:p (:accountName r)] [:p (:accountNumber r)] [:p (:method r)] [:p (:instructions r)]])]
        [:section.card [:h2 "Receipts"] (for [r (:receipts data)] ^{:key (:id r)} [:p [:a {:href (str "/api/portal/receipts/" (:id r) "/download")} (str "Receipt #" (:id r) " · " (:currency r) " " (/ (:amountMinor r) 100))]])]
        [:section.card [:h2 "Payments and signed documents"]
         (for [r (:integrations data)] ^{:key (:id r)} [:p (:status r)
           (when (:checkoutUrl r) [:a {:href (:checkoutUrl r) :rel "noopener noreferrer"} " Pay invoice"])
           (when (:signedPdfReady r) [:a {:href (str "/api/portal/signatures/" (:id r) "/download")} " Download signed agreement"])])]
        [:section.card [:h2 "Messages"] (for [r (:messages data)] ^{:key (:id r)} [:article [:h3 (:title r)] [:p (:body r)]])]]))]))
(defn reset-page [state]
  [:main.login [:form.card {:on-submit #(do (.preventDefault %) (rf/dispatch [:reset-password]))}
                [:h1 "Reset your password"]
                [input-field (:form state) [] [:password "New password (12+ characters)" "password" true]]
                [:button.primary {:type "submit"} "Reset password"]
                (when (:error state) [:p.error (:error state)]) (when (:notice state) [:p.notice (:notice state)])]])
(def profile-fields [[:preferredName "Preferred name" "text"] [:dateOfBirth "Date of birth" "date"] [:institution "Institution" "text"] [:program "Program" "text"] [:intakeDate "Intake" "date"] [:qualification "Qualification" "text"] [:nationality "Nationality" "text"]
                     [:passportNumber "Passport number" "text"] [:passportExpiry "Passport expiry" "date"] [:address "Address" "textarea"]
                     [:emergencyName "Emergency contact" "text"] [:emergencyPhone "Emergency phone" "tel"] [:education "Education" "textarea"] [:occupation "Occupation" "text"]])
(def privilege-labels [["edit" "Edit records"] ["delete" "Archive records"] ["download" "Download files"] ["export" "Export reports"] ["email" "Send email"] ["portal" "Manage portal"]
                       ["sales_view" "View sales"] ["finance_view" "View finance"] ["payments_record" "Record payments"] ["expenses_record" "Record expenses"]
                       ["expenses_approve" "Approve expenses"] ["finance_periods" "Manage periods"] ["finance_reconcile" "Reconcile bank entries"]])
(defn extra-panels [state]
  [:<>
   (when (contains? #{:reports :sales :trends :cashflow} (:page state))
     [:form.card {:on-submit #(do (.preventDefault %) (rf/dispatch [:report-range]))}
      [:div.form-grid [input-field (:form state) [] [:fromDate "From" "date"]] [input-field (:form state) [] [:toDate "To" "date"]]]
      [:button {:type "submit"} "Apply date range"]])
   (when (:expense-files state) [:section.card [:h2 "Expense attachments"]
      (for [file (:expense-files state)] ^{:key (:id file)} [:p (:filename file) " · " (:scanStatus file)
        (when (= "Clean" (:scanStatus file)) [:a {:href (str "/api/documents/" (:id file) "/download")} " Download"])])])
   (when (contains? #{:reports :sales :ageing :bottlenecks :trends :cashflow :balances :payments :expenses :finance-audit} (:page state))
     [:p [:a {:href (str "/api/workspace/" (if (contains? #{:reports :ageing :bottlenecks :trends} (:page state)) "report-export/" "finance-export/") (name (:page state)) "?q=" (js/encodeURIComponent (:query state)))} "Export CSV"]])
   (when (= :appointments (:page state)) [:p [:a {:href "/api/workspace/calendar.ics"} "Download calendar"]])
   (when (:portal-share-target state)
     [:section.card [:h2 "Share an approved document"]
      [:p.muted "Only a current, approved, clean and unexpired checklist version can be shared with this portal link."]
      [input-field (:form state) [] [:documentId "Document ID" "number" true]]
      [:div.actions [:button {:on-click #(rf/dispatch [:portal-document-access "grant"])} "Grant access"]
       [:button {:on-click #(rf/dispatch [:portal-document-access "ungrant"])} "Remove access"]]])
   (when (:profile-open? state)
     [:form.card {:on-submit #(do (.preventDefault %) (rf/dispatch [:save-profile]))}
      [:h2 "Student profile"] [:div.form-grid (for [field profile-fields] ^{:key (first field)} [input-field (:form state) [] field])]
      [:button.primary {:type "submit"} "Save profile"]])
   (when (:template-application state)
     [:section.card [:h2 "Apply a checklist template"]
      (for [template (:templates state)] ^{:key (:id template)} [:p (:title template) " " [:button {:on-click #(rf/dispatch [:apply-template template])} "Apply"]])])
   (when (= :reconciliation (:page state))
     [:section.card [:h2 "Import a bank statement"] [:p.muted "CSV columns: date, amount, currency, reference, description. Use negative amounts for outgoing payments."]
      [input-field (:form state) [] [:account "Bank account label" "text"]]
      [:input {:type "file" :accept ".csv,text/csv" :disabled (not (allowed? state "import")) :on-change #(when-let [file (aget (.. % -target -files) 0)] (rf/dispatch [:bank-import-file file]))}]
      (when (:bank-candidates state) [:div [:h3 "Matching posted entries"]
                                    (for [entry (:bank-candidates state)] ^{:key (str (:kind entry) (:id entry))}
                                      [:p (str (:kind entry) " #" (:id entry) " · " (:currency entry) " " (/ (:amountMinor entry) 100))
                                       " " [:button {:on-click #(rf/dispatch [:bank-match entry])} "Match entry"]])])])
   (when (:financial-history state) [:section.card [:h2 "Posted history"]
                                     (for [entry (:financial-history state)] ^{:key (:id entry)} [:p (str (:date entry) " · " (:action entry) " · Actor " (:actorId entry))])])
   (when (:access-target state)
     [:form.card {:on-submit #(do (.preventDefault %) (rf/dispatch [:admin-security "access"]))}
      [:h2 (str "Access for " (get-in state [:access-target :name]))]
      [input-field (:form state) [] [:accessLevel "Record access" ["all" "assigned"]]]
      [:div.form-grid (for [[privilege label] privilege-labels] ^{:key privilege} [:label [:input {:type "checkbox" :checked (boolean (some #{privilege} (get-in state [:form :privileges])))
                                                                                              :on-change #(rf/dispatch [:toggle-privilege privilege])}] " " label])]
      [input-field (:form state) [] [:password "Your password to confirm" "password" true]] [:button.primary {:type "submit"} "Save access"]])
   (when (= :notifications (:page state))
     [:form.card {:on-submit #(do (.preventDefault %) (rf/dispatch [:save-preferences]))} [:h2 "Notification preferences"]
      (for [field [[:assignments "Assignments" "checkbox"] [:deadlines "Deadlines" "checkbox"] [:documents "Documents" "checkbox"] [:escalations "Escalations" "checkbox"] [:emailEnabled "Email notifications" "checkbox"]]]
        ^{:key (first field)} [input-field (:form state) [] field]) [:button {:type "submit"} "Save preferences"]])
   (when (= :search (:page state))
     [:section.card [:h2 "Saved views"]
      [input-field (:form state) [] [:title "View name" "text"]] [input-field (:form state) [] [:entity "Records" ["leads" "clients" "tasks" "cases"]]]
      [input-field (:form state) [] [:query "Search text" "text"]] [input-field (:form state) [] [:mine "Assigned to me" "checkbox"]] [input-field (:form state) [] [:overdue "Overdue only" "checkbox"]]
      [:div.actions [:button {:on-click #(rf/dispatch [:saved-view-action "save" nil])} "Save view"] [:button {:on-click #(rf/dispatch [:saved-views])} "Load my views"]]
      (for [view (:saved-views state)] ^{:key (:id view)} [:p (:title view) " " [:button {:on-click #(rf/dispatch [:apply-view view])} "Apply view"]
                                                        [:button {:on-click #(rf/dispatch [:saved-view-action "delete" view])} "Delete view"]])])
   (when (:conflict state) [:section.card [:h2 "Current server values"]
                            [:dl (for [[field value] (select-keys (:conflict state) [:fullName :title :notes :description :stage :status :revision])]
                                   ^{:key field} [:div [:dt (name field)] [:dd (str value)]])]
                            [:button {:on-click #(rf/dispatch [:edit (:conflict state)])} "Use server values"]])])
(defn app [] (let [state @(rf/subscribe [:state])]
              (cond (:portal? state) [portal-page state] (:reset-token state) [reset-page state]
                    (:user state) [workspace state] :else [login state])))
(def router (routing/router (into [["/" {:name :dashboard}]] (for [[_ links] navigation [page _] links :when (not= page :dashboard)]
                                                                           [(str "/" (name page)) {:name page}]))))
(defonce root (atom nil))
(defn route-change [match _]
  (let [state @(rf/subscribe [:state]) hash (.-hash js/location)
        params (js/URLSearchParams. (or (second (str/split hash #"\?" 2)) "")) token (.get params "token")
        reset? (str/starts-with? hash "#/reset") public? (or (str/starts-with? hash "#/client-portal") (and token (not reset?)))]
    (cond
      public? (when (or token (not (:portal? state)))
                (rf/dispatch [:initialize :portal token])
                (when token (.replaceState js/history nil "" (str (.-pathname js/location) "#/client-portal"))))
      (and reset? token) (do (rf/dispatch [:initialize :reset token])
                             (.replaceState js/history nil "" (str (.-pathname js/location) "#/reset")))
      match (if (or (:portal? state) (:reset-token state))
              (rf/dispatch [:initialize nil nil (get-in match [:data :name])])
              (rf/dispatch [:navigate (get-in match [:data :name])])))))
(defn ^:export init []
  (let [hash (.-hash js/location) query (second (str/split hash #"\?" 2))
        params (js/URLSearchParams. (or query "")) token (.get params "token")
        reset? (str/starts-with? hash "#/reset") portal? (or (str/starts-with? hash "#/client-portal") (and token (not reset?)))
        mode (cond reset? :reset portal? :portal :else nil)]
    (rf/dispatch-sync [:initialize mode token])
    (when token (.replaceState js/history nil "" (str (.-pathname js/location) (if reset? "#/reset" "#/client-portal")))))
  (history/start! router route-change {:use-fragment true})
  (reset! root (dom/create-root (.getElementById js/document "app")))
  (dom/render @root [app]))

(init)
