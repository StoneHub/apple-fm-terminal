#!/usr/bin/env python3
"""Exact preview archive test with external developer tools deliberately failing."""
import os
from pathlib import Path
import pty
import select
import signal
import subprocess
import tarfile
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parent.parent


class Preview(unittest.TestCase):
    def test_unready_setup_and_unactivated_uninstall(self):
        with tempfile.TemporaryDirectory(prefix='fm-unready-') as tmp:
            root = Path(tmp)/'payload'
            (root/'scripts').mkdir(parents=True)
            script = root/'scripts/management.py'
            script.write_bytes((ROOT/'scripts/management.py').read_bytes())
            (root/'VERSION').write_text('fixture')
            helper = root/'apple-fm-terminal-model'
            helper.write_text('#!/bin/sh\necho \'{"availability":"appleIntelligenceNotEnabled"}\'\n')
            helper.chmod(0o755)
            (root/'installed-files.json').write_text('["scripts/management.py", "VERSION", "apple-fm-terminal-model"]')
            home = Path(tmp)/'home'
            home.mkdir()
            (home/'.zshrc').write_text('# preserved')
            env = dict(os.environ, HOME=str(home), ZDOTDIR=str(home))
            command = [str(ROOT/'build/package/runtime/bin/python3'), '-I', '-B', str(script)]
            result = subprocess.run(command+['setup', '--yes'], env=env, capture_output=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual((home/'.zshrc').read_text(), '# preserved')
            self.assertFalse((home/'.zshenv').exists())
            self.assertFalse((root/'backups').exists())
            result = subprocess.run(command+['uninstall', '--yes'], env=env, capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertFalse(root.exists())

    def test_unsafe_archives_and_wrong_checksums(self):
        with tempfile.TemporaryDirectory(prefix='fm-unsafe-') as tmp:
            root = Path(tmp)
            archive = root/'unsafe.tar.gz'
            env = dict(os.environ, HOME=tmp)
            for name, link in [('../outside', False), ('/absolute', False), ('payload/link', True)]:
                with self.subTest(name=name):
                    with tarfile.open(archive, 'w:gz') as bundle:
                        info = tarfile.TarInfo(name)
                        if link:
                            info.type = tarfile.SYMTYPE
                            info.linkname = '/tmp'
                        bundle.addfile(info)
                    result = subprocess.run(['/bin/sh', str(ROOT/'install.sh'), '--archive', str(archive), '--yes'], env=env, capture_output=True)
                    self.assertNotEqual(result.returncode, 0)
                    self.assertFalse((root/'.local').exists())
            sums = root/'SHA256SUMS'
            sums.write_text('0'*64+'  '+archive.name+'\n')
            result = subprocess.run(['/bin/sh', str(ROOT/'install.sh'), '--archive', str(archive), '--checksums', str(sums)], env=env, capture_output=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn(b'checksum verification failed', result.stderr)

    def test_self_contained_install_use_update_remove(self):
        with tempfile.TemporaryDirectory(prefix='fm-preview-check-') as tmp:
            base = Path(tmp)
            home = base/'home'
            home.mkdir()
            target = home/'.local/share/apple-fm-terminal'
            original = b'PS1="PREVIEW> "\nalias my-command="print PRESERVED"\n_test_buffer() { print -r -- "$BUFFER" > "$HOME/accepted-buffer"; }; zle -N _test_buffer; bindkey "^Xb" _test_buffer\n'
            (home/'.zshrc').write_bytes(original)
            (home/'.zshenv').write_bytes(b'# original env\n')
            stubs = base/'stubs'
            stubs.mkdir()
            trace = base/'external-tool-used'
            for name in ['python3', 'python', 'swift', 'xcode-select', 'xcrun']:
                file = stubs/name
                file.write_text('#!/bin/sh\nprintf BAD >> "'+str(trace)+'"\nexit 99\n')
                file.chmod(0o755)
            poison = base/'poison'
            poison.mkdir()
            (poison/'sitecustomize.py').write_text('raise RuntimeError("External Python path loaded")')
            env = dict(os.environ, HOME=str(home), ZDOTDIR=str(home), PATH=str(stubs)+':/usr/bin:/bin:/usr/sbin:/sbin', PYTHONHOME=str(poison), PYTHONPATH=str(poison), TERM='xterm-256color', TERM_PROGRAM='FMPreviewTest')
            env.pop('APPLE_FM_PYTHON', None)
            env.pop('PYTHONDONTWRITEBYTECODE', None)
            command = ['/bin/sh', str(ROOT/'install.sh'), '--archive', str(ROOT/'dist/apple-fm-terminal.tar.gz'), '--checksums', str(ROOT/'dist/SHA256SUMS')]
            result = subprocess.run(command, input='y\n', text=True, capture_output=True, env=env)
            self.assertEqual(result.returncode, 0, result.stdout+result.stderr)
            configured = (home/'.zshenv').read_text()
            self.assertIn(str(target/'runtime/bin/python3'), configured)
            self.assertNotIn('Xcode', configured)
            self.assertNotIn('apple-fm-terminal-install.', configured)
            cli = home/'.local/bin/apple-fm-terminal'
            result = subprocess.run([str(cli), '--version'], env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout.strip(), '0.3.0-preview.1')
            count = len(list((target/'backups').iterdir()))
            result = subprocess.run(command+['--yes'], env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stdout+result.stderr)
            self.assertEqual(len(list((target/'backups').iterdir())), count)
            master, slave = pty.openpty()
            process = subprocess.Popen(['/bin/zsh', '-l', '-i'], stdin=slave, stdout=slave, stderr=slave, env=env, start_new_session=True)
            os.close(slave)
            pending = b''
            def read_until(needle, timeout=8):
                nonlocal pending
                end = time.monotonic()+timeout
                while needle not in pending:
                    if time.monotonic()>end:
                        raise AssertionError('PTY missing '+repr(needle)+': '+repr(pending[-1000:]))
                    if select.select([master], [], [], .05)[0]:
                        pending += os.read(master, 65536)
                at = pending.index(needle)+len(needle)
                result, pending = pending[:at], pending[at:]
                return result
            def send(value): os.write(master, value)
            try:
                read_until(b'\x1b[?2004h')
                send(b'my-command\r')
                self.assertIn(b'PRESERVED', read_until(b'\x1b[?2004h'))
                send(b'print -r -- "ENV_CHECK:${PYTHONDONTWRITEBYTECODE-unset}"\r')
                self.assertIn(b'\r\nENV_CHECK:unset\r\n', read_until(b'\x1b[?2004h'))
                send(b'sw_vers -product\r')
                read_until(b'\x1b[?2004h')
                send(b'ask "Correct the failed sw_vers command to show the macOS version"\r')
                self.assertIn(b'Proposed command: sw_vers --productVersion', read_until(b'\x1b[?2004h', 30))
                send(b'\t')
                time.sleep(.2)
                inserted = os.read(master, 65536) if select.select([master], [], [], .5)[0] else b''
                # ZLE redraws only changed screen cells; inspect actual buffer
                # through this isolated fixture's widget instead of screen text.
                send(b'\x18b')
                deadline = time.monotonic()+2
                while not (home/'accepted-buffer').exists() and time.monotonic()<deadline:
                    time.sleep(.02)
                self.assertEqual((home/'accepted-buffer').read_text().strip(), 'sw_vers --productVersion')
                self.assertNotIn(b'\x1b[?2004l', inserted)
                send(b'\r')
                actual = subprocess.check_output(['/usr/bin/sw_vers', '-productVersion']).strip()
                self.assertIn(actual, read_until(b'\x1b[?2004h'))
                send(b'exit\r')
                end = time.monotonic()+5
                while process.poll() is None and time.monotonic()<end:
                    if select.select([master], [], [], .05)[0]:
                        try: os.read(master, 65536)
                        except OSError: pass
                self.assertIsNotNone(process.poll())
            finally:
                if process.poll() is None:
                    os.killpg(process.pid, signal.SIGHUP)
                    process.wait(timeout=5)
                os.close(master)
            self.assertFalse(trace.exists(), 'External developer tool invoked')
            self.assertFalse(list(target.rglob('__pycache__')))
            self.assertFalse(list(target.rglob('._*')))
            (target/'unrelated.txt').write_text('keep')
            result = subprocess.run([str(cli), 'uninstall', '--yes'], env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stdout+result.stderr)
            self.assertEqual((home/'.zshrc').read_bytes(), original)
            self.assertEqual((home/'.zshenv').read_bytes(), b'# original env\n')
            self.assertFalse(cli.exists())
            self.assertEqual([p.name for p in target.rglob('*')], ['unrelated.txt'])


if __name__ == '__main__':
    unittest.main(verbosity=2)
