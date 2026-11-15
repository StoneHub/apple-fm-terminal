---
name: full-send
description: Use when the user says "full send" or "yolo". Takes a change all the way to a merged PR with nobody watching. Proves it, reviews it with a fresh Opus reviewer (or the council), files the PR, babysits it, and merges it.
---

# Full send

Adapted from Theo Browne's `full-send` in t3dotgg/tstack (MIT). This version
reviews with Claude Opus instead of GPT Sol, and folds Theo's `sol-loop`,
`file-pr`, `babysit-pr` and `leaving-pr-comments` into one file.

The user is not watching this thread. They want the work done end to end.
Your updates and final message go unread until long after you stop. You own
the work from its current state to a merged PR.

Only follow this skill when the user clearly said "full send" or "yolo". Never
assume this much autonomy otherwise.

## What the request grants

- Merging the PR once the merge gate below passes.
- `git push --force-with-lease` on this task's own branch after a rebase.
- The test methods that proof needs, including running the app, a dev server,
  a simulator, browser automation, computer use and screenshots, even where a
  project file says to ask first. Rules about *how* to test still apply.

It does not grant production changes, deleting data, changes outside the
repo, closing PRs, pushing to any other branch, or bypassing branch
protection or a harness approval prompt.

## Repo rules win

Read the repo's `AGENTS.md` and `CLAUDE.md` before starting. Where they limit
CI, PRs or machines, they override this skill. For example: a repo that says
PRs stay draft until a person promotes them, that CI runs locally only, that
some paths are off limits, or that some builds must not run on this machine.
When a repo rule stops the merge, finish everything else and stop at the
`full-stop` handoff instead.

## Steps

1. **Finish the change.** Smallest change that meets the goal. Fix the case
   that happened, not every case that could. On the default branch, create a
   branch first.
2. **Prove it.** See Proof.
3. **Review it.** Run the Opus review loop below. If the user said "full send
   with council", run the `council` skill instead.
4. **File the PR.** See Filing the PR.
5. **Babysit the PR.** See Babysitting. Fix real findings and CI failures,
   with proof for each fix before you push.
6. **Merge** when the merge gate passes.
7. **Report** in the final message: PR link, merge commit, proof, reviewer
   outcome, and every decision you made for the user.

Stay active from step 1 to step 7. If you end your turn while checks or bots
are pending and nothing will wake you, the work stops.

## Proof

Proof is evidence you saw yourself in this session: command output, a
reproduction, a screenshot.

- Reproduce the failure, apply the fix, and watch the same reproduction pass.
- Run the checks the repo's CI runs (typecheck, lint, tests, build). Where the
  repo says CI runs locally, these local runs are the required checks.
- Add one focused test that fails without the fix, when the behaviour has
  none and the repo has a test setup.
- For UI and runtime behaviour, run the app and look. Green mocked tests do
  not prove the user experience. Attach screenshots when you can upload them.

If you cannot prove a change, you do not have full confidence. Ask.

## Opus review loop

One fresh reviewer on Claude Opus at high effort, in a new context, read-only.
A fresh context is the point: it has not seen your reasoning.

**Budget.** 3 rounds. Round 1 reviews the whole change. Later rounds check
only changed code and open findings. Allow up to 5 only for security, auth,
permissions, data loss or concurrency while a `blocker` or `should` stays
open with evidence. Stop early when a round returns only nits.

**Scope.** Run `git status --short`. Do not stash or discard unrelated work.
Base: `git merge-base HEAD origin/<default>`. Use one diff command every
round. Write two sentences: intent, and what is out of scope.

**Start the reviewer.**
- Claude Code: the `Agent` tool with `model: "opus"`, a general-purpose
  subagent, the brief as its whole prompt.
- T3 Code: `delegate_task` with `role: "review"` on the latest Claude Opus.
- Anywhere with a shell: `claude -p --model opus --permission-mode plan` with
  the brief on stdin, output to a file outside the checkout.

Do not edit the scoped files while the reviewer runs. A timeout, error or
empty reply is not approval.

**Brief.**

```
Review only. Do not edit, commit, push, comment on GitHub, or start subagents.
Repo: <abs path>  Base: <sha>  Intent: <intent>  Out of scope: <scope>
Checks run: <results>
See: git diff <base> [-- <paths>]; git status --short (read untracked files).
Read surrounding code. Find bugs, broken callers, and mismatch with the intent.
Skip style unless it hides a bug. Flag code, tests or guards the intent does
not need. blocker = intended case wrong. should = real bug callers will hit.
nit = everything else (other paths, rare cases, small perf, extra compat).
Reply:
VERDICT: APPROVE or CHANGES
F1 [blocker|should|nit] <file>:<line> <claim>. Fix: <suggestion>
```

**Answer findings.** Check each one against the code yourself. Agree: make
the smallest fix, preferring delete or narrow over a new helper, option, lock
or cache. Disagree: say why with `file:line`, a test or output. Nit or out of
scope: decline in one line and list it as a follow-up. Keep a ledger of id,
severity and outcome. Re-run the checks and `git diff --shortstat`. If review
grew the diff, cut first. Never agree just to end the loop.

**Next round** only if budget remains and a `blocker` or `should` is open or
behaviour code changed. Send the brief, the ledger, and the change since the
last round.

**Stop.** Agreed means APPROVE on the current diff, nothing `blocker` or
`should` open, and no concern of your own. If an item stays disputed after two
replies, or the budget ends, show both sides in two or three lines and ask.
Budget end is not approval.

## Filing the PR

- Check whether a PR for this branch already exists. Rebase onto the latest
  default branch.
- Title: follow the repo's convention and say why it matters, not what you
  touched.
- Description: open with the problem in plain words, then the fix. No
  inventory of changed functions. Add one line on how you proved it and one
  line on the review: "Reviewed with Opus: 2 rounds, approved."
- End with the model and harness that made the change, as the harness reports
  it. Never guess a model name.
- Check the title, description and attachments for secrets and private
  details.
- Open a ready PR so review bots run, unless a repo rule says draft.

## Babysitting

- Handle existing checks and comments first, then wait with one watcher:
  `subscribe_pr_activity` in a Claude Code cloud session, `watch_pull_request`
  in T3 Code, otherwise `gh pr checks <n> --watch` run in the background or
  under the Monitor tool. Never write your own polling or sleep loop.
- Act only on checks and comments newer than the latest push. Verify every
  bot finding against the source. Fix real ones. Dismiss false positives with
  a written reason and resolve the thread.
- Keep the PR the size the goal needs. Decline unneeded tests, guards for edge
  cases that do not matter, extra compatibility and small perf costs, and list
  them as follow-ups.
- Rebase when the base moves under this PR's files.

## Comments on GitHub

Start every comment you post on the user's behalf with:

```
> [!NOTE]
> 🤖 <model> responding on behalf of <user>
```

Then lead with the conclusion, cite the code, check or output, and stop. Do
not add this to PR descriptions or commit messages.

## Merge gate

All true on the latest commit:

- Proof covers every change in the diff.
- Required checks are green, or, where the repo runs CI locally, the local
  checks passed on this commit.
- Review bots have finished, and each finding is fixed or dismissed with a
  reason.
- No human review requests changes.
- The branch is up to date with the default branch and GitHub reports it
  mergeable.

Merge with the method the repo uses. Never use `--admin` or another bypass.
Right before merging, fetch and check the PR again.

## Asking the user

A question in a normal message goes unseen. Use the harness's question tool
(AskUserQuestion in Claude Code) with the PR link, the blocker, and options
with your recommendation first. Ask only when you cannot prove the change, the
merge gate cannot pass, the next step is outside the grant, the goal is
ambiguous in a way that changes the result, or another PR makes this one
obsolete. Decide everything else and list it in the report. With no question
tool, leave the PR open and unmerged and start the final message with the
question.
