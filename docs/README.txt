KEEP IT UP TO DATER 1.5.0
===========================================================

Weekly automatic app updates with winget for Windows devices where users are
not local admins. Uses only what ships with Windows: PowerShell 5.1, Task
Scheduler and winget. Nothing else is installed, except the Microsoft
Visual C++ runtime on a device that lacks it (winget needs it).

QUICK START ON A TEST DEVICE
1. Get the files: git clone https://github.com/hajee999-bit/KeepItUpToDater.git
   (or GitHub Desktop: File > Clone repository). Run the steps below from
   that folder; the .cmd files and the installer are in its root.
2. Optional: double-click CheckUpdates.cmd to see what is outdated. Apps that
   must never be updated: add their winget IDs to config.json. It ships with an
   empty list. An exclusion for one computer only: see EXCLUSIONS FOR ONE
   COMPUTER below. config.json also replaces end-of-life Node.js versions with
   the current Node.js LTS. Remove the Replace rule if you do not want that. It
   also removes older SoapUI copies left next to the newest one. The same for
   every package ("*") is off unless you add it, see REMOVING OLDER COPIES.
3. Right-click Install.cmd > Run as administrator. This installs and starts the
   first update run (machine-wide apps). PC that reaches the internet only
   through the proxy: run it from PowerShell as administrator, in this folder,
   as
       .\Install.cmd -UseProxy
   See PCS BEHIND A PROXY below.
4. The signed-in user gets a Windows message when the first app starts
   updating, and one at the end with what was updated and what could not be.
   This is "ShowResults": true in config.json, on in the example config.json;
   set it to false for silent runs. The SYSTEM task shows these messages
   itself, so they also work where AppLocker blocks PowerShell and .cmd files
   for standard users. Who signs in later gets the last result at sign-in.
   system.log names who got each message. Or double-click ShowLogs.cmd.
   Right-click Status.cmd > Run as administrator to see the scheduled tasks,
   their last result, AppLocker blocks and the log locations. It also works
   where Group Policy blocks the Task Scheduler console.
5. User task: off in the example config.json ("UserTask": false), because on
   many managed PCs standard users cannot run PowerShell, and the user task
   runs PowerShell as the user. On PCs without that block, set "UserTask":
   true: 15 minutes after sign-in it updates the apps in that user's own
   profile.
6. Test the scheduling: right-click TestSchedule.cmd > Run as administrator.
   Task Scheduler then starts the System task by itself 5 minutes later, once
   (also the User task when it is on). Afterwards Status.cmd shows that time
   as its last run, and the user gets both messages.
7. Right-click Uninstall.cmd > Run as administrator to remove it again. This
   also lifts the exclusions (winget pins) the System task set.

ROLLOUT
With a GPO computer startup script, see Deployment-Commands.txt.
For a first rollout, limit the GPO to the PCs you choose with a computer group and
security filtering.

FILES
  Install-KeepItUpToDater.ps1   Installer
  config.json                   Exclusions (winget IDs never updated), replace
                                rules (old package -> new package), messages
                                (ShowResults), the User task (UserTask) and
                                the proxy (Proxy, ProxyBypass, UseProxy) and
                                the time limit per run (MaxRunHours)
                                Installer + config.json = all a rollout needs
  Install.cmd / Uninstall.cmd   Helpers, run as administrator
  TestSchedule.cmd              Test the scheduling: the tasks start by
                                themselves in 5 minutes (run as administrator)
  CheckUpdates.cmd              List available updates, changes no apps
  ShowLogs.cmd                  Open the logs and show run summaries
  Status.cmd                    Tasks, last results, log locations; no console needed
  Deployment-Commands.txt       GPO rollout and other commands to copy

EXCLUSIONS FOR ONE COMPUTER
ExcludeIds in config.json applies to every computer. Two ways to add an
exclusion for one computer only; both add to ExcludeIds:
1. Centrally, per computer name, in the same config.json (NETLOGON). Both
   tasks read it at every run. Use the name from: echo %COMPUTERNAME%
       "ComputerExcludeIds": {
           "PC024": [ "Mobatek.MobaXterm" ]
       }
2. On the computer itself, as administrator (cloned folder or NETLOGON):
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File
   .\Install-KeepItUpToDater.ps1 -AddLocalExclusion Oracle.VirtualBox
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File
   .\Install-KeepItUpToDater.ps1 -RemoveLocalExclusion Oracle.VirtualBox
   Several IDs: separate them with commas. This only edits
   C:\ProgramData\KeepItUpToDater\local-config.json (only administrators can
   change it); nothing is reinstalled. The file stays when the tool is
   installed again or removed. Not for the GPO line: there the installer would
   only edit the local list and not install.
Status.cmd shows all lists: all computers, and this computer from config.json
and from local-config.json.

REPLACING END-OF-LIFE PACKAGES
winget keeps an old Node.js (for example 18.x) on its own package and only updates
it within that major version. The shipped config.json moves every such version to
the current LTS:
    "Replace": { "OpenJS.NodeJS.*": "OpenJS.NodeJS.LTS" }
The System task installs the LTS version and removes the old version only when it
is still installed next to it. Excluded packages are not replaced. Tested with
Node.js 4.8.7 up to 23.11.0.

REMOVING OLDER COPIES
Some installers put a new version next to the old one instead of replacing it
(SoapUI: a folder per version, each with its own Java). winget lists every copy
under the same ID but only ever updates the newest, so the older copies stay.
The shipped config.json removes them for SoapUI:
    "RemoveOlder": { "SmartBear.SoapUI": "-q" }
After the update pass the System task keeps the newest copy of each listed ID
and deals with the older ones. Nothing is removed when the update of that app
failed in this run, after an unexpected winget result, or when the newest copy
has no uninstall entry of its own (1.5.0). The value holds the switches that
make that app's uninstaller silent: -q for SoapUI, /S for most NSIS installers,
/qn /norestart for MSI. An uninstall entry with its own quiet command uses
that, so the value may be "". Excluded IDs are skipped. system.log and the
result message list what was removed; a copy that could not be removed makes
the run end with a warning (event 1001). Optional: "*" for every package,
"RemoveOlder": { "*": "", "SmartBear.SoapUI": "-q" }. Since 1.5.0 it only looks
at packages winget updated successfully in that run, and it never uninstalls
anything (PC396: winget installed Unity 2020 next to Unity 2018 and 1.4.8 then
uninstalled Unity 2018):
- Same folder as the newest copy (Notepad++ 7.8.1 next to 8.9.9, Total
  Commander 9.51 next to 11.58.1): the update already replaced its files and
  its uninstaller would delete the new ones. Only its uninstall entry is
  removed, after a backup to C:\ProgramData\KeepItUpToDater\removed-entry-*.reg
  (double-click to put it back).
- A folder of its own, or folder unknown: left alone and listed in system.log
  and the summary as "Older copies left, check by hand". A rule for that ID
  uninstalls it. Keep the older copies of one app: "RemoveOlder": { "*": "",
  "Vendor.App": "keep" } See what "*" would do on a PC, changing nothing (as
  administrator): powershell -ExecutionPolicy Bypass -File "C:\Program
  Files\KeepItUpToDater\Invoke-KeepItUpToDater.ps1" -Mode System -ListOnly

PCS BEHIND A PROXY
The SYSTEM account does not use the user's proxy settings. On a PC that
reaches the internet only through a proxy, the System task then fails with
0x8A15000F and "Download location NOT reachable". The address is in
config.json once; it is used only on the PCs where it is turned on:
    "Proxy": "http://192.0.2.163:8080",
    "ProxyBypass": "<local>;*.contoso.local",
    "UseProxy": false
Turn it on for a PC in one of three ways:
1. The installer's -UseProxy: .\Install.cmd -UseProxy. With a GPO only on a
   separate GPO that those PCs get instead of the general one.
2. "UseProxy": [ "VM-*", "PC-002" ] in config.json: the PCs named, * and ?
   allowed. Read at every run from NETLOGON.
3. "UseProxy": true: every PC that uses this config.json.
The System task then sets that proxy for winget (DefaultProxy), WinHTTP and
SYSTEM's internet settings, only where nothing else is set, and removes these
settings again when the proxy is turned off or the tool is removed.
Status.cmd shows the line Proxy.

TIME LIMIT PER RUN
Task Scheduler stops a run after 3 hours. A stopped run is not counted: the
System task starts again 15 minutes after the next startup and goes on with
the apps that are left. For the first runs on PCs with many outdated apps,
or VMs that are seldom restarted, allow more time in config.json:
    "MaxRunHours": 8      1 to 72 hours
    "MaxRunHours": 0      no limit
A change on NETLOGON reaches a PC at its next startup, or without a restart
at its next run (for the runs after it). One PC: .\Install.cmd -MaxRunHours 0
(wins over config.json). Hanging installers are still stopped after 60
minutes without progress. Status.cmd shows the line Run limit. Set it back
to 3 once the backlog is gone.

WHERE THINGS ARE ON A DEVICE
  C:\Program Files\KeepItUpToDater     Updater and the installed config.json
  C:\ProgramData\KeepItUpToDater       install.log, system.log, notify.log,
                                       local-config.json, proxy.json
                                       (hidden folder: type the path in Explorer)
  %LOCALAPPDATA%\KeepItUpToDater       user.log of the signed-in user Task
  Scheduler folder \KeepItUpToDater\   Tasks System, User and Notify (not in
  the root)

CHANGES
  1.5.0  Fixes from the security review of 19 Nov 2026 (findings F-01 to F-09,
         see Security-Remediation-1.5.0.txt):
         - Program and data folders: no junctions or symbolic links, owned by
           Administrators, only SYSTEM and Administrators can change them;
           checked again after setting, and by the System task at each run.
         - Windows tools called by full path in the .cmd files and the updater.
         - A missing or damaged installed config.json never means "no
           exclusions": config.lastgood.json is used, otherwise the run stops
           (event 1002) before anything changes. Config files are written
           atomically.
         - Exclusions: only the pins this tool set are lifted (no more pin
           reset for SYSTEM); every exclusion is read back from winget, and the
           run stops if one is missing for an installed app.
         - A separate Invoke-KeepItUpToDater.ps1 next to the installer is only
           used with a valid signature from an approved signer (the installer's
           own, or "TrustedSigners" in config.json); the tasks then run it with
           ExecutionPolicy AllSigned.
         - Proxy: unreadable, automatic (PAC) and Group Policy settings are left
           alone; proxy.json keeps the bypass list; a setting is removed only
           while address and bypass list are still as this tool set them.
         - Older copies: only after a documented winget result; "*" only for
           packages updated in that run and never uninstalls (Unity, PC396);
           "*" is no longer in the shipped config.json.
         - Task result: 0 done, 2 finished with failed updates or warnings,
           1 did not finish. Failed updates are tried again at a later start on
           another day, at most twice before the next weekly run.
         - -ListOnly installs no Visual C++ runtime and repairs no catalogue.
  1.4.8  Older copies for every package: "RemoveOlder": { "*": "" } removes
         older copies of any app winget lists more than once, decided per PC
         from the folders and installer types it finds (Notepad++ and Total
         Commander on PC380, 11 Nov). A copy in the same folder as the
         newest loses only its uninstall entry (saved first), so the new
         files and settings stay. "keep" opts one ID out.
  1.4.7  Older copies: "RemoveOlder" in config.json uninstalls the copies an
         installer left next to the newest one (SoapUI 4.6.x to 5.9.x next
         to 5.10.0 on a test PC, 11 Nov). Uninstall now also lifts the
         exclusions (winget pins) the System task set for SYSTEM; before,
         those apps stayed pinned after the tool was removed.
  1.4.6  Time limit per run: "MaxRunHours" in config.json (1 to 72 hours, or
         0 for no limit; default 3), or -MaxRunHours for one PC. For a large
         backlog of updates on the first runs. The sign-in message no longer
         says apps are updating when that run was stopped.
  1.4.5  Proxy for PCs that reach the internet only through one: "Proxy" and
         "ProxyBypass" in config.json, turned on per PC with -UseProxy or
         "UseProxy" (true, or computer names with * and ?). The System task
         sets it for winget, WinHTTP and SYSTEM's internet settings and uses
         it for its own downloads; off by default. A winget ID shortened
         with "..." in winget's table no longer hides the apps listed after
         it.
  1.4.4  Result messages through the Windows message service, sent by the
         SYSTEM task: the 1.4.3 window ran PowerShell as the user, which
         AppLocker blocks. Notify task now
         runs as SYSTEM at sign-in. "UserTask": false in config.json (off in
         the example config) and Status.cmd shows AppLocker blocks of PowerShell.
  1.4.3  Result window for the user (ShowResults, on in the example config.json):
         while a run is busy, which app is being updated; when it is done,
         what was updated and what could not be. New task Notify.
         -TestSchedule and TestSchedule.cmd to test the scheduling.
  1.4.2  Once per week: a catch-up run late in the week no longer makes the
         next weekly run skip. The week begins two days before the scheduled
         day (Monday 12:00 for Wednesday 12:00).
         The run summary names apps winget listed but did not update (GnuPG,
         MobaXterm on PC024), apps to start again (Outlook, WSL) and a
         previous run that did not finish.
  1.4.1  Exclusions per computer name in config.json (ComputerExcludeIds),
         managed centrally on NETLOGON.
  1.4.0  Exclusions for one computer (-AddLocalExclusion / -RemoveLocalExclusion).
         -RunNow now always runs, also when the last run was recent.
         The run summary names apps that need a restart of the PC.
  1.3.0  Replace rules in config.json: end-of-life Node.js versions are replaced
         with the current Node.js LTS (System task).
  1.2.3  An installer that hangs (VirtualBox) is stopped after 60 minutes without
         progress, so the run continues with the next app.
  1.2.2  Status.cmd: task status and logs without the Task Scheduler console.
  1.2.1  Apps delivered in a zip file (TeamViewer) now install as SYSTEM.
  1.2.0  Visual C++ runtime installed automatically when missing. Exclusions
         read from NETLOGON at every run: a changed config.json needs no restart.

Questions: open an issue in this repository.
