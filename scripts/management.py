#!/usr/bin/env python3
"""Install wizard and removal for owned zsh blocks. No model or terminal content logs."""
import argparse
import json
import os
from pathlib import Path
import shlex
import shutil
import stat
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parent.parent
STATE = ROOT / "setup-state.json"
START = b"# >>> apple-fm-terminal ask >>>\n"
END = b"# <<< apple-fm-terminal ask <<<\n"
LEGACY_START = b"# >>> apple-fm-terminal >>>\n"
LEGACY_END = b"# <<< apple-fm-terminal <<<\n"


def strip(data, start=START, end=END):
    if data.count(start) != data.count(end) or data.count(start) > 1:
        raise ValueError("Incomplete or repeated managed block; repair it before setup/removal.")
    if start not in data:
        return data
    first = data.index(start)
    last = data.index(end, first) + len(end)
    if first and data[first-1:first] != b"\n":
        raise ValueError("Managed block is not on its own line.")
    return data[:first] + data[last:]


def atomic(path, data, mode=None):
    # Follow the user's existing symlink without replacing it. The replacement
    # file is created beside the actual target so rename is atomic.
    target = path.resolve() if path.is_symlink() else path
    target.parent.mkdir(parents=True, exist_ok=True)
    original_mode = stat.S_IMODE(target.stat().st_mode) if target.exists() else 0o600
    fd, name = tempfile.mkstemp(prefix=".apple-fm-write-", dir=target.parent)
    try:
        with os.fdopen(fd, "wb") as file:
            os.fchmod(file.fileno(), mode if mode is not None else original_mode)
            file.write(data)
        os.replace(name, target)
    finally:
        if os.path.exists(name):
            os.unlink(name)


def blocks():
    python = shlex.quote(str(ROOT/"runtime/bin/python3") if (ROOT/"runtime/bin/python3").is_file() else sys.executable)
    session = shlex.quote(str(ROOT / "terminal-session"))
    bridge = shlex.quote(str(ROOT / "shell" / "help.zsh"))
    helper = shlex.quote(str(ROOT / "apple-fm-terminal-model"))
    # Intercept before user .zshenv/.zprofile/.zshrc content runs. The inner shell
    # gets its actual PID, preventing recursion and giving nested shells their own session.
    env = f'''if [[ -o interactive && ${{+ZSH_EXECUTION_STRING}} == 0 && ${{ZSH_ARGZERO:t}} == (zsh|-zsh) && -t 0 && -t 1 && -z ${{APPLE_FM_DISABLE:-}} && ${{APPLE_FM_SESSION_PID:-0}} != $$ ]]; then
  if [[ -x {python} && -r {session} && -x {helper} ]]; then
    typeset -a _apple_fm_login_args=()
    [[ -o login ]] && _apple_fm_login_args=(--login)
    {python} -I -B {session} "${{_apple_fm_login_args[@]}}"
    _apple_fm_session_status=$?
    if (( _apple_fm_session_status != 125 )); then
      builtin exit $_apple_fm_session_status
    fi
    unset _apple_fm_login_args _apple_fm_session_status
    print -u2 -- 'Apple FM unavailable; continuing with your ordinary shell.'
  fi
fi
'''
    rc = f'''if [[ -o interactive && ${{APPLE_FM_SESSION_PID:-0}} == $$ && -S ${{APPLE_FM_SESSION_SOCKET:-}} && -r {bridge} ]]; then
  source {bridge}
fi
'''
    return START + env.encode() + END, START + rc.encode() + END


def load_state():
    return json.loads(STATE.read_text()) if STATE.exists() else {"files": [], "backups": []}


def setup(args):
    if not (ROOT / "apple-fm-terminal-model").is_file():
        raise ValueError("Build/install the Swift model helper before running setup.")
    if os.uname().machine != "arm64":
        raise ValueError("This preview requires an Apple Silicon Mac running natively (not under Rosetta).")
    readiness = subprocess.run([str(ROOT/"apple-fm-terminal-model"), "--availability"], capture_output=True, text=True, timeout=8)
    try:
        available = json.loads(readiness.stdout).get("availability")
    except ValueError:
        available = "unknown"
    if available != "available":
        raise ValueError("Apple Intelligence is not ready (" + str(available) + "). Enable it in System Settings and finish the model download, then run setup again. Shell files were not changed.")
    home = Path.home()
    config = Path(args.config_dir or os.environ.get("ZDOTDIR", str(home))).expanduser().resolve()
    bootstrap_dir = Path(os.environ.get("ZDOTDIR", str(home))).expanduser().resolve()
    env_file, rc_file = bootstrap_dir / ".zshenv", config / ".zshrc"
    env_block, rc_block = blocks()
    state = load_state()
    changes = []
    records = {r["path"]: r for r in state["files"]}
    for path, block, prepend in [(env_file, env_block, True), (rc_file, rc_block, False)]:
        if path.is_symlink() and not path.exists():
            raise ValueError(str(path) + " is a dangling symlink; it was not changed.")
        old = path.read_bytes() if path.exists() else b""
        clean = strip(old)
        if path == rc_file:
            clean = strip(clean, LEGACY_START, LEGACY_END)
        record = records.get(str(path), {"path": str(path), "created": not path.exists(), "separator": False})
        if not prepend and START not in old:
            record["separator"] = bool(clean and not clean.endswith(b"\n"))
        new = block + clean if prepend else clean + (b"\n" if clean and not clean.endswith(b"\n") else b"") + block
        if old != new:
            changes.append((path, old, new))
        records[str(path)] = record
    print("Apple FM Terminal setup")
    print("  Inference: shared AppleFM Swift library; on device only")
    print("  Session transport: Python " + sys.version.split()[0] + " (" + sys.executable + ")")
    print("  Context: five recent commands and bounded output in memory; no content logs")
    try:
        availability = subprocess.run([str(ROOT/"apple-fm-terminal-model"), "--availability"], capture_output=True, text=True, timeout=8)
        print("  Model readiness:", json.loads(availability.stdout).get("availability", "unknown"))
    except (ValueError, OSError, subprocess.TimeoutExpired):
        print("  Model readiness could not be checked; use apple-fm-terminal doctor.")
    print("  Help: ask or Ctrl-X then ?; Tab inserts, Enter executes separately")
    print("  Shell: keep your existing prompt, options, aliases, history and completion")
    for path, old, new in changes:
        print("  " + ("Update " if path.exists() else "Create ") + str(path) + " (managed block only)")
    if not changes:
        print("Already configured; no files or backups added.")
        return
    print("Existing files will be backed up privately before changes.")
    if not args.yes and input("Enable this setup? [Y/n] ").strip().lower() not in ("", "y", "yes"):
        print("Setup cancelled; shell files unchanged.")
        return
    backup_dir = ROOT / "backups"
    backup_dir.mkdir(mode=0o700, exist_ok=True)
    backups = list(state["backups"])
    written = []
    try:
        for path, old, new in changes:
            if path.exists():
                backup = backup_dir / (path.name + "." + str(time.time_ns()))
                atomic(backup, old, 0o600)
                backups.append(str(backup))
            existed = path.exists()
            atomic(path, new)
            written.append((path, old, existed))
        atomic(STATE, json.dumps({"files": list(records.values()), "backups": backups}, indent=2).encode())
    except BaseException:
        for path, old, existed in reversed(written):
            if existed:
                atomic(path, old)
            else:
                path.unlink(missing_ok=True)
        raise
    print("Ready. Open a new Terminal window or tab. Existing shells remain unchanged.")


def remove(args):
    state = load_state()
    if not state["files"] and args.command != "uninstall":
        print("No managed shell setup found.")
        return
    changes = []
    for record in state["files"]:
        path = Path(record["path"])
        if not path.exists():
            continue
        old = path.read_bytes()
        new = strip(old)
        if record["separator"] and old.endswith(END) and new.endswith(b"\n"):
            new = new[:-1]
        if old != new:
            changes.append((path, new, record["created"] and not new))
    print("Remove Apple FM's managed shell blocks; keep all other shell content.")
    if not args.yes and input("Continue? [y/N] ").strip().lower() not in ("y", "yes"):
        return
    for path, data, delete in changes:
        if delete:
            path.unlink()
        else:
            atomic(path, data)
    if args.command == "uninstall":
        link = Path.home()/".local/bin/apple-fm-terminal"
        if link.is_symlink() and link.resolve() == ROOT/"apple-fm-terminal":
            link.unlink()
        for backup in state["backups"]:
            path = Path(backup)
            if path.parent == ROOT/"backups":
                path.unlink(missing_ok=True)
        # Delete the installed payload's inventory only, never unrelated files.
        inventory = ROOT/"installed-files.json"
        if inventory.exists():
            for relative in json.loads(inventory.read_text()):
                target = ROOT/relative
                if target.resolve().is_relative_to(ROOT) and target.is_file():
                    target.unlink()
            inventory.unlink()
        STATE.unlink(missing_ok=True)
        for directory in sorted((p for p in ROOT.rglob('*') if p.is_dir()), key=lambda p: len(p.parts), reverse=True):
            try:
                directory.rmdir()
            except OSError:
                pass
        try:
            ROOT.rmdir()
        except OSError:
            pass
    print("Removed. New shells use your ordinary configuration. Existing sessions are left running.")


def doctor():
    helper = ROOT/"apple-fm-terminal-model"
    print("Version:", (ROOT/"VERSION").read_text().strip())
    print("AppleFM revision: 5b937241b0236f892af28588e75a78dd557acf21")
    print("Python:", sys.version.split()[0], sys.executable)
    print("Model helper:", helper)
    if helper.is_file():
        try:
            result = subprocess.run([str(helper), "--availability"], capture_output=True, text=True, timeout=8)
            value = json.loads(result.stdout)
            print("On-device model:", value.get("availability", "unknown"))
        except (ValueError, OSError, subprocess.TimeoutExpired):
            print("On-device model: availability check failed")
    else:
        print("On-device model: helper not installed")
    state = load_state()
    for record in state["files"]:
        path = Path(record["path"])
        print("Shell block:", path, "present" if path.exists() and START in path.read_bytes() else "missing")
    print("Privacy: session context stays in memory; no prompt/answer logs; no cloud fallback.")


def main():
    parser = argparse.ArgumentParser(description="Apple FM Terminal setup and health")
    parser.add_argument("--version", action="version", version=(ROOT/"VERSION").read_text().strip())
    parser.add_argument("command", nargs="?", default="doctor", choices=["setup", "doctor", "disable", "uninstall", "version"])
    parser.add_argument("--yes", action="store_true", help="apply the displayed managed changes without prompting")
    parser.add_argument("--config-dir", help="directory containing your active .zshrc (custom ZDOTDIR)")
    args = parser.parse_args()
    if args.command == "setup": setup(args)
    elif args.command in ("disable", "uninstall"): remove(args)
    elif args.command == "doctor": doctor()
    else: print((ROOT/"VERSION").read_text().strip())


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, EOFError, KeyboardInterrupt, subprocess.TimeoutExpired) as error:
        print("Apple FM:", str(error) or "Setup cancelled.", file=sys.stderr)
        sys.exit(1)
