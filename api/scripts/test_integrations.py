"""Provider protocol and durable reconciliation tests. No real provider calls."""
import json
import os
from pathlib import Path
import sqlite3
import tempfile
import unittest
from unittest.mock import patch
import integration_worker as worker
import database

ROOT = Path(__file__).resolve().parents[1]


class Fixture:
    def __init__(self, responses):
        self.responses = list(responses)
        self.calls = []

    def request(self, method, url, **kwargs):
        self.calls.append((method,url,kwargs))
        if not self.responses: raise AssertionError('Unexpected HTTP request: '+method+' '+url)
        response = self.responses.pop(0)
        if isinstance(response,Exception): raise response
        return response


class ProviderTests(unittest.TestCase):
    def setUp(self):
        self.env = patch.dict(os.environ, {'INTEGRATION_NAMESPACE':'ecc-test-instance-123456','PUBLIC_URL':'https://crm.example.test','ZOOM_HOST_USER':'host@example.test','ZOOM_CLIENT_ID':'test-id','ZOOM_CLIENT_SECRET':'test-secret','ZOOM_ACCOUNT_ID':'test-account','GOOGLE_CALENDAR_ID':'calendar@example.test','GOOGLE_CLIENT_ID':'test-id','GOOGLE_CLIENT_SECRET':'test-secret','GOOGLE_REFRESH_TOKEN':'test-refresh','STRIPE_SECRET_KEY':'sk_test_fixture','DOCUSIGN_ACCOUNT_ID':'test-account','DOCUSIGN_BASE_URL':'https://demo.docusign.net/restapi'})
        self.env.start()
        self.addCleanup(self.env.stop)
        url = os.environ.get('ECC_INTEGRATION_TEST_DATABASE_URL')
        if url:
            import psycopg
            import secrets
            raw = psycopg.connect(url)
            schema = 'ecc_provider_' + secrets.token_hex(12)
            raw.execute('CREATE SCHEMA '+schema)
            raw.execute('SET search_path='+schema+',public')
            raw.execute("SET TIME ZONE 'UTC'")
            for file in sorted((ROOT/'migrations/postgresql').glob('*.sql')): raw.execute(file.read_text())
            raw.commit()
            self.conn = database.PostgresConnection(raw)
            def cleanup():
                raw.rollback()
                raw.execute('SET search_path=public')
                raw.execute('DROP SCHEMA '+schema+' CASCADE')
                raw.commit()
                raw.close()
            self.addCleanup(cleanup)
        else:
            self.conn = sqlite3.connect(':memory:')
            self.conn.create_function('business_offset',0,lambda:'480 minutes')
            self.conn.execute('PRAGMA foreign_keys=ON')
            for file in sorted((ROOT/'migrations').glob('*.sql')): self.conn.executescript(file.read_text())
        self.conn.execute("INSERT INTO users(id,email,password_hash,name,role) VALUES (1,'staff@example.test','unused','Flor','admin')")
        self.conn.execute("INSERT INTO clients(id,client_number,full_name,email,case_officer_id) VALUES (1,'ECC-1','Maria Santos','maria@example.test',1)")
        self.conn.execute("INSERT INTO cases(id,client_id,service_category,destination,stage) VALUES (1,1,'Student Visa','Canada','New Client')")
        self.conn.execute("INSERT INTO appointments(id,client_id,case_id,owner_id,title,starts_at,ends_at,status) VALUES (1,1,1,1,'Consultation','2099-01-01 10:00:00','2099-01-01 11:00:00','Scheduled')")
        self.conn.execute("INSERT INTO invoices(id,client_id,case_id,description,currency,amount_minor,due_date) VALUES (1,1,1,'Consulting','PHP',2500000,'2099-12-31')")
        self.conn.execute("UPDATE invoices SET status='Issued' WHERE id=1")
        self.conn.execute("INSERT INTO commercial_documents(id,client_id,case_id,kind,title,body,currency,total_minor,valid_until,status,created_by) VALUES (1,1,1,'contract','Agreement','<script>private terms</script>','PHP',2500000,'2099-12-31','Issued',1)")
        self.conn.commit()
        if not url: self.addCleanup(self.conn.close)

    def job(self, provider, kind='appointment', revision=None):
        table = {'appointment':'appointments','invoice':'invoices','contract':'commercial_documents'}[kind]
        rev = revision or self.conn.execute('SELECT revision FROM '+table+' WHERE id=1').fetchone()[0]
        ident = self.conn.execute('INSERT INTO integration_jobs(provider,record_kind,record_id,source_revision,client_id,case_id,actor_id) VALUES (?,?,1,?,1,1,1) RETURNING id',(provider,kind,rev)).fetchone()[0]
        self.conn.commit()
        return ident

    def provider(self, responses):
        fixture = Fixture(responses)
        provider = worker.Providers(fixture)
        import time
        provider.tokens['docusign'] = ('test-token',time.time()+3600)
        return provider,fixture

    def link(self, provider, kind, remote, status, **extras):
        jid = self.job(provider,kind)
        self.conn.execute("UPDATE integration_jobs SET status='Succeeded' WHERE id=?",(jid,))
        rev = self.conn.execute('SELECT source_revision FROM integration_jobs WHERE id=?',(jid,)).fetchone()[0]
        lid = self.conn.execute('INSERT INTO integration_links(job_id,provider,record_kind,record_id,client_id,case_id,remote_id,status,source_revision,amount_minor,currency,remote_etag) VALUES (?,?,?,1,1,1,?,?,?,?,?,?) RETURNING id',(jid,provider,kind,remote,status,rev,extras.get('amount_minor'),extras.get('currency'),extras.get('remote_etag'))).fetchone()[0]
        self.conn.commit()
        return worker.row(self.conn,'SELECT * FROM integration_links WHERE id=?',(lid,))

    def paid(self, link, **changes):
        result = {'id':link['remote_id'],'payment_status':'paid','payment_intent':'pi_fixture','amount_total':2500000,'currency':'php','metadata':{'ecc_namespace':worker.namespace(),'ecc_invoice':'1','ecc_job':str(link['job_id'])}}
        result.update(changes)
        return result

    def test_zoom_uses_oauth_and_only_join_link_is_stored(self):
        self.job('zoom')
        provider,fixture = self.provider([{'access_token':'zoom-token','expires_in':3600},{'id':123,'join_url':'https://zoom.us/j/123','start_url':'https://zoom.us/secret-host-url','password':'1234'}])
        self.assertTrue(worker.run_job(self.conn,provider))
        self.assertIn('account_credentials', fixture.calls[0][2]['form'].values())
        self.assertEqual(fixture.calls[1][2]['payload']['duration'],60)
        self.assertEqual(self.conn.execute('SELECT meeting_url,meeting_id,client_visible FROM appointments').fetchone(),('https://zoom.us/j/123','123',0))
        self.assertNotIn('secret-host-url', str(self.conn.execute('SELECT * FROM integration_links').fetchall()))

    def test_zoom_unknown_create_is_not_blindly_retried(self):
        self.job('zoom')
        provider,fixture = self.provider([{'access_token':'z'},worker.ProviderError('timeout',uncertain=True)])
        worker.run_job(self.conn,provider)
        self.assertEqual(self.conn.execute('SELECT status FROM integration_jobs').fetchone()[0],'Review')
        self.assertFalse(worker.run_job(self.conn,provider))
        self.conn.execute("UPDATE integration_jobs SET status='Queued',next_attempt_at=NULL")
        self.conn.commit()
        provider,fixture = self.provider([{'access_token':'z'},{'meetings':[]}])
        worker.run_job(self.conn,provider)
        self.assertEqual([call[0] for call in fixture.calls],['POST','GET'])
        self.assertEqual(self.conn.execute('SELECT status FROM integration_jobs').fetchone()[0],'Review')

    def test_stale_job_never_calls_provider(self):
        self.job('zoom',revision=999)
        provider,fixture = self.provider([])
        worker.run_job(self.conn,provider)
        self.assertEqual(fixture.calls,[])
        self.assertEqual(self.conn.execute('SELECT error_code FROM integration_jobs').fetchone()[0],'record_changed_before_dispatch')

    def test_google_uses_deterministic_event_and_private_fields(self):
        self.job('google')
        provider,fixture = self.provider([{'access_token':'g'},worker.ProviderError('notfound',status=404),{'etag':'etag-1'}])
        worker.run_job(self.conn,provider)
        payload = fixture.calls[-1][2]['payload']
        self.assertEqual(payload['visibility'],'private')
        self.assertEqual(len(payload['id']),64)
        self.assertEqual(payload['start']['dateTime'],'2099-01-01T10:00:00Z')
        self.assertNotIn('attendees',payload)
        self.assertNotIn('description',payload)

    def test_calendar_inbound_reschedule_preserves_local_conflicts(self):
        link = self.link('google','appointment','event-1','Active',remote_etag='old')
        remote = {'etag':'new','summary':'Rescheduled consultation','start':{'dateTime':'2099-01-02T14:00:00+08:00'},'end':{'dateTime':'2099-01-02T15:00:00+08:00'},'extendedProperties':{'private':{'eccNamespace':worker.namespace()}}}
        provider,_ = self.provider([{'access_token':'g'},remote])
        worker.reconcile_calendar(self.conn,provider,link)
        self.assertEqual(self.conn.execute('SELECT starts_at FROM appointments').fetchone()[0],'2099-01-02 06:00:00')
        self.conn.execute("UPDATE appointments SET title='Local edit',revision=revision+1")
        self.conn.commit()
        provider,_ = self.provider([{'access_token':'g'},dict(remote,summary='Remote edit')])
        worker.reconcile_calendar(self.conn,provider,link)
        self.assertEqual(self.conn.execute('SELECT title FROM appointments').fetchone()[0],'Local edit')

    def test_stripe_checkout_exact_minor_units_and_idempotency(self):
        self.job('stripe','invoice')
        provider,fixture = self.provider([{'id':'cs_fixture','url':'https://checkout.stripe.com/c/pay/test'}])
        worker.run_job(self.conn,provider)
        request = fixture.calls[0][2]
        self.assertEqual(request['form']['line_items[0][price_data][unit_amount]'],2500000)
        self.assertEqual(request['headers']['Idempotency-Key'],worker.namespace()+':checkout:1')
        self.assertIn('/portal?',request['form']['success_url'])
        self.assertEqual(self.conn.execute('SELECT count(*) FROM invoice_payments').fetchone()[0],0)

    def test_paid_checkout_posts_once_and_notifies(self):
        link = self.link('stripe','invoice','cs_fixture','Open',amount_minor=2500000,currency='PHP')
        provider,_ = self.provider([self.paid(link),self.paid(link)])
        worker.reconcile_checkout(self.conn,provider,link)
        worker.reconcile_checkout(self.conn,provider,link)
        self.assertEqual(self.conn.execute('SELECT count(*) FROM invoice_payments').fetchone()[0],1)
        self.assertEqual(self.conn.execute('SELECT status FROM invoices').fetchone()[0],'Paid')
        self.assertEqual(self.conn.execute('SELECT count(*) FROM integration_events').fetchone()[0],1)
        self.assertEqual(self.conn.execute("SELECT count(*) FROM work_history WHERE kind='payment.received' AND case_id=1").fetchone()[0],1)
        self.assertEqual(self.conn.execute("SELECT count(*) FROM notifications WHERE event_key='stripe-paid:cs_fixture'").fetchone()[0],1)

    def test_checkout_rejects_wrong_amount_currency_metadata_and_unpaid(self):
        link = self.link('stripe','invoice','cs_fixture','Open',amount_minor=2500000,currency='PHP')
        for changes in [{'amount_total':1},{'currency':'usd'},{'metadata':{'ecc_invoice':'2'}},{'id':'cs_other'}]:
            provider,_ = self.provider([self.paid(link,**changes)])
            with self.assertRaises(worker.ProviderError): worker.reconcile_checkout(self.conn,provider,link)
        provider,_ = self.provider([self.paid(link,payment_status='unpaid')])
        worker.reconcile_checkout(self.conn,provider,link)
        self.assertEqual(self.conn.execute('SELECT count(*) FROM invoice_payments').fetchone()[0],0)

    def test_concurrent_manual_payment_requires_review_instead_of_overpayment(self):
        link = self.link('stripe','invoice','cs_fixture','Open',amount_minor=2500000,currency='PHP')
        self.conn.execute("INSERT INTO invoice_payments(invoice_id,amount_minor,paid_on,method,actor_name) VALUES (1,100,date('now',business_offset()),'Cash','Flor')")
        self.conn.commit()
        provider,_ = self.provider([self.paid(link)])
        with self.assertRaises(worker.ProviderError): worker.reconcile_checkout(self.conn,provider,link)
        self.assertEqual(self.conn.execute('SELECT count(*) FROM invoice_payments').fetchone()[0],1)
        self.assertEqual(self.conn.execute('SELECT status FROM integration_links').fetchone()[0],'Open')

    def test_signature_sent_with_escaped_terms_and_fixed_transaction_identity(self):
        self.job('docusign','contract')
        provider,fixture = self.provider([{'envelopeId':'env_fixture'}])
        worker.run_job(self.conn,provider)
        body = fixture.calls[0][2]['payload']
        import base64
        document = base64.b64decode(body['documents'][0]['documentBase64']).decode()
        self.assertIn('&lt;script&gt;',document)
        self.assertNotIn('<script>',document)
        self.assertEqual(body['recipients']['signers'][0]['email'],'maria@example.test')
        self.assertEqual(len(body['transactionId']),64)
        self.assertEqual(self.conn.execute('SELECT status FROM commercial_documents').fetchone()[0],'Issued')

    def test_signature_completion_retains_exact_pdf_and_scan_gate(self):
        link = self.link('docusign','contract','env_fixture','Sent')
        pdf = b'%PDF-1.4\nSigned bytes and certificate'
        provider,_ = self.provider([{'envelopeId':'env_fixture','status':'completed'},pdf])
        worker.reconcile_signature(self.conn,provider,link)
        self.assertEqual(self.conn.execute('SELECT status FROM commercial_documents').fetchone()[0],'Accepted')
        self.assertEqual(self.conn.execute('SELECT content,scan_status FROM documents').fetchone(),(pdf,'Pending'))
        self.assertEqual(self.conn.execute('SELECT status,signed_document_id FROM integration_links').fetchone(),('Completed',1))
        provider,_ = self.provider([{'envelopeId':'env_fixture','status':'completed'},pdf])
        worker.reconcile_signature(self.conn,provider,link)
        self.assertEqual(self.conn.execute('SELECT count(*) FROM documents').fetchone()[0],1)

    def test_lease_loss_cannot_publish_provider_result(self):
        self.job('zoom')
        job = worker.claim(self.conn)
        self.conn.execute("UPDATE integration_jobs SET lease_token='replacement'")
        self.conn.commit()
        with self.assertRaises(worker.ProviderError): worker.finish(self.conn,job,{'remote_id':'123','url':'https://zoom.us/j/123','status':'Active'})
        self.assertEqual(self.conn.execute('SELECT count(*) FROM integration_links').fetchone()[0],0)

    def test_signature_status_is_not_polled_more_often_than_provider_limit(self):
        self.link('docusign','contract','env_fixture','Sent')
        provider,fixture = self.provider([{'envelopeId':'env_fixture','status':'sent'}])
        worker.reconcile(self.conn,provider)
        worker.reconcile(self.conn,provider)
        self.assertEqual(len(fixture.calls),1)

    def test_changed_invoice_expires_old_checkout_without_posting_payment(self):
        link = self.link('stripe','invoice','cs_fixture','Open',amount_minor=2500000,currency='PHP')
        self.conn.execute("INSERT INTO invoice_payments(invoice_id,amount_minor,paid_on,method,actor_name) VALUES (1,100,date('now',business_offset()),'Cash','Flor')")
        self.conn.commit()
        provider,fixture = self.provider([self.paid(link,payment_status='unpaid',status='open'),{}])
        worker.reconcile_checkout(self.conn,provider,link)
        self.assertTrue(fixture.calls[-1][1].endswith('/expire'))
        self.assertEqual(self.conn.execute('SELECT status FROM integration_links').fetchone()[0],'Expired')
        self.assertEqual(self.conn.execute('SELECT count(*) FROM invoice_payments').fetchone()[0],1)

    def test_integration_events_are_immutable(self):
        link = self.link('stripe','invoice','cs_fixture','Open',amount_minor=2500000,currency='PHP')
        self.conn.execute("INSERT INTO integration_events(link_id,event_key,status) VALUES (?,'test-event','Paid')",(link['id'],))
        self.conn.commit()
        for statement in ["UPDATE integration_events SET status='No'","DELETE FROM integration_events"]:
            with self.assertRaises((sqlite3.IntegrityError,database.DatabaseError)): self.conn.execute(statement)
            self.conn.rollback()

    def test_no_credential_or_arbitrary_host_redirects(self):
        for url in ['http://api.stripe.com/v1','https://api.stripe.com@evil.test/','https://evil.test/']:
            with self.assertRaises(worker.ProviderError): worker.Transport().request('GET',url,headers={'Authorization':'Bearer private'})


if __name__ == '__main__': unittest.main()
