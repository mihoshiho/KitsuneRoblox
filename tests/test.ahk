#Requires AutoHotkey v2.0
#Include ..\lib\Core.ahk
; Run: tools\AutoHotkey64.exe /ErrorStdOut tests\test.ahk   (prints results, exit code = failures)

fails := 0
Check(ok, what) {
    global fails
    FileAppend((ok ? "ok   " : "FAIL ") what "`n", "*")
    fails += !ok
}

me := DllCall("GetCurrentProcessId")

; Close-handle path, on our own process with a test name (no Roblox touched).
name := "KitsuneTest_singletonEvent_" me
h := DllCall("CreateEvent", "Ptr", 0, "Int", 1, "Int", 0, "Str", name, "Ptr")
Check(h, "test event created")
Check(DllCall("OpenEvent", "UInt", 0x100000, "Int", 0, "Str", name, "Ptr"), "event name exists before")
Check(CloseSingleton(me, name), "CloseSingleton found and closed it")
Check(!DllCall("OpenEvent", "UInt", 0x100000, "Int", 0, "Str", name, "Ptr"), "event name is gone after")
Check(!CloseSingleton(me, "KitsuneTest_noSuchEvent"), "unknown name: nothing closed")
Check(!CloseSingleton(999999, name), "bad pid: nothing closed")

; Session filter
Check(SessionOf(me) != "", "own session read")
found := false
for pid in SessionProcs("AutoHotkey64.exe")
    found := found || pid = me
Check(found, "SessionProcs lists this process")

; Game links
Check(GameLink("https://www.roblox.com/games/8304191830/Anime-Adventures?privateServerLinkCode=abc-123") = "roblox://placeId=8304191830&linkCode=abc-123", "private server link")
Check(GameLink("https://www.roblox.com/share?code=xyz789&type=Server") = "roblox://navigation/share_links?code=xyz789&type=Server", "share link")
Check(GameLink("https://www.roblox.com/games/8304191830/Anime") = "roblox://placeId=8304191830", "game page link")
Check(GameLink("hello") = "", "not a link")

; Log states (lines copied from a real Roblox log)
join := "2026-11-23T07:00:22.368Z,13.368044,ba64,6 [FLog::Output] ! Joining game 'f314' place 8304191830 at 10.32.39.67"
gone := "2026-11-23T07:26:35.512Z,1310.512451,afd8,7 [FLog::Network] Time to disconnect replication data: 10.648400"
Check(LogState(join) = "in", "join = in")
Check(LogState(join "`n" gone) = "out", "join then disconnect = out")
Check(LogState(gone "`n" join) = "in", "teleport (disconnect then join) = in")
Check(LogState("noise line") = "", "nothing new")
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

FileAppend(fails " failed`n", "*")
ExitApp(fails)
