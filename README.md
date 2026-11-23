# KitsuneRoblox

Small tray tool for Roblox clients in your own Windows session:

- **Accounts**: Add account opens a Roblox login page; you log in yourself. Each account keeps its own saved login browser (`%LOCALAPPDATA%\KitsuneRoblox\profiles`, never share it). Play / Play all open Roblox's own start page in real Edge with that account's profile (one at a time, closed again once Roblox opens), so Roblox starts the game as that account. Ctrl/Shift+click selects many.
- **Anti-AFK**: every 15 min (you can change it) it focuses each Roblox window for a moment, taps one key, and gives focus back.
- **Auto rejoin**: after a disconnect it opens the game again with the same account. If you close a client yourself, it does not rejoin. Stops after 3 failed launches.
- **Multi-instance**: frees Roblox's one-client lock (closes the `ROBLOX_singletonEvent` handle, like Process Explorer's "Close Handle"), so more clients can open.

- **RAM limit**: soft cap per client (default 2 GB). Extra memory goes to disk, so no crash, only slower.

It stops and beeps if Roblox shows a popup or a kick message.

Needs: Windows, WebView2 runtime (comes with Windows 11), AutoHotkey v2 at `tools\AutoHotkey64.exe` (not in git; copy it from KitsuneMacro). Start with `run.bat`.
