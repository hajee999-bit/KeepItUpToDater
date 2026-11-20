# Keep It Up To Dater

Free weekly app updates for Windows desktops, with only what Windows already has: PowerShell 5.1, Task Scheduler and winget. No agent, no server, no licence cost. Built for desktop admins who do not have Intune, SCCM or a patch management suite for every device, and whose users are not local admins.

Current release: **1.5.2**

## What it does

- Updates machine-wide apps once a week as SYSTEM, plus an optional user task for apps installed in the user's own profile
- Deploys with one GPO computer startup script
- Weekly start fixed (`"Mode": "Fixed"`) or random per computer in a window, such as weekdays 09:00-14:30 (`"Mode": "Random"`), so hundreds of computers do not saturate the internet connection at the same moment
- One central `config.json` (for example on NETLOGON), read at every run: exclude apps for every computer or per computer, replace end-of-life packages, remove older copies left next to a new version
- Works behind a proxy, also for the SYSTEM account
- Optional Windows message to the signed-in user with the result
- Event log entries 1000 (OK), 1001 (warning) and 1002 (error), and a task result of 0x0, 0x2 or 0x1 for monitoring
- Retries failed updates on a later day, at most twice before the next weekly run
- `-ListOnly` shows what would change without changing anything
- Updates itself: put a new version of the installer next to `config.json` on the share, and every computer installs it at the start of its next weekly run (`"SelfUpdate": false` turns this off)
- Security reviewed: locked-down program and data folders, a config that fails closed, full paths for Windows tools, and an optional signed updater that runs under AllSigned

## Requirements

- Windows 10 1809 or later, or Windows 11
- winget (App Installer, part of Windows)
- Administrator rights to install; the users themselves need none

## Get the files

Clone the repository:

```
git clone https://github.com/hajee999-bit/KeepItUpToDater.git
```

or, in GitHub Desktop: **File > Clone repository**, then `hajee999-bit/KeepItUpToDater`.

Files from a clone are not marked as downloaded from the internet, so Windows does not block them. To update later, pull the latest version (`git pull`, or **Fetch origin** in GitHub Desktop).

## Quick start on a test device

Run these from the folder you cloned to.

1. Optional: double-click `CheckUpdates.cmd` to see which apps are outdated. Nothing is changed.
2. Check `config.json`. Add the winget IDs of apps that must never be updated to `ExcludeIds`; it ships with an empty list.
3. Right-click `Install.cmd` > **Run as administrator**. This installs the scheduled tasks and starts the first update run.
4. Right-click `Status.cmd` > **Run as administrator** to see the tasks, their last result and the log locations. `ShowLogs.cmd` opens the logs.
5. Right-click `Uninstall.cmd` > **Run as administrator** to remove it again.

## Rollout with Group Policy

Put `Install-KeepItUpToDater.ps1` and `config.json` in a share all computers can read, such as NETLOGON, and run the installer as a computer startup script. Start with a small group of computers (security filtering). The commands are in [docs/Deployment-Commands.txt](docs/Deployment-Commands.txt).

## Documentation

| File | Contents |
|---|---|
| [docs/README.txt](docs/README.txt) | Quick start, configuration options, proxy, time limit, change log |
| [docs/Deployment-Commands.txt](docs/Deployment-Commands.txt) | GPO rollout and other commands to copy and paste, security checks |
| [tests/README.txt](tests/README.txt) | How to run the test scripts |
| `Install-KeepItUpToDater.ps1` | `Get-Help .\Install-KeepItUpToDater.ps1 -Full` lists every parameter |

## Placeholders

The domain `contoso.local`, the computer names and the addresses in the examples and tests are placeholders. Replace them with your own in `config.json` and the deployment commands.

## Licence

[Apache License 2.0 with the Commons Clause](LICENSE).

- **Allowed:** use it for free, also commercially inside your own organisation; change it; share it, with this licence included.
- **Not allowed:** sell it, or sell a product or service whose value comes entirely or substantially from it, including fees for hosting, consulting or support around it.
- **No warranty, no liability:** the software is provided "as is". You use it at your own risk; the author is not liable for any damage (sections 7 and 8 of the Apache License).

Because of the Commons Clause this is source-available software, not open source in the OSI sense. Copyright 2026 Hendrik-Jan Sluis.

## Feedback

Questions, problems and ideas: open an issue in this repository.
