#Requires AutoHotkey v2.0
#Include ..\lib\Core.ahk
#Include ..\lib\Accounts.ahk
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

; Accounts: encryption, links, account match
secret := "_|WARNING:-DO-NOT-SHARE-THIS.--fake-test-cookie-ąé"
enc := Protect(secret)
Check(enc != "" && !InStr(enc, "fake"), "cookie is encrypted")
Check(Unprotect(enc) = secret, "cookie decrypts back")
Check(Unprotect("bm90IGEgYmxvYg==") = "", "broken data gives nothing")
Check(UrlEncode("a b&c=d/é") = "a%20b%26c%3Dd%2F%E9", "url encode")
g := GameInfo("https://www.roblox.com/games/8304191830/x?privateServerLinkCode=abc-123")
Check(g.place = "8304191830" && g.linkCode = "abc-123", "private server info")
g2 := GameInfo("https://www.roblox.com/games/8304191830/Anime")
Check(g2.place = "8304191830" && g2.linkCode = "", "public game info")
Check(GameInfo("https://www.roblox.com/share?code=xyz&type=Server") = "", "share link needs a cookie")
pl := PlayLink("TICKET", g, "123456654321")
Check(RegExMatch(pl, "^roblox-player:1\+launchmode:play\+gameinfo:TICKET\+launchtime:\d{13}\+placelauncherurl:https%3A%2F%2Fassetgame"), "play link start")
Check(InStr(pl, "RequestPrivateGame%26placeId%3D8304191830%26linkCode%3Dabc-123") && InStr(pl, "+browsertrackerid:123456654321+"), "play link game and tracker")
Check(StrLen(NewTracker()) = 12, "tracker id is 12 digits")
Check(InStr(CmdLine(me), "test.ahk"), "command line read")
Check(RbxTicket("not-a-real-cookie") = "", "bad cookie gives no ticket")

FileAppend(fails " failed`n", "*")
ExitApp(fails)
