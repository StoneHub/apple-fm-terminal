# Possible context after literal cd completion

This is a menu for discussion, not an implementation backlog or an approval to collect more data.

| Order | Context | Value and constraint |
| --- | --- | --- |
| 1 | Bounded choice list for ambiguous directory candidates | Useful without a model. Reuse the same permitted snapshot; no second discovery pass or broad completion fallback. |
| 2 | More directory-taking commands, such as `pushd` | Add one documented operand grammar at a time. Keep stack syntax and shell options explicit. |
| 3 | Explicit file operands for a small command allowlist | One parent and typed prefix, names/types only. Distinguish source from destination operands; never treat missing output paths as invalid by default. |
| 4 | Command-name candidates after pipes | Address issue #3 separately with bounded shell command candidates. Do not enumerate all PATH roots without policy. Preserve exact typed prefix; choosing a command is not validating its arguments. |
| 5 | Current-repository branch names and coarse Git state | Separate opt-in and permitted repo identity; no cross-repo scan, diff, commit messages, remote calls, or protected work metadata. |
| 6 | A selected project task list | Read only explicitly permitted manifest fields after content access is separately approved. Do not auto-run project scripts. |
| 7 | Session-local recent directories | Use only directories the feature has already been allowed to observe. No shell-history import or persistent trail by default. |
| 8 | Model selection among known candidates | Require evidence of improved choices. Send bounded serialized labels and opaque IDs; accept only an exact candidate ID; keep all collection and insertion validation terminal-owned. |

Avoid a recursive “real tree,” whole-home index, automatic README ingestion, unrestricted history, and global Git discovery. Each new source should answer a concrete completion question and carry its own access policy, size/time bound, invalidation rule, and demonstrable benefit over existing zsh completion.
