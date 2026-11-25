# KitsuneRoblox

Small tray tool for Roblox clients in your own Windows session:

- **Accounts**: Add account opens a Roblox login page; you log in yourself. Each account keeps its own saved login browser (`%LOCALAPPDATA%\KitsuneRoblox\profiles`, never share it). Play / Play all start Roblox directly, one at a time. Roblox logs in with its own saved login, so the tool keeps a copy of it per account and puts the right one in place before each Play. First Play of an account: sign in yourself in the Roblox window, and it is saved. Ctrl/Shift+click selects many.
- **Anti-AFK**: every 15 min (you can change it) it focuses each Roblox window for a moment, taps one key, and gives focus back.
- **Auto rejoin**: after a disconnect it opens the game again with the same account. If you close a client yourself, it does not rejoin. Stops after 3 failed launches.
- **Multi-instance**: each account runs Roblox from its own path (a folder link in its profile to Fishstrap's Roblox folder, made again when Fishstrap updates), so a new client doesn't hand its join to an open one. Needs Fishstrap. A small `LockKeeper.ahk` process holds Roblox's lock (`ROBLOX_singletonMutex`), so one client closing doesn't close the others. The keeper stays when you close the tool and quits 2 min after the last client closes.

- **Trim RAM**: 1 min after a client starts, then every 10 min, unused memory goes to disk. No cap, so no freeze.

It stops and beeps if Roblox shows a popup or a kick message.

Needs: Windows, WebView2 runtime (comes with Windows 11), AutoHotkey v2 at `tools\AutoHotkey64.exe` (not in git; copy it from KitsuneMacro). Start with `run.bat`.
