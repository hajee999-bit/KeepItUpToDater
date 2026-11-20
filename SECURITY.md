Security Policy

Keep It Up To Dater runs as SYSTEM on every computer it is installed on. Security problems in it can affect a whole domain, so please report them privately.

Supported Versions

Security fixes are released as a new version. Computers with self-update on pick it up at their next weekly run once an administrator puts the new installer next to config.json on the share.

Version	Supported
1.5.x (latest: 1.5.1)	Yes
1.4.x and older	No. These lack the fixes from the security review in 1.5.0

If you run an older version, update to the latest 1.5.x.

Reporting a Vulnerability

Do not report security problems in public issues, pull requests or discussions.

Report them privately through GitHub: open the repository's Security tab and choose Report a vulnerability. Only the maintainer sees the report.

Please include:

The version (Status.cmd shows it) and the Windows version and edition
How it was installed: Install.cmd on one computer, or a GPO startup script, and whether the signed updater or TrustedSigners is used
The settings in config.json that matter for the issue
Which part is affected: the System task, the User task, the Notify task, the installer, self-update or the .cmd files
Steps to reproduce, ideally on a clean test computer, and what an attacker needs first (for example a standard user account on the computer, or write access to the share)
What the attacker gains
Whether you have told anyone else, and any date you plan to publish

Leave out your own organisation's details, such as domain names, computer names and addresses, unless they are needed to understand the issue.

What happens next

This project is maintained in spare time, so these are targets rather than guarantees:

Step	Target
Confirmation that the report arrived	Within 5 working days
First assessment: accepted, declined or more information needed	Within 10 working days
Progress updates while it is open	At least every 14 days
Fix for a critical or high severity issue	Within 30 days of acceptance
Fix for a medium or low severity issue	Within 90 days of acceptance

If the report is accepted, the fix is released as a new version, listed in the change log in docs/README.txt, and described in a GitHub security advisory with the affected versions. A CVE is requested where the issue warrants one. You are credited in the advisory unless you prefer not to be. Please keep the details private until the advisory is out, or for 90 days after your report, whichever comes first. That period can be extended by agreement for complex fixes.

If the report is declined, you get an explanation: for example, the behaviour is by design, it is out of scope, or it could not be reproduced. You are welcome to reply with more information. Declined reports may still lead to a hardening change.

There is no paid bug bounty.

Scope
In scope
A standard user getting code to run as SYSTEM or as another user through this tool. For example: through the program folder (C:\Program Files\KeepItUpToDater), the data folder (C:\ProgramData\KeepItUpToDater), the scheduled tasks, links or junctions, search paths, or files and registry keys a standard user can write
Data that a standard user or a winget package can influence (uninstall entries, winget output, files in a user profile) being used unsafely by the System task
Getting around the signature check for the signed updater, TrustedSigners or self-update when signing is in use
A missing, damaged or crafted local file that makes the System task skip exclusions, ignore the config or act on the wrong app
Changes that leave a computer less secure than before installation or after uninstall, such as proxy, winget or execution policy settings left behind
Secrets or sensitive data in log files that standard users can read
Insecure defaults in the shipped config.json, the .cmd files or the deployment commands
Out of scope

These are known limits of the design:

Anyone who can write to the share folder holding config.json and the installer can change what every computer runs as SYSTEM, as with any Group Policy startup script. Only administrators should be able to write there. Without the signed updater or TrustedSigners, self-update trusts the installer on the share.
Local administrators can change, disable or remove the tool.
The tool installs what winget offers. Vulnerabilities in the apps it installs, in the winget package catalogue or in winget itself belong with the app vendor or with Microsoft.
The deployment commands run the installer with -ExecutionPolicy Bypass, as Group Policy startup scripts usually do. With AllSigned, AppLocker or WDAC, use the signed files as described in docs/Deployment-Commands.txt.
The Windows message shows the signed-in user which apps were updated.

Also out of scope:

Attacks that need administrator rights, physical access or an already compromised computer or domain
The scripts under tests/, which are for development and are not meant for production computers
Findings from automated scanners without a demonstrated impact
Social engineering of the maintainer or users
Testing Rules

Good-faith research that follows these rules is welcome, and no legal action will be taken against it:

Test only on computers and domains you own or are allowed to test. Use a test computer or virtual machine, not production devices.
Never put a changed installer or config.json on a share that production computers read.
Do not access, change or delete data that is not yours.
Give a reasonable time to fix the issue before publishing details.
Running It Securely
Allow only administrators to write to the share folder that holds config.json and the installer.
Where you can, sign the updater and the installer and set TrustedSigners, so computers accept only signed updates. See "Code signing" in docs/Deployment-Commands.txt.
Roll out to a small group first with security filtering, and use -ListOnly or CheckUpdates.cmd to see what would change.
Watch event IDs 1001 and 1002 and the task results with your monitoring.
Keep self-update on, or update by hand, so fixes reach every computer.
