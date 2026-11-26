#Requires AutoHotkey v2.0
#Include ..\lib\Core.ahk
#Include ..\lib\Accounts.ahk
#Include ..\lib\Update.ahk
; Run: tools\AutoHotkey64.exe /ErrorStdOut tests\test.ahk   (prints results, exit code = failures)

fails := 0
Check(ok, what) {
    global fails
    FileAppend((ok ? "ok   " : "FAIL ") what "`n", "*")
    fails += !ok
}

me := DllCall("GetCurrentProcessId"), t0 := A_TickCount

; Close-handle path, on our own process with a test name (no Roblox touched).
name := "KitsuneTest_singletonEvent_" me
h := DllCall("CreateEvent", "Ptr", 0, "Int", 1, "Int", 0, "Str", name, "Ptr")
Check(h, "test event created")
Check(DllCall("OpenEvent", "UInt", 0x100000, "Int", 0, "Str", name, "Ptr"), "event name exists before")
Check(CloseSingleton(me, name), "CloseSingleton found and closed it")
Check(!DllCall("OpenEvent", "UInt", 0x100000, "Int", 0, "Str", name, "Ptr"), "event name is gone after")
Check(!CloseSingleton(me, "KitsuneTest_noSuchEvent"), "unknown name: nothing closed")
Check(!CloseSingleton(999999, name), "bad pid: nothing closed")

; Handoff objects: a mutex, a section and a prefix name, all closed in one pass
mx := DllCall("CreateMutex", "Ptr", 0, "Int", 0, "Str", "KitsuneTest_" me ".mtx", "Ptr")
sh := DllCall("CreateFileMapping", "Ptr", -1, "Ptr", 0, "UInt", 4, "UInt", 0, "UInt", 4096, "Str", "KitsuneTest_" me ".shm", "Ptr")
wn := DllCall("CreateFileMapping", "Ptr", -1, "Ptr", 0, "UInt", 4, "UInt", 0, "UInt", 4096, "Str", "KitsuneTestWND-" me "-GUID", "Ptr")
objs := Map("KitsuneTest_" me ".mtx", "Mutant", "KitsuneTest_" me ".shm", "Section", "KitsuneTestWND-" me "-*", "Section", "KitsuneTest_none", "Event")
Check(CloseSingleton(me, objs) = 3, "mutex, section and prefix name closed")
Check(objs.Count = 1 && objs.Has("KitsuneTest_none"), "only the missing name is left")
Check(!NameExists("Mutex", "KitsuneTest_" me ".mtx"), "mutex name gone")

; Session filter
Check(SessionOf(me) != "", "own session read")
Check(RedirectGuarded() = 0, "no redirection guard here")
found := false
for pid in SessionProcs("AutoHotkey64.exe")
    found := found || pid = me
Check(found, "SessionProcs lists this process")

; Game links
Check(GameLink("https://www.roblox.com/games/8304191830/Anime-Adventures?privateServerLinkCode=abc-123") = "roblox://placeId=8304191830&linkCode=abc-123", "private server link")
Check(GameLink("https://www.roblox.com/share?code=xyz789&type=Server") = "roblox://navigation/share_links?code=xyz789&type=Server", "share link")
Check(GameLink("https://www.roblox.com/games/8304191830/Anime") = "roblox://experiences/start?placeId=8304191830", "game page link")
Check(GameLink("hello") = "", "not a link")
Check(Json(Map("a", 1, "b", ["x", 2.5], "c", {d: 'q"\' "`n"})) = '{"a":1,"b":["x",2.5],"c":{"d":"q\"\\\n"}}', "json of map, array, object, escapes")
g := GameInfo("https://www.roblox.com/games/8304191830/x?privateServerLinkCode=abc")
Check(g.ok && g.vip && g.place = "8304191830", "private server: vip with place id")
g := GameInfo("https://www.roblox.com/share?code=xyz&type=Server")
Check(g.ok && g.vip && g.place = "", "share link: vip, no place id")
g := GameInfo("https://www.roblox.com/games/8304191830/Anime")
Check(g.ok && !g.vip, "game page: not vip")
Check(!GameInfo("hello").ok, "not a link: not ok")

; Updates: version compare, release JSON, file hash
Check(VerNewer("1.0.10", "1.0.9") && VerNewer("v1.1", "1.0.9") && !VerNewer("1.0.0", "1.0") && !VerNewer("0.9", "1.0.0"), "version compare")
rel := '{"tag_name":"v1.2.0","assets":[{"browser_download_url":"https://github.com/mihoshiho/KitsuneRoblox/releases/download/v1.2.0/KitsuneRoblox-Setup.exe"},'
    . '{"browser_download_url":"https://github.com/mihoshiho/KitsuneRoblox/releases/download/v1.2.0/KitsuneRoblox-Setup.exe.sha256"}]}'
r := ParseRelease(rel, "mihoshiho/KitsuneRoblox")
Check(r && r.ver = "1.2.0" && InStr(r.setup, "/KitsuneRoblox-Setup.exe") && InStr(r.sha, ".sha256"), "release parsed")
Check(!ParseRelease(StrReplace(rel, "github.com/mihoshiho/", "github.com/evil/"), "mihoshiho/KitsuneRoblox"), "links of another repo are refused")
Check(!ParseRelease("", "mihoshiho/KitsuneRoblox"), "no release: nothing")
f := A_Temp "\kr-sha-" me ".txt"
FileOpen(f, "w", "UTF-8-RAW").Write("abc")
Check(FileSha256(f) = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", "sha-256 of abc")
FileDelete(f)

; Log states (lines copied from a real Roblox log)
join := "2026-11-23T07:00:22.368Z,13.368044,ba64,6 [FLog::Output] ! Joining game 'f314' place 8304191830 at 10.32.39.67"
gone := "2026-11-23T07:26:35.512Z,1310.512451,afd8,7 [FLog::Network] Time to disconnect replication data: 10.648400"
Check(LogState(join) = "in", "join = in")
Check(LogState(join "`n" gone) = "out", "join then disconnect = out")
Check(LogState(gone "`n" join) = "in", "teleport (disconnect then join) = in")
Check(LogState("noise line") = "", "nothing new")
; real error 256 "Lost connection" ending: join, then disconnect with no "Time to disconnect" after it
lost := join "`n2026-11-23T20:00:59.894Z,6522.894043,bd00,6,Info [DFLog::NetworkClient] Client:Disconnect"
    . "`n2026-11-23T20:01:06.820Z,6529.820312,789c,7 [FLog::Network] Client has been disconnected with reason: Disconnected from game, please reconnect"
Check(LogState(lost) = "out", "lost connection (error 256) = out")
Check(LogState(lost "`n" join) = "in", "teleport after Client:Disconnect = in")
; real server hop: new join, then the old server's "Time to disconnect" 0.05 s later (split over two reads)
hop1 := "2026-11-24T05:44:56.119Z,60.119999,cd50,6 [FLog::Output] ! Joining game 'e950' place 8304191830 at 10.20.4.84"
hop2 := "2026-11-24T05:44:56.164Z,60.164345,dea0,7 [FLog::Network] Time to disconnect replication data: 17.257000"
j := -99
Check(LogState(hop1 "`n" hop2, &j) = "in", "server hop, one read = in")
j := -99, LogState(hop1, &j)
Check(LogState(hop2, &j) = "", "server hop, split reads = nothing new")
Check(LogState("2026-11-24T05:46:00.000Z,124.0,dea0,7 [FLog::Network] Time to disconnect replication data: 1.0", &j) = "out", "drop 1 min after join = out")
; real teleport: old server's Client:Disconnect comes 2 s after the new join
Check(LogState(gone "`n" join "`n2026-11-24T05:36:04.821Z,556.821472,f588,6,Info [DFLog::NetworkClient] Client:Disconnect") = "in", "teleport cleanup Client:Disconnect = still in")
Check(LogState(gone "`nDisconnection: You were kicked from this experience (Error Code: 267)") = "warn", "kick = warn")
Check(LogState("[FLog::Output] Player kicked a ball") = "", "game chat 'kicked' alone is not a warn")

; Log file found by process start time
dir := A_Temp "\kr-test-" me
DirCreate(dir)
ft := 0, x := 0, hp := DllCall("OpenProcess", "UInt", 0x1000, "Int", 0, "UInt", me, "Ptr")
DllCall("GetProcessTimes", "Ptr", hp, "Int64*", &ft, "Int64*", &x, "Int64*", &x, "Int64*", &x), DllCall("CloseHandle", "Ptr", hp)
t := DateAdd(16010101, ft // 10000000 + 2, "Seconds")
good := dir "\0.748_" SubStr(t, 1, 8) "T" SubStr(t, 9) "Z_Player_AAAAA_last.log"
FileAppend("", good)
FileAppend("", dir "\0.748_" SubStr(t, 1, 8) "T" SubStr(t, 9) "Z_Player_BBBBB_CrashHandler_last.log")
FileAppend("", dir "\0.748_20200101T000000Z_Player_CCCCC_last.log")
Check(FindLog(me, dir) = good, "FindLog picks the log started with the process")
DirDelete(dir, true)

; Accounts: tracker, command line
Check(StrLen(NewTracker()) = 12, "tracker id is 12 digits")
Check(InStr(CmdLine(me), "test.ahk"), "command line read")

; Own Roblox path per account: junction made, moved to a new version, removed without touching Roblox's files
root := A_Temp "\kr-junc-" me, v1 := root "\Versions\version-aaa", v2 := root "\Versions\version-bbb", prof := root "\profiles\p1"
DirCreate(v1), DirCreate(v2), DirCreate(prof)
FileAppend("x", v1 "\RobloxPlayerBeta.exe"), FileAppend("x", v2 "\RobloxPlayerBeta.exe")
Check(AcctExe(prof, v1) = prof "\Roblox-version-aaa\RobloxPlayerBeta.exe", "junction made")
Check(InStr(FileGetAttrib(prof "\Roblox-version-aaa"), "L"), "it is a link, not a copy")
Check(AcctExe(prof, v1) = prof "\Roblox-version-aaa\RobloxPlayerBeta.exe", "second call: same path")
Check(AcctExe(prof, v2) = prof "\Roblox-version-bbb\RobloxPlayerBeta.exe" && !DirExist(prof "\Roblox-version-aaa"), "new version: old link gone")
Check(FileExist(v1 "\RobloxPlayerBeta.exe"), "old version's files kept")
Check(AcctExe(prof, root "\Versions\none") = "", "no Roblox there: empty")
DropJunctions(prof), DirDelete(prof, true)
Check(FileExist(v2 "\RobloxPlayerBeta.exe"), "profile deleted: Roblox's files kept")
DirDelete(root, true)
accts := Map("111", {profile: "p1"}, "222", {profile: "p12"}, "333", {profile: ""})
Check(AcctOfPath("C:\pr\p12\Roblox-v\RobloxPlayerBeta.exe", accts, "C:\pr") = "222", "path finds its account")
Check(AcctOfPath("C:\Fishstrap\Versions\v\RobloxPlayerBeta.exe", accts, "C:\pr") = "", "Fishstrap's own path: no account")

; Trim on this process: 300 MB touched, trim moves it out, and no cap stays after
big := Buffer(300 << 20)
loop (300 << 20) // 4096
    NumPut("UChar", 1, big, (A_Index - 1) * 4096)
before := RamOf(me)
Check(TrimRam(me), "trim done")
Check(RamOf(me) < before - 200, "trim moved RAM out (" before " -> " RamOf(me) " MB)")
loop (300 << 20) // 4096
    NumPut("UChar", 2, big, (A_Index - 1) * 4096)
Check(RamOf(me) > 250, "no cap after trim (" RamOf(me) " MB)")
big := 0
Check(!TrimRam(999999), "bad pid: nothing")

; Crash report found by pid (line copied from a real Roblox crash handler log)
dir := A_Temp "\kr-crash-" me
DirCreate(dir)
FileAppend("[FLog::CrashpadHandlerLog] WARNING duplicate key PID, discarding value 48876`r`n", dir "\a_Player_X_CrashHandler_last.log")
FileAppend("normal crash handler log", dir "\b_Player_Y_CrashHandler_last.log")
Check(Crashed(48876, dir), "crash report found")
Check(!Crashed(4887, dir) && !Crashed(488760, dir), "other pids: no crash")
DirDelete(dir, true)
Check(Abs(AgeOf(me) - (A_TickCount - t0) // 1000) <= 3, "process age read")   ; vs the test's own run time: a busy PC makes it slow
f := A_Temp "\kr-hung-" me ".log"
FileAppend("2026-11-23T20:53:55.160Z,215.160339,c878,6,Error [FLog::CrashReportLog] Terminated due it was hanging past timeout.`n", f)
Check(Hung(f), "frozen client ended by Roblox = hung")
FileDelete(f), FileAppend("normal end`n", f)
Check(!Hung(f) && !Hung(f "x"), "normal log or no log: not hung")
FileDelete(f)

; Lock: we own it, another process can't; a dead owner's lock comes to us
name := "KitsuneTest_mutex_" me, h := 0
child := A_Temp "\kr-mutex-child-" me ".ahk"
FileAppend('h := DllCall("CreateMutex", "Ptr", 0, "Int", 0, "Str", "' name '", "Ptr"), r := DllCall("WaitForSingleObject", "Ptr", h, "UInt", 0, "UInt")`nif A_Args.Length`n    Sleep(1500)`nExitApp(r)', child)
Check(RunWait('"' A_AhkPath '" "' child '"') = 0, "free lock: child gets it")
Run('"' A_AhkPath '" "' child '" hold', , , &cp)
loop 50 {                                       ; wait until the child made it (a busy PC starts it slowly)
    if NameExists("Mutex", name)
        break
    Sleep(100)
}
Sleep(200)
Check(!OwnMutex(name, &h), "child holds it: we don't")
ProcessWaitClose(cp, 5)
Check(OwnMutex(name, &h), "child died holding it: now ours")
Check(RunWait('"' A_AhkPath '" "' child '"') = 0x102, "we hold it: child can't get it")
FileDelete(child), DllCall("CloseHandle", "Ptr", h)

; Lock keeper: started by a process that exits at once, holds the lock while a fake client runs, quits after
name := "KitsuneTest_keeper_" me, h := 0, fake := A_Temp "\kr-fake-" me ".exe", sleeper := A_Temp "\kr-sleep-" me ".ahk"
FileCopy(A_AhkPath, fake, true), FileAppend("Sleep(60000)", sleeper)
Run('"' fake '" "' sleeper '"', , , &fp)
RunWait('"' A_AhkPath '" /ErrorStdOut "' A_ScriptDir '\launch-keeper.ahk" "' name '" "kr-fake-' me '.exe"')
Sleep(1500)
Check(NameExists("Event", "KitsuneKeeper_held_" name), "keeper holds the lock after its starter exited")
Check(!OwnMutex(name, &h), "keeper holds it: we don't")
RunWait('"' A_AhkPath '" "' A_ScriptDir '\launch-keeper.ahk" "' name '" "kr-fake-' me '.exe"'), Sleep(500)
n := 0
for p in ComObjGet("winmgmts:").ExecQuery("SELECT ProcessId FROM Win32_Process WHERE CommandLine LIKE '%LockKeeper.ahk%" name "%'")
    n++
Check(n = 1, "second start: still one keeper")
Sleep(2000)
Check(NameExists("Mutex", "KitsuneKeeper_" name), "keeper stays while a client runs")
ProcessClose(fp), ProcessWaitClose(fp, 5), Sleep(3500)
Check(!NameExists("Mutex", "KitsuneKeeper_" name), "keeper quits after no client for 2 s")
Check(OwnMutex(name, &h), "lock free after keeper quits")
DllCall("CloseHandle", "Ptr", h), FileDelete(fake), FileDelete(sleeper)

FileAppend(fails " failed`n", "*")
ExitApp(fails)
