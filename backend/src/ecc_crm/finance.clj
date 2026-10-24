(ns ecc-crm.finance
  (:require [clojure.string :as str]
            [ecc-crm.domain :as d] [ecc-crm.store :as store])
  (:import [java.math BigDecimal RoundingMode]
           [java.time LocalDate]))

(defn minor [value]
  (try
    (let [v (bigdec (str value)) cents (.longValueExact (.movePointRight (.setScale v 2 RoundingMode/UNNECESSARY) 2))]
      (when (or (neg? cents) (> cents 100000000000)) (d/fail 400 "Amount is outside the allowed range")) cents)
    (catch Exception _ (d/fail 400 "Enter an amount with at most two decimal places"))))
(defn money [cents] (format "%.2f" (/ (double cents) 100)))
(defn currency [v] (let [s (str/upper-case (str v))]
                     (when-not (re-matches #"[A-Z]{3}" s) (d/fail 400 "Use a three-letter currency code")) s))
(defn valid-date [v]
  (try (str (LocalDate/parse v)) (catch Exception _ (d/fail 400 "Choose a valid date"))))
(defn open-period! [s date]
  (valid-date date)
  (when (some #(and (= "Closed" (:status %)) (<= (compare (:from %) date) 0)
                    (<= (compare date (:to %)) 0)) (d/rows s :periods))
    (d/fail 409 "This accounting period is closed")))
(defn balance [s invoice]
  (let [paid (reduce + 0 (map :amountMinor (store/matching (:payments s {}) :invoiceId (:id invoice))))]
    (assoc invoice :paidMinor paid :balanceMinor (- (:amountMinor invoice 0) paid)
           :amount (money (:amountMinor invoice 0)) :paid (money paid) :balance (money (- (:amountMinor invoice 0) paid)))))
(defn invoice-save [s u input]
  (d/admin! u)
  (let [input (d/owner-input s u input)
        _ (when-not (:clientId input) (d/fail 400 "Invoices require a client"))
        old (when (:id input) (d/accessible! s u :invoices (:id input)))
        _ (when (and old (not= "Draft" (:status old))) (d/fail 409 "Issued invoices cannot be edited"))
        subtotal (minor (:subtotal input (:amount input))) discount (minor (:discount input "0")) tax (minor (:tax input "0"))
        total (- (+ subtotal tax) discount)
        _ (when (<= total 0) (d/fail 400 "Invoice total must be positive"))
        input (assoc input :currency (currency (:currency input "PHP")) :amountMinor total
                     :subtotalMinor subtotal :taxMinor tax :discountMinor discount :dueDate (valid-date (:dueDate input)))]
    (d/save! s u :invoices input [:clientId :caseId :title :description :currency :amountMinor :subtotalMinor
                                 :discountMinor :taxMinor :dueDate :lineItems] {:status "Draft"})))
(defn issue-invoice [s u input]
  (d/admin! u)
  (let [r (d/accessible! s u :invoices (:id input))]
    (d/version! r input)
    (when-not (= "Draft" (:status r)) (d/fail 409 "Select a draft invoice"))
    (open-period! s (d/today))
    (let [[s r] (d/replace-row s :invoices r {:status "Issued" :issuedAt (d/now)})]
      [(d/audit s u :invoices r "issued") r])))
(defn payment [s u action input]
  (d/writer! u) (d/choice action ["record" "reverse"]) (d/privilege! u "finance_view") (d/privilege! u "payments_record")
  (let [key (d/required input :submissionKey 200)
        existing (get-in s [:submissions [(:id u) key]])]
    (if existing [s existing]
      (let [reversed (when (= action "reverse") (d/record s :payments (:id input)))
            invoice (d/accessible! s u :invoices (or (:invoiceId reversed) (d/integer (:invoiceId input))))
            _ (when-not (contains? #{"Issued" "Paid"} (:status invoice)) (d/fail 409 "Invoice must be issued"))
            _ (when reversed
                (when (or (:reversesId reversed) (some #(= (:id reversed) (:reversesId %)) (d/rows s :payments)))
                  (d/fail 409 "Payment is already reversed")))
            amount (if reversed (- (:amountMinor reversed)) (minor (:amount input)))
            _ (when (or (zero? amount) (and (pos? amount) (> amount (:balanceMinor (balance s invoice)))))
                (d/fail 400 "Payment exceeds the outstanding balance or is zero"))
            date (valid-date (:paidOn input (d/today)))
            _ (open-period! s date)
            [s r] (d/insert s :payments {:invoiceId (:id invoice) :clientId (:clientId invoice)
                                         :currency (:currency invoice) :amountMinor amount :paidOn date
                                         :method (:method input) :reference (:reference input) :reason (:reason input)
                                         :reversesId (:id reversed) :actorId (:id u)})
            status (if (zero? (:balanceMinor (balance s invoice))) "Paid" "Issued")
            s (assoc-in s [:invoices (:id invoice) :status] status)
            s (d/audit s u :payments r (if reversed "reversed" "recorded"))]
        [(assoc-in s [:submissions [(:id u) key]] r) r]))))
(defn expense [s u action input]
  (d/writer! u) (d/privilege! u "finance_view")
  (d/privilege! u (if (contains? #{"approve" "reject" "reverse-expense"} action) "expenses_approve" "expenses_record"))
  (if (= action "submit")
    (let [date (valid-date (:expenseOn input)) _ (open-period! s date)]
      (d/save! s u :expenses
               (assoc input :amountMinor (minor (:amount input)) :currency (currency (:currency input))
                      :createdBy (:id u))
               [:supplier :description :category :currency :amountMinor :expenseOn :reference :createdBy]
               {:status "Submitted"}))
    (let [old (d/record s :expenses (:id input)) _ (d/version! old input)
          status (case action "approve" "Approved" "reject" "Rejected" "pay" "Paid" "reverse-expense" "Reversed"
                       (d/fail 404 "Unknown expense action"))
          allowed (case action "approve" #{"Submitted"} "reject" #{"Submitted"} "pay" #{"Approved"} "reverse-expense" #{"Paid"})]
      (when-not (allowed (:status old)) (d/fail 409 "Expense state does not allow this action"))
      (when (and (= action "approve") (= (:id u) (:createdBy old))) (d/fail 403 "A different approver must approve this expense"))
      (open-period! s (d/today))
      (let [date (valid-date (:postedOn input (d/today))) _ (open-period! s date)
            [s row] (d/replace-row s :expenses old {:status status :reviewNote (:reviewNote input) :reviewedBy (:id u)})
            s (if (contains? #{"pay" "reverse-expense"} action)
                (let [original (when (= "reverse-expense" action) (first (filter #(and (= (:id old) (:expenseId %)) (nil? (:reversesId %))) (d/rows s :expenseEntries))))
                      _ (when (= "reverse-expense" action) (d/required input :reason 2000))]
                  (first (d/insert s :expenseEntries {:expenseId (:id old) :amountMinor (if (= action "pay") (:amountMinor old) (- (:amountMinor old)))
                                                      :currency (:currency old) :postedOn date :method (:method input) :reference (:reference input)
                                                      :reason (:reason input) :reversesId (:id original) :actorId (:id u)}))) s)]
        [(d/audit s u :expenses row action) row]))))
(defn period [s u action input]
  (d/writer! u) (d/privilege! u "finance_periods")
  (if (= action "close")
    (let [from (valid-date (:from input)) to (valid-date (:to input))]
      (when (pos? (compare from to)) (d/fail 400 "End date precedes start date"))
      (let [[s r] (d/insert s :periods {:from from :to to :status "Closed" :reason (d/required input :reason 2000)})]
        [(d/audit s u :periods r "closed") r]))
    (let [r (d/record s :periods (:id input))]
      (d/version! r input)
      (let [[s r] (d/replace-row s :periods r {:status "Open" :reason (d/required input :reason 2000)})]
        [(d/audit s u :periods r "reopened") r]))))
(defn summary [s u]
  (d/privilege! u "finance_view")
  (->> (d/rows s :invoices) (filter #(and (d/visible? s u :invoices %) (contains? #{"Issued" "Paid"} (:status %))))
       (map #(balance s %)) (group-by :currency)
       (mapv (fn [[currency invoices]]
               {:currency currency :invoiced (money (reduce + 0 (map :amountMinor invoices)))
                :collected (money (reduce + 0 (map :paidMinor invoices)))
                :outstanding (money (reduce + 0 (map :balanceMinor invoices)))}))))
