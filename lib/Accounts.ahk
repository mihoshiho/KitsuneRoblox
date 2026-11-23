; Roblox accounts: each one has a saved login browser profile. Play opens Roblox's own start page in it,
; so Roblox makes the login ticket itself (with its browser-bound security key).

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
