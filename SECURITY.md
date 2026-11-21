# Security Policy

## Supported versions

Security fixes are intended for the latest released version. Until the project publishes a release, report issues against the current `main` branch.

## Reporting a vulnerability

Please do not report security vulnerabilities in public issues or pull requests. Use GitHub's private vulnerability reporting for this repository when it is enabled. If that option is unavailable, contact the maintainer using the contact method on the [ChuBu0012 GitHub profile](https://github.com/ChuBu0012).

Include, when possible:

- The affected version or commit and macOS version.
- A concise description of the impact and the conditions required.
- Reproduction steps or a proof of concept that does not expose other people's data.
- Any proposed mitigation.

Please allow the maintainer reasonable time to investigate and prepare a fix before public disclosure. The project will acknowledge reports and coordinate disclosure when possible, but does not currently promise a response or resolution timeframe.

## Security-sensitive behavior

Awake changes a system-wide sleep setting and can install a sudoers rule for a narrowly scoped `pmset` command. Review the scripts before granting administrator access, and disable Awake when it is no longer needed.
