#!/usr/bin/env python3
"""Build the Clojure release using a resolved builder digest and record image IDs.
CI runs the application/browser/capacity suites and image scans separately.
"""
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]

def output(*args):
    return subprocess.check_output(args, cwd=ROOT, text=True).strip()

def main():
    builder = 'clojure:temurin-21-tools-deps'
    subprocess.run(['docker', 'pull', builder], cwd=ROOT, check=True)
    immutable = json.loads(output('docker', 'image', 'inspect', builder))[0]['RepoDigests'][0]
    if '@sha256:' not in immutable: raise SystemExit('Builder did not resolve to an immutable digest')
    images = {}
    for name, dockerfile, tag in [('api','Dockerfile','ecc-crm-clojure:release'),('clamav','deploy/clamav.Dockerfile','ecc-crm-clamav:release')]:
        subprocess.run(['docker','build','--build-arg','CLOJURE_IMAGE='+immutable,'--file',dockerfile,'--tag',tag,'.'], cwd=ROOT, check=True)
        images[name] = {'tag':tag,'id':output('docker','image','inspect','--format','{{.Id}}',tag)}
    subprocess.run(['docker','pull','caddy:2'], cwd=ROOT, check=True)
    images['caddy'] = {'tag':'caddy:2','id':output('docker','image','inspect','--format','{{.Id}}','caddy:2')}
    (ROOT/'release-images.json').write_text(json.dumps({'stack':'clojure-xtdb','builder':immutable,'images':images},indent=2)+'\n')
    services = {name:{'image':images['api' if name=='backup' else name]['id']} for name in ['api','backup','clamav','caddy']}
    (ROOT/'compose.verified.yaml').write_text(json.dumps({'services':services},indent=2)+'\n')
    print('Recorded image identities and compose.verified.yaml. Run the quality gate and image scans before deployment.')

if __name__ == '__main__': main()
