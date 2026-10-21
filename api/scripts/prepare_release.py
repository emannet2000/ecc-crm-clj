#!/usr/bin/env python3
"""Verify a tested release and a restored off-site backup before schema changes.
Run in the new release directory with production environment variables loaded.
API and background writer services must already be stopped; this does not restart them.
"""
import argparse
import os
from pathlib import Path
import re
import subprocess
import operations
import recovery


def run(arguments):
    return subprocess.run(arguments,check=True,text=True,capture_output=True,timeout=300).stdout.strip()


def prepare(binary, database, directory, services, runner=run, backupper=operations.backup):
    if os.environ.get('DATABASE_URL'):
        raise ValueError('This systemd preparation command is SQLite-only; use the Render PostgreSQL runbook')
    binary=Path(binary).absolute()
    database=Path(database).absolute()
    if os.environ.get('APP_ENV') != 'production':
        raise ValueError('APP_ENV=production is required for production preparation')
    if Path(os.environ.get('DATABASE_PATH','')).absolute() != database:
        raise ValueError('DATABASE_PATH must match the database being backed up')
    if not services or any(not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_.@-]*\.service',service) for service in services):
        raise ValueError('Specify the API and all background writer service names')
    # Verify binary, assets and migrations before touching the live database.
    runner([str(binary),'verify-release'])
    if runner(['timedatectl','show','--property=NTPSynchronized','--value'])!='yes':
        raise ValueError('Host clock synchronization must be verified before migration')
    for service in services:
        state=runner(['systemctl','show','--property=LoadState','--value','--',service])
        active=runner(['systemctl','show','--property=ActiveState','--value','--',service])
        if state!='loaded' or active!='inactive':
            raise ValueError('All supplied writer services must be installed and stopped')
    recovery.validate(database)
    # Actual remote restore verification, not an upload-success assertion.
    backupper(database,Path(directory),remote=True)
    runner([str(binary),'migrate'])
    return {'event':'release-prepared','backupRestoreVerified':True,
            'servicesRestarted':False}


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--binary',required=True,type=Path)
    parser.add_argument('--database',type=Path,default=os.environ.get('DATABASE_PATH'),required=not os.environ.get('DATABASE_PATH'))
    parser.add_argument('--directory',type=Path,default=os.environ.get('BACKUP_DIR'),required=not os.environ.get('BACKUP_DIR'))
    parser.add_argument('--service',action='append',required=True)
    args=parser.parse_args()
    import json
    print(json.dumps(prepare(args.binary,args.database,args.directory,args.service),sort_keys=True))


if __name__=='__main__': main()
