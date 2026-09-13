#!/usr/bin/env python3
"""Read-only MCP readiness diagnostic; emits types/counts, never application content."""
import json
import os
import re
import selectors
import subprocess
import time

home = os.path.expanduser("~")
executable = os.path.join(home, ".codex/computer-use/Codex Computer Use.app/Contents/SharedSupport/SkyComputerUseClient.app/Contents/MacOS/SkyComputerUseClient")
known_keys = {"apps", "applications", "data", "result", "content", "structuredContent", "isError", "error", "message", "text", "type", "protocolVersion", "capabilities", "serverInfo", "tools"}

def describe(value):
    if isinstance(value, dict):
        info = {"kind": "object", "knownKeys": sorted(set(value) & known_keys), "otherKeyCount": len(set(value) - known_keys)}
        info["arrayFields"] = {key: len(item) for key, item in value.items() if key in known_keys and isinstance(item, list)}
        return info
    if isinstance(value, list):
        return {"kind": "array", "count": len(value), "entryKinds": sorted(set(type(item).__name__ for item in value))}
    return {"kind": type(value).__name__}

if not os.access(executable, os.X_OK):
    print(json.dumps({"phase": "launch", "error": "helper_missing"}))
    raise SystemExit(1)

process = subprocess.Popen([executable, "mcp"], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                           env={"HOME": home, "CODEX_HOME": os.path.join(home, ".codex"), "PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "LANG": "en_US.UTF-8"})
selector = selectors.DefaultSelector()
selector.register(process.stdout, selectors.EVENT_READ)
buffer = bytearray()

def send(message):
    process.stdin.write((json.dumps(message) + "\n").encode())
    process.stdin.flush()

def response(identifier, timeout):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        while b"\n" in buffer:
            frame, _, tail = buffer.partition(b"\n")
            buffer[:] = tail
            if not frame:
                continue
            try:
                message = json.loads(frame)
            except (ValueError, UnicodeDecodeError):
                print(json.dumps({"phase": "wire", "error": "invalid_json", "bytes": len(frame)}))
                return None
            if message.get("id") == identifier and "method" not in message:
                return message
            if "method" in message:
                print(json.dumps({"phase": "callback", "request": "id" in message, "knownMethod": message.get("method") if message.get("method") in {"ping", "roots/list", "sampling/createMessage", "elicitation/create", "notifications/progress", "notifications/message"} else "other"}))
                if "id" in message:
                    send({"jsonrpc": "2.0", "id": message["id"], "error": {"code": -32601, "message": "Unavailable in this read-only diagnostic."}})
        if not selector.select(max(0, deadline - time.monotonic())):
            break
        chunk = os.read(process.stdout.fileno(), 65536)
        if not chunk:
            print(json.dumps({"phase": "wire", "error": "connection_closed"}))
            return None
        buffer.extend(chunk)
        if len(buffer) > 8 * 1024 * 1024:
            print(json.dumps({"phase": "wire", "error": "frame_limit"}))
            return None
    return None

def request(identifier, phase, method, params, timeout):
    start = time.monotonic()
    send({"jsonrpc": "2.0", "id": identifier, "method": method, "params": params})
    message = response(identifier, timeout)
    report = {"phase": phase, "elapsedSeconds": round(time.monotonic() - start, 3), "responded": message is not None}
    if message is not None:
        report["rpcErrorCode"] = message.get("error", {}).get("code")
        result = message.get("result", {})
        report["result"] = describe(result)
        if phase == "readiness":
            report["isError"] = result.get("isError")
            report["content"] = []
            for item in result.get("content", []):
                summary = {"type": item.get("type") if item.get("type") in {"text", "image", "resource", "resource_link"} else "other"}
                if isinstance(item.get("text"), str):
                    summary["textBytes"] = len(item["text"].encode())
                    try:
                        summary["textJSON"] = describe(json.loads(item["text"]))
                    except ValueError:
                        summary["textJSON"] = {"kind": "not_json"}
                    if result.get("isError") is True:
                        error_text = item["text"][:1200].replace(home, "[user-home]")
                        error_text = re.sub(r"(?i)\b(?:bearer\s+\S+|sk-[A-Za-z0-9_-]+)", "[redacted]", error_text)
                        error_text = re.sub(r"(?i)\b(token|password|secret|api[_ -]?key)\s*[:=]\s*\S+", r"\1=[redacted]", error_text)
                        summary["sanitizedError"] = error_text
                report["content"].append(summary)
            if "structuredContent" in result:
                report["structuredContent"] = describe(result["structuredContent"])
    print(json.dumps(report), flush=True)
    return message

try:
    initialized = request(1, "initialize", "initialize", {"protocolVersion": "2024-11-05", "capabilities": {}, "clientInfo": {"name": "Computah", "version": "1.0"}}, 5)
    if initialized is not None and "result" in initialized:
        send({"jsonrpc": "2.0", "method": "notifications/initialized", "params": {}})
        inventory = request(2, "inventory", "tools/list", {}, 5)
        if inventory is not None and "result" in inventory:
            request(3, "readiness", "tools/call", {"name": "list_apps", "arguments": {}}, 30)
finally:
    process.terminate()
    try:
        process.wait(timeout=2)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait()
