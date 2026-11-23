#Requires AutoHotkey v2.0
#SingleInstance Force
#Include lib\Core.ahk

; KitsuneRoblox: anti-AFK, auto rejoin and multi-instance for Roblox clients in this Windows session.
App.Init()

class App {
    static Exe := "RobloxPlayerBeta.exe"
    static Win := "Roblox ahk_exe RobloxPlayerBeta.exe ahk_class WINDOWSCLIENT"
    static Ini := A_ScriptDir "\KitsuneRoblox.ini"
    static Running := false
    static Clients := Map()          ; pid -> {log, pos, state, outSince, born, freed}
    static Poked := Map()            ; hwnd -> tick of last anti-AFK key
    static Launch := 0, Fails := 0, Queue := 0, BeforeLaunch := Map(), Lines := []
    static TickFn := ObjBindMethod(App, "Tick")

    static Init() {
        g := this.G := Gui("+MinSize", "KitsuneRoblox")
        g.BackColor := "191919"
        g.SetFont("s10 cF2E6EE", "Noto Sans")
        g.SetFont("s14 bold cFF9EC7")
        g.AddText("w460", "KitsuneRoblox")
        g.SetFont("s10 norm cF2E6EE")
        g.AddText("y+8", "Game link (private server or game page)")
        this.Link := g.AddEdit("w460 Background2A2228 cF2E6EE", IniRead(this.Ini, "Main", "Link", ""))
        this.Afk := g.AddCheckbox("-Theme cF2E6EE y+12 Checked" IniRead(this.Ini, "Main", "AntiAfk", 1), "Anti-AFK every")
        this.Mins := g.AddEdit("x+4 yp-3 w40 Number Background2A2228 cF2E6EE", IniRead(this.Ini, "Main", "Minutes", 15))
        g.AddText("x+4 yp+3", "min, key")
        this.Key := g.AddEdit("x+4 yp-3 w70 Background2A2228 cF2E6EE", IniRead(this.Ini, "Main", "Key", "Space"))
        this.Rej := g.AddCheckbox("-Theme cF2E6EE xm y+10 Checked" IniRead(this.Ini, "Main", "Rejoin", 1), "Auto rejoin when a client disconnects or closes")
        this.Multi := g.AddCheckbox("-Theme cF2E6EE xm y+6 Checked" IniRead(this.Ini, "Main", "Multi", 1), "Multi-instance (free Roblox's one-client lock)")
        g.SetFont("s11 bold c191919")
        this.Btn := g.AddButton("xm y+12 w460 h34", "Start")
        this.Btn.OnEvent("Click", (*) => this.Running ? this.Stop("Stopped") : this.Start())
        g.SetFont("s10 norm cF2E6EE")
        this.LV := g.AddListView("xm w460 r5 Background221C20 cF2E6EE -Multi", ["PID", "State", "Log"])
        this.Out := g.AddEdit("xm w460 r8 ReadOnly Background221C20 cBFAFB8")
        g.OnEvent("Close", (*) => g.Hide())
        A_TrayMenu.Delete()
        A_TrayMenu.Add("Show", (*) => g.Show())
        A_TrayMenu.Add("Exit", (*) => ExitApp())
        A_TrayMenu.Default := "Show"
        OnExit((*) => this.Save())
        g.Show()
        this.Log("Ready. Only Roblox clients in this Windows session (" SessionOf(DllCall("GetCurrentProcessId")) ") are touched")
    }

    static Save() {
        for k, c in Map("Link", this.Link, "AntiAfk", this.Afk, "Minutes", this.Mins, "Key", this.Key, "Rejoin", this.Rej, "Multi", this.Multi)
            IniWrite(c.Value, this.Ini, "Main", k)
    }

    static Start() {
        if this.Rej.Value && GameLink(this.Link.Value) = ""
            return this.Log("Paste a game link first (needed for rejoin)")
        this.Save()
        this.Running := true, this.Fails := 0, this.Launch := 0, this.Queue := 0, this.Clients := Map(), this.Poked := Map()
        this.Btn.Text := "Stop"
        this.Log("Started")
        this.Tick()
        SetTimer(this.TickFn, 5000)
    }

    static Stop(why, alert := false) {
        this.Running := false
        SetTimer(this.TickFn, 0)
        this.Btn.Text := "Start"
        this.Log(why)
        if alert
            SoundPlay("*48"), TrayTip(why, "KitsuneRoblox", 2), this.G.Show()
    }

    ; One check every 5 s. Cheap: one process list, new log bytes only.
    static Tick() {
        if !this.Running
            return
        if WinExist("ahk_class #32770 ahk_exe " this.Exe)      ; a Roblox popup (error, warning): a person must look
            return this.Stop("STOPPED: Roblox shows a popup. Check it, then Start again", true)
        now := SessionProcs(this.Exe), alive := Map()
        for pid in now {
            alive[pid] := 1
            if !this.Clients.Has(pid)
                this.Clients[pid] := {log: "", pos: 0, state: "starting", outSince: 0, born: A_TickCount, freed: false}
        }
        for pid, c in this.Clients.Clone() {
            if !alive.Has(pid) {
                this.Clients.Delete(pid)
                this.Log("Client " pid " closed")
                if this.Rej.Value
                    this.Queue++
                continue
            }
            if this.Multi.Value && !c.freed && A_TickCount - c.born < 60000
                if c.freed := CloseSingleton(pid)
                    this.Log("Client " pid ": one-client lock freed")
            if this.ReadLog(pid, c) = "warn"
                return this.Stop("STOPPED: client " pid " was kicked or warned. Check it, then Start again", true)
            if this.Rej.Value && c.state = "out" && A_TickCount - c.outSince > 45000 {   ; 45 s: a teleport joins again before that
                this.Log("Client " pid " disconnected: closing it to rejoin")
                ProcessClose(pid)
                this.Clients.Delete(pid), this.Queue++
            }
        }
        this.Rejoin(alive)
        if this.Afk.Value
            this.AntiAfk()
        this.Show()
    }

    static ReadLog(pid, c) {
        if c.log = "" && !(c.log := FindLog(pid))
            return ""
        try {
            f := FileOpen(c.log, "r-", "UTF-8")       ; Roblox keeps writing; we only read the new part
            f.Pos := c.pos, text := f.Read(), c.pos := f.Pos, f.Close()
        } catch
            return ""
        if (s := LogState(text)) = "out" && c.state != "out"
            c.outSince := A_TickCount
        if s != ""
            c.state := s
        return s
    }

    ; One launch at a time; stop after 3 launches that didn't open a client.
    static Rejoin(alive) {
        if this.Launch {
            for pid in alive
                if !this.BeforeLaunch.Has(pid)
                    return (this.Launch := 0, this.Fails := 0, this.Queue := Max(this.Queue - 1, 0), this.Log("Rejoined: client " pid))
            if A_TickCount - this.Launch < 90000
                return
            this.Launch := 0
            if ++this.Fails >= 3
                return this.Stop("STOPPED: Roblox didn't open 3 times. Check the screen", true)
            this.Log("Roblox didn't open. Trying again")
        }
        if this.Queue <= 0
            return
        for pid in SessionProcs("Fishstrap.exe")      ; a launcher stuck on a popup blocks the next launch
            ProcessClose(pid)
        this.BeforeLaunch := alive, this.Launch := A_TickCount
        this.Log("Opening the game")
        Run('explorer.exe "' GameLink(this.Link.Value) '"')
    }

    ; Roblox kicks after 20 min with no input. Background key messages don't count, so focus each
    ; window for a moment, tap one key, then give focus back.
    static AntiAfk() {
        every := Max(this.Mins.Value, 1) * 60000
        due := []
        for hwnd in WinGetList(this.Win) {
            if SessionOf(WinGetPID(hwnd)) != SessionOf(DllCall("GetCurrentProcessId"))
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
            WinActivate(hwnd)
            if WinWaitActive(hwnd, , 1) {
                Send("{" this.Key.Value " down}"), Sleep(60), Send("{" this.Key.Value " up}")
                this.Poked[hwnd] := A_TickCount
            }
        }
        try WinActivate(back)
        this.Log("Anti-AFK: " due.Length " window(s)")
    }

    static Show() {
        this.LV.Delete()
        for pid, c in this.Clients
            this.LV.Add(, pid, c.state (c.freed ? ", multi ok" : ""), c.log ? "found" : "-")
        this.LV.ModifyCol(1, 80), this.LV.ModifyCol(2, 220), this.LV.ModifyCol(3, 120)
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
