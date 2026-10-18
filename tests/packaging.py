#!/usr/bin/env python3
"""Packaging regression: extended attributes, dirty archives and safe upgrades."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tarfile
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent


class Packaging(unittest.TestCase):
    def test_archive_and_install_discard_metadata(self):
        with tempfile.TemporaryDirectory(prefix='fm-package-check-') as tmp:
            base = Path(tmp)
            repo = base/'repo'
            package = repo/'build/package'
            (package/'scripts').mkdir(parents=True)
            (repo/'scripts').mkdir()
            (repo/'VERSION').write_text('0.2.0\n')
            shutil.copyfile(ROOT/'package-release.sh', repo/'package-release.sh')
            shutil.copyfile(ROOT/'install.sh', repo/'install.sh')
            build = repo/'scripts/build-install.sh'
            build.write_text('#!/bin/sh\nexit 0\n')
            build.chmod(0o755)
            shutil.copyfile(ROOT/'scripts/install.py', package/'scripts/install.py')
            (package/'scripts/management.py').write_text('raise SystemExit(0)\n')
            for name in ['apple-fm-terminal', 'apple-fm-terminal-model', 'terminal-session']:
                (package/name).write_text('fixture\n')
            subprocess.run(['xattr', '-w', 'com.apple.metadata:fm-packaging-test', 'fixture', str(package/'terminal-session')], check=True)
            debris = b'\x00\x05\x16\x07fixture'
            for name in ['._terminal-session', '.DS_Store', 'scripts/._install.py']:
                (package/name).write_bytes(debris)
            subprocess.run(['sh', str(repo/'package-release.sh')], check=True, capture_output=True)
            archive = repo/'dist/apple-fm-terminal.tar.gz'
            with tarfile.open(archive) as bundle:
                names = bundle.getnames()
            self.assertFalse(any(p.startswith('._') or p == '.DS_Store' for name in names for p in Path(name).parts), names)
            home = base/'home'
            home.mkdir()
            target = home/'.local/share/apple-fm-terminal'
            (target/'scripts').mkdir(parents=True)
            for name in ['._terminal-session', '._scripts', 'scripts/._install.py']:
                (target/name).write_bytes(debris)
            (target/'._unrelated').write_bytes(debris)
            (target/'scripts/._management.py').write_bytes(b'user text, not AppleDouble')
            env = dict(os.environ, HOME=str(home), APPLE_FM_INSTALL_DIR=str(target), APPLE_FM_PYTHON=sys.executable, PYTHONDONTWRITEBYTECODE='1')
            # Exercise the real archive extraction and installer; stub only setup.
            subprocess.run(['sh', str(ROOT/'install.sh'), '--archive', str(archive), '--yes'], env=env, check=True, capture_output=True)
            self.assertFalse((target/'._terminal-session').exists())
            self.assertFalse((target/'._scripts').exists())
            self.assertFalse((target/'scripts/._install.py').exists())
            self.assertEqual((target/'._unrelated').read_bytes(), debris)
            self.assertEqual((target/'scripts/._management.py').read_bytes(), b'user text, not AppleDouble')
            # A direct directory install may still contain older metadata entries.
            subprocess.run([sys.executable, str(ROOT/'scripts/install.py'), str(package), str(target), '--yes'], env=env, check=True, capture_output=True)
            self.assertFalse((target/'.DS_Store').exists())
            inventory = json.loads((target/'installed-files.json').read_text())
            self.assertFalse(any(part.startswith('._') or part == '.DS_Store' for name in inventory for part in Path(name).parts))
            self.assertEqual((target/'terminal-session').read_bytes(), b'fixture\n')


if __name__ == '__main__':
    unittest.main()
