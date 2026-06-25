#!/usr/bin/env python3
"""atelier MCP server — stdio JSON-RPC 2.0, Python stdlib only.

Exposes the `bin/devbox` command set as MCP tools, so an AI agent
consuming atelier never has to shell out:

    mcp__atelier__run({"cmd": "pnpm test"})
    mcp__atelier__status({})
    mcp__atelier__doctor({})
    mcp__atelier__run_claude({"prompt": "...", "model": "...", "timeout": 3600})
    mcp__atelier__version({})

Each tool internally invokes `bin/devbox --json <subcmd>` and
re-emits the parsed result as the MCP tool result. There is no
state, no caching, no daemon — it's a thin typed wrapper around
`bin/devbox --json`.

Protocol: MCP over stdio, newline-delimited JSON-RPC 2.0. The
official MCP spec is the source of truth; this is a deliberately
small subset sufficient for the agent ↔ atelier contract.

Stdlib only — no `pip install mcp`, no `npm install`. The host
stays inert.
"""

from __future__ import annotations

import json
import os
import shlex
import subprocess
import sys
import time
from pathlib import Path
from typing import Any

# ---------------------------------------------------------------------------
# locate bin/devbox (sibling of this script)
# ---------------------------------------------------------------------------

HERE = Path(__file__).resolve().parent
DEVBOX = HERE / "devbox"

PROTOCOL_VERSION = "2024-11-05"
SERVER_NAME = "atelier"
SERVER_VERSION = "0.1.0"


# ---------------------------------------------------------------------------
# bin/devbox --json invocation
# ---------------------------------------------------------------------------


def devbox_json(subcmd: str, args: list[str], timeout: int = 1800) -> dict[str, Any]:
    """Run `bin/devbox --json <subcmd> <args>` and return the parsed JSON.

    Raises subprocess.TimeoutExpired on timeout. On non-zero exit
    (other than timeout), still returns the parsed JSON envelope if
    one was emitted; otherwise returns a synthetic error envelope.
    """
    if not DEVBOX.exists():
        return {
            "ok": False,
            "command": subcmd,
            "exit_code": 127,
            "duration_ms": 0,
            "error": f"bin/devbox not found at {DEVBOX}",
        }
    cmd = [str(DEVBOX), "--json", subcmd, *args]
    start = time.time()
    try:
        proc = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=timeout,
            check=False,
        )
    except subprocess.TimeoutExpired:
        return {
            "ok": False,
            "command": subcmd,
            "exit_code": 124,
            "duration_ms": int((time.time() - start) * 1000),
            "error": f"bin/devbox {subcmd} timed out after {timeout}s",
            "cmd": shlex.join(cmd),
        }
    duration_ms = int((time.time() - start) * 1000)
    stdout = proc.stdout.strip()
    if not stdout:
        return {
            "ok": False,
            "command": subcmd,
            "exit_code": proc.returncode,
            "duration_ms": duration_ms,
            "error": "bin/devbox emitted no JSON",
            "stderr": proc.stderr.strip(),
            "cmd": shlex.join(cmd),
        }
    try:
        envelope = json.loads(stdout)
    except json.JSONDecodeError as e:
        return {
            "ok": False,
            "command": subcmd,
            "exit_code": proc.returncode,
            "duration_ms": duration_ms,
            "error": f"bin/devbox --json output is not valid JSON: {e}",
            "raw_stdout": stdout[:2000],
            "stderr": proc.stderr.strip(),
            "cmd": shlex.join(cmd),
        }
    return envelope


# ---------------------------------------------------------------------------
# tool implementations
# ---------------------------------------------------------------------------


def tool_run(args: dict[str, Any]) -> dict[str, Any]:
    """Run a single command inside the atelier VM.

    Required: cmd (str).
    Optional: timeout (int, seconds, default 1800).
    """
    if not isinstance(args.get("cmd"), str) or not args["cmd"].strip():
        return _tool_error("'cmd' is required and must be a non-empty string")
    cmd_str = args["cmd"]
    timeout = int(args.get("timeout", 1800))
    # shell-split so callers can pass either "pnpm test" or ["pnpm", "test"]
    argv = shlex.split(cmd_str)
    return devbox_json("run", argv, timeout=timeout)


def tool_status(_args: dict[str, Any]) -> dict[str, Any]:
    """Return structured VM state."""
    return devbox_json("status", [])


def tool_doctor(_args: dict[str, Any]) -> dict[str, Any]:
    """Run the four health checks (orbstack / vm / mount / passthrough)."""
    return devbox_json("doctor", [])


def tool_run_claude(args: dict[str, Any]) -> dict[str, Any]:
    """Spawn a fresh `claude -p "<prompt>"` subprocess inside the VM.

    Required: prompt (str).
    Optional: model (str), timeout (int, seconds, default 3600).

    Returns the raw envelope (stdout / stderr / exit_code). The caller
    is expected to interpret the output (e.g. parse a score-card JSON
    written to disk by the generator).
    """
    if not isinstance(args.get("prompt"), str) or not args["prompt"].strip():
        return _tool_error("'prompt' is required and must be a non-empty string")
    prompt = args["prompt"]
    argv = ["-p", prompt]
    if isinstance(args.get("model"), str) and args["model"]:
        argv += ["--model", args["model"]]
    return devbox_json("claude", argv, timeout=int(args.get("timeout", 3600)))


def tool_version(_args: dict[str, Any]) -> dict[str, Any]:
    """Return atelier MCP server version + underlying bin/devbox state."""
    return {
        "ok": True,
        "server": {"name": SERVER_NAME, "version": SERVER_VERSION},
        "protocol_version": PROTOCOL_VERSION,
        "devbox_path": str(DEVBOX),
        "devbox_exists": DEVBOX.exists(),
        "python": sys.version.split()[0],
        "pid": os.getpid(),
    }


def _tool_error(msg: str) -> dict[str, Any]:
    return {"ok": False, "exit_code": 2, "duration_ms": 0, "error": msg}


# ---------------------------------------------------------------------------
# tool catalog (exposed via tools/list)
# ---------------------------------------------------------------------------


TOOLS: list[dict[str, Any]] = [
    {
        "name": "devbox_run",
        "description": (
            "Run a command inside the atelier VM. Returns the parsed "
            "JSON envelope (ok, exit_code, duration_ms, stdout, stderr). "
            "Use this for any toolchain work — pnpm test, cargo build, "
            "pytest, playwright, curl, etc. The host's toolchain is "
            "empty; everything goes through here."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "cmd": {
                    "type": "string",
                    "description": (
                        "Shell-style command string, e.g. 'pnpm test' "
                        "or 'go test ./...'."
                    ),
                },
                "timeout": {
                    "type": "integer",
                    "minimum": 1,
                    "description": "Timeout in seconds (default 1800).",
                },
            },
            "required": ["cmd"],
            "additionalProperties": False,
        },
    },
    {
        "name": "devbox_status",
        "description": (
            "Return structured VM state (exists, running, name, distro, "
            "arch, raw orbctl info). Use as a pre-flight check."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {},
            "additionalProperties": False,
        },
    },
    {
        "name": "devbox_doctor",
        "description": (
            "Run the four health checks (orbstack / vm / shared mount / "
            "host env passthrough). Returns ok=false if any check fails."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {},
            "additionalProperties": False,
        },
    },
    {
        "name": "devbox_run_claude",
        "description": (
            "Spawn a fresh `claude -p <prompt>` subprocess inside the VM. "
            "Returns the raw envelope. The generator or evaluator writes "
            "its score-card / output to disk; the caller parses it."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "prompt": {
                    "type": "string",
                    "description": "Self-contained prompt for the subprocess.",
                },
                "model": {
                    "type": "string",
                    "description": "Optional model override.",
                },
                "timeout": {
                    "type": "integer",
                    "minimum": 1,
                    "description": "Timeout in seconds (default 3600).",
                },
            },
            "required": ["prompt"],
            "additionalProperties": False,
        },
    },
    {
        "name": "devbox_version",
        "description": (
            "Return the MCP server version + bin/devbox path + python "
            "version. Cheap; use for health pings."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {},
            "additionalProperties": False,
        },
    },
]


TOOL_DISPATCH = {
    "devbox_run": tool_run,
    "devbox_status": tool_status,
    "devbox_doctor": tool_doctor,
    "devbox_run_claude": tool_run_claude,
    "devbox_version": tool_version,
}


# ---------------------------------------------------------------------------
# JSON-RPC plumbing (MCP over stdio, line-delimited)
# ---------------------------------------------------------------------------


def _send(msg: dict[str, Any]) -> None:
    sys.stdout.write(json.dumps(msg) + "\n")
    sys.stdout.flush()


def _send_result(req_id: Any, result: Any) -> None:
    _send({"jsonrpc": "2.0", "id": req_id, "result": result})


def _send_error(req_id: Any, code: int, message: str, data: Any = None) -> None:
    err: dict[str, Any] = {"code": code, "message": message}
    if data is not None:
        err["data"] = data
    _send({"jsonrpc": "2.0", "id": req_id, "error": err})


def _tool_call_result(envelope: dict[str, Any]) -> dict[str, Any]:
    """Wrap an envelope as an MCP tool-call result.

    MCP tool results are normally {content: [{type, text}], isError}.
    We embed the full envelope as JSON text so the caller sees both
    the typed fields and the raw shape.
    """
    is_error = not envelope.get("ok", False)
    text = json.dumps(envelope, indent=2, ensure_ascii=False)
    return {
        "content": [{"type": "text", "text": text}],
        "isError": is_error,
    }


def handle_initialize(req_id: Any, _params: dict[str, Any]) -> None:
    _send_result(
        req_id,
        {
            "protocolVersion": PROTOCOL_VERSION,
            "serverInfo": {"name": SERVER_NAME, "version": SERVER_VERSION},
            "capabilities": {"tools": {"listChanged": False}},
        },
    )


def handle_tools_list(req_id: Any, _params: dict[str, Any]) -> None:
    _send_result(req_id, {"tools": TOOLS})


def handle_tools_call(req_id: Any, params: dict[str, Any]) -> None:
    name = params.get("name")
    args = params.get("arguments") or {}
    if not isinstance(name, str):
        _send_error(req_id, -32602, "'name' is required")
        return
    fn = TOOL_DISPATCH.get(name)
    if fn is None:
        _send_error(req_id, -32602, f"unknown tool: {name}")
        return
    try:
        envelope = fn(args)
    except Exception as e:  # noqa: BLE001 — surface any tool error to the agent
        _send_error(req_id, -32603, f"tool '{name}' failed: {e}")
        return
    _send_result(req_id, _tool_call_result(envelope))


def handle_ping(req_id: Any, _params: dict[str, Any]) -> None:
    _send_result(req_id, {})


HANDLERS = {
    "initialize": handle_initialize,
    "ping": handle_ping,
    "tools/list": handle_tools_list,
    "tools/call": handle_tools_call,
}


def serve() -> None:
    """Main loop: read JSON-RPC requests from stdin, write responses to stdout."""
    for raw in sys.stdin:
        line = raw.strip()
        if not line:
            continue
        try:
            msg = json.loads(line)
        except json.JSONDecodeError as e:
            _send_error(None, -32700, f"parse error: {e}")
            continue
        method = msg.get("method")
        req_id = msg.get("id")
        params = msg.get("params") or {}
        if method == "notifications/initialized":
            # client → server only; no response
            continue
        if not isinstance(method, str):
            _send_error(req_id, -32600, "missing 'method'")
            continue
        handler = HANDLERS.get(method)
        if handler is None:
            _send_error(req_id, -32601, f"method not found: {method}")
            continue
        try:
            handler(req_id, params)
        except Exception as e:  # noqa: BLE001
            _send_error(req_id, -32603, f"handler '{method}' crashed: {e}")


def main() -> int:
    # When invoked as a CLI (not stdio), print help and exit.
    if len(sys.argv) > 1 and sys.argv[1] in ("--help", "-h"):
        print(
            "atelier MCP server (stdio JSON-RPC 2.0).\n"
            "\n"
            "Wire it via .mcp.json:\n"
            "  {\n"
            '    "mcpServers": {\n'
            '      "atelier": {\n'
            '        "type": "stdio",\n'
            '        "command": "python3",\n'
            f'        "args": ["{DEVBOX.with_name("mcp-atelier.py")}"]\n'
            "      }\n"
            "    }\n"
            "  }\n"
            "\n"
            "Tools exposed: devbox_run, devbox_status, devbox_doctor,\n"
            "               devbox_run_claude, devbox_version.\n"
        )
        return 0
    if len(sys.argv) > 1 and sys.argv[1] == "--selftest":
        # Internal smoke test (used by CI). Prints one JSON line and exits.
        print(json.dumps(tool_version({}), ensure_ascii=False))
        return 0
    serve()
    return 0


if __name__ == "__main__":
    sys.exit(main())