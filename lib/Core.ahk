; Plain helpers with no GUI, so tests\test.ahk can check them.

; Windows session of a process ("" if it is gone or we can't read it).
SessionOf(pid) {
    sid := 0
    return DllCall("ProcessIdToSessionId", "UInt", pid, "UInt*", &sid) ? sid : ""
}

; Process ids of this exe in OUR session only (never another user's / RDP farm's).
SessionProcs(exe) {
    me := SessionOf(DllCall("GetCurrentProcessId")), list := []
    for p in ComObjGet("winmgmts:").ExecQuery("SELECT ProcessId FROM Win32_Process WHERE Name = '" exe "'")
        if SessionOf(p.ProcessId) = me
            list.Push(p.ProcessId)
    return list
}

; Close named objects a Roblox client holds, like Process Explorer's "Close Handle".
; Once they are gone the next client thinks it is the only one, so both stay open.
; objs: a name (an Event) or a Map of name -> kind ("Event", "Mutant", "Section"); a name ending in * matches by prefix.
; Closed names are removed from the Map. The session number comes from the target process. Returns how many were closed.
CloseSingleton(pid, objs := "ROBLOX_singletonEvent") {
    static types := Map()                       ; ObjectTypeIndex -> type name, same for the whole boot
    if Type(objs) = "String"
        objs := Map(objs, "Event")
    if (sid := SessionOf(pid)) = ""
        return 0
    base := "\Sessions\" sid "\BaseNamedObjects\", kinds := Map()
    for name, kind in objs
        kinds[kind] := 1
    if !hProc := DllCall("OpenProcess", "UInt", 0x40 | 0x1000, "Int", 0, "UInt", pid, "Ptr")   ; DUP_HANDLE | QUERY_LIMITED
        return 0
    size := 0x400000
    loop {                                      ; SystemExtendedHandleInformation (64); grow until it fits
        buf := Buffer(size), need := 0
        st := DllCall("ntdll\NtQuerySystemInformation", "Int", 64, "Ptr", buf, "UInt", size, "UInt*", &need, "UInt")
        if st != 0xC0000004 || A_Index > 5
            break
        size := need + 0x100000
    }
    done := Map(), me := DllCall("GetCurrentProcess", "Ptr")
    if st = 0
        loop NumGet(buf, 0, "UPtr") {
            off := 16 + (A_Index - 1) * 40      ; SYSTEM_HANDLE_TABLE_ENTRY_INFO_EX is 40 bytes on x64
            if NumGet(buf, off + 8, "UPtr") != pid
                continue
            ti := NumGet(buf, off + 30, "UShort")
            if types.Has(ti) && !kinds.Has(types[ti])
                continue
            h := NumGet(buf, off + 16, "UPtr"), dup := 0
            if !DllCall("DuplicateHandle", "Ptr", hProc, "Ptr", h, "Ptr", me, "Ptr*", &dup, "UInt", 0, "Int", 0, "UInt", 2)
                continue
            if !types.Has(ti)
                types[ti] := ObjectInfo(dup, 2)
            ; only names of the wanted kinds are read: a name query on some pipe handles can hang
            if kinds.Has(types[ti]) && InStr(n := ObjectInfo(dup, 1), base) = 1 {
                n := SubStr(n, StrLen(base) + 1)
                for name, kind in objs
                    if kind = types[ti] && (n = name || SubStr(name, -1) = "*" && InStr(n, SubStr(name, 1, -1)) = 1) {
                        if DllCall("DuplicateHandle", "Ptr", hProc, "Ptr", h, "Ptr", 0, "Ptr", 0, "UInt", 0, "Int", 0, "UInt", 1)   ; DUPLICATE_CLOSE_SOURCE
                            done[name] := 1             ; a client can hold one name twice: close every handle
                        break
                    }
            }
            DllCall("CloseHandle", "Ptr", dup)
        }
    DllCall("CloseHandle", "Ptr", hProc)
    for name in done
        objs.Delete(name)
    return done.Count
}

; NtQueryObject: class 1 = name, 2 = type name. Both start with a UNICODE_STRING.
ObjectInfo(h, cls) {
    buf := Buffer(2048)
    if DllCall("ntdll\NtQueryObject", "Ptr", h, "Int", cls, "Ptr", buf, "UInt", buf.Size, "Ptr", 0, "UInt")
        return ""
    p := NumGet(buf, 8, "Ptr")
    return p ? StrGet(p, NumGet(buf, 0, "UShort") // 2, "UTF-16") : ""
}

; Game link -> roblox:// link that opens the game directly ("" if not a game link).
GameLink(url) {
    url := Trim(url)
    if RegExMatch(url, "^roblox://")
        return url
    if RegExMatch(url, "games/(\d+).*privateServerLinkCode=([\w-]+)", &m)
        return "roblox://placeId=" m[1] "&linkCode=" m[2]
    if RegExMatch(url, "share\?code=([\w-]+).*type=Server", &m)
        return "roblox://navigation/share_links?code=" m[1] "&type=Server"
    if RegExMatch(url, "games/(\d+)", &m)
        return "roblox://experiences/start?placeId=" m[1]
    return ""
}

; Read new log text and return the last state seen: "in", "out", "warn" or "" (nothing new).
; A teleport also logs "disconnect", but a new "Joining game" follows within seconds, so the caller waits a bit.
; joinAt: client uptime (2nd log field, seconds) of the last join, kept by the caller across reads.
; Out lines within 10 s after a join are the old server's cleanup after a teleport, not a disconnect.
LogState(text, &joinAt := -99) {
    state := ""
    loop parse text, "`n", "`r" {
        up := StrSplit(A_LoopField, ",", , 3), up := up.Length > 2 && IsNumber(up[2]) ? up[2] + 0 : ""
        if InStr(A_LoopField, "! Joining game") || InStr(A_LoopField, "initiateTeleport")
            state := "in", joinAt := up != "" ? up : joinAt
        else if (InStr(A_LoopField, "Time to disconnect replication data") || InStr(A_LoopField, "leaveUGCGameInternal")
            || InStr(A_LoopField, "Client has been disconnected with reason"))   ; "Lost connection" popup (error 256); not "Client:Disconnect", a teleport logs it after the new join
            && !(up != "" && up - joinAt < 10)     ; shortcut: a real drop within 10 s of joining is missed, rare
            state := "out"
        ; shortcut: kick/ban text guessed from known popups, no real kick log seen yet; refine with a real one
        if RegExMatch(A_LoopField, "i)\b(kick(ed)?|bann?ed)\b|same account") && RegExMatch(A_LoopField, "i)disconnect|lost connection|error code")
            return "warn"
    }
    return state
}

; Log file of a client: the Player log whose name time is closest to the process start (within 20 s).
; shortcut: matches by start time, two clients started in the same second could swap logs.
FindLog(pid, dir := "") {
    dir := dir || EnvGet("LOCALAPPDATA") "\Roblox\logs"
    if !hProc := DllCall("OpenProcess", "UInt", 0x1000, "Int", 0, "UInt", pid, "Ptr")
        return ""
    ft := 0, x := 0
    ok := DllCall("GetProcessTimes", "Ptr", hProc, "Int64*", &ft, "Int64*", &x, "Int64*", &x, "Int64*", &x)
    DllCall("CloseHandle", "Ptr", hProc)
    if !ok
        return ""
    start := DateAdd(16010101, ft // 10000000, "Seconds")     ; UTC, same as the log name
    best := "", bestGap := 20
    loop files dir "\*_Player_*.log" {
        if InStr(A_LoopFileName, "CrashHandler") || !RegExMatch(A_LoopFileName, "_(\d{8})T(\d{6})Z_", &m)
            continue
        if (gap := Abs(DateDiff(m[1] m[2], start, "Seconds"))) <= bestGap
            best := A_LoopFileFullPath, bestGap := gap
    }
    return best
}

; Trim: Windows moves the process's unused memory to disk once. No limit after it: the game takes
; back what it needs, so it can't freeze from it. Also removes a hard cap an older version set.
TrimRam(pid) {
    if !(h := DllCall("OpenProcess", "UInt", 0x1100, "Int", 0, "UInt", pid, "Ptr"))   ; SET_QUOTA | QUERY_LIMITED_INFORMATION
        return false
    lo := 0, hi := 0, fl := 0
    if DllCall("GetProcessWorkingSetSizeEx", "Ptr", h, "UPtr*", &lo, "UPtr*", &hi, "UInt*", &fl) && fl & 0x4
        DllCall("SetProcessWorkingSetSizeEx", "Ptr", h, "UPtr", lo, "UPtr", hi, "UInt", 0xA)   ; MIN_DISABLE | MAX_DISABLE
    ok := DllCall("SetProcessWorkingSetSize", "Ptr", h, "Ptr", -1, "Ptr", -1)
    DllCall("CloseHandle", "Ptr", h)
    return ok
}

; Real memory a process uses now, in MB.
RamOf(pid) {
    if !(h := DllCall("OpenProcess", "UInt", 0x1000, "Int", 0, "UInt", pid, "Ptr"))
        return 0
    pmc := Buffer(80, 0), NumPut("UInt", 80, pmc)
    DllCall("psapi\GetProcessMemoryInfo", "Ptr", h, "Ptr", pmc, "UInt", 80)
    DllCall("CloseHandle", "Ptr", h)
    return NumGet(pmc, 16, "UPtr") >> 20                ; WorkingSetSize
}

; Seconds since a process started (0 if it can't be read).
AgeOf(pid) {
    if !(h := DllCall("OpenProcess", "UInt", 0x1000, "Int", 0, "UInt", pid, "Ptr"))
        return 0
    ft := 0, x := 0, now := 0
    DllCall("GetProcessTimes", "Ptr", h, "Int64*", &ft, "Int64*", &x, "Int64*", &x, "Int64*", &x), DllCall("CloseHandle", "Ptr", h)
    DllCall("GetSystemTimeAsFileTime", "Int64*", &now)
    return ft ? (now - ft) // 10000000 : 0
}

; Roblox's crash handler wrote a crash report for this pid in the last 3 minutes.
Crashed(pid, dir := "") {
    dir := dir || EnvGet("LOCALAPPDATA") "\Roblox\logs"
    loop files dir "\*CrashHandler*.log"
        if DateDiff(A_Now, A_LoopFileTimeModified, "Seconds") < 180
            try if RegExMatch(FileRead(A_LoopFilePath), "duplicate key PID, discarding value " pid "\b")
                return true
    return false
}

; Roblox ended a frozen client itself ("Terminated due it was hanging past timeout" at the end of its log).
Hung(log) {
    try {
        f := FileOpen(log, "r", "UTF-8"), f.Pos := Max(0, f.Length - 4096), t := f.Read(), f.Close()
        return !!InStr(t, "hanging past timeout")
    }
    return false
}

; True if a named mutex or event exists (kind "Mutex" or "Event").
NameExists(kind, name) {
    if h := DllCall("Open" kind, "UInt", 0x100000, "Int", 0, "Str", name, "Ptr")
        DllCall("CloseHandle", "Ptr", h)
    return !!h
}

; Own a named lock and keep it (h keeps the handle between calls). False while another process holds it.
; Held by us, Roblox clients never own ROBLOX_singletonMutex, so one closing can't make the others quit.
OwnMutex(name, &h) {
    if !h
        h := DllCall("CreateMutex", "Ptr", 0, "Int", 0, "Str", name, "Ptr")
    r := DllCall("WaitForSingleObject", "Ptr", h, "UInt", 0, "UInt")
    return h && (r = 0 || r = 0x80)                ; 0x80: last owner died, now ours
}
