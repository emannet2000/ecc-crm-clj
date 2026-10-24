(ns ecc-crm.security-test
  (:require [clojure.test :refer :all]
            [clojure.string :as str]
            [ecc-crm.domain :as d]
            [ecc-crm.auth :as auth]
            [ecc-crm.mfa :as mfa]
            [ecc-crm.portal :as portal]
            [ecc-crm.migration :as migration]
            [ecc-crm.files :as files])
  (:import [java.time Instant] [java.nio.file Files] [java.nio.file.attribute FileAttribute]))
(def admin {:id 1 :role "admin"})
(defn status [f] (try (f) 200 (catch clojure.lang.ExceptionInfo e (:status (ex-data e)))))
(deftest totp-and-legacy-bcrypt
  (let [secret (mfa/secret) counter (quot (.getEpochSecond (Instant/now)) 30) code (mfa/code secret counter)]
    (is (= counter (mfa/verify-counter secret code nil)))
    (is (nil? (mfa/verify-counter secret code counter)))
    (is (nil? (mfa/verify-counter secret "invalid" nil))))
  (let [encoded (buddy.impl.bcrypt.BCrypt/hashpw "legacy-password" (buddy.impl.bcrypt.BCrypt/gensalt 4))]
    (is (auth/password? "legacy-password" encoded))
    (is (not (auth/password? "wrong" encoded)))
    (is (not (auth/password? (str "legacy-password" "\u0000suffix") encoded)))
    (is (not (auth/password? (apply str (repeat 73 "a")) encoded)))))
(deftest portal-is-restricted-to-one-client-and-public-fields
  (let [[s a] (d/save-person {} admin :clients {:fullName "A" :notes "Private staff notes"})
        [s b] (d/save-person s admin :clients {:fullName "B"})
        [s result] (portal/manage s admin "create" {:clientId (:id a)})
        [s exchanged] (portal/exchange s {:token (:token result)})
        link (portal/session s (:token exchanged))
        [s _] (d/insert s :messages {:clientId (:id a) :body "Private message" :clientVisible false})
        [s other] (d/insert s :proposals {:clientId (:id b) :status "Issued" :title "Other client"})
        data (portal/view s link)]
    (is (= "A" (get-in data [:client :fullName])))
    (is (not (str/includes? (pr-str data) "Private")))
    (is (= 404 (status #(portal/commercial-action s link :proposals (:id other) "accept" {:name "A"}))))
    (let [[s _] (portal/manage s admin "revoke" {:id (:id result)})]
      (is (= 401 (status #(portal/session s (:token exchanged))))))))
(deftest quarantined-files-and-scope
  (let [directory (str (Files/createTempDirectory "ecc-blob-test-" (make-array FileAttribute 0)))]
    (with-redefs [files/directory (constantly directory)]
      (let [[s client] (d/save-person {} admin :clients {:fullName "A" :consultantId 1})
            [s doc] (files/upload s admin :clients (:id client) {:filename "test.txt" :content "aGVsbG8="})]
        (is (= "Quarantined" (:scanStatus doc)))
        (is (= 409 (status #(files/download s admin (:id doc)))))
        (let [s (assoc-in s [:documents (:id doc) :scanStatus] "Clean")]
          (is (= "hello" (slurp (:body (files/download s admin (:id doc))))))
          (is (= 404 (status #(files/download (assoc s :assignedOnly true) {:id 2 :role "consultant"} (:id doc))))))))))
(deftest migration-preserves-identities-access-and-unmapped-tables
  (let [s (migration/import-state {:format "ecc-sqlite-v1"
                                   :tables {:users [{:id 7 :name "Staff" :email "staff@example.com" :role "consultant" :password_hash "hash" :suspended 0}]
                                            :clients [{:id 9 :full_name "Client" :case_officer_id 7}]
                                            :user_access [{:user_id 7 :access_level "assigned" :privileges "[\"edit\"]"}]
                                            :custom_table [{:key "retained"}]}})]
    (is (= 7 (get-in s [:users 7 :id])))
    (is (= "hash" (get-in s [:users 7 :passwordHash])))
    (is (= "assigned" (get-in s [:users 7 :accessLevel])))
    (is (= 7 (get-in s [:clients 9 :consultantId])))
    (is (= 9 (get-in s [:counters :clients])))
    (is (= {:key "retained"} (get-in s [:legacy [:custom_table 0]])))))

(deftest portal-files-need-explicit-current-approved-grants
  (let [[s client] (d/save-person {} admin :clients {:fullName "Portal student"})
        [s doc] (d/insert s :documents {:clientId (:id client) :filename "Private file" :scanStatus "Clean"})
        [s request] (d/insert s :checklists {:clientId (:id client) :documentId (:id doc) :status "Approved"})
        [s result] (portal/manage s admin "create" {:clientId (:id client)})
        [s exchange] (portal/exchange s {:token (:token result)}) link (portal/session s (:token exchange))]
    (is (empty? (:documents (portal/view s link))))
    (is (not (portal/shared? s link doc)))
    (is (= 401 (status #(portal/exchange s {:token (:token result)}))))
    (let [[s _] (portal/manage s admin "grant" {:id (:id link) :documentId (:id doc)})]
      (is (portal/shared? s link doc))
      (is (= 1 (count (:documents (portal/view s link)))))
      (is (not (portal/shared? (assoc-in s [:checklists (:id request) :documentId] 99) link doc)))
      (is (not (portal/shared? (assoc-in s [:checklists (:id request) :expiresOn] "2000-01-01") link doc)))
      (let [[s _] (portal/manage s admin "ungrant" {:id (:id link) :documentId (:id doc)})]
        (is (not (portal/shared? s link doc)))))))
