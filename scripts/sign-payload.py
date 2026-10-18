#!/usr/bin/env python3
"""Explicit distribution signing only; never choose a certificate automatically."""
import os
from pathlib import Path
import subprocess
import sys

identity = os.environ['APPLE_FM_SIGN_IDENTITY']
team = os.environ['APPLE_FM_SIGN_TEAM']
if not identity.startswith('Developer ID Application:') or not identity.endswith('(' + team + ')'):
    raise SystemExit('Provide the intended Developer ID Application identity and matching APPLE_FM_SIGN_TEAM.')
root = Path(sys.argv[1])
mach_magic = {b'\xcf\xfa\xed\xfe', b'\xce\xfa\xed\xfe', b'\xca\xfe\xba\xbe', b'\xbe\xba\xfe\xca'}
for file in sorted(root.rglob('*')):
    if not file.is_file(): continue
    with file.open('rb') as stream:
        if stream.read(4) not in mach_magic: continue
    subprocess.run(['codesign', '--force', '--sign', identity, '--timestamp', '--options', 'runtime', str(file)], check=True)
    subprocess.run(['codesign', '--verify', '--strict', str(file)], check=True)
print('Distribution payload signed with explicitly selected team', team)
