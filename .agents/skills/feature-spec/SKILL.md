---
name: feature-spec
description: Create an implementation-ready specification for one feature from feature_list.json. Use when the user asks to plan a feature, create a feature spec, apply lightweight SDD/spec-driven development, prepare work for another implementation agent, or generate specs/tasks/technical plan from the feature list. If no feature id is provided, select the first dependency-ready feature in feature_list.json order that is neither passing nor accepted and is not marked out_of_mvp.
---

# Feature Spec

Use this skill to turn one harness feature into an implementation-ready contract for another agent. The output is not a PRD and not implementation code. It is a planning artifact that lets a future implementation session execute with minimal rediscovery, and lets a later validation session judge the result.

## Hard Rules

- Plan exactly one feature per run.
- Do not implement code.
- Do not modify application source files.
- Do not generate specs for every feature unless the user explicitly asks after this skill finishes.
- Create or update only `../../../docs/specs/<feature-id>.md` by default.
- Record the feature's task ID in the spec (`ft_id`, e.g. `FT00001`; and its `FT00001-PTn` parts when the feature is split across PRs, see `../../../docs/feature-ids.md` and the `feature-task-ids` skill). Do not edit `feature_list.json`: if the selected feature has no `ft_id`, report it so the orchestrator assigns the next free one before implementation.
- Respect existing claims: do not plan a feature that another session has already claimed (an open PR toward `main`, or a remote branch starting with `feat/<ft-id-lowercase>`). See `docs/git-workflow.md` §*Reclamar (claim) la feature antes de empezar*.
- If the feature id is not provided, select the first feature in `feature_list.json` order whose status is neither `passing` nor `accepted`, that is not marked `"out_of_mvp": true` (out of MVP scope; only eligible when the user names its id explicitly), and whose `depends_on` prerequisites are satisfied.
- If a feature is too broad to plan cleanly, stop and recommend splitting it in `feature_list.json` instead of producing a vague spec. Rough signal: it needs more than one data model plus one user flow, or the spec would clearly exceed the 100-250 line target.
- Treat the spec as a contract between agents: planner -> implementer -> validator.
- Prefer concrete repository findings over assumptions. If something was not inspected, say so.

## Inputs To Read First

1. `../../../AGENTS.md`
2. `../../../PROGRESS.md`
3. `feature_list.json`
4. `../../../docs/feature-ids.md` (task ID registry: the feature's `ft_id` and parts)
5. Existing feature spec if present: `../../../docs/specs/<feature-id>.md`
6. Product/discovery docs as needed:
   - `../../../CONTEXT.md`
   - `../../../docs/product-brief.md`
   - `../../../docs/domain-model.md`
   - `../../../docs/user-and-access-model.md`
   - `../../../docs/technical-discovery.md`
   - `../../../docs/mvp-scope.md`
   - `../../../DESIGN.md` when the selected feature has UI or visual behavior
   - `../../../docs/risks-and-open-questions.md`
   - `../../../docs/adr/*.md`
7. Existing application files relevant to the selected feature. Inspect enough of the repo to identify expected file changes, patterns, commands, and risks.

If `feature_list.json` is missing, stop and tell the user to run the startup harness skill first.

## Workflow

### 1. Select The Feature

Use a user-provided feature id when present. Otherwise, choose the first feature in `feature_list.json` order with status other than `passing` or `accepted`, not marked `"out_of_mvp": true`, whose `depends_on` prerequisites are satisfied. Prefer an `in_progress` feature over a `not_started` feature if one exists. A feature marked `"out_of_mvp": true` is out of MVP scope and is only eligible when the user names its id explicitly.

A dependency is satisfied when the referenced feature id exists and has status `accepted`. For legacy feature lists, a dependency with status `passing` may be treated as satisfied only when durable evidence shows independent validator acceptance. If `depends_on` is absent in an older feature list, treat it as `[]` for backward compatibility. If the first unfinished features are blocked by dependencies, skip them only when looking for a later dependency-ready feature; report the skipped blockers in the summary.

Skip features that are already claimed by another session: an open PR toward `main` whose head branch starts with `feat/<ft-id-lowercase>` (or whose title starts with its `FTxxxxx`), or a remote branch with that prefix. Check with `git fetch origin --prune`, `git ls-remote --heads origin 'refs/heads/feat/ft<nnnnn>*'` and `gh pr list --state open --json number,headRefName,title`; only plan a claimed feature when the user names it explicitly and confirms the other claim is abandoned.

Before planning, verify the feature has enough scope information: `id`, `title`, `user_visible_behavior`, `depends_on`, and `verification`. If not, improve the feature entry only if the user explicitly asked for feature-list maintenance; otherwise stop and report the missing fields.

### 2. Research The Repository

Investigate how to implement the selected feature in this specific repo:

- current app/framework state,
- existing routes, components, modules, tests, scripts, or conventions,
- relevant data models and migrations,
- relevant API boundaries,
- relevant auth/permission patterns,
- verification commands available today,
- persistent E2E commands available today, such as `pnpm test:e2e`, when the feature has user-facing or API-flow behavior,
- gaps caused by pre-bootstrap or missing infrastructure.

Record inspected files in the spec. Do not pretend to have inspected files that do not exist.

### 3. Write The Feature Implementation Spec

Create or update `../../../docs/specs/<feature-id>.md` using `references/spec-template.md`. For a sense of the right level of detail, look at an existing accepted spec such as `../../../docs/specs/bootstrap-nextjs-shell.md`.

The spec must include:

- source feature metadata,
- goal and non-goals,
- job story or user story,
- acceptance scenarios in Given/When/Then style,
- repository research,
- technical approach,
- expected file changes,
- visual design impact when UI is involved,
- durable documentation impact,
- implementation plan,
- implementation tasks,
- verification plan,
- evidence to capture,
- validator checklist.

Keep the spec concise but operational. A good default target is 100-250 lines. If it grows far beyond that, the feature may need splitting.

### 4. Quality Gate

Before finishing, check:

- A future implementer can identify exactly what to build without reading this chat.
- A future validator can decide whether the implementation satisfies the spec.
- The plan names concrete files or directories where possible.
- The tasks are ordered and executable.
- Verification includes commands or manual checks available in the repo's current state.
- If a persistent E2E command exists and the feature changes user-visible behavior, authentication, authorization, routing, or API flows, the verification plan should include adding/updating focused E2E coverage or explicitly justify why unit/integration coverage is enough.
- For shell scripts such as `init.sh`, the spec states whether the script must execute checks, print guidance, start services, or provide modes. The default harness rule is: `init.sh` executes non-blocking startup/verification checks and must not start long-running dev servers.
- Durable documentation impact is explicit: `../../../ARCHITECTURE.md`, `../../../CONSTRAINTS.md`, `../../../AGENTS.md`, and other durable docs are each marked create/update/not needed with a reason.
- Non-goals prevent scope creep.
- Unknowns are explicit and do not hide blocking ambiguity.

If the spec fails this gate, revise it before reporting completion.

## Output Summary

Report:

- selected feature id,
- spec path,
- whether the feature looked correctly sized,
- key implementation risks,
- next suggested action: usually hand the spec to an implementation agent.
