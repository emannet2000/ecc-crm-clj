(ns p2.core)
(defn go []
  (require '[xtdb.node :as xtn]) (require '[xtdb.api :as xt])
  (let [q    (ns-resolve 'xtdb.api 'q)
        et   (ns-resolve 'xtdb.api 'execute-tx)
        p    (ns-resolve 'clojure.pprint 'pprint)
        dir  "/tmp/xt-smoke4"
        l7   (keyword "lead" "7")]
    (with-open [node ((ns-resolve 'xtdb.node 'start-node)
                      {:log [:local {:path (str dir "/log")}], :storage [:local {:path (str dir "/storage")}]})]
      (et node [[:put-docs :leads {:xt/id l7 :lead/name "Bob" :revision 1 :lead/email "b@x.io"}]
                [:put-docs :audit {:xt/id (keyword "audit" "1") :audit/entity (keyword "lead" "7") :audit/action "test"}]])
      (et node [[:patch-docs :leads {:xt/id l7 :lead/name "Bob B" :revision 2}]])
      ;; history: 3 time cols + 2 attr cols
      (println "HIST1:") (p (q node '(from :leads [{:xt/id i, :lead/name n, :revision r, :xt/valid-from vf, :xt/tx-time tt}])))
      ;; order-by variants
      (println "ORD-A:") (p (q node '(-> (from :leads [{:xt/id i, :revision r}]) (order-by r) (limit 10))))
      (println "ORD-B:") (p (q node '(-> (from :leads [{:xt/id i, :revision r}]) (order-by {:val r :dir :desc}) (limit 10))))
      ;; plain assert
      (try (println "PLAIN-ASSERT:" (et node [[:sql "ASSERT EXISTS (SELECT 1 FROM leads WHERE _id = ? AND revision = ?)" [l7 2]]] :ok))
           (catch Throwable e (println "plain assert failed:" (type e) (.getMessage e) (ex-data e))))
      ;; assert message
      (try (et node [[:sql "ASSERT 1 = 2"]])
           (catch Throwable e (println "ASSERTERR:" (.getMessage e) "data:" (ex-data e))))
      ;; parametric xtql via fn
      (try (println "PARAM:") (p (q node ['#(from :leads [{:xt/id %1, :lead/name n}]) l7]))
           (catch Throwable e (println "param failed:" (.getMessage e))))
      ;; aggregate count
      (try (println "COUNT:") (p (q node '(-> (from :leads [{:xt/id i}]) (aggregate {:count (count i)}))))
      (catch Throwable e (println "count failed:" (.getMessage e))))
      (try (println "COUNTSQL:") (p (q node ["SELECT count(*) FROM leads"]))
           (catch Throwable e (println "countsql failed:" (.getMessage e))))
      (System/exit 0))))
(defn -main [& _] (go))
