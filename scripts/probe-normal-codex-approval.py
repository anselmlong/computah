#!/usr/bin/env python3
"""Read-only app-server probe. Run only when live Computer Use testing is authorized."""

import json
import os
import selectors
import subprocess
import time
import argparse


parser = argparse.ArgumentParser()
parser.add_argument("--accept", action="store_true", help="Allow one empty-schema native Computer Use approval")
options = parser.parse_args()


def send(process, message):
    process.stdin.write(json.dumps(message, separators=(",", ":")) + "\n")
    process.stdin.flush()


environment = {
    key: value for key, value in os.environ.items()
    if not (key.startswith("CODEX_") and key != "CODEX_HOME") and key != "OPENAI_API_KEY"
}
process = subprocess.Popen(
    ["/opt/homebrew/bin/codex", "app-server", "--listen", "stdio://"],
    stdin=subprocess.PIPE,
    stdout=subprocess.PIPE,
    stderr=subprocess.DEVNULL,
    text=True,
    bufsize=1,
    cwd=os.path.expanduser("~"),
    env=environment,
)
selector = selectors.DefaultSelector()
selector.register(process.stdout, selectors.EVENT_READ)
next_id = 1
responses = {}
turn_completed = False


def request(method, params):
    global next_id
    request_id = next_id
    next_id += 1
    send(process, {"id": request_id, "method": method, "params": params})
    while request_id not in responses:
        receive_one()
    return responses.pop(request_id)


def receive_one(timeout=60):
    global turn_completed
    events = selector.select(timeout)
    if not events:
        raise TimeoutError("Codex app-server did not respond in time")
    message = json.loads(process.stdout.readline())
    if "id" in message and "method" not in message:
        responses[message["id"]] = message
        return
    method = message.get("method", "")
    params = message.get("params", {})
    if "id" in message:
        print("SERVER_REQUEST", method, sorted(params.keys()), flush=True)
        if method in {"item/commandExecution/requestApproval", "item/fileChange/requestApproval"}:
            send(process, {"id": message["id"], "result": {"decision": "decline"}})
        elif method in {"execCommandApproval", "applyPatchApproval"}:
            send(process, {"id": message["id"], "result": {"decision": "abort"}})
        elif method == "item/permissions/requestApproval":
            send(process, {"id": message["id"], "result": {"permissions": {}, "scope": "turn"}})
        elif method == "item/tool/requestUserInput":
            send(process, {"id": message["id"], "result": {"answers": {}}})
        elif method == "mcpServer/elicitation/request":
            schema = params.get("requestedSchema", {})
            print("ELICITATION_MESSAGE", params.get("message", "")[:500], flush=True)
            print("ELICITATION_MODE", params.get("mode"), flush=True)
            print("ELICITATION_SCHEMA_KEYS", sorted(schema.keys()), flush=True)
            properties = schema.get("properties", {})
            print("ELICITATION_PROPERTIES", sorted(properties.keys()), flush=True)
            for name, value in sorted(properties.items()):
                summary = {key: value[key] for key in ("type", "enum", "default", "title") if key in value}
                print("ELICITATION_PROPERTY", name, json.dumps(summary, separators=(",", ":")), flush=True)
            metadata = params.get("_meta", {})
            safe_native_approval = (
                params.get("mode") == "form"
                and metadata.get("codex_approval_kind") == "mcp_tool_call"
                and not schema.get("required", [])
            )
            if options.accept and safe_native_approval:
                print("ELICITATION_RESPONSE accept-once", flush=True)
                send(process, {"id": message["id"], "result": {"action": "accept", "content": {}, "_meta": None}})
            else:
                print("ELICITATION_RESPONSE decline", flush=True)
                send(process, {"id": message["id"], "result": {"action": "decline", "content": None, "_meta": None}})
        else:
            send(process, {"id": message["id"], "error": {"code": -32601, "message": "Unsupported probe request"}})
        return
    if method == "item/completed":
        item = params.get("item", {})
        item_type = item.get("type", "unknown")
        print("ITEM_COMPLETED", item_type, flush=True)
        if item_type == "agentMessage" and item.get("phase") == "final_answer":
            print("FINAL", item.get("text", "")[:2000], flush=True)
    elif method == "error" and not params.get("willRetry", False):
        print("ERROR", params.get("error", {}).get("message", "unknown")[:1000], flush=True)
    elif method == "turn/completed":
        print("TURN_COMPLETED", params.get("turn", {}).get("status", "unknown"), flush=True)
        turn_completed = True


try:
    initialized = request("initialize", {
        "clientInfo": {"name": "computah-approval-probe", "title": "Computah Approval Probe", "version": "0.1.0"},
        "capabilities": {"experimentalApi": True},
    })
    if "error" in initialized:
        raise RuntimeError(initialized["error"].get("message", "initialize failed"))
    send(process, {"method": "initialized", "params": {}})
    started = request("thread/start", {
        "model": "gpt-6-astra",
        "allowProviderModelFallback": False,
        "cwd": os.path.expanduser("~"),
        "approvalPolicy": "untrusted",
        "approvalsReviewer": "user",
        "sandbox": "read-only",
        "ephemeral": True,
    })
    thread_id = started["result"]["thread"]["id"]
    request("turn/start", {
        "threadId": thread_id,
        "model": "gpt-6-astra",
        "effort": "high",
        "input": [{"type": "text", "text_elements": [], "text": (
            "Use the installed native Codex computer-use capability to observe only Calculator. "
            "Do not click, type, press keys, move the pointer, open or close anything, or inspect "
            "any other app. Report whether Calculator is reachable and its visible display value. "
            "If access is unavailable, report the exact useful tool error."
        )}],
    })
    deadline = time.monotonic() + 120
    while time.monotonic() < deadline and process.poll() is None and not turn_completed:
        try:
            receive_one(min(30, deadline - time.monotonic()))
        except TimeoutError:
            continue
except Exception as error:
    print("PROBE_ERROR", str(error)[:1000], flush=True)
finally:
    process.terminate()
    try:
        process.wait(timeout=3)
    except subprocess.TimeoutExpired:
        process.kill()
