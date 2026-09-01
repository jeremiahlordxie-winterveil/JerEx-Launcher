Option Explicit

Dim shell, fso, scriptDir, ps1Path, cmd, exitCode

Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

scriptDir = fso.GetParentFolderName(WScript.ScriptFullName)
ps1Path = fso.BuildPath(scriptDir, "JerEx-launcher.ps1")

If Not fso.FileExists(ps1Path) Then
  MsgBox "Missing launcher script:" & vbCrLf & ps1Path, vbCritical, "JEL"
  WScript.Quit 1
End If

cmd = "powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File """ & ps1Path & """ -InstallDir """ & scriptDir & """"
exitCode = shell.Run(cmd, 0, True)

WScript.Quit exitCode
