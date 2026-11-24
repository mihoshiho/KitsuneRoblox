#Requires AutoHotkey v2.0
#SingleInstance Force
#Include lib\Core.ahk
#Include lib\Accounts.ahk
#Include lib\WebView2\WebView2.ahk

; KitsuneRoblox: accounts, anti-AFK, auto rejoin and multi-instance for Roblox clients in this Windows session.
App.Init()

class App {
    static Exe := "RobloxPlayerBeta.exe"
    static Win := "Roblox ahk_exe RobloxPlayerBeta.exe ahk_class WINDOWSCLIENT"
    static Ini := A_ScriptDir "\KitsuneRoblox.ini"
    static AccIni := A_ScriptDir "\accounts.ini"    ; names and ids only: the logins live in the profiles below
    static Running := false
    static Profiles := EnvGet("LOCALAPPDATA") "\KitsuneRoblox\profiles"   ; one saved login browser per account (Edge encrypts it)
    static Accts := Map()           ; user id -> {name, tracker, profile, pid, state}
    static Clients := Map()         ; pid -> {acct, log, pos, state, outSince, born, freed, gone, trimAt}
    static Poked := Map()           ; hwnd -> tick of last anti-AFK key
    static Queue := [], Launching := 0, Fails := 0, Rows := [], Lines := [], LockSeen := false
    static TickFn := ObjBindMethod(App, "Tick")

    static Init() {
        g := this.G := Gui("+MinSize", "KitsuneRoblox")
        g.BackColor := "191919"
        DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", g.Hwnd, "UInt", 20, "Int*", 1, "UInt", 4)   ; dark title bar
        g.SetFont("s14 bold cFF9EC7", "Noto Sans")
        g.AddText("w480", "KitsuneRoblox")
        g.SetFont("s10 norm cBFAFB8")
        g.AddText("y+8", "Game link (private server or game page)")
        g.SetFont("cF2E6EE")
        this.Link := g.AddEdit("w480 r1 -Wrap Background2A2228", IniRead(this.Ini, "Main", "Link", ""))

        g.SetFont("cBFAFB8")
        g.AddText("xm y+14", "Accounts")
        g.SetFont("cF2E6EE")
        this.LV := g.AddListView("xm w480 r6 Background221C20 -Hdr", ["Name", "State"])   ; Ctrl/Shift+click selects many
        this.LV.OnEvent("DoubleClick", (lv, row) => row && this.Play(this.Rows[row]))
        g.SetFont("s10 c191919")
        for b in [["Add account", (*) => this.AddAccount()], ["Play", (*) => this.ForSel("Play")], ["Close", (*) => this.ForSel("CloseOne")]
                , ["Remove", (*) => this.Remove()], ["Play all", (*) => this.PlayAll()]]
            g.AddButton((A_Index = 1 ? "xm" : "x+6") " w91 h30", b[1]).OnEvent("Click", b[2])

        g.SetFont("cF2E6EE")
        this.Afk := g.AddCheckbox("-Theme xm y+14 Checked" IniRead(this.Ini, "Main", "AntiAfk", 1), "Anti-AFK every")
        this.Mins := g.AddEdit("x+4 yp-3 w40 Number Background2A2228", IniRead(this.Ini, "Main", "Minutes", 15))
        g.AddText("x+4 yp+3", "min, key")
        this.Key := g.AddEdit("x+4 yp-3 w70 Background2A2228", IniRead(this.Ini, "Main", "Key", "Space"))
        this.Rej := g.AddCheckbox("-Theme xm y+10 Checked" IniRead(this.Ini, "Main", "Rejoin", 1), "Rejoin after a disconnect (not when you close it)")
        this.Multi := g.AddCheckbox("-Theme xm y+6 Checked" IniRead(this.Ini, "Main", "Multi", 1), "Multi-instance (free Roblox's one-client lock)")
        g.AddText("xm y+10", "Trim RAM every")
        this.Trim := g.AddEdit("x+6 yp-3 w40 Number Background2A2228", IniRead(this.Ini, "Main", "TrimMin", 10))
        g.AddText("x+4 yp+3", "min (first 1 min after start, empty = off)")
        g.SetFont("s11 bold c191919")
        this.Btn := g.AddButton("xm y+12 w480 h34", "Start watching")
        this.Btn.OnEvent("Click", (*) => this.Running ? this.Stop("Stopped") : this.Start())
        g.SetFont("s9 norm cBFAFB8")
        this.Out := g.AddEdit("xm w480 r7 ReadOnly Background221C20")
        g.OnEvent("Close", (*) => g.Hide())
        A_TrayMenu.Delete()
        A_TrayMenu.Add("Show", (*) => g.Show())
        A_TrayMenu.Add("Exit", (*) => ExitApp())
        A_TrayMenu.Default := "Show"
        OnExit((*) => this.Save())
        this.LoadAccounts()
        this.Show()
        g.Show()
        this.Log("Ready. Only Roblox clients in this Windows session (" SessionOf(DllCall("GetCurrentProcessId")) ") are touched")
    }

    static Save() {
        for k, c in Map("Link", this.Link, "AntiAfk", this.Afk, "Minutes", this.Mins, "Key", this.Key, "Rejoin", this.Rej, "Multi", this.Multi, "TrimMin", this.Trim)
            IniWrite(c.Value, this.Ini, "Main", k)
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

    ; Ids of every selected row (accounts, or "pid:<n>" for other clients).
    static Selected() {
        ids := [], r := 0
        while (r := this.LV.GetNext(r)) && r <= this.Rows.Length
            ids.Push(this.Rows[r])
        return ids
    }

    static ForSel(method) {
        for id in this.Selected()
            this.%method%(id)
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
        SetTimer(() => (DirExist(dir) && DirDelete(dir, true)), -5000)   ; Edge lets go of the folder a moment later
    }

    static Remove() {
        ids := [], names := ""
        for id in this.Selected()
            if !InStr(id, "pid:")
                ids.Push(id), names .= (names = "" ? "" : ", ") this.Accts[id].name
        if !ids.Length || MsgBox("Remove " names "? (open clients stay open)", "KitsuneRoblox", "YesNo Owner" this.G.Hwnd) != "Yes"
            return
        for id in ids
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
        if !(pid := other ? Integer(SubStr(id, 5)) : this.Accts[id].pid)
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
        if PlayPage(this.Link.Value) = ""
            return (this.Log("Paste a game link first"), false)
        this.Save()
        this.Running := true, this.Fails := 0, this.Poked := Map()
        this.Btn.Text := "Stop watching"
        this.Log("Watching")
        SetTimer(this.TickFn, 5000)
        SetTimer(() => this.Tick(), -10)              ; first check right away (a new function: reusing TickFn would replace the 5 s timer)
        return true
    }

    static Stop(why, alert := false) {
        this.Running := false, this.Queue := [], this.EndLaunch()
        SetTimer(this.TickFn, 0)
        for id, a in this.Accts
            if a.state = "Waiting" || a.state = "Opening"
                a.state := "Idle"
        this.Btn.Text := "Start watching"
        this.Log(why)
        if alert
            SoundPlay("*48"), TrayTip(why, "KitsuneRoblox", 2), this.G.Show()
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
                acct := this.AcctOf(pid)
                this.Clients[pid] := {acct: acct, log: "", pos: 0, state: "starting", outSince: 0, join: -99, born: A_TickCount - AgeOf(pid) * 1000, freed: false, gone: 0, trimAt: 0}
                if acct
                    this.Accts[acct].pid := pid, this.Accts[acct].state := "In game"
            }
        }
        for pid, c in this.Clients.Clone() {
            if !alive.Has(pid) {                      ; crash report = rejoin; none after 15 s = you closed it
                c.gone := c.gone || A_TickCount
                if this.Rej.Value && (Crashed(pid) || c.log != "" && Hung(c.log)) {   ; crash report, or Roblox ended it frozen
                    this.Log(this.Name(c.acct, pid) " crashed: rejoining")
                    this.Clients.Delete(pid), this.Free(c.acct, pid), this.Queue.Push(c.acct)
                    if c.acct && this.Accts.Has(c.acct)
                        this.Accts[c.acct].state := "Waiting"
                } else if A_TickCount - c.gone > 15000 {
                    this.Clients.Delete(pid), this.Free(c.acct, pid)
                    this.Log(this.Name(c.acct, pid) " closed (no rejoin)")
                }
                continue
            }
            if this.Multi.Value && !c.freed && A_TickCount - c.born < 60000
                if c.freed := CloseSingleton(pid)
                    this.Log("Client " pid ": one-client lock freed")
            if this.ReadLog(pid, c) = "warn"
                return this.Stop("STOPPED: " this.Name(c.acct, pid) " was kicked or warned. Check it, then start again", true)
            if this.Rej.Value && c.state = "out" && A_TickCount - c.outSince > 45000 {   ; 45 s: a teleport joins again before that
                this.Log(this.Name(c.acct, pid) " disconnected: rejoining")
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
        if (every := this.Trim.Value) = "" || every < 1
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
            Run('"' A_AhkPath '" "' A_ScriptDir '\LockKeeper.ahk"'), this.LockSeen := false
        else if !this.LockSeen && (this.LockSeen := NameExists("Event", "KitsuneKeeper_held_ROBLOX_singletonMutex"))
            this.Log("Holding Roblox's lock: clients won't close each other, even if this tool closes")
    }

    static Name(acct, pid) => acct && this.Accts.Has(acct) ? this.Accts[acct].name : "Client " pid

    ; Account back to Idle. With a pid: only if that is still the account's client (a newer one may be in game).
    static Free(acct, pid := 0) {
        if acct && this.Accts.Has(acct) && (!pid || this.Accts[acct].pid = pid)
            this.Accts[acct].pid := 0, this.Accts[acct].state := "Idle"
    }

    ; Which saved account a client belongs to: our browsertrackerid is in its command line.
    static AcctOf(pid) {
        cmd := CmdLine(pid)
        for id, a in this.Accts
            if RegExMatch(cmd, "(-b |browsertrackerid:)" a.tracker "\b")
                return id
        return ""
    }

    static ReadLog(pid, c) {
        if c.log = "" && !(c.log := FindLog(pid))
            return ""
        try {
            f := FileOpen(c.log, "r", "UTF-8")        ; shared read: Roblox keeps writing. "r-" locked it and always failed
            f.Pos := c.pos, text := f.Read(), c.pos := f.Pos, f.Close()
        } catch
            return ""
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
                if !l.before.Has(pid) && this.Clients.Has(pid) && (l.acct = "" || this.Clients[pid].acct = l.acct || this.Clients[pid].acct = "") {
                    if l.acct && this.Clients[pid].acct = ""
                        this.Own(pid, l.acct)         ; shortcut: a client you open yourself in this moment gets this account too
                    this.EndLaunch()
                    return (this.Fails := 0, this.Log("In game: " this.Name(l.acct, pid)))
                }
            if A_TickCount - l.at < 90000
                return
            this.EndLaunch()
            if ++this.Fails >= 3
                return this.Stop("STOPPED: Roblox didn't open 3 times. Check the screen", true)
            this.Log("Roblox didn't open. Trying again")
            this.Queue.InsertAt(1, l.acct)
        }
        if !this.Queue.Length
            return
        ; never close Fishstrap here: it holds ROBLOX_singletonMutex, and killing it made every open client quit
        acct := this.Queue.RemoveAt(1), dir := ""
        if acct = "" {
            if (link := GameLink(this.Link.Value)) = ""
                return this.Log("Can't rejoin: the game link isn't a link I can open")
            Run('explorer.exe "' link '"')
        } else {
            if !this.Accts.Has(acct)
                return
            a := this.Accts[acct]
            if a.profile = "" || !DirExist(this.Profiles "\" a.profile)
                return (a.state := "Log in again", this.Log(a.name ": click Add account and log in to it again"))
            if (exe := EdgeExe()) = ""
                return (a.state := "Idle", this.Log("Can't find Edge"))
            dir := this.Profiles "\" a.profile "\EBWebView"   ; the login window's browser data: Edge reads it as is
            if !EdgeProcs(dir).Length
                AllowRoblox(dir)
            a.state := "Opening"
            Run('"' exe '" --user-data-dir=' dir ' --window-position=-32000,-32000 --no-first-run --no-default-browser-check --new-window "'
                . PlayPage(this.Link.Value) '"', , , &epid)
        }
        this.Launching := {acct: acct, at: A_TickCount, before: alive, edge: dir, hid: Map()}
        if dir != ""
            this.HideEdge(this.Launching, epid)
        this.Log("Opening " (acct ? this.Accts[acct].name : "the game"))
    }

    ; The new client is this account's. Its browsertrackerid (Edge profile's own) finds it again after a restart.
    static Own(pid, acct) {
        if !this.Accts.Has(acct)
            return
        a := this.Accts[acct], this.Clients[pid].acct := acct, a.pid := pid, a.state := "In game"
        if RegExMatch(CmdLine(pid), "browsertrackerid:(\d+)", &m)
            a.tracker := m[1], IniWrite(m[1], this.AccIni, acct, "Tracker")
    }

    ; Keep the account's Edge hidden while Roblox opens. No client after 45 s: show it so you can see why
    ; (login expired, captcha, a Roblox message) and click yourself.
    static HideEdge(l, pid) {
        if this.Launching != l
            return
        if A_TickCount - l.at > 45000 {               ; a normal launch takes about 25 s
            DetectHiddenWindows(true)
            for hwnd in l.hid
                try WinShow(hwnd), WinMove(100, 100, 900, 700, hwnd), WinActivate(hwnd)
            return this.Log("Roblox didn't open yet: Edge is shown, check it")
        }
        for hwnd in WinGetList("ahk_pid " pid " ahk_class Chrome_WidgetWin_1")   ; visible ones only
            try WinHide(hwnd), l.hid[hwnd] := 1
        SetTimer(() => this.HideEdge(l, pid), -300)
    }

    ; Launch over: close the account's Edge (asks its windows first, then ends what is left).
    static EndLaunch() {
        l := this.Launching, this.Launching := 0
        if !l || l.edge = ""
            return
        old := A_DetectHiddenWindows, DetectHiddenWindows(true)   ; Tick runs on after this: give the setting back
        for hwnd in l.hid
            try WinClose(hwnd)
        DetectHiddenWindows(old)
        dir := l.edge
        SetTimer(() => this.KillEdge(dir), -5000)
    }

    static KillEdge(dir) {
        for pid in EdgeProcs(dir)
            try ProcessClose(pid)
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

    static Show() {
        sel := Map()
        for id in this.Selected()
            sel[id] := 1
        this.LV.Opt("-Redraw"), this.LV.Delete(), this.Rows := []
        for id, a in this.Accts
            this.LV.Add(sel.Has(id) ? "Select" : "", a.name, a.state (a.pid ? "  (" a.pid ")" : "")), this.Rows.Push(id)
        for pid, c in this.Clients
            if !c.acct
                this.LV.Add(sel.Has("pid:" pid) ? "Select" : "", "Other client", c.state "  (" pid ")"), this.Rows.Push("pid:" pid)
        this.LV.ModifyCol(1, 220), this.LV.ModifyCol(2, 240), this.LV.Opt("+Redraw")
    }

    static Log(msg) {
        line := FormatTime(, "HH:mm:ss") "  " msg
        this.Lines.Push(line)
        if this.Lines.Length > 100
            this.Lines.RemoveAt(1)
        s := ""
        for l in this.Lines
            s .= (A_Index > 1 ? "`r`n" : "") l
        this.Out.Value := s
        SendMessage(0x115, 7, 0, this.Out)            ; scroll to bottom
        FileAppend(line "`n", A_ScriptDir "\KitsuneRoblox.log", "UTF-8")
    }
}
