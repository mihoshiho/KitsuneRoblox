#Requires AutoHotkey v2.0
#NoTrayIcon
#SingleInstance Off
#Include lib\Core.ahk
; Holds ROBLOX_singletonMutex in its own process, so closing or restarting KitsuneRoblox
; never frees the lock (a freed lock makes other clients close). Quits once no client
; in this Windows session has been open for 2 min (a launch can take 90 s).
; Args (tests only): lock name, client exe, seconds without clients, check interval ms.

lock := A_Args.Length > 0 ? A_Args[1] : "ROBLOX_singletonMutex"
exe := A_Args.Length > 1 ? A_Args[2] : "RobloxPlayerBeta.exe"
grace := A_Args.Length > 2 ? A_Args[3] : 120
every := A_Args.Length > 3 ? A_Args[4] : 5000

if NameExists("Mutex", "KitsuneKeeper_" lock)
    ExitApp()                                   ; one keeper per lock
DllCall("CreateMutex", "Ptr", 0, "Int", 0, "Str", "KitsuneKeeper_" lock, "Ptr")

h := 0, held := 0, idle := A_TickCount
loop {
    if !held && OwnMutex(lock, &h)
        held := DllCall("CreateEvent", "Ptr", 0, "Int", 1, "Int", 1, "Str", "KitsuneKeeper_held_" lock, "Ptr")   ; tells the tool
    if SessionProcs(exe).Length
        idle := A_TickCount
    else if A_TickCount - idle > grace * 1000
        ExitApp()
    Sleep(every)
}
