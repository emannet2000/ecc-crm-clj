"""HTTPS operations alert delivery. No redirects or customer data."""
import json
import os
from pathlib import Path
import urllib.request
import urllib.parse


def send_alert(payload):
    endpoint = os.environ.get('ALERT_WEBHOOK_URL', '')
    parsed = urllib.parse.urlsplit(endpoint)
    if parsed.scheme != 'https' or not parsed.hostname or parsed.username or parsed.password:
        raise ValueError('Configure an HTTPS alert webhook')
    headers = {'Content-Type': 'application/json'}
    token_file = os.environ.get('ALERT_TOKEN_FILE')
    if token_file:
        path = Path(token_file)
        if not path.is_file() or path.stat().st_mode & 0o077:
            raise ValueError("Alert token file must be private")
        token = path.read_text().strip()
        if not token or '\n' in token or '\r' in token:
            raise ValueError('Invalid alert token')
        headers['Authorization'] = 'Bearer ' + token
    # Redirects could send authorization to another host. Reject them.
    class NoRedirect(urllib.request.HTTPRedirectHandler):
        def redirect_request(self, req, fp, code, msg, hdrs, newurl):
            return None
    request = urllib.request.Request(endpoint, data=json.dumps(payload).encode(), headers=headers, method='POST')
    with urllib.request.build_opener(NoRedirect).open(request, timeout=15) as response:
        if not 200 <= response.status < 300:
            raise RuntimeError('Alert delivery failed')

