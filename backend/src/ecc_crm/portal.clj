(ns ecc-crm.portal
  (:require [clojure.string :as str]
            [ecc-crm.domain :as d]
            [ecc-crm.auth :as auth]
            [ecc-crm.files :as files] [ecc-crm.finance :as finance])
  (:import [java.time Instant]))
(defn approvable? [s link doc]
  (and (= (:clientId link) (:clientId doc)) (= "Clean" (:scanStatus doc)) (not (:deletedAt doc))
       (some #(and (= (:clientId link) (:clientId %)) (= (:id doc) (:documentId %)) (= "Approved" (:status %))
                   (or (empty? (:expiresOn %)) (not (neg? (compare (:expiresOn %) (d/today)))))) (d/rows s :checklists))))
(defn shared? [s link doc]
  (and (get-in s [:portalGrants [(:id link) (:id doc)]]) (approvable? s link doc)))
(defn manage [s u action input]
  (d/writer! u) (d/privilege! u "portal")
  (case action
    "create" (let [input (d/owner-input s u input) cid (:clientId input) token (auth/token)]
               (when-not cid (d/fail 400 "Choose a client"))
               (let [[s row] (d/insert s :portalLinks {:clientId cid :tokenHash (auth/digest token)
                                                       :expiresAt (str (.plusSeconds (Instant/now) (* 7 86400))) :status "Active"})]
                 [s {:id (:id row) :token token :url (str (:publicUrl input "") "/#/client-portal?token=" token)}]))
    "grant" (let [link (d/accessible! s u :portalLinks (:id input)) doc (d/accessible! s u :documents (:documentId input))]
              (when-not (approvable? s link doc) (d/fail 400 "Only the latest approved, clean and unexpired checklist version can be shared"))
              [(assoc-in s [:portalGrants [(:id link) (:id doc)]] {:linkId (:id link) :documentId (:id doc)}) {:message "Document access granted"}])
    "ungrant" (let [link (d/accessible! s u :portalLinks (:id input))]
                [(update s :portalGrants dissoc [(:id link) (d/integer (:documentId input))]) {:message "Document access removed"}])
    "revoke" (let [r (d/accessible! s u :portalLinks (:id input))]
               (d/replace-row s :portalLinks r {:status "Revoked"}))
    (d/fail 404 "Unknown portal action")))
(defn link [s token]
  (or (some #(when (and (= (auth/digest token) (:tokenHash %)) (= "Active" (:status %)) (not (:activatedAt %)) (auth/unexpired? %)) %)
            (d/rows s :portalLinks)) (d/fail 401 "Portal link is invalid or expired")))
(defn session [s token]
  (let [entry (get-in s [:portalSessions (auth/digest token)])
        r (get-in s [:portalLinks (:linkId entry)])]
    (when-not (and (auth/unexpired? entry) (= "Active" (:status r)) (auth/unexpired? r)
                   (not (:deletedAt (get-in s [:clients (:clientId r)]))))
      (d/fail 401 "Portal session is invalid or expired")) r))
(defn exchange [s input]
  (let [r (link s (:token input)) token (auth/token)]
    [(assoc-in (assoc-in s [:portalLinks (:id r) :activatedAt] (d/now)) [:portalSessions (auth/digest token)] {:linkId (:id r) :expiresAt (str (.plusSeconds (Instant/now) 3600))})
     {:token token :expiresAt (str (.plusSeconds (Instant/now) 3600))}]))
(defn view [s r]
  (let [cid (:clientId r)]
    {:client (select-keys (d/record s :clients cid) [:id :fullName :clientNumber])
     :documents (mapv #(select-keys % [:id :filename :size :scanStatus])
                      (filter #(shared? s r %) (d/related s :documents :clientId cid)))
     :requests (mapv #(select-keys % [:id :title :status :expiresOn]) (d/related s :checklists :clientId cid))
     :applications (mapv #(select-keys % [:id :serviceCategory :status :stage :destination]) (d/related s :cases :clientId cid))
     :appointments (mapv #(select-keys % [:id :title :startsAt :endsAt :meetingUrl :location])
                        (filter :clientVisible (d/related s :appointments :clientId cid)))
     :commercial (vec (for [table [:proposals :contracts] doc (d/related s table :clientId cid)
                           :when (not= "Draft" (:status doc))]
                       (assoc (select-keys doc [:id :title :body :currency :totalMinor :status :validUntil]) :kind (name table))))
     :invoices (mapv #(select-keys % [:id :title :description :currency :amountMinor :dueDate :status])
                    (filter #(contains? #{"Issued" "Paid"} (:status %)) (d/related s :invoices :clientId cid)))
     :paymentInstructions (mapv #(select-keys % [:id :invoiceId :bank :accountName :accountNumber :method :instructions]) (d/related s :paymentInstructions :clientId cid))
     :receipts (vec (for [payment (d/rows s :payments) :when (= cid (:clientId (get-in s [:invoices (:invoiceId payment)])))]
                      (select-keys payment [:id :invoiceId :currency :amountMinor :paidOn :method :reference :reversesId])))
     :integrations (vec (for [link (d/related s :integrationLinks :clientId cid)]
                         {:id (:id link) :kind (:table link) :recordId (:recordId link) :status (:status link)
                          :checkoutUrl (when (and (= "stripe" (:provider link)) (= "Open" (:status link))
                                                   (= "Issued" (get-in s [:invoices (:recordId link) :status]))
                                                   (= (:amountMinor link) (:balanceMinor (finance/balance s (get-in s [:invoices (:recordId link)]))))) (:url link))
                          :signedPdfReady (and (:signedDocumentId link) (= "Clean" (get-in s [:documents (:signedDocumentId link) :scanStatus])))}))
     :messages (mapv #(select-keys % [:id :title :body :createdAt :direction])
                    (filter :clientVisible (d/related s :messages :clientId cid)))}))
(defn commercial-action [s link table id action input]
  (let [doc (d/record s table id)]
    (when (or (not= (:clientId link) (:clientId doc)) (= "Draft" (:status doc))) (d/fail 404 "Document not found"))
    (when (and (:validUntil doc) (neg? (compare (:validUntil doc) (d/today)))) (d/fail 409 "Document has expired"))
    (when-not (contains? #{"Issued" "Viewed"} (:status doc)) (d/fail 409 "Document has already been answered"))
    (let [status (case action "accept" "Accepted" "decline" "Declined" "view" "Viewed" (d/fail 404 "Unknown action"))
          name (when (= action "accept") (d/required input :name 255))
          [s row] (d/replace-row s table doc {:status status :signedName name :respondedAt (d/now)})]
      [(d/audit s nil table row (str "portal." action)) {:status status}])))
