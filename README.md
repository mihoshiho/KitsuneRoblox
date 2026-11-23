# KitsuneRoblox

Small tray tool for Roblox clients in your own Windows session:

- **Anti-AFK**: every 15 min (you can change it) it focuses each Roblox window for a moment, taps one key, and gives focus back.
- **Auto rejoin**: when a client disconnects or closes, it opens your game link again. Stops after 3 failed launches.
- **Multi-instance**: frees Roblox's one-client lock (closes the `ROBLOX_singletonEvent` handle, like Process Explorer's "Close Handle"), so more clients can open.

It stops and beeps if Roblox shows a popup or a kick message.

Needs: Windows, AutoHotkey v2 at `tools\AutoHotkey64.exe` (not in git; copy it from KitsuneMacro). Start with `run.bat`.
