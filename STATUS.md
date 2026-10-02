# Current checkpoint: 0.1.1

Git suggestions that add or finish an option now abstain, leaving ordinary zsh completion available. PR #11 was checked on macOS 27.2 (26B5086k), zsh 5.9, with the real on-device `/usr/bin/fm`. Three runs of the ten declared dogfood cases produced 6 option abstentions (both Git option cases each run), 18 accepted previews, 3 unsafe refusals and 3 prefix mismatches. The quoted commit-message case produced a usable inserted message in all three runs. No generated command was executed. Accepted non-Git previews are not a general command-quality guarantee.

The full fixture-backed PTY smoke passed, including Tab insertion without execution, cancellation, stale requests and original binding restoration. Local archive installation is separate from publication; no public release was created.

# Unreleased: Ctrl-C and removal

Pressing Ctrl-C while a suggestion was visible left the gray suffix printed in the scrollback, because zsh skips `line-finish` on an interrupt. Copied out of Terminal, it reads as typed text. The plugin now installs a `TRAPINT` that clears the suggestion. It does this only when the shell has no INT trap of its own, and `apple-fm-disable` removes it. `apple-fm-remove` never worked before this fix: it passed `_apple_fm_*` to `unfunction` as a filename glob, which failed with no matches. It now matches function names. `install.sh --uninstall` and `apple-fm-uninstall` remove the `.zshrc` block and the installed files. Reinstalling no longer adds a blank line to `.zshrc` each time.

Checked on Linux (zsh 5.9, Expect, fake model): `./pty-smoke.exp` passes, and its new Ctrl-C case fails without the fix. Install into a temporary home (with `uname` and `/usr/bin/fm` stubbed), then reinstall: the zshrc is identical after both. `apple-fm-uninstall` restores it byte for byte and leaves no plugin functions or bindings. This has not been tried in Terminal.app with the real model, and a slow or garbled prompt reported there has not been reproduced.

# Unreleased: request-key restoration

Changing `APPLE_FM_TRIGGER` while enabled previously left `fm-suggest` bound to the old key and restored its original binding onto the new key. The plugin now captures the request key for each enable/disable cycle. An active repeated enable is still a no-op; the next enable uses the new setting. Disable and remove restore the key actually bound, leaving the next configured key alone.

Checked on Linux with zsh 5.9 and Expect 5.45.4: `./pty-bindings.exp` fails on the previous code and passes three consecutive runs on the fix. It checks both keymaps, configuration changes while enabled, repeated enable, re-enable with the new trigger, Tab insertion without execution, removal and preservation of `nounset`/`ksharrays`. `zsh -n apple-fm.zsh`, `sh -n install.sh package-release.sh` and `git diff --check` pass. The unchanged full `./pty-smoke.exp` intermittently stalls after a rapid Ctrl-C on both the prior code and this fix; that remains a separate verification gap. This change has not yet been accepted in Terminal.app with the real model and does not resolve issue #12's mid-line corruption report.

# Terminal prototype status

Parent Astra reviewed; ready for a local trial on this Mac. Use `git rev-parse HEAD` for the current local checkpoint.

## Try and remove

For an isolated trial, start `zsh -f` in Terminal, then:

```zsh
source /Users/monroe/Developer/GitRepos/FM/terminal/apple-fm.zsh
apple-fm-enable
```

Pause after typing a prefix, or press Ctrl-X then Ctrl-F. Tab accepts the visible suffix; Enter is still required to execute. Escape dismisses. `apple-fm-disable` restores captured bindings. `exit` closes the isolated trial shell. No .zshrc edit or persistent install is performed.

## Evidence

On macOS 27.0 (26A428), parent ran a real interactive zsh PTY:

- Automatic fixture preview appeared with its leading space.
- Before Tab: buffer `alpha`, preview ` suffix`. After Tab: buffer `alpha suffix`, no execution.
- Delayed request followed by Escape left buffer `SLOW` with no suggestion.
- The assertion harness passed preview, whitespace, insertion without execution, dismissal, binding restoration, and stderr preservation. Run `./pty-smoke.exp` from a terminal (it requires an outer TTY).
- Live `/usr/bin/fm respond --model system --no-stream --greedy --instructions ...` read its prompt from stdin. A real preview appeared and was inserted without execution. Its wording was poor (`git sta` plus `--all`); this is integration evidence, not a claim of model quality.
- `zsh -n apple-fm.zsh` and `git diff --check` passed.

## Limits

End-of-buffer single-line completion only; CLI backend only. Swift integration is deferred. Other autosuggestion plugins were not exercised; use the isolated shell for the first trial. The CLI result passes through a private transient file that is removed on response/cancellation; prompts and shell history are not saved. Forced shell termination can interrupt cleanup. Exact suggestion quality and normal Terminal.app visual polish remain Monroe's trial.

All parent-owned PTY sessions are closed. No server, login item, watcher, or persistent inference process is required.

## Local release checkpoint

Commit: `ebb6d30` (with the release packaging commit `3dfbc87` immediately before it).

Build local release assets with `./package-release.sh [dist-directory]`. This emits
`apple-fm-terminal-0.1.0.tar.gz`, the stable-download alias
`apple-fm-terminal.tar.gz`, `install.sh`, and a fresh `SHA256SUMS` manifest. The
packager refuses tracked worktree changes; publishing these assets remains a
separate parent-owned step.

Install or update on a supported Mac with `/usr/bin/fm`:

```zsh
curl -fsSL https://github.com/StoneHub/apple-fm-terminal/releases/latest/download/install.sh | sh
```

The installer uses no sudo, installs to `~/.local/share/apple-fm-terminal`, and
adds an idempotent marked block to `${ZDOTDIR:-$HOME}/.zshrc`. New shells provide
`apple-fm-update` and `apple-fm-version`. A local artifact trial uses
`HOME=/tmp/test-home ZDOTDIR=/tmp/test-home/zsh APPLE_FM_INSTALL_DIR=/tmp/test-home/data/apple-fm-terminal ./install.sh --archive ... --checksums ...`.
To remove the installation, run `apple-fm-uninstall` (or `install.sh --uninstall`). Installs
from 0.1.1 or earlier don't have that command: delete the marked block from the selected zshrc
and remove `~/.local/share/apple-fm-terminal`, then open a new window.

Checks run: `sh -n install.sh package-release.sh`, `zsh -n apple-fm.zsh`,
`git diff --check`, package generation, checksum-verified temporary-home install,
second-install idempotence, zshrc parse, and a temporary-home `apple-fm-version`
read. The temporary-home path included an apostrophe to exercise shell quoting.
No background processes remain.
