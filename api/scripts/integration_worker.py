#!/usr/bin/env python3
"""Durable provider operations. Network calls never run in a database transaction.
Provider status is fetched using server credentials; browser redirects cannot post
payments or signatures. Public webhook endpoints are deliberately unnecessary.
"""
import base64
from contextlib import contextmanager, closing
from datetime import datetime, timezone
import hashlib
import json
import math
import os
from pathlib import Path
import secrets
import sqlite3
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
import database


class ProviderError(RuntimeError):
    def __init__(self, code, uncertain=False, status=None):
        super().__init__(code)
        self.code, self.uncertain, self.status = code, uncertain, status


def required(name):
    value = os.environ.get(name, '').strip()
    if not value:
        raise ProviderError('configuration_missing_' + name.lower())
    return value


def public_origin():
    value = required('PUBLIC_URL').rstrip('/')
    parts = urllib.parse.urlsplit(value)
    if parts.scheme != 'https' or not parts.hostname or parts.username or parts.password or parts.query or parts.fragment or parts.path:
        raise ProviderError('configuration_public_url')
    return value


def namespace():
    value = required('INTEGRATION_NAMESPACE')
    if len(value) < 16 or len(value) > 64 or not all(c.isalnum() or c in '-_' for c in value):
        raise ProviderError('configuration_namespace')
    return value


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        return None


class Transport:
    def request(self, method, url, headers=None, payload=None, form=None, binary=False):
        parts = urllib.parse.urlsplit(url)
        if parts.scheme != 'https' or parts.username or parts.password:
            raise ProviderError('unsafe_provider_url')
        allowed = ('zoom.us', 'api.zoom.us', 'oauth2.googleapis.com', 'www.googleapis.com', 'api.stripe.com', 'account.docusign.com', 'account-d.docusign.com')
        if parts.hostname not in allowed and not (parts.hostname or '').endswith('.docusign.net'):
            raise ProviderError('unsafe_provider_host')
        headers = dict(headers or {})
        data = None
        if payload is not None:
            headers['Content-Type'] = 'application/json'
            data = json.dumps(payload).encode()
        if form is not None:
            headers['Content-Type'] = 'application/x-www-form-urlencoded'
            data = urllib.parse.urlencode(form).encode()
        request = urllib.request.Request(url, data=data, headers=headers, method=method)
        try:
            with urllib.request.build_opener(NoRedirect).open(request, timeout=25) as response:
                limit = 25*1024*1024 if binary else 2*1024*1024
                raw = response.read(limit+1)
                if len(raw) > limit:
                    raise ProviderError('provider_response_too_large', uncertain=method == 'POST')
                if binary:
                    if not raw.startswith(b'%PDF-'):
                        raise ProviderError('invalid_signed_pdf')
                    return raw
                return json.loads(raw) if raw else {}
        except urllib.error.HTTPError as exc:
            raise ProviderError('provider_http_' + str(exc.code), uncertain=exc.code >= 500 and method == 'POST', status=exc.code) from None
        except (OSError, ValueError) as exc:
            raise ProviderError('provider_transport_' + type(exc).__name__.lower(), uncertain=method == 'POST') from None


class Providers:
    def __init__(self, transport=None):
        self.http = transport or Transport()
        self.tokens = {}

    def token(self, provider):
        cached = self.tokens.get(provider)
        if cached and cached[1] > time.time()+60:
            return cached[0]
        if provider == 'zoom':
            auth = base64.b64encode((required('ZOOM_CLIENT_ID')+':'+required('ZOOM_CLIENT_SECRET')).encode()).decode()
            response = self.http.request('POST', 'https://zoom.us/oauth/token', headers={'Authorization': 'Basic '+auth}, form={'grant_type': 'account_credentials', 'account_id': required('ZOOM_ACCOUNT_ID')})
        elif provider == 'google':
            response = self.http.request('POST', 'https://oauth2.googleapis.com/token', form={'grant_type': 'refresh_token', 'client_id': required('GOOGLE_CLIENT_ID'), 'client_secret': required('GOOGLE_CLIENT_SECRET'), 'refresh_token': required('GOOGLE_REFRESH_TOKEN')})
        elif provider == 'docusign':
            auth_host = os.environ.get('DOCUSIGN_AUTH_HOST', 'account-d.docusign.com')
            if auth_host not in ('account.docusign.com', 'account-d.docusign.com'):
                raise ProviderError('configuration_docusign_auth_host')
            refresh_file = Path(required('DOCUSIGN_REFRESH_TOKEN_FILE'))
            if refresh_file.is_symlink() or refresh_file.stat().st_mode & 0o077:
                raise ProviderError('configuration_docusign_token_permissions')
            auth = base64.b64encode((required('DOCUSIGN_CLIENT_ID')+':'+required('DOCUSIGN_CLIENT_SECRET')).encode()).decode()
            response = self.http.request('POST', 'https://'+auth_host+'/oauth/token', headers={'Authorization': 'Basic '+auth}, form={'grant_type': 'refresh_token', 'refresh_token': refresh_file.read_text().strip()})
            if response.get('refresh_token'):
                # Rotating tokens stay in the mounted secret file, never in CRM rows.
                fd, name = tempfile.mkstemp(prefix='.oauth-', dir=refresh_file.parent)
                try:
                    with os.fdopen(fd, 'w') as output:
                        output.write(response['refresh_token'])
                        output.flush()
                        os.fsync(output.fileno())
                    os.replace(name, refresh_file)
                finally:
                    if os.path.exists(name): os.unlink(name)
        else:
            return required('STRIPE_SECRET_KEY')
        token = response.get('access_token')
        if not token:
            raise ProviderError('provider_token_missing')
        self.tokens[provider] = (token, time.time()+int(response.get('expires_in', 300)))
        return token

    def api(self, provider, method, path, **kwargs):
        roots = {'zoom': 'https://api.zoom.us/v2', 'google': 'https://www.googleapis.com/calendar/v3', 'stripe': 'https://api.stripe.com/v1'}
        root = roots.get(provider)
        if provider == 'docusign':
            root = required('DOCUSIGN_BASE_URL').rstrip('/')
            parts = urllib.parse.urlsplit(root)
            if parts.scheme != 'https' or not (parts.hostname or '').endswith('.docusign.net') or parts.path != '/restapi' or parts.username or parts.password or parts.query or parts.fragment:
                raise ProviderError('configuration_docusign_base_url')
            root += '/v2.1/accounts/'+urllib.parse.quote(required('DOCUSIGN_ACCOUNT_ID'), safe='')
        headers = kwargs.pop('headers', {})
        headers['Authorization'] = 'Bearer '+self.token(provider)
        return self.http.request(method, root+path, headers=headers, **kwargs)

    def zoom(self, job, record, link):
        start, end = parse_time(record['starts_at']), parse_time(record['ends_at'])
        body = {'topic': record['title'], 'type': 2, 'start_time': start.strftime('%Y-%m-%dT%H:%M:%SZ'), 'timezone': 'UTC', 'duration': max(1, math.ceil((end-start).total_seconds()/60)), 'settings': {'waiting_room': True, 'join_before_host': False}}
        if link:
            remote = urllib.parse.quote(link['remote_id'], safe='')
            if record['status'] == 'Cancelled':
                try: self.api('zoom', 'DELETE', '/meetings/'+remote)
                except ProviderError as exc:
                    if exc.status != 404: raise
                return dict(link, status='Cancelled')
            self.api('zoom', 'PATCH', '/meetings/'+remote, payload=body)
            result = self.api('zoom', 'GET', '/meetings/'+remote)
        else:
            if record['meeting_url']:
                raise ProviderError('existing_manual_meeting')
            marker = hashlib.sha256((namespace()+':zoom:'+str(job['id'])).encode()).hexdigest()[:24]
            body['topic'] += ' [ECC-'+marker+']'
            # A create timeout has an unknown outcome. Search before recovering;
            # never issue a second create when the first result is uncertain.
            if job['attempts'] > 1:
                host = urllib.parse.quote(required('ZOOM_HOST_USER'), safe='')
                page = ''
                result = None
                for _ in range(20):
                    batch = self.api('zoom', 'GET', '/users/'+host+'/meetings?type=scheduled&page_size=300&next_page_token='+urllib.parse.quote(page, safe=''))
                    match = next((item for item in batch.get('meetings', []) if marker in item.get('topic', '')), None)
                    if match:
                        result = self.api('zoom', 'GET', '/meetings/'+str(match['id']))
                        break
                    page = batch.get('next_page_token', '')
                    if not page: break
                if result is None: raise ProviderError('zoom_create_outcome_unknown', uncertain=True)
            else:
                host = urllib.parse.quote(required('ZOOM_HOST_USER'), safe='')
                result = self.api('zoom', 'POST', '/users/'+host+'/meetings', payload=body)
        url = result.get('join_url', '')
        if not url.startswith('https://') or not result.get('id'):
            raise ProviderError('invalid_zoom_response', uncertain=True)
        return {'remote_id': str(result['id']), 'url': url, 'status': 'Active', 'passcode': str(result.get('password', ''))}

    def google(self, job, record, link):
        calendar = urllib.parse.quote(required('GOOGLE_CALENDAR_ID'), safe='')
        remote = link['remote_id'] if link else hashlib.sha256((namespace()+':appointment:'+str(record['id'])).encode()).hexdigest()
        path = '/calendars/'+calendar+'/events/'+remote
        if record['status'] == 'Cancelled':
            try: self.api('google', 'DELETE', path)
            except ProviderError as exc:
                if exc.status not in (404, 410): raise
            return {'remote_id': remote, 'url': '', 'status': 'Cancelled'}
        # Only meeting fields are shared with the staff calendar, never internal
        # CRM notes, financial information or unrelated client fields.
        body = {'summary': record['title'], 'start': {'dateTime': iso(record['starts_at'])}, 'end': {'dateTime': iso(record['ends_at'])}, 'location': record.get('meeting_url') or record.get('location', ''), 'visibility': 'private', 'extendedProperties': {'private': {'eccNamespace': namespace(), 'eccAppointment': str(record['id'])}}}
        try:
            existing = self.api('google', 'GET', path)
        except ProviderError as exc:
            if exc.status not in (404, 410): raise
            existing = None
        if existing:
            if existing.get('extendedProperties', {}).get('private', {}).get('eccNamespace') != namespace():
                raise ProviderError('calendar_namespace_mismatch')
            response = self.api('google', 'PATCH', path, payload=body, headers={'If-Match': existing['etag']})
        else:
            response = self.api('google', 'POST', '/calendars/'+calendar+'/events', payload=dict(body, id=remote))
        return {'remote_id': remote, 'url': '', 'status': 'Active', 'remote_etag': response.get('etag', '')}

    def stripe(self, job, record, link):
        if record['status'] != 'Issued' or record['balance_minor'] <= 0:
            raise ProviderError('invoice_not_payable')
        amount = record['balance_minor']
        key = namespace()+':checkout:'+str(job['id'])
        # Never reuse an idempotency key after Stripe's retention window.
        if job['attempts'] > 1 and (datetime.now(timezone.utc)-parse_time(job['created_at'])).total_seconds() > 23*3600:
            raise ProviderError('checkout_outcome_requires_review', uncertain=True)
        body = {'mode': 'payment', 'payment_method_types[0]': 'card', 'client_reference_id': str(record['id']), 'metadata[ecc_namespace]': namespace(), 'metadata[ecc_invoice]': str(record['id']), 'metadata[ecc_job]': str(job['id']), 'line_items[0][price_data][currency]': record['currency'].lower(), 'line_items[0][price_data][unit_amount]': amount, 'line_items[0][price_data][product_data][name]': 'ECC invoice INV-'+str(record['id']), 'line_items[0][quantity]': 1, 'success_url': public_origin()+'/portal?checkout=returned', 'cancel_url': public_origin()+'/portal?checkout=cancelled'}
        result = self.api('stripe', 'POST', '/checkout/sessions', form=body, headers={'Idempotency-Key': key})
        url = result.get('url', '')
        if urllib.parse.urlsplit(url).hostname != 'checkout.stripe.com' or not url.startswith('https://'):
            raise ProviderError('invalid_checkout_response', uncertain=True)
        return {'remote_id': result['id'], 'url': url, 'status': 'Open', 'amount_minor': amount, 'currency': record['currency']}

    def docusign(self, job, record, link):
        if record['status'] not in ('Issued', 'Viewed') or record['valid_until'] < datetime.now(timezone.utc).strftime('%Y-%m-%d'):
            raise ProviderError('contract_not_signable')
        if not record.get('email'):
            raise ProviderError('client_email_required')
        transaction = hashlib.sha256((namespace()+':contract:'+str(job['id'])).encode()).hexdigest()[:64]
        if job['attempts'] > 1:
            if (datetime.now(timezone.utc)-parse_time(job['created_at'])).total_seconds() > 6*86400:
                raise ProviderError('signature_outcome_requires_review', uncertain=True)
            prior = self.api('docusign', 'GET', '/envelopes?transaction_ids='+transaction)
            if prior.get('envelopes'):
                return {'remote_id': prior['envelopes'][0]['envelopeId'], 'url': '', 'status': 'Sent'}
        # HTML is a supported document input. Escape every client-supplied field.
        import html
        document = '<html><body><h1>'+html.escape(record['title'])+'</h1><p>Contract #'+str(record['id'])+'</p><pre>'+html.escape(record['body'])+'</pre><p>Total: '+html.escape(record['currency'])+' '+str(record['total_minor']//100)+'.'+str(record['total_minor']%100).zfill(2)+'</p><p>Valid until: '+html.escape(record['valid_until'])+'</p><p>Signature: /ecc_sign_here/</p></body></html>'
        body = {'emailSubject': 'ECC contract agreement', 'transactionId': transaction, 'status': 'sent', 'documents': [{'documentBase64': base64.b64encode(document.encode()).decode(), 'name': 'ECC contract agreement', 'fileExtension': 'html', 'documentId': '1'}], 'recipients': {'signers': [{'email': record['email'], 'name': record['full_name'], 'recipientId': '1', 'routingOrder': '1', 'tabs': {'signHereTabs': [{'anchorString': '/ecc_sign_here/', 'anchorUnits': 'pixels', 'anchorXOffset': '0', 'anchorYOffset': '0'}]}}]}}
        result = self.api('docusign', 'POST', '/envelopes', payload=body)
        if not result.get('envelopeId'): raise ProviderError('invalid_signature_response', uncertain=True)
        return {'remote_id': result['envelopeId'], 'url': '', 'status': 'Sent'}


def parse_time(value):
    result = datetime.fromisoformat(value.replace('Z', '+00:00'))
    return result.replace(tzinfo=timezone.utc) if result.tzinfo is None else result.astimezone(timezone.utc)


def iso(value):
    return parse_time(value).strftime('%Y-%m-%dT%H:%M:%SZ')


@contextmanager
def transaction(conn, actor=None):
    conn.execute('BEGIN IMMEDIATE')
    try:
        conn.execute("UPDATE request_context SET actor_id=?,role='system',assigned_only='false' WHERE id=1", (actor,))
        yield
        conn.execute("UPDATE request_context SET actor_id=NULL,role=NULL,assigned_only='false' WHERE id=1")
        conn.commit()
    except BaseException:
        conn.rollback()
        raise


def row(conn, sql, args=()):
    cursor = conn.execute(sql, args)
    result = cursor.fetchone()
    if result is None: return None
    names = [column[0] for column in cursor.description]
    return dict(zip(names, result))


def rows(conn, sql, args=()):
    cursor = conn.execute(sql, args)
    names = [column[0] for column in cursor.description]
    return [dict(zip(names, item)) for item in cursor.fetchall()]


def event(conn, client, app, kind, note, actor=None):
    conn.execute('INSERT INTO work_history(client_id,case_id,actor_id,kind,note) VALUES (?,?,?,?,?)', (client, app, actor, kind, note))


def notify(conn, client, app, title, key):
    conn.execute("INSERT INTO notifications(user_id,kind,title,client_id,case_id,event_key) SELECT case_officer_id,'documents',?,?,?,? FROM clients WHERE id=? AND case_officer_id IS NOT NULL ON CONFLICT(user_id,event_key) DO NOTHING", (title, client, app, key, client))


def claim(conn):
    with transaction(conn):
        job = row(conn, "SELECT * FROM integration_jobs WHERE (status='Queued' AND (next_attempt_at IS NULL OR next_attempt_at<=datetime('now'))) OR (status='Running' AND lease_until<datetime('now')) ORDER BY id LIMIT 1")
        if job is None: return None
        lease = secrets.token_urlsafe(24)
        conn.execute("UPDATE integration_jobs SET status='Running',attempts=attempts+1,lease_token=?,lease_until=datetime('now','+10 minutes'),updated_at=datetime('now') WHERE id=?", (lease, job['id']))
        job.update(lease_token=lease, attempts=job['attempts']+1)
        return job


def snapshot(conn, job):
    table = {'appointment': 'appointments', 'invoice': 'invoice_balances', 'contract': 'commercial_documents'}[job['record_kind']]
    result = row(conn, 'SELECT r.* FROM '+table+' r JOIN clients c ON c.id=r.client_id WHERE r.id=? AND r.client_id=? AND c.deleted_at IS NULL AND c.merged_into IS NULL', (job['record_id'], job['client_id']))
    if not result: raise ProviderError('record_unavailable')
    if result['revision'] != job['source_revision']: raise ProviderError('record_changed_before_dispatch')
    if job['provider'] == 'docusign':
        result.update(row(conn, 'SELECT full_name,email FROM clients WHERE id=?', (job['client_id'],)))
    link = row(conn, 'SELECT * FROM integration_links WHERE provider=? AND record_kind=? AND record_id=? ORDER BY id DESC LIMIT 1', (job['provider'], job['record_kind'], job['record_id']))
    # Release PostgreSQL's implicit read transaction before all network calls.
    conn.commit()
    return result, link


def finish(conn, job, result):
    with transaction(conn, job['actor_id']):
        owned = row(conn, "SELECT id FROM integration_jobs WHERE id=? AND lease_token=? AND status='Running'", (job['id'], job['lease_token']))
        if not owned: raise ProviderError('lease_lost')
        previous = row(conn, 'SELECT id FROM integration_links WHERE provider=? AND remote_id=?', (job['provider'], result['remote_id']))
        if previous:
            conn.execute("UPDATE integration_links SET status=?,source_revision=?,remote_etag=?,checked_at=datetime('now') WHERE id=?", (result['status'], job['source_revision'], result.get('remote_etag'), previous['id']))
        else:
            conn.execute('INSERT INTO integration_links(job_id,provider,record_kind,record_id,client_id,case_id,remote_id,url,status,source_revision,amount_minor,currency,remote_etag) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)', (job['id'],job['provider'],job['record_kind'],job['record_id'],job['client_id'],job['case_id'],result['remote_id'],result.get('url',''),result['status'],job['source_revision'],result.get('amount_minor'),result.get('currency'),result.get('remote_etag')))
        if job['provider'] == 'zoom' and result['status'] == 'Active':
            # Do not overwrite a concurrently edited appointment. Reconciliation
            # will send the latest revision on the next worker cycle.
            changed = conn.execute('UPDATE appointments SET meeting_url=?,meeting_id=?,passcode=?,revision=revision+1 WHERE id=? AND revision=?', (result['url'],result['remote_id'],result.get('passcode',''),job['record_id'],job['source_revision'])).rowcount
            if changed:
                conn.execute('UPDATE integration_links SET source_revision=? WHERE provider=? AND remote_id=?', (job['source_revision']+1,'zoom',result['remote_id']))
        conn.execute("UPDATE integration_jobs SET status='Succeeded',error_code=NULL,lease_token=NULL,lease_until=NULL,updated_at=datetime('now') WHERE id=?", (job['id'],))
        event(conn,job['client_id'],job['case_id'],'integration.completed',job['provider']+' connected to '+job['record_kind']+' #'+str(job['record_id']),job['actor_id'])
        notify(conn,job['client_id'],job['case_id'],job['provider']+' integration completed','integration-job:'+str(job['id']))


def fail_job(conn, job, error):
    # Never log response bodies, URLs, provider tokens or client data.
    unknown = error.uncertain
    retry = not unknown and error.status in (412, 429, 500, 502, 503, 504) and job['attempts'] < 5
    status = 'Review' if unknown else ('Queued' if retry else 'Failed')
    with transaction(conn):
        delay = '+16 minutes' if job['provider'] == 'docusign' else '+5 minutes'
        changed = conn.execute("UPDATE integration_jobs SET status=?,error_code=?,lease_token=NULL,lease_until=NULL,next_attempt_at=datetime('now',?),updated_at=datetime('now') WHERE id=? AND lease_token=?", (status,error.code,delay,job['id'],job['lease_token'])).rowcount
        if changed and status in ('Review','Failed'):
            notify(conn,job['client_id'],job['case_id'],'Integration needs attention: '+job['provider'],'integration-failed:'+str(job['id'])+':'+str(job['attempts']))
    return status


def run_job(conn, providers):
    job = claim(conn)
    if not job: return False
    try:
        if job['provider'] == 'docusign' and job['attempts'] > 1 and (datetime.now(timezone.utc)-parse_time(job['updated_at'])).total_seconds() < 16*60:
            raise ProviderError('signature_retry_throttled', status=429)
        record, link = snapshot(conn, job)
        result = getattr(providers, job['provider'])(job, record, link)
        finish(conn, job, result)
    except ProviderError as exc:
        conn.rollback()
        fail_job(conn, job, exc)
    return True


def queue_appointment_changes(conn):
    with transaction(conn):
        conn.execute("INSERT INTO integration_jobs(provider,record_kind,record_id,source_revision,client_id,case_id,actor_id) SELECT l.provider,'appointment',a.id,a.revision,a.client_id,a.case_id,NULL FROM integration_links l JOIN appointments a ON a.id=l.record_id JOIN clients c ON c.id=a.client_id WHERE l.record_kind='appointment' AND l.provider IN ('zoom','google') AND l.status='Active' AND a.status IN ('Scheduled','Cancelled') AND a.revision<>l.source_revision AND c.deleted_at IS NULL AND c.merged_into IS NULL AND NOT EXISTS(SELECT 1 FROM integration_jobs j WHERE j.provider=l.provider AND j.record_kind='appointment' AND j.record_id=a.id AND j.status IN ('Queued','Running','Review')) ON CONFLICT(provider,record_kind,record_id,source_revision) DO NOTHING")


def reconcile_checkout(conn, providers, link):
    response = providers.api('stripe','GET','/checkout/sessions/'+urllib.parse.quote(link['remote_id'],safe=''))
    if response.get('id') != link['remote_id']: raise ProviderError('checkout_identity_mismatch')
    meta = response.get('metadata',{})
    if meta.get('ecc_namespace') != namespace() or meta.get('ecc_invoice') != str(link['record_id']) or meta.get('ecc_job') != str(link['job_id']):
        raise ProviderError('checkout_metadata_mismatch')
    if response.get('payment_status') != 'paid':
        invoice = row(conn,'SELECT i.balance_minor,i.status,c.deleted_at FROM invoice_balances i JOIN clients c ON c.id=i.client_id WHERE i.id=?',(link['record_id'],))
        conn.commit()
        stale = not invoice or invoice['status'] != 'Issued' or invoice['balance_minor'] != link['amount_minor'] or invoice['deleted_at'] is not None
        if stale and response.get('status') == 'open':
            providers.api('stripe','POST','/checkout/sessions/'+urllib.parse.quote(link['remote_id'],safe='')+'/expire')
        if response.get('status') == 'expired' or stale:
            with transaction(conn):
                conn.execute("UPDATE integration_links SET status='Expired',checked_at=datetime('now') WHERE id=?",(link['id'],))
                conn.execute("UPDATE invoices SET revision=revision+1 WHERE id=? AND status='Issued'",(link['record_id'],))
        return
    if response.get('amount_total') != link['amount_minor'] or response.get('currency','').upper() != link['currency'] or not response.get('payment_intent'):
        raise ProviderError('checkout_amount_mismatch')
    with transaction(conn):
        current = row(conn,'SELECT payment_id FROM integration_links WHERE id=?',(link['id'],))
        if current['payment_id'] is not None: return
        invoice = row(conn,'SELECT * FROM invoice_balances WHERE id=?',(link['record_id'],))
        if invoice['client_id'] != link['client_id'] or invoice['status'] != 'Issued' or invoice['balance_minor'] < link['amount_minor']:
            raise ProviderError('paid_checkout_balance_conflict')
        # One unique integration event and receipt in the SAME transaction.
        conn.execute("INSERT INTO integration_events(link_id,event_key,status) VALUES (?,?,'Paid')",(link['id'],'stripe:'+link['remote_id']+':paid'))
        receipt = row(conn,"INSERT INTO invoice_payments(invoice_id,amount_minor,paid_on,method,reference,actor_name) VALUES (?,?,date('now',business_offset()),'Card',?,'Stripe') RETURNING id",(link['record_id'],link['amount_minor'],response['payment_intent']))
        conn.execute("UPDATE integration_links SET status='Paid',payment_id=?,checked_at=datetime('now') WHERE id=?",(receipt['id'],link['id']))
        event(conn,link['client_id'],link['case_id'],'payment.received','Stripe payment received for INV-'+str(link['record_id']))
        notify(conn,link['client_id'],link['case_id'],'Payment received for INV-'+str(link['record_id']),'stripe-paid:'+link['remote_id'])


def reconcile_signature(conn, providers, link):
    path = '/envelopes/'+urllib.parse.quote(link['remote_id'],safe='')
    result = providers.api('docusign','GET',path)
    if result.get('envelopeId') != link['remote_id']: raise ProviderError('signature_identity_mismatch')
    status = result.get('status')
    if status not in ('completed','declined','voided'): return
    pdf = providers.api('docusign','GET',path+'/documents/combined?certificate=true',binary=True) if status == 'completed' else None
    with transaction(conn):
        current = row(conn,'SELECT status FROM integration_links WHERE id=?',(link['id'],))
        if current['status'] != 'Sent': return
        terminal = {'completed':'Completed','declined':'Declined','voided':'Voided'}[status]
        conn.execute('INSERT INTO integration_events(link_id,event_key,status) VALUES (?,?,?)',(link['id'],'docusign:'+link['remote_id']+':'+status,terminal))
        document_id = None
        if status == 'completed':
            contract = row(conn,"SELECT status FROM commercial_documents WHERE id=? AND client_id=? AND kind='contract'",(link['record_id'],link['client_id']))
            if not contract or contract['status'] not in ('Issued','Viewed'):
                raise ProviderError('signature_contract_state_conflict')
            # Preserve exact provider-signed bytes with the completion certificate.
            # Existing scanner gates portal access; no approval is inferred from a PDF.
            content = pdf if isinstance(conn,sqlite3.Connection) else pdf
            doc = row(conn,'INSERT INTO documents(client_id,filename,mime_type,size,content) VALUES (?,?,?,?,?) RETURNING id',(link['client_id'],'signed-contract-'+str(link['record_id'])+'.pdf','application/pdf',len(pdf),content))
            document_id = doc['id']
            conn.execute("UPDATE commercial_documents SET status='Accepted',accepted_at=datetime('now'),revision=revision+1 WHERE id=?",(link['record_id'],))
        if status != 'completed':
            conn.execute('UPDATE commercial_documents SET revision=revision+1 WHERE id=?',(link['record_id'],))
        conn.execute("UPDATE integration_links SET status=?,signed_document_id=?,checked_at=datetime('now') WHERE id=?",(terminal,document_id,link['id']))
        event(conn,link['client_id'],link['case_id'],'contract.'+status,'DocuSign contract '+status+' #'+str(link['record_id']))
        notify(conn,link['client_id'],link['case_id'],'Contract '+status,'docusign:'+link['remote_id']+':'+status)


def reconcile_calendar(conn, providers, link):
    calendar = urllib.parse.quote(required('GOOGLE_CALENDAR_ID'),safe='')
    try:
        remote = providers.api('google','GET','/calendars/'+calendar+'/events/'+link['remote_id'])
    except ProviderError as exc:
        if exc.status not in (404,410): raise
        remote = {'status':'cancelled'}
    if remote.get('etag') and remote['etag'] == link.get('remote_etag'): return
    if remote.get('status') != 'cancelled' and remote.get('extendedProperties',{}).get('private',{}).get('eccNamespace') != namespace():
        raise ProviderError('calendar_namespace_mismatch')
    with transaction(conn):
        appointment = row(conn,'SELECT * FROM appointments WHERE id=?',(link['record_id'],))
        if not appointment or appointment['revision'] != link['source_revision']:
            # Local changes win over concurrent calendar edits. Outbound sync
            # will overwrite the remote event using its current ETag.
            return
        if remote.get('status') == 'cancelled':
            conn.execute("UPDATE appointments SET status='Cancelled',revision=revision+1 WHERE id=?",(appointment['id'],))
            status = 'Cancelled'
        else:
            if not remote.get('start',{}).get('dateTime') or not remote.get('end',{}).get('dateTime'):
                raise ProviderError('calendar_all_day_requires_review')
            start,end = parse_time(remote['start']['dateTime']),parse_time(remote['end']['dateTime'])
            if end <= start: raise ProviderError('calendar_invalid_duration')
            title = remote.get('summary','Meeting')[:255]
            conn.execute('UPDATE appointments SET title=?,starts_at=?,ends_at=?,revision=revision+1 WHERE id=?',(title,start.strftime('%Y-%m-%d %H:%M:%S'),end.strftime('%Y-%m-%d %H:%M:%S'),appointment['id']))
            status = 'Active'
        conn.execute("UPDATE integration_links SET status=?,source_revision=?,remote_etag=?,checked_at=datetime('now') WHERE id=?",(status,appointment['revision']+1,remote.get('etag'),link['id']))
        event(conn,link['client_id'],link['case_id'],'meeting.calendar_updated','Meeting updated from Google Calendar #'+str(link['record_id']))
        notify(conn,link['client_id'],link['case_id'],'Meeting updated from calendar','google:'+str(link['id'])+':'+str(appointment['revision']+1))


def reconcile(conn, providers):
    links = rows(conn,"SELECT l.* FROM integration_links l JOIN clients c ON c.id=l.client_id WHERE (l.provider='stripe' AND l.status='Open') OR (l.provider='docusign' AND l.status='Sent' AND (l.checked_at IS NULL OR l.checked_at<=datetime('now','-16 minutes'))) OR (l.provider='google' AND l.status='Active' AND c.deleted_at IS NULL AND c.merged_into IS NULL) ORDER BY coalesce(l.checked_at,''),l.id LIMIT 50")
    conn.commit()
    for link in links:
        try:
            {'stripe':reconcile_checkout,'docusign':reconcile_signature,'google':reconcile_calendar}[link['provider']](conn,providers,link)
            with transaction(conn): conn.execute("UPDATE integration_links SET checked_at=datetime('now') WHERE id=?",(link['id'],))
        except ProviderError as exc:
            conn.rollback()
            with transaction(conn):
                conn.execute("UPDATE integration_links SET checked_at=datetime('now') WHERE id=?",(link['id'],))
                if exc.code not in ('provider_http_429','provider_http_500','provider_http_502','provider_http_503','provider_http_504') and not exc.code.startswith('provider_transport_'):
                    conn.execute("UPDATE integration_links SET status='Review' WHERE id=?",(link['id'],))
                    notify(conn,link['client_id'],link['case_id'],'Provider status requires review: '+link['provider'],'integration-review:'+str(link['id']))


def run_once(conn, providers):
    namespace()
    queue_appointment_changes(conn)
    for _ in range(10):
        if not run_job(conn,providers): break
    reconcile(conn,providers)
    with transaction(conn): conn.execute("UPDATE integration_worker_state SET last_success_at=datetime('now') WHERE id=1")


def main():
    providers = Providers()
    while True:
        try:
            with closing(database.connect()) as conn:
                run_once(conn,providers)
        except (OSError,ValueError,sqlite3.Error,database.DatabaseError,ProviderError) as exc:
            print(json.dumps({'event':'integration_worker_retry','errorType':type(exc).__name__}),flush=True)
        time.sleep(60)


if __name__ == '__main__': main()
