# Changelog

All changes to Keep It Up To Dater, newest first. The same list is in
docs/README.txt under CHANGES.

## 1.5.2

- Weekly start fixed or random, set centrally in config.json:
  - `"Schedule": { "Mode": "Fixed", "Day": "Tuesday", "Time": "10:00" }`
  - `"Schedule": { "Mode": "Random", "Days": "Weekdays", "From": "09:00", "To": "14:30" }`
- Random gives every computer its own fixed day and minute in the window,
  worked out from its name, so 500+ computers do not all download at the same
  moment and the slot stays the same at every reinstall.
- The installer switch -RandomSchedule does the same with weekdays 09:00-14:30.
- config.json overrides -DayOfWeek, -Time and -RandomSchedule. A change takes
  effect at the next install (restart with the GPO, or the next self-update).

## 1.5.1

- Self-update from NETLOGON: each weekly System run compares the installer
  next to the config.json on NETLOGON with its own version. A newer one is
  installed at the start of the run, with the settings the computer was
  installed with, and the run goes on with the new version. Before, a new
  version arrived only at the next restart (GPO startup script).
- One try per day per version; `"SelfUpdate": false` in config.json turns it off.
- With a signed updater or TrustedSigners the new installer must be signed by
  an approved signer.

## 1.5.0

Fixes from the security review of 19 Nov 2026 (findings F-01 to F-09):

- Program and data folders: no junctions or symbolic links, owned by
  Administrators, only SYSTEM and Administrators can change them; checked
  again after setting, and by the System task at each run.
- Windows tools called by full path in the .cmd files and the updater.
- A missing or damaged installed config.json never means "no exclusions":
  config.lastgood.json is used, otherwise the run stops (event 1002) before
  anything changes. Config files are written atomically.
- Exclusions: only the pins this tool set are lifted (no more pin reset for
  SYSTEM); every exclusion is read back from winget, and the run stops if one
  is missing for an installed app.
- A separate Invoke-KeepItUpToDater.ps1 next to the installer is only used
  with a valid signature from an approved signer (the installer's own, or
  "TrustedSigners" in config.json); the tasks then run it with
  ExecutionPolicy AllSigned.
- Proxy: unreadable, automatic (PAC) and Group Policy settings are left alone;
  proxy.json keeps the bypass list; a setting is removed only while address
  and bypass list are still as this tool set them.
- Older copies: only after a documented winget result; "*" only for packages
  updated in that run and never uninstalls (Unity, PC396); "*" is no longer
  in the shipped config.json.
- Task result: 0 done, 2 finished with failed updates or warnings, 1 did not
  finish. Failed updates are tried again at a later start on another day, at
  most twice before the next weekly run.
- -ListOnly installs no Visual C++ runtime and repairs no catalogue.

## 1.4.8

- Older copies for every package: `"RemoveOlder": { "*": "" }` removes older
  copies of any app winget lists more than once, decided per PC from the
  folders and installer types it finds (Notepad++ and Total Commander on
  PC380, 11 Nov).
- A copy in the same folder as the newest loses only its uninstall entry
  (saved first), so the new files and settings stay. "keep" opts one ID out.

## 1.4.7

- Older copies: "RemoveOlder" in config.json uninstalls the copies an
  installer left next to the newest one (SoapUI 4.6.x to 5.9.x next to 5.10.0
  on a test PC, 11 Nov).
- Uninstall now also lifts the exclusions (winget pins) the System task set
  for SYSTEM; before, those apps stayed pinned after the tool was removed.

## 1.4.6

- Time limit per run: "MaxRunHours" in config.json (1 to 72 hours, or 0 for
  no limit; default 3), or -MaxRunHours for one PC. For a large backlog of
  updates on the first runs.
- The sign-in message no longer says apps are updating when that run was
  stopped.

## 1.4.5

- Proxy for PCs that reach the internet only through one: "Proxy" and
  "ProxyBypass" in config.json, turned on per PC with -UseProxy or "UseProxy"
  (true, or computer names with * and ?). The System task sets it for winget,
  WinHTTP and SYSTEM's internet settings and uses it for its own downloads;
  off by default.
- A winget ID shortened with "..." in winget's table no longer hides the apps
  listed after it.

## 1.4.4

- Result messages through the Windows message service, sent by the SYSTEM
  task: the 1.4.3 window ran PowerShell as the user, which AppLocker blocks.
- Notify task now runs as SYSTEM at sign-in.
- "UserTask": false in config.json (off in the example config) and Status.cmd
  shows AppLocker blocks of PowerShell.

## 1.4.3

- Result window for the user (ShowResults, on in the example config.json): while
  a run is busy, which app is being updated; when it is done, what was updated
  and what could not be. New task Notify.
- -TestSchedule and TestSchedule.cmd to test the scheduling.

## 1.4.2

- Once per week: a catch-up run late in the week no longer makes the next
  weekly run skip. The week begins two days before the scheduled day (Monday
  12:00 for Wednesday 12:00).
- The run summary names apps winget listed but did not update (GnuPG,
  MobaXterm on PC024), apps to start again (Outlook, WSL) and a previous run
  that did not finish.

## 1.4.1

- Exclusions per computer name in config.json (ComputerExcludeIds), managed
  centrally on NETLOGON.

## 1.4.0

- Exclusions for one computer (-AddLocalExclusion / -RemoveLocalExclusion).
- -RunNow now always runs, also when the last run was recent.
- The run summary names apps that need a restart of the PC.

## 1.3.0

- Replace rules in config.json: end-of-life Node.js versions are replaced with
  the current Node.js LTS (System task).

## 1.2.3

- An installer that hangs (VirtualBox) is stopped after 60 minutes without
  progress, so the run continues with the next app.

## 1.2.2

- Status.cmd: task status and logs without the Task Scheduler console.

## 1.2.1

- Apps delivered in a zip file (TeamViewer) now install as SYSTEM.

## 1.2.0

- Visual C++ runtime installed automatically when missing.
- Exclusions read from NETLOGON at every run: a changed config.json needs no
  restart.

## 1.1.1

- Catalogue package repair, also for error 0x8A15000F.

## 1.1.0

- Exclusions in config.json.

## 1.0.1

- Catalogue repair for error 0x8A15000F.

## 1.0.0

- First version: install, the System and User tasks, the skip rule and
  uninstall.
