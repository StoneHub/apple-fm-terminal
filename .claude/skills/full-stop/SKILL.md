---
name: full-stop
description: Use when the user says "full stop", even as a closing "Full stop." that reads like emphasis. Same as full-send, but stops with the PR ready for the user to merge and never merges.
---

# Full stop

Adapted from Theo Browne's `full-stop` in t3dotgg/tstack (MIT).

Do the same work as the `full-send` skill: read it and follow its steps,
proof rules, Opus review loop (or council, if asked), filing and babysitting.
A "full stop" request grants full-send's testing permission. Its merge
permission does not apply, and the rules below win.

## Never merge

You may commit, push, rebase, fix conflicts and use `--force-with-lease` on
this task's branch. Never merge, enable auto-merge, enter a merge queue, push
to the default branch, bypass branch protection, or ask another agent to do
any of those. If the PR has auto-merge on or sits in a merge queue, turn that
off before starting, check again before each push, and report it.

## Stop at the gate

Use full-send's merge gate as the readiness check. Make sure proof and review
cover the final diff. Then fetch the target branch and check the live PR: open,
head, base, checks, reviews, mergeable.

Hand off with one of:

- **Ready to merge.** The gate passes. The PR is open and unmerged.
- **Waiting for approval.** Only a human approval remains.
- **Blocked.** What stops it, what you tried, and what you need.

If a repo rule keeps PRs as drafts, leave it as a draft and say it is ready to
be marked ready.

Report the PR link, final head commit, verdict, proof, reviewer outcome,
remaining risks, and that the PR is still open and unmerged.
