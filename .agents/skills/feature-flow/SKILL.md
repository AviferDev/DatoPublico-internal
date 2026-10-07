---
name: feature-flow
description: Orchestrate the planner, implementer, and validator workflow for one feature using the project's configured subagents. Use when the user asks to run the feature flow, continue the next available feature, delegate to planner/implementer/validator agents, or move a feature through spec, implementation, and validation.
---

# Feature Flow

Use this skill to let the main agent coordinate the three project subagents:

- `planner` wraps `$feature-spec`.
- `implementer` wraps `$feature-implementer`.
- `validator` wraps `$feature-validator`.

The main agent is the orchestrator. It chooses the next role, launches the right subagent, reviews the result, and keeps the same feature moving until the flow reaches an explicit stop condition.

## Hard Rules

- All work happens inside a dedicated git worktree on a new branch created from `origin/main` (see `docs/git-workflow.md`); never commit directly on `main`.
- Before planning or implementing, **claim** the feature so parallel sessions cannot pick it: create the worktree/branch from `origin/main` and push the branch immediately with an empty claim commit; the remote branch is the lock (see `docs/git-workflow.md` §*Reclamar (claim) la feature antes de empezar*). If the push is rejected, the feature is already claimed: discard the local worktree/branch and re-select.
- Work on one feature at a time; parallelism is across sessions, coordinated by the claim.
- Do not run planner, implementer, and validator in parallel for the same feature.
- Do not skip roles unless the required artifact already exists and is current.
- Do not implement work in the main agent while a subagent owns that role.
- Subagents do not create commits. The main orchestrator owns final staging and commit after validator acceptance.
- Do not treat `passing` as accepted. `passing` means implementer self-verification passed; validator `accept` is independent.
- After validation returns `accept`, persist acceptance by changing the selected feature status in `feature_list.json` from `passing` to `accepted` and appending concise evidence that names the independent validator acceptance.
- If validation returns `revise`, route the repair brief back to `implementer` for the same feature.
- After a `revise` repair, route the same feature back to `validator`; do not stop after the repair unless the user explicitly asked for a single role step.
- If validation returns `block`, stop and report the blocker.
- After validation returns `accept`, stage only the accepted feature's changes and create a Conventional Commit before selecting or reporting the next feature.
- After every accepted feature pass, the main orchestrator must report what changed and how the user can try it locally. The implementer supplies raw verification notes, the validator checks they are real, and the orchestrator presents the final user-facing testing steps after the commit.
- After the commit, the orchestrator must push the feature branch and open a Pull Request toward `main` (mandatory; see `docs/git-workflow.md`). Do not merge without explicit review.
- Every selected feature must carry a task ID: `ft_id` (`FTxxxxx`) and, when the work is split across several PRs (multiple layers or >30 files), part IDs `FTxxxxx-PTn`. See `docs/feature-ids.md` and the `feature-task-ids` skill. Use the ID in the branch and commit, and the PR title MUST start with it (`FT00001-PT1 feat(backend): ...`).

## Inputs To Read First

1. `../../../AGENTS.md`
2. `../../../PROGRESS.md`
3. `feature_list.json`
4. `../../../docs/feature-ids.md` (task ID registry and next free `FT`)
5. `docs/specs/` if present
6. `docs/validations/` if present
7. Current git status

## Feature Selection

If the user provides a feature id, use that feature.

If no feature id is provided, select in this order:

1. A feature with status `in_progress`.
2. The first `passing` feature in `feature_list.json` order; `passing` always means implemented and self-verified but not independently accepted.
3. The first feature whose status is neither `passing` nor `accepted` in `feature_list.json` order whose `depends_on` prerequisites are satisfied and that already has a spec.
4. The first feature whose status is neither `passing` nor `accepted` in `feature_list.json` order whose `depends_on` prerequisites are satisfied and that has no spec.

Never auto-select a feature marked `"out_of_mvp": true`; it is out of MVP scope and is only eligible when the user names its id explicitly. A feature with that marker cannot be brought back into the flow without an explicit owner decision that removes the marker.

A feature is dependency-ready when every id in `depends_on` references a feature whose status is `accepted`. For legacy feature lists, a dependency with status `passing` may be treated as ready only when `feature_list.json`, `../../../PROGRESS.md`, or `../../../docs/validations/<feature-id>.md` contains explicit independent validator acceptance evidence. If `depends_on` is absent in an older feature list, treat it as `[]` for backward compatibility, but prefer adding it when maintaining the list.

If no unfinished feature is dependency-ready, report the blocking dependency ids instead of selecting a later blocked feature. When the user asks what can run in parallel, list all dependency-ready unfinished features in `feature_list.json` order, excluding features marked `"out_of_mvp": true`.

**Claimed features.** A feature is already claimed — and therefore not auto-selectable — when an open PR toward `main` targets a branch starting with `feat/<ft-id-lowercase>` (or whose title starts with its `FTxxxxx`), or when such a branch exists on the remote. Detect claims after `git fetch origin --prune` with `git ls-remote --heads origin 'refs/heads/feat/ft<nnnnn>*'` and `gh pr list --state open --json number,headRefName,title`. Skip claimed features when selecting; only work a claimed feature when the user names it explicitly and confirms the other claim is abandoned (see `docs/git-workflow.md` §*Reclamar (claim) la feature antes de empezar*).

Before planning or creating the worktree/branch, ensure the selected feature carries a task ID (use the `feature-task-ids` skill). If its `ft_id` is missing, assign the next free `FTxxxxx` from `../../../docs/feature-ids.md`, add it to `feature_list.json`, and update the registry's *Siguiente FT libre*. If the feature will be split across several PRs (multiple layers or >30 files), also add its `parts` with `FTxxxxx-PTn`. Use the ID in the branch name and in the PR title.

## Claim The Feature

Selection alone is not a lock: two sessions that start from the same `origin/main` can choose the same feature and then collide on the branch, the spec (`docs/specs/<feature-id>.md`) and the `feature_list.json` entry. Reserve the feature **before** running `planner`, using the remote branch as an atomic compare-and-swap (full protocol and commands in `docs/git-workflow.md` §*Reclamar (claim) la feature antes de empezar*):

1. Ensure the feature has an `ft_id` (see *Feature Selection* and the `feature-task-ids` skill); the `FT` is part of the claim.
2. Create the worktree and branch from `origin/main`: `feat/<ft-id-lowercase>[-ptn]-<slug>`.
3. Push the claim **immediately**, before any planning: an empty commit `chore(<FT>): claim` followed by `git push origin <branch>`. The first push wins; a rejected push means another session holds the feature → remove the local worktree/branch and re-select.
4. Only once the claim is visible on the remote, run `planner` → `implementer` → `validator`.
5. Release the claim when abandoning the feature by deleting the remote branch (`git push origin --delete <branch>`) and removing the worktree; after a merge the branch is deleted by the usual clean-up. Never delete or force-push another session's claim branch without the owner's confirmation.

## Role Selection

For the selected feature:

0. If the feature status is `accepted`, report that the feature is already planned, implemented, and accepted; select the next available feature if the user asked to continue.
1. If `../../../docs/specs/<feature-id>.md` is missing or stale, run `planner`.
2. Else if the feature is neither `passing` nor `accepted`, run `implementer`.
3. Else if the feature is `passing`, run `validator`.

Validation records should live under `../../../docs/validations/<feature-id>.md` when the validator or main agent persists them. If the validator only reports in chat, the main agent should ask before writing a validation record unless the user requested persistence.

## Configured Subagents

Launch the project subagents configured for the active agent runtime.

Send only dynamic handoff context:

- repository path,
- selected feature id,
- selected role,
- spec path when applicable,
- validator repair brief when applicable,
- expected output summary.

Do not duplicate the subagent role prompts in this skill. The stable role instructions live in the configured subagent files.

## Orchestration Loop

Default behavior for this skill is until-accepted mode for one selected feature. Do not stop after a planner, implementer, or repair step while the next required role is clear.

Mode summary: until-accepted is the default full pipeline for one feature; one-step runs a single role only when explicitly requested; next-feature only selects and reports after an accept, never auto-starts.

- Until-accepted mode: run planner -> implementer -> validator sequentially for one feature, stopping only when the validator returns `accept`, the validator returns `block`, or a subagent cannot continue.
- Repair loop: if validator returns `revise`, run `implementer` with the repair brief, then run `validator` again for the same feature.
- One-step mode: run only the next required role and report the result only when the user explicitly asks for a single step, dry run, preview, or next-role-only execution.
- Next-feature mode: after accept, select the next feature and report the next required role; do not start it unless asked.

## Commit On Acceptance

Creating the commit is the main orchestrator's final step after the validator returns `accept`; subagents never commit (see Hard Rules). The orchestrator must commit the accepted feature before reporting the flow complete.

1. Run `git status --short` and inspect the relevant diff.
2. Persist acceptance by updating `feature_list.json` for the selected feature to status `accepted` and appending concise validator evidence. If a validation artifact is useful, create or update `../../../docs/validations/<feature-id>.md`; otherwise `feature_list.json` plus `../../../PROGRESS.md` evidence is sufficient.
3. Identify the files changed for the accepted feature, including required harness/docs/evidence updates.
4. Stage only those files. Do not stage unrelated user or other-agent changes.
5. Create one Conventional Commit that names the feature and uses the task ID as scope:
   - `feat(FTxxxxx[-PTn]): complete <feature-id>` for user-visible product/platform features,
   - `docs(FTxxxxx): complete <feature-id>` for documentation-only features,
   - `chore(FTxxxxx): complete <feature-id>` for workflow/tooling-only features.
6. If the accepted feature's changes cannot be isolated from unrelated work, stop and report the commit blocker instead of making a mixed commit.
7. Push the branch (`git push -u origin <branch>`) and open a Pull Request toward `main` with `gh pr create --base main --head <branch> --title "<ID> <tipo>(<scope>): <resumen>"` (mandatory; see `docs/git-workflow.md`). The title MUST start with the task ID (`FTxxxxx`/`FTxxxxx-PTn`). Include the verification evidence in the PR body. Do not merge without explicit review.
8. After the commit and PR succeed, select the next available feature and report the next required role. Do not start the next feature unless asked.

## Final User Handoff

After a validator `accept` and successful commit, the main orchestrator must give a concise user-facing handoff. Do not delegate this final handoff to a subagent.

The handoff headings below are intentionally in Spanish: the skill is written in English, but the final handoff is addressed to the Spanish-speaking user.

Include:

- `Qué se ha hecho`: 2-5 bullets summarizing the accepted behavior, not internal noise.
- `Cómo probarlo`: the automatic command, usually `CI=true ./init.sh`, plus concrete manual/local steps when the feature has observable behavior. Prefer commands the user can run directly. If manual testing needs env vars, database, a dev server, or a port, state that explicitly.
- `Validación`: validator verdict and the most relevant checks/smokes that actually ran.
- `Commit`: hash and Conventional Commit message.
- `Pull Request`: PR URL toward `main`.
- `Siguiente`: next feature id and next required role/action.

When no meaningful manual test exists, say so and explain the closest verification command. Do not invent product behavior that was not implemented.

## Reviewing Subagent Results

After a subagent returns:

- verify the expected artifact exists or the expected verdict is present,
- check that the subagent stayed in role,
- check for obvious missing state updates,
- summarize the next action.

Do not redo the subagent's work unless it clearly failed or the user asks.

## Output Summary

Report:

- selected feature id and task ID (`ft_id`/`pt_id`),
- claim branch and whether the claim was acquired (or the feature was skipped as already claimed),
- role executed,
- subagent used,
- artifact or files produced/updated,
- verification or verdict summary,
- user-facing summary of what changed,
- user-facing instructions for how to test the accepted feature locally,
- commit hash and commit message when a commit was created,
- Pull Request URL toward `main` when a PR was opened,
- next required role/action.
