(ns ecc-crm.mfa
  (:require [clojure.string :as str])
  (:import [javax.crypto Mac] [javax.crypto.spec SecretKeySpec] [java.nio ByteBuffer]
           [java.time Instant] [java.security SecureRandom MessageDigest] [org.bouncycastle.util.encoders Base32]))
(defn secret [] (let [b (byte-array 20)] (.nextBytes (SecureRandom.) b) (Base32/toBase32String b)))
(defn code
  ([secret counter] (code secret counter "HmacSHA1"))
  ([secret counter algorithm]
   (when-not (contains? #{"HmacSHA1" "HmacSHA256"} algorithm) (throw (ex-info "Unsupported authenticator algorithm" {})))
   (let [mac (Mac/getInstance algorithm)
         _ (.init mac (SecretKeySpec. (Base32/decode (str/upper-case secret)) algorithm))
         bytes (.doFinal mac (.array (.putLong (ByteBuffer/allocate 8) counter)))
         offset (bit-and (aget bytes (dec (alength bytes))) 15)
         binary (bit-and (.getInt (ByteBuffer/wrap bytes) offset) 0x7fffffff)]
     (format "%06d" (mod binary 1000000)))))
(defn verify-counter
  ([secret value last-counter] (verify-counter secret value last-counter "HmacSHA1"))
  ([secret value last-counter algorithm]
   (when (and secret (re-matches #"\d{6}" (str value)))
     (let [counter (quot (.getEpochSecond (Instant/now)) 30)]
       (some (fn [n] (when (and (> n (or last-counter -1))
                                (MessageDigest/isEqual (.getBytes (code secret n algorithm) "UTF-8") (.getBytes value "UTF-8"))) n))
             [(dec counter) counter (inc counter)])))))
