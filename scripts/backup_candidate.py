#!/usr/bin/env python3
"""Bind backup checks to source, configuration, and archive bytes."""
import hashlib
import json
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent


def digest_files(root, paths):
    digest = hashlib.sha256()
    for relative in sorted(paths):
        path = root / relative
        digest.update(str(relative).encode() + b'\0')
        if path.is_symlink():
            digest.update(path.readlink().as_posix().encode())
        elif path.is_file():
            with path.open('rb') as stream:
                for chunk in iter(lambda: stream.read(1048576), b''):
                    digest.update(chunk)
        else:
            digest.update(b'<deleted>')
    return digest.hexdigest()


def candidate():
    names = subprocess.check_output(['git', 'ls-files', '-z', '--cached', '--others', '--exclude-standard'], cwd=ROOT).decode().split('\0')
    return {'source': digest_files(ROOT, {p for p in names if p and not p.startswith('sites/')}), 'configuration': 'Release'}


def archive_digest(path):
    return digest_files(path, [p.relative_to(path) for p in path.rglob('*') if p.is_file() and p.name != 'clinical-backup-receipt.json'])


def main():
    mode, destination = sys.argv[1:3]
    path = pathlib.Path(destination)
    current = candidate()
    if mode == 'capture':
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(current, sort_keys=True))
    elif mode == 'check':
        if json.loads(path.read_text()) != current:
            raise RuntimeError('Candidate source changed during verification or archive creation.')
    elif mode == 'attest':
        saved = json.loads(pathlib.Path(sys.argv[3]).read_text())
        if saved != current:
            raise RuntimeError('Archive source changed during its build.')
        current['archive'] = archive_digest(path)
        (path / 'clinical-backup-receipt.json').write_text(json.dumps(current, sort_keys=True))
    elif mode == 'verify-archive':
        saved = json.loads((path / 'clinical-backup-receipt.json').read_text())
        current['archive'] = archive_digest(path)
        if saved != current:
            raise RuntimeError('Archive does not match this candidate. Create a new archive.')
    else:
        raise RuntimeError('Unknown candidate command.')


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        print('Backup release gate: ' + str(error), file=sys.stderr)
        sys.exit(1)
