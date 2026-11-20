Tests
=====

The test scripts expect all files in one folder. Copy the files of the repository root
(Install-KeepItUpToDater.ps1, config.json and the .cmd files) and of this folder
(including replay\*.txt) into one empty test folder, then run as a standard user:

  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\test.ps1     (1.0.0 to 1.4.7 cases)
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\test148.ps1  (1.4.8 cases)
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\test150.ps1  (1.5.0 security cases)

stub.ps1 stands in for winget and fake-un.ps1 for uninstallers; nothing is installed or
removed on the computer. Install-143.ps1 and Install-144.ps1 are older releases used by
the upgrade cases. Test-F01-Admin.ps1 needs administrator rights and only works in
C:\ProgramData\KIUTD-F01Test, which it removes at the end.
