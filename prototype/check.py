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

ROOT = Path(__file__).resolve().parent
loader = importlib.machinery.SourceFileLoader("terminal_help", str(ROOT / "terminal-help"))
spec = importlib.util.spec_from_loader(loader.name, loader)
helper = importlib.util.module_from_spec(spec)
loader.exec_module(helper)


class Terminal:
    def __init__(self, scratch):
        self.log = scratch / "calls.jsonl"
        fake = scratch / "fixture-fm"
        fake.write_text("#!/usr/bin/env python3\n" + '''
import json, os, sys, time
request = json.load(sys.stdin)
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
        self.process = subprocess.Popen([str(ROOT / "terminal-help")], stdin=slave, stdout=slave, stderr=slave,
                                        env=dict(os.environ, APPLE_FM_COMMAND=str(fake), FM_TEST_LOG=str(self.log),
                                                 TERM="xterm-256color", PYTHONDONTWRITEBYTECODE="1"),
                                        start_new_session=True)
        os.close(slave)
        self.pending = b""
        self.read_until(b"Model requests are explicit.")
        self.read_until(b"\x1b[?2004h")

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
            try:
                self.process.wait(timeout=4)
            except subprocess.TimeoutExpired:
                self.process.terminate()
                self.process.wait(timeout=3)
        os.close(self.master)


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


if __name__ == "__main__":
    unittest.main(verbosity=2)
