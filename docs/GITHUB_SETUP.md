# GitHub Repository Setup

Complete these settings before inviting outside contributions:

1. **Confirm repository visibility and license.** The repository is public and `LICENSE` contains MIT. Confirm `ChuBu0012` is the intended copyright holder before publishing a release.
2. **Enable private vulnerability reporting.** In repository Settings → Security → Code security and analysis, enable private vulnerability reporting. The issue template links to the private advisory page; keep the fallback contact path in `SECURITY.md` current.
3. **Review community files.** GitHub should detect `CODE_OF_CONDUCT.md`, `CONTRIBUTING.md`, `LICENSE`, and `SECURITY.md`. Update the maintainer contact links if ownership changes.
4. **Protect `main`.** Require pull requests, dismiss stale approvals when new commits are pushed, and prevent force pushes and branch deletion. Add required status checks after CI is introduced.
5. **Keep issue intake focused.** The issue forms collect macOS version and architecture. Enable Discussions later only if maintainers want a separate space for usage questions.
6. **Create the first release deliberately.** Choose a version tag, update `CHANGELOG.md`, and publish release notes that state the supported macOS version and any known limitations.

Repository settings are not changed by editing these local files. Apply and review them in GitHub's repository settings before announcing the project.
