#!/usr/bin/env python3
"""Minimal bridge between a ComputerCraft WebSocket client and MATLAB HTTP.

ComputerCraft connects to ws://HOST:8768/cc.
MATLAB uses http://HOST:8768/state and /command through webread/webwrite.
Only the Python standard library is required.
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
import socket
import struct
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any
from urllib.parse import parse_qs, urlparse


GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"


class BridgeState:
    def __init__(self) -> None:
        self.lock = threading.Lock()
        self.latest_state: dict[str, Any] | None = None
        self.last_ack: dict[str, Any] | None = None
        self.connected = False
        self.last_seen = 0.0
        self.next_command_id = 1
        self.commands: list[dict[str, Any]] = []
        self.auth_token = ""

    def queue_command(self, command: dict[str, Any]) -> dict[str, Any]:
        with self.lock:
            command = dict(command)
            command["id"] = self.next_command_id
            self.next_command_id += 1
            self.commands.append(command)
            self.commands = self.commands[-100:]
            return command

    def pop_commands(self) -> list[dict[str, Any]]:
        with self.lock:
            commands = self.commands
            self.commands = []
            return commands

    def mark_connected(self, value: bool) -> None:
        with self.lock:
            self.connected = value
            self.last_seen = time.time()

    def update_from_cc(self, message: dict[str, Any]) -> None:
        with self.lock:
            self.last_seen = time.time()
            if message.get("type") == "state":
                self.latest_state = message
            elif message.get("type") == "ack":
                self.last_ack = message

    def snapshot(self) -> dict[str, Any]:
        with self.lock:
            return {
                "ok": True,
                "connected": self.connected,
                "last_seen": self.last_seen,
                "state": self.latest_state,
                "last_ack": self.last_ack,
                "queued": len(self.commands),
            }


STATE = BridgeState()


def set_auth_token(token: str | None) -> None:
    STATE.auth_token = token or ""


def token_matches(value: str | None) -> bool:
    if not STATE.auth_token:
        return True
    return value == STATE.auth_token


def json_bytes(value: Any) -> bytes:
    return json.dumps(value, ensure_ascii=False, separators=(",", ":")).encode("utf-8")


def ws_accept_value(key: str) -> str:
    digest = hashlib.sha1((key + GUID).encode("ascii")).digest()
    return base64.b64encode(digest).decode("ascii")


def read_exact(sock: socket.socket, size: int) -> bytes:
    chunks: list[bytes] = []
    remaining = size
    while remaining > 0:
        chunk = sock.recv(remaining)
        if not chunk:
            raise ConnectionError("socket closed")
        chunks.append(chunk)
        remaining -= len(chunk)
    return b"".join(chunks)


def read_frame(sock: socket.socket) -> tuple[int, bytes]:
    header = read_exact(sock, 2)
    first, second = header[0], header[1]
    opcode = first & 0x0F
    masked = (second & 0x80) != 0
    length = second & 0x7F

    if length == 126:
        length = struct.unpack("!H", read_exact(sock, 2))[0]
    elif length == 127:
        length = struct.unpack("!Q", read_exact(sock, 8))[0]

    mask = read_exact(sock, 4) if masked else b""
    payload = read_exact(sock, length) if length else b""
    if masked:
        payload = bytes(byte ^ mask[index % 4] for index, byte in enumerate(payload))
    return opcode, payload


def send_frame(sock: socket.socket, text: str) -> None:
    payload = text.encode("utf-8")
    first = 0x81
    length = len(payload)
    if length < 126:
        header = bytes([first, length])
    elif length < 65536:
        header = bytes([first, 126]) + struct.pack("!H", length)
    else:
        header = bytes([first, 127]) + struct.pack("!Q", length)
    sock.sendall(header + payload)


def send_json_frame(sock: socket.socket, value: Any) -> None:
    send_frame(sock, json.dumps(value, ensure_ascii=False, separators=(",", ":")))


class BridgeHandler(BaseHTTPRequestHandler):
    server_version = "CCAirshipBridge/0.1"

    def log_message(self, fmt: str, *args: Any) -> None:
        print("%s - %s" % (self.address_string(), fmt % args))

    def send_json(self, status: int, value: Any) -> None:
        body = json_bytes(value)
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def read_json(self) -> dict[str, Any]:
        length = int(self.headers.get("Content-Length", "0"))
        if length <= 0:
            return {}
        raw = self.rfile.read(length)
        return json.loads(raw.decode("utf-8"))

    def query_token(self) -> str | None:
        parsed = urlparse(self.path)
        values = parse_qs(parsed.query).get("token")
        if values:
            return values[0]
        return None

    def require_http_auth(self) -> bool:
        if token_matches(self.headers.get("X-Bridge-Token")):
            return True
        if token_matches(self.query_token()):
            return True
        self.send_json(401, {"ok": False, "err": "unauthorized"})
        return False

    def do_OPTIONS(self) -> None:
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.end_headers()

    def do_GET(self) -> None:
        path = urlparse(self.path).path
        if path == "/cc" and self.headers.get("Upgrade", "").lower() == "websocket":
            self.handle_websocket()
            return
        if path in ("/", "/health"):
            self.send_json(200, {"ok": True, "service": "cc-airship-bridge"})
            return
        if path == "/state":
            if not self.require_http_auth():
                return
            self.send_json(200, STATE.snapshot())
            return
        if path == "/command":
            if not self.require_http_auth():
                return
            parsed = urlparse(self.path)
            query = parse_qs(parsed.query)
            command_values = query.get("command")
            if not command_values:
                self.send_json(400, {"ok": False, "err": "missing command"})
                return
            command = {
                "type": "set_output",
                "alias": (query.get("alias") or ["TopThruster"])[0],
                "command": command_values[0],
            }
            queued = STATE.queue_command(command)
            self.send_json(200, {"ok": True, "queued": queued, "connected": STATE.snapshot()["connected"]})
            return
        if path == "/stop":
            if not self.require_http_auth():
                return
            parsed = urlparse(self.path)
            query = parse_qs(parsed.query)
            queued = STATE.queue_command({
                "type": "stop",
                "alias": (query.get("alias") or ["TopThruster"])[0],
            })
            self.send_json(200, {"ok": True, "queued": queued, "connected": STATE.snapshot()["connected"]})
            return
        self.send_json(404, {"ok": False, "err": "not found"})

    def do_POST(self) -> None:
        path = urlparse(self.path).path
        if path in ("/command", "/stop", "/set-height") and not self.require_http_auth():
            return

        try:
            body = self.read_json()
        except Exception as err:
            self.send_json(400, {"ok": False, "err": "invalid json", "detail": str(err)})
            return

        if path == "/command":
            command = {
                "type": "set_output",
                "alias": body.get("alias") or "TopThruster",
                "command": body.get("command"),
            }
            if command["command"] is None:
                self.send_json(400, {"ok": False, "err": "missing command"})
                return
            queued = STATE.queue_command(command)
            self.send_json(200, {"ok": True, "queued": queued, "connected": STATE.snapshot()["connected"]})
            return

        if path == "/stop":
            queued = STATE.queue_command({"type": "stop", "alias": body.get("alias") or "TopThruster"})
            self.send_json(200, {"ok": True, "queued": queued, "connected": STATE.snapshot()["connected"]})
            return

        if path == "/set-height":
            self.send_json(501, {
                "ok": False,
                "err": "direct height write is not supported by the current ComputerCraft/Aeronautics peripheral APIs",
                "required": "external Minecraft command/RCON, a custom mod API, or a controlled in-game reset mechanism",
            })
            return

        self.send_json(404, {"ok": False, "err": "not found"})

    def handle_websocket(self) -> None:
        key = self.headers.get("Sec-WebSocket-Key")
        if not key:
            self.send_error(400, "Missing Sec-WebSocket-Key")
            return
        if not token_matches(self.query_token()) and not token_matches(self.headers.get("X-Bridge-Token")):
            self.send_error(401, "Unauthorized")
            return

        self.send_response(101, "Switching Protocols")
        self.send_header("Upgrade", "websocket")
        self.send_header("Connection", "Upgrade")
        self.send_header("Sec-WebSocket-Accept", ws_accept_value(key))
        self.end_headers()

        sock = self.connection
        sock.settimeout(0.1)
        STATE.mark_connected(True)
        print("ComputerCraft WebSocket connected")

        try:
            while True:
                for command in STATE.pop_commands():
                    send_json_frame(sock, command)

                try:
                    opcode, payload = read_frame(sock)
                except socket.timeout:
                    continue

                if opcode == 8:
                    break
                if opcode == 9:
                    sock.sendall(b"\x8a\x00")
                    continue
                if opcode != 1:
                    continue

                message = json.loads(payload.decode("utf-8"))
                STATE.update_from_cc(message)
        except Exception as err:
            print("ComputerCraft WebSocket closed:", err)
        finally:
            STATE.mark_connected(False)


def make_server(host: str, port: int) -> ThreadingHTTPServer:
    return ThreadingHTTPServer((host, port), BridgeHandler)


def serve(host: str, port: int) -> None:
    server = make_server(host, port)
    print(f"CC Airship bridge listening on http://{host}:{port}")
    print(f"ComputerCraft URL: ws://{host}:{port}/cc")
    if STATE.auth_token:
        print("Bridge auth: enabled")
    else:
        print("Bridge auth: disabled")
    server.serve_forever()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="0.0.0.0")
    parser.add_argument("--port", type=int, default=8768)
    parser.add_argument("--token", default="")
    args = parser.parse_args()
    set_auth_token(args.token)
    serve(args.host, args.port)


if __name__ == "__main__":
    main()
