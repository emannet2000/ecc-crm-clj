"""Prepare the existing Elm frontend with the myapp5 navy/gold motif."""
from pathlib import Path
import shutil
import runpy

root = Path(__file__).resolve().parents[1]
source = root.parent / 'web'
target = root / 'web'
for name in ('src', 'public', 'dist'):
    shutil.copytree(source / name, target / name, dirs_exist_ok=True)
shutil.copy2(source / 'elm.json', target / 'elm.json')
css = (source / 'public/css/app.css').read_text()
# Translate the existing components to the reference workspace palette.
palette = {
    '#f6f7f4':'#f5f7fa', '#213d37':'#202b3c', '#687872':'#59677b',
    '#dfe7e1':'#e0e5ec', '#256953':'#916113', '#e9f1eb':'#f8f2e7',
    '#14211e':'#101722', '#1c2e28':'#182130', '#e0e9de':'#e8edf5',
    '#a0b1a5':'#b1bfd1', '#33473b':'#303d50', '#8fb69c':'#e2b457',
    '#263e31':'#202b3c', '#174b3d':'#182131', '#153c36':'#182131',
}
for old, new in palette.items():
    css = css.replace(old, new)
css += '''
/* Motif adapted from ecc-crm-myapp5/public/workspace.css. */
.header,.login-story { background:#182131; color:#e4eaf3; }
.header .logo,.header .logo strong { color:#fff; }
.header .logo-icon,.login-brand .logo-icon { background:#dfb45f; color:#182131; }
.header .nav-link { color:#bdc7d7; }
.header .nav-link:hover { background:#253146; color:#fff; }
.header .nav-link.active { background:rgba(223,180,95,.14); color:#f7d58f; box-shadow:none; }
.header .nav-section-label,.header-right { color:#94a4ba; }
.header .nav-link.active::after { background:#dfb45f; }
.login-story h1,.login-card h2,.heading-content h1 { font-family:inherit; font-weight:650; }
.login-card h2 { color:var(--ink); }
.login-story p,.login-brand span,.login-story-footer { color:#bdc7d7; }
.login-story .eyebrow { color:#dfb45f; }
.btn-primary,.login-submit { background:var(--accent); color:#fff; }
.btn-primary:hover,.login-submit:hover { filter:brightness(.94); }
.card,.stat { border-color:var(--line); box-shadow:0 2px 4px #18273e08; }
.stage-fill { background:var(--accent); }
:focus-visible { outline:2px solid var(--accent); outline-offset:3px; }
.dark-mode .btn-primary,.dark-mode .login-submit { color:#1a2230; }
.dark-mode .task-column,.dark-mode .search-container { background:var(--paper); }
'''
css = runpy.run_path(str(root / 'scripts/theme-palette.py'))['remove_green'](css)
for folder in ('public','dist'):
    (target / folder / 'css/app.css').write_text(css)
    index = target / folder / 'index.html'
    index.write_text(index.read_text().replace('#153c36','#182131'))
print('Prepared api/web sources and compiled assets')
