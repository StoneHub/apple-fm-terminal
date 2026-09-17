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
To remove the installation, delete only the marked block from the selected zshrc
and remove `~/.local/share/apple-fm-terminal` after closing shells using it.

Checks run: `sh -n install.sh package-release.sh`, `zsh -n apple-fm.zsh`,
`git diff --check`, package generation, checksum-verified temporary-home install,
second-install idempotence, zshrc parse, and a temporary-home `apple-fm-version`
read. The temporary-home path included an apostrophe to exercise shell quoting.
No background processes remain.
