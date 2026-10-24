(ns ecc-crm.postgres-export
  "Repeatable-read, read-only JDBC export using server catalog names, not browser input."
  (:require [clojure.string :as str] [ecc-crm.domain :as d])
  (:import [java.sql DriverManager Connection ResultSet] [java.util Base64]))
(defn sql-name [s] (str "\"" (str/replace s "\"" "\"\"") "\""))
(defn rows [connection sql]
  (with-open [statement (.createStatement ^Connection connection) result (.executeQuery statement sql)]
    (let [metadata (.getMetaData result) n (.getColumnCount metadata)]
      (loop [records []]
        (if (.next result)
          (recur (conj records (into {} (for [i (range 1 (inc n))]
                                         [(keyword (.getColumnLabel metadata i))
                                          (let [v (.getObject result i)]
                                            (cond (bytes? v) {:$binary (.encodeToString (Base64/getEncoder) v)}
                                                  (instance? java.sql.Timestamp v) (if (= "timestamp" (.getColumnTypeName metadata i)) (str (.toInstant (.atOffset (.toLocalDateTime ^java.sql.Timestamp v) java.time.ZoneOffset/UTC))) (str (.toInstant ^java.sql.Timestamp v)))
                                                  (instance? java.sql.Date v) (str v)
                                                  (instance? org.postgresql.util.PGobject v) (.getValue ^org.postgresql.util.PGobject v)
                                                  :else v))])))) records)))))
(defn export [url]
  (Class/forName "org.postgresql.Driver")
  (with-open [connection (DriverManager/getConnection url)]
    (.setAutoCommit connection false) (.setReadOnly connection true)
    (.setTransactionIsolation connection Connection/TRANSACTION_REPEATABLE_READ)
    (try
      (let [names (map :tablename (rows connection "SELECT tablename FROM pg_catalog.pg_tables WHERE schemaname='public' ORDER BY tablename"))
            tables (into {} (for [name names] [(keyword name) (rows connection (str "SELECT * FROM public." (sql-name name)))]))
            sequences (into {} (for [name names
                                   :let [records (get tables (keyword name)) maximum (reduce max 0 (keep #(when (integer? (:id %)) (:id %)) records))
                                         columns (rows connection (str "SELECT column_name FROM information_schema.columns WHERE table_schema='public' AND table_name='" (str/replace name "'" "''") "' AND column_name='id'"))
                                         sequence (when (seq columns) (:sequence (first (rows connection (str "SELECT pg_get_serial_sequence('public." (str/replace (sql-name name) "'" "''") "','id') AS sequence")))))
                                         sequence-value (when sequence (:last_value (first (rows connection (str "SELECT last_value FROM " sequence)))))]]
                                  [(keyword name) (max maximum (or sequence-value 0))]))]
        (.commit connection)
        {:format "ecc-postgresql-v1" :tables tables :sequences sequences})
      (catch Throwable e (.rollback connection) (throw e)))))
