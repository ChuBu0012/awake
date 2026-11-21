# Contributing to Awake

Thanks for considering a contribution. Bug reports, documentation improvements, and focused code changes are welcome.

## Before you start

- Read the [Code of Conduct](CODE_OF_CONDUCT.md) and [Security Policy](SECURITY.md).
- For a significant feature or behavior change, open an issue first to discuss its scope.
- Do not disclose security vulnerabilities in public issues; use the private reporting guidance in `SECURITY.md`.

## Development setup

Awake requires macOS 12 or later and Xcode Command Line Tools.

```bash
git clone https://github.com/ChuBu0012/awake.git
cd awake
make build
```

`make setup` configures a narrowly scoped sudoers rule for `pmset -a disablesleep 0|1`. It requires administrator access and is not needed to compile the app. Review `scripts/setup-sudoers.sh` before running it.

## Changes and branches

- Create a focused branch from `main` for each feature, fix, security change, or chore.
- Keep changes small and grouped into coherent commits; do not bundle unrelated work into one catch-all commit.
- Use descriptive imperative commit subjects, for example `fix(cli): restore previous sleep setting`.
- Follow [Git Workflow](docs/GIT_WORKFLOW.md) for branch names and commit review steps.

## Pull requests

1. Keep the PR focused and explain the user-visible behavior or maintenance reason.
2. Include relevant platform details and manual verification steps.
3. Run `make test` on macOS when possible and include the result. Do not include generated build output.
4. Update the README or changelog when the change affects users.
5. Confirm the PR contains no secrets, local configuration, or unrelated changes.

Please be clear about checks you could not run, especially checks that require macOS or administrator privileges.
