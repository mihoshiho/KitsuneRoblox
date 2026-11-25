; Roblox accounts: each one has a profile folder with its saved Roblox login and its own path to Roblox.

NewTracker() => Random(100000, 174999) "" Random(100000, 899999)

; Command line of a process ("" if gone).
CmdLine(pid) {
    for p in ComObjGet("winmgmts:").ExecQuery("SELECT CommandLine FROM Win32_Process WHERE ProcessId = " pid)
        try return String(p.CommandLine)
    return ""
}

; Roblox's own saved login (encrypted by Windows for this user). Never read here, only copied per account.
RobloxLogin() => EnvGet("LOCALAPPDATA") "\Roblox\LocalStorage\RobloxCookies.dat"

; Roblox exe for one account: a junction in its profile folder to Fishstrap's Roblox version folder.
; A new client finds an open one by names made from its exe path, so a path per account keeps them apart.
AcctExe(dir, src := "") {
    src := src || RegRead("HKCU\Software\Fishstrap", "PlayerPath", "")
    if src = "" || !FileExist(src "\RobloxPlayerBeta.exe")
        return ""
    SplitPath(src, &ver), j := dir "\Roblox-" ver
    DropJunctions(dir, j)
    if !DirExist(j)
        RunWait(A_ComSpec ' /c mklink /J "' j '" "' src '"', , "Hide")
    return FileExist(j "\RobloxPlayerBeta.exe") ? j "\RobloxPlayerBeta.exe" : ""
}

; Remove the Roblox junctions in a profile folder, except keep. RemoveDirectory removes the link only,
; never Roblox's files: call it before deleting a profile folder.
DropJunctions(dir, keep := "") {
    loop files dir "\Roblox-*", "D"
        if A_LoopFileFullPath != keep
            DllCall("RemoveDirectory", "Str", A_LoopFileFullPath)
}

; Account id whose profile folder holds this exe path ("" if none).
AcctOfPath(path, accts, root) {
    for id, a in accts
        if a.profile != "" && InStr(path, root "\" a.profile "\") = 1
            return id
    return ""
}
