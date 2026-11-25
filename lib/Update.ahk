; Updates from the newest GitHub release: KitsuneRoblox-Setup.exe, run only if its SHA-256 matches
; the release's KitsuneRoblox-Setup.exe.sha256.

; True if version a is newer than b ("1.2.10" > "1.2.9", a leading "v" is fine).
VerNewer(a, b) {
    a := StrSplit(LTrim(a, "vV"), "."), b := StrSplit(LTrim(b, "vV"), ".")
    loop Max(a.Length, b.Length) {
        x := A_Index <= a.Length && IsInteger(a[A_Index]) ? Integer(a[A_Index]) : 0
        y := A_Index <= b.Length && IsInteger(b[A_Index]) ? Integer(b[A_Index]) : 0
        if x != y
            return x > y
    }
    return false
}

; GitHub "latest release" JSON -> {ver, setup, sha} (download links), or 0. Only links of this repo's releases count.
ParseRelease(json, repo) {
    base := "https://github.com/" repo "/releases/download/"
    if !RegExMatch(json, '"tag_name"\s*:\s*"v?(\d+(?:\.\d+){0,3})"', &t)
        return 0
    setup := sha := ""
    pos := 1
    while pos := RegExMatch(json, '"browser_download_url"\s*:\s*"([^"]+)"', &m, pos) {
        pos += m.Len
        if InStr(m[1], base) != 1
            continue
        if RegExMatch(m[1], "/KitsuneRoblox-Setup\.exe$")
            setup := m[1]
        else if RegExMatch(m[1], "/KitsuneRoblox-Setup\.exe\.sha256$")
            sha := m[1]
    }
    return setup && sha ? {ver: t[1], setup: setup, sha: sha} : 0
}

; GET a URL as text (blocking). "" on any error. Tried twice: the first lookup of a host can take over 10 s here.
HttpText(url) {
    loop 2
        try {
            r := ComObject("WinHttp.WinHttpRequest.5.1"), r.SetTimeouts(10000, 10000, 10000, 10000)
            r.Open("GET", url), r.SetRequestHeader("User-Agent", "KitsuneRoblox"), r.Send()
            if r.Status = 200
                return r.ResponseText
        }
    return ""
}

; Lower-case hex SHA-256 of a file ("" if it can't be read).
FileSha256(path) {
    try buf := FileRead(path, "RAW")
    catch
        return ""
    alg := 0, out := Buffer(32), hex := ""
    if DllCall("bcrypt\BCryptOpenAlgorithmProvider", "Ptr*", &alg, "Str", "SHA256", "Ptr", 0, "UInt", 0)
        return ""
    st := DllCall("bcrypt\BCryptHash", "Ptr", alg, "Ptr", 0, "UInt", 0, "Ptr", buf, "UInt", buf.Size, "Ptr", out, "UInt", 32)
    DllCall("bcrypt\BCryptCloseAlgorithmProvider", "Ptr", alg, "UInt", 0)
    if st
        return ""
    loop 32
        hex .= Format("{:02x}", NumGet(out, A_Index - 1, "UChar"))
    return hex
}
