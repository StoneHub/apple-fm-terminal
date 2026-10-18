# Apple FM Terminal

Ask questions in your normal zsh session using Apple's on-device model. Review an
explanation and one proposed command, press **Tab to insert**, and press **Enter
separately to execute**. Jot is not required.

## Downloadable preview candidate

Version **0.3.0-preview.1** is prepared locally; it is **not published**. The latest
public 0.1.0 release is the older autocomplete prototype, not this experience.

Runtime requirements: **macOS 26 or later**, **Apple Silicon**, native execution
(not Rosetta), zsh, and Apple Intelligence enabled with its model downloaded.
**No Xcode, developer tools, Python installation, Jot, or paid API account is
required by users.** A private CPython runtime is included in this package.

After publication, the normal workflow will be:

1. Download the preview disk image and open it.
2. Open **Install.command** to start the Terminal setup wizard.
3. Review the managed shell changes and enable setup.
4. Open a new Terminal tab and type `ask "How can I list attached disks?"`.
5. Review the proposal, press Tab to insert it, then Enter to run it.

For local candidate review, the same wizard is available in the staged folder:

```sh
./build/package/Install.command
# Or install the exact archive with its checksum:
sh dist/install.sh --archive dist/apple-fm-terminal.tar.gz --checksums dist/SHA256SUMS
```

The current local candidate has not completed Developer ID signing and
notarization. It must complete those steps before public distribution; the
release procedure is in [docs/preview-release.md](docs/preview-release.md).
The installer checks hardware and OS support before unpacking and checks model
readiness before changing shell files. If Apple Intelligence is not ready, finish
setup in System Settings and run `apple-fm-terminal setup` again. Uninstall also
works when shell setup was cancelled or model readiness prevented activation.

The install wizard previews and confirms the managed shell changes. `--yes`
applies that displayed setup without prompting. It installs the package under
`~/.local/share/apple-fm-terminal` and links `~/.local/bin/apple-fm-terminal`.
No sudo, login item or always-running model process is needed.

The wizard prepends a guarded block to your startup `.zshenv` and appends the
help bridge to your active `.zshrc`. Your original startup content runs once in
the captured shell, including normal login/profile behavior. Your prompt, aliases,
options and history settings are retained. Only ready proposals consume Tab;
ordinary completion uses the binding captured from your shell. Both emacs and
vi insert mode are supported. If `ask` already belongs to you, it is preserved;
use `fm-ask` or the shortcut instead.

Existing files receive private backups only when they actually change. Symlinks
and file permissions are preserved. Repeating setup is idempotent. Malformed
managed blocks are refused before any shell file is changed. For a custom active
`ZDOTDIR`, pass `--config-dir PATH` to `apple-fm-terminal setup` if it is not exported.

Open a new Terminal tab/window after setup. Existing shells are left alone. The
prototype's separate clean shell is no longer the main workflow.

## Use

```text
ask "Why did the last command fail?"
ask "How can I list attached disks?"
ask
ask --context
ask --clear
ask --pause
ask --resume
```

- **Ctrl-X then ?**: use the current buffer as the question, or ask about the last
  command when it is empty. Your buffer remains intact until you accept.
- **Tab**: replace the unchanged buffer with the reviewed command. It never
  executes the command. Enter without accepting does not execute a preview.
- **Enter**: execute the text actually in the shell buffer, as usual.
- **Escape** or editing: dismiss the preview. Typing/Ctrl-C during generation
  cancels it, so queued Tab/Enter cannot accept an unseen answer.
- A simple missing command offers the shortcut without starting the model.

```text
apple-fm-terminal doctor
apple-fm-terminal setup
apple-fm-terminal disable
apple-fm-terminal uninstall
```

`doctor` reports the version, interpreter, native model readiness and managed
setup. `apple-fm-help-disable` disables help immediately in the current shell and
restores bindings it still owns; `disable` removes the managed startup blocks for
future shells. `uninstall` additionally removes inventoried package files and its
backup copies, preserving unrelated files/edits. `APPLE_FM_DISABLE=1 zsh` starts
an ordinary shell without capture or help.

## Context and privacy

Each open assisted shell has one Python controller using the private bundled runtime, a local socket,
and its normal zsh. The Swift model helper runs only while you explicitly ask.
It uses the AppleFM library's typed availability and structured-generation calls.
Deadlines, one-request concurrency, prompts and command validation belong here
in Terminal. Model availability checks do not generate text.

Context stays in memory: up to five completed commands, working directories,
exit statuses and at most 1,800 characters of output each, with a 7,000-character
JSON request budget. No prompts, replies, commands or terminal output are written
to generation logs. One private temporary directory contains only the session
socket and is removed on normal exit. A forced kill can leave that small directory
behind; it contains no retained context. Apple's own model memory is separate.

`ask --context` shows what will be included; `ask --clear` forgets it. `--pause`
clears context and stops capture until `--resume`. Help answers and previews are
excluded from future context. Nested shells, SSH sessions and common full-screen
programs are excluded from the parent shell's capture. Script output can be
included as output of the top-level script invocation, but scripts do not invoke
help or run model requests. There is no general secret detector: pause before
commands whose output you do not want included in subsequent local requests.

The shell bridge is scoped to its exact interactive shell PID. It does not load
for noninteractive scripts, `zsh -c`, pipelines or pasted command blocks, and
`ask` refuses calls from sourced scripts, functions, loops and substitutions.
Command output remains attached to a real TTY; it is not redirected through tee.
On a supported remote Mac, setup belongs on that Mac; SSH transport still needs
an actual device trial.

## Model quality

A structured answer is not proof of command correctness. The helper checks that
an executable exists, rejects shell operators/control characters and unchanged
failed commands, and withholds known privileged/destructive commands. Specific
checks cover the observed ambiguous `sw_vers` and unrelated `diskpart` proposals.
Other flags and effects still need your review. The model may clarify or abstain.

The functional prototype is preserved on branch `prototype/terminal-ask-session`.
Native testing repaired `sw_vers -product` using captured usage output, inserted
`sw_vers --productVersion` with Tab, and ran it only after a separate Enter.

## Development and packaging

Build hosts need Xcode 27 / Swift 6.4 and Python 3.9+. These are developer
requirements only. Generation uses the existing
[AppleFM Swift library](https://github.com/StoneHub/apple-fm-swift) pinned to
`5b937241b0236f892af28588e75a78dd557acf21`, with no `/usr/bin/fm` or cloud fallback.

```sh
./scripts/build-install.sh --build-only
PYTHONDONTWRITEBYTECODE=1 python3 tests/check.py
python3 -B tests/packaging.py
./scripts/prepare-preview.sh
python3 -B tests/preview.py
```

`build/` holds disposable compiler/staging/download outputs. `dist/` holds the
reviewable disk image, archives, installer and SHA256SUMS. The private runtime is
pinned and checksum-verified from
[python-build-standalone](https://github.com/astral-sh/python-build-standalone/releases/tag/20261013).
Its interpreter, standard library, dependency license texts and provenance ship
inside `runtime/`. It adds no system-wide Python, pip commands or PATH entries.
Build-time downloads are not needed during local archive/disk image installation.
The candidate is approximately 22 MB as a tar archive, 29 MB as a disk image and
58 MB installed. Sizes vary with builds and signing.

The legacy suffix plugin remains in `apple-fm.zsh` for existing source consumers;
the wizard removes only its recognized old managed block during migration and
installs request-only Terminal Ask. It does not enable both Tab handlers.
