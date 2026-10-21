#!/usr/bin/env python3
"""Quarantine worker; ClamAV INSTREAM scanning outside SQLite writer transactions."""
from contextlib import closing
import os
import socket
import sqlite3
import struct
import time
import uuid


def scan_bytes(content):
    # Protocol: https://docs.clamav.net/manual/Usage/ClamdProtocol.html
    with socket.create_connection((os.environ.get('CLAMD_HOST', 'clamav'), int(os.environ.get('CLAMD_PORT', '3310'))), timeout=60) as stream:
        stream.sendall(b'zINSTREAM\0')
        for offset in range(0, len(content), 65536):
            chunk = content[offset:offset + 65536]
            stream.sendall(struct.pack('!I', len(chunk)) + chunk)
        stream.sendall(b'\0\0\0\0')
        response = b''
        while b'\0' not in response and len(response) < 4096:
            part = stream.recv(1024)
            if not part:
                break
            response += part
        answer = response.split(b'\0')[0].decode('utf-8', 'replace').strip()
        if answer == 'stream: OK':
            return 'Clean', 'ClamAV scan completed'
        if answer.startswith('stream: ') and answer.endswith(' FOUND'):
            return 'Infected', answer[:250]
        raise RuntimeError('Scanner did not return a complete verdict')


def run_once(conn, scanner=scan_bytes):
    lease = uuid.uuid4().hex
    with conn:
        row = conn.execute("UPDATE documents SET scan_status='Scanning',scan_lease=?,scan_until=datetime('now','+5 minutes'),scan_attempts=scan_attempts+1 WHERE id=(SELECT id FROM documents WHERE scan_status='Pending' OR scan_status='Error' AND scan_attempts<5 AND scan_until<datetime('now') OR scan_status='Scanning' AND scan_until<datetime('now') ORDER BY id LIMIT 1) RETURNING id,content", (lease,)).fetchone()
    if row is None:
        return False
    did, content = row
    try:
        verdict, detail = scanner(content)
        if verdict not in ('Clean', 'Infected'):
            raise ValueError('Invalid verdict')
    except Exception as exc:
        verdict, detail = 'Error', type(exc).__name__
    with conn:
        # A content change clears the lease; stale results cannot approve replacement bytes.
        changed = conn.execute("UPDATE documents SET scan_status=?,scan_detail=?,scanned_at=CASE WHEN ?='Error' THEN NULL ELSE datetime('now') END,scan_lease=NULL,scan_until=CASE WHEN ?='Error' THEN datetime('now','+5 minutes') ELSE NULL END WHERE id=? AND scan_lease=?", (verdict, detail, verdict, verdict, did, lease)).rowcount
        if changed and verdict == 'Infected':
            conn.execute("UPDATE document_requests SET status='Rejected',review_note='File blocked by malware scanning',reviewed_by=NULL WHERE id IN (SELECT request_id FROM document_versions WHERE document_id=? AND version=(SELECT max(v.version) FROM document_versions v WHERE v.request_id=document_versions.request_id))", (did,))
        if changed:
            conn.execute("INSERT INTO audit_log(entity_type,entity_id,entity_name,action) VALUES ('document',?,?,'updated')", (did, 'Malware scan: ' + verdict))
    return True


def main():
    while True:
        try:
            with closing(sqlite3.connect(os.environ['DATABASE_PATH'], timeout=10)) as conn:
                conn.execute('PRAGMA foreign_keys=ON')
                if not run_once(conn):
                    time.sleep(10)
        except (sqlite3.Error, OSError):
            print('scanner database retry', flush=True)
            time.sleep(10)

if __name__ == '__main__':
    main()
