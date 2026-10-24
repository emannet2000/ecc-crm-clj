(ns ecc-crm.files
  (:require [clojure.java.io :as io]
            [clojure.string :as str]
            [ecc-crm.domain :as d]
            [ecc-crm.auth :as auth])
  (:import [java.util Base64]
           [java.security MessageDigest]
           [java.nio.file Files StandardCopyOption CopyOption]))
(defn directory [] (or (System/getenv "BLOB_DIR") "data/blobs"))
(defn blob-path [hash]
  (when-not (re-matches #"[a-f0-9]{64}" (str hash)) (d/fail 500 "Invalid stored file reference"))
  (io/file (directory) hash))
(defn upload [s u table id input]
  (d/writer! u) (d/privilege! u "edit")
  (let [owner (d/accessible! s u table id)
        name (d/required input :filename 255)
        _ (when (re-find #"[\r\n/\\\x00]" name) (d/fail 400 "Invalid filename"))
        content (try (.decode (Base64/getDecoder) (str (:content input)))
                     (catch Exception _ (d/fail 400 "Invalid base64 file content")))
        _ (when (or (zero? (alength content)) (> (alength content) (* 25 1024 1024)))
            (d/fail 413 "Files must be between 1 byte and 25 MB"))
        hash (.formatHex (java.util.HexFormat/of) (.digest (MessageDigest/getInstance "SHA-256") content))
        file (blob-path hash)
        _ (.mkdirs (io/file (directory)))
        _ (when-not (.exists file)
            (let [tmp (Files/createTempFile (.toPath (io/file (directory))) ".upload-" ".tmp"
                                            (make-array java.nio.file.attribute.FileAttribute 0))]
              (try
                (Files/write tmp content (make-array java.nio.file.OpenOption 0))
                (Files/move tmp (.toPath file) (into-array CopyOption [StandardCopyOption/ATOMIC_MOVE StandardCopyOption/REPLACE_EXISTING]))
                (finally (Files/deleteIfExists tmp)))))
        [s r] (d/insert s :documents {(if (= table :leads) :leadId :clientId) (:id owner)
                                      :filename name :size (alength content) :contentType "application/octet-stream"
                                      :hash hash :scanStatus "Quarantined" :uploadedBy (:id u)})
        request-id (d/integer (:requestId input))
        s (if request-id
            (let [request (d/accessible! s u :checklists request-id)
                  fk (if (= table :leads) :leadId :clientId)]
              (when-not (= (fk request) (:id owner)) (d/fail 400 "Checklist belongs to a different record"))
              (-> s (assoc-in [:checklists request-id :documentId] (:id r))
                  (update-in [:checklists request-id :versions] (fnil conj []) (:id r)))) s)]
    [(d/audit s u :documents r "uploaded") r]))
(defn download [s u id]
  (d/privilege! u "download")
  (let [r (d/accessible! s u :documents id)]
    (when (:expenseId r) (d/privilege! u "finance_view"))
    (when-not (= "Clean" (:scanStatus r)) (d/fail 409 "This file has not passed malware scanning"))
    (let [f (blob-path (:hash r))]
      (when-not (.isFile f) (d/fail 404 "Stored file is missing"))
      {:status 200 :headers {"content-type" "application/octet-stream"
                            "content-disposition" (str "attachment; filename*=UTF-8''" (java.net.URLEncoder/encode (:filename r) "UTF-8"))}
       :body f})))
