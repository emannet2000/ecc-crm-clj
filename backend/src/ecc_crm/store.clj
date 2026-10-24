(ns ecc-crm.store
  "One XTDB document per entity. Snapshots resolve records lazily at one system-time;
  mutations persist only changed records under an atomic revision assertion."
  (:require [clojure.edn :as edn] [clojure.set :as set] [clojure.string :as str]
            [xtdb.api :as xt] [xtdb.node :as node])
  (:import [java.time Instant] [clojure.lang MapEntry]))

(defprotocol Store (snapshot [store]) (transact! [store f]))
(defrecord MemoryStore [state]
  Store (snapshot [_] @state)
  (transact! [_ f] (locking state (let [[next result] (f @state)] (reset! state next) result))))
(defn memory-store [] (->MemoryStore (atom {})))
(def deleted ::deleted)
(defn entity-id [bucket key] (pr-str [bucket key]))
(defn query [node basis sql & args] (xt/q node (into [sql] args) {:snapshot-time basis}))
(defn load-one [node bucket basis key not-found]
  (if-let [row (first (query node basis "SELECT payload FROM crm_entities WHERE _id = ?" (entity-id bucket key)))]
    (edn/read-string (:payload row)) not-found))
(defn load-table [node bucket basis]
  (into {} (for [row (query node basis "SELECT entity_key, payload FROM crm_entities WHERE bucket = ?" (name bucket))]
             [(edn/read-string (:entity-key row)) (edn/read-string (:payload row))])))
(declare table-map)
(deftype EntityTable [node bucket basis changes cache metadata]
  clojure.lang.ILookup
  (valAt [this k] (.valAt this k nil))
  (valAt [_ k not-found]
    (if (contains? changes k) (let [v (get changes k)] (if (= deleted v) not-found v))
      (let [cached (find @cache k)]
        (if cached (if (= deleted (val cached)) not-found (val cached))
          (let [v (load-one node bucket basis k deleted)] (swap! cache assoc k v) (if (= deleted v) not-found v))))))
  clojure.lang.Associative
  (containsKey [this k] (not= deleted (.valAt this k deleted)))
  (entryAt [this k] (when (.containsKey this k) (MapEntry/create k (.valAt this k))))
  (assoc [_ k v] (EntityTable. node bucket basis (assoc changes k v) cache metadata))
  clojure.lang.IPersistentMap
  (assocEx [this k v] (if (.containsKey this k) (throw (RuntimeException. "Key already present")) (.assoc this k v)))
  (without [_ k] (EntityTable. node bucket basis (assoc changes k deleted) cache metadata))
  clojure.lang.IPersistentCollection
  (count [this] (count (table-map this)))
  (empty [_] {})
  (cons [this value] (if (map-entry? value) (.assoc this (key value) (val value))
                       (if (vector? value) (.assoc this (nth value 0) (nth value 1)) (reduce conj this value))))
  (equiv [this other] (= (table-map this) other))
  clojure.lang.Seqable (seq [this] (seq (table-map this)))
  clojure.lang.IKVReduce (kvreduce [this f init] (reduce-kv f init (table-map this)))
  clojure.lang.IObj (meta [_] metadata) (withMeta [_ m] (EntityTable. node bucket basis changes cache m))
  java.lang.Iterable (iterator [this] (.iterator ^Iterable (table-map this)))
  Object (toString [this] (pr-str (table-map this)))
  (equals [this other] (= (table-map this) other)) (hashCode [this] (hash (table-map this))))
(defn table-map [^EntityTable table]
  (let [base (or (::all @(.-cache table))
                 (let [all (load-table (.-node table) (.-bucket table) (.-basis table))]
                   (swap! (.-cache table) assoc ::all all) all))]
    (reduce-kv #(if (= deleted %3) (dissoc %1 %2) (assoc %1 %2 %3)) base (.-changes table))))
(defmethod print-method EntityTable [table writer] (print-method (table-map table) writer))
(defmethod print-dup EntityTable [table writer] (print-method (table-map table) writer))
(defn materialize [s] (into {} (map (fn [[k v]] [k (if (instance? EntityTable v) (table-map v) v)]) s)))
(def indexed-fields {:leadId "lead_id" :clientId "client_id" :invoiceId "invoice_id" :userId "user_id"
                     :taskId "task_id" :status "status" :consultantId "consultant_id" :assignedTo "assigned_to"
                     :email "email" :expenseId "expense_id" :recordId "record_id" :jobId "job_id" :stage "stage" :quality "quality" :source "source" :templateId "template_id"})
(defn matching [table field value]
  (if (and (instance? EntityTable table) (empty? (.-changes ^EntityTable table)) (indexed-fields field))
    (mapv #(edn/read-string (:payload %))
          (query (.-node ^EntityTable table) (.-basis ^EntityTable table)
                 (str "SELECT payload FROM crm_entities WHERE bucket = ? AND " (indexed-fields field) " = ?")
                 (name (.-bucket ^EntityTable table)) value))
    (filter #(= value (get % field)) (vals table))))
(defn- doc [bucket k v]
  (merge {:xt/id (entity-id bucket k) :bucket (name bucket) :entity-key (pr-str k) :payload (pr-str v)
          :entity-id (when (integer? k) k) :search-text (str/lower-case (str (:fullName v) " " (:title v) " " (:email v) " " (:phone v)))
          :deleted-at (:deletedAt v)}
         (into {} (for [[field column] indexed-fields] [(keyword (str/replace column "_" "-")) (when (map? v) (get v field))]))))
(defn- meta-row [node basis]
  (first (query node basis "SELECT revision, payload FROM crm_entities WHERE _id = ?" "workspace-meta")))
(defn- view [node basis]
  (let [{:keys [revision payload]} (meta-row node basis) {:keys [buckets scalars]} (edn/read-string payload)]
    (with-meta (reduce #(assoc %1 %2 (EntityTable. node %2 basis {} (atom {}) nil)) scalars buckets)
      {::revision revision ::buckets buckets})))
(defn- changes-for [bucket old new]
  (cond (identical? old new) []
        (instance? EntityTable new)
        (for [[k v] (.-changes ^EntityTable new)]
          (if (= deleted v) [:delete-docs :crm_entities (entity-id bucket k)] [:put-docs :crm_entities (doc bucket k v)]))
        :else (for [k (set/union (set (keys old)) (set (keys new))) :when (not= (get old k deleted) (get new k deleted))]
                (if (contains? new k) [:put-docs :crm_entities (doc bucket k (get new k))]
                    [:delete-docs :crm_entities (entity-id bucket k)]))))
(defrecord XtdbStore [node]
  Store
  (snapshot [_] (view node (Instant/now)))
  (transact! [_ f]
    (locking node
      (let [s (view node (Instant/now)) [next result] (f s)
            buckets (set (keep (fn [[k v]] (when (map? v) k)) next))
            ;; EntityTable implements IPersistentMap, so map? recognizes it.
            scalars (into {} (remove #(contains? buckets (key %))) next)
            ops (mapcat (fn [bucket] (changes-for bucket (get s bucket {}) (get next bucket {})))
                        (set/union (::buckets (meta s)) buckets))
            revision (::revision (meta s))]
        (when (or (seq ops) (not= (set (::buckets (meta s))) buckets)
                  (not= scalars (into {} (remove #(contains? (::buckets (meta s)) (key %))) s)))
          (xt/execute-tx node (into [[:sql "ASSERT EXISTS (SELECT 1 FROM crm_entities WHERE _id = ? AND revision = ?)" ["workspace-meta" revision]]
                                    [:put-docs :crm_entities {:xt/id "workspace-meta" :revision (inc revision)
                                                              :payload (pr-str {:buckets buckets :scalars scalars})}]] ops)))
        result)))
  java.io.Closeable (close [_] (.close ^java.io.Closeable node)))
(defn open-store [directory]
  (let [n (node/start-node {:log [:local {:path (str directory "/log")}]
                            :storage [:local {:path (str directory "/storage")}]})]
    (try
      (xt/execute-tx n [[:put-docs :crm_entities (merge (doc :schema :schema {})
                      (into {} (for [[field column] indexed-fields] [(keyword (str/replace column "_" "-"))
                                      (if (contains? #{:status :email :stage :quality :source} field) "" -1)]))
                      {:xt/id "schema" :revision -1 :entity-id -1 :deleted-at ""})]])
      (when-not (meta-row n (Instant/now))
        ;; Import the first port's aggregate once, within the same atomic transaction.
        (let [old (try (first (xt/q n ["SELECT payload FROM crm_state WHERE _id = ?" "workspace"]))
                       (catch Exception e (if (str/includes? (.getMessage e) "Table not found") nil (throw e))))
              s (if old (edn/read-string (:payload old)) {}) buckets (set (keep #(when (map? (val %)) (key %)) s))
              ops (for [b buckets [k v] (get s b)] [:put-docs :crm_entities (doc b k v)])]
          (xt/execute-tx n (into [[:sql "ASSERT NOT EXISTS (SELECT 1 FROM crm_entities WHERE _id = ?)" ["workspace-meta"]]
                                 [:put-docs :crm_entities {:xt/id "workspace-meta" :revision 0
                                  :payload (pr-str {:buckets buckets :scalars (apply dissoc s buckets)})}]] ops))))
      (->XtdbStore n)
      (catch Throwable e (.close n) (throw e)))))

(defn paged [^EntityTable table {:keys [query offset limit assigned? user-id filters]}]
  (let [bucket (.-bucket table)
        scope (when assigned?
                (if (contains? #{:leads :clients} bucket) " AND e.consultant_id = ?"
                  " AND (e.assigned_to = ? OR EXISTS (SELECT 1 FROM crm_entities p WHERE p.bucket = 'clients' AND p.entity_id = e.client_id AND p.consultant_id = ? AND p.deleted_at IS NULL) OR EXISTS (SELECT 1 FROM crm_entities p WHERE p.bucket = 'leads' AND p.entity_id = e.lead_id AND p.consultant_id = ? AND p.deleted_at IS NULL))"))
        args (into [(name bucket)] (when assigned? (repeat (if (contains? #{:leads :clients} bucket) 1 3) user-id)))
        nonempty (filter #(and (indexed-fields (key %)) (not (str/blank? (val %)))) filters)
        where (str " FROM crm_entities e WHERE e.bucket = ? AND e.deleted_at IS NULL" scope
                   (when (seq query) " AND e.search_text LIKE ?")
                   (apply str (map #(str " AND e." (indexed-fields (key %)) " = ?") nonempty)))
        args (into (cond-> args (seq query) (conj (str "%" (str/lower-case query) "%"))) (map val nonempty))
        fetch (fn [sql arguments] (apply ecc-crm.store/query (.-node table) (.-basis table) sql arguments))
        total (:total (first (fetch (str "SELECT COUNT(*) AS total" where) args)))
        rows (fetch (str "SELECT e.payload" where " ORDER BY e.entity_id DESC LIMIT ? OFFSET ?") (conj args limit offset))]
    {:rows (mapv #(edn/read-string (:payload %)) rows) :total total :offset offset :limit limit}))
