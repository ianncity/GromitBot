"""
models.py — Pydantic data models for GromitBot management server
"""
from __future__ import annotations
from enum import Enum
from typing import Any, Optional
from pydantic import BaseModel, Field


class BotMode(str, Enum):
    fishing   = "fishing"
    herbalism = "herbalism"
    leveling  = "leveling"


class AgentConfig(BaseModel):
    vm_id:   str = Field(..., description="Unique VM / bot identifier")
    host:    str = Field(..., description="Agent TCP host (IP or hostname)")
    port:    int = Field(9000, ge=1, le=65535, description="Agent TCP port")
    enabled: bool = True


class CommandRequest(BaseModel):
    cmd:  str           = Field(..., description="Command name (e.g. JUMP, SAY, STOP)")
    args: Optional[str] = Field(None,  description="Optional command arguments")


class BroadcastRequest(BaseModel):
    cmd:  str
    args: Optional[str] = None


class SetModeRequest(BaseModel):
    mode: BotMode


class SayRequest(BaseModel):
    text: str


class WhisperRequest(BaseModel):
    target:  str
    message: str


class AgentStatus(BaseModel):
    vm_id:    str
    online:   bool
    data:     Optional[dict[str, Any]] = None
    error:    Optional[str]            = None
