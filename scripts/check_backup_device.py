#!/usr/bin/env python3
"""Require physical Release OAuth evidence for the configured Google client."""
import json
import pathlib
import plistlib
import sys

try:
    root = pathlib.Path(__file__).resolve().parent.parent
    configuration = plistlib.loads((root / 'clinical-swift/Info.plist').read_bytes())
    credentials = json.loads(pathlib.Path(sys.argv[1]).read_text())
    device = credentials.get('deviceCheck') or {}
    if not (device.get('releaseOnDevice') is True
            and device.get('clientID') == configuration['GoogleBackupClientID']
            and device.get('callbackScheme') == configuration['GoogleBackupCallbackScheme']
            and credentials.get('clientID') == device.get('clientID')):
        raise ValueError()
except Exception:
    print('Release blocked: complete Google authorization in a signed Release internal build on a physical iPhone, then export its check credentials. Simulator credentials can run backup-drive-check.', file=sys.stderr)
    sys.exit(1)
