; Roblox accounts: saved login cookie (DPAPI, only this Windows user can read it) -> one-time ticket -> launch.
; Same idea as Roblox Account Manager: auth.roblox.com ticket + roblox-player: link with browsertrackerid.

global RbxLast := ""   ; last Roblox answer (status + short body), for the log

; Encrypt text for this Windows user. Returns base64.
Protect(text) {
    inBuf := Buffer(StrPut(text, "UTF-8") - 1)
    StrPut(text, inBuf, "UTF-8")
    blobIn := Blob(inBuf), blobOut := Buffer(16, 0)
    if !DllCall("crypt32\CryptProtectData", "Ptr", blobIn, "Ptr", 0, "Ptr", 0, "Ptr", 0, "Ptr", 0, "UInt", 1, "Ptr", blobOut)
        throw Error("CryptProtectData failed")
    s := ToBase64(NumGet(blobOut, 8, "Ptr"), NumGet(blobOut, 0, "UInt"))
    DllCall("LocalFree", "Ptr", NumGet(blobOut, 8, "Ptr"))
    return s
}

; Decrypt Protect() output. "" if it can't (other user / broken data).
Unprotect(b64) {
    if b64 = "" || !(raw := FromBase64(b64))
        return ""
    blobOut := Buffer(16, 0)
    if !DllCall("crypt32\CryptUnprotectData", "Ptr", Blob(raw), "Ptr", 0, "Ptr", 0, "Ptr", 0, "Ptr", 0, "UInt", 1, "Ptr", blobOut)
        return ""
    s := StrGet(NumGet(blobOut, 8, "Ptr"), NumGet(blobOut, 0, "UInt"), "UTF-8")
    DllCall("LocalFree", "Ptr", NumGet(blobOut, 8, "Ptr"))
    return s
}

Blob(buf) {                                     ; DATA_BLOB {DWORD cb; BYTE* pb}; the caller keeps buf alive
    b := Buffer(16, 0), NumPut("UInt", buf.Size, b, 0), NumPut("Ptr", buf.Ptr, b, 8)
    return b
}

ToBase64(ptr, size) {
    n := 0
    DllCall("crypt32\CryptBinaryToStringW", "Ptr", ptr, "UInt", size, "UInt", 0x40000001, "Ptr", 0, "UInt*", &n)
    out := Buffer(n * 2)
    DllCall("crypt32\CryptBinaryToStringW", "Ptr", ptr, "UInt", size, "UInt", 0x40000001, "Ptr", out, "UInt*", &n)
    return StrGet(out, n, "UTF-16")
}

FromBase64(s) {
    n := 0
    if !DllCall("crypt32\CryptStringToBinaryW", "Str", s, "UInt", 0, "UInt", 1, "Ptr", 0, "UInt*", &n, "Ptr", 0, "Ptr", 0) || !n
        return ""
    buf := Buffer(n)
    DllCall("crypt32\CryptStringToBinaryW", "Str", s, "UInt", 0, "UInt", 1, "Ptr", buf, "UInt*", &n, "Ptr", 0, "Ptr", 0)
    return buf
}

; One HTTPS call as this account. Returns the WinHttpRequest (Status, ResponseText, GetResponseHeader).
; Slow network: one retry after a timeout (seen: 8-11 s to reach Roblox now and then).
RbxHttp(method, url, cookie, body := "", csrf := "") {
    global RbxLast
    loop 2 {
        r := ComObject("WinHttp.WinHttpRequest.5.1")
        r.SetTimeouts(10000, 10000, 20000, 20000)
        r.Open(method, url, false)
        r.SetRequestHeader("Cookie", ".ROBLOSECURITY=" cookie)
        r.SetRequestHeader("Referer", "https://www.roblox.com/")
        r.SetRequestHeader("Origin", "https://www.roblox.com")
        r.SetRequestHeader("Content-Type", "application/json")
        r.SetRequestHeader("RBXAuthenticationNegotiation", "1")
        if csrf
            r.SetRequestHeader("X-CSRF-TOKEN", csrf)
        try r.Send(body)
        catch as e {
            m := StrSplit(e.Message, "`n")
            RbxLast := "network error: " Trim(m.Length > 1 ? m[2] : m[1])
            if A_Index = 2
                throw e
            continue
        }
        RbxLast := "HTTP " r.Status " " SubStr(RegExReplace(r.ResponseText, "\s+", " "), 1, 120)   ; for the log when Roblox says no
        return r
    }
}

; POST that needs a CSRF token: the first try returns 403 with the token, the second uses it.
RbxPost(url, cookie, body := "{}") {
    r := RbxHttp("POST", url, cookie, body)
    if r.Status = 403 && (t := Header(r, "x-csrf-token"))
        r := RbxHttp("POST", url, cookie, body, t)
    return r
}

Header(r, name) {
    try return r.GetResponseHeader(name)
    return ""
}

; {id, name} of the logged-in account, or "" if the cookie no longer works.
RbxUser(cookie) {
    try {
        r := RbxHttp("GET", "https://users.roblox.com/v1/users/authenticated", cookie)
        if r.Status = 200 && RegExMatch(r.ResponseText, '"id"\s*:\s*(\d+)', &i) && RegExMatch(r.ResponseText, '"name"\s*:\s*"([^"]+)"', &n)
            return {id: i[1], name: n[1]}
    }
    return ""
}

; One-time login ticket. "" = cookie expired or Roblox said no.
RbxTicket(cookie) {
    try return Header(RbxPost("https://auth.roblox.com/v1/authentication-ticket/", cookie), "rbx-authentication-ticket")
    return ""
}

; Game link -> {place, linkCode}. Share links (roblox.com/share?code=...) are resolved with an account cookie.
GameInfo(url, cookie := "") {
    if RegExMatch(url, "games/(\d+).*privateServerLinkCode=([\w-]+)", &m)
        return {place: m[1], linkCode: m[2]}
    if RegExMatch(url, "share\?code=([\w-]+).*type=Server", &m) && cookie {
        try {
            r := RbxPost("https://apis.roblox.com/sharelinks/v1/resolve-link", cookie, '{"linkId":"' m[1] '","linkType":"Server"}')
            if RegExMatch(r.ResponseText, '"placeId"\s*:\s*(\d+)', &p) && RegExMatch(r.ResponseText, '"linkCode"\s*:\s*"([\w-]+)"', &c)
                return {place: p[1], linkCode: c[1]}
        }
        return ""
    }
    if RegExMatch(url, "games/(\d+)", &m)
        return {place: m[1], linkCode: ""}
    return ""
}

; roblox-player: link that opens the game logged in as the ticket's account.
; browsertrackerid is ours per account, so we can tell its client apart later (it shows in the command line).
PlayLink(ticket, game, tracker) {
    pl := "https://assetgame.roblox.com/game/PlaceLauncher.ashx?"
        . (game.linkCode ? "request=RequestPrivateGame&placeId=" game.place "&linkCode=" game.linkCode
                         : "request=RequestGame&browserTrackerId=" tracker "&placeId=" game.place "&isPlayTogetherGame=false")
    ms := DateDiff(A_NowUTC, 19700101, "Seconds") * 1000
    return "roblox-player:1+launchmode:play+gameinfo:" ticket "+launchtime:" ms "+placelauncherurl:" UrlEncode(pl)
        . "+browsertrackerid:" tracker "+robloxLocale:en_us+gameLocale:en_us+channel:+LaunchExp:InApp"
}

UrlEncode(s) {
    out := ""
    loop parse s
        out .= RegExMatch(A_LoopField, "[\w.~-]") ? A_LoopField : Format("%{:02X}", Ord(A_LoopField))
    return out
}

NewTracker() => Random(100000, 174999) "" Random(100000, 899999)

; Command line of a process ("" if gone).
CmdLine(pid) {
    for p in ComObjGet("winmgmts:").ExecQuery("SELECT CommandLine FROM Win32_Process WHERE ProcessId = " pid)
        try return String(p.CommandLine)
    return ""
}
