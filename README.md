# GromitBot

C# scaffold for a WoW bot agent with Discord-side command interoperability via TCP JSON lines.

## What Is Implemented

- .NET worker host with Windows service support (`GromitBotAgent`)
- TCP command server (newline-delimited JSON)
- Multi-slot bot manager (1-8 slots)
- Core commands (`LIST`, `STATUS`, `POSITION`, `START`, `STOP`, `MODE`, `PROFILE`, `PROFILES`, social/action passthrough)
- Persistent per-slot state snapshots (`state/`)
- WoW bridge abstraction with addon IPC + memory-input fallback
- Starter mode loops (`fishing`, `herbalism`) plus profile/navmesh-driven leveling routing
- Starter addon files under `addon/GromitBot/`
- VM bootstrap script at `installer/bootstrap.bat`

## Quick Start (Local)

From repo root:

```powershell
dotnet restore src/GromitBot.Agent/GromitBot.Agent.csproj
dotnet run --project src/GromitBot.Agent/GromitBot.Agent.csproj -- --contentRoot C:\GromitBot
```

Default command endpoint:

- Host: `127.0.0.1` (development)
- Port: `9000`

## Command Format

One JSON object per line:

```json
{"cmd":"MODE","args":"fishing","bot":0,"auth":""}
```

Common commands:

- `LIST`
- `STATUS`
- `POSITION`
- `PROFILES`
- `PROFILE` with `args` set to a profile name
- `MODE` with `args` in: `fishing`, `herbalism`, `leveling`
- `START`
- `STOP`
- `SAY`, `WHISPER`, `EMOTE`, `PRINT`, `MAIL`, `JUMP`, `SIT`, `STAND`, `RELOAD`, `DISCONNECT`

## Runtime Layout

Runtime paths are relative to content root:

- `profiles/` (starter: `profiles/default.json`)
- `navmeshes/` (starter: `navmeshes/default.json`)
- `state/` (slot snapshots)
- `ipc/` (addon telemetry and queued actions)

## Windows Service Bootstrap

Run as Administrator:

```bat
installer\bootstrap.bat
```

Script actions:

1. Creates runtime directories
2. Restores and publishes self-contained single-file build
3. Creates/updates `GromitBotAgent` service
4. Sets recovery policy (auto-restart)
5. Starts service

## Addon

Starter addon files are in:

- `addon/GromitBot/GromitBot.toc`
- `addon/GromitBot/GromitBot.lua`

Copy that folder into your WoW Interface AddOns directory on the game VM.
