# Terminal prototype status

State: buildable local prototype, awaiting parent review.

Commit: see `git rev-parse HEAD` after commit.

Artifact: `apple-fm.zsh` (source directly; no installer and no `.zshrc` mutation).

Run/install:

```zsh
source /Users/monroe/Developer/GitRepos/FM/terminal/apple-fm.zsh
apple-fm-enable
```

Disable/remove:

```zsh
apple-fm-disable
apple-fm-remove
```

Checks run:

* `zsh -n apple-fm.zsh` passed.
* `/usr/bin/fm respond --help` inspected on macOS 27 build supplied by parent; stdin, `--model system`, `--no-stream`, `--greedy`, and `--instructions` are supported.
* Live on-device smoke through stdin completed: `printf` prefix request returned a single-line suffix (`%s`).
* PTY smoke script `pty-smoke.exp` exercised source/enable, explicit trigger, Tab, and Ctrl-C cleanup. Terminal output is noisy under this desktop PTY, so visible suggestion text and model wording were not treated as a quality gate.

Limitations: only an end-of-line single command is supported; output is deliberately rejected when multiline or containing terminal control bytes. The CLI response is request-scoped and stale state is discarded. Autosuggestion key conflicts depend on shell load order and should be checked alongside any existing plugin.

Owned background processes: request and debounce children are tracked and killed when superseded or disabled. No persistent process, server, login item, or watcher is left running.
