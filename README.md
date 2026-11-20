Keep It Up To Dater
===================

Weekly winget app updates for Windows workstations, run as scheduled tasks (System, User, Notify) and deployed by GPO.

The example domain contoso.local, the computer names and the addresses in the examples and tests are placeholders: replace them with your own in config.json and the deployment commands.

Current release: 1.5.0 (security review F-01 to F-09 remediated).

- Install-KeepItUpToDater.ps1  installer with the embedded updater
- *.cmd                        wrappers for install, status, logs, test schedule, uninstall
- config.json                  ExcludeIds, RemoveOlder, TrustedSigners
- docs/                        README, deployment commands, security remediation, test results, manual
- tests/                       test harness (winget stand-in, simulated and elevated tests)

See docs/README.txt and docs/Deployment-Commands.txt.
