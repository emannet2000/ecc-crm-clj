(ns ecc-crm.workers
  (:require [clojure.java.io :as io]
            [clojure.string :as str]
            [ecc-crm.domain :as d]
            [ecc-crm.files :as files]
            [ecc-crm.store :as store]
            [postal.core :as postal]
            [ecc-crm.integrations :as integrations] [ecc-crm.monitor :as monitor])
  (:import [java.net Socket InetSocketAddress] [java.io DataOutputStream]
           [java.util.concurrent Executors TimeUnit ScheduledExecutorService]
           [java.time Instant LocalDate]))
(defn scan
  ([file] (scan file (or (System/getenv "CLAMD_HOST") "127.0.0.1") (int (or (d/integer (System/getenv "CLAMD_PORT")) 3310))))
  ([file host port]
  (with-open [socket (Socket.)]
    (.connect socket (InetSocketAddress. host (int port)) 5000)
    (.setSoTimeout socket 60000)
    (let [out (DataOutputStream. (.getOutputStream socket))]
      (.write out (.getBytes "zINSTREAM\u0000" "US-ASCII"))
      (with-open [in (io/input-stream file)]
        (let [buffer (byte-array 65536)]
          (loop [] (let [n (.read in buffer)] (when (pos? n) (.writeInt out n) (.write out buffer 0 n) (recur))))))
      (.writeInt out 0) (.flush out)
      (let [response (let [in (.getInputStream socket) buffer (java.io.ByteArrayOutputStream.)]
                       (loop [n 0]
                         (let [b (.read in)]
                           (when (and (pos? b) (< n 8192)) (.write buffer b) (recur (inc n)))))
                       (.toString buffer "UTF-8"))]
        (cond (str/includes? response " OK") "Clean" (str/includes? response " FOUND") "Infected"
              :else (throw (ex-info "Scanner could not complete" {}))))))))
(defn scan-pending! [db]
  (doseq [doc (take 10 (filter #(and (contains? #{"Quarantined" "Scan failed"} (:scanStatus %)) (< (:scanAttempts % 0) 5)) (d/rows (store/snapshot db) :documents)))]
    (let [status (try (scan (files/blob-path (:hash doc))) (catch Exception _ "Scan failed"))]
      (store/transact! db (fn [s] [(update-in s [:documents (:id doc)] #(assoc % :scanStatus status :scanAttempts (inc (:scanAttempts % 0)) :scannedAt (d/now))) nil])))))
(defn smtp-config []
  (let [host (System/getenv "SMTP_HOST") tls (or (System/getenv "SMTP_TLS") "starttls")]
    (when-not (str/blank? host)
      (when (and (not (contains? #{"localhost" "127.0.0.1"} host)) (not (contains? #{"starttls" "tls"} tls)))
        (d/fail 500 "Remote SMTP requires TLS"))
      (cond-> {:host host :port (int (or (d/integer (System/getenv "SMTP_PORT")) 587))
               :connectiontimeout 10000 :timeout 30000 :ssl.checkserveridentity true}
        (= tls "starttls") (assoc :tls true :starttls.enable true :starttls.required true)
        (= tls "tls") (assoc :ssl true)
        (not (str/blank? (System/getenv "SMTP_USER"))) (assoc :user (System/getenv "SMTP_USER") :pass (System/getenv "SMTP_PASSWORD"))))))
(defn sender [] (System/getenv "SMTP_FROM"))
(defn deliver-mail! [db]
  (when-let [smtp (smtp-config)]
    (doseq [message (take 10 (filter #(contains? #{"Queued" "Sending"} (:status %)) (d/rows (store/snapshot db) :mail)))]
      (let [leased (store/transact! db
                     (fn [s]
                       (let [r (get-in s [:mail (:id message)])
                             expired? (and (:leaseUntil r) (.isBefore (Instant/parse (:leaseUntil r)) (Instant/now)))]
                         (if (and (< (:attempts r 0) 5) (or (= "Queued" (:status r)) (and (= "Sending" (:status r)) expired?)))
                           (let [r (assoc r :status "Sending" :attempts (inc (:attempts r 0))
                                            :leaseUntil (str (.plusSeconds (Instant/now) 300)))]
                             [(assoc-in s [:mail (:id r)] r) r]) [s nil]))))]
        (when leased
          (let [sent? (try (= :SUCCESS (:error (postal/send-message smtp {:from (sender)
                                                                         :to (:to leased) :subject (:subject leased) :body (:body leased)})))
                           (catch Exception _ false))]
            (store/transact! db (fn [s]
                                  [(update-in s [:mail (:id leased)]
                                              #(cond-> (assoc % :status (if sent? "Sent" (if (>= (:attempts %) 5) "Failed" "Queued")))
                                                 sent? (dissoc :body))) nil]))))))))
(defn allowed? [preferences field] (not (contains? #{false 0 "false"} (get preferences field true))))
(defn notify [s task recipient kind key email?]
  (if (or (nil? recipient) (get-in s [:reminderReceipts key])) s
    (let [preferences (get-in s [:preferences recipient] {}) user (get-in s [:users recipient])
          enabled? (allowed? preferences (if (= kind "Escalation") :escalations (if (= kind "Assignment") :assignments :deadlines)))
          s (if enabled? (first (d/insert s :notifications {:userId recipient :taskId (:id task) :leadId (:leadId task) :clientId (:clientId task)
                                                           :title (:title task) :dueDate (:dueDate task) :kind kind :eventKey (pr-str key)})) s)
          s (if (and enabled? email? (allowed? preferences :emailEnabled) user (not (:suspended user)) (:email user))
              (first (d/insert s :mail {:to (:email user) :subject (str "ECC " kind ": " (:title task)) :status "Queued" :attempts 0
                                        :body (str (:title task) "\nDue: " (:dueDate task) "\nOpen the ECC workspace for details.")})) s)]
      (assoc-in s [:reminderReceipts key] true))))
(defn reminders! [db]
  (store/transact! db
    (fn [s]
      [(reduce
         (fn [s task]
           (let [due (try (LocalDate/parse (:dueDate task)) (catch Exception _ nil))
                 days (when due (.between java.time.temporal.ChronoUnit/DAYS (LocalDate/parse (d/today)) due))
                 assigned (:assignedTo task) previous (get-in s [:lastAssignments (:id task)])
                 s (if (and assigned (not= previous assigned))
                     (-> s (notify task assigned "Assignment" ["assignment" (:id task) assigned (:revision task)] false)
                         (assoc-in [:lastAssignments (:id task)] assigned)) s)
                 rules (filter #(= (:id task) (:taskId %)) (d/rows s :reminderRules))
                 rule (first rules) enabled? (and rule (allowed? rule :enabled))
                 open? (not (contains? #{"Done" "Cancelled"} (:status task)))
                 s (if (and due open? (<= days 7)) (notify s task assigned "Task reminder" ["in-app" (:id task) (:dueDate task)] false) s)
                 s (if (and due open? enabled? (<= 0 days (or (d/integer (:daysBefore rule)) 1)))
                     (notify s task assigned "Deadline" ["deadline" (:id task) (:dueDate task) assigned] true) s)]
             (if (and due open? enabled? (<= days (- (or (d/integer (:escalateAfter rule)) 2))))
               (reduce (fn [s user] (notify s task (:id user) "Escalation" ["escalation" (:id task) (:dueDate task) (:id user)] true))
                       s (filter #(and (= "admin" (:role %)) (not (:suspended %))) (d/rows s :users))) s)))
         s (d/rows s :tasks)) nil])))
(defn start! [db]
  (let [pool (Executors/newScheduledThreadPool 4)]
    (doseq [job [scan-pending! deliver-mail! reminders! integrations/run-jobs! integrations/reconcile! monitor/run!]]
      (.scheduleWithFixedDelay pool ^Runnable
                               (fn [] (try (job db) (catch Throwable e (binding [*out* *err*] (println "worker_failed" (.getName (class e)))))))
                               5 60 TimeUnit/SECONDS)) pool))
