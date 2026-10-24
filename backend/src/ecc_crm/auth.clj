(ns ecc-crm.auth
  (:refer-clojure :exclude [reset!])
  (:require [buddy.hashers :as hashers]
            [clojure.string :as str]
            [ecc-crm.domain :as d]
            [ecc-crm.mfa :as mfa]
            [ecc-crm.store :as store])
  (:import [java.security SecureRandom MessageDigest]
           [java.util Base64]
           [java.time Instant]))

(defn token []
  (let [b (byte-array 32)] (.nextBytes (SecureRandom.) b)
    (.encodeToString (.withoutPadding (Base64/getUrlEncoder)) b)))
(defn digest [value]
  (.formatHex (java.util.HexFormat/of) (.digest (MessageDigest/getInstance "SHA-256") (.getBytes (str value) "UTF-8"))))
(defn hash-password [password]
  (when (or (< (count (str password)) 12) (> (alength (.getBytes (str password) "UTF-8")) 1024)
            (str/includes? (str password) "\u0000"))
    (d/fail 400 "Use a password of 12–1024 bytes without NUL characters"))
  (hashers/derive password {:alg :bcrypt+sha512 :iterations 12}))
(defn password? [password encoded]
  (try
    (if (str/starts-with? (str encoded) "$2")
      (and (<= (alength (.getBytes (str password) "UTF-8")) 72)
           (not (str/includes? (str password) "\u0000"))
           (buddy.impl.bcrypt.BCrypt/checkpw password encoded))
      (boolean (hashers/check password encoded)))
    (catch Exception _ false)))
(def dummy-hash (delay (hash-password "invalid-account-password")))
(defn unexpired? [r] (and (:expiresAt r) (.isAfter (Instant/parse (:expiresAt r)) (Instant/now))))
(defn request-token [req]
  (or (some-> (get-in req [:headers "authorization"]) (str/replace #"^Bearer " ""))
      (get-in req [:cookies "ecc_session" :value])))
(defn authenticate [s req]
  (let [session (get-in s [:sessions (digest (request-token req))]) user (get-in s [:users (:userId session)])]
    (when (and (unexpired? session) user (not (:suspended user))) user)))
(defn cookie [value production? max-age]
  {:ecc_session {:value value :http-only true :same-site :strict :secure production? :path "/" :max-age max-age}})
(defn revoke-user [s uid]
  (update s :sessions #(into {} (remove (fn [[_ session]] (= uid (:userId session))) %))))
(defn create-user [s actor input]
  (when actor (d/admin! actor))
  (let [email (str/lower-case (d/required input :email 255))
        _ (when (some #(= email (:email %)) (d/rows s :users)) (d/fail 409 "Email address already exists"))
        role (d/choice (:role input "consultant") ["admin" "consultant" "viewer"])
        [s u] (d/insert s :users {:email email :name (d/required input :name 255) :role role
                                 :passwordHash (or (:passwordHash input) (hash-password (:password input)))})]
    [(d/audit s actor :users u "created") (d/public-user u)]))
(defn recovery-match [u value]
  (when (seq value)
    (let [raw (str value) bytes (.digest (MessageDigest/getInstance "SHA-256") (.getBytes raw "UTF-8"))
          candidates #{(digest (str/upper-case (str/replace raw " " "")))
                       (.encodeToString (.withoutPadding (Base64/getUrlEncoder)) bytes)}]
      (some candidates (:recoveryCodes u)))))
(defn login! [db input source]
  (let [email (str/lower-case (str/trim (str (or (:email input) (:lrEmail input)))))
        password (or (:password input) (:lrPassword input) "")
        raw (token) key (digest raw)
        result (store/transact! db
                 (fn [s]
                   (let [time (.getEpochSecond (Instant/now))
                         account-key (digest (str "account:" email))
                         source-key (digest (str "source:" source))
                         recent (fn [k] (vec (filter #(> % (- time 900)) (get-in s [:loginAttempts k] []))))
                         limited? (or (>= (count (recent account-key)) 20) (>= (count (recent source-key)) 200))
                         s (reduce #(assoc-in %1 [:loginAttempts %2] (conj (recent %2) time)) s [account-key source-key])
                         u (some #(when (= email (:email %)) %) (d/rows s :users))
                         recovery-key (recovery-match u (:recoveryCode input))
                         recovery? (boolean recovery-key)
                         counter (when (:mfaSecret u) (mfa/verify-counter (:mfaSecret u) (or (:otp input) (:lrOtp input)) (:mfaCounter u) (:mfaAlgorithm u "HmacSHA1")))]
                     (cond limited? [s {:error "Too many login attempts. Try again later." :status 429}]
                           (not (and (password? password (or (:passwordHash u) @dummy-hash))
                                     u (not (:suspended u)))) [s {:error "Invalid email or password" :status 401}]
                           (and (:mfaSecret u) (nil? counter) (not recovery?)) [s {:error "Enter a current authenticator code" :status 401}]
                           :else [(assoc-in (cond-> s counter (assoc-in [:users (:id u) :mfaCounter] counter) recovery? (update-in [:users (:id u) :recoveryCodes] #(vec (remove #{recovery-key} %)))) [:sessions key]
                                            {:userId (:id u) :createdAt (d/now)
                                             :expiresAt (str (.plusSeconds (Instant/now) 28800))})
                                  {:user (d/public-user u) :token raw}]))))]
    (when (:error result) (d/fail (:status result) (:error result))) result))
(defn logout! [db req]
  (store/transact! db #(vector (update % :sessions dissoc (digest (request-token req))) {:loggedOut true})))
(defn change-password [s u input]
  (let [current (d/record s :users (:id u))]
    (when-not (password? (:currentPassword input) (:passwordHash current)) (d/fail 403 "Current password is incorrect"))
    [(-> s (assoc-in [:users (:id u) :passwordHash] (hash-password (:newPassword input)))
         (revoke-user (:id u))) {:message "Password changed. Sign in again."}]))

(defn security [s u action input]
  (let [old (d/record s :users (:id u))]
    (case action
      "setup" (let [secret (mfa/secret)]
                [(assoc-in s [:users (:id u) :mfaPending] secret)
                 {:secret secret :uri (str "otpauth://totp/ECC:" (:email u) "?secret=" secret "&issuer=ECC")}])
      "enable" (let [codes (vec (repeatedly 10 #(str/upper-case (subs (token) 0 16))))
                     secret (:mfaPending old)
                     counter (when secret (mfa/verify-counter secret (:otp input) nil))]
                 (when-not (and counter (password? (:password input) (:passwordHash old)))
                   (d/fail 403 "Verify your password and authenticator code"))
                 [(-> s (assoc-in [:users (:id u) :mfaSecret] secret)
                      (assoc-in [:users (:id u) :mfaAlgorithm] "HmacSHA1")
                      (assoc-in [:users (:id u) :recoveryCodes] (mapv digest codes))
                      (assoc-in [:users (:id u) :mfaCounter] counter)
                      (update-in [:users (:id u)] dissoc :mfaPending) (revoke-user (:id u)))
                  {:message "Authenticator enabled. Store these single-use recovery codes, then sign in again." :recoveryCodes codes}])
      "disable" (do
                  (when-not (and (password? (:password input) (:passwordHash old))
                                 (or (mfa/verify-counter (:mfaSecret old) (:otp input) (:mfaCounter old) (:mfaAlgorithm old "HmacSHA1"))
                                     (recovery-match old (:recoveryCode input))))
                    (d/fail 403 "Verify your password and authenticator code"))
                  [(-> s (update-in [:users (:id u)] dissoc :mfaSecret :mfaCounter :mfaAlgorithm :recoveryCodes) (revoke-user (:id u)))
                   {:message "Authenticator disabled. Sign in again."}])
      "revoke" [(update s :sessions #(into {} (remove (fn [[key session]]
                                                       (and (= (:id u) (:userId session))
                                                            (str/starts-with? key (str (:id input))))) %)))
                {:message "Session revoked"}]
      (d/fail 404 "Unknown security action"))))
(defn attempt [s category key maximum]
  (let [now (.getEpochSecond (Instant/now)) k (digest (str category ":" key))
        recent (filterv #(> % (- now 900)) (get-in s [:operationAttempts k] []))]
    [(assoc-in s [:operationAttempts k] (conj recent now)) (< (count recent) maximum)]))
(defn recover! [db input public-url]
  (let [raw (token) email (str/lower-case (str/trim (str (:email input))))]
    (store/transact! db
      (fn [s]
        (let [[s allowed?] (attempt s "recovery" email 20)]
        (if-let [u (when allowed? (some #(when (= email (:email %)) %) (d/rows s :users)))]
          (let [s (assoc-in s [:recovery (digest raw)] {:userId (:id u) :expiresAt (str (.plusSeconds (Instant/now) 3600))})
                [s _] (d/insert s :mail {:to email :subject "Reset your ECC password" :status "Queued" :attempts 0
                                          :body (str "Reset your password: " public-url "/#/reset?token=" raw)})]
            [s {:message "If this account exists, a recovery email has been queued."}])
          [s {:message "If this account exists, a recovery email has been queued."}]))))))
(defn reset! [db input]
  (let [encoded (hash-password (:password input))]
    (store/transact! db
      (fn [s]
        (let [key (digest (:token input)) entry (get-in s [:recovery key])]
          (when-not (unexpired? entry) (d/fail 400 "Reset link is invalid or expired"))
          [(-> s (assoc-in [:users (:userId entry) :passwordHash] encoded)
               (update :recovery dissoc key) (revoke-user (:userId entry)))
           {:message "Password reset. Sign in with your new password."}])))))
