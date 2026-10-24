(ns ecc-crm.reports
  (:require [clojure.string :as str] [ecc-crm.domain :as d] [ecc-crm.finance :as f])
  (:import [java.time LocalDate Instant] [java.time.temporal ChronoUnit]))
(defn range! [query]
  (let [[a b] (str/split (or query "") #"," -1) from (if (str/blank? a) "0001-01-01" a) to (if (str/blank? b) "9999-12-31" b)]
    (f/valid-date from) (f/valid-date to) (when (pos? (compare from to)) (d/fail 400 "End date precedes start date")) [from to]))
(defn in-range? [[from to] date]
  (when date (let [date (subs (str date) 0 (min 10 (count (str date))))]
               (and (<= (compare from date) 0) (<= (compare date to) 0)))))
(defn days [a b] (try (.between ChronoUnit/DAYS (LocalDate/parse a) (LocalDate/parse b)) (catch Exception _ 0)))
(defn finance-summary [s u query]
  (d/privilege! u "finance_view")
  (let [range (range! query)
        invoices (filter #(and (d/visible? s u :invoices %) (contains? #{"Issued" "Paid"} (:status %)) (in-range? range (:issuedAt % (:createdAt %)))) (d/rows s :invoices))
        payments (filter #(and (d/visible? s u :invoices (get-in s [:invoices (:invoiceId %)])) (in-range? range (:paidOn %))) (d/rows s :payments))
        expenses (if (seq (:expenseEntries s))
                   (map #(assoc % :currency (:currency (get-in s [:expenses (:expenseId %)])))
                        (filter #(in-range? range (:postedOn %)) (d/rows s :expenseEntries)))
                   (filter #(and (= "Paid" (:status %)) (in-range? range (:expenseOn %))) (d/rows s :expenses)))
        currencies (set (keep :currency (concat invoices payments expenses)))]
    (mapv (fn [currency]
            (let [sum (fn [rows] (reduce + 0 (map :amountMinor (filter #(= currency (:currency %)) rows))))
                  received (sum payments) spent (sum expenses)
                  outstanding (reduce + 0 (map #(:balanceMinor (f/balance s %)) (filter #(= currency (:currency %)) invoices)))]
              {:id currency :title currency :currency currency :invoiced (f/money (sum invoices)) :collected (f/money received)
               :expenses (f/money spent) :net (f/money (- received spent)) :outstanding (f/money outstanding)})) (sort currencies))))
(defn rows [s u kind query]
  (let [range (when (contains? #{"sales" "reports" "trends" "cashflow"} kind) (range! query))
        leads (filter #(d/visible? s u :leads %) (d/rows s :leads))
        cases (filter #(d/visible? s u :cases %) (d/rows s :cases))]
    (case kind
      "cashflow" (finance-summary s u query)
      "sales" (do (d/privilege! u "sales_view")
                  (vec (for [[source records] (group-by #(or (:source %) "Unspecified") (filter #(in-range? range (:createdAt %)) leads))]
                         {:id source :title source :source source :leads (count records) :converted (count (filter :convertedClientId records))
                          :conversionRate (format "%.2f" (* 100.0 (/ (count (filter :convertedClientId records)) (count records))))})))
      "ageing" (do (d/privilege! u "finance_view")
                   (vec (for [invoice (d/rows s :invoices) :when (and (d/visible? s u :invoices invoice) (contains? #{"Issued" "Paid"} (:status invoice)))
                              :let [r (f/balance s invoice) overdue (max 0 (days (:dueDate r) (d/today)))] :when (pos? (:balanceMinor r))]
                          (assoc r :title (:fullName (get-in s [:clients (:clientId r)])) :overdueDays overdue
                                 :bucket (cond (zero? overdue) "Current" (<= overdue 30) "1–30" (<= overdue 60) "31–60" (<= overdue 90) "61–90" :else "90+")))))
      "bottlenecks" (do (d/admin! u)
                        (vec (for [[stage records] (group-by #(or (:status %) (:stage %)) cases)]
                               {:id stage :title stage :stage stage :applications (count records)
                                :averageDays (if (seq records) (quot (reduce + (map #(days (subs (:createdAt % (d/now)) 0 10) (d/today)) records)) (count records)) 0)})))
      "trends" (do (d/admin! u)
                   (vec (for [[month records] (sort-by key (group-by #(subs (:createdAt %) 0 7) (filter #(in-range? range (:createdAt %)) leads)))]
                          {:id month :title month :month month :leads (count records) :converted (count (filter :convertedClientId records))})))
      "reports" (do (d/admin! u)
                    (vec (for [[id staff] (:users s)]
                           (let [mine (filter #(and (= id (:consultantId %)) (in-range? range (:createdAt %))) leads)
                                 tasks (filter #(and (= id (:assignedTo %)) (d/visible? s u :tasks %)) (d/rows s :tasks))
                                 open (remove #(contains? #{"Done" "Cancelled"} (:status %)) tasks)]
                             {:id id :title (:name staff) :leads (count mine) :converted (count (filter :convertedClientId mine))
                              :openTasks (count open) :overdueTasks (count (filter #(and (:dueDate %) (neg? (compare (:dueDate %) (d/today)))) open))
                              :from (first range) :to (second range)}))))
      "payments" (do (d/privilege! u "finance_view")
                     (vec (for [r (d/rows s :payments) :when (d/visible? s u :invoices (get-in s [:invoices (:invoiceId r)]))]
                            (assoc r :amount (f/money (:amountMinor r)) :title (str "Receipt #" (:id r))))))
      "balances" (do (d/privilege! u "finance_view") (mapv #(f/balance s %) (filter #(d/visible? s u :invoices %) (d/rows s :invoices))))
      "expenses" (do (d/privilege! u "finance_view") (mapv #(assoc % :amount (f/money (:amountMinor %))) (d/rows s :expenses)))
      "finance-audit" (do (d/privilege! u "finance_view") (vec (filter #(contains? #{"payments" "invoices" "expenses" "periods" "bankEntries"} (:entityType %)) (d/rows s :audit))))
      (d/fail 404 "Report not found"))))
(defn calendar [s u]
  (d/privilege! u "export")
  (let [escape #(-> (str %) (str/replace "\\" "\\\\") (str/replace "\r" "") (str/replace "\n" "\\n") (str/replace "," "\\,") (str/replace ";" "\\;"))
        stamp #(-> (str %) (str/replace #"[-:]" "") (str/replace #"\.\d+Z$" "Z"))]
    (str "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//ECC//Workspace//EN\r\n"
         (apply str (for [r (d/rows s :appointments) :when (d/visible? s u :appointments r)]
                      (str "BEGIN:VEVENT\r\nUID:ecc-appointment-" (:id r) "\r\nDTSTAMP:" (stamp (d/now))
                           "\r\nDTSTART:" (stamp (:startsAt r)) "\r\nDTEND:" (stamp (:endsAt r))
                           "\r\nSUMMARY:" (escape (:title r)) "\r\nLOCATION:" (escape (:location r))
                           "\r\nSTATUS:" (if (= "Cancelled" (:status r)) "CANCELLED" "CONFIRMED") "\r\nEND:VEVENT\r\n")))
         "END:VCALENDAR\r\n")))
