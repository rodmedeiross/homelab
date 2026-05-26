"""
title: Honcho Memory
author: rodmedeiross
author_url: https://github.com/rodmedeiross
funding_url: https://honcho.dev
version: 0.1.0
license: MIT
description: |
  Injects honcho memory into chat prompts (inlet) and persists conversations
  back to honcho (outlet). Peers = OWUI users; sessions = OWUI chats;
  workspace = open_webui. Failures are logged and silently bypassed — chat
  never breaks because honcho is down.
requirements: httpx
"""

from __future__ import annotations

import logging
import re
from typing import Any, Awaitable, Callable, Optional

import httpx
from pydantic import BaseModel, Field

logger = logging.getLogger("honcho_memory_filter")


def _slug(value: str, fallback: str = "anonymous") -> str:
    """Honcho peer/session IDs accept letters, digits, underscore and hyphen.
    OWUI emails / chat IDs may contain '@', '.', spaces — sanitize."""
    if not value:
        return fallback
    cleaned = re.sub(r"[^A-Za-z0-9_-]", "-", value).strip("-")
    return cleaned or fallback


class Filter:
    class Valves(BaseModel):
        # ---- Connection ----
        HONCHO_BASE_URL: str = Field(
            default="https://honcho.outerheaven.network/v3",
            description="Honcho API base URL including /v3 prefix",
        )
        HONCHO_API_KEY: str = Field(
            default="",
            description="Honcho admin JWT (Bearer token)",
        )
        WORKSPACE: str = Field(
            default="open_webui",
            description="Honcho workspace name — keep separate per integration",
        )
        REQUEST_TIMEOUT_S: float = Field(
            default=8.0,
            description="HTTP timeout per honcho call (seconds)",
        )

        # ---- Inlet (memory retrieval) ----
        ENABLE_INLET: bool = Field(
            default=True,
            description="If true, query honcho for context before sending to LLM",
        )
        INLET_REASONING_LEVEL: str = Field(
            default="low",
            description="Honcho dialectic reasoning_level: minimal|low|medium|high|max",
        )
        INLET_MAX_CONTEXT_CHARS: int = Field(
            default=4000,
            description="Truncate honcho context if it exceeds this many chars",
        )
        INLET_SYSTEM_HEADER: str = Field(
            default="## Context from Honcho memory about this user",
            description="Header prepended to the honcho context system message",
        )

        # ---- Outlet (message persistence) ----
        ENABLE_OUTLET: bool = Field(
            default=True,
            description="If true, persist user+assistant messages to honcho",
        )
        ASSISTANT_PEER_PREFIX: str = Field(
            default="owui-",
            description="Prefix added to assistant peer name to distinguish models",
        )

    def __init__(self) -> None:
        self.valves = self.Valves()

    # -------------------------------------------------------------------------
    # Helpers
    # -------------------------------------------------------------------------

    def _headers(self) -> dict[str, str]:
        return {
            "Authorization": f"Bearer {self.valves.HONCHO_API_KEY}",
            "Content-Type": "application/json",
        }

    def _peer_for_user(self, user: Optional[dict]) -> str:
        if not user:
            return "anonymous"
        # Prefer stable email; fallback to id; finally name
        raw = user.get("email") or user.get("id") or user.get("name") or "anonymous"
        return _slug(str(raw))

    def _peer_for_assistant(self, model: Optional[str]) -> str:
        base = _slug(model or "unknown")
        return f"{self.valves.ASSISTANT_PEER_PREFIX}{base}"

    def _session_id(self, body: dict, metadata: Optional[dict]) -> str:
        # OWUI puts chat_id in different places depending on flow
        raw = (
            body.get("chat_id")
            or (metadata or {}).get("chat_id")
            or body.get("session_id")
            or "default"
        )
        return _slug(str(raw))

    # -------------------------------------------------------------------------
    # Inlet — query honcho memory, inject as system message
    # -------------------------------------------------------------------------

    async def inlet(
        self,
        body: dict,
        __user__: Optional[dict] = None,
        __metadata__: Optional[dict] = None,
        __event_emitter__: Optional[Callable[[dict], Awaitable[None]]] = None,
    ) -> dict:
        if not self.valves.ENABLE_INLET or not self.valves.HONCHO_API_KEY:
            return body

        messages = body.get("messages") or []
        last_user_msg = next(
            (m["content"] for m in reversed(messages) if m.get("role") == "user"),
            None,
        )
        if not last_user_msg:
            return body

        peer_id = self._peer_for_user(__user__)
        session_id = self._session_id(body, __metadata__)

        url = (
            f"{self.valves.HONCHO_BASE_URL}"
            f"/workspaces/{self.valves.WORKSPACE}"
            f"/peers/{peer_id}/chat"
        )
        payload = {
            "query": last_user_msg[:10000],  # honcho limits query to 10k chars
            "session_id": session_id,
            "stream": False,
            "reasoning_level": self.valves.INLET_REASONING_LEVEL,
        }

        try:
            async with httpx.AsyncClient(timeout=self.valves.REQUEST_TIMEOUT_S) as client:
                resp = await client.post(url, json=payload, headers=self._headers())
                resp.raise_for_status()
                data = resp.json()
        except Exception as e:
            logger.warning("Honcho inlet failed (peer=%s, session=%s): %s", peer_id, session_id, e)
            return body

        content = (data or {}).get("content")
        if not content:
            return body

        # Truncate if too long
        if len(content) > self.valves.INLET_MAX_CONTEXT_CHARS:
            content = content[: self.valves.INLET_MAX_CONTEXT_CHARS] + "\n…[truncated]"

        system_msg = {
            "role": "system",
            "content": f"{self.valves.INLET_SYSTEM_HEADER}\n\n{content}",
        }

        # Insert AFTER any existing system messages so user-defined instructions stay primary
        insert_idx = 0
        for i, m in enumerate(messages):
            if m.get("role") == "system":
                insert_idx = i + 1
            else:
                break
        body["messages"] = messages[:insert_idx] + [system_msg] + messages[insert_idx:]

        return body

    # -------------------------------------------------------------------------
    # Outlet — persist last user + assistant turn to honcho
    # -------------------------------------------------------------------------

    async def outlet(
        self,
        body: dict,
        __user__: Optional[dict] = None,
        __metadata__: Optional[dict] = None,
        __event_emitter__: Optional[Callable[[dict], Awaitable[None]]] = None,
    ) -> dict:
        if not self.valves.ENABLE_OUTLET or not self.valves.HONCHO_API_KEY:
            return body

        messages = body.get("messages") or []
        if len(messages) < 2:
            return body

        # Take the last user message and the last assistant message
        last_assistant = next(
            (m for m in reversed(messages) if m.get("role") == "assistant"),
            None,
        )
        last_user = next(
            (m for m in reversed(messages) if m.get("role") == "user"),
            None,
        )
        if not last_assistant or not last_user:
            return body

        user_peer = self._peer_for_user(__user__)
        assistant_peer = self._peer_for_assistant(body.get("model"))
        session_id = self._session_id(body, __metadata__)

        url = (
            f"{self.valves.HONCHO_BASE_URL}"
            f"/workspaces/{self.valves.WORKSPACE}"
            f"/sessions/{session_id}/messages"
        )
        payload: dict[str, Any] = {
            "messages": [
                {"peer_id": user_peer, "content": last_user.get("content", "")},
                {"peer_id": assistant_peer, "content": last_assistant.get("content", "")},
            ]
        }

        try:
            async with httpx.AsyncClient(timeout=self.valves.REQUEST_TIMEOUT_S) as client:
                resp = await client.post(url, json=payload, headers=self._headers())
                resp.raise_for_status()
        except Exception as e:
            logger.warning(
                "Honcho outlet failed (session=%s, user=%s, asst=%s): %s",
                session_id, user_peer, assistant_peer, e,
            )

        return body
