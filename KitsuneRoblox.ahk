#Requires AutoHotkey v2.0
#SingleInstance Off
;@Ahk2Exe-SetName KitsuneRoblox
;@Ahk2Exe-SetDescription KitsuneRoblox
;@Ahk2Exe-SetCopyright mihoshiho
;@Ahk2Exe-SetMainIcon ui\fox.ico
#Include lib\Core.ahk
#Include lib\Accounts.ahk
#Include lib\Keeper.ahk
#Include lib\Update.ahk
#Include lib\WebView2\WebView2.ahk

; KitsuneRoblox: accounts, anti-AFK, auto rejoin and multi-instance for Roblox clients in this Windows session.
SetWorkingDir(A_ScriptDir)                          ; the installed exe finds WebView2Loader.dll next to it
if A_Args.Length && A_Args[1] = "--keeper"
    A_IconHidden := true, KeepLock()                ; never returns
if A_Args.Length > 1 && A_Args[1] = "--check"       ; update check in its own process: a slow network never freezes the window
    rel := ParseRelease(HttpText("https://api.github.com/repos/" App.Repo "/releases/latest"), App.Repo)
    , FileOpen(A_Args[2], "w", "UTF-8-RAW").Write(rel ? rel.ver "`n" rel.setup "`n" rel.sha : ""), ExitApp()
App.Init()

class App {
    static Exe := "RobloxPlayerBeta.exe"
    static Win := "Roblox ahk_exe RobloxPlayerBeta.exe ahk_class WINDOWSCLIENT"
    static Version := "1.0.1"
    ;@Ahk2Exe-Let U_version = %A_PriorLine~U)^(.+")(.*)".*$~$2%
    ;@Ahk2Exe-SetVersion %U_version%
    static Repo := "mihoshiho/KitsuneRoblox", Update := 0
    static Data := EnvGet("LOCALAPPDATA") "\KitsuneRoblox"   ; your settings and accounts: kept when the app updates
    static Ini := EnvGet("LOCALAPPDATA") "\KitsuneRoblox\KitsuneRoblox.ini"
    static AccIni := EnvGet("LOCALAPPDATA") "\KitsuneRoblox\accounts.ini"    ; names and ids only: the logins live in the profiles below
    static Running := false
    static Profiles := EnvGet("LOCALAPPDATA") "\KitsuneRoblox\profiles"   ; per account: login browser, saved Roblox login, own Roblox path
    static Accts := Map()           ; user id -> {name, tracker, profile, pid, state}
    static Clients := Map()         ; pid -> {acct, log, pos, state, outSince, join, born, uid, saved, gone, trimAt}
    static Poked := Map()           ; hwnd -> tick of last anti-AFK key
    static Queue := [], Launching := 0, Fails := 0, Lines := [], LockSeen := false
    static Opt := Map(), AskLink := false, UiReady := false, Rejoins := 0, GameName := ""
    static PushFn := ObjBindMethod(App, "Push")
    static TickFn := ObjBindMethod(App, "Tick")

    static Init() {
        ; Started with "redirection guard" (Inno Setup passes it on), Roblox can't be opened through the
        ; per-account folder links: start again from Explorer, which runs it without. Once a minute at most (no loop).
        DirCreate(this.Data)
        if A_IsCompiled && RedirectGuarded() && DateDiff(A_Now, IniRead(this.Ini, "Main", "Unguard", 19000101), "Seconds") > 60
            return (IniWrite(A_Now, this.Ini, "Main", "Unguard"), Run('explorer.exe "' A_ScriptFullPath '"'), ExitApp())
        ; one app at a time: a second start shows the open one
        static showMsg := DllCall("RegisterWindowMessage", "Str", "KitsuneRoblox_show", "UInt")
        if NameExists("Mutex", "KitsuneRoblox_app")
            return (DllCall("PostMessage", "Ptr", 0xFFFF, "UInt", showMsg, "Ptr", 0, "Ptr", 0), ExitApp())
        DllCall("CreateMutex", "Ptr", 0, "Int", 0, "Str", "KitsuneRoblox_app", "Ptr")
        OnMessage(showMsg, (*) => (this.OpenUi(), 0))
        DirCreate(this.Data)
        for f in ["KitsuneRoblox.ini", "accounts.ini"]     ; older versions kept these next to the script
            if !FileExist(this.Data "\" f) && FileExist(A_ScriptDir "\" f)
                FileCopy(A_ScriptDir "\" f, this.Data "\" f)
        if !A_IsCompiled
            TraySetIcon(A_ScriptDir "\ui\fox.ico")
        g := this.G := Gui("+Resize +MinSize520x560", "KitsuneRoblox")
        g.BackColor := "191919"
        DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", g.Hwnd, "UInt", 20, "Int*", 1, "UInt", 4)   ; dark title bar
        DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", g.Hwnd, "UInt", 33, "Int*", 2, "UInt", 4)   ; round corners (Windows 11)
        for attr in [34, 35]                          ; border and title bar = ground, not the Windows accent color
            DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", g.Hwnd, "UInt", attr, "UInt*", 0x191919, "UInt", 4)
        ; settings: plain values the window edits (see SetOpt)
        for k, d in Map("Link", "", "AntiAfk", 1, "Minutes", 15, "Key", "Space", "Rejoin", 1, "Multi", 1, "TrimMin", 10, "TrimOn", 1, "AutoStart", 1)
            this.Opt[k] := {Value: IniRead(this.Ini, "Main", k, d)}
        this.Link := this.Opt["Link"], this.Afk := this.Opt["AntiAfk"], this.Mins := this.Opt["Minutes"], this.Key := this.Opt["Key"]
        this.Rej := this.Opt["Rejoin"], this.Multi := this.Opt["Multi"], this.Trim := this.Opt["TrimMin"]
        r := StrSplit(IniRead(this.Ini, "Main", "Rejoins", ""), ":")
        this.Rejoins := r.Length = 2 && r[1] = A_YYYY A_MM A_DD && IsInteger(r[2]) ? Integer(r[2]) : 0
        this.GameName := IniRead(this.Ini, "Main", "GameName", "")
        g.OnEvent("Close", (*) => this.HideUi())
        g.OnEvent("Size", (*) => this.HasOwnProp("Wv") && this.Wv.Fill())
        A_TrayMenu.Delete()
        A_TrayMenu.Add("Show", (*) => this.OpenUi())
        A_TrayMenu.Add("Exit", (*) => ExitApp())
        A_TrayMenu.Default := "Show"
        OnExit((*) => this.Save())
        this.LoadAccounts()
        this.Log("Ready. Only Roblox clients in this Windows session (" SessionOf(DllCall("GetCurrentProcessId")) ") are touched")
        this.OpenUi()
        if GameLink(this.Link.Value) = ""
            this.AskLink := true, this.Show()
        else if this.Opt["AutoStart"].Value
            this.Start()
        if this.GameName = ""
            this.FetchName()
        if A_IsCompiled                               ; the source copy updates with git, not here
            SetTimer(() => this.CheckUpdate(), -20000), SetTimer(() => this.CheckUpdate(), 6 * 3600000)
    }

    ; Newest GitHub release newer than this one: the header shows "Update to vX".
    static CheckUpdate() {
        f := A_Temp "\KitsuneRoblox-check.txt"
        try FileDelete(f)
        Run('"' A_ScriptFullPath '" --check "' f '"')
        SetTimer(this.ReadCheck.Bind(this, f, A_TickCount), -2000)
    }

    static ReadCheck(f, at) {
        if !FileExist(f)
            return A_TickCount - at < 60000 ? SetTimer(this.ReadCheck.Bind(this, f, at), -2000) : 0
        try l := StrSplit(FileRead(f, "UTF-8"), "`n")
        catch                                         ; still being written
            return SetTimer(this.ReadCheck.Bind(this, f, at), -1000)
        base := "https://github.com/" this.Repo "/releases/download/"   ; the temp file is checked again: only this repo's links
        if l.Length < 3 || InStr(l[2], base) != 1 || InStr(l[3], base) != 1 || !VerNewer(l[1], this.Version) || this.Update && this.Update.ver = l[1]
            return
        this.Update := {ver: l[1], setup: l[2], sha: l[3]}, this.Log("Update v" l[1] " is ready: click it at the top")
    }

    ; Download the installer, check it, run it quietly and quit. It starts the app again (watching starts by itself).
    static DoUpdate() {
        if !(u := this.Update)
            return
        if this.Launching
            return this.Log("Roblox is opening: update after it")
        this.Log("Downloading update v" u.ver "…"), this.Push()
        file := A_Temp "\KitsuneRoblox-Setup-" u.ver ".exe"
        want := RegExMatch(HttpText(u.sha), "i)^\s*([0-9a-f]{64})", &m) ? StrLower(m[1]) : ""
        try Download(u.setup, file)
        if want = "" || FileSha256(file) != want {
            try FileDelete(file)
            return this.Log("Update download failed or didn't match. Try again later")
        }
        this.Save()
        Run('"' file '" /VERYSILENT /SUPPRESSMSGBOXES /NORESTART')
        ExitApp()
    }

    ; The window is a WebView2 page (ui\index.html). Closing it frees WebView2 (about 100 MB); watching goes on.
    static OpenUi() {
        this.G.Show(this.HasOwnProp("Shown") ? "" : "w640 h740"), this.Shown := true
        if this.HasOwnProp("Wv")
            return
        try {
            wv := WebView2.CreateControllerAsync(this.G.Hwnd, 0, EnvGet("LOCALAPPDATA") "\KitsuneRoblox\ui").await()
        } catch as e
            return MsgBox("The window needs the WebView2 runtime: " e.Message, "KitsuneRoblox", "Iconx")
        wv.DefaultBackgroundColor := 0x191919FF       ; no white flash while the page loads
        cw := wv.CoreWebView2, st := cw.Settings
        st.AreDevToolsEnabled := false, st.AreDefaultContextMenusEnabled := false, st.IsStatusBarEnabled := false, st.IsZoomControlEnabled := false
        cw.SetVirtualHostNameToFolderMapping("kitsune.ui", A_ScriptDir "\ui", 0)
        cw.add_WebMessageReceived((sender, args) => this.OnUi(args.TryGetWebMessageAsString()))
        cw.Navigate("https://kitsune.ui/index.html")
        this.Wv := wv, this.UiReady := false
        wv.Fill()
    }

    static HideUi() {
        this.G.Hide()
        if this.HasOwnProp("Wv")
            try this.Wv.Close()
        try this.DeleteProp("Wv")
        this.UiReady := false
        if this.Running
            TrayTip("Still watching. Click the tray icon to open", "KitsuneRoblox", 0x10)
    }

    ; Messages from the page: "command<tab>arg<tab>arg". Handled just after WebView2's event returns:
    ; waiting inside it (Add account starts its own WebView2) never finished.
    static OnUi(msg) => SetTimer(this.DoUi.Bind(this, msg), -1)

    static DoUi(msg) {
        m := StrSplit(msg, "`t")
        switch m[1] {
            case "ready": this.UiReady := true, this.Push()
            case "start": this.Start(), this.Show()
            case "stop": this.Stop("Stopped")
            case "add": this.AddAccount()
            case "playall": this.PlayAll()
            case "play": this.Play(m[2])
            case "close": this.CloseOne(m[2])
            case "remove": this.Remove(m[2])
            case "set": this.SetOpt(m[2], m.Length > 2 ? m[3] : "")
            case "update": this.DoUpdate()
        }
    }

    ; A setting changed in the window. Checked here: the page is not trusted with keys or numbers.
    static SetOpt(k, v) {
        if !this.Opt.Has(k)
            return
        if k = "Minutes" || k = "TrimMin"
            v := IsInteger(v) && v >= 1 && v <= 999 ? Integer(v) : this.Opt[k].Value
        else if k = "Key"
            v := RegExMatch(v, "^[A-Za-z0-9]{1,12}$") && GetKeyVK(v) ? v : this.Opt[k].Value   ; a key name only: it goes into Send
        else if k != "Link"
            v := v ? 1 : 0
        this.Opt[k].Value := v, this.Save()
        if k = "Link"
            this.FetchName()
        this.Show()
    }

    ; Game name for the link pill, from Roblox's public game API. Runs once per link, just after the window shows.
    ; shortcut: a blocking request (up to 4 s, often 0.3 s) because async WinHttp never finished inside timers here.
    static FetchName() {
        this.GameName := "", IniWrite("", this.Ini, "Main", "GameName")
        if (place := GameInfo(this.Link.Value).place) != ""
            SetTimer(() => this.GetName(place), -500)
    }

    static GetName(place) {
        try {
            r := ComObject("WinHttp.WinHttpRequest.5.1"), r.SetTimeouts(2000, 2000, 2000, 2000)
            r.Open("GET", "https://apis.roblox.com/universes/v1/places/" place "/universe"), r.Send()
            if !RegExMatch(r.ResponseText, '"universeId"\s*:\s*(\d+)', &u)
                return
            r.Open("GET", "https://games.roblox.com/v1/games?universeIds=" u[1]), r.Send()
            if !RegExMatch(r.ResponseText, '"name"\s*:\s*"((?:[^"\\]|\\.)*)"', &n) || GameInfo(this.Link.Value).place != place
                return
            this.GameName := RegExReplace(n[1], '\\(["\\/])', "$1")
            IniWrite(this.GameName, this.Ini, "Main", "GameName"), this.Show()
        }
    }

    static Save() {
        for k, o in this.Opt
            IniWrite(o.Value, this.Ini, "Main", k)
        IniWrite(A_YYYY A_MM A_DD ":" this.Rejoins, this.Ini, "Main", "Rejoins")
    }

    ; ---------- accounts ----------

    static LoadAccounts() {
        try for id in StrSplit(IniRead(this.AccIni), "`n") {
            try IniDelete(this.AccIni, id, "Cookie")  ; older versions kept a cookie copy: not needed now
            this.Accts[id] := {name: IniRead(this.AccIni, id, "Name", id), tracker: IniRead(this.AccIni, id, "Tracker", NewTracker())
                , profile: p := IniRead(this.AccIni, id, "Profile", ""), pid: 0
                , state: p != "" && DirExist(this.Profiles "\" p) ? "Idle" : "Log in again"}
        }
    }

    ; A Roblox login page in a new browser profile. You log in yourself. The profile is kept for Play.
    static AddAccount() {
        if this.HasOwnProp("LoginGui")
            return this.LoginGui.Show()
        lg := this.LoginGui := Gui("+Owner" this.G.Hwnd " +Resize", "Log in to Roblox")
        lg.BackColor := "191919"
        lg.Show("w460 h680")
        this.LoginProfile := "p" A_TickCount          ; new profile: never reuses a past login
        try this.LoginWv := WebView2.CreateControllerAsync(lg.Hwnd, 0, this.Profiles "\" this.LoginProfile).await()
        catch as e {
            this.Log("Login window failed: " e.Message " (is the WebView2 runtime installed?)")
            return this.EndLogin()
        }
        this.LoginWv.DefaultBackgroundColor := 0x191919FF
        lg.OnEvent("Size", (*) => this.LoginWv.Fill())
        lg.OnEvent("Close", (*) => this.EndLogin())
        this.LoginWv.Fill()
        this.LoginSeen := false
        this.LoginWv.CoreWebView2.add_WebMessageReceived((sender, args) => this.GotUser(args.TryGetWebMessageAsString()))
        this.LoginWv.CoreWebView2.Navigate("https://www.roblox.com/login")
        this.LoginFn := ObjBindMethod(this, "CheckLogin")
        SetTimer(this.LoginFn, 1500)
        this.Log("Login window open: log in there yourself")
    }

    static CheckLogin() {
        if this.HasOwnProp("LoginWv")
            try this.LoginWv.CoreWebView2.CookieManager.GetCookiesAsync("https://www.roblox.com").then(list => this.GotCookies(list))
    }

    ; Login cookie seen: ask Roblox "who is logged in?" from inside the login page (its own browser session).
    ; No answer yet = login not finished (2-step, captcha): the next check asks again.
    static GotCookies(list) {
        loop list.Count {
            c := list.GetValueAtIndex(A_Index - 1)
            if c.Name != ".ROBLOSECURITY" || !this.HasOwnProp("LoginWv")
                continue
            this.LoginSeen := true
            ; fails while the page is busy (redirect, closing): the next check asks again
            try this.LoginWv.CoreWebView2.ExecuteScriptAsync("fetch('https://users.roblox.com/v1/users/authenticated',{credentials:'include'})"
                . ".then(r=>r.text()).then(t=>chrome.webview.postMessage(t)).catch(e=>chrome.webview.postMessage(''))")
            return
        }
    }

    static GotUser(json) {
        if !this.HasOwnProp("LoginWv") || !this.LoginSeen
            || !RegExMatch(json, '"id"\s*:\s*(\d+)', &i) || !RegExMatch(json, '"name"\s*:\s*"([^"]+)"', &n)
            return
        u := {id: i[1], name: n[1]}
        this.EndLogin(true)
        old := this.Accts.Has(u.id) ? this.Accts[u.id] : 0
        if old && old.profile != ""
            this.DropProfile(old.profile)
        a := this.Accts[u.id] := {name: u.name, tracker: old ? old.tracker : NewTracker(), profile: this.LoginProfile
            , pid: old ? old.pid : 0, state: old && old.state != "Log in again" ? old.state : "Idle"}
        IniWrite(a.name, this.AccIni, u.id, "Name"), IniWrite(a.tracker, this.AccIni, u.id, "Tracker")
        IniWrite(a.profile, this.AccIni, u.id, "Profile")
        this.Log((old ? "Updated " : "Added ") a.name)
        this.Show()
    }

    static EndLogin(keep := false) {
        try SetTimer(this.LoginFn, 0)
        try this.LoginWv.Close()
        try this.LoginGui.Destroy()
        for p in ["LoginWv", "LoginGui"]
            try this.DeleteProp(p)
        if !keep
            this.DropProfile(this.LoginProfile)
    }

    static DropProfile(name) {
        if name = ""
            return
        dir := this.Profiles "\" name
        SetTimer(() => (DirExist(dir) && (DropJunctions(dir), DirDelete(dir, true))), -5000)   ; Edge lets go of the folder a moment later
    }

    ; The window asks "Remove?" first. An open client stays open.
    static Remove(id) {
        if !this.Accts.Has(id)
            return
        this.Log("Removed " this.Accts[id].name), this.DropProfile(this.Accts[id].profile), this.Accts.Delete(id), IniDelete(this.AccIni, id)
        this.Show()
    }

    static Play(id) {
        if InStr(id, "pid:") || !this.Accts.Has(id)
            return
        a := this.Accts[id]
        if a.pid
            return this.Log(a.name " is already in game")
        for q in this.Queue
            if q = id
                return
        if !this.Running && !this.Start()
            return
        this.Queue.Push(id), a.state := "Waiting"
        this.Show()
    }

    static PlayAll() {
        for id, a in this.Accts
            if !a.pid && a.state != "Log in again"
                this.Play(id)
    }

    static CloseOne(id) {
        other := InStr(id, "pid:")
        if !(pid := other ? (IsInteger(SubStr(id, 5)) ? Integer(SubStr(id, 5)) : 0) : this.Accts.Has(id) ? this.Accts[id].pid : 0)
            return
        if other && !this.Clients.Has(pid)            ; only a client we track: the page can't end any other process
            return
        this.Clients.Delete(pid)                      ; closed by you: never rejoined
        ProcessClose(pid)
        if !other
            this.Free(id)
        this.Log("Closed " (other ? "client " pid : this.Accts[id].name) " (no rejoin)")
        this.Show()
    }

    ; ---------- watching ----------

    static Start() {
        if GameLink(this.Link.Value) = ""
            return (this.AskLink := true, this.Log("Paste a game link first"), false)
        this.Save()
        this.Running := true, this.Fails := 0, this.Poked := Map(), this.Since := FormatTime(, "HH:mm")
        this.Log("Watching")
        SetTimer(this.TickFn, 5000)
        SetTimer(() => this.Tick(), -10)              ; first check right away (a new function: reusing TickFn would replace the 5 s timer)
        return true
    }

    static Stop(why, alert := false) {
        this.Running := false, this.Queue := [], this.Launching := 0
        SetTimer(this.TickFn, 0)
        for id, a in this.Accts
            if a.state = "Waiting" || a.state = "Opening"
                a.state := "Idle"
        this.Log(why)
        if alert
            SoundPlay("*48"), TrayTip(why, "KitsuneRoblox", 2), this.OpenUi()
        this.Show()
    }

    ; One check every 5 s. Cheap: one process list, new log bytes only.
    static Tick() {
        if !this.Running
            return
        if WinExist("ahk_class #32770 ahk_exe " this.Exe)      ; a Roblox popup (error, warning): a person must look
            return this.Stop("STOPPED: Roblox shows a popup. Check it, then start again", true)
        if this.Multi.Value
            this.HoldLock()
        alive := Map()
        for pid in SessionProcs(this.Exe) {
            alive[pid] := 1
            if !this.Clients.Has(pid) {
                acct := this.AcctOf(pid)   ; saved: only a client opened by our Play now may save the live login (an older one may not have written it last)
                this.Clients[pid] := {acct: acct, log: "", pos: 0, state: "starting", outSince: 0, join: -99, born: A_TickCount - AgeOf(pid) * 1000, uid: "", saved: !(this.Launching && this.Launching.acct), gone: 0, trimAt: 0}
                if acct
                    this.Accts[acct].pid := pid, this.Accts[acct].state := "In game"
            }
        }
        for pid, c in this.Clients.Clone() {
            if !alive.Has(pid) {                      ; crash report = rejoin; none after 15 s = you closed it
                c.gone := c.gone || A_TickCount
                if this.Rej.Value && (Crashed(pid) || c.log != "" && Hung(c.log)) {   ; crash report, or Roblox ended it frozen
                    this.Log(this.Name(c.acct, pid) " crashed: rejoining"), this.Rejoins++
                    this.Clients.Delete(pid), this.Free(c.acct, pid), this.Queue.Push(c.acct)
                    if c.acct && this.Accts.Has(c.acct)
                        this.Accts[c.acct].state := "Waiting"
                } else if A_TickCount - c.gone > 15000 {
                    this.Clients.Delete(pid), this.Free(c.acct, pid)
                    this.Log(this.Name(c.acct, pid) " closed (no rejoin)")
                }
                continue
            }
            if this.ReadLog(pid, c) = "warn"
                return this.Stop("STOPPED: " this.Name(c.acct, pid) " was kicked or warned. Check it, then start again", true)
            if c.acct = "" && c.uid && this.Accts.Has(c.uid) && !this.Accts[c.uid].pid {   ; a client you opened yourself, logged in as a saved account
                c.acct := c.uid, this.Accts[c.uid].pid := pid, this.Accts[c.uid].state := "In game"
                this.Log("Client " pid " is " this.Accts[c.uid].name)
            }
            if c.acct && c.uid && c.uid != c.acct {        ; the account's saved login is someone else: drop it, next Play asks to sign in
                try FileMove(this.Profiles "\" this.Accts[c.acct].profile "\RobloxCookies.dat", this.Profiles "\" this.Accts[c.acct].profile "\RobloxCookies.dat.wrong", true)
                return this.Stop("STOPPED: " this.Name(c.acct, pid) " opened as another account (user " c.uid "). Play it again and sign in to it in the Roblox window", true)
            }
            if c.acct && c.uid = c.acct && !c.saved && this.Newest(pid)
                c.saved := this.SaveLogin(c.acct)
            if this.Rej.Value && c.state = "out" && A_TickCount - c.outSince > 45000 {   ; 45 s: a teleport joins again before that
                this.Log(this.Name(c.acct, pid) " disconnected: rejoining"), this.Rejoins++
                this.Clients.Delete(pid), this.Free(c.acct, pid)
                ProcessClose(pid)
                this.Queue.Push(c.acct)               ; "" = a client not opened from an account: plain game link
                if c.acct && this.Accts.Has(c.acct)
                    this.Accts[c.acct].state := "Waiting"
            }
        }
        this.TrimAll()
        this.Launch(alive)
        if this.Afk.Value
            this.AntiAfk()
        this.Show()
    }

    ; Trim each client 1 min after it starts, then every N minutes.
    static TrimAll() {
        if !this.Opt["TrimOn"].Value || (every := this.Trim.Value) = "" || every < 1
            return
        n := 0, saved := 0
        for pid, c in this.Clients
            if A_TickCount - c.born > 60000 && (!c.trimAt || A_TickCount - c.trimAt > every * 60000) {
                before := RamOf(pid), c.trimAt := A_TickCount
                if TrimRam(pid)
                    n++, saved += Max(before - RamOf(pid), 0)
            }
        if n
            this.Log("Trimmed RAM: " n " client(s), " saved " MB moved to disk")
    }

    ; LockKeeper.ahk holds ROBLOX_singletonMutex in its own process, so closing this tool never frees it.
    static HoldLock() {
        if !NameExists("Mutex", "KitsuneKeeper_ROBLOX_singletonMutex")
            this.RunKeeper()
        else if !this.LockSeen && (this.LockSeen := NameExists("Event", "KitsuneKeeper_held_ROBLOX_singletonMutex"))
            this.Log("Holding Roblox's lock: clients won't close each other, even if this tool closes")
    }

    ; The keeper runs from its own copy of the app, so an update can replace KitsuneRoblox.exe
    ; while the keeper keeps the lock (closing it would close every client).
    static RunKeeper() {
        if !A_IsCompiled
            return Run('"' A_AhkPath '" "' A_ScriptFullPath '" --keeper')
        keeper := this.Data "\KitsuneKeeper.exe"
        try FileCopy(A_ScriptFullPath, keeper, true)   ; fails while an old keeper runs: that one is fine
        Run('"' (FileExist(keeper) ? keeper : A_ScriptFullPath) '" --keeper')
    }

    static Name(acct, pid) => acct && this.Accts.Has(acct) ? this.Accts[acct].name : "Client " pid

    ; Account back to Idle. With a pid: only if that is still the account's client (a newer one may be in game).
    static Free(acct, pid := 0) {
        if acct && this.Accts.Has(acct) && (!pid || this.Accts[acct].pid = pid)
            this.Accts[acct].pid := 0, this.Accts[acct].state := "Idle"
    }

    ; Roblox's own saved login is this account's now (it joined as itself): keep a copy for its next Play.
    ; shortcut: Roblox may renew the login later in a running client, our copy only updates on the next join.
    static SaveLogin(acct) {
        try FileCopy(RobloxLogin(), this.Profiles "\" this.Accts[acct].profile "\RobloxCookies.dat", true)
        catch
            return false
        this.Log(this.Accts[acct].name ": Roblox login saved")
        return true
    }

    ; Only the newest client's login is in Roblox's file.
    static Newest(pid) {
        for p, c in this.Clients
            if c.born > this.Clients[pid].born
                return false
        return true
    }

    ; Which saved account a client belongs to: it runs from that account's own Roblox path.
    ; The command line keeps the junction path (the process path shows the real folder).
    static AcctOf(pid) => AcctOfPath(LTrim(CmdLine(pid), '"'), this.Accts, this.Profiles)

    static ReadLog(pid, c) {
        if c.log = "" && !(c.log := FindLog(pid))
            return ""
        try {
            f := FileOpen(c.log, "r", "UTF-8")        ; shared read: Roblox keeps writing. "r-" locked it and always failed
            f.Pos := c.pos, text := f.Read(), c.pos := f.Pos, f.Close()
        } catch
            return ""
        if c.uid = "" && RegExMatch(text, "userid:(\d+)", &m)
            c.uid := m[1]
        j := c.join, s := LogState(text, &j), c.join := j
        if s = "out" && c.state != "out"
            c.outSince := A_TickCount
        if s != ""
            c.state := s
        return s
    }

    ; One launch at a time; stop after 3 launches in a row that didn't open a client.
    static Launch(alive) {
        if (l := this.Launching) {
            for pid in alive
                if !l.before.Has(pid) && this.Clients.Has(pid) && (l.acct = "" || this.Clients[pid].acct = l.acct) {
                    this.Launching := 0
                    return (this.Fails := 0, this.Log("Roblox started: " this.Name(l.acct, pid) ". Its window shows in a moment"), this.Front(pid, A_TickCount))
                }
            if A_TickCount - l.at < 90000
                return
            this.Launching := 0
            if ++this.Fails >= 3
                return this.Stop("STOPPED: Roblox didn't open 3 times. Check the screen", true)
            this.Log("Roblox didn't open. Trying again")
            this.Queue.InsertAt(1, l.acct)
        }
        if !this.Queue.Length
            return
        for pid, c in this.Clients                    ; wait until the last opened client's login is saved: the next Play swaps the file
            if c.acct && !c.saved && !c.uid && A_TickCount - c.born < 120000
                return
        ; never close Fishstrap here: it holds ROBLOX_singletonMutex, and killing it made every open client quit
        acct := this.Queue.RemoveAt(1)
        if (link := GameLink(this.Link.Value)) = ""
            return this.Log("Can't open: the game link isn't a link I can open")
        if acct = ""
            Run('explorer.exe "' link '"')
        else {
            if !this.Accts.Has(acct)
                return
            a := this.Accts[acct]
            if a.profile = "" || !DirExist(this.Profiles "\" a.profile)
                return (a.state := "Log in again", this.Log(a.name ": click Add account and log in to it again"))
            if (exe := AcctExe(this.Profiles "\" a.profile)) = ""
                return (a.state := "Idle", this.Log("Can't find Roblox: open it once with Fishstrap ("
                    . (src := RegRead("HKCU\Software\Fishstrap", "PlayerPath", "")) ", found " (FileExist(src "\RobloxPlayerBeta.exe") != "") ")"))
            ; Roblox logs in with its own saved login file: put this account's in place first
            live := RobloxLogin(), saved := this.Profiles "\" a.profile "\RobloxCookies.dat"
            if FileExist(saved)
                FileCopy(saved, live, true)
            else if FileExist(live) {
                FileMove(live, live ".kitsune-bak", true)
                this.Log(a.name ": no saved Roblox login yet. Sign in to it in the Roblox window")
            }
            a.state := "Opening"
            Run('"' exe '" ' link)                    ; its own path: Roblox doesn't hand the join to an open client
        }
        this.Launching := {acct: acct, at: A_TickCount, before: alive}
        this.Log("Opening " (acct ? this.Accts[acct].name : "the game"))
    }

    ; Bring a client we started to the front once its window shows (started directly, Windows opens it behind).
    ; Not while you type, so it never takes your keys. Gives up after 1 min.
    static Front(pid, at) {
        if (hwnd := WinExist(this.Win " ahk_pid " pid)) && A_TimeIdlePhysical > 3000
            return (WinActivate(hwnd), this.Log(this.Name(this.Clients.Has(pid) ? this.Clients[pid].acct : "", pid) ": window shown"))
        if A_TickCount - at < 60000 && ProcessExist(pid)
            SetTimer(() => this.Front(pid, at), -1000)
    }

    ; Roblox kicks after 20 min with no input. Background key messages don't count, so focus each
    ; window for a moment, tap one key, then give focus back.
    static AntiAfk() {
        every := Max(this.Mins.Value, 1) * 60000, me := SessionOf(DllCall("GetCurrentProcessId"))
        due := []
        for hwnd in WinGetList(this.Win) {
            try pid := WinGetPID(hwnd)
            catch                                     ; window closed while we looked (rejoin, crash)
                continue
            if SessionOf(pid) != me
                continue
            if !this.Poked.Has(hwnd) || WinActive(hwnd) && A_TimeIdlePhysical < 5000   ; you're playing it: that counts
                this.Poked[hwnd] := A_TickCount
            else if A_TickCount - this.Poked[hwnd] > every
                due.Push(hwnd)
        }
        if !due.Length || A_TimeIdlePhysical < 3000 && A_TickCount - this.Poked[due[1]] < every + 120000   ; don't grab focus while you type (up to 2 min)
            return
        back := WinExist("A")
        for hwnd in due {
            try WinActivate(hwnd)
            catch
                continue
            if WinWaitActive(hwnd, , 1) {
                Send("{" this.Key.Value " down}"), Sleep(60), Send("{" this.Key.Value " up}")
                this.Poked[hwnd] := A_TickCount
            }
        }
        try WinActivate(back)
        this.Log("Anti-AFK: " due.Length " window(s)")
    }

    ; Send the whole state to the window, at most once per 100 ms.
    static Show() => SetTimer(this.PushFn, -100)

    static Push() {
        if !this.UiReady || !this.HasOwnProp("Wv")
            return
        accts := [], others := [], ingame := 0, ram := 0
        for id, a in this.Accts
            accts.Push({id: id, name: a.name, state: a.state, pid: a.pid})
        for pid, c in this.Clients {
            ingame += c.state != "out", ram += RamOf(pid)   ; a client found after a restart stays "starting" until its next join line
            if !c.acct
                others.Push({pid: pid, state: c.state = "in" ? "In game" : c.state = "out" ? "Disconnected" : "Starting"})
        }
        g := GameInfo(this.Link.Value), set := Map(), log := []
        for k, o in this.Opt
            set[k] := o.Value
        loop Min(40, this.Lines.Length)
            log.Push(this.Lines[this.Lines.Length - Min(40, this.Lines.Length) + A_Index])
        name := !g.ok ? "" : this.GameName != "" ? this.GameName : g.place ? "Place " g.place : "Private server"
        st := {running: this.Running, since: this.HasOwnProp("Since") ? this.Since : "", accts: accts, others: others, set: set
            , game: {ok: g.ok, vip: g.vip, name: name}, version: this.Version, update: this.Update ? this.Update.ver : "", stats: {ingame: ingame, ram: ram, rejoins: this.Rejoins}, log: log, askLink: this.AskLink}
        this.AskLink := false
        try this.Wv.CoreWebView2.PostWebMessageAsJson(Json(st))
    }

    static Log(msg) {
        line := FormatTime(, "HH:mm:ss") "  " msg
        this.Lines.Push(line)
        if this.Lines.Length > 100
            this.Lines.RemoveAt(1)
        FileAppend(line "`n", this.Data "\KitsuneRoblox.log", "UTF-8")
        this.Show()
    }
}
