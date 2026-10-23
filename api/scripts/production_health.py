#!/usr/bin/env python3
"""No customer data: check HTTPS readiness and the provider worker heartbeat."""
from contextlib import closing
from datetime import datetime, timezone
import json
import os
import database
import integration_worker
import operations


def check(conn):
    value = conn.execute('SELECT last_success_at FROM integration_worker_state WHERE id=1').fetchone()
    if not value or not value[0] or (datetime.now(timezone.utc)-integration_worker.parse_time(value[0])).total_seconds() > 180:
        raise ValueError('Provider worker heartbeat is stale')
    failures = conn.execute("SELECT count(*) FROM integration_jobs WHERE status IN ('Failed','Review')").fetchone()[0]
    if failures: raise ValueError('Provider operations require review')
    return {'worker':'healthy','providerOperationsRequiringReview':0}


def main():
    if operations.readiness_problem(integration_worker.public_origin()+'/api/ready'):
        raise SystemExit('API readiness failed')
    with closing(database.connect()) as conn:
        result = check(conn)
    print(json.dumps(dict(result,api='ready')))


if __name__ == '__main__': main()
