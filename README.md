# GromitBot — WoW 1.12 Vanilla Bot for Turtle WoW

C++/Lua bot for WoW 1.12.1 (build 5875) on Turtle WoW with a Python agent that pushes live status to a Discord bot for remote monitoring and control.

---

## Architecture

```
Discord Bot (separate repo / VM)  ← /commands received by users in Discord
        │ TCP JSON :9000
Python Agent (agent/agent.py)     ← per-VM, listens :9000, polls files,
        │                              pushes status to Discord webhook
        │ file I/O (1 s poll)
WoW.exe + GromitBot.dll           ← D3D8 hook, memory reads, GB_* Lua fns
        │ SuperWoW Lua API
GromitBot Addon (Lua)             ← fishing/herbalism, chat, auto-mail, human behaviour
```

The Discord bot lives in a **separate GitHub repository** and runs on a **separate VM**.
It receives `/commands` from Discord users, forwards them to the agent over TCP, and
displays the live status embeds that the agent pushes via webhook.

---

## Prerequisites

| Component | Requirement |
|-----------|-------------|
| C++ DLL | VS 2022 ("Desktop C++" workload), CMake ≥ 3.20, DirectX 8 SDK, Lua 5.1 headers/lib |
| Python | 3.11+, `pip install -r agent/requirements.txt` |
| WoW client | 1.12.1 build 5875, SuperWoW (pre-built binaries in [`superwow/`](superwow/)), Ollama (`ollama serve && ollama pull llama3`) |

---

## Build — C++ DLL

```cmd
:: 1. Fetch cpp-httplib
curl -L https://raw.githubusercontent.com/yhirose/cpp-httplib/master/httplib.h -o dll\include\httplib.h

:: 2. Get Lua 5.1 headers+lib from https://sourceforge.net/projects/luabinaries/
::    Place headers in C:\lua51\include\ and lua51.lib in C:\lua51\

:: 3. Build (32-bit)
cmake -B build -A Win32 -DLUA_INCLUDE_DIR="C:/lua51/include" -DLUA_LIB="C:/lua51/lua51.lib" -DD3D8_INCLUDE_DIR="C:/DXSDK/include"
cmake --build build --config Release
```

Output: `build\Release\GromitBot.dll` and `build\Release\injector.exe`

---

## Install & Run

**SuperWoW:** See [`superwow/README.md`](superwow/README.md) for setup instructions.

**Lua Addon:** Copy `addon/` to `C:\WoW\Interface\AddOns\GromitBot\` and enable it in the addon selector.

**Inject DLL** (after logging in):
```cmd
build\Release\injector.exe         :: auto-finds WoW.exe
build\Release\injector.exe 1234    :: or pass a PID
```

**Python Agent** (each VM):
```cmd
cd agent && python agent.py        :: listens on 0.0.0.0:9000
```
Env vars:

| Variable | Default | Description |
|----------|---------|-------------|
| `GROMITBOT_CMD_FILE` | `C:\GromitBot\command.txt` | Command file path |
| `GROMITBOT_STATUS_FILE` | `C:\GromitBot\command_status.json` | Status file path |
| `LOG_LEVEL` | `INFO` | Logging verbosity |
| `DISCORD_WEBHOOK_URL` | *(empty)* | Discord webhook URL for status push |
| `DISCORD_STATUS_INTERVAL` | `60` | Seconds between Discord status updates |

---

## Configure

Edit `config/bot_config.json` or use in-game slash commands:

| Command | Description |
|---------|-------------|
| `/gbot start` / `stop` | Start or stop the bot |
| `/gbot mode fishing\|herbalism\|leveling` | Switch mode |
| `/gbot profile <name>` | Load / hot-swap a leveling profile |
| `/gbot profiles` | List all available leveling profiles |
| `/gbot mail` | Trigger auto-mail now |
| `/gbot status` | Show bag / mode status |
| `/gbot debug` | Toggle debug messages |
| `/gbot home` | Update wiggle home position |
| `/gbot breakstop` | Cancel an in-progress AFK break |
| `/gbot reload` | Reload the UI |
| `/gbot help` | Show all commands |

---

## Agent Command Reference

Commands are sent as newline-delimited JSON over TCP to port 9000 (used by the Discord bot):

| Command | Args | Description |
|---------|------|-------------|
| `START` / `STOP` | — | Start or stop bot |
| `MODE` | `fishing\|herbalism\|leveling` | Switch mode |
| `PROFILE` | `<name>` | Load / hot-swap a leveling profile |
| `PROFILES` | — | Print available profiles to chat |
| `SAY` | `<text>` | `/say text` |
| `WHISPER` | `<target> <msg>` | Whisper player |
| `EMOTE` | `<emote>` | `DoEmote(emote)` |
| `MAIL` | — | Trigger auto-mail |
| `STATUS` | — | Write status JSON |
| `JUMP` / `SIT` / `STAND` | — | Player actions |
| `RELOAD` | — | `ReloadUI()` |
| `DISCONNECT` | — | `/quit` |
| `PRINT` | `<text>` | Print to chat frame |

---

## Discord Status Push

The agent periodically (every `DISCORD_STATUS_INTERVAL` seconds) posts a rich embed to
`DISCORD_WEBHOOK_URL` with the following fields sourced from the status JSON:

- **Zone** — current in-game zone
- **Level** — character level
- **Mode** — active bot mode (fishing / herbalism / leveling)
- **Status** — Running / Stopped
- **Bags** — bag fill percentage
- **XP / HP / Mana** — when available

The Discord bot (separate repo) then relays `/commands` back to the agent via TCP.

---

## Features

**Fishing Bot** — auto-equips rod, casts, detects bobber splash via `GB_FindFishingBobber()` + `BOBBER_SPLASH` event, loots, recasts with 1–1.5 s random delay, mails when bags hit `mailThreshold`%.

**Herbalism Bot** — casts Find Herbs, finds nearest node via `GB_FindNearestHerb()`, pathfinds via `.nav` waypoints, gathers, loots, mails when bags full.

**AI Chat** — intercepts whispers (always replies) and /say (range + message-count gated). Replies via Ollama `llama3` with a 2–4 s simulated typing delay and 8 s per-sender cooldown.

**Human Behaviour** — random camera turns (±`humanTurnAmount` rad, every 4–10 s), ~8% jump chance/s, position wiggle within `humanWiggleRadius` yards.

---

## Memory Offsets

For WoW 1.12.1 build 5875. Defined in `dll/include/offsets.h`; re-derive with CheatEngine if the client updates.

Key offsets: `STATIC_CLIENT_CONNECTION` `0x00C79CE0`, `PLAYER_POS_X/Y/Z` `0xABD6FC/700/704`, `PLAYER_CASTING_ID` `0xABD6F4`, `LUA_STATE_PTR` `0x00C7B284`.

---

## Known Limitations

- **Navmesh**: `.nav` is a straight-line stub — replace with Recast/Detour for production.
- **Mail**: `ClickSendMailItemButton()` requires SuperWoW; standard 1.12 needs a different method.
- **File I/O**: SuperWoW re-enables `io.*` (`ReadFile_SWoW`/`WriteFile_SWoW`); command poller is a no-op without it.

