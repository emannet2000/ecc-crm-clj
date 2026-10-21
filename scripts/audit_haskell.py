#!/usr/bin/env python3
"""Conservatively check a Cabal plan against the Haskell Security Advisory DB."""
import json
import pathlib
import re
import sys
import tomllib


def version(value):
    if not re.fullmatch(r'\d+(?:\.\d+)*', value):
        raise ValueError('Invalid version: ' + value)
    return tuple(map(int, value.split('.')))


def affected(current, ranges):
    current = version(current)
    return any(version(entry.get('introduced', '0')) <= current and
               ('fixed' not in entry or current < version(entry['fixed'])) for entry in ranges)


def audit(plan, database):
    packages = {(pkg['pkg-name'], pkg['pkg-version']) for pkg in plan['install-plan']}
    compiler = plan['compiler-id'].removeprefix('ghc-')
    findings = []
    paths = list(pathlib.Path(database).rglob('HSEC-*.md'))
    if not paths:
        raise ValueError('Security advisory database is empty')
    for path in paths:
        match = re.search(r'^```toml\s*\n(.*?)^```', path.read_text(), re.M | re.S)
        if not match:
            raise ValueError('Missing advisory metadata: ' + str(path))
        data = tomllib.loads(match[1])
        if data['advisory'].get('withdrawn'):
            continue
        for entry in data.get('affected', []):
            candidates = [(name, ver) for name, ver in packages if name == entry.get('package')]
            if 'ghc-component' in entry:
                candidates.append((entry['ghc-component'], compiler))
            for name, current in candidates:
                if 'versions' not in entry:
                    raise ValueError('Missing affected version ranges: ' + str(path))
                if affected(current, entry['versions']):
                    findings.append(f"{data['advisory']['id']}: {name} {current} ({path})")
    return findings


if __name__ == '__main__':
    if len(sys.argv) != 3:
        raise SystemExit('Usage: audit_haskell.py api/dist-newstyle/cache/plan.json /path/to/security-advisories/advisories')
    findings = audit(json.loads(pathlib.Path(sys.argv[1]).read_text()), sys.argv[2])
    print('\n'.join(findings) if findings else 'No matching Haskell advisories')
    raise SystemExit(bool(findings))
