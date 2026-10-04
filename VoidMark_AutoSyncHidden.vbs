Option Explicit

Dim shell, fso, here, ps, watcher, cmd
Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

here = fso.GetParentFolderName(WScript.ScriptFullName)
watcher = fso.BuildPath(here, "VoidMark_AutoSyncWatcher.ps1")
ps = shell.ExpandEnvironmentStrings("%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe")

cmd = Chr(34) & ps & Chr(34) _
    & " -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File " _
    & Chr(34) & watcher & Chr(34)

shell.CurrentDirectory = here
' 0 = hidden window, False = do not wait for the watcher to exit.
shell.Run cmd, 0, False
