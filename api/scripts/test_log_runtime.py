import contextlib
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import time
import tempfile
import unittest
from unittest import mock

import alerting
import log_runtime


class RuntimeTests(unittest.TestCase):
    def test_errors_alert_deduplicate_retry_and_recover(self):
        now = [1000]
        alerts = []
        monitor = log_runtime.Monitor(sender=alerts.append, clock=lambda: now[0])
        for _ in range(10):
            monitor.observe({'event': 'request_completed', 'status': 500})
        for _ in range(3):
            monitor.observe({'event': 'database_error', 'status': 503})
        self.assertEqual(monitor.check(True), ['api:server-errors', 'database:request-failures'])
        monitor.check(True)
        self.assertEqual(len(alerts), 1)
        now[0] += 360
        monitor.sender = mock.Mock(side_effect=OSError('secret URL'))
        with self.assertRaises(OSError):
            monitor.check(True)
        self.assertNotEqual(monitor.active, ())
        monitor.sender = alerts.append
        self.assertEqual(monitor.check(True), [])
        self.assertEqual(alerts[-1]['event'], 'runtime-recovered')
        self.assertEqual(monitor.active, ())

    def test_readiness_threshold_and_storage_failure(self):
        alerts = []
        monitor = log_runtime.Monitor(sender=alerts.append)
        self.assertEqual(monitor.check(False), [])
        self.assertEqual(monitor.check(False), [])
        self.assertEqual(monitor.check(False), ['api:readiness-failed'])
        self.assertEqual(len(alerts), 1)
        self.assertEqual(monitor.check(True, True), ['logs:storage-failed'])
        self.assertEqual(monitor.check(True), [])

    def test_bounded_counters_and_client_errors_do_not_alert(self):
        now = [1000]
        monitor = log_runtime.Monitor(sender=lambda value: self.fail(str(value)), clock=lambda: now[0])
        for i in range(100):
            now[0] += 60
            monitor.observe({'event': 'request_completed', 'status': 409})
        self.assertLessEqual(len(monitor.buckets), 5)
        self.assertEqual(monitor.check(True), [])

    def test_rotation_retention_permissions_and_restart(self):
        with tempfile.TemporaryDirectory() as root, contextlib.redirect_stdout(io.StringIO()):
            recorder = log_runtime.Recorder(root, max_bytes=150, copies=2)
            for i in range(20):
                recorder.write(log_runtime.event('test', index=i))
            recorder.close()
            files = list(Path(root).glob('api.jsonl*'))
            self.assertLessEqual(len(files), 3)
            for path in files:
                self.assertEqual(path.stat().st_mode & 0o077, 0)
                for line in path.read_text().splitlines():
                    json.loads(line)
            before = (Path(root)/'api.jsonl').read_text()
            recorder = log_runtime.Recorder(root)
            recorder.write(log_runtime.event('after-restart'))
            recorder.close()
            self.assertTrue((Path(root)/'api.jsonl').read_text().startswith(before))
            old = Path(root)/'api.jsonl.2'
            old.write_text('old')
            os.utime(old, (0, 0))
            recorder = log_runtime.Recorder(root)
            recorder.write(log_runtime.event('prune'))
            recorder.close()
            self.assertFalse(old.exists())

    def test_disk_errors_are_visible(self):
        with tempfile.TemporaryDirectory() as root, contextlib.redirect_stdout(io.StringIO()) as output:
            recorder = log_runtime.Recorder(root)
            with mock.patch.object(recorder.handler, 'shouldRollover', side_effect=OSError('secret path')):
                recorder.write(log_runtime.event('test'))
            self.assertTrue(recorder.failed)
            self.assertIn('log_storage_failed', output.getvalue())
            self.assertNotIn('secret path', output.getvalue())
            recorder.close()

    def test_supervisor_preserves_json_suppresses_raw_secrets_and_exit_status(self):
        with tempfile.TemporaryDirectory() as root:
            env = dict(os.environ, API_LOG_DIR=root)
            env.pop('ALERT_WEBHOOK_URL', None)
            code = 'import json;print(json.dumps({"service":"ecc-crm-api","event":"test"}));print("password=secret");raise SystemExit(7)'
            result = subprocess.run([sys.executable, str(Path(log_runtime.__file__)), '--', sys.executable, '-c', code],
                                    env=env, capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 7)
            content = (Path(root)/'api.jsonl').read_text()
            self.assertNotIn('password=secret', content+result.stdout+result.stderr)
            events = [json.loads(line)['event'] for line in content.splitlines()]
            self.assertIn('test', events)
            self.assertIn('unstructured_process_output', events)
            self.assertIn('process_exited', events)

    def test_supervisor_forwards_shutdown_without_reporting_a_crash(self):
        with tempfile.TemporaryDirectory() as root:
            env = dict(os.environ, API_LOG_DIR=root)
            env.pop('ALERT_WEBHOOK_URL', None)
            code = 'import json,time;print(json.dumps({"service":"ecc-crm-api","event":"child-ready"}),flush=True);time.sleep(60)'
            child = subprocess.Popen([sys.executable, str(Path(log_runtime.__file__)), '--', sys.executable, '-c', code],
                                     env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            try:
                log = Path(root)/'api.jsonl'
                for _ in range(100):
                    if log.exists() and 'child-ready' in log.read_text():
                        break
                    time.sleep(.02)
                else:
                    self.fail('Child did not start')
                child.terminate()
                self.assertEqual(child.wait(timeout=12), 0)
                last = json.loads(log.read_text().splitlines()[-1])
                self.assertTrue(last['expectedStop'])
                self.assertEqual(last['severity'], 'INFO')
            finally:
                if child.poll() is None:
                    child.kill()
                    child.wait()

    def test_alert_rejects_http_and_insecure_token_file(self):
        with mock.patch.dict(os.environ, {'ALERT_WEBHOOK_URL': 'http://example.invalid'}):
            with self.assertRaises(ValueError):
                alerting.send_alert({})
        with tempfile.TemporaryDirectory() as root:
            token = Path(root)/'token'
            token.write_text('secret')
            token.chmod(0o644)
            with mock.patch.dict(os.environ, {'ALERT_WEBHOOK_URL': 'https://example.invalid', 'ALERT_TOKEN_FILE': str(token)}):
                with self.assertRaises(ValueError):
                    alerting.send_alert({})


if __name__ == '__main__':
    unittest.main()
