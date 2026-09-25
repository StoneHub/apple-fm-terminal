# Cloud work: terminal completion

This zsh plugin is a companion to Jot, not its current package dependency. Jot's proposed ownership of model/context/settings and installation should preserve a thin shell component for buffer, cursor, ghost text and Tab. No migration is implemented or authorized by this preparation.

## Environment

Preparation baseline: `d9bd7bd` on 2026-09-25. Record the runner's checkout/branch and inspect the assigned issue/overlapping PRs. For source analysis, Git and text tools suffice. For mocked shell tests, provision zsh and Expect; `pty-smoke.exp` uses `fixture-fm`, not `/usr/bin/fm`. Run `zsh -n apple-fm.zsh` then `./pty-smoke.exp` once. Verify a usable PTY and fixture shebangs on the actual runner. The fake-model suite passed locally on a Mac; hosted Linux is not yet verified.

Allow five minutes for preflight and one evidence-backed setup correction, then report repeated failure. Missing Apple inference is an expected Linux limit. Real quality tests in `dogfood.exp`, user shell installation and Jot integration need separate Mac work. Keep Tab acceptance separate from Enter execution. Preserve caller options/bindings. Avoid changing real shell startup files or running installers. No personal history or MCP service is required. Missing personal `/Users/...` files are not setup dependencies.

## First bounded review: issue #10

[Issue #10](https://github.com/StoneHub/apple-fm-terminal/issues/10) records invalid Git flags in two actual responses. Start with its evidence, `apple-fm.zsh`, `fixture-fm` and `pty-smoke.exp`. Deliver `docs/plans/git-completion-quality.md`, a decision report rather than a production change.

Compare three bounded choices: adjusting the model prompt, constructing a small supported candidate set, and conservative abstention for unsupported additions. Identify false positives, stale Git-version assumptions and what the existing output checks can actually prove. Include the two recorded failures and at least four synthetic valid/invalid counterexamples with explicit expected outcomes. Synthetic examples are authored expectations, not measured model results. Recommend the smallest implementation slice and exact fixture/PTY and later Mac quality checks.

Do not execute generated commands to validate them or build a general shell parser. Directory completion #9 and partial words after pipes #3 remain separate. The permitted-root and insertion decisions in the directory proposal are unresolved implementation gates, so #9 is not an automatic cloud assignment.

Return the source-backed report and proposed focused task, with any Linux test blocker. A no-change recommendation is acceptable when supported. The local integrator reviews it before assigning implementation. No release, merge of unvalidated app/shell code, or install is implied.

Copy-ready launch:

> Review issue #10 using docs/CLOUD-WORK.md. Produce the bounded Git-completion quality decision report and synthetic counterexamples. Start with source analysis; use only the fake-model test if the runner supports it. End with one recommended implementation slice and its acceptance checks. Do not implement the fix or run live inference.
