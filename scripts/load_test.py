#!/usr/bin/env python3
"""Bounded read load test for a dedicated staging account; never prints the token."""
import argparse
import concurrent.futures
import json
import math
import os
import time
import urllib.error
import urllib.request


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('url')
    parser.add_argument('--requests', type=int, default=100)
    parser.add_argument('--concurrency', type=int, default=8)
    parser.add_argument('--max-p95-ms', type=float, default=2000)
    args = parser.parse_args()
    if not 1 <= args.requests <= 10000 or not 1 <= args.concurrency <= 64:
        parser.error('requests must be 1–10000 and concurrency 1–64')
    token = os.environ.get('ECC_LOAD_TOKEN')
    if not token:
        parser.error('Set ECC_LOAD_TOKEN to a staging session token')
    paths = ['/api/ready', '/api/leads?limit=50', '/api/clients?limit=50', '/api/tasks?limit=50', '/api/stats']

    def request(index):
        started = time.monotonic()
        req = urllib.request.Request(args.url.rstrip('/') + paths[index % len(paths)], headers={'Authorization': 'Bearer ' + token})
        try:
            with urllib.request.urlopen(req, timeout=30) as response:
                response.read()
                ok = response.status == 200
        except (OSError, urllib.error.HTTPError):
            ok = False
        return (time.monotonic() - started) * 1000, ok

    started = time.monotonic()
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.concurrency) as pool:
        results = list(pool.map(request, range(args.requests)))
    timings = sorted(duration for duration, _ in results)
    failures = sum(not ok for _, ok in results)
    p95 = timings[math.ceil(len(timings) * .95) - 1]
    print(json.dumps({'requests': len(results), 'concurrency': args.concurrency, 'errors': failures,
                      'p95Ms': round(p95, 2), 'maxMs': round(max(timings), 2),
                      'elapsedSeconds': round(time.monotonic() - started, 2)}))
    raise SystemExit(bool(failures or p95 > args.max_p95_ms))


if __name__ == '__main__':
    main()
