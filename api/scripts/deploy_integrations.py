#!/usr/bin/env python3
"""Review or execute a host-side, backup-first production deployment.
Defaults to a read-only plan. No host, database or service is inferred.
"""
import argparse
import json
import os
from pathlib import Path
import subprocess
import time
import operations
import release
import integration_worker as integrations


def validate_commands(path):
    value = json.loads(Path(path).read_text())
    for key in ('stop','start','health'):
        command = value.get(key)
        if not isinstance(command,list) or not command or not all(isinstance(item,str) and item and '\0' not in item for item in command):
            raise ValueError('Service command file requires stop/start/health argument arrays')
    return value


def preflight(binary, web, commands):
    if os.environ.get('APP_ENV') != 'production':
        raise ValueError('APP_ENV=production is required; no deployment target is inferred')
    target = os.environ.get('DATABASE_URL') or os.environ.get('DATABASE_PATH')
    if not target: raise ValueError('An explicit production database is required')
    integrations.public_origin()
    integrations.namespace()
    enabled = set(filter(None,os.environ.get('INTEGRATIONS_ENABLED','').split(',')))
    if not enabled or enabled - {'zoom','google','stripe','docusign'}:
        raise ValueError('Select supported providers in INTEGRATIONS_ENABLED')
    needed = {'zoom':['ZOOM_ACCOUNT_ID','ZOOM_CLIENT_ID','ZOOM_CLIENT_SECRET','ZOOM_HOST_USER'], 'google':['GOOGLE_CLIENT_ID','GOOGLE_CLIENT_SECRET','GOOGLE_REFRESH_TOKEN','GOOGLE_CALENDAR_ID'], 'stripe':['STRIPE_SECRET_KEY'], 'docusign':['DOCUSIGN_ACCOUNT_ID','DOCUSIGN_CLIENT_ID','DOCUSIGN_CLIENT_SECRET','DOCUSIGN_BASE_URL','DOCUSIGN_REFRESH_TOKEN_FILE']}
    for provider in enabled:
        for key in needed[provider]: integrations.required(key)
    existing = json.loads((Path(web)/'release.json').read_text())
    if not existing.get('verified') or existing != release.manifest(web,binary):
        raise ValueError('The exact binary, assets and migrations must pass the complete release gate first')
    if 'docusign' in enabled:
        file = Path(integrations.required('DOCUSIGN_REFRESH_TOKEN_FILE'))
        if file.is_symlink() or file.stat().st_mode & 0o077 or not file.read_text().strip():
            raise ValueError('DocuSign refresh token requires a nonempty private writable file')
    validate_commands(commands)
    return target


def deploy(binary, web, backup_dir, commands, apply=False, runner=subprocess.run, backup=operations.backup):
    target = preflight(binary,web,commands)
    actions = validate_commands(commands)
    plan = {'mode':'apply' if apply else 'plan','databaseEngine':'postgresql' if target.startswith(('postgres://','postgresql://')) else 'sqlite','providers':sorted(filter(None,os.environ['INTEGRATIONS_ENABLED'].split(','))),'stages':['verify-release','verified-offsite-backup-and-restore-drill','stop-api-and-all-writers','final-verified-offsite-backup-and-restore-drill','migrate','start-api-and-workers','authenticated-service-health-check']}
    if not apply: return plan
    # An initial recovery copy exists even if stopping services fails. The final
    # snapshot captures all last writes after API and every writer have stopped.
    backup(target,backup_dir,remote=True)
    runner(actions['stop'],check=True,timeout=180,capture_output=True)
    try:
        backup(target,backup_dir,remote=True)
        env = dict(os.environ,WEB_DIST=str(Path(web).absolute()))
        runner([str(Path(binary).absolute()),'migrate'],env=env,check=True,timeout=300,capture_output=True)
        runner(actions['start'],check=True,timeout=180,capture_output=True)
        for attempt in range(30):
            try:
                runner(actions['health'],check=True,timeout=15,capture_output=True)
                break
            except subprocess.CalledProcessError:
                if attempt == 29: raise
                time.sleep(5)
    except BaseException:
        # Do not guess whether restoring an old schema or restarting old writers
        # is safe. Preserve backups and leave a specific recovery checkpoint.
        try: runner(actions['stop'],check=True,timeout=180,capture_output=True)
        except Exception: pass
        raise RuntimeError('Deployment did not complete. Writers are stopped; use the verified recovery snapshot and inspect the failed stage.') from None
    return dict(plan,result='deployed-and-health-checked')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--binary',required=True,type=Path)
    parser.add_argument('--web',required=True,type=Path)
    parser.add_argument('--backup-dir',required=True,type=Path)
    parser.add_argument('--service-commands',required=True,type=Path)
    parser.add_argument('--apply',action='store_true')
    args = parser.parse_args()
    try: print(json.dumps(deploy(args.binary,args.web,args.backup_dir,args.service_commands,args.apply),indent=2))
    except Exception as exc:
        # Exception messages from subprocesses can contain credentials.
        print(json.dumps({'event':'deployment_failed','errorType':type(exc).__name__,'message':'Review configuration, verified release, backup evidence and service status. No successful deployment is claimed.'}))
        raise SystemExit(1)


if __name__ == '__main__': main()
