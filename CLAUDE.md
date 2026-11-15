# Cloud tasks

For cloud work, read `docs/CLOUD-WORK.md` before setup or implementation, then the assigned issue. It defines the supported checks and the Mac/browser gates. Follow any applicable `AGENTS.md`.

## Review and shipping skills

- "full send" or "yolo": the `full-send` skill. "full stop": the `full-stop` skill. "council": the `council` skill. "full send with council" uses the council instead of the single Opus review loop.
- Reviewers are Claude only: Opus 5.5 for correctness and verification, Fable 5.2 for judgement. Do not use GPT or Codex seats; Monroe dropped that subscription on 2026-11-14.
- Council bar 8/10, hard cap three rounds.
- Review runs on Monroe's own machines with his subscriptions. Never run it in GitHub Actions, and never spend another person's CI quota to satisfy a merge gate.
- In repos whose AGENTS.md keeps PRs as drafts or says CI runs locally (Splats), full send stops at the full-stop handoff with local checks as proof.
