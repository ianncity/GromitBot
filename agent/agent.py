"""
agent.py — GromitBot VM Agent
==============================
Runs on each Windows VM that hosts one or more WoW bot instances.

• Supports 1–8 bot slots per VM, each with its own command and status file.
• Listens on TCP port (default 9000) for JSON commands.
• Routes commands to a specific bot slot or broadcasts to all slots on the VM.
• Writes received commands to per-slot files which the Lua addon polls.
• Pushes status to a Discord webhook on a configurable interval.

Environment variables:
  GROMITBOT_PORT          — TCP listen port (default 9000)
  GROMITBOT_BOT_COUNT     — number of bot slots on this VM (default 1)
  GROMITBOT_BOT_BASE_DIR  — base dir for per-bot files (default C:\\GromitBot\\bots)
  GROMITBOT_VM_ID         — unique name for this VM (default: hostname)
  GROMITBOT_AGENT_SECRET  — shared auth token; must be present in every command
  GROMITBOT_CMD_FILE      — single-bot command file (legacy / BOT_COUNT=1 only)
  GROMITBOT_STATUS_FILE   — single-bot status file  (legacy / BOT_COUNT=1 only)
  LOG_LEVEL               — logging verbosity (default INFO)
  DISCORD_WEBHOOK_URL     — webhook URL for per-bot status embeds
  DISCORD_STATUS_INTERVAL — seconds between Discord pushes (default 60)

Multi-bot file layout (GROMITBOT_BOT_COUNT > 1):
  {BOT_BASE_DIR}\\bot_0\\command.txt   — Lua addon polls this file for bot 0
  {BOT_BASE_DIR}\\bot_0\\command_status.json
  {BOT_BASE_DIR}\\bot_1\\command.txt
  ...

Command protocol (JSON over newline-delimited TCP):
  {"cmd": "STATUS"}                       — status of all bots (BOT_COUNT>1) or bot 0
  {"cmd": "STATUS",  "bot": 2}            — status of slot 2
  {"cmd": "STATUS",  "bot": "all"}        — status of every slot on this VM
  {"cmd": "LIST"}                         — list all slots + their statuses + VM info
  {"cmd": "START",   "bot": 0}
  {"cmd": "STOP",    "bot": "all"}
  {"cmd": "MODE",    "args": "herbalism", "bot": "all"}
  {"cmd": "JUMP",    "bot": 3}
  ... (all standard commands accept "bot": <int> | "all")

  Add "auth": "<GROMITBOT_AGENT_SECRET>" when the secret is configured.

Response:
  Single target  → {"ok": true/false, "data": ..., "bot": <id>}
  Broadcast      → {"ok": true/false, "results": {"0": ..., "1": ...}}
"""

import asyncio
import json
import logging
import os
import socket
import sys
import time
from pathlib import Path
from typing import Optional, Union

import aiohttp

# ---- Config -------------------------------------------------
LISTEN_HOST             = "0.0.0.0"
LISTEN_PORT             = int(os.environ.get("GROMITBOT_PORT", "9000"))
BOT_COUNT               = max(1, int(os.environ.get("GROMITBOT_BOT_COUNT", "1")))
BOT_BASE_DIR            = Path(os.environ.get("GROMITBOT_BOT_BASE_DIR", r"C:\GromitBot\bots"))
VM_ID                   = os.environ.get("GROMITBOT_VM_ID", socket.gethostname())
AGENT_SECRET            = os.environ.get("GROMITBOT_AGENT_SECRET", "")

# Legacy single-bot paths — used when BOT_COUNT == 1 for backward compatibility
_LEGACY_CMD_FILE    = Path(os.environ.get("GROMITBOT_CMD_FILE",   r"C:\GromitBot\command.txt"))
_LEGACY_STATUS_FILE = Path(os.environ.get("GROMITBOT_STATUS_FILE", r"C:\GromitBot\command_status.json"))

LOG_LEVEL               = os.environ.get("LOG_LEVEL", "INFO").upper()
HEARTBEAT_SECS          = 30
DISCORD_WEBHOOK_URL     = os.environ.get("DISCORD_WEBHOOK_URL", "")
DISCORD_STATUS_INTERVAL = int(os.environ.get("DISCORD_STATUS_INTERVAL", "60"))

# ---- Logging ------------------------------------------------
_LOG_FILE = BOT_BASE_DIR.parent / "agent.log"
_LOG_FILE.parent.mkdir(parents=True, exist_ok=True)
logging.basicConfig(
    format="%(asctime)s [%(levelname)s] %(message)s",
    level=getattr(logging, LOG_LEVEL, logging.INFO),
    handlers=[
        logging.StreamHandler(sys.stdout),
        logging.FileHandler(_LOG_FILE, encoding="utf-8"),
    ],
)
log = logging.getLogger("gromitbot-agent")

# ---- Path helpers -------------------------------------------
def get_bot_paths(bot_id: int) -> tuple[Path, Path]:
    """Return (command_file, status_file) for the given bot slot."""
    if BOT_COUNT == 1:
        return _LEGACY_CMD_FILE, _LEGACY_STATUS_FILE
    slot_dir = BOT_BASE_DIR / f"bot_{bot_id}"
    return slot_dir / "command.txt", slot_dir / "command_status.json"

# ---- Discord helpers ----------------------------------------
def _build_discord_payload(status: dict) -> dict:
    """Format a bot status dict into a Discord webhook embed payload."""
    char_name = status.get("name", status.get("player", "Unknown"))
    zone      = status.get("zone", "Unknown")
    level     = status.get("level", "?")
    mode      = status.get("mode", "unknown")
    running   = status.get("running", False)
    bag_pct   = status.get("bagFull", status.get("bagFillPct", 0))
    xp        = status.get("xp", None)
    hp        = status.get("hp", None)
    mana      = status.get("mana", None)
    vm_id     = status.get("vm_id", VM_ID)
    bot_id    = status.get("bot_id", 0)

    colour = 0x2ecc71 if running else 0xe74c3c

    fields = [
        {"name": "VM",     "value": f"{vm_id}[{bot_id}]",          "inline": True},
        {"name": "Zone",   "value": str(zone),                      "inline": True},
        {"name": "Level",  "value": str(level),                     "inline": True},
        {"name": "Mode",   "value": str(mode),                      "inline": True},
        {"name": "Status", "value": "Running" if running else "Stopped", "inline": True},
        {"name": "Bags",   "value": f"{bag_pct:.0f}%",              "inline": True},
    ]
    if xp   is not None: fields.append({"name": "XP",   "value": str(xp),   "inline": True})
    if hp   is not None: fields.append({"name": "HP",   "value": str(hp),   "inline": True})
    if mana is not None: fields.append({"name": "Mana", "value": str(mana), "inline": True})

    return {
        "embeds": [{
            "title":       f"GromitBot — {char_name}",
            "description": f"Status at <t:{int(time.time())}:T>",
            "color":       colour,
            "fields":      fields,
        }]
    }


async def push_discord_status(status: dict) -> None:
    """POST a status embed to the configured Discord webhook."""
    if not DISCORD_WEBHOOK_URL:
        return
    payload = _build_discord_payload(status)
    try:
        async with aiohttp.ClientSession() as session:
            async with session.post(
                DISCORD_WEBHOOK_URL,
                json=payload,
                timeout=aiohttp.ClientTimeout(total=10),
            ) as resp:
                if resp.status not in (200, 204):
                    text = await resp.text()
                    log.warning("Discord webhook returned %d: %s", resp.status, text[:200])
                else:
                    log.debug("Discord status pushed (HTTP %d)", resp.status)
    except Exception as exc:
        log.warning("Failed to push Discord status: %s", exc)

# ---- Valid commands (relayed to Lua via command file) -------
VALID_CMDS = {
    "DISCONNECT", "JUMP", "SAY", "WHISPER", "STOP", "START",
    "MODE", "MAIL", "STATUS", "PRINT", "RELOAD", "EMOTE",
    "SIT", "STAND", "PROFILE", "PROFILES", "POSITION",
}


# ---- File helpers ------------------------------------------
def write_command(line: str, bot_id: int = 0) -> None:
    """Append a command line to the given bot slot's command file."""
    cmd_file, _ = get_bot_paths(bot_id)
    cmd_file.parent.mkdir(parents=True, exist_ok=True)
    with cmd_file.open("a", encoding="utf-8") as f:
        f.write(line.strip() + "\n")
    log.debug("Bot %d: wrote command: %s", bot_id, line.strip())


def read_status(bot_id: int = 0) -> dict:
    """Read the status JSON written by the Lua addon for this bot slot."""
    _, status_file = get_bot_paths(bot_id)
    try:
        if status_file.exists():
            text = status_file.read_text(encoding="utf-8").strip()
            if text:
                data = json.loads(text)
                data["bot_id"] = bot_id
                data["vm_id"]  = VM_ID
                # Normalise character name: Lua writes "player", Discord bot reads "name"
                if "name" not in data:
                    data["name"] = data.get("player", "Unknown")
                return data
    except Exception as exc:
        log.warning("Bot %d: failed to read status: %s", bot_id, exc)
    return {"error": "status_unavailable", "bot_id": bot_id, "vm_id": VM_ID,
            "time": time.time()}


# ---- Command builder ----------------------------------------
def build_command_line(cmd: str, args: Optional[str]) -> str:
    """Convert a parsed command into a single file-line."""
    cmd = cmd.upper().strip()
    if args:
        return f"{cmd} {args.strip()}"
    return cmd


# ---- Bot target parser --------------------------------------
def parse_bot_targets(payload: dict) -> Union[list[int], str]:
    """
    Return a list of bot slot IDs to target, or an error string.

    "bot" key rules:
      absent with BOT_COUNT==1  → [0]          (backward compat)
      absent with BOT_COUNT>1   → all slots     (broadcast default)
      "all"                     → all slots
      <integer>                 → that single slot
    """
    raw = payload.get("bot", "all" if BOT_COUNT > 1 else 0)
    if raw == "all":
        return list(range(BOT_COUNT))
    try:
        idx = int(raw)
    except (TypeError, ValueError):
        return f"invalid bot value: {raw!r}"
    if not (0 <= idx < BOT_COUNT):
        return f"bot index {idx} out of range (0–{BOT_COUNT - 1})"
    return [idx]


# ---- Connection handler -------------------------------------
async def handle_client(reader: asyncio.StreamReader,
                         writer: asyncio.StreamWriter) -> None:
    peer = writer.get_extra_info("peername")
    log.info("Connection from %s", peer)
    try:
        while True:
            data = await asyncio.wait_for(reader.readline(), timeout=60.0)
            if not data:
                break
            line = data.decode("utf-8", errors="replace").strip()
            if not line:
                continue

            try:
                payload = json.loads(line)
            except json.JSONDecodeError as exc:
                resp = {"ok": False, "error": f"JSON parse error: {exc}"}
                writer.write(json.dumps(resp).encode() + b"\n")
                await writer.drain()
                continue

            # --- Authentication ---
            if AGENT_SECRET:
                if payload.get("auth") != AGENT_SECRET:
                    resp = {"ok": False, "error": "Unauthorized"}
                    writer.write(json.dumps(resp).encode() + b"\n")
                    await writer.drain()
                    log.warning("[%s] Authentication failure — closing", peer)
                    break

            cmd  = str(payload.get("cmd", "")).upper()
            args = payload.get("args", None)

            if cmd == "LIST":
                # Return VM identity and all slot statuses
                resp = {
                    "ok": True,
                    "data": {
                        "vm_id":     VM_ID,
                        "bot_count": BOT_COUNT,
                        "bots":      [read_status(i) for i in range(BOT_COUNT)],
                    },
                }

            elif cmd not in VALID_CMDS:
                resp = {"ok": False, "error": f"Unknown command: {cmd}"}

            else:
                targets = parse_bot_targets(payload)
                if isinstance(targets, str):
                    resp = {"ok": False, "error": targets}
                elif cmd == "STATUS":
                    if len(targets) == 1:
                        resp = {"ok": True, "data": read_status(targets[0]),
                                "bot": targets[0], "vm_id": VM_ID}
                    else:
                        resp = {
                            "ok":   True,
                            "data": {str(i): read_status(i) for i in targets},
                            "vm_id": VM_ID,
                        }

                elif cmd == "POSITION":
                    if len(targets) == 1:
                        resp = {"ok": True, "data": read_status(targets[0]),
                                "bot": targets[0], "vm_id": VM_ID}
                    else:
                        resp = {
                            "ok":   True,
                            "data": {"bots": [read_status(i) for i in targets]},
                            "vm_id": VM_ID,
                        }
                else:
                    results: dict[str, dict] = {}
                    for bot_id in targets:
                        cmdline = build_command_line(cmd, args)
                        try:
                            write_command(cmdline, bot_id)
                            results[str(bot_id)] = {"ok": True, "queued": cmdline}
                        except Exception as exc:
                            results[str(bot_id)] = {"ok": False, "error": str(exc)}
                    if len(targets) == 1:
                        resp = results[str(targets[0])]
                        resp["bot"] = targets[0]
                    else:
                        all_ok = all(v["ok"] for v in results.values())
                        resp = {"ok": all_ok, "results": results}

            writer.write(json.dumps(resp).encode() + b"\n")
            await writer.drain()
            log.info("[%s] %s bot=%s → ok=%s",
                     peer, cmd, payload.get("bot", "default"), resp.get("ok"))

    except asyncio.TimeoutError:
        log.debug("Client %s timed out", peer)
    except ConnectionResetError:
        log.debug("Client %s disconnected", peer)
    except Exception as exc:
        log.error("Error handling %s: %s", peer, exc)
    finally:
        try:
            writer.close()
        except Exception:
            pass
        log.debug("Closed connection from %s", peer)


# ---- Heartbeat log -----------------------------------------
async def heartbeat() -> None:
    while True:
        await asyncio.sleep(HEARTBEAT_SECS)
        statuses = [read_status(i) for i in range(BOT_COUNT)]
        running  = sum(1 for s in statuses if s.get("running"))
        log.info("Heartbeat — %d/%d bot(s) running on %s", running, BOT_COUNT, VM_ID)


# ---- Discord status pusher ---------------------------------
async def discord_status_pusher() -> None:
    """Periodically push per-bot status embeds to the Discord webhook."""
    if not DISCORD_WEBHOOK_URL:
        log.info("DISCORD_WEBHOOK_URL not set — status push disabled")
        return
    log.info("Discord status pusher started (interval=%ds, bots=%d)",
             DISCORD_STATUS_INTERVAL, BOT_COUNT)
    while True:
        await asyncio.sleep(DISCORD_STATUS_INTERVAL)
        for bot_id in range(BOT_COUNT):
            status = read_status(bot_id)
            await push_discord_status(status)
            if BOT_COUNT > 1:
                await asyncio.sleep(1.0)  # avoid Discord rate-limit between bots


# ---- Main --------------------------------------------------
async def main() -> None:
    # Ensure all bot command files exist
    for bot_id in range(BOT_COUNT):
        cmd_file, _ = get_bot_paths(bot_id)
        cmd_file.parent.mkdir(parents=True, exist_ok=True)
        if not cmd_file.exists():
            cmd_file.write_text("", encoding="utf-8")

    server = await asyncio.start_server(handle_client, LISTEN_HOST, LISTEN_PORT)
    addrs  = ", ".join(str(s.getsockname()) for s in server.sockets)
    log.info("GromitBot Agent listening on %s", addrs)
    log.info("VM ID      : %s", VM_ID)
    log.info("Bot slots  : %d", BOT_COUNT)
    if AGENT_SECRET:
        log.info("Auth       : enabled")
    if BOT_COUNT > 1:
        log.info("Bot base   : %s", BOT_BASE_DIR)
    else:
        log.info("Command    : %s", _LEGACY_CMD_FILE)
        log.info("Status     : %s", _LEGACY_STATUS_FILE)

    asyncio.create_task(heartbeat())
    asyncio.create_task(discord_status_pusher())

    async with server:
        await server.serve_forever()


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        log.info("Agent stopped.")
