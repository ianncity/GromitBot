"""
main.py — GromitBot FastAPI Management Server
===============================================
Central control plane for all bot VMs.

Endpoints:
  GET  /agents                     — list registered agents
  POST /agents                     — register a new agent
  DELETE /agents/{vm_id}           — remove an agent
  POST /agents/{vm_id}/command     — send arbitrary command to one agent
  POST /agents/{vm_id}/start       — start bot
  POST /agents/{vm_id}/stop        — stop bot
  POST /agents/{vm_id}/mode        — set bot mode
  POST /agents/{vm_id}/say         — /say text
  POST /agents/{vm_id}/whisper     — whisper to player
  POST /agents/{vm_id}/jump        — player jumps
  POST /agents/{vm_id}/disconnect  — leave game
  POST /agents/{vm_id}/mail        — trigger auto-mail
  GET  /agents/{vm_id}/status      — get bot status JSON
  POST /broadcast                  — send command to ALL agents
  GET  /status                     — overall status of all bots

Run:
  uvicorn main:app --host 0.0.0.0 --port 8000 --reload
"""

from __future__ import annotations

import asyncio
import json
import logging
import time
from contextlib import asynccontextmanager
from typing import Any, Optional

import httpx
from fastapi import FastAPI, HTTPException, Path, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from models import (
    AgentConfig, AgentStatus, BotMode,
    BroadcastRequest, CommandRequest, SetModeRequest,
    SayRequest, WhisperRequest,
)

# ---- Logging -----------------------------------------------
logging.basicConfig(
    format="%(asctime)s [%(levelname)s] %(name)s — %(message)s",
    level=logging.INFO,
)
log = logging.getLogger("gromitbot-server")

# ---- In-memory agent registry ------------------------------
# Production: swap for Redis / DB persistence.
AGENTS: dict[str, AgentConfig] = {}

# ---- TCP agent communication timeout ----------------------
AGENT_TIMEOUT = 10.0   # seconds


# ============================================================
# Agent TCP communication
# ============================================================
async def send_command(agent: AgentConfig,
                        payload: dict[str, Any],
                        timeout: float = AGENT_TIMEOUT) -> dict[str, Any]:
    """Open a TCP connection to the VM agent, send one JSON command, get reply."""
    try:
        reader, writer = await asyncio.wait_for(
            asyncio.open_connection(agent.host, agent.port),
            timeout=timeout,
        )
        data = json.dumps(payload).encode() + b"\n"
        writer.write(data)
        await writer.drain()

        line = await asyncio.wait_for(reader.readline(), timeout=timeout)
        writer.close()
        try:
            await asyncio.wait_for(writer.wait_closed(), timeout=2.0)
        except Exception:
            pass

        return json.loads(line.decode("utf-8", errors="replace").strip())

    except asyncio.TimeoutError:
        raise HTTPException(
            status_code=status.HTTP_504_GATEWAY_TIMEOUT,
            detail=f"Agent {agent.vm_id} ({agent.host}:{agent.port}) timed out",
        )
    except ConnectionRefusedError:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=f"Agent {agent.vm_id} is offline (connection refused)",
        )
    except Exception as exc:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Agent communication error: {exc}",
        )


def get_agent(vm_id: str) -> AgentConfig:
    if vm_id not in AGENTS:
        raise HTTPException(status_code=404, detail=f"Agent '{vm_id}' not registered")
    return AGENTS[vm_id]


# ============================================================
# Lifespan
# ============================================================
@asynccontextmanager
async def lifespan(app: FastAPI):
    log.info("GromitBot Management Server starting up")
    yield
    log.info("GromitBot Management Server shutting down")


# ============================================================
# App
# ============================================================
app = FastAPI(
    title="GromitBot Management Server",
    description="Central control plane for GromitBot WoW bots",
    version="1.0.0",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


# ============================================================
# Agent Registry
# ============================================================
@app.get("/agents", summary="List all registered agents")
async def list_agents() -> list[AgentConfig]:
    return list(AGENTS.values())


@app.post("/agents", status_code=status.HTTP_201_CREATED,
          summary="Register a new VM agent")
async def register_agent(cfg: AgentConfig) -> AgentConfig:
    AGENTS[cfg.vm_id] = cfg
    log.info("Registered agent: %s @ %s:%d", cfg.vm_id, cfg.host, cfg.port)
    return cfg


@app.delete("/agents/{vm_id}", summary="Remove an agent")
async def remove_agent(vm_id: str = Path(...)) -> dict:
    agent = get_agent(vm_id)
    del AGENTS[vm_id]
    log.info("Removed agent: %s", vm_id)
    return {"ok": True, "removed": vm_id}


# ============================================================
# Commands
# ============================================================
@app.post("/agents/{vm_id}/command", summary="Send arbitrary command")
async def raw_command(
    body: CommandRequest,
    vm_id: str = Path(...),
) -> dict:
    agent  = get_agent(vm_id)
    result = await send_command(agent, {"cmd": body.cmd, "args": body.args})
    return result


@app.post("/agents/{vm_id}/start", summary="Start the bot")
async def start_bot(vm_id: str = Path(...)) -> dict:
    agent = get_agent(vm_id)
    return await send_command(agent, {"cmd": "START"})


@app.post("/agents/{vm_id}/stop", summary="Stop the bot")
async def stop_bot(vm_id: str = Path(...)) -> dict:
    agent = get_agent(vm_id)
    return await send_command(agent, {"cmd": "STOP"})


@app.post("/agents/{vm_id}/mode", summary="Set bot mode (fishing|herbalism)")
async def set_mode(
    body: SetModeRequest,
    vm_id: str = Path(...),
) -> dict:
    agent = get_agent(vm_id)
    return await send_command(agent, {"cmd": "MODE", "args": body.mode.value})


@app.post("/agents/{vm_id}/say", summary="Send /say message")
async def say_message(
    body: SayRequest,
    vm_id: str = Path(...),
) -> dict:
    agent = get_agent(vm_id)
    return await send_command(agent, {"cmd": "SAY", "args": body.text})


@app.post("/agents/{vm_id}/whisper", summary="Whisper to a player")
async def whisper(
    body: WhisperRequest,
    vm_id: str = Path(...),
) -> dict:
    agent = get_agent(vm_id)
    return await send_command(agent, {
        "cmd":  "WHISPER",
        "args": f"{body.target} {body.message}",
    })


@app.post("/agents/{vm_id}/jump", summary="Make player jump")
async def jump(vm_id: str = Path(...)) -> dict:
    agent = get_agent(vm_id)
    return await send_command(agent, {"cmd": "JUMP"})


@app.post("/agents/{vm_id}/disconnect", summary="Disconnect from game (/quit)")
async def disconnect(vm_id: str = Path(...)) -> dict:
    agent = get_agent(vm_id)
    return await send_command(agent, {"cmd": "DISCONNECT"})


@app.post("/agents/{vm_id}/mail", summary="Trigger auto-mail of inventory")
async def trigger_mail(vm_id: str = Path(...)) -> dict:
    agent = get_agent(vm_id)
    return await send_command(agent, {"cmd": "MAIL"})


@app.post("/agents/{vm_id}/sit", summary="Make player sit")
async def sit(vm_id: str = Path(...)) -> dict:
    return await send_command(get_agent(vm_id), {"cmd": "SIT"})


@app.post("/agents/{vm_id}/stand", summary="Make player stand")
async def stand(vm_id: str = Path(...)) -> dict:
    return await send_command(get_agent(vm_id), {"cmd": "STAND"})


@app.post("/agents/{vm_id}/reload", summary="ReloadUI")
async def reload_ui(vm_id: str = Path(...)) -> dict:
    return await send_command(get_agent(vm_id), {"cmd": "RELOAD"})


# ============================================================
# Status
# ============================================================
@app.get("/agents/{vm_id}/status", summary="Get bot status from agent")
async def agent_status(vm_id: str = Path(...)) -> dict:
    agent  = get_agent(vm_id)
    result = await send_command(agent, {"cmd": "STATUS"})
    return result


@app.get("/status", summary="Poll all agents for status")
async def all_status() -> list[AgentStatus]:
    """Concurrently poll every registered agent."""
    async def poll_one(agent: AgentConfig) -> AgentStatus:
        try:
            result = await send_command(agent, {"cmd": "STATUS"}, timeout=5.0)
            return AgentStatus(
                vm_id=agent.vm_id,
                online=True,
                data=result.get("data"),
            )
        except HTTPException as exc:
            return AgentStatus(
                vm_id=agent.vm_id,
                online=False,
                error=exc.detail,
            )

    results = await asyncio.gather(*(poll_one(a) for a in AGENTS.values()))
    return list(results)


# ============================================================
# Broadcast
# ============================================================
@app.post("/broadcast", summary="Send a command to ALL registered agents")
async def broadcast(body: BroadcastRequest) -> list[dict]:
    """Fire-and-forget broadcast; returns per-agent results."""
    async def send_one(agent: AgentConfig) -> dict:
        try:
            r = await send_command(agent, {"cmd": body.cmd, "args": body.args})
            return {"vm_id": agent.vm_id, "result": r}
        except HTTPException as exc:
            return {"vm_id": agent.vm_id, "error": exc.detail}

    results = await asyncio.gather(*(send_one(a) for a in AGENTS.values()))
    return list(results)


# ============================================================
# Health
# ============================================================
@app.get("/health", include_in_schema=False)
async def health() -> dict:
    return {"status": "ok", "agents": len(AGENTS), "time": time.time()}
