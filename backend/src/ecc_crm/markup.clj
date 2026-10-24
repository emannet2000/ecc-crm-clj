(ns ecc-crm.markup
  "Escape document text explicitly: Hiccup 1.x treats string nodes as raw HTML."
  (:require [clojure.walk :as walk] [hiccup.core :as hiccup] [hiccup.util :as util]))
(defn html [tree]
  (hiccup/html (walk/postwalk #(if (string? %) (util/escape-html %) %) tree)))
