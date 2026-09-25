# Acceptance cases for the proposed directory slice

These are future implementation requirements, not tests run by this design task. Use a synthetic temporary tree and a spy filesystem adapter; do not use real personal or work directories for negative tests. Assert zero filesystem calls for forbidden or unresolved policy targets, not merely an empty displayed result.

| Case | Required outcome |
| --- | --- |
| `cd pro` with only directory `projects` matching | Preview `jects/`; Tab produces `cd projects/`; no execution |
| Same prefix with a regular file and a directory | Only the directory can be suggested; file contents never opened |
| `cd src/co` | Only one listing of the fully typed `src` parent; no descendants enumerated |
| `cd `, `cd ./`, `cd ../`, `cd /allowed/pa`, `cd ~/allowed/pa` | Work only if resolved parent is permitted; bare home and broad ancestors are not implicitly permitted |
| `cd pro` with `projects` and `prototypes` | No arbitrary winner; only proven common extension, if any |
| `cd "My P` with `My Projects` | Typed bytes preserved; completed operand decodes to that exact path, including slash; quote is closed |
| Escaped spaces; single-quoted names with apostrophes; Unicode | Literal argument round-trip preserves exact name; unsupported lexical forms decline without guessing |
| Names containing `$()`, backticks, `;`, `*`, quotes | Escaped candidate insertion stays one literal operand; no command/expansion executes |
| Name beginning `-` | Accepted only with `./` or preceding `--`; no accidental `cd` flag |
| Hidden name | Considered only for a dot-prefixed final component |
| Newline/control/invalid encoding in name | Omitted from preview/list; cannot corrupt ZLE or transport |
| Typed `$HOME/x`, substitution, glob, stack operand, extra operand, pipe, redirect | No directory collection; no evaluation; appropriate unsupported/not-applicable routing |
| Alias/function named `cd`; nontrivial `cdpath` | Decline semantics the slice cannot establish; explicit relative path can bypass only supported lookup ambiguity |
| Denied target or uncertain broad parent | Zero open/stat/readdir/readlink calls; no model request carrying path context; no automatic fallback scanner |
| Symlink parent or candidate; `..` escape | No target traversal, no metadata read from target; reject before crossing permitted root |
| 257 entries, 33 candidates, oversized payload | Stop within budget, mark limited, never infer uniqueness from truncated results |
| Permission failure or unavailable directory | Quiet no suggestion on automatic request; short reason on explicit request |
| Slow/stuck enumeration | UI remains responsive; deadline invalidates result; one owned collector, no unbounded backlog |
| Edit, cursor movement, Escape, disable, line finish during scan | Cancel; delayed callback cannot restore preview; worker eventually reaped |
| Same PWD string but parent replaced, candidate removed, or root policy changed | Discard before display or Tab; stale Tab does not insert old suffix or run unrestricted fallback |
| Directory changed after Tab, before Enter | No execution by plugin; ordinary shell behavior at Enter, with no stronger guarantee claimed |
| Model missing, exits nonzero, or unavailable | Eligible deterministic `cd` suggestions still function without CLI invocation |
| Existing `alpha`, whitespace, Tab, Escape, cancellation and keybinding fixtures | Current PTY behavior remains intact; shell options and unrelated jobs remain untouched |
| Existing ten dogfood cases, including `xarg`/`jq` | No new directory data sent for these inputs; record baseline and after results separately; #3 stays separately owned |

Test through the terminal module interface and interactive ZLE acceptance. Quoting tests must inspect resulting argument bytes using a harmless recording command in an isolated shell, never execute filenames or model text. Include open-quote and shell-option cases in PTY tests. Record collection counts and cancellation outcomes without retaining real path names. A fake malicious candidate/model fixture should prove that membership and literal-argument validation hold independently of prompt wording.
