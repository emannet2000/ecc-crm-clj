(ns ecc-crm.transport-test
  (:require [clojure.test :refer :all] [clojure.java.io :as io]
            [ecc-crm.workers :as workers] [ecc-crm.store :as store] [ecc-crm.domain :as d])
  (:import [java.net ServerSocket] [java.io DataInputStream ByteArrayOutputStream]
           [java.nio.file Files] [java.nio.file.attribute FileAttribute]))
(deftest clamav-instream-clean-and-infected
  (doseq [[content expected] [["fixture document" "Clean"] ["EICAR fixture marker" "Infected"]]]
    (with-open [server (ServerSocket. 0)]
      (.setSoTimeout server 10000)
      (let [file (.toFile (Files/createTempFile "ecc-scan-fixture-" ".txt" (make-array FileAttribute 0)))
            _ (spit file content)
            received (promise)
            job (future (with-open [socket (.accept server)]
                           (let [in (DataInputStream. (.getInputStream socket)) command (ByteArrayOutputStream.) body (ByteArrayOutputStream.)]
                             (loop [] (let [b (.read in)] (when (pos? b) (.write command b) (recur))))
                             (assert (= "zINSTREAM" (.toString command "US-ASCII")))
                             (loop [] (let [n (.readInt in)] (when (pos? n) (.write body (.readNBytes in n)) (recur))))
                             (deliver received (.toString body "UTF-8"))
                             (.write (.getOutputStream socket) (.getBytes (str "stream: " (if (= expected "Clean") "OK" "Eicar-Test-Signature FOUND") "\u0000") "UTF-8"))
                             (.flush (.getOutputStream socket)))))]
        (is (= expected (workers/scan file "127.0.0.1" (.getLocalPort server))))
        (is (= content (deref received 10000 :timeout)))
        (deref job 10000 :timeout)))))
(deftest smtp-delivery-and-body-redaction
  (with-open [server (ServerSocket. 0)]
    (.setSoTimeout server 10000)
    (let [body (promise)
          job (future (with-open [socket (.accept server)
                                 reader (io/reader (.getInputStream socket))
                                 writer (io/writer (.getOutputStream socket))]
                        (let [send (fn [text] (.write writer (str text "\r\n")) (.flush writer))]
                          (send "220 fixture ESMTP")
                          (loop [data? false lines []]
                            (when-let [line (.readLine ^java.io.BufferedReader reader)]
                              (cond
                                (and data? (= line ".")) (do (deliver body lines) (send "250 accepted") (recur false []))
                                data? (recur true (conj lines line))
                                (.startsWith line "EHLO") (do (send "250-fixture") (send "250 8BITMIME") (recur false lines))
                                (= line "DATA") (do (send "354 send body") (recur true lines))
                                (= line "QUIT") (send "221 bye")
                                :else (do (send "250 OK") (recur false lines))))))))
          db (store/memory-store)]
      (store/transact! db #(d/insert % :mail {:to "recipient@fixture.invalid" :subject "Fixture delivery" :body "Private test body" :status "Queued" :attempts 0}))
      (with-redefs [workers/smtp-config (constantly {:host "127.0.0.1" :port (.getLocalPort server) :tls false :connectiontimeout 5000 :timeout 5000})
                    workers/sender (constantly "sender@fixture.invalid")]
        (workers/deliver-mail! db))
      (is (= "Sent" (get-in (store/snapshot db) [:mail 1 :status])))
      (is (nil? (get-in (store/snapshot db) [:mail 1 :body])))
      (is (some #(clojure.string/includes? % "Private test body") (deref body 10000 [])))
      (deref job 10000 :timeout))))
