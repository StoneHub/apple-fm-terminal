#!/usr/bin/env python3
"""Build-time only: verify and bundle a relocatable, private CPython runtime."""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent
VERSION = '3.12.15'
RELEASE = '20261013'
BASE = 'https://github.com/astral-sh/python-build-standalone/releases/download/' + RELEASE + '/'
ARTIFACTS = {
    'python.tar.gz': ('cpython-3.12.15%2B20261013-aarch64-apple-darwin-install_only_stripped.tar.gz', '9866e11cf2ae9caa1e671383786f248859a52dd8bfb702fb4c0dc2c65f1d36de'),
    'python-full.tar.zst': ('cpython-3.12.15%2B20261013-aarch64-apple-darwin-pgo%2Blto-full.tar.zst', '8c7ac5f091c64111247e595c9fc8fecc38453e94a60323a3b66dbfca3c01414a'),
}


def bundle(destination):
    cache = ROOT/'build/downloads'
    cache.mkdir(parents=True, exist_ok=True)
    for name, (asset, digest) in ARTIFACTS.items():
        archive = cache/name
        if not archive.exists():
            subprocess.run(['curl', '-fL', '--retry', '2', BASE+asset, '-o', str(archive)], check=True)
        if hashlib.sha256(archive.read_bytes()).hexdigest() != digest:
            raise ValueError('Bundled Python checksum mismatch: ' + name)
    with tempfile.TemporaryDirectory(prefix='runtime-', dir=ROOT/'build') as tmp:
        subprocess.run(['tar', '-xzf', str(cache/'python.tar.gz'), '-C', tmp], check=True)
        # Dereference upstream internal symlinks so release archives contain only
        # regular files/directories; the bootstrap can reject all archive links.
        shutil.copytree(Path(tmp)/'python', destination, ignore=shutil.ignore_patterns('__pycache__', '*.pyc'))
        # Tool scripts have upstream build-machine shebangs. Only our private
        # interpreter is used; don't ship pip/idle or development executables.
        for file in (destination/'bin').iterdir():
            if file.name != 'python3': file.unlink()
        shutil.rmtree(destination/'include')
        shutil.rmtree(destination/'share')
        shutil.rmtree(destination/'lib/python3.12/site-packages')
        (destination/'lib/python3.12/site-packages').mkdir()
        # The full distribution supplies the dependency license texts and build
        # metadata omitted from install_only. Extract just those small files.
        names = subprocess.check_output(['tar', '-tf', str(cache/'python-full.tar.zst')], text=True).splitlines()
        legal = [n for n in names if n.startswith('python/licenses/LICENSE') or n == 'python/PYTHON.json']
        if not legal: raise ValueError('Upstream license metadata missing')
        licenses = destination/'licenses'
        licenses.mkdir()
        for name in legal:
            if name.endswith('/'): continue
            data = subprocess.check_output(['tar', '-xOf', str(cache/'python-full.tar.zst'), name])
            (licenses/Path(name).name).write_bytes(data)
    (destination/'provenance.json').write_text(json.dumps({'project': 'astral-sh/python-build-standalone', 'python': VERSION, 'release': RELEASE, 'target': 'aarch64-apple-darwin', 'artifacts': ARTIFACTS}, indent=2)+'\n')
    subprocess.run([str(destination/'bin/python3'), '-I', '-B', '-c', 'import pty, socket, ssl, json, termios, fcntl; print("Private Python runtime ready")'], check=True)


if __name__ == '__main__':
    bundle(ROOT/'build/package/runtime')
