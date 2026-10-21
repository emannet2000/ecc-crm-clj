#!/usr/bin/env python3
"""Render worker entry point. Provision services and secrets in Render first."""
from contextlib import contextmanager
import os
from pathlib import Path
import sys
import tempfile
import operations


@contextmanager
def password_file():
    password = os.environ.pop('RESTIC_PASSWORD', None)
    if password:
        with tempfile.TemporaryDirectory(prefix='ecc-restic-key-') as directory:
            path = Path(directory) / 'password'
            # The directory is private; the password file is private as well.
            fd = os.open(path, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
            with os.fdopen(fd, 'w') as stream:
                stream.write(password)
            os.environ['RESTIC_PASSWORD_FILE'] = str(path)
            yield
    else:
        yield  # run_restic validates an operator-supplied password file.


def main():
    with password_file():
        if sys.argv[1:] == ['init-repository']:
            operations.run_restic(['init'])
            print('Encrypted backup repository initialized')
        else:
            if len(sys.argv) == 1:
                sys.argv.append('run')
            operations.main()


if __name__ == '__main__':
    try:
        main()
    except Exception as exc:
        raise SystemExit('Backup worker failed: ' + type(exc).__name__ + '; details withheld') from None
