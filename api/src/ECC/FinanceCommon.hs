{-# LANGUAGE OverloadedStrings #-}
module ECC.FinanceCommon (financialClients, requireOpenDate, companyPermission, expenseAccess, auditControl) where
import Control.Monad (when, unless, void)
import Control.Monad.IO.Class (liftIO)
import qualified Data.Aeson as A
import qualified Data.ByteString.Lazy as BL
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import Network.HTTP.Types hiding (Query)
import qualified Web.Scotty as S
import ECC.DB (Env(..))
import ECC.Models
import ECC.Store
import ECC.Security (reject)
import qualified ECC.Access as Access

financialClients :: Query
financialClients = "SELECT id FROM clients WHERE merged_into IS NULL AND ((SELECT assigned_only FROM request_context WHERE id=1)<>'true' OR (SELECT role FROM request_context WHERE id=1)='admin' OR case_officer_id=(SELECT actor_id FROM request_context WHERE id=1))"

requireOpenDate :: Env -> T.Text -> S.ActionM ()
requireOpenDate env date = do
 rows <- liftIO $ query (envConn env) "SELECT month FROM financial_periods WHERE month=? AND closed=1" (Only (T.take 7 date)) :: S.ActionM [Only T.Text]
 unless (null rows) $ reject status409 "This financial month is closed. An authorized administrator must reopen it with a reason."

companyPermission :: Env -> User -> T.Text -> S.ActionM ()
companyPermission env u privilege = do
 Access.requirePrivilege env u "finance_view"
 Access.requirePrivilege env u privilege
 assigned <- liftIO $ Access.assignedOnly env u
 when (assigned && userRole u/="admin") $ reject status403 "Company-wide financial access is required for periods and bank reconciliation"

expenseAccess :: Env -> User -> Int -> S.ActionM Int
expenseAccess env u eid = do
 Access.requirePrivilege env u "finance_view"
 allExpenses <- liftIO $ Access.hasPrivilege env u "expenses_approve"
 rows <- liftIO $ query (envConn env) "SELECT revision FROM expenses WHERE id=? AND (? OR created_by=?)" (eid,allExpenses,userId u) :: S.ActionM [Only Int]
 case rows of [Only rev] -> pure rev; _ -> reject status404 "Expense not found"

auditControl :: Env -> User -> T.Text -> Int -> T.Text -> A.Value -> IO ()
auditControl env u kind ident action details = void $ execute (envConn env) "INSERT INTO finance_audit(kind,record_id,action,details,actor_id,actor_name) VALUES (?,?,?,?,?,?)" (kind,ident,action,TE.decodeUtf8(BL.toStrict(A.encode details)),userId u,userName u)
