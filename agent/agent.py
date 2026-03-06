"""
agent.py — GromitBot VM Agent
==============================
Runs on each Windows VM that runs a WoW instance.

• Listens on TCP port (default 9000) for JSON commands from the
  FastAPI management server.
• Writes received commands to a local file (command.txt) which
  the Lua addon polls every second.
• Reads a status JSON file written by the Lua addon and serves
  it back to the management server on request.

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
"""

import asyncio
import json
import logging
import os
import sys
import time
from pathlib import Path
from typing import Optional

# ---- Config -------------------------------------------------
LISTEN_HOST      = "0.0.0.0"
LISTEN_PORT      = 9000
COMMAND_FILE     = Path(os.environ.get("GROMITBOT_CMD_FILE",   r"C:\GromitBot\command.txt"))
STATUS_FILE      = Path(os.environ.get("GROMITBOT_STATUS_FILE", r"C:\GromitBot\command_status.json"))
LOG_LEVEL        = os.environ.get("LOG_LEVEL", "INFO").upper()
HEARTBEAT_SECS   = 30   # seconds between keep-alive logs

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

    async with server:
        await server.serve_forever()


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        log.info("Agent stopped.")
