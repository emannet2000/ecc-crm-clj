(ns ecc-crm.domain-test
  (:require [clojure.test :refer :all]
            [ecc-crm.domain :as d]
            [ecc-crm.auth :as auth]
            [ecc-crm.finance :as f]
            [ecc-crm.http :as http]
            [ecc-crm.store :as store]
            [cheshire.core :as json])
  (:import [java.io ByteArrayInputStream]))
(def admin {:id 1 :role "admin" :name "Admin"})
(def viewer {:id 2 :role "viewer"})
(defn status [f] (try (f) 200 (catch clojure.lang.ExceptionInfo e (:status (ex-data e)))))
(deftest conversion-is-atomic-and-idempotent
  (let [[s lead] (d/save-person {} admin :leads {:fullName "A Student" :email "a@example.com"})
        [s task] (d/save-task s admin {:leadId (:id lead) :title "Follow up"})
        [s client] (d/convert s admin (:id lead))
        [s second] (d/convert s admin (:id lead))]
    (is (= (:id client) (:id second))) (is (= "New Client" (:stage client))) (is (= 1 (count (:clients s))))
    (is (= 1 (count (:cases s)))) (is (= (:id client) (get-in s [:tasks (:id task) :clientId])))))
(deftest roles-scope-and-stale-updates
  (let [[s lead] (d/save-person {} admin :leads {:fullName "Private student" :consultantId 4})]
    (is (= 403 (status #(d/save-person s viewer :leads {:fullName "Denied"}))))
    (is (= 404 (status #(d/accessible! (assoc s :assignedOnly true) {:id 3 :role "consultant"} :leads (:id lead)))))
    (is (= 409 (status #(d/save-person s admin :leads {:id (:id lead) :fullName "Stale" :revision 0}))))
    (let [[s _] (d/archive s admin :leads (:id lead))]
      (is (empty? (:rows (d/list-records s admin :leads {}))))
      (is (= "Private student" (:fullName (second (d/restore-record s admin :leads (:id lead)))))))))
(deftest money-and-posting
  (is (= 400 (status #(f/minor "1.001"))))
  (is (= 400 (status #(f/minor "-1"))))
  (let [[s client] (d/save-person {} admin :clients {:fullName "Student"})
        [s invoice] (f/invoice-save s admin {:clientId (:id client) :subtotal "100" :tax "10" :discount "5" :currency "PHP" :dueDate "2027-01-01"})
        [s invoice] (f/issue-invoice s admin {:id (:id invoice)})
        input {:invoiceId (:id invoice) :amount "50" :paidOn "2026-10-24" :submissionKey "one"}
        [s payment] (f/payment s admin "record" input)
        [s duplicate] (f/payment s admin "record" input)]
    (is (= (:id payment) (:id duplicate)))
    (is (= 5500 (:balanceMinor (f/balance s invoice))))
    (is (= 400 (status #(f/payment s admin "record" (assoc input :amount "56" :submissionKey "two")))))
    (let [[s _] (f/payment s admin "reverse" {:id (:id payment) :submissionKey "reverse"})]
      (is (= 10500 (:balanceMinor (f/balance s invoice))))
      (is (= 409 (status #(f/payment s admin "reverse" {:id (:id payment) :submissionKey "another"})))))))
(deftest recurrence-does-not-duplicate
  (let [[s lead] (d/save-person {} admin :leads {:fullName "Student"})
        [s t] (d/save-task s admin {:leadId (:id lead) :title "Repeat" :dueDate "2026-10-24" :recurrenceDays 7})
        [s t] (d/save-task s admin {:id (:id t) :status "Done"})
        [s _] (d/save-task s admin {:id (:id t) :status "Done"})]
    (is (= 2 (count (:tasks s))))
    (is (= "2026-10-31" (:dueDate (last (sort-by :id (d/rows s :tasks))))))))
(defn request [app method path body token]
  (app {:request-method method :uri path :remote-addr "127.0.0.1"
        :headers (cond-> {"content-type" "application/json"} token (assoc "authorization" (str "Bearer " token)))
        :body (when body (ByteArrayInputStream. (.getBytes (json/generate-string body) "UTF-8")))}))
(deftest real-router-session-and-csrf
  (let [db (store/memory-store)
        _ (store/transact! db #(auth/create-user % nil {:name "Admin" :email "admin@example.com" :role "admin" :password "a-long-enough-password"}))
        app (http/app db {:public-url "http://localhost:4000"})
        login (request app :post "/api/auth/login" {:email "admin@example.com" :password "a-long-enough-password"} nil)
        result (json/parse-string (:body login) true) token (:token result)]
    (is (= 200 (:status login)))
    (is (get-in login [:headers "Set-Cookie"]))
    (is (= 401 (:status (request app :get "/api/leads" nil nil))))
    (is (= 200 (:status (request app :post "/api/leads" {:fullName "HTTP Student"} token))))
    (is (= 1 (:total (json/parse-string (:body (request app :get "/api/leads" nil token)) true))))
    (is (= 403 (:status (app {:request-method :post :uri "/api/leads" :headers {"origin" "https://attacker.invalid"}}))))
    (request app :post "/api/auth/logout" {} token)
    (is (= 401 (:status (request app :get "/api/auth/me" nil token))))))

(deftest account-revocation-and-role-protection
  (let [[s user] (auth/create-user {} nil {:name "Admin" :email "admin@example.com" :role "admin" :password "a-long-enough-password"})
        s (assoc-in s [:sessions "hash"] {:userId (:id user) :expiresAt "2099-01-01T00:00:00Z"})]
    (is (= 409 (status #(http/users-save s user {:id (:id user) :role "viewer"}))))
    (is (= 400 (status #(http/users-save s user {:id (:id user) :suspended true}))))
    (is (empty? (:sessions (auth/revoke-user s (:id user)))))))

(deftest approval-and-closed-periods
  (let [[s expense] (f/expense {} admin "submit" {:supplier "Vendor" :currency "PHP" :amount "10" :expenseOn "2026-10-24"})]
    (is (= 403 (status #(f/expense s admin "approve" {:id (:id expense)}))))
    (let [approver (assoc admin :id 3) [s _] (f/expense s approver "approve" {:id (:id expense)})
          [s _] (f/period s approver "close" {:from "2026-10-01" :to "2026-10-31" :reason "Monthly close"})]
      (is (= 409 (status #(f/expense s admin "pay" {:id (:id expense)})))))))
