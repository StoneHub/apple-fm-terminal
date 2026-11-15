---
name: council
description: Use when the user says "council", or council with a score such as "full stop with council 9". Thorough code review by three read-only Claude reviewers with different jobs, each scoring the change; the author fixes real findings, capped at three rounds.
---

# Council

Adapted from Theo Browne's `council` in t3dotgg/tstack (MIT). Theo seats one
model from each of three providers. This version runs on Claude alone, so it
gets its spread from different models and different jobs instead. It also
adds a hard round cap, diff-only re-review, and a reviewer that runs the code.

## 0. Before convening

- Finish the change. Address open PR comments, fix known issues, run the
  repo's checks. Give the council the version you believe is done.
- Commit the work to the task branch (no push needed), so the verifier can
  check out the exact change.
- Skip the council for docs-only, comment-only or formatting changes unless
  the user asks.
- Read the repo's `AGENTS.md` and `CLAUDE.md`. Tell the reviewers which paths
  and commands are off limits.

## 1. Scope

Run `git status --short`. Base: `git merge-base HEAD origin/<default>`, or the
PR's base. Use one diff command every round. Record
`git diff --shortstat <base>` as the starting size. Write two sentences:
intent, and what is out of scope.

## 2. Seats

Use the seats in the user's instructions if they name any. Default:

| Seat | Model | Job |
| --- | --- | --- |
| Correctness | Claude Opus, high effort | Bugs, broken callers, the intended case, edge cases that matter. Checks everything. |
| Judgement | Claude Fable, high effort | Is this the right change? Simpler path? Scope creep? Is it good enough to ship? Lets unimportant nits go. |
| Verifier | Claude Opus, high effort | Runs the repo's checks and tries to break the change in a separate worktree. Reports only what it reproduced. |

If the Fable seat cannot run, for example because the plan's Fable limit is
used up, run that seat on Opus with the same job and write
`Opus (Fable unavailable)` in the table.

All three seats are Claude models, so they can share blind spots. If the user
adds a seat from another provider in their instructions, run it too, as
non-blocking unless they say otherwise.

**Bar.** Every blocking seat scores at least the bar, and no `blocker` or
`should` finding is open. Default bar 8/10. "council 9" sets it to 9.

## 3. Run the reviewers in parallel

Each seat gets the shared brief plus its job line. Reviewers never edit,
commit, push, comment on GitHub or start subagents.

**Wiring.**
- Claude Code: three `Agent` calls in one message, `model: "opus"`,
  `"fable"`, `"opus"`, each a general-purpose subagent with the brief as its
  whole prompt.
- T3 Code: one `delegate_task` per seat with `role: "review"`, `mode: "async"`,
  resolving the models through `orchestrator_capabilities`. Children get no
  history, so the brief is the whole task.
- Any shell: `claude -p --model <opus|fable> --permission-mode plan` with the
  brief on stdin, run in the background, output to files outside the checkout.

**Verifier setup.** Before starting it, create a worktree outside the
checkout: `git worktree add "$TMP/council-verify" HEAD`. The verifier may run
the repo's checks and the app there. It must follow the repo's rules about
which builds may run on this machine. Remove the worktree when the council
ends.

**Shared brief.**

```
Review only. Do not edit, commit, push, comment on GitHub, or start subagents.
Your job: <seat job line>
Repo: <abs path>  Base: <sha>  Head: <sha>  Intent: <intent>
Out of scope: <scope>  Off limits: <paths and commands from AGENTS.md>
Checks already run: <results>
See: git diff <base> <head> [-- <paths>]
Read surrounding code before judging. Skip style unless it hides a bug.
Flag code, tests or guards the intent does not need.
blocker = intended case wrong. should = real bug callers will hit.
nit = everything else (other paths, rare cases, small perf, extra compat).
Reply exactly:
SCORE: <n>/10
VERDICT: APPROVE or CHANGES
F1 [blocker|should|nit] <file>:<line> <claim>. Evidence: <what you saw>. Fix: <suggestion>
```

The verifier's job line adds: "Work only in <worktree path>. Run <checks>.
Report a finding only if you reproduced it, with the command and output."

Rounds after the first add the ledger (`fixed:` / `disagree:` / `declined:`
with evidence), the change since last round, and "review only open ids and
changed code".

## 4. Answer the findings

Do not wait idle. As each seat returns, check its findings against the code.
Do not edit files a seat is still reading. A finding you cannot locate or
reproduce is `disagree`, with evidence.

- Agree: the smallest fix. Prefer delete or narrow over a new helper, option,
  lock or cache.
- Disagree: say why with `file:line`, a test or output.
- Nit or out of scope: decline in one line and list it as follow-up.

Keep a ledger: id, seat, severity, outcome. Re-run the checks and
`git diff --shortstat <base>`. If review grew the diff by more than a quarter,
cut before the next round. Your job is to keep scope limited. Never agree with
a finding just to end the loop. Commit the fixes before the next round so the
verifier sees them.

## 5. Next round or stop

Start a new round only if a `blocker` or `should` is open, or behaviour code
changed since the last review. A round where every seat returns only nits ends
the council.

**Hard cap: three rounds.** Budget end is not approval. After round 3, stop,
show each open dispute in two or three lines per side, and let the user
decide. Do not start round 4 even if the user said "until they agree". More
rounds need the user to say so.

## 6. Record the result

If the work ends in a PR, put this in the PR description above the model and
harness line. Edit the description; do not post a comment.

```markdown
## Council review

Bar: 8/10. Rounds: 2.

| Seat | Round 1 | Round 2 |
| --- | --- | --- |
| Correctness (Claude Opus) | 7/10 | 9/10 |
| Judgement (Claude Fable) | 8/10 | 9/10 |
| Verifier (Claude Opus) | 6/10 | 9/10 |

Fixed: F1, F3. Declined: F2 (nit, out of scope). Disputed: none.
```

Write `no score` when a seat gave none. Never invent one. With no PR, put the
table in the final reply.

Report: rounds, seats and models, diff size before and after, fixed and
declined findings with reasons, and whether anything was pushed. Do not push
during the council; push afterwards only if the user asked to push, ship or
update the PR.
