import json
import os
from pathlib import Path
import shutil
import sqlite3
import tempfile
import unittest
from unittest import mock
import operations
import recovery
import scan_worker


class OperationsTests(unittest.TestCase):
    def setUp(self):
        env = mock.patch.dict(os.environ,{'HEALTH_URL':'https://crm.example.test/api/ready'})
        env.start(); self.addCleanup(env.stop)
        ready = mock.patch.object(operations,'readiness_problem',return_value=None)
        ready.start(); self.addCleanup(ready.stop)
        usage = mock.patch.object(operations.shutil,'disk_usage',return_value=shutil._ntuple_diskusage(10*1024**3,2*1024**3,8*1024**3))
        usage.start(); self.addCleanup(usage.stop)
        self.temp = tempfile.TemporaryDirectory(prefix='ecc-ops-test-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.database = self.root/'database.sqlite3'
        self.backups = self.root/'backups'
        with sqlite3.connect(self.database) as conn:
            conn.execute('PRAGMA foreign_keys=ON')
            for file in sorted((Path(__file__).resolve().parents[1]/'migrations').glob('*.sql')):
                conn.executescript(file.read_text())

    def test_low_disk_and_api_outage_are_reported_without_paths(self):
        operations.backup(self.database,self.backups,False)
        with mock.patch.object(operations.shutil,'disk_usage',return_value=shutil._ntuple_diskusage(10*1024**3,10*1024**3-1024,1024)), mock.patch.object(operations,'readiness_problem',return_value='api:unavailable'):
            problems=operations.health(self.database,self.backups,False)
        self.assertIn('database-storage:low-space',problems)
        self.assertIn('backup-storage:low-space',problems)
        self.assertIn('api:unavailable',problems)
        self.assertNotIn(str(self.root),json.dumps(problems))

    def fake_restic(self, arguments):
        if arguments[0] == 'backup':
            self.uploaded = [Path(path) for path in arguments[arguments.index('--')+1:]]
            return json.dumps({'message_type':'summary','snapshot_id':'a'*64})
        if arguments[0] == 'restore':
            target = Path(arguments[arguments.index('--target')+1])
            for path in self.uploaded:
                restored = target/str(path).lstrip('/')
                restored.parent.mkdir(parents=True,exist_ok=True)
                shutil.copyfile(path,restored)
            return ''
        raise AssertionError(arguments)

    def test_actual_local_backup_and_restore_evidence(self):
        result=operations.backup(self.database,self.backups,remote=False)
        self.assertEqual(result['event'],'backup-verified')
        self.assertEqual(operations.health(self.database,self.backups,False),[])
        status=json.loads((self.backups/'restore-drill-status.json').read_text())
        self.assertIn('financialFileBytesSha256',status)
        self.assertIn('invoice_payments',status['tableCounts'])
        self.assertEqual((self.backups/'backup-status.json').stat().st_mode&0o077,0)

    def test_offsite_adapter_restores_and_verifies_remote_bytes(self):
        operations.backup(self.database,self.backups,runner=self.fake_restic)
        self.assertEqual(operations.health(self.database,self.backups),[])
        status=json.loads((self.backups/'offsite-status.json').read_text())
        self.assertTrue(status['restoreVerified'])

    def test_offsite_bad_restore_never_records_success(self):
        target=recovery.backup_once(self.database,self.backups)
        def bad(arguments):
            result=self.fake_restic(arguments)
            if arguments[0]=='restore':
                root=Path(arguments[arguments.index('--target')+1])
                (root/str(target).lstrip('/')).write_bytes(b'corrupt')
            return result
        with self.assertRaises((ValueError,OSError)):
            operations.offsite(target,self.backups,bad)
        self.assertFalse((self.backups/'offsite-status.json').exists())

    def test_alerts_deduplicate_and_report_recovery_without_private_data(self):
        alerts=[]
        first=operations.monitor(self.database,self.backups,False,sender=alerts.append)
        self.assertFalse(first['healthy'])
        operations.monitor(self.database,self.backups,False,sender=alerts.append)
        self.assertEqual(len(alerts),1)
        operations.backup(self.database,self.backups,False)
        fixed=operations.monitor(self.database,self.backups,False,sender=alerts.append)
        self.assertTrue(fixed['healthy'])
        self.assertEqual(alerts[-1]['event'],'operations-recovered')
        self.assertNotIn(str(self.database),json.dumps(alerts))
        self.assertNotIn('recipient',json.dumps(alerts))

    def test_failed_alert_delivery_is_retried(self):
        def fail(_): raise OSError('not available')
        first=operations.monitor(self.database,self.backups,False,sender=fail)
        self.assertFalse(first['alertDelivered'])
        self.assertTrue(first['notificationPending'])
        alerts=[]
        operations.monitor(self.database,self.backups,False,sender=alerts.append)
        self.assertEqual(len(alerts),1)

    def test_failed_recovery_notification_is_retried(self):
        operations.monitor(self.database,self.backups,False,sender=lambda _:None)
        operations.backup(self.database,self.backups,False)
        def fail(_): raise OSError('webhook unavailable')
        recovered=operations.monitor(self.database,self.backups,False,sender=fail)
        self.assertTrue(recovered['healthy'])
        self.assertTrue(recovered['notificationPending'])
        alerts=[]
        retried=operations.monitor(self.database,self.backups,False,sender=alerts.append)
        self.assertEqual(alerts[0]['event'],'operations-recovered')
        self.assertFalse(retried['notificationPending'])

    def test_monitor_detects_stuck_mail_and_financial_scan_failures(self):
        operations.backup(self.database,self.backups,False)
        with sqlite3.connect(self.database) as conn:
            conn.execute("INSERT INTO mail_outbox(recipient,subject,body,attempts) VALUES ('private@example.test','private','private',5)")
            conn.execute("INSERT INTO expenses(supplier,description,category,currency,amount_minor,expense_on,created_by,created_name) VALUES ('supplier','expense','office','PHP',100,'2020-01-01',1,'actor')")
            conn.execute("INSERT INTO financial_files(expense_id,filename,content,size,uploaded_by,uploaded_name,scan_status) VALUES (1,'private.pdf',X'255044462D',5,1,'actor','Error')")
        problems=operations.health(self.database,self.backups,False)
        self.assertIn('email:failed-or-stuck',problems)
        self.assertIn('financial_files:scanning-failed-or-stuck',problems)

    def test_backup_job_failure_stays_unhealthy_until_success(self):
        operations.backup(self.database,self.backups,False)
        recovery.atomic_json(self.backups/'backup-job-status.json',{'state':'failed','attemptedAt':recovery.utc_now().isoformat()})
        self.assertIn('backup-job:failed-or-interrupted',operations.health(self.database,self.backups,False))

    def test_financial_file_scanner_retains_audit_and_quarantine(self):
        with sqlite3.connect(self.database) as conn:
            conn.execute("INSERT INTO expenses(supplier,description,category,currency,amount_minor,expense_on,created_by,created_name) VALUES ('supplier','expense','office','PHP',100,'2020-01-01',1,'actor')")
            conn.execute("INSERT INTO financial_files(expense_id,filename,content,size,uploaded_by,uploaded_name) VALUES (1,'receipt.pdf',X'255044462D',5,1,'actor')")
            conn.commit()
            self.assertTrue(scan_worker.run_financial_once(conn,lambda content:('Clean','verified')))
            self.assertEqual(conn.execute('SELECT scan_status FROM financial_files').fetchone()[0],'Clean')
            self.assertEqual(conn.execute("SELECT count(*) FROM finance_audit WHERE action='scan'").fetchone()[0],1)

    def test_plaintext_offsite_and_insecure_alert_endpoints_are_rejected(self):
        with mock.patch.dict(os.environ,{'RESTIC_REPOSITORY':'/local/backup'}):
            with self.assertRaises(ValueError): operations.run_restic(['backup'])
        with mock.patch.dict(os.environ,{'ALERT_WEBHOOK_URL':'http://alerts.example.test'}):
            with self.assertRaises(ValueError): operations.send_alert({})

if __name__=='__main__':unittest.main()
