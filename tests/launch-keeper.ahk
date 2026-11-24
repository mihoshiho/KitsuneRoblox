#Requires AutoHotkey v2.0
; Test helper: starts LockKeeper.ahk (test lock, fake client exe, 2 s grace, 200 ms checks) and exits at once.
Run('"' A_AhkPath '" "' A_ScriptDir '\..\LockKeeper.ahk" "' A_Args[1] '" "' A_Args[2] '" 2 200')
