"""
fleet.py — GromitBot Fleet Controller
======================================
Runs once on any machine with network reach to all VM agents.
Provides a single control-point for the entire bot fleet (50+ bots / many VMs).

• Reads fleet_config.json for the registry of VM agents.
• Exposes a TCP JSON server (default port 9100) for fleet-wide commands.
• Fans commands out to all targeted agents concurrently.
• Aggregates STATUS results from every agent.
• Pushes a fleet-level Discord summary embed on a configurable interval.

Fleet config (config/fleet_config.json):
  {
    "vms": [
      {"id": "vm-01", "host": "192.168.1.10", "port": 9000, "bot_count": 6},
      ...
    ],
    "fleet_listen_host":     "0.0.0.0",
    "fleet_listen_port":     9100,
    "agent_secret":          "...",   // injected into every agent command
    "fleet_secret":          "...",   // required in commands sent to fleet controller
    "discord_webhook_url":   "...",
    "discord_status_interval": 120
  }

Fleet command protocol (JSON over newline-delimited TCP):
  {"cmd": "STATUS"}                           — all bots on all VMs
  {"cmd": "STATUS",  "target": "vm:vm-01"}    — all bots on vm-01
  {"cmd": "STATUS",  "target": "bot:vm-01:2"} — bot slot 2 on vm-01
  {"cmd": "START",   "target": "all"}         — broadcast START to every bot
  {"cmd": "STOP",    "target": "all"}
  {"cmd": "MODE",    "args": "herbalism", "target": "all"}
  {"cmd": "LIST_FLEET"}                       — list all registered VMs + totals
  {"cmd": "RELOAD_CONFIG"}                    — hot-reload fleet_config.json

  Add "auth": "<fleet_secret>" when fleet_secret is configured.

Response for a broadcast command:
  {"ok": true, "results": {"vm-01": {...}, "vm-02": {...}, ...}, "target": "all"}
Response for a single-target command:
  {"ok": true, "data": {...}, "target": "vm-01:2"}

Environment variables (overrides for fleet_config.json values):
  GROMITBOT_FLEET_CONFIG   — path to fleet_config.json
  GROMITBOT_FLEET_PORT     — listen port (default 9100)
  GROMITBOT_AGENT_TIMEOUT  — per-agent TCP timeout in seconds (default 10)
  DISCORD_WEBHOOK_URL      — fallback webhook URL
  DISCORD_STATUS_INTERVAL  — fallback status push interval in seconds
  LOG_LEVEL                — logging verbosity (default INFO)
"""

import asyncio
import json
import logging
import os
import sys
import time
from pathlib import Path
from typing import Any, Optional

import aiohttp

# ---- Config -------------------------------------------------
FLEET_CONFIG_PATH = Path(os.environ.get(
    "GROMITBOT_FLEET_CONFIG",
    r"C:\GromitBot\config\fleet_config.json",
))
LOG_LEVEL         = os.environ.get("LOG_LEVEL", "INFO").upper()
AGENT_TIMEOUT     = float(os.environ.get("GROMITBOT_AGENT_TIMEOUT", "10"))

# ---- Logging ------------------------------------------------
logging.basicConfig(
    format="%(asctime)s [%(levelname)s] %(message)s",
    level=getattr(logging, LOG_LEVEL, logging.INFO),
    handlers=[
        logging.StreamHandler(sys.stdout),
        logging.FileHandler(r"C:\GromitBot\fleet.log", encoding="utf-8"),
    ],
)
log = logging.getLogger("gromitbot-fleet")

# ---- Fleet config state -------------------------------------
_fleet_cfg: dict = {}


def load_fleet_config() -> dict:
    global _fleet_cfg
    try:
        text = FLEET_CONFIG_PATH.read_text(encoding="utf-8")
        _fleet_cfg = json.loads(text)
        vm_count  = len(_fleet_cfg.get("vms", []))
        bot_total = sum(v.get("bot_count", 1) for v in _fleet_cfg.get("vms", []))
        log.info("Loaded fleet config: %d VM(s), %d bot slot(s)", vm_count, bot_total)
    except Exception as exc:
        log.error("Failed to load fleet config from %s: %s", FLEET_CONFIG_PATH, exc)
        if not _fleet_cfg:
            _fleet_cfg = {"vms": []}
    return _fleet_cfg


def get_fleet_cfg() -> dict:
    return _fleet_cfg


# ---- Target resolution --------------------------------------
def resolve_targets(target: Optional[str]) -> list[tuple[dict, Optional[int]]]:
    """
    Parse a target string and return a list of (vm_config, bot_id_or_None) tuples.
    bot_id=None means "all bots on that VM" (agent will broadcast with bot="all").

    target formats:
      None | "all"        → every VM, all bots
      "vm:vm-01"          → all bots on vm-01
      "bot:vm-01:2"       → bot slot 2 on vm-01
    """
    vms    = get_fleet_cfg().get("vms", [])
    vm_map = {v["id"]: v for v in vms}

    if not target or target == "all":
        return [(vm, None) for vm in vms]

    if target.startswith("vm:"):
        vm_id = target[3:]
        vm = vm_map.get(vm_id)
        if not vm:
            return []
        return [(vm, None)]

    if target.startswith("bot:"):
        parts = target[4:].split(":", 1)
        if len(parts) != 2:
            return []
        vm_id, slot_str = parts
        vm = vm_map.get(vm_id)
        if not vm:
            return []
        try:
            bot_id = int(slot_str)
        except ValueError:
            return []
        return [(vm, bot_id)]

    return []


# ---- Agent communication ------------------------------------
async def send_to_agent(vm: dict, payload: dict,
                         timeout: float = AGENT_TIMEOUT) -> dict:
    """Open a TCP connection to a VM agent, send one JSON command, return response."""
    host = vm["host"]
    port = int(vm["port"])

    # Inject per-agent shared secret
    agent_secret = get_fleet_cfg().get("agent_secret", "")
    if agent_secret:
        payload = {**payload, "auth": agent_secret}

    try:
        reader, writer = await asyncio.wait_for(
            asyncio.open_connection(host, port),
            timeout=timeout,
        )
        writer.write(json.dumps(payload).encode() + b"\n")
        await writer.drain()
        raw = await asyncio.wait_for(reader.readline(), timeout=timeout)
        writer.close()
        try:
            await asyncio.wait_for(writer.wait_closed(), timeout=2.0)
        except Exception:
            pass
        return json.loads(raw.decode("utf-8", errors="replace").strip())
    except asyncio.TimeoutError:
        return {"ok": False, "error": f"timeout connecting to {host}:{port}"}
    except ConnectionRefusedError:
        return {"ok": False, "error": f"connection refused at {host}:{port}"}
    except Exception as exc:
        return {"ok": False, "error": str(exc)}


async def fan_out(
    targets: list[tuple[dict, Optional[int]]],
    cmd: str,
    args: Optional[str] = None,
    extra: Optional[dict] = None,
) -> dict[str, Any]:
    """
    Send a command to all (vm, bot_id) targets concurrently via asyncio.gather.
    Returns a dict keyed by "vm_id" (all bots on that VM) or "vm_id:bot_id".
    """
    keys: list[str]     = []
    coros: list         = []

    for vm, bot_id in targets:
        payload: dict = {"cmd": cmd}
        if args is not None:
            payload["args"] = args
        payload["bot"] = bot_id if bot_id is not None else "all"
        if extra:
            payload.update(extra)

        key = vm["id"] if bot_id is None else f"{vm['id']}:{bot_id}"
        keys.append(key)
        coros.append(send_to_agent(vm, payload))

    raw_results = await asyncio.gather(*coros, return_exceptions=True)

    results: dict[str, Any] = {}
    for key, r in zip(keys, raw_results):
        if isinstance(r, Exception):
            results[key] = {"ok": False, "error": str(r)}
        else:
            results[key] = r
    return results


# ---- Valid command sets -------------------------------------
FLEET_OWN_CMDS   = {"LIST_FLEET", "RELOAD_CONFIG"}
AGENT_RELAY_CMDS = {
    "DISCONNECT", "JUMP", "SAY", "WHISPER", "STOP", "START",
    "MODE", "MAIL", "STATUS", "PRINT", "RELOAD", "EMOTE",
    "SIT", "STAND", "PROFILE", "PROFILES", "LIST", "POSITION",
}


# ---- Discord fleet summary ----------------------------------
async def push_fleet_discord_summary(
    results: dict[str, Any],
    webhook_url: str,
) -> None:
    """Post a fleet-wide summary embed to Discord (one embed for all 50+ bots)."""
    total   = 0
    running = 0
    errors  = 0

    for resp in results.values():
        if not resp.get("ok"):
            errors += 1
            continue
        data = resp.get("data", {})
        # data is either a single status dict or {bot_id: status_dict}
        if isinstance(data, dict) and "running" in data:
            total += 1
            if data.get("running"):
                running += 1
        elif isinstance(data, dict):
            for v in data.values():
                if isinstance(v, dict):
                    total += 1
                    if v.get("running"):
                        running += 1

    colour = 0x2ecc71 if errors == 0 else (0xe67e22 if running > 0 else 0xe74c3c)
    payload = {
        "embeds": [{
            "title":       "GromitBot Fleet Status",
            "description": f"<t:{int(time.time())}:T>",
            "color":       colour,
            "fields": [
                {"name": "Bots tracked",  "value": str(total),             "inline": True},
                {"name": "Running",       "value": str(running),           "inline": True},
                {"name": "Stopped",       "value": str(total - running),   "inline": True},
                {"name": "Agent errors",  "value": str(errors),            "inline": True},
                {"name": "VMs",           "value": str(len(get_fleet_cfg().get("vms", []))), "inline": True},
            ],
        }]
    }
    try:
        async with aiohttp.ClientSession() as session:
            async with session.post(
                webhook_url,
                json=payload,
                timeout=aiohttp.ClientTimeout(total=10),
            ) as resp:
                if resp.status not in (200, 204):
                    log.warning("Fleet Discord webhook: HTTP %d", resp.status)
                else:
                    log.debug("Fleet Discord summary pushed")
    except Exception as exc:
        log.warning("Fleet Discord push failed: %s", exc)


# ---- Connection handler -------------------------------------
async def handle_fleet_client(
    reader: asyncio.StreamReader,
    writer: asyncio.StreamWriter,
) -> None:
    peer = writer.get_extra_info("peername")
    log.info("Fleet connection from %s", peer)
    fleet_secret = get_fleet_cfg().get("fleet_secret", "")

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

            # Fleet-level authentication
            if fleet_secret:
                if payload.get("auth") != fleet_secret:
                    resp = {"ok": False, "error": "Unauthorized"}
                    writer.write(json.dumps(resp).encode() + b"\n")
                    await writer.drain()
                    log.warning("[%s] Fleet auth failure — closing", peer)
                    break

            cmd    = str(payload.get("cmd", "")).upper()
            args   = payload.get("args", None)
            target = payload.get("target", "all")

            # ---- Fleet-local commands -----------------------
            if cmd == "LIST_FLEET":
                cfg = get_fleet_cfg()
                vms = cfg.get("vms", [])
                resp = {
                    "ok": True,
                    "data": {
                        "vms":        vms,
                        "vm_count":   len(vms),
                        "total_bots": sum(v.get("bot_count", 1) for v in vms),
                    },
                }

            elif cmd == "RELOAD_CONFIG":
                load_fleet_config()
                resp = {"ok": True, "data": "Fleet config reloaded"}

            # ---- Commands relayed to VM agents --------------
            elif cmd in AGENT_RELAY_CMDS:
                targets = resolve_targets(target)
                if not targets:
                    resp = {"ok": False, "error": f"No matching targets for: {target!r}"}
                else:
                    results = await fan_out(targets, cmd, args)
                    all_ok  = all(v.get("ok") for v in results.values())
                    if len(results) == 1:
                        key  = next(iter(results))
                        resp = results[key]
                        resp["target"] = key
                    else:
                        resp = {"ok": all_ok, "results": results, "target": target}

            else:
                resp = {"ok": False, "error": f"Unknown fleet command: {cmd}"}

            writer.write(json.dumps(resp).encode() + b"\n")
            await writer.drain()
            log_ok = resp.get("ok")
            log.info("[%s] %s target=%s → ok=%s", peer, cmd, target, log_ok)

    except asyncio.TimeoutError:
        log.debug("Fleet client %s timed out", peer)
    except ConnectionResetError:
        log.debug("Fleet client %s disconnected", peer)
    except Exception as exc:
        log.error("Error handling fleet client %s: %s", peer, exc)
    finally:
        try:
            writer.close()
        except Exception:
            pass
        log.debug("Closed fleet connection from %s", peer)


# ---- Fleet Discord status pusher ----------------------------
async def fleet_discord_pusher() -> None:
    cfg      = get_fleet_cfg()
    webhook  = cfg.get("discord_webhook_url", os.environ.get("DISCORD_WEBHOOK_URL", ""))
    interval = int(cfg.get("discord_status_interval",
                            os.environ.get("DISCORD_STATUS_INTERVAL", "120")))
    if not webhook:
        log.info("DISCORD_WEBHOOK_URL not set — fleet status push disabled")
        return
    log.info("Fleet Discord pusher started (interval=%ds)", interval)
    while True:
        await asyncio.sleep(interval)
        cfg      = get_fleet_cfg()
        webhook  = cfg.get("discord_webhook_url", os.environ.get("DISCORD_WEBHOOK_URL", ""))
        vms      = cfg.get("vms", [])
        results  = await fan_out([(vm, None) for vm in vms], "STATUS")
        await push_fleet_discord_summary(results, webhook)


# ---- Main ---------------------------------------------------
async def main() -> None:
    cfg = load_fleet_config()

    listen_host = cfg.get("fleet_listen_host", "0.0.0.0")
    listen_port = int(cfg.get("fleet_listen_port",
                               os.environ.get("GROMITBOT_FLEET_PORT", "9100")))

    server = await asyncio.start_server(handle_fleet_client, listen_host, listen_port)
    addrs  = ", ".join(str(s.getsockname()) for s in server.sockets)

    vms       = cfg.get("vms", [])
    bot_total = sum(v.get("bot_count", 1) for v in vms)

    log.info("GromitBot Fleet Controller listening on %s", addrs)
    log.info("Registered VMs  : %d", len(vms))
    log.info("Total bot slots : %d", bot_total)
    if cfg.get("fleet_secret"):
        log.info("Fleet auth      : enabled")
    if cfg.get("agent_secret"):
        log.info("Agent auth      : enabled")

    asyncio.create_task(fleet_discord_pusher())

    async with server:
        await server.serve_forever()


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        log.info("Fleet controller stopped.")
