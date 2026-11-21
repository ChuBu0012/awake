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

Awake's normal idle-sleep prevention uses a per-request `caffeinate` process. Optional lid-closed support changes the system-wide `SleepDisabled` setting and can install `/etc/sudoers.d/awake` for these exact commands only:

- `/usr/bin/pmset -a disablesleep 0`
- `/usr/bin/pmset -a disablesleep 1`

The rule does not grant access to arbitrary `pmset` commands or a shell. It does let any process running as the configured user invoke those two exact commands without a password while the rule exists. A compromised user account can therefore keep the Mac awake or change the system sleep toggle, which can drain the battery or prevent expected sleep. Awake captures the prior setting before applying its own change and restores it when the last request ends; forced termination or power loss can prevent immediate cleanup, so the next Awake CLI/app invocation performs recovery. This mechanism does not guarantee recovery before the user logs in.

Review `scripts/setup-sudoers.sh` before granting administrator access. To revoke the rule, inspect it, remove the known Awake rule files, and validate the remaining sudoers configuration:

```sh
sudo visudo -c
sudo rm -f /etc/sudoers.d/awake /etc/sudoers.d/mac-awake
sudo visudo -c
```

`make uninstall` performs the same revocation when one of these files exists. Do not remove an unrelated sudoers file with a different name unless you have confirmed it belongs to Awake.
