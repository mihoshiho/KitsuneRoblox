; Holds ROBLOX_singletonMutex in its own process, so closing, restarting or updating KitsuneRoblox
; never frees the lock (a freed lock makes other clients close). Quits once no client in this
; Windows session has been open for 2 min (a launch can take 90 s).
; Args (tests only): lock name, client exe, seconds without clients, check interval ms.
KeepLock(lock := "ROBLOX_singletonMutex", exe := "RobloxPlayerBeta.exe", grace := 120, every := 5000) {
    if NameExists("Mutex", "KitsuneKeeper_" lock)
        ExitApp()                               ; one keeper per lock
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
}
