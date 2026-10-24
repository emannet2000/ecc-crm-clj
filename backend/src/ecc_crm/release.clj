(ns ecc-crm.release
  (:require [cheshire.core :as json] [clojure.java.io :as io] [clojure.string :as str]
            [ecc-crm.domain :as d] [ecc-crm.backup :as backup]))
(defn assets [root]
  (let [root (.getCanonicalFile (io/file root))]
    (->> (concat [(io/file root "backend/deps.edn")]
                 (filter #(.isFile %) (file-seq (io/file root "backend/src")))
                 (filter #(.isFile %) (file-seq (io/file root "frontend/public"))))
         (map (fn [f] [(.toString (.relativize (.toPath root) (.toPath (.getCanonicalFile f)))) (backup/sha f)]))
         (into (sorted-map)))))
(defn generate! [root path]
  (let [files (assets root)]
    (when-not (and (get files "frontend/public/js/main.js") (get files "backend/src/ecc_crm/main.clj"))
      (d/fail 500 "Build the ClojureScript release before generating a manifest"))
    (spit path (json/generate-string {:format "ecc-clojure-release-v1" :createdAt (d/now) :files files} {:pretty true}))))
(defn verify! [root path]
  (let [manifest (try (json/parse-string (slurp path)) (catch Exception _ (d/fail 500 "Production release manifest is missing or invalid")))
        expected (get manifest "files") actual (assets root)]
    (when-not (and (= "ecc-clojure-release-v1" (get manifest "format")) (seq expected) (= expected actual))
      (d/fail 500 "Release files differ from the verified manifest"))
    {:verified true :files (count actual)}))
(defn -main [& [command root path]]
  (case command "generate" (generate! (or root "..") (or path "../release-clojure.json"))
        "verify" (println (pr-str (verify! (or root "..") (or path "../release-clojure.json"))))))
