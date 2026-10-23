import json
import tempfile
from pathlib import Path
import unittest
from unittest import mock
import render_preflight as preflight


class RenderPreflightTests(unittest.TestCase):
    def config(self):
        return {'APP_ENV':'production','DATABASE_URL':'postgresql://fixture:private@example.invalid/crm?sslmode=require',
                'JWT_SECRET':'unit-test-private-value-at-least-32-bytes','PUBLIC_URL':'https://crm.example.invalid','SEED_DEMO':'false'}

    def test_api_configuration_has_no_secret_values_in_report(self):
        values=self.config()
        self.assertEqual(preflight.configuration_problems(values,'api'),[])
        for key in ['APP_ENV','DATABASE_URL','JWT_SECRET','PUBLIC_URL','SEED_DEMO']:
            broken={**values,key:''}
            report=json.dumps(preflight.configuration_problems(broken,'api'))
            self.assertIn(key,report)
            self.assertNotIn('fixture:private',report)

    def test_plaintext_postgres_and_credentialed_public_urls_fail(self):
        for url in ['https://user:private@example.invalid','https://example.invalid/path','http://example.invalid','https://example.invalid?secret=private']:
            self.assertIn('PUBLIC_URL:require-https-origin',preflight.configuration_problems({**self.config(),'PUBLIC_URL':url},'api'))
        self.assertIn('DATABASE_URL:require-postgresql-and-TLS',preflight.configuration_problems({**self.config(),'DATABASE_URL':'postgresql://fixture.invalid/crm?sslmode=disable'},'api'))

    def test_scanner_must_be_explicitly_configured(self):
        self.assertIn('CLAMD_HOST:required',preflight.configuration_problems(self.config(),'scan'))
        for port in ['0','65536','bad']:
            self.assertIn('CLAMD_PORT:invalid',preflight.configuration_problems({**self.config(),'CLAMD_HOST':'scanner','CLAMD_PORT':port},'scan'))
        self.assertEqual(preflight.configuration_problems({**self.config(),'CLAMD_HOST':'scanner','CLAMD_PORT':'3310'},'scan'),[])

    def test_api_port_and_pool_match_runtime_limits(self):
        for key, values in [('PORT', ['0','65536','bad','']), ('DB_POOL_SIZE', ['0','17','bad',''])]:
            for value in values:
                self.assertIn(key + ':invalid',preflight.configuration_problems({**self.config(),key:value},'api'))
        self.assertEqual(preflight.configuration_problems({**self.config(),'PORT':'10000','DB_POOL_SIZE':'16'},'api'),[])

    def test_backups_require_isolated_target_offsite_key_and_alerts(self):
        values={**self.config(),'RESTORE_TEST_DATABASE_URL':'postgresql://fixture.invalid/ecc_restore_drill?sslmode=require',
                'RESTIC_REPOSITORY':'s3:https://storage.invalid/ecc','RESTIC_PASSWORD':'fixture-test-key',
                'HEALTH_URL':'https://crm.example.invalid/api/ready','ALERT_WEBHOOK_URL':'https://alerts.example.invalid/ecc'}
        self.assertEqual(preflight.configuration_problems(values,'backup'),[])
        for key in ['RESTORE_TEST_DATABASE_URL','RESTIC_REPOSITORY','RESTIC_PASSWORD','HEALTH_URL','ALERT_WEBHOOK_URL']:
            self.assertTrue(preflight.configuration_problems({**values,key:''},'backup'))
        self.assertIn('RESTORE_TEST_DATABASE_URL:require-dedicated-drill-database',preflight.configuration_problems({**values,'RESTORE_TEST_DATABASE_URL':values['DATABASE_URL']},'backup'))

    def test_scanner_ping_rejects_error_verdict_and_connection_failure(self):
        with mock.patch.dict(preflight.os.environ,{'CLAMD_HOST':'scanner'}):
            with mock.patch.object(preflight.socket,'create_connection',side_effect=OSError('private details')):
                self.assertEqual(preflight.scanner_problem(),'scanner:unavailable-or-invalid-response')
            stream=mock.MagicMock();stream.__enter__.return_value=stream
            stream.recv.return_value=b'PONG\0'
            with mock.patch.object(preflight.socket,'create_connection',return_value=stream):
                self.assertIsNone(preflight.scanner_problem())
            stream.recv.return_value=b'ERROR\0'
            with mock.patch.object(preflight.socket,'create_connection',return_value=stream):
                self.assertEqual(preflight.scanner_problem(),'scanner:unavailable-or-invalid-response')


if __name__=='__main__': unittest.main()
