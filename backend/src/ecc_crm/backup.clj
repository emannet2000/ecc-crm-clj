(ns ecc-crm.backup
  "Streaming ZIP snapshots. Each record and immutable file has its own entry.
  Restore commits bounded batches and marks incomplete restores so startup refuses them."
  (:require [clojure.edn :as edn] [clojure.java.io :as io] [ecc-crm.store :as store]
            [ecc-crm.files :as files] [ecc-crm.domain :as d] [xtdb.api :as xt])
  (:import [java.util.zip ZipOutputStream ZipEntry ZipFile] [java.util Base64]
           [java.nio.file Files CopyOption StandardCopyOption] [java.security MessageDigest]))
(defn sha [file]
  (let [digest (MessageDigest/getInstance "SHA-256") buffer (byte-array 65536)]
    (with-open [in (io/input-stream file)] (loop [] (let [n (.read in buffer)] (when (pos? n) (.update digest buffer 0 n) (recur)))))
    (.formatHex (java.util.HexFormat/of) (.digest digest))))
(defn walk [table f]
  (if (instance? ecc_crm.store.EntityTable table)
    (let [^ecc_crm.store.EntityTable table table]
      (reduce (fn [_ row] (f (edn/read-string (:entity-key row)) (edn/read-string (:payload row))) nil) nil
              (xt/plan-q (.-node table) ["SELECT entity_key, payload FROM crm_entities WHERE bucket = ?" (name (.-bucket table))] {:snapshot-time (.-basis table)})))
    (doseq [[k v] table] (f k v))))
(defn write! [db destination]
  (let [target (.toPath (io/file destination)) parent (.getParent (.toAbsolutePath target))
        _ (when (Files/exists target (make-array java.nio.file.LinkOption 0)) (d/fail 409 "Backup destination already exists"))
        tmp (Files/createTempFile parent ".ecc-backup-" ".zip" (make-array java.nio.file.attribute.FileAttribute 0))
        s (store/snapshot db) tables (set (keep #(when (map? (val %)) (key %)) s)) blobs (atom #{}) count-records (atom 0)]
    (try
      (Files/setPosixFilePermissions tmp (java.nio.file.attribute.PosixFilePermissions/fromString "rw-------"))
      (with-open [out (ZipOutputStream. (io/output-stream (.toFile tmp)))]
        (let [entry (fn [name value] (.putNextEntry out (ZipEntry. name)) (.write out (.getBytes (pr-str value) "UTF-8")) (.closeEntry out))]
          (entry "manifest.edn" {:format "ecc-clojure-v2" :createdAt (d/now) :tables tables :scalars (apply dissoc s tables)})
          (doseq [table tables]
            (walk (get s table) (fn [k v]
                                 (entry (str "records/" (swap! count-records inc) ".edn") {:table table :key k :value v})
                                 (when (and (= table :documents) (:hash v)) (swap! blobs conj (:hash v))))))
          (doseq [hash @blobs]
            (let [file (files/blob-path hash)]
              (when-not (= hash (sha file)) (d/fail 500 "Stored document checksum mismatch"))
              (.putNextEntry out (ZipEntry. (str "blobs/" hash)))
              (with-open [in (io/input-stream file)] (io/copy in out)) (.closeEntry out)))
          (entry "counts.edn" {:records @count-records :blobs (count @blobs)})))
      (Files/move tmp target (make-array CopyOption 0))
      {:path (str destination) :sha256 (sha destination) :records @count-records :blobs (count @blobs)}
      (finally (Files/deleteIfExists tmp)))))
(defn read-entry [zip entry maximum]
  (with-open [in (.getInputStream ^ZipFile zip ^ZipEntry entry)]
    (let [bytes (.readNBytes in (inc maximum))]
      (when (> (alength bytes) maximum) (d/fail 400 "Backup entry exceeds the size limit")) bytes)))
(defn restore! [db source]
  (let [fingerprint (sha source) state (store/snapshot db) progress (:restoreProgress state)]
    (when (and (seq state) (not= fingerprint (:source progress))) (d/fail 409 "Restore requires an empty target or the same interrupted restore"))
    (with-open [zip (ZipFile. (io/file source))]
      (let [entry (.getEntry zip "manifest.edn") _ (when-not entry (d/fail 400 "Backup manifest is missing"))
            manifest (edn/read-string (String. (read-entry zip entry (* 1024 1024)) "UTF-8"))
            _ (when-not (= "ecc-clojure-v2" (:format manifest)) (d/fail 400 "Unsupported backup format"))
            counts-entry (.getEntry zip "counts.edn")
            expected (when counts-entry (edn/read-string (String. (read-entry zip counts-entry 4096) "UTF-8")))
            entries (vec (enumeration-seq (.entries zip))) record-entries (filter #(.startsWith (.getName ^ZipEntry %) "records/") entries)
            _ (when-not (and expected (= (:records expected) (count record-entries))
                              (= (:blobs expected) (count (filter #(.startsWith (.getName ^ZipEntry %) "blobs/") entries))))
                (d/fail 400 "Backup entry counts do not match the manifest"))
            _ (store/transact! db #(vector (assoc (merge % (:scalars manifest)) :restoreProgress {:source fingerprint :status "In progress"}) nil))]
        (doseq [batch (partition-all 500 record-entries)]
          (let [records (mapv #(edn/read-string (String. (read-entry zip % (* 64 1024 1024)) "UTF-8")) batch)]
            (doseq [{:keys [table key]} records]
              (when-not (and (keyword? table) (contains? (:tables manifest) table) (some? key)) (d/fail 400 "Invalid backup record")))
            (store/transact! db #(vector (reduce (fn [s {:keys [table key value]}] (assoc-in s [table key] value)) % records) nil))))
        (doseq [entry entries :let [name (.getName ^ZipEntry entry)] :when (.startsWith name "blobs/")]
          (let [hash (subs name 6) target (files/blob-path hash) bytes (read-entry zip entry (* 25 1024 1024))
                actual (.formatHex (java.util.HexFormat/of) (.digest (MessageDigest/getInstance "SHA-256") bytes))]
            (when-not (= hash actual) (d/fail 400 "Document checksum verification failed"))
            (.mkdirs (.getParentFile target))
            (when-not (.exists target) (Files/write (.toPath target) bytes (make-array java.nio.file.OpenOption 0)))))
        (let [s (store/snapshot db)]
          (walk (:documents s {}) (fn [_ doc] (when (:hash doc)
                                                 (let [file (files/blob-path (:hash doc))]
                                                   (when-not (and (.isFile file) (= (:hash doc) (sha file))) (d/fail 400 "Backup is missing a valid document")))))))
        (store/transact! db #(vector (-> (reduce (fn [s table] (if (contains? s table) s (assoc s table {}))) % (:tables manifest))
                                        (dissoc :restoreProgress)) nil))
        {:restored true :sha256 fingerprint :records (count record-entries)}))))
