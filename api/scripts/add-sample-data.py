"""Add repeatable fictional CRM examples without changing any login credentials."""
import datetime as dt
import os
import sqlite3

conn = sqlite3.connect(os.environ.get('DATABASE_PATH', 'ecc-crm.sqlite3'))
conn.execute('PRAGMA foreign_keys=ON')
today = dt.date.today()
year = today.year
def day(offset):
    return (today + dt.timedelta(days=offset)).isoformat()

with conn:
    owner = conn.execute('SELECT id FROM users WHERE email=?', ('demo@northwind.dev',)).fetchone()
    if not owner:
        raise SystemExit('Create demo@northwind.dev before adding sample data.')
    uid = owner[0]
    samples = [
        ('Maria Santos', 'Canada', 'Student Visa', 'Website', 'Hot', 'Qualified', -2),
        ('Ahmed Faris', 'Australia', 'Work Visa', 'Referral', 'Warm', 'Consultation Booked', 1),
        ('Grace Villanueva', 'New Zealand', 'Student Visa', 'School Partner', 'Hot', 'Proposal Sent', -1),
        ('Youssef Nabil', 'UK', 'Immigration Consultation', 'WhatsApp', 'Cold', 'New Lead', 5),
        ('Liza Fernandez', 'Canada', 'Work Visa', 'Facebook', 'Warm', 'Contacted', 2),
        ('Karim Haddad', 'Canada', 'Student Visa', 'Referral', 'Hot', 'Initial Assessment', 3),
    ]
    for i, (name, destination, service, source, quality, stage, due) in enumerate(samples, 1):
        email = f'sample.lead{i}@example.com'
        existing = conn.execute('SELECT id FROM leads WHERE email=?', (email,)).fetchone()
        if existing:
            continue
        counter = conn.execute("SELECT coalesce(max(CAST(substr(lead_number,8) AS INTEGER)),0)+1 FROM leads WHERE lead_number LIKE ?", (f'L-{year}-%',)).fetchone()[0]
        lid = conn.execute('INSERT INTO leads(lead_number,full_name,email,source,consultant_id,quality,stage,destination,service,notes,last_contact,next_followup) VALUES(?,?,?,?,?,?,?,?,?,?,?,?)',
            (f'L-{year}-{counter:04}', name,email,source,uid,quality,stage,destination,service,'Fictional sample record for exploring the CRM.',day(-i),day(due))).lastrowid
        conn.execute('INSERT INTO tasks(lead_id,title,due_date,priority,status,assigned_to_id) VALUES(?,?,?,?,?,?)',
            (lid, f'Follow up with {name}',day(due),'High' if quality=='Hot' else 'Medium','In Progress' if i==2 else 'Pending',uid))
        conn.execute('INSERT INTO activities(lead_id,type,description,date) VALUES(?,?,?,?)',
            (lid,'note','Sample inquiry received; review eligibility and confirm next steps.',day(-i)))
    for i, (name, destination, service, stage) in enumerate([
        ('Rosa Dimaculangan','Canada','Student Visa','Documents Under Review'),
        ('Fahad Otaibi','Australia','Work Visa','Decision Pending'),
    ],1):
        email=f'sample.client{i}@example.com'
        if conn.execute('SELECT 1 FROM clients WHERE email=?',(email,)).fetchone():
            continue
        counter=conn.execute("SELECT coalesce(max(CAST(substr(client_number,10) AS INTEGER)),0)+1 FROM clients WHERE client_number LIKE ?",(f'ECC-{year}-%',)).fetchone()[0]
        cid=conn.execute('INSERT INTO clients(client_number,full_name,email,case_officer_id) VALUES(?,?,?,?)',(f'ECC-{year}-{counter:05}',name,email,uid)).lastrowid
        conn.execute('INSERT INTO cases(client_id,service_category,destination,stage,next_deadline) VALUES(?,?,?,?,?)',(cid,service,destination,stage,day(-3 if i==1 else 9)))
    for prefix, table, column, offset in [('L','leads','lead_number',8),('ECC','clients','client_number',10)]:
        value=conn.execute(f'SELECT coalesce(max(CAST(substr({column},{offset}) AS INTEGER)),0) FROM {table} WHERE {column} LIKE ?',(f'{prefix}-{year}-%',)).fetchone()[0]
        conn.execute('INSERT INTO reference_counters(prefix,year,value) VALUES(?,?,?) ON CONFLICT(prefix,year) DO UPDATE SET value=max(reference_counters.value,excluded.value)',(prefix,year,value))
    if conn.execute("SELECT 1 FROM sqlite_master WHERE type='table' AND name='checklist_templates'").fetchone():
        for template_name, category, required, optional in [
            ('Sample student application checklist', 'Student Visa', ['Passport', 'Academic records'], ['Supporting letter']),
            ('Sample school admission checklist', 'School Admission', ['Application form', 'Academic records'], ['Personal statement']),
        ]:
            conn.execute('INSERT OR IGNORE INTO checklist_templates(name,category,destination) VALUES(?,?,?)', (template_name, category, ''))
            template_id=conn.execute('SELECT id FROM checklist_templates WHERE name=? AND category=? AND destination=?', (template_name,category,'')).fetchone()[0]
            for title, mandatory in [(title,1) for title in required]+[(title,0) for title in optional]:
                conn.execute('INSERT OR IGNORE INTO checklist_template_items(template_id,title,required) VALUES(?,?,?)',(template_id,title,mandatory))
        sample_client=conn.execute("SELECT id FROM clients WHERE email='sample.client2@example.com'").fetchone()
        if sample_client and not conn.execute("SELECT 1 FROM cases WHERE client_id=? AND service_category='School Admission' AND destination='UK'",sample_client).fetchone():
            conn.execute('INSERT INTO cases(client_id,service_category,destination,stage,next_deadline,intake_date) VALUES(?,?,?,?,?,?)',(sample_client[0],'School Admission','UK','Submitted',day(4),day(180)))
        sample_client=conn.execute("SELECT id FROM clients WHERE email='sample.client1@example.com'").fetchone()
        if sample_client and not conn.execute("SELECT 1 FROM tasks WHERE client_id=? AND title='Confirm application intake'",sample_client).fetchone():
            conn.execute('INSERT INTO tasks(client_id,title,due_date,priority,status,assigned_to_id) VALUES(?,?,?,?,?,?)',(sample_client[0],'Confirm application intake',day(2),'High','Pending',uid))
    violations=conn.execute('PRAGMA foreign_key_check').fetchall()
    if violations:
        raise RuntimeError(violations)
for table in ('users','leads','clients','cases','tasks','activities'):
    print(table, conn.execute(f'SELECT count(*) FROM {table}').fetchone()[0])
conn.close()
