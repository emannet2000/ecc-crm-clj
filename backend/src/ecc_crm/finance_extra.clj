(ns ecc-crm.finance-extra
  (:require [clojure.string :as str] [clojure.data.csv :as csv] [ecc-crm.domain :as d]
            [ecc-crm.auth :as auth] [ecc-crm.finance :as f] [ecc-crm.files :as files])
  (:import [java.io StringReader]))
(defn signed-minor [v] (if (str/starts-with? (str v) "-") (- (f/minor (subs (str v) 1))) (f/minor v)))
(defn reconciliation [s u action input]
  (d/writer! u) (d/privilege! u "finance_view") (d/privilege! u "finance_reconcile")
  (case action
    "import" (let [content (d/required input :csv (* 2 1024 1024)) rows (csv/read-csv (StringReader. content))
                   header (mapv #(keyword (str/trim %)) (first rows))
                   _ (when-not (every? (set header) [:date :amount :currency :reference]) (d/fail 400 "CSV requires date,amount,currency,reference columns"))
                   data (mapv #(zipmap header %) (rest rows)) _ (when (> (count data) 5000) (d/fail 400 "Import at most 5000 bank lines"))]
               (reduce (fn [[s result] row]
                         (let [date (f/valid-date (:date row)) amount (signed-minor (:amount row)) currency (f/currency (:currency row))
                               key (auth/digest (pr-str [(:account input) date amount currency (:reference row)]))]
                           (f/open-period! s date)
                           (if (get-in s [:bankImports key]) [s result]
                             (let [[s line] (d/insert s :bankEntries {:account (:account input) :date date :amountMinor amount :currency currency
                                                                     :reference (:reference row) :description (:description row) :status "Unmatched"})]
                               [(assoc-in s [:bankImports key] (:id line)) (conj result line)])))) [s []] data))
    (let [line (d/record s :bankEntries (:id input)) _ (d/version! line input) _ (f/open-period! s (:date line))]
      (case action
        "match" (let [kind (d/choice (:kind input "payment") ["payment" "expense"])
                      table (if (= kind "payment") :payments :expenses)
                      entry (d/record s table (:entryId input))
                      _ (when (= table :payments) (d/accessible! s u :invoices (:invoiceId entry)))
                      amount (if (= table :expenses) (- (:amountMinor entry)) (:amountMinor entry))]
                  (when (or (not= "Unmatched" (:status line)) (not= (:currency line) (:currency entry))
                            (not= amount (:amountMinor line)) (:reversesId entry)
                            (and (= table :expenses) (not= "Paid" (:status entry)))
                            (some #(and (= "Matched" (:status %)) (= kind (:matchKind %)) (= (:id entry) (:entryId %))) (d/rows s :bankEntries))
                            (and (= table :payments) (some #(= (:id entry) (:reversesId %)) (d/rows s :payments))))
                    (d/fail 409 "Bank line and posted entry cannot be matched"))
                  (let [[s row] (d/replace-row s :bankEntries line {:status "Matched" :matchKind kind :entryId (:id entry)})]
                    [(d/audit s u :bankEntries row "matched") row]))
        "unmatch" (let [_ (d/required input :reason 2000) [s row] (d/replace-row s :bankEntries line {:status "Unmatched" :entryId nil :matchKind nil :reason (:reason input)})]
                    [(d/audit s u :bankEntries row "unmatched") row])
        "ignore" (let [_ (when-not (= "Unmatched" (:status line)) (d/fail 409 "Unmatch this bank line first"))
                       [s row] (d/replace-row s :bankEntries line {:status "Ignored" :reason (d/required input :reason 2000)})]
                   [(d/audit s u :bankEntries row "ignored") row])
        (d/fail 404 "Unknown reconciliation action")))))
(defn candidates [s u id]
  (d/privilege! u "finance_view") (d/privilege! u "finance_reconcile")
  (let [line (d/record s :bankEntries id)]
    (vec (concat (for [r (d/rows s :payments) :when (and (= (:currency r) (:currency line)) (= (:amountMinor r) (:amountMinor line))
                         (d/visible? s u :invoices (d/record s :invoices (:invoiceId r))) (not (:reversesId r)))] (assoc r :kind "payment"))
                 (for [r (d/rows s :expenses) :when (and (= "Paid" (:status r)) (= (:currency r) (:currency line)) (= (- (:amountMinor r)) (:amountMinor line)))]
                   (assoc r :kind "expense"))))))
(defn expense-file [s u id input]
  (d/writer! u) (d/privilege! u "finance_view") (d/privilege! u "expenses_record")
  (d/record s :expenses id)
  ;; Finance files use the same immutable quarantine pipeline, without exposing a client record.
  (let [virtual-id -1 virtual (assoc-in s [:clients virtual-id] {:id virtual-id :fullName "Financial file"})
        [next doc] (files/upload virtual (assoc u :role "admin") :clients virtual-id input)
        doc (-> doc (dissoc :clientId) (assoc :expenseId (d/integer id) :uploadedBy (:id u)))
        next (-> next (update :clients dissoc virtual-id) (assoc-in [:documents (:id doc)] doc))]
    [(d/audit next u :expenses {:id (d/integer id)} "attachment.uploaded") doc]))
(defn history [s u table id]
  (d/privilege! u "finance_view")
  (if (= table :expenses) (d/record s table id) (d/accessible! s u table id))
  (vec (filter #(and (= (name table) (:entityType %)) (= (d/integer id) (:entityId %))) (d/rows s :audit))))
(def action-privileges {"record" "payments_record" "reverse" "payments_record" "submit" "expenses_record" "pay" "expenses_record"
                       "approve" "expenses_approve" "reject" "expenses_approve" "reverse-expense" "expenses_approve"
                       "close" "finance_periods" "reopen" "finance_periods" "match" "finance_reconcile" "unmatch" "finance_reconcile"
                       "import" "finance_reconcile" "ignore" "finance_reconcile" "export" "export" "download" "download"})
(defn permissions [u]
  (into {} (for [[action privilege] action-privileges]
             [action (try (d/privilege! u privilege) (when-not (contains? #{"download" "export"} action) (d/writer! u)) true
                          (catch clojure.lang.ExceptionInfo _ false))])))
