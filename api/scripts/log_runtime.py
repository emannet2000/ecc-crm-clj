#!/usr/bin/env python3
"""Run the API with private rotating logs and deduplicated health alerts."""
import argparse
from collections import defaultdict
from datetime import datetime, timezone
import json
import logging
from logging.handlers import RotatingFileHandler
import os
from pathlib import Path
import signal
import subprocess
import sys
import threading
import time
import urllib.request

from alerting import send_alert


def event(name, severity='INFO', **fields):
    return dict(timestamp=datetime.now(timezone.utc).isoformat(), severity=severity,
                event=name, service='ecc-crm-runtime', **fields)


class Recorder:
    def __init__(self, directory, max_bytes=10*1024*1024, copies=10, days=14):
        self.directory = Path(directory)
        self.directory.mkdir(parents=True, exist_ok=True, mode=0o700)
        os.chmod(self.directory, 0o700)
        self.days = days
        self.lock = threading.Lock()
        self.handler = RotatingFileHandler(self.directory/'api.jsonl', maxBytes=max_bytes,
                                          backupCount=copies, encoding='utf-8')
        self.handler.setFormatter(logging.Formatter('%(message)s'))
        os.chmod(self.directory/'api.jsonl', 0o600)
        self.last_prune = 0
        self.failed = False

    def write(self, value):
        line = json.dumps(value, separators=(',', ':'))
        with self.lock:
            # Stdout remains available to the hosting provider's log collector.
            print(line, flush=True)
            try:
                # Call emit's underlying operations directly: logging.emit normally
                # swallows disk errors, which would hide loss of persistence.
                record = logging.makeLogRecord({'msg': line, 'levelno': logging.INFO})
                if self.handler.shouldRollover(record):
                    self.handler.doRollover()
                self.handler.stream.write(line+'\n')
                self.handler.flush()
                os.chmod(self.directory/'api.jsonl', 0o600)
                now = time.time()
                if now-self.last_prune >= 60:
                    for path in self.directory.glob('api.jsonl*'):
                        if path.is_file() and now-path.stat().st_mtime > self.days*86400:
                            path.unlink()
                    self.last_prune = now
                self.failed = False
            except OSError:
                self.failed = True
                print(json.dumps(event('log_storage_failed', 'ERROR')), flush=True)

    def close(self):
        self.handler.close()


class Monitor:
    def __init__(self, sender=send_alert, clock=time.monotonic):
        self.sender, self.clock = sender, clock
        self.lock = threading.Lock()
        self.buckets = defaultdict(lambda: [0, 0])
        self.readiness_failures = 0
        self.active = ()
        self.last_sent = 0

    def observe(self, value):
        with self.lock:
            minute = int(self.clock()//60)
            for key in list(self.buckets):
                if key <= minute-5:
                    del self.buckets[key]
            counts = self.buckets[minute]
            status = value.get('status')
            if value.get('event') == 'request_completed' and isinstance(status, int) and status >= 500:
                counts[0] += 1
            if value.get('event') == 'database_error' and isinstance(status, int) and status >= 500:
                counts[1] += 1

    def check(self, ready, storage_failed=False):
        with self.lock:
            self.readiness_failures = 0 if ready else self.readiness_failures+1
            now = self.clock()
            recent = [v for k, v in self.buckets.items() if k > int(now//60)-5]
            problems = []
            if sum(v[0] for v in recent) >= 10:
                problems.append('api:server-errors')
            if sum(v[1] for v in recent) >= 3:
                problems.append('database:request-failures')
            if self.readiness_failures >= 3:
                problems.append('api:readiness-failed')
            if storage_failed:
                problems.append('logs:storage-failed')
        current = tuple(sorted(problems))
        if current != self.active or (current and now-self.last_sent >= 3600):
            payload = event('runtime-problems' if current else 'runtime-recovered',
                            'ERROR' if current else 'INFO', problems=list(current))
            # Only acknowledge delivery after success; retry on the next check.
            self.sender(payload)
            self.active, self.last_sent = current, now
        return problems


def readiness(port):
    # Fixed local address, no credentials, redirects, proxy or URL parameters.
    class NoRedirect(urllib.request.HTTPRedirectHandler):
        def redirect_request(self, request, fp, code, msg, headers, newurl):
            return None
    try:
        opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirect)
        with opener.open(f'http://127.0.0.1:{port}/api/ready', timeout=5) as response:
            body = response.read(4097)
            return response.status == 200 and len(body) <= 4096 and json.loads(body).get('status') == 'ready'
    except (OSError, ValueError, AttributeError):
        return False


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command[1:] if args.command[:1] == ['--'] else args.command
    if not command:
        parser.error('Provide the API command after --')
    os.umask(0o077)
    directory = os.environ.get('API_LOG_DIR', '/var/log/ecc')
    recorder = Recorder(directory)
    monitor = Monitor()
    port = int(os.environ.get('PORT', '4000'))
    if not 1 <= port <= 65535:
        parser.error('PORT must be between 1 and 65535')
    alerts_enabled = bool(os.environ.get('ALERT_WEBHOOK_URL'))
    recorder.write(event('runtime_started', alertsEnabled=alerts_enabled))
    if not alerts_enabled:
        recorder.write(event('runtime_alerts_unconfigured', 'WARN'))
    child = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)

    shutdown = [None]

    def forward_signal(signum, _frame):
        shutdown[0] = time.monotonic()+10
        if child.poll() is None:
            child.send_signal(signum)
    signal.signal(signal.SIGTERM, forward_signal)
    signal.signal(signal.SIGINT, forward_signal)

    def collect():
        # Bounded reads prevent an unexpectedly long diagnostic from filling RAM.
        while True:
            line = child.stdout.readline(65537)
            if not line:
                break
            oversized = len(line) > 65536
            if oversized:
                while line and not line.endswith(b'\n'):
                    line = child.stdout.readline(65537)
            try:
                value = json.loads(line) if not oversized else None
                if not isinstance(value, dict) or value.get('service') != 'ecc-crm-api':
                    raise ValueError('Unstructured output')
            except (ValueError, UnicodeError):
                # Raw runtime/boot exceptions may contain secrets; never persist them.
                value = event('unstructured_process_output', 'WARN')
            recorder.write(value)
            monitor.observe(value)

    collector = threading.Thread(target=collect, daemon=True)
    collector.start()
    try:
        next_check = time.monotonic()+30
        while child.poll() is None:
            try:
                child.wait(timeout=1)
                break
            except subprocess.TimeoutExpired:
                pass
            if shutdown[0] is not None:
                if time.monotonic() >= shutdown[0]:
                    child.kill()
                continue
            if time.monotonic() < next_check:
                continue
            next_check = time.monotonic()+30
            ready = readiness(port)
            try:
                if alerts_enabled:
                    monitor.check(ready, recorder.failed)
            except Exception:
                recorder.write(event('runtime_alert_delivery_failed', 'ERROR'))
        collector.join(timeout=5)
        expected_stop = shutdown[0] is not None
        recorder.write(event('process_exited', 'ERROR' if child.returncode and not expected_stop else 'INFO', exitCode=child.returncode, expectedStop=expected_stop))
        if child.returncode and not expected_stop and alerts_enabled:
            try:
                send_alert(event('api-process-exited', 'ERROR', exitCode=child.returncode))
            except Exception:
                recorder.write(event('runtime_alert_delivery_failed', 'ERROR'))
        if expected_stop:
            return 0
        return child.returncode if child.returncode is not None and child.returncode >= 0 else 1
    finally:
        if child.poll() is None:
            child.terminate()
            try:
                child.wait(timeout=10)
            except subprocess.TimeoutExpired:
                child.kill()
                child.wait()
        child.stdout.close()
        recorder.close()


if __name__ == '__main__':
    try:
        sys.exit(main())
    except Exception as exc:
        # Exception strings can contain command arguments and filesystem secrets.
        print(json.dumps(event('runtime_failed', 'ERROR', errorType=type(exc).__name__)), flush=True)
        sys.exit(1)
