# Directory-aware terminal completion: recommendation

Status: proposed design, recorded 2026-09-25 from a 2026-09-24 source review. Implementation has not started. Next step: agree on the literal `cd` scope and permitted-root policy, then validate the collector and insertion approach.

Companion documents: [acceptance cases](acceptance-cases.md) and [later context options](follow-on-context-menu.md).

Start with deterministic completion of a literal directory operand to `cd`. Offer only existing, permitted directories from one explicitly resolved parent. A unique match can use the current gray preview and Tab acceptance. Multiple matches should offer only a common extension, or leave the choice to a bounded candidate list. Do not ask the model to invent or rank paths in this first slice. This makes the feature useful even when model inference is unavailable.

## Verified starting point

Read-only snapshot: terminal `main` at `4c6446edc79c7bf35e9ef13b235576a80b89ce63`; Swift `main` at `d5755b6ab9a64212f2caf5a35707a02f9a8d2c7d`. Both were clean when inspected. Other workers may advance these; implementation must reread current source.

- [Terminal request path](https://github.com/StoneHub/apple-fm-terminal/blob/4c6446edc79c7bf35e9ef13b235576a80b89ce63/apple-fm.zsh#L97) sends shell name, `$PWD`, and the typed left buffer to `/usr/bin/fm respond --model system --no-stream --greedy`. No directory entries, file contents, history, or Swift helper are supplied. Long typed input is currently reduced to its trailing context cap; the new path parser must instead decline overlong input, never classify a truncated command.
- [State and cancellation](https://github.com/StoneHub/apple-fm-terminal/blob/4c6446edc79c7bf35e9ef13b235576a80b89ce63/apple-fm.zsh#L34) already bind requests to PWD, both buffers, cursor, and a generation counter. Response and Tab check that state. They do not detect filesystem replacement beneath an unchanged PWD string.
- [Preview acceptance](https://github.com/StoneHub/apple-fm-terminal/blob/4c6446edc79c7bf35e9ef13b235576a80b89ce63/apple-fm.zsh#L135) appends the suggested suffix, and otherwise calls the saved Tab widget. Enter remains a separate action. Keep that interaction.
- [AppleFMClient](https://github.com/StoneHub/apple-fm-swift/blob/d5755b6ab9a64212f2caf5a35707a02f9a8d2c7d/Sources/AppleFM/AppleFM.swift#L112) already exposes text and caller-schema generation with cancellation and sanitized errors. [CompletionRequest](https://github.com/StoneHub/apple-fm-swift/blob/d5755b6ab9a64212f2caf5a35707a02f9a8d2c7d/Sources/AppleFM/AppleFM.swift#L52) also has optional context. Neither collects directories. The terminal does not call either interface today.

## First slice and module interface

Keep one terminal-owned directory-completion module: `request(snapshot, policy) -> result`. Results are `notApplicable`, `unsupported`, `blocked`, `empty`, `ambiguous`, `ready`, `limited`, or `cancelled`; a ready result includes an append-only insertion plus private candidate identities. The caller owns scheduling, preview, acceptance, and cancellation. Parsing, bounded collection, quoting, and membership validation stay together behind this interface.

Recognize a single simple command whose command word is literal builtin `cd`, with optional `--` and zero or one literal path operand. The cursor must be at the end. Require that `cd` is not shadowed by an alias/function. Support a missing operand after `cd `, relative paths, `./`, `../`, absolute paths, and unquoted `~/`. Resolve only the fully typed parent components, then prefix-match the final component. `cd src/co` lists immediate children of `src`; it never walks `src` recursively. No glob interpretation or fuzzy parent expansion.

Use a non-evaluating lexical parser with explicit unquoted, single-quoted, double-quoted, and escape states. Preserve the exact typed bytes and quote state. Handle spaces, Unicode, apostrophes, and escaped metacharacters as literal filename data. Do not use `eval`, shell expansion, command substitution, or a subshell `cd` to interpret input. Quoted `~` is literal; only the explicitly supported unquoted `~/` form uses the already known home value.

Decline compound commands, redirects, pipelines, variable/substitution syntax, glob syntax, named homes, directory-stack forms (`cd -`, `cd +1`), `cd old new`, flags other than `--`, mixed quote forms that the parser cannot prove, dangling escapes, and closed-quote cases that require rewriting typed text. Initially decline bare relative operands when nontrivial `cdpath` or `CDABLE_VARS` would change their meaning; explicit `./path` can still work. Do not disable the user's options. This is a small grammar with a reliable escape hatch, not a general shell parser.

Route before checking model availability. `notApplicable` retains existing model completion. Recognized `cd` requests, including unsupported or empty ones, must not fall through to unconstrained model path generation. Ordinary native completion remains available for unsupported syntax; a policy-blocked request must not cause the plugin to invoke an unrestricted scanner on the user's behalf.

## Collection policy and hard bounds

Policy is supplied by the terminal, before any filesystem lookup. The initial trial uses explicitly permitted roots rather than implicitly permitting a whole home or repository collection. Caller-designated protected repositories must never be discovered, opened, statted, resolved, or supplied to a model. Obtain exclusion policy from existing configuration rather than searching for protected repositories.

This restriction cannot be met by running `find`, a broad glob, or native `_cd` first and filtering afterward. A directory listing can itself disclose a forbidden child. Permit enumeration only of roots/parents known safe from existing configuration; do not enumerate an ancestor whose children may include the protected repository. If existing configuration cannot establish that a parent is safe, return `blocked` before opening it. A basename filter is insufficient. Broad home/repository-root completion remains outside the initial trial until safe collection policy is supplied.

Reject symlink traversal in the first slice, including ancestor components; do not follow symlink candidates to classify their targets. Walk permitted components through directory handles with no-follow checks, so path replacement cannot redirect collection outside the allowed tree. Normalize `.`/`..` lexically only under this no-symlink rule and reject escapes from allowed roots before probing them. Listing-safe roots need an explicit trust assumption: a newly relocated protected tree must invalidate that policy. A static allowlist cannot promise protection against arbitrary future filesystem rearrangement.

Proposed initial limits, to validate rather than advertise as measured performance:

| Limit | Initial value / behavior |
| --- | --- |
| Breadth | One parent directory, immediate children only |
| Work | At most 256 visited entries and 32 matching directory candidates |
| Data | At most 8 KiB candidate payload; no contents, sizes, owners, timestamps, Git state, or history in results |
| Time | 50 ms worker deadline; UI stays asynchronous; late results are discarded |
| Input | At most 4096 bytes; at most 32 parent components |
| Retention | One active request, in-memory candidates; no persistent cache or path logging |

Use a streaming iterator in a cancellable worker; taking the first 32 results of an already expanded glob does not bound collection work. Count entries before classification, and stop at the limit. If a limit prevents proving the complete match set, return `limited`, with no unique/common-prefix claim from that partial set. A blocked filesystem syscall may not end at 50 ms: the deadline bounds waiting/display eligibility, not kernel latency. Restrict the initial policy to local roots and reap the worker when it exits; do not accumulate replacements behind a stuck collector. Runtime/language choice for the collector is an implementation gate: verify an available packaged dependency, and do not add a Swift framework requirement merely for filesystem access.

Skip hidden names unless the typed final component begins with a dot. Reject control characters, line breaks, invalidly encodable names, and oversized candidates before display. Preserve case and Unicode spelling exactly. Collect only directory identity metadata required for stale-result checks, kept locally; names are untrusted data even when obtained from disk.

## Candidates, quoting, and stale results

Prefer zsh's completion insertion machinery for quoting already bounded, validated candidates. The installed `_cd` also considers `cdpath`, directory-stack state, and other styles, so calling it automatically is not a bounded collector. `_path_files` can expand partial parent paths. Do not install `compinit`, run arbitrary user completers, or change styles as part of this feature. Zsh documents candidate capture and default quoting through `compadd`; these are useful insertion tools, not an assurance of bounded filesystem access. See [Completion Widgets](https://zsh.sourceforge.io/Doc/Release/Completion-Widgets.html) and [Completion System](https://zsh.sourceforge.io/Doc/Release/Completion-System.html).

Before implementation is accepted, prove a side-effect-free way to derive an append-only preview from those candidates in a completion widget. If that requires rewriting the typed prefix or invoking broad completion, suppress the preview for that case. Never assume `compadd -O` returns an already shell-escaped insertion. A small literal suffix encoder is an alternative only for the grammar above, with round-trip shell-argument tests.

For a unique match, construct the path suffix from the actual candidate, retain its directory slash, and close any supported open quote without altering the typed prefix. Leading-hyphen directories require an already typed `./` or `cd --`; never silently insert an option-like operand. For ambiguity, show only an extension shared by the complete candidate set; if none exists, no ghost text. A later bounded menu may receive only those prevalidated names, with no new discovery.

Carry request generation, exact buffers/cursor, logical PWD, allowed-root policy version, parent directory identity, candidate identity, and relevant shell-option snapshot. Recheck after collection, before preview, and immediately before Tab insertion. A renamed/deleted/replaced parent, removed candidate, policy change, or changed shell state clears the suggestion and consumes that stale acceptance attempt without immediately invoking broad completion. Directory handles plus identity checks are required; a PWD string or directory modification timestamp alone is insufficient. Revalidate candidate membership without reading contents. No filesystem check guarantees that a later Enter will still find the same directory; the feature inserts text and does not reserve or execute the target.

Buffer edits, cursor movement, directory changes, Escape, disable, and line finish cancel collection and any model request. Keep one owner for both stages. Directory metadata never becomes shell code; if model selection is explored later, serialize candidates as data with opaque IDs and accept only an exact ID from that request's allowlist. Prompts alone are not an output validator.

## Shared AppleFM and issue #3

No AppleFM framework or helper protocol change is needed. Terminal owns intent, filesystem access, exclusions, caps, shell quoting, deadlines, and accepted-path validation. The existing generic `generate` interface is sufficient for a future caller-owned selection schema; candidate membership remains the caller's responsibility. The terminal's CLI whole-line protocol differs from the helper's insertion protocol, so changing the helper prompt would not improve this terminal path today.

[Issue #3](https://github.com/StoneHub/apple-fm-terminal/issues/3), verified open during this review, concerns partial command words after a pipe: `xarg` does not become `xargs`, and the `jq` case can return a nonmatching prefix. Neither is a directory operand. Keep that issue separate and run its ten existing dogfood cases for regressions when implementing this feature. Directory work must not claim to resolve #3 or expand into arbitrary command validation. The current destructive-token heuristic is not a shell safety proof; this slice avoids relying on it by constructing only a literal path operand.

Recommendation for discussion: approve the deterministic `cd` slice and a small set of permitted personal roots first. Broader filesystem context and model ranking should wait for evidence that they improve on native candidate selection. Acceptance cases and possible later context sources are in the companion documents.
