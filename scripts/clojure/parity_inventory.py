#!/usr/bin/env python3
"""Keep a reviewable inventory of the original routes; presence is not parity."""
import json
from pathlib import Path
import re

root = Path(__file__).resolve().parents[2]
endpoints = []
for source in sorted((root / 'api/src/ECC').glob('*.hs')):
    for match in re.finditer(r'S\.(get|post|patch|put|delete)\s+"(/api/[^"\n]*)"', source.read_text()):
        endpoints.append({'method': match[1].upper(), 'path': match[2], 'source': str(source.relative_to(root)),
                          'line': source.read_text()[:match.start()].count('\n') + 1})
print(json.dumps({'note': 'Literal routes only. Dynamic workspace actions require separate workflow review.',
                  'legacyEndpoints': endpoints}, indent=2))
