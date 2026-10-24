;; Scratch harness — empirically confirms the XTDB 2.2 API shapes before the
;; real code is built on them. Run once: clojure -M -m scratch.xtdb
(ns scratch.xtdb
  (:require [xtdb.node :as xtn]
            [xtdb.api :as xt])
  (:import [java.time Instant]
           [java.nio.file Files]))

(defn demo []
  (let [dir (str (Files/createTempDirectory
                  "xtdb-smoke" (make-array java.nio.file.attribute.FileAttribute 0)))
        u1 (keyword "user" "1")
        l7 (keyword "lead" "7")
        l8 (keyword "lead" "8")]
    (with-open [node (xtn/start-node {:log     [:local {:path (str dir "/log")}]
                                      :storage [:local {:path (str dir "/storage")}]})]
      (println "status:" (keys (xt/status node)))

      (xt/execute-tx node [[:put-docs :users {:xt/id u1 :user/name "Ann" :user/role "admin" :revision 1}]
                           [:put-docs :leads {:xt/id l7 :lead/full-name "Bob" :lead/stage "New Lead"}]])
      (xt/execute-tx node [[:delete-docs :leads l8]])
      (xt/execute-tx node [[:patch-docs :leads {:xt/id l7 :lead/full-name "Bob B" :lead/stage "Contacted"
                                                :revision 2 :local-time nil}]])

      (try
        (xt/execute-tx node [[:sql "ASSERT EXISTS (SELECT 1 FROM users WHERE _id = ? AND user_name = ?)" [u1 "Ann"]]])
        (println "sql assert ok")
        (catch Exception e (println "sql assert failed:" (.getMessage e))))

      (println "users:" (xt/q node '(from :users [{:xt/id i} user-name])))
      (println "leads:" (xt/q node '(from :leads [{:xt/id i, :lead/full-name n, :lead/stage st, :lead/nothere nt}])))
      (println "limit:" (xt/q node '(-> (from :users [{:xt/id i} user-name])
                                        (order-by {:user-name :asc})
                                        (limit 10))))
      (println "by-id:" (xt/q node ["SELECT _id, * FROM leads WHERE _id = ?" l7]))

      (println "history:" (xt/q node (list '->
                                           (list 'from :leads '[{:xt/id i} lead-full-name {:xt/valid-from vf, :xt/valid-to vt, :xt/tx-time tt}])
                                           (list 'where (list '= 'i l7)))))

      (try
        (println "as-of:" (xt/q node '(->
                                       (from :leads [{:xt/id i} lead-full-name])
                                       (for-system-time :in (Instant/parse "2999-01-01T00:00:00Z")))))
        (catch Exception e (println "for-system-time failed:" (.getMessage e))))

      (try (println "failed assert errors like:" (xt/execute-tx node [[:sql "ASSERT 1 = 2"]]))
           (catch Exception e
             (println "assert failure class:" (type (.getCause e)))
             (println "msg:" (.getMessage (.getCause e)))))

      (println "SMOKE DONE"))))
