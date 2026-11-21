# Git Workflow

## Branches

Start each feature, bug fix, security change, or chore on its own branch from the up-to-date base branch. Do not develop new work directly on `main`.

Use descriptive names with a category prefix:

- `feat/<short-name>` for user-facing features
- `fix/<short-name>` for bug fixes
- `security/<short-name>` for security hardening
- `perf/<short-name>` for performance work
- `refactor/<short-name>` for behavior-preserving code changes
- `chore/<short-name>` for maintenance and tooling
- `docs/<short-name>` for documentation

Keep one branch focused on one outcome. If work reveals an independent task, put that task on another branch.

## Commits

Commit changes in small, reviewable groups. Each commit should represent one coherent step and leave the branch understandable. Split commits by concern when changes can be reviewed or reverted independently; for example, security hardening, CLI behavior, app behavior, packaging, and documentation should not be bundled into one large commit by default.

Use imperative commit subjects, preferably with a scope, such as:

```text
security(cli): validate duration input
fix(state): restore the previous sleep setting
chore(install): include the sudo setup helper
docs: describe branch and commit workflow
```

Before each commit:

1. Review `git status` and stage only files for that logical change.
2. Inspect `git diff --cached` to confirm the commit contains no unrelated work or secrets.
3. Run checks relevant to that change and include their result in the review or pull request.
4. Commit with a subject that describes the change, not the act of changing it.

Do not use a single catch-all commit for a multi-part task. Avoid commits that mix formatting churn with behavior changes unless the formatting is required to make that specific change reviewable.

## Pull requests

Keep the pull request focused on the branch outcome. Explain the behavior change, security or performance impact where relevant, and checks performed. Do not push local-only files such as the ignored root `AGENTS.md`.
