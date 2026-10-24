(ns ecc-crm.diagnostics
  (:require [cheshire.core :as json]))
(defn request! [request status milliseconds]
  (when-not (= "false" (System/getenv "REQUEST_LOGS"))
    (println (json/generate-string {:event "request" :method (name (:request-method request)) :path (:uri request)
                                   :status status :latencyMs milliseconds}))))
