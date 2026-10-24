(ns ecc-crm.test-runner
  (:require [clojure.test :as test] [ecc-crm.domain-test] [ecc-crm.security-test] [ecc-crm.main] [ecc-crm.completion-test]))
(defn -main [& _]
  (let [result (test/run-tests 'ecc-crm.domain-test 'ecc-crm.security-test 'ecc-crm.completion-test)]
    (shutdown-agents)
    (System/exit (if (zero? (+ (:fail result) (:error result))) 0 1))))
