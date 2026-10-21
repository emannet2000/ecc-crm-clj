#!/usr/bin/env python3
"""Idempotent recurring tasks, deadline email and escalation scheduling."""
from contextlib import closing
import os
import sqlite3
import time


def run_once(conn):
    conn.execute('BEGIN IMMEDIATE')
    try:
        conn.execute("UPDATE request_context SET actor_id=NULL,role='system',assigned_only='false' WHERE id=1")
        # New tasks retain their own recurrence; unique parent prevents retries creating copies.
        recurring = conn.execute("SELECT t.id,t.lead_id,t.client_id,t.title,t.description,t.due_date,t.priority,t.assigned_to_id,t.recurrence_days,t.case_id FROM tasks t WHERE t.status='Done' AND t.recurrence_days IS NOT NULL AND t.due_date IS NOT NULL AND NOT EXISTS(SELECT 1 FROM tasks child WHERE child.recurrence_parent=t.id) AND (t.lead_id IN (SELECT id FROM leads WHERE deleted_at IS NULL AND converted_client_id IS NULL) OR t.client_id IN (SELECT id FROM clients WHERE deleted_at IS NULL))").fetchall()
        for tid, lead, client, title, description, due, priority, assigned, interval, case_id in recurring:
            row = conn.execute("INSERT OR IGNORE INTO tasks(lead_id,client_id,title,description,due_date,priority,assigned_to_id,recurrence_days,recurrence_parent,case_id) VALUES (?,?,?,?,date(CASE WHEN ?<date('now') THEN date('now') ELSE ? END,?),?,?,?,?,?) RETURNING id", (lead, client, title, description, due, due, '+' + str(interval) + ' days', priority, assigned, interval, tid, case_id)).fetchone()
            if row:
                conn.execute('INSERT INTO reminder_rules(task_id,days_before,escalate_after,enabled) SELECT ?,days_before,escalate_after,enabled FROM reminder_rules WHERE task_id=?', (row[0], tid))
                conn.execute("INSERT INTO work_history(lead_id,client_id,kind,note) VALUES (?,?,'recurring_task',?)", (lead, client, 'Next recurring task created: ' + title))
        tasks = conn.execute("SELECT t.id,t.title,t.due_date,t.assigned_to_id,r.escalate_after FROM tasks t JOIN reminder_rules r ON r.task_id=t.id WHERE r.enabled=1 AND t.status<>'Done' AND t.due_date IS NOT NULL AND t.due_date<=date('now','+'||r.days_before||' days') AND (t.lead_id IN (SELECT id FROM leads WHERE deleted_at IS NULL AND converted_client_id IS NULL) OR t.client_id IN (SELECT id FROM clients WHERE deleted_at IS NULL))").fetchall()
        for tid, title, due, assigned, escalation in tasks:
            recipients = []
            if assigned:
                recipients.extend((uid, email, 'reminder') for uid, email in conn.execute('SELECT u.id,u.email FROM users u LEFT JOIN notification_preferences p ON p.user_id=u.id WHERE u.id=? AND u.suspended=0 AND coalesce(p.email_enabled,1)=1 AND coalesce(p.deadlines,1)=1', (assigned,)))
            overdue = conn.execute("SELECT ?<=date('now',?)", (due, '-' + str(escalation) + ' days')).fetchone()[0]
            if overdue:
                recipients.extend((uid, email, 'escalation') for uid, email in conn.execute("SELECT u.id,u.email FROM users u LEFT JOIN notification_preferences p ON p.user_id=u.id WHERE u.role='admin' AND u.suspended=0 AND coalesce(p.email_enabled,1)=1 AND coalesce(p.escalations,1)=1"))
            for uid, email, kind in recipients:
                claimed = conn.execute('INSERT OR IGNORE INTO reminder_deliveries(task_id,due_date,kind,recipient_id) VALUES (?,?,?,?)', (tid, due, kind, uid)).rowcount
                if claimed:
                    subject = ('Overdue task: ' if kind == 'escalation' else 'Task reminder: ') + ' '.join(title.splitlines())
                    conn.execute('INSERT INTO mail_outbox(recipient,subject,body) VALUES (?,?,?)', (email, subject, title + '\nDue: ' + due + '\nOpen the workspace Tasks page to review or complete this task.'))
        conn.execute("INSERT OR IGNORE INTO notifications(user_id,kind,title,lead_id,client_id,case_id,event_key) SELECT t.assigned_to_id,'deadlines','Task due: '||t.title,t.lead_id,t.client_id,t.case_id,'task:'||t.id||':due:'||t.due_date FROM tasks t WHERE t.assigned_to_id IS NOT NULL AND t.status<>'Done' AND t.due_date<=date('now','+7 days') AND (t.client_id IN (SELECT id FROM clients WHERE deleted_at IS NULL) OR t.lead_id IN (SELECT id FROM leads WHERE deleted_at IS NULL AND converted_client_id IS NULL))")
        conn.execute("INSERT OR IGNORE INTO notifications(user_id,kind,title,lead_id,client_id,case_id,event_key) SELECT u.id,'escalations','Overdue task: '||t.title,t.lead_id,t.client_id,t.case_id,'task:'||t.id||':escalation:'||t.due_date FROM tasks t JOIN reminder_rules r ON r.task_id=t.id JOIN users u ON u.role='admin' AND u.suspended=0 WHERE r.enabled=1 AND t.status<>'Done' AND t.due_date<=date('now','-'||r.escalate_after||' days') AND (t.client_id IN (SELECT id FROM clients WHERE deleted_at IS NULL) OR t.lead_id IN (SELECT id FROM leads WHERE deleted_at IS NULL AND converted_client_id IS NULL))")
        conn.execute("INSERT OR IGNORE INTO notifications(user_id,kind,title,client_id,case_id,event_key) SELECT cl.case_officer_id,'deadlines','Case deadline: '||coalesce(c.service_category,'Case'),cl.id,c.id,'case:'||c.id||':deadline:'||c.next_deadline FROM cases c JOIN clients cl ON cl.id=c.client_id WHERE cl.deleted_at IS NULL AND cl.case_officer_id IS NOT NULL AND c.stage NOT IN ('Approved','Rejected','Completed') AND c.next_deadline<=date('now','+7 days')")
        conn.execute("INSERT OR IGNORE INTO notifications(user_id,kind,title,lead_id,client_id,case_id,event_key) SELECT coalesce(cl.case_officer_id,l.consultant_id),'documents','Document expiry: '||d.title,d.lead_id,d.client_id,d.case_id,'document:'||d.id||':expiry:'||d.expires_on FROM document_requests d LEFT JOIN clients cl ON cl.id=d.client_id LEFT JOIN leads l ON l.id=d.lead_id WHERE d.expires_on<=date('now','+30 days') AND coalesce(cl.case_officer_id,l.consultant_id) IS NOT NULL AND (d.client_id IN (SELECT id FROM clients WHERE deleted_at IS NULL) OR d.lead_id IN (SELECT id FROM leads WHERE deleted_at IS NULL AND converted_client_id IS NULL))")
        conn.execute("INSERT INTO workload_snapshots(day,user_id,staff_name,open_tasks,overdue_tasks,open_cases) SELECT date('now'),u.id,u.name,(SELECT count(*) FROM tasks t WHERE t.assigned_to_id=u.id AND t.status<>'Done' AND (t.client_id IN (SELECT id FROM clients WHERE deleted_at IS NULL) OR t.lead_id IN (SELECT id FROM leads WHERE deleted_at IS NULL AND converted_client_id IS NULL))),(SELECT count(*) FROM tasks t WHERE t.assigned_to_id=u.id AND t.status<>'Done' AND t.due_date<date('now') AND (t.client_id IN (SELECT id FROM clients WHERE deleted_at IS NULL) OR t.lead_id IN (SELECT id FROM leads WHERE deleted_at IS NULL AND converted_client_id IS NULL))),(SELECT count(*) FROM cases c JOIN clients cl ON cl.id=c.client_id WHERE cl.case_officer_id=u.id AND cl.deleted_at IS NULL AND c.stage NOT IN ('Approved','Rejected','Completed')) FROM users u WHERE u.role<>'viewer' ON CONFLICT(day,user_id) DO UPDATE SET staff_name=excluded.staff_name,open_tasks=excluded.open_tasks,overdue_tasks=excluded.overdue_tasks,open_cases=excluded.open_cases")
        conn.execute("UPDATE request_context SET actor_id=NULL,role=NULL,assigned_only='false' WHERE id=1")
        conn.execute("DELETE FROM portal_sessions WHERE expires_at<datetime('now')")
        conn.commit()
    except BaseException:
        conn.rollback()
        raise


def main():
    while True:
        try:
            with closing(sqlite3.connect(os.environ['DATABASE_PATH'], timeout=10)) as conn:
                conn.execute('PRAGMA foreign_keys=ON')
                run_once(conn)
        except (sqlite3.Error, OSError) as exc:
            print('scheduler retry:', type(exc).__name__, flush=True)
        time.sleep(15)


if __name__ == '__main__':
    main()
