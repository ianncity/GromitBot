# SuperWoW — Pre-built Binaries

This folder contains the pre-built SuperWoW binaries required for GromitBot to function with Turtle WoW (WoW 1.12.1 build 5875).

| File | Purpose |
|------|---------|
| `SuperWoWlauncher.exe` | Launches `WoW.exe` with the SuperWoW hook loaded |
| `SuperWoWhook.dll` | SuperWoW DLL that re-enables extended Lua APIs inside WoW |

---

## What is SuperWoW?

[SuperWoW](https://github.com/balakethelock/SuperWoW) is a third-party extension for WoW 1.12.1 that unlocks additional Lua functions used by GromitBot:

- **`io.*` file access** (`ReadFile_SWoW` / `WriteFile_SWoW`) — needed for the command poller in `GromitBot Addon`
- **`ClickSendMailItemButton()`** — needed for the auto-mail feature

Without SuperWoW, the file I/O command poller and auto-mail are no-ops.

---

## Installation

1. **Copy both files** (`SuperWoWlauncher.exe` and `SuperWoWhook.dll`) into your Turtle WoW installation directory (the folder that contains `WoW.exe`), e.g.:
   ```
   C:\TurtleWoW\SuperWoWlauncher.exe
   C:\TurtleWoW\SuperWoWhook.dll
   ```

2. **Launch WoW via the launcher** instead of `WoW.exe` directly:
   ```cmd
   C:\TurtleWoW\SuperWoWlauncher.exe
   ```
   `SuperWoWlauncher.exe` starts `WoW.exe` and injects `SuperWoWhook.dll` automatically.

3. **Verify** the hook is active — in-game, open the Lua console and type:
   ```lua
   /script print(SuperWoW and "SuperWoW OK" or "NOT loaded")
   ```
   You should see `SuperWoW OK` in the chat frame.

4. **Continue with the normal GromitBot setup** — inject `GromitBot.dll` after logging in (see the top-level [README](../README.md#install--run)).

---

## Compatibility

These binaries target **Turtle WoW** (WoW 1.12.1 build 5875). They will not work with retail or other WoW versions.

> **Source:** <https://github.com/balakethelock/SuperWoW>
