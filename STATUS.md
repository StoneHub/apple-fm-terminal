# Terminal prototype status

State: buildable local prototype, awaiting parent review.

Commit: pending the lifecycle repair commit.

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
* `zsh -n apple-fm.zsh` passes after the lifecycle repair.
* A real `zsh -dfi` PTY sourced and enabled the repaired plugin successfully.

Limitations: only an end-of-line single command is supported; output is deliberately rejected when multiline or containing terminal control bytes. Requests are generation-bound to the prompt state, cancel their bridge child on edits, Escape, replacement, disable, and timeout, and are capped at 15 seconds. The Swift backend is deferred; this is CLI-only. The existing PTY harness is a liveness check and still needs deterministic fixture assertions for leading-space fidelity, stale/dismissal suppression, and binding restoration before parent review can call the prototype ready.

Owned background processes: request and debounce children are tracked and killed when superseded or disabled. No persistent process, server, login item, or watcher is left running.
