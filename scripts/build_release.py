#!/usr/bin/env python3
"""Build release images from immutable bases and record their local image IDs."""
import json
import pathlib
import subprocess

ROOT = pathlib.Path(__file__).resolve().parents[1]


def output(*args):
    return subprocess.check_output(args, cwd=ROOT, text=True).strip()


def main():
    backend = 'haskell:9.6.6-slim-bookworm'
    subprocess.run(['docker', 'pull', backend], cwd=ROOT, check=True)
    immutable = json.loads(output('docker', 'image', 'inspect', backend))[0]['RepoDigests'][0]
    if '@sha256:' not in immutable:
        raise SystemExit('Builder did not resolve to an immutable digest')
    definitions = [('api', 'Dockerfile'), ('mail', 'deploy/mail.Dockerfile'), ('backup', 'deploy/backup.Dockerfile'), ('clamav', 'deploy/clamav.Dockerfile')]
    images = {}
    for name, dockerfile in definitions:
        tag = 'ecc-crm-' + name + ':release'
        subprocess.run(['docker', 'build', '--build-arg', 'HASKELL_IMAGE=' + immutable,
                        '-f', dockerfile, '-t', tag, '.'], cwd=ROOT, check=True)
        images[name] = {'tag': tag, 'id': output('docker', 'image', 'inspect', '--format', '{{.Id}}', tag)}
    manifest = {'haskellBuilder': immutable, 'images': images}
    path = ROOT / 'release-images.json'
    path.write_text(json.dumps(manifest, indent=2) + '\n')
    print('Release image identities recorded in', path.name)


if __name__ == '__main__':
    main()
