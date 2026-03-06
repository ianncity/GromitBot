"""
agent.py — GromitBot VM Agent
==============================
Runs on each Windows VM that runs a WoW instance.

• Listens on TCP port (default 9000) for JSON commands from the
  Discord bot (running on a separate VM/repo).
• Writes received commands to a local file (command.txt) which
  the Lua addon polls every second.
• Reads a status JSON file written by the Lua addon and pushes
  it to a Discord webhook on a configurable interval, reporting
  useful info such as zone, level, mode, and bag fill %.

Command protocol (JSON over newline-delimited TCP):
  → {"cmd": "JUMP"}
  → {"cmd": "SAY", "args": "Hello world"}
  → {"cmd": "DISCONNECT"}
  → {"cmd": "STATUS"}            ← returns status JSON
  → {"cmd": "START"}
  → {"cmd": "STOP"}
  → {"cmd": "MODE", "args": "fishing"}
  → {"cmd": "PRINT", "args": "some text"}
  → {"cmd": "MAIL"}
  → {"cmd": "WHISPER", "args": "PlayerName hello there"}
  → {"cmd": "RELOAD"}

Response: {"ok": true, "data": ...} or {"ok": false, "error": ...}

Discord webhook env vars:
  DISCORD_WEBHOOK_URL    — full webhook URL (required for status push)
  DISCORD_STATUS_INTERVAL — seconds between pushes (default 60)
"""

import asyncio
import json
import logging
import os
import sys
import time
from pathlib import Path
from typing import Optional

import aiohttp

# ---- Config -------------------------------------------------
LISTEN_HOST             = "0.0.0.0"
LISTEN_PORT             = 9000
COMMAND_FILE            = Path(os.environ.get("GROMITBOT_CMD_FILE",   r"C:\GromitBot\command.txt"))
STATUS_FILE             = Path(os.environ.get("GROMITBOT_STATUS_FILE", r"C:\GromitBot\command_status.json"))
LOG_LEVEL               = os.environ.get("LOG_LEVEL", "INFO").upper()
HEARTBEAT_SECS          = 30   # seconds between keep-alive logs
DISCORD_WEBHOOK_URL     = os.environ.get("DISCORD_WEBHOOK_URL", "")
DISCORD_STATUS_INTERVAL = int(os.environ.get("DISCORD_STATUS_INTERVAL", "60"))

# ---- Logging ------------------------------------------------
logging.basicConfig(
    format="%(asctime)s [%(levelname)s] %(message)s",
    level=getattr(logging, LOG_LEVEL, logging.INFO),
    handlers=[
        logging.StreamHandler(sys.stdout),
        logging.FileHandler(r"C:\GromitBot\agent.log", encoding="utf-8"),
    ],
)
log = logging.getLogger("gromitbot-agent")

# ---- Discord helpers ----------------------------------------
def _build_discord_payload(status: dict) -> dict:
    """Format a bot status dict into a Discord webhook embed payload."""
    char_name = status.get("name", "Unknown")
    zone      = status.get("zone", "Unknown")
    level     = status.get("level", "?")
    mode      = status.get("mode", "unknown")
    running   = status.get("running", False)
    bag_pct   = status.get("bagFillPct", 0)
    xp        = status.get("xp", None)
    hp        = status.get("hp", None)
    mana      = status.get("mana", None)

    colour    = 0x2ecc71 if running else 0xe74c3c  # green / red

    fields = [
        {"name": "Zone",   "value": str(zone),  "inline": True},
        {"name": "Level",  "value": str(level), "inline": True},
        {"name": "Mode",   "value": str(mode),  "inline": True},
        {"name": "Status", "value": "Running" if running else "Stopped", "inline": True},
        {"name": "Bags",   "value": f"{bag_pct}%", "inline": True},
    ]
    if xp is not None:
        fields.append({"name": "XP", "value": str(xp), "inline": True})
    if hp is not None:
        fields.append({"name": "HP",   "value": str(hp),   "inline": True})
    if mana is not None:
        fields.append({"name": "Mana", "value": str(mana), "inline": True})

    return {
        "embeds": [{
            "title":       f"GromitBot — {char_name}",
            "description": f"Status update at <t:{int(time.time())}:T>",
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

# ---- Valid commands set ------------------------------------
VALID_CMDS = {
    "DISCONNECT", "JUMP", "SAY", "WHISPER", "STOP", "START",
    "MODE", "MAIL", "STATUS", "PRINT", "RELOAD", "EMOTE",
    "SIT", "STAND",
}


# ---- File helpers ------------------------------------------
def write_command(line: str) -> None:
    """Append a command line to the command file."""
    COMMAND_FILE.parent.mkdir(parents=True, exist_ok=True)
    with COMMAND_FILE.open("a", encoding="utf-8") as f:
        f.write(line.strip() + "\n")
    log.debug("Wrote command: %s", line.strip())


def read_status() -> dict:
    """Read the status JSON written by the Lua addon."""
    try:
        if STATUS_FILE.exists():
            text = STATUS_FILE.read_text(encoding="utf-8").strip()
            if text:
                return json.loads(text)
    except Exception as exc:
        log.warning("Failed to read status file: %s", exc)
    return {"error": "status_unavailable", "time": time.time()}


# ---- Command builder ----------------------------------------
def build_command_line(cmd: str, args: Optional[str]) -> str:
    """Convert a parsed command into a single file-line."""
    cmd = cmd.upper().strip()
    if args:
        return f"{cmd} {args.strip()}"
    return cmd


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

            cmd  = str(payload.get("cmd", "")).upper()
            args = payload.get("args", None)

            if cmd not in VALID_CMDS:
                resp = {"ok": False, "error": f"Unknown command: {cmd}"}
            elif cmd == "STATUS":
                status = read_status()
                resp = {"ok": True, "data": status}
            else:
                cmdline = build_command_line(cmd, args)
                try:
                    write_command(cmdline)
                    resp = {"ok": True, "queued": cmdline}
                except Exception as exc:
                    resp = {"ok": False, "error": str(exc)}

            writer.write(json.dumps(resp).encode() + b"\n")
            await writer.drain()
            log.info("[%s] %s → %s", peer, cmd, resp.get("ok"))

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
        status = read_status()
        log.info("Heartbeat — bot status: %s", json.dumps(status))


# ---- Discord status pusher ---------------------------------
async def discord_status_pusher() -> None:
    """Periodically push bot status to the Discord webhook."""
    if not DISCORD_WEBHOOK_URL:
        log.info("DISCORD_WEBHOOK_URL not set — status push disabled")
        return
    log.info("Discord status pusher started (interval=%ds)", DISCORD_STATUS_INTERVAL)
    while True:
        await asyncio.sleep(DISCORD_STATUS_INTERVAL)
        status = read_status()
        await push_discord_status(status)


# ---- Main --------------------------------------------------
async def main() -> None:
    # Ensure command file exists and is writable
    COMMAND_FILE.parent.mkdir(parents=True, exist_ok=True)
    if not COMMAND_FILE.exists():
        COMMAND_FILE.write_text("", encoding="utf-8")

    server = await asyncio.start_server(handle_client, LISTEN_HOST, LISTEN_PORT)
    addrs  = ", ".join(str(s.getsockname()) for s in server.sockets)
    log.info("GromitBot Agent listening on %s", addrs)
    log.info("Command file : %s", COMMAND_FILE)
    log.info("Status  file : %s", STATUS_FILE)

    asyncio.create_task(heartbeat())
    asyncio.create_task(discord_status_pusher())

    async with server:
        await server.serve_forever()


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        log.info("Agent stopped.")
