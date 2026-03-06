# GromitBot — WoW 1.12 Vanilla Bot for Turtle WoW

A C++/Lua hybrid bot for World of Warcraft 1.12.1 (build 5875) on the Turtle WoW private server, with a Python management layer for remote control.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│  FastAPI Management Server  (server/main.py — any machine)      │
│  - REST API to register VMs and send commands                   │
│  - Broadcasts to all agents simultaneously                      │
└────────────────────────────────┬────────────────────────────────┘
                                 │ TCP JSON (port 8000)
              ┌──────────────────▼──────────────────────┐
              │  Windows VM (one per WoW instance)       │
              │  ┌───────────────────────────────────┐   │
              │  │  Python Agent (agent/agent.py)    │   │
              │  │  - Listens on TCP port 9000        │   │
              │  │  - Writes commands → command.txt  │   │
              │  │  - Reads status ← command_status. │   │
              │  └──────────┬────────────────────────┘   │
              │             │  file I/O (1 s poll)        │
              │  ┌──────────▼────────────────────────┐   │
              │  │  WoW.exe (1.12.1 build 5875)       │   │
              │  │  ┌──────────────────────────────┐  │   │
              │  │  │  GromitBot.dll  (C++ DLL)    │  │   │
              │  │  │  - Injected via injector.exe │  │   │
              │  │  │  - Reads process memory      │  │   │
              │  │  │  - Hooks D3D8 EndScene        │  │   │
              │  │  │  - Registers GB_* Lua funcs  │  │   │
              │  │  │  - HTTP → Ollama :11434       │  │   │
              │  │  └────────────┬─────────────────┘  │   │
              │  │               │ SuperWoW Lua API     │   │
              │  │  ┌────────────▼─────────────────┐  │   │
              │  │  │  GromitBot Addon  (Lua)       │  │   │
              │  │  │  - Fishing / Herbalism bots   │  │   │
              │  │  │  - Chat interceptor + Ollama  │  │   │
              │  │  │  - Auto-mail when bags full   │  │   │
              │  │  │  - Human behaviour randomiser │  │   │
              │  │  │  - Command file poller        │  │   │
              │  │  └──────────────────────────────┘  │   │
              │  └───────────────────────────────────┘   │
              └─────────────────────────────────────────┘
```

---

## Prerequisites

### Build environment (C++ DLL)
| Tool | Version | Notes |
|------|---------|-------|
| Visual Studio | 2022 | Install "Desktop development with C++" workload |
| CMake | ≥ 3.20 | Add to PATH |
| Windows SDK | 10.x | Included with VS |
| DirectX 8 SDK | DXSDK_Jun10 | For `d3d8.h` — install from archive.org |
| Lua 5.1 headers + lib | 5.1.x | Match WoW's embedded Lua version |

### Python (agent + server)
- Python 3.11+
- `pip install -r agent/requirements.txt`
- `pip install -r server/requirements.txt`

### WoW client
- WoW 1.12.1 build 5875 (Turtle WoW client)
- [SuperWoW](https://github.com/balakethelock/SuperWoW) installed (enables Lua file I/O + custom events)
- Ollama running locally: `ollama serve` with `ollama pull llama3`

---

## Repository Layout

```
GromitBot/
├── CMakeLists.txt              Root CMake
├── config/
│   └── bot_config.json         Bot configuration (reference copy)
├── dll/
│   ├── CMakeLists.txt
│   ├── include/
│   │   ├── httplib.h           ← DOWNLOAD (see below)
│   │   └── offsets.h           WoW 1.12 memory offsets
│   └── src/
│       ├── dllmain.cpp         DLL entry, installs hooks
│       ├── hooks.cpp/h         D3D8 EndScene vtable hook
│       ├── memory.cpp/h        Process memory read/write
│       ├── lua_bridge.cpp/h    GB_* Lua function registration
│       ├── http_client.cpp/h   Ollama / HTTP client
│       └── injector.cpp        Standalone LoadLibrary injector
├── addon/
│   ├── GromitBot.toc           WoW addon manifest
│   ├── GromitBot.lua           Main entry, event dispatcher
│   ├── config.lua              SavedVariables config
│   ├── utils.lua               Shared helpers
│   ├── fishing.lua             Fishing bot state machine
│   ├── herbalism.lua           Herbalism bot + pathfinding
│   ├── chat_listener.lua       Chat → Ollama → reply
│   ├── inventory.lua           Bag fullness + auto-mail
│   ├── human_behavior.lua      Random jumps / turns / wiggles
│   ├── command_poller.lua      Polls command.txt each second
│   └── navmesh/
│       └── arathi.nav          Example Arathi Highlands route
├── agent/
│   ├── agent.py                Python TCP agent (per VM)
│   └── requirements.txt
└── server/
    ├── main.py                 FastAPI management server
    ├── models.py               Pydantic models
    └── requirements.txt
```

---

## Build — C++ DLL

### 1. Download cpp-httplib
```cmd
curl -L https://raw.githubusercontent.com/yhirose/cpp-httplib/master/httplib.h ^
     -o dll\include\httplib.h
```

### 2. Obtain Lua 5.1 headers
Download from https://sourceforge.net/projects/luabinaries/ (5.1.5 Win32 DLL + header).
Extract so that `lua.h`, `lauxlib.h`, `lualib.h` are in `C:\lua51\include\`
and `lua51.lib` is in `C:\lua51\`.

### 3. Configure and build (32-bit!)
```cmd
cmake -B build -A Win32 ^
      -DLUA_INCLUDE_DIR="C:/lua51/include" ^
      -DLUA_LIB="C:/lua51/lua51.lib" ^
      -DD3D8_INCLUDE_DIR="C:/DXSDK/include"

cmake --build build --config Release
```

Output: `build\Release\GromitBot.dll` and `build\Release\injector.exe`
(if you add injector.cpp as a second target).

---

## Install — Lua Addon

1. Copy the `addon/` folder to:
   ```
   C:\WoW\Interface\AddOns\GromitBot\
   ```
2. Enable "GromitBot" in the WoW addon selector.
3. Ensure SuperWoW is active (`SuperWoW_Loaded` will be true in game).

---

## Inject the DLL

After WoW is running and you're logged in:

```cmd
cd build\Release
injector.exe
```

The injector auto-finds `WoW.exe`. You can also pass a PID:
```cmd
injector.exe 1234
```

Once injected, `GromitBot.dll` installs a D3D8 EndScene hook. On the first
rendered frame it reads the Lua state pointer and registers all `GB_*` functions.
The addon receives these immediately and is ready to use.

---

## Configure

Edit `config/bot_config.json` (used as a reference), then transfer settings
to the addon's `SavedVariables` file:
```
C:\WoW\WTF\Account\<ACCOUNT>\SavedVariables\GromitBot.lua
```

Or use in-game slash commands:

| Command | Description |
|---------|-------------|
| `/gbot start` | Start the configured bot mode |
| `/gbot stop` | Stop bot |
| `/gbot mode fishing` | Switch to fishing mode |
| `/gbot mode herbalism` | Switch to herbalism mode |
| `/gbot mail` | Trigger auto-mail now |
| `/gbot status` | Show bag / mode status |
| `/gbot debug` | Toggle debug chat messages |
| `/gbot home` | Update home position for wiggle behaviour |
| `/gbot help` | Show all commands |

---

## Run — Python Agent (each VM)

```cmd
cd agent
pip install -r requirements.txt
python agent.py
```

Environment variables:
```
GROMITBOT_CMD_FILE    default: C:\GromitBot\command.txt
GROMITBOT_STATUS_FILE default: C:\GromitBot\command_status.json
LOG_LEVEL             default: INFO
```

Agent listens on `0.0.0.0:9000`.

---

## Run — FastAPI Management Server

```cmd
cd server
pip install -r requirements.txt
uvicorn main:app --host 0.0.0.0 --port 8000 --reload
```

Interactive docs: http://localhost:8000/docs

### Quick-start API example

```bash
# Register a VM agent
curl -X POST http://localhost:8000/agents \
     -H "Content-Type: application/json" \
     -d '{"vm_id":"vm1","host":"192.168.1.101","port":9000}'

# Start the bot on vm1
curl -X POST http://localhost:8000/agents/vm1/start

# Check status
curl http://localhost:8000/agents/vm1/status

# Make all bots jump
curl -X POST http://localhost:8000/broadcast \
     -d '{"cmd":"JUMP"}'

# Send a /say message
curl -X POST http://localhost:8000/agents/vm1/say \
     -d '{"text":"Hello world!"}'

# Stop bot
curl -X POST http://localhost:8000/agents/vm1/stop
```

---

## Bot Modes

### Fishing Bot
1. Equips fishing rod automatically.
2. Casts via `CastSpellByName("Fishing")`.
3. Polls for bobber splash (D3D dynamic flags via `GB_FindFishingBobber()`).
4. Also listens for the SuperWoW `BOBBER_SPLASH` event as backup.
5. Right-clicks bobber via `SuperWoW_InteractObject()`.
6. Auto-loots via `LOOT_OPENED` event.
7. Recasts after 1.0–1.5 s randomized delay.
8. When bags reach `mailThreshold`%, stops fishing and mails inventory.

### Herbalism Bot
1. Casts `Find Herbs` tracking.
2. Reads nearest herb node from object manager via `GB_FindNearestHerb()`.
3. Pathfinds using waypoints from the `.nav` file (straight-line stub included;
   replace with Recast/Detour navmesh for production).
4. Right-clicks herb node to gather.
5. Auto-loots. Moves to next node.
6. When bags full: triggers auto-mail.

---

## AI Chat Listener

- Intercepts **WHISPER** and **SAY** messages.
- **Whispers**: always replies.
- **Say**: only replies if sender is within `chatReplySayRange` yards AND
  has sent `chatReplyMinSayMessages` or more messages this session.
- Reply is generated by Ollama (`llama3` by default) using a configurable
  persona prompt.
- A randomized **2–4 second** delay simulates human typing.
- Per-sender cooldown of 8 seconds prevents spam loops.

---

## Human Behaviour

All bots apply the following randomisation while active:

| Behaviour | Description |
|-----------|-------------|
| Camera turns | Random yaw ±`humanTurnAmount` rad every 4–10 s |
| Jumps | ~8% chance per second of a single jump |
| Position wiggle | Wanders ≤ `humanWiggleRadius` yards from home, returns after 2 s |

Tune via `humanJumpChance`, `humanTurnAmount`, `humanTurnInterval`, and
`humanWiggleInterval` in config.

---

## Agent Command Reference

Commands sent from the management server (or typed directly into `command.txt`):

| Command | Args | Description |
|---------|------|-------------|
| `DISCONNECT` | — | Leave game (`/quit`) |
| `JUMP` | — | Player jumps once |
| `SAY` | `<text>` | Send `/say text` |
| `WHISPER` | `<target> <msg>` | Whisper player |
| `STOP` | — | Stop active bot |
| `START` | — | Start configured bot |
| `MODE` | `fishing\|herbalism` | Switch mode |
| `MAIL` | — | Trigger auto-mail |
| `STATUS` | — | Write status JSON to file |
| `PRINT` | `<text>` | Print to chat frame |
| `RELOAD` | — | `ReloadUI()` |
| `EMOTE` | `<emote>` | `DoEmote(emote)` |
| `SIT` | — | Sit |
| `STAND` | — | Stand |

---

## Memory Offsets

All offsets are for **WoW 1.12.1 build 5875** (Turtle WoW). Defined in
`dll/include/offsets.h`. If Turtle WoW updates the client, re-derive offsets
using CheatEngine against the new binary.

Key offsets verified:
- `STATIC_CLIENT_CONNECTION` `0x00C79CE0` — object manager root
- `PLAYER_POS_X/Y/Z` `0xABD6FC/700/704` — local player world position
- `PLAYER_CASTING_ID` `0xABD6F4` — current cast spell ID
- `LUA_STATE_PTR` `0x00C7B284` — Lua VM state pointer

---

## Known Limitations / TODO

- **Navmesh**: The included `.nav` file is a straight-line waypoint stub.
  For production, generate a proper navmesh with Recast/Detour.
- **Mail**: `ClickSendMailItemButton()` is a SuperWoW-extended function;
  standard 1.12 may require a different attachment method.
- **Herb interaction**: `SuperWoW_InteractObject` must be available; the
  fallback `/target + /interact` macro is less reliable.
- **Bobber detection**: Polling via `GB_FindFishingBobber()` every 100 ms is
  reliable; the `BOBBER_SPLASH` SuperWoW event is a bonus.
- **File I/O in Lua**: Standard 1.12 Lua disables `io.*`. SuperWoW re-enables
  it via `ReadFile_SWoW` / `WriteFile_SWoW`. Without SuperWoW the command
  poller does nothing.

---

## Disclaimer

This project is for **educational purposes only** — understanding memory
reading, Lua/C++ interop, and async Python architectures. Using bots on any
game server may violate the Terms of Service. The authors bear no
responsibility for account actions taken against users of this code.
