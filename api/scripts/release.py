#!/usr/bin/env python3
"""Bind a quality-gate result to the exact API binary, web assets and migrations."""
import argparse
import base64
import hashlib
import json
from pathlib import Path
import re
import tarfile
import recovery

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ['index.html','main.js','bootstrap.js','reports.js','finance-print.js',
          'css/app.css','manifest.webmanifest','sw.js','offline.html',
          'icons/icon-192.png','icons/icon-512.png','brand/ecc-emblem.png','guide.html']


def digest(path):
    return base64.urlsafe_b64encode(hashlib.sha256(Path(path).read_bytes()).digest()).decode().rstrip('=')


def contract():
    backend = re.search(r'^releaseContract = "([^"]+)"', (ROOT/'src/ECC/Release.hs').read_text(), re.M).group(1)
    frontend = re.search(r'contract =\s*"([^"]+)"', (ROOT/'web/src/Release.elm').read_text()).group(1)
    if backend != frontend:
        raise ValueError('Frontend/API contracts differ')
    return backend


def manifest(web, binary=None):
    return {'format':1, 'contract':contract(), 'verified':binary is not None,
            'backend':digest(binary) if binary else '',
            'assets':{name:digest(Path(web)/name) for name in ASSETS},
            'migrations':{file.relative_to(ROOT/'migrations').as_posix():digest(file) for file in sorted((ROOT/'migrations').rglob('*.sql'))}}


def build(web):
    # Rebuilding any UI files invalidates the prior quality-gate evidence.
    recovery.atomic_json(Path(web)/'release.json',manifest(web))


def seal(web, binary):
    existing = json.loads((Path(web)/'release.json').read_text())
    current = manifest(web)
    if existing['assets'] != current['assets'] or existing['migrations'] != current['migrations'] or existing['contract'] != current['contract']:
        raise ValueError('Release changed while tests were running; rebuild and rerun checks')
    recovery.atomic_json(Path(web)/'release.json',manifest(web,binary))


def package(web, binary, output):
    existing=json.loads((Path(web)/'release.json').read_text())
    if existing != manifest(web,binary):
        raise ValueError('Only the exact sealed release can be packaged')
    selected=[(Path(binary),'ecc-crm-api')]
    selected += [(Path(web)/name,'web/dist/'+name) for name in ASSETS+['release.json']]
    selected += [(file,'migrations/'+file.relative_to(ROOT/'migrations').as_posix()) for file in sorted((ROOT/'migrations').rglob('*.sql'))]
    selected += [(file,'scripts/'+file.name) for file in sorted((ROOT/'scripts').glob('*.py'))]
    selected += [(file,'deploy/'+file.name) for file in sorted((ROOT/'deploy').iterdir()) if file.is_file() and file.suffix in ('.service','.timer','.example','.sh','.json')]
    selected += [(ROOT/name,name) for name in ['src/ECC/Release.hs','web/src/Release.elm','OPERATIONS.md','CLOCK.md','FINANCE.md','ACCESS.md','BACKUPS.md','RELIABILITY.md','INTEGRATIONS.md'] if (ROOT/name).is_file()]
    selected += [(ROOT/'scripts/requirements.txt','scripts/requirements.txt')]
    selected += [(ROOT/'deploy'/name,'deploy/'+name) for name in ['Dockerfile.postgres-backup','Dockerfile.render','Dockerfile.workers']]
    selected += [(file,'docs/'+file.name) for file in sorted((ROOT/'docs').glob('*.md'))]
    # Explicit paths exclude credentials, live databases, caches and build outputs.
    def permissions(info):
        info.mode=0o755 if info.name=='ecc-crm-api' else 0o644
        info.uid=info.gid=0;info.uname=info.gname='';return info
    with tarfile.open(output,'x:gz') as archive:
        for file,name in selected:archive.add(file,arcname=name,recursive=False,filter=permissions)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command',choices=['build','seal','package'])
    parser.add_argument('--web',type=Path,default=ROOT/'web/dist')
    parser.add_argument('--binary',type=Path)
    parser.add_argument('--output',type=Path)
    args=parser.parse_args()
    if args.command=='package':
        if not args.binary or not args.output: parser.error('package requires --binary and --output')
        package(args.web,args.binary,args.output)
    elif args.command=='seal':
        if not args.binary: parser.error('seal requires --binary after all checks pass')
        seal(args.web,args.binary)
    else: build(args.web)


if __name__=='__main__': main()
