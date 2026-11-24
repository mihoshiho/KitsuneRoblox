; Roblox accounts: each one has a saved login browser profile. Play opens Roblox's own start page in it
; with real Edge, so Roblox makes the login ticket itself (Roblox refuses tickets made in WebView2).

EdgeExe() {
    try return RegRead("HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\msedge.exe")
    p := EnvGet("ProgramFiles(x86)") "\Microsoft\Edge\Application\msedge.exe"
    return FileExist(p) ? p : ""
}

; Edge processes that use this profile folder (never the user's own Edge).
EdgeProcs(dir) {
    pids := []
    for p in ComObjGet("winmgmts:").ExecQuery("SELECT ProcessId, CommandLine FROM Win32_Process WHERE Name = 'msedge.exe'")
        try if InStr(StrReplace(p.CommandLine, '"') " ", "--user-data-dir=" dir " ")
            pids.Push(p.ProcessId)
    return pids
}

; Let roblox.com open roblox-player: links in this profile without the "Open Roblox?" prompt
; (same as ticking "Always allow"). Call only while Edge is closed on it.
AllowRoblox(dir) {
    f := dir "\Default\Preferences"
    t := FileExist(f) ? FileRead(f, "UTF-8") : "{}"
    if InStr(t, '"roblox-player"') || InStr(t, '"protocol_handler"')   ; shortcut: other saved protocol choices = prompt once, tick "Always allow"
        return
    pair := '"protocol_handler":{"allowed_origin_protocol_pairs":{"https://www.roblox.com":{"roblox-player":true}}}'
    t := RegExReplace(t, "^\s*\{", "{" pair (RegExMatch(t, "^\s*\{\s*\}") ? "" : ","), , 1)
    DirCreate(dir "\Default")
    f := FileOpen(f, "w", "UTF-8-RAW"), f.Write(t), f.Close()
}

; Game link -> page that starts the game by itself ("" if not a game link).
; Private server and share links already start the game; a plain game page needs games/start.
PlayPage(url) {
    url := Trim(url)
    if RegExMatch(url, "i)^(https?://)?(www\.)?roblox\.com/.*(privateServerLinkCode=|share\?code=)")
        return RegExMatch(url, "i)^https?://") ? url : "https://" url
    if RegExMatch(url, "games/(\d+)", &m)
        return "https://www.roblox.com/games/start?placeId=" m[1]
    return ""
}

NewTracker() => Random(100000, 174999) "" Random(100000, 899999)

; Command line of a process ("" if gone).
CmdLine(pid) {
    for p in ComObjGet("winmgmts:").ExecQuery("SELECT CommandLine FROM Win32_Process WHERE ProcessId = " pid)
        try return String(p.CommandLine)
    return ""
}

; Roblox's own saved login (encrypted by Windows for this user). Never read here, only copied per account.
RobloxLogin() => EnvGet("LOCALAPPDATA") "\Roblox\LocalStorage\RobloxCookies.dat"
