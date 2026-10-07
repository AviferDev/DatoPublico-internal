---
name: feature-implementer
description: Implement exactly one planned feature from a feature spec file under docs/specs. Use when the user asks to implement a feature spec, execute the selected feature, act as the generator/implementer in a planner-generator-validator workflow, or turn a feature implementation spec into code. The skill self-verifies the work, updates progress/evidence, and updates durable documentation when required, but it does not perform final independent validation.
---

# Feature Implementer

Use this skill to implement one already-planned feature. The implementer writes code, runs the required checks, records evidence, and leaves the repository ready for an independent validator.

## Role Boundary

You are the implementer/generator, not the planner and not the final validator.

- Work inside the dedicated git worktree/branch for this feature; never commit on `main` (see `docs/git-workflow.md`).
- Use the feature's task ID (`ft_id`, e.g. `FT00001`; part `FT00001-PTn` when the work is a split part) in the branch and evidence; the orchestrator opens the PR with the ID at the start of the title. See `../../../docs/feature-ids.md`.
- Do implement the selected feature.
- Do self-verify with the checks required by the spec and repo harness.
- Do update status, progress, evidence, and required durable docs.
- Do not broaden the feature scope.
- Do not silently redesign the spec. If the spec is wrong or blocked, update the spec with findings or mark the feature blocked instead of improvising.
- Do not declare final acceptance. Leave that for `feature-validator`.
- Treat `passing` as "implemented and self-verified, ready for independent validation", not as final acceptance.
- Never set a feature to `accepted`; only the main orchestrator may persist `accepted` after an independent validator returns `accept`.

## Inputs To Read First

1. `../../../AGENTS.md`
2. `../../../PROGRESS.md`
3. `feature_list.json`
4. `../../../docs/feature-ids.md` (task ID registry for the selected feature)
5. Selected feature spec: `../../../docs/specs/<feature-id>.md`
6. Durable docs if present and relevant:
   - `../../../ARCHITECTURE.md`
   - `../../../CONSTRAINTS.md`
   - `../../../DESIGN.md` when the spec has UI or visual behavior
   - relevant docs under `docs/`
7. Existing application files named in the spec's repository research and expected file changes.

If no feature id is provided, choose the feature that is currently `in_progress`; otherwise choose the first feature in `feature_list.json` order whose status is neither `passing` nor `accepted`, that is not marked `"out_of_mvp": true` (out of MVP scope; only eligible when the user names its id explicitly), whose `depends_on` prerequisites are satisfied, and that already has `../../../docs/specs/<feature-id>.md`.

A dependency is satisfied when the referenced feature id exists and has status `accepted`. For legacy feature lists, a dependency with status `passing` may be treated as satisfied only when durable evidence shows independent validator acceptance. If `depends_on` is absent in an older feature list, treat it as `[]` for backward compatibility.

If no spec exists for the selected feature, stop and ask the user to run the planner/spec step first.

## Workflow

### 1. Confirm The Contract

Read the selected spec and identify:

- goal and non-goals,
- acceptance scenarios,
- expected file changes,
- durable documentation impact,
- implementation tasks,
- verification plan,
- evidence to capture,
- validator checklist.

If the spec is too vague for implementation, stop with a concise blocker and recommend revising the spec.

### 2. Set Feature State

Before code changes, ensure `feature_list.json` reflects one active feature:

- mark the selected feature `in_progress` if it is not already,
- keep all unrelated unfinished features `not_started`,
- do not mark anything `passing` before verification evidence exists.

### 3. Implement Only This Feature

Make the smallest coherent set of changes needed to satisfy the spec.

Rules:

- Follow existing repository patterns.
- Apply the repo code-quality rules: prefer reusable components/functions, follow Compose/clean-code best practices, keep every function within the 40-line limit, put **all user-facing UI text in resources** (no hardcoded strings), and use **Material Icons** for semantic icons (`../../../AGENTS.md` + the architecture skills).
- Keep WIP=1.
- Do not implement adjacent features from `feature_list.json`.
- Add regression/unit/integration/smoke tests when they fit the feature and current repo maturity.
- If the repo has a persistent E2E command such as `pnpm test:e2e` and the selected feature changes user-visible behavior, authentication, authorization, routing, or API flows, add or update focused E2E coverage unless the spec explicitly justifies not doing so.
- Use `references/implementation-rules.md` for durable documentation rules.

### 4. Self-Verify

Run the spec's verification plan and the repo's standard gate. If a required check cannot run, document exactly why and what is missing.

If the feature creates or updates `init.sh`, make it an executable non-blocking gate: it should run the standard verification checks for the current repo state and must not start long-running dev servers. A script that only prints the checks is not enough unless the spec explicitly says this repository is still pre-bootstrap.

Self-verification should include the strongest applicable levels available today:

1. static/syntax checks,
2. tests and runtime/startup checks,
3. persistent E2E checks when the repo has them and the feature affects an observable user/API flow,
4. manual user-flow or smoke checks when persistent E2E is not yet available or cannot cover the case.

If any required check fails, fix it or leave the feature non-passing with a clear blocker. Do not hide failures.

Also self-check the code-quality rules before finishing: no function exceeds 40 lines (excluding KDoc/comments/blank lines), reusable components/functions are extracted, UI composables follow Compose best practices, and each UI composable has a preview.

### 5. Update Harness State

After verification:

- update `feature_list.json` for the selected feature only,
- record exact evidence for checks that passed,
- update `../../../PROGRESS.md` with what changed, what ran, what failed, and the next best step,
- update the session handoff note if it exists or if the session leaves meaningful incomplete state,
- update durable docs required by the spec or discovered during implementation.

CONSTRAINTS.md rule: read `../../../CONSTRAINTS.md` before implementing (see Inputs To Read First). When implementation or verification reveals a durable operational constraint (a MUST/MUST NOT rule future features have to respect), append it to `../../../CONSTRAINTS.md` with a short reason. Do not add speculative rules or restate what the spec, `../../../AGENTS.md`, or `../../../ARCHITECTURE.md` already cover; follow the durable documentation rules in `references/implementation-rules.md`.

Status rule:

- `passing` means required verification passed and evidence is recorded.
- `passing` does not mean independently accepted. It means the implementer believes the feature is ready for `feature-validator`.
- `accepted` means an independent validator returned `accept` and the main orchestrator persisted that acceptance.
- `blocked` means implementation cannot continue and the reason is durable in `../../../PROGRESS.md` and/or the feature entry.
- If implementation is partial or unverified, leave `in_progress` or `blocked`, not `passing`.

### 6. Leave Validator-Ready State

Before finishing, ensure a fresh validator can review without this chat:

- source changes are saved,
- generated temporary files are removed,
- checks/evidence are recorded,
- docs and harness state are consistent,
- final response lists changed files and verification run.

## Output Summary

Report:

- selected feature id and spec path,
- what was implemented,
- verification commands/checks and results,
- files changed,
- harness/docs updated,
- whether the feature is ready for independent validation.
