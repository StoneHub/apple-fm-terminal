#!/usr/bin/env python3
"""Focused PTY checks for the prototype's context and execution boundaries."""
import fcntl
import importlib.machinery
import importlib.util
import json
import os
from pathlib import Path
import pty
import select
import subprocess
import tempfile
import termios
import time
import unittest

ROOT = Path(__file__).resolve().parent.parent
loader = importlib.machinery.SourceFileLoader("terminal_help", str(ROOT / "terminal-session"))
spec = importlib.util.spec_from_loader(loader.name, loader)
helper = importlib.util.module_from_spec(spec)
loader.exec_module(helper)


class Terminal:
    def __init__(self, scratch, extra_rc="", native=False):
        self.log = scratch / "calls.jsonl"
        fake = scratch / "fixture-fm"
        fake.write_text("#!/usr/bin/env python3\n" + '''
import json, os, sys, time
if '--availability' in sys.argv:
    print(json.dumps({'availability': 'available'})); sys.exit(0)
request = json.loads(json.load(sys.stdin)["prompt"])
with open(os.environ['FM_TEST_LOG'], 'a') as log:
    log.write(json.dumps(request) + '\\n')
question = request['user_request']
if 'SLOW' in question:
    time.sleep(40)
if 'UNKNOWN' in question:
    command = 'fm_nonexistent_tool'
elif 'CHAIN' in question:
    command = 'printf X; printf Y'
else:
    command = 'printf FM_EXECUTED'
print(json.dumps({'explanation': 'Fixture explanation, no execution.', 'next_command': command}))
''')
        fake.chmod(0o755)
        self.master, slave = pty.openpty()
        fcntl.ioctl(slave, termios.TIOCSWINSZ, b"\x1e\x00\x78\x00\x00\x00\x00\x00")
        self.home = scratch / "home"
        self.home.mkdir()
        self.rc_original = b"PS1='PROOF> '\nsetopt no_prompt_sp\nalias fm-proof='print ALIAS_PROOF'\nprint rc >> \"$HOME/rc-count\"\n" + extra_rc.encode()
        (self.home / ".zshrc").write_bytes(self.rc_original)
        (self.home / ".zshenv").write_text('print env >> "$HOME/env-count"\n')
        (self.home / ".zprofile").write_text('print profile >> "$HOME/profile-count"\n')
        env = dict(os.environ, HOME=str(self.home), ZDOTDIR=str(self.home), APPLE_FM_INSTALL_DIR=str(scratch / "installed"),
                   APPLE_FM_MODEL_HELPER=str(fake), FM_TEST_LOG=str(self.log), TERM="xterm-256color", TERM_PROGRAM="FMTest", PYTHONDONTWRITEBYTECODE="1")
        if native:
            env.pop("APPLE_FM_MODEL_HELPER", None)
        subprocess.run([str(ROOT / "install.sh"), "--directory", str(ROOT / "build/package"), "--yes"], env=env, check=True, capture_output=True)
        self.process = subprocess.Popen(["/bin/zsh", "-l", "-i"], stdin=slave, stdout=slave, stderr=slave,
                                        env=env, start_new_session=True)
        os.close(slave)
        self.pending = b""
        self.startup = self.read_until(b"\x1b[?2004h")

    def send(self, value):
        os.write(self.master, value.encode() if isinstance(value, str) else value)

    def read_until(self, needle, timeout=6):
        end = time.monotonic() + timeout
        while needle not in self.pending:
            if time.monotonic() > end:
                raise AssertionError(f"Missing {needle!r}; output={self.pending[-4000:]!r}")
            if select.select([self.master], [], [], 0.05)[0]:
                self.pending += os.read(self.master, 65536)
        at = self.pending.index(needle) + len(needle)
        result, self.pending = self.pending[:at], self.pending[at:]
        return result.decode("utf-8", "replace")

    def command(self, text):
        self.send(text + "\r")
        return self.read_until(b"\x1b[?2004h")

    def calls(self):
        return [json.loads(line) for line in self.log.read_text().splitlines()] if self.log.exists() else []

    def drain(self, duration=0.2):
        result, self.pending = self.pending, b""
        end = time.monotonic() + duration
        while time.monotonic() < end:
            if select.select([self.master], [], [], 0.02)[0]:
                result += os.read(self.master, 65536)
        return result.decode("utf-8", "replace")

    def close(self):
        if self.process.poll() is None:
            self.send(b"\x03")
            time.sleep(0.1)
            self.send("exit\r")
            end = time.monotonic() + 3
            while self.process.poll() is None and time.monotonic() < end:
                if select.select([self.master], [], [], 0.05)[0]:
                    try: os.read(self.master, 65536)
                    except OSError: break
            if self.process.poll() is None:
                import signal
                os.killpg(self.process.pid, signal.SIGKILL)
            self.process.wait(timeout=3)
        os.close(self.master)
        time.sleep(0.1)


class Checks(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="fm-ask-check-")
        self.scratch = Path(self.temp.name)
        self.terminal = Terminal(self.scratch)

    def tearDown(self):
        self.terminal.close()
        self.temp.cleanup()

    def test_accept_then_enter_and_context(self):
        t = self.terminal
        t.command("print CONTEXT_PROOF")
        result = t.command('ask "help me"')
        self.assertIn("Proposed command: printf FM_EXECUTED", result)
        self.assertNotIn("\r\nFM_EXECUTED", result)
        calls = t.calls()
        self.assertEqual(len(calls), 1)
        self.assertEqual(calls[0]["session_context"][-1]["command"], "print CONTEXT_PROOF")
        self.assertIn("CONTEXT_PROOF", calls[0]["session_context"][-1]["output"])
        self.assertEqual(calls[0]["session_context"][-1]["exit_status"], 0)
        result = t.command("")
        self.assertNotIn("\r\nFM_EXECUTED", result)
        t.command('ask "help again"')
        t.send(b"\t")
        before_enter = t.drain()
        self.assertIn("printf FM_EXECUTED", before_enter)
        self.assertNotIn("\r\nFM_EXECUTED", before_enter)
        self.assertNotIn("\x1b[?2004l", before_enter)
        self.assertEqual(len(t.calls()), 2)
        t.send(b"\r")
        result = t.read_until(b"\x1b[?2004h")
        self.assertIn("\r\nFM_EXECUTED", result)

    def test_shortcut_and_changed_buffer(self):
        t = self.terminal
        t.send("explain this")
        t.send(b"\x18?")
        result = t.read_until(b"Enter runs it separately.")
        self.assertIn("Proposed command", result)
        self.assertEqual(t.calls()[0]["user_request"], "explain this")
        t.send(b"\x1b")
        time.sleep(0.1)
        t.send(b"\x15")
        result = t.command("print DISMISSED")
        self.assertIn("\r\nDISMISSED", result)
        self.assertNotIn("\r\nFM_EXECUTED", result)
        t.command('ask "help"')
        t.send("print EDITED")
        t.send(b"\r")
        result = t.read_until(b"\x1b[?2004h")
        self.assertIn("\r\nEDITED", result)
        self.assertNotIn("\r\nFM_EXECUTED", result)

    def test_missing_command_and_scripts_stay_normal(self):
        t = self.terminal
        result = t.command("fm_definitely_missing")
        self.assertIn("command not found", result)
        self.assertIn("No model has run.", result)
        result = t.command('print "STATUS:$?"')
        self.assertIn("\r\nSTATUS:127", result)
        script = self.scratch / "script.zsh"
        script.write_text('fm_script_missing\nask "do not run"\n')
        for command in [f"zsh {script}", f"source {script}", 'f() { ask "no"; }; f',
                        'for n in 1; do ask "no"; done', 'ask "no" | cat', 'print "$(ask no)"']:
            result = t.command(command)
            self.assertNotIn("No model has run.", result)
        t.send(b"\x1b[200~ask pasted\n\x1b[201~\r")
        t.read_until(b"\x1b[?2004h")
        self.assertEqual(t.calls(), [])

    def test_quoted_question_and_normal_child_tty(self):
        t = self.terminal
        self.assertEqual((t.home/"rc-count").read_text().splitlines(), ["rc"])
        self.assertEqual((t.home/"env-count").read_text().splitlines(), ["env"])
        self.assertEqual((t.home/"profile-count").read_text().splitlines(), ["profile"])
        self.assertIn("\r\nALIAS_PROOF", t.command("fm-proof"))
        result = t.command("zsh -c '[[ -t 0 && -t 1 && -t 2 ]] && print CHILD_TTY; exit 7'")
        self.assertIn("\r\nCHILD_TTY", result)
        result = t.command('print "STATUS:$?"')
        self.assertIn("\r\nSTATUS:7", result)
        t.command("ask 'What does a | b mean?'")
        self.assertEqual(t.calls()[0]["user_request"], "What does a | b mean?")

    def test_bounded_context_clear_and_output_controls(self):
        t = self.terminal
        for number in range(7):
            t.command(f"print EVENT_{number}")
        result = t.command("ask --context")
        self.assertNotIn('"command": "print EVENT_0"', result)
        self.assertIn('"command": "print EVENT_6"', result)
        t.command("printf '%10000s' x")
        t.command("ask help")
        context = t.calls()[0]["session_context"]
        self.assertLessEqual(len(context), 5)
        self.assertTrue(all(len(e["output"]) <= 1800 for e in context))
        self.assertLessEqual(len(json.dumps(context)), 7000)
        t.command("ask --clear")
        result = t.command("ask --context")
        self.assertIn("\r\n[]\r\n", result)
        self.assertEqual(len(t.calls()), 1)

    def test_invalid_model_commands_and_cancellation(self):
        t = self.terminal
        for question in ("UNKNOWN", "CHAIN"):
            result = t.command(f"ask {question}")
            self.assertNotIn("Proposed command:", result)
        t.send("ask SLOW\r")
        t.read_until(b"thinking locally")
        end = time.monotonic() + 3
        while len(t.calls()) < 3 and time.monotonic() < end:
            time.sleep(0.02)
        t.send(b"\x03")
        t.read_until(b"\x1b[?2004h")
        result = t.command("print AFTER_CANCEL")
        self.assertIn("\r\nAFTER_CANCEL", result)
        # Check cancellation kills only this model's process, without relying on
        # global process-name kills or terminating the shell.
        time.sleep(0.3)
        processes = subprocess.check_output(["ps", "-axo", "command="], text=True)
        self.assertNotIn(str(self.scratch / "fixture-fm"), processes)

    def test_typeahead_during_generation_cannot_accept_a_command(self):
        t = self.terminal
        t.send("ask SLOW\r")
        t.read_until(b"thinking locally")
        end = time.monotonic() + 3
        while not t.calls() and time.monotonic() < end:
            time.sleep(0.02)
        t.send(b"\t\r")
        result = t.read_until(b"\x1b[?2004h")
        self.assertIn("Typing cancelled", result)
        self.assertNotIn("Proposed command", result)
        self.assertNotIn("\r\nFM_EXECUTED", result)

    def test_pause_and_nested_shell_context(self):
        t = self.terminal
        t.command("print BEFORE_PAUSE")
        t.command("ask --pause")
        t.command("print PRIVATE_OUTPUT")
        self.assertIn("\r\n[]\r\n", t.command("ask --context"))
        t.command("ask --resume")
        t.command("print AFTER_RESUME")
        result=t.command("ask --context")
        self.assertIn('"command": "print AFTER_RESUME"',result)
        self.assertNotIn("PRIVATE_OUTPUT",result)
        t.send("zsh\r");t.read_until(b"\x1b[?2004h")
        self.assertIn("\r\n[]\r\n",t.command("ask --context"))
        t.command("print NESTED_PRIVATE")
        t.send("exit\r");t.read_until(b"\x1b[?2004h")
        result=t.command("ask --context")
        self.assertNotIn("NESTED_PRIVATE",result)
        self.assertIn("AFTER_RESUME",result)


class ValidationChecks(unittest.TestCase):
    def test_observed_model_failures_are_withheld(self):
        failed = [{"command": "sw_vers -product", "exit_status": 1}]
        self.assertEqual(helper.valid_command("sw_vers -product", failed)[0], "")
        self.assertEqual(helper.valid_command("sw_vers --productVersion", failed)[0], "sw_vers --productVersion")
        missing = [{"command": "diskpart", "exit_status": 127}]
        self.assertEqual(helper.valid_command("ls -la", missing, reviewing_last=True)[0], "")
        self.assertEqual(helper.valid_command("ls -la", missing)[0], "ls -la")
        self.assertEqual(helper.valid_command("/bin/rm example")[0], "")
        self.assertEqual(helper.valid_command("printf '\u0085'")[0], "")


class ShellPreservation(unittest.TestCase):
    def test_existing_ask_is_preserved(self):
        with tempfile.TemporaryDirectory(prefix="fm-settings-check-") as directory:
            t=Terminal(Path(directory),'ask() { print MY_ASK; }\n')
            try:
                self.assertIn("\r\nMY_ASK",t.command("ask"))
                self.assertEqual(t.calls(),[])
                self.assertIn("Proposed command",t.command('fm-ask "help"'))
                t.command("apple-fm-help-disable")
                self.assertIn("\r\nMY_ASK",t.command("ask"))
            finally:t.close()

    def test_vi_settings_custom_tab_and_disable(self):
        with tempfile.TemporaryDirectory(prefix="fm-settings-check-") as directory:
            t = Terminal(Path(directory), "bindkey -v\nproof-tab() { LBUFFER+='CUSTOM'; }\nzle -N proof-tab\nbindkey -M viins '^I' proof-tab\nsetopt nounset ksharrays\n")
            try:
                self.assertIn("PROOF>", t.startup)
                t.send("print TAB_"); t.send(b"\t\r")
                self.assertIn("\r\nTAB_CUSTOM", t.read_until(b"\x1b[?2004h"))
                result = t.command("[[ -o nounset && -o ksharrays ]] && print OPTIONS_OK")
                self.assertIn("\r\nOPTIONS_OK", result)
                result = t.command('ask "help"')
                self.assertIn("Proposed command", result)
                t.send(b"\t")
                self.assertNotIn("\r\nFM_EXECUTED", t.drain())
                t.send(b"\x03"); t.read_until(b"\x1b[?2004h")
                t.command("apple-fm-help-disable")
                t.send("print RESTORED_"); t.send(b"\t\r")
                self.assertIn("\r\nRESTORED_CUSTOM", t.read_until(b"\x1b[?2004h"))
            finally:
                t.close()


class SetupChecks(unittest.TestCase):
    def test_idempotent_setup_symlink_and_uninstall_preserve_changes(self):
        with tempfile.TemporaryDirectory(prefix="fm-wizard-check-") as directory:
            base = Path(directory)
            home = base/"home"; home.mkdir()
            target = base/"installed"
            actual = base/"actual-zshrc"
            original = b"alias keep='print KEPT'"
            actual.write_bytes(original)
            actual.chmod(0o640)
            (home/".zshrc").symlink_to(actual)
            env = dict(os.environ, HOME=str(home), ZDOTDIR=str(home), APPLE_FM_INSTALL_DIR=str(target), PYTHONDONTWRITEBYTECODE="1")
            install = [str(ROOT/"install.sh"), "--directory", str(ROOT/"build/package"), "--yes"]
            subprocess.run(install, env=env, check=True, capture_output=True)
            before = actual.read_bytes()
            backups = list((target/"backups").iterdir())
            subprocess.run(install, env=env, check=True, capture_output=True)
            self.assertEqual(actual.read_bytes(), before)
            self.assertEqual(list((target/"backups").iterdir()), backups)
            self.assertEqual(actual.stat().st_mode & 0o777, 0o640)
            self.assertTrue((home/".zshrc").is_symlink())
            # An unrelated edit made after setup must survive uninstall.
            actual.write_bytes(actual.read_bytes() + b"export KEEP_AFTER=1\n")
            (target/"keep-user-file").write_text("unrelated")
            subprocess.run([str(ROOT/"install.sh"), "--uninstall", "--yes"], env=env, check=True, capture_output=True)
            self.assertEqual(actual.read_bytes(), original + b"\nexport KEEP_AFTER=1\n")
            self.assertTrue((home/".zshrc").is_symlink())
            self.assertFalse((home/".zshenv").exists())
            self.assertEqual((target/"keep-user-file").read_text(), "unrelated")
            self.assertFalse((home/".local/bin/apple-fm-terminal").exists())

    def test_damaged_block_does_not_modify_other_config(self):
        with tempfile.TemporaryDirectory(prefix="fm-wizard-check-") as directory:
            base=Path(directory); home=base/"home"; home.mkdir()
            (home/".zshenv").write_text("export KEEP=1\n")
            (home/".zshrc").write_text("# >>> apple-fm-terminal ask >>>\nbroken\n")
            env=dict(os.environ, HOME=str(home), ZDOTDIR=str(home), APPLE_FM_INSTALL_DIR=str(base/"installed"))
            result=subprocess.run([str(ROOT/"install.sh"), "--directory", str(ROOT/"build/package"), "--yes"], env=env, capture_output=True)
            self.assertNotEqual(result.returncode,0)
            self.assertEqual((home/".zshenv").read_text(),"export KEEP=1\n")


if __name__ == "__main__":
    unittest.main(verbosity=2)
