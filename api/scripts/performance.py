#!/usr/bin/env python3
"""Repeatable SQLite scaling checks; uses synthetic data, never the runtime DB."""
import json
import sqlite3
import statistics
import time
from pathlib import Path


def median_ms(db, sql, params=()):
    timings = []
    for _ in range(25):
        start = time.perf_counter()
        db.execute(sql, params).fetchall()
        timings.append((time.perf_counter() - start) * 1000)
    return statistics.median(timings)


with sqlite3.connect(':memory:') as db:
    db.executescript('''
        CREATE TABLE leads(id INTEGER PRIMARY KEY, converted_client_id INTEGER);
        CREATE TABLE cases(id INTEGER PRIMARY KEY,client_id INTEGER,next_deadline TEXT);
        CREATE TABLE tasks(id INTEGER PRIMARY KEY,client_id INTEGER,due_date TEXT);
        CREATE TABLE work_history(id INTEGER PRIMARY KEY,lead_id INTEGER);
        CREATE TABLE record_versions(kind TEXT,record_id INTEGER,revision INTEGER,
                                     PRIMARY KEY(kind,record_id));
    ''')
    db.executemany('INSERT INTO leads VALUES (?,?)',
                   ((i, i) for i in range(1, 100001)))
    db.executemany('INSERT INTO record_versions VALUES (?,?,?)',
                   (('clients', i, 2) for i in range(1, 100001)))
    history = 'SELECT id FROM leads WHERE converted_client_id=?'
    before = median_ms(db, history, (50000,))
    db.executescript((Path(__file__).resolve().parents[1] /
                     'migrations/0010_workspace_performance.sql').read_text())
    after = median_ms(db, history, (50000,))
    plan = str(db.execute('EXPLAIN QUERY PLAN ' + history, (50000,)).fetchall())
    assert 'leads_converted_client' in plan, plan
    print(f'100,000 leads: client history lookup {before:.3f} -> {after:.3f} ms')
    keys = json.dumps([{'kind': 'clients', 'id': i} for i in range(1, 51)])
    rows = db.execute('''SELECT v.kind,v.record_id,v.revision FROM json_each(?) j
        JOIN record_versions v ON v.kind=json_extract(j.value,'$.kind')
        AND v.record_id=json_extract(j.value,'$.id')''', (keys,)).fetchall()
    assert len(rows) == 50 and all(row[2] == 2 for row in rows)
    print('50-row revision enrichment: 1 query instead of 50; values verified')

# Use the production visibility predicate, with enough unrelated work to expose
# accidental whole-database materialization in an individual client record.
import re
root = Path(__file__).resolve().parents[1]
source = (root / 'src/ECC/WorkflowSupport.hs').read_text()
def query_literal(name):
    return json.loads(re.search(r'^' + name + r' = (".*")$', source, re.M).group(1))
leads = query_literal('visibleLeads')
clients = query_literal('visibleClients')
visibility = query_literal('taskVisibility')
old_visibility = ('SELECT id FROM tasks WHERE (lead_id IN (' + leads +
                  ') OR client_id IN (' + clients +
                  ")) AND ((SELECT assigned_only FROM request_context WHERE id=1)<>'true' OR "
                  "(SELECT role FROM request_context WHERE id=1)='admin' OR "
                  'assigned_to_id=(SELECT actor_id FROM request_context WHERE id=1))')
with sqlite3.connect(':memory:') as db:
    db.executescript('''
      CREATE TABLE clients(id INTEGER PRIMARY KEY,deleted_at TEXT,case_officer_id INTEGER);
      CREATE TABLE leads(id INTEGER PRIMARY KEY,deleted_at TEXT,converted_client_id INTEGER,consultant_id INTEGER);
      CREATE TABLE tasks(id INTEGER PRIMARY KEY,client_id INTEGER,lead_id INTEGER,assigned_to_id INTEGER,status TEXT,due_date TEXT);
      CREATE INDEX tasks_client_due ON tasks(client_id,due_date,id);
      CREATE INDEX tasks_lead ON tasks(lead_id);
      CREATE TABLE request_context(id INTEGER PRIMARY KEY,assigned_only TEXT,role TEXT,actor_id INTEGER);
      INSERT INTO request_context VALUES(1,'false','admin',1);
    ''')
    db.executemany('INSERT INTO clients VALUES (?,NULL,1)', ((i,) for i in range(1,10001)))
    db.executemany("INSERT INTO tasks VALUES (?,?,NULL,?,'Pending','2026-10-01')",
                   ((i, (i-1)//10+1, 1 if i % 2 else 2) for i in range(1,100001)))
    old = 'SELECT t.id FROM tasks t WHERE t.client_id=? AND t.id IN (' + old_visibility + ') ORDER BY t.due_date NULLS LAST,t.id LIMIT 50'
    new = 'SELECT t.id FROM tasks t WHERE t.client_id=? AND ' + visibility + ' ORDER BY t.due_date NULLS LAST,t.id LIMIT 50'
    for scope, role in [('false','admin'),('false','consultant'),('true','consultant')]:
        db.execute('UPDATE request_context SET assigned_only=?,role=?',(scope,role))
        assert db.execute(old,(5000,)).fetchall() == db.execute(new,(5000,)).fetchall()
    db.execute("UPDATE request_context SET assigned_only='false',role='admin'")
    before, after = median_ms(db,old,(5000,)),median_ms(db,new,(5000,))
    plan = str(db.execute('EXPLAIN QUERY PLAN '+new,(5000,)).fetchall())
    assert 'SEARCH t USING INDEX tasks_client_due (client_id=?)' in plan, plan
    assert 'LIST SUBQUERY' not in plan, plan
    print(f'100,000 tasks: client task panel {before:.3f} -> {after:.3f} ms; scoped results identical')
    profile_old = old.replace('ORDER BY t.due_date NULLS LAST,t.id LIMIT 50', "AND t.status<>'Done' ORDER BY t.due_date NULLS LAST,t.id DESC LIMIT 1")
    profile_new = new.replace('ORDER BY t.due_date NULLS LAST,t.id LIMIT 50', "AND t.status<>'Done' ORDER BY t.due_date NULLS LAST,t.id DESC LIMIT 1")
    assert db.execute(profile_old,(5000,)).fetchall()==db.execute(profile_new,(5000,)).fetchall()
    print(f'100,000 tasks: client next step {median_ms(db,profile_old,(5000,)):.3f} -> {median_ms(db,profile_new,(5000,)):.3f} ms')
