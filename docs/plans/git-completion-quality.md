# Git completion quality: invented options (issue #10)

Status: decision report, written 2026-09-25 against `7fd06dc`. Nothing here is implemented. Issue: [#10](https://github.com/StoneHub/apple-fm-terminal/issues/10).

## What happens today

A reply is shown when it passes these checks in `_apple_fm_response` (`apple-fm.zsh:68-89`):

| Check | Source | Proves |
| --- | --- | --- |
| At most 4096 bytes; one line; no control characters | `apple-fm.zsh:76`, `:80` | The text can be displayed and inserted safely |
| Starts with the typed text; the remainder is nonempty | `:82-84` | Tab only appends to what the user typed |
| Adds no destructive command beyond those already typed | `:86-87`, counter at `:20-33` | No added `rm`, `sudo`, `dd`, `mkfs`, recursive `chmod`/`chown`/`chgrp`, forced `git push` or truncating redirect |
| Buffer, cursor, directory and generation unchanged; not dismissed | `:75`, `:138` | The reply belongs to the line on screen |

None of these checks whether an option exists. Both recorded replies pass every check:

- `git sta` → `git status --dirty --show-modified`. The prefix matches and nothing destructive is added, but Git rejects `--dirty` (exit 129).
- `git log --oneline -` → `git log --oneline -l`. The prefix matches, but Git rejects `-l` without a value (exit 129).

When no suggestion is showing, Tab runs the user's original binding, normally zsh's `expand-or-complete` (`apple-fm.zsh:139`). zsh's Git completion already offers options from the installed Git. So abstaining costs the user one ordinary Tab, not the option.

## Evidence gathered for this report

Taken on this runner with Git 2.43.0. Nothing generated was executed; only `git <builtin> --git-completion-helper`, the listing Git's own bash completion uses, was run in a scratch repository.

- `git status` lists 28 entries, including `--short`, `--branch` and `--porcelain`. `--dirty` and `--show-modified` are absent.
- `git log` lists only 15 entries: `--quiet`, `--source`, `--decorate`… Its revision and diff options (`--graph`, `--oneline`, `-n`) are parsed elsewhere and **are not listed**.
- `git stash` lists its subcommands (`push`, `pop`…), not options.
- No builtin lists short options.
- Outside a repository, `git status --git-completion-helper` exits 128.

## Options compared

| Option | How it works | Would it reject the two recorded replies? | False rejections and gaps | Cost |
| --- | --- | --- | --- | --- |
| **A. Prompt change** ("do not add options the user didn't start") | Change `instructions` at `apple-fm.zsh:105` | Unknown: this can only be measured with the real model on a Mac, and the result changes with each model/OS | None structurally; the model can still invent options | One line; unverifiable offline |
| **B. Git's supported option list** | For a Git builtin, allow an added option only if `git <sub> --git-completion-helper` lists it | Yes: `--dirty` is not listed, and `-l` is a short option that can't be verified | Rejects valid `git log --graph`/`--oneline` (not listed), every short option (`git status -s`), and everything outside a repository or for `stash` subcommands. Adds a synchronous `git` fork in the ZLE callback and a per-session cache. Assumes the installed Git has the helper. | ~40 lines plus a cache; depends on Git behavior |
| **C. Abstain on added Git options** | If the line starts with `git`, reject any reply that adds a word starting with `-`, or extends one, before `--` and outside quotes. zsh completion stays available on Tab | Yes, both | Hides valid added options such as `git sta` → `git status --short`; zsh completion still offers them | ~15 lines; no Git calls; no version assumptions |

B is not worth its dependency: Git's own list is incomplete for the log/diff family, and short options can't be checked. C costs some useful option suggestions but never shows an invalid one. zsh already provides the accurate path for options. A can reduce how often C abstains, but only a Mac quality run can show that.

**Recommendation: C, for Git lines only, as one small change.** Leave the prompt alone until the Mac dogfood run below measures how often C abstains.

## Cases

R1 and R2 are the recorded live replies. S1–S9 are authored expectations for rule C, not model measurements.

| # | Typed | Reply | Expected with C | Why |
| --- | --- | --- | --- | --- |
| R1 | `git sta` | `git status --dirty --show-modified` | Abstain (`option`) | Adds options |
| R2 | `git log --oneline -` | `git log --oneline -l` | Abstain (`option`) | Extends the typed `-` into an option |
| S1 | `git stat` | `git status` | Shows `us` → `ok` | Completes the subcommand only |
| S2 | `git sta` | `git status --short` | Abstain (`option`) | Valid but added; zsh completion offers `--short` on the next Tab (loss accepted) |
| S3 | `git commit -m "` | `git commit -m "Fix export guard"` | `ok` | The addition is quoted message text |
| S4 | `git checkout -b feature/` | `git checkout -b feature/export-guard` | `ok` | The user typed `-b`; the addition is its value |
| S5 | `git log --oneline --gr` | `git log --oneline --graph` | Abstain (`option`) | Extends an option word; zsh completion finishes `--graph` |
| S6 | `git push origin main` | `git push origin main --force` | `unsafe` | The existing destructive check runs first |
| S7 | `git -C ../app sta` | `git -C ../app status` | `ok` | The typed global option is unchanged; nothing is added |
| S8 | `git add -- ` | `git add -- -draft.md` | `ok` | After `--`, a word starting with `-` is a path |
| S9 | `docker ps -` | `docker ps -aq` | `ok` (unchanged) | This slice is Git-only; see decision D1 |

## Proposed implementation slice

Owned files: `apple-fm.zsh`, `fixture-fm`, `pty-smoke.exp`, README (one sentence under the checks list).

1. Add `_apple_fm_git_adds_option before full`, following `_apple_fm_risky_count`. It z-splits both lines (`${(z)}`), returns 0 unless the first word is `git`, and treats as added the words after the typed ones plus the last typed word if the reply extends it. It sets `REPLY=1` if any added word before a `--` starts with `-`. A quoted word starts with a quote, so `-m "text -l"` is unaffected.
2. In `_apple_fm_response`, after the destructive check (`:86-87`), set `_APPLE_FM_LAST_OUTCOME=option` and return without showing anything. Explicit requests say "Apple FM left Git options to zsh completion." Add `option` to the outcome list in the comment at `:13`.
3. Teach `fixture-fm` to return R1, R2, S1, S3 and S5 for those typed lines, and add PTY assertions for their outcomes. R1 and R2 must show no suggestion, and Tab on them must fall through to the original binding without inserting the reply.

Acceptance:

- `zsh -n apple-fm.zsh` passes.
- `./pty-smoke.exp` passes as a non-root user, with the existing checks unchanged: cancellation, destructive-output rejection, caller options and bindings, background-job protection, and Tab inserting without executing.
- `git diff --check` is clean.
- On the Mac, run `./dogfood.exp` three times on `dogfood-cases.txt` with the recorded OS/model build. For every `ok` Git line, inspect usability by reading it, without running it. Report `option` abstentions separately from `ok`, `empty` and `mismatch`.
- No suggestion is executed to score it, and no general shell parser is added.

## Linux test finding

On a root runner, `pty-smoke.exp` times out at its first `expect "%"` (line 9). zsh's default prompt ends in `#` for root. Run as an unprivileged user (`runuser -u nobody -- ./pty-smoke.exp`), the full fake-model suite **passed** on Ubuntu 24.04 with zsh 5.9 and Expect 5.45.4. A one-line fix, `expect -re {[%#] }` in `pty-smoke.exp` and `dogfood.exp`, would make both scripts root-safe. It can ride with the slice above or go separately.

## Decisions for the owner

- **D1.** Apply the option rule only to Git (recommended first), or to every command, since zsh completion handles flags generally.
- **D2.** Whether the abstention hint is shown only on explicit requests (as proposed) or never.
- **D3.** Whether to try prompt change A after C, measured with the same dogfood cases.
