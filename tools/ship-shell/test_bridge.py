"""Drive the shipped bridge: hello plus eval, oversized frame, shutdown."""

import base64
import json
import os
import socket
import sys
import threading
import urllib.request
from pathlib import Path

import importlib.util

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("ship_shell_bridge", HERE / "bridge.py")
bridge_mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bridge_mod)

TOKEN = "test-token"
ENGINE_ID = 12


class ManualClock:
    def __init__(self):
        self.now = 0.0
        self._cv = threading.Condition()

    def time(self):
        with self._cv:
            return self.now

    def sleep(self, seconds):
        with self._cv:
            target = self.now + seconds
            while self.now < target:
                self._cv.wait(timeout=0.05)

    def advance(self, seconds):
        with self._cv:
            self.now += seconds
            self._cv.notify_all()


class ListRcon:
    def __init__(self):
        self.commands = []
        self.event = threading.Event()

    def send(self, command):
        self.commands.append(command)
        self.event.set()


def client_frame(payload, opcode=0x1):
    data = payload if isinstance(payload, bytes) else payload.encode("utf-8")
    mask = os.urandom(4)
    length = len(data)
    header = bytearray([0x80 | opcode])
    if length < 126:
        header.append(0x80 | length)
    elif length < 65536:
        header.append(0x80 | 126)
        header += length.to_bytes(2, "big")
    else:
        header.append(0x80 | 127)
        header += length.to_bytes(8, "big")
    masked = bytes(data[i] ^ mask[i % 4] for i in range(length))
    return bytes(header) + mask + masked


def read_http_headers(conn):
    data = b""
    while b"\r\n\r\n" not in data:
        chunk = conn.recv(4096)
        if not chunk:
            raise ConnectionError("closed during handshake")
        data += chunk
    head, rest = data.split(b"\r\n\r\n", 1)
    if b"101 " not in head.split(b"\r\n", 1)[0]:
        raise AssertionError(head.decode("latin1", "replace"))
    return rest


def read_server_frame(conn, buffered=b""):
    while len(buffered) < 2:
        chunk = conn.recv(4096)
        if not chunk:
            raise ConnectionError("closed")
        buffered += chunk
    length = buffered[1] & 0x7F
    start = 2
    if length == 126:
        while len(buffered) < 4:
            buffered += conn.recv(4096)
        length = int.from_bytes(buffered[2:4], "big")
        start = 4
    elif length == 127:
        while len(buffered) < 10:
            buffered += conn.recv(4096)
        length = int.from_bytes(buffered[2:10], "big")
        start = 10
    while len(buffered) < start + length:
        chunk = conn.recv(65536)
        if not chunk:
            raise ConnectionError("closed")
        buffered += chunk
    payload = buffered[start:start + length]
    return json.loads(payload.decode("utf-8")), buffered[start + length:]


def connect(port, role, engine_id=None):
    conn = socket.create_connection(("127.0.0.1", port), timeout=5)
    key = base64.b64encode(os.urandom(16)).decode("ascii")
    request = (
        "GET /ship HTTP/1.1\r\n"
        "Host: 127.0.0.1\r\n"
        "Upgrade: websocket\r\n"
        "Connection: Upgrade\r\n"
        "Sec-WebSocket-Key: %s\r\n"
        "Sec-WebSocket-Version: 13\r\n"
        "\r\n" % key
    )
    conn.sendall(request.encode("ascii"))
    rest = read_http_headers(conn)
    hello = {"type": "hello", "role": role, "token": TOKEN, "label": role}
    if engine_id is not None:
        hello["id"] = engine_id
    conn.sendall(client_frame(json.dumps(hello)))
    ready, rest = read_server_frame(conn, rest)
    if ready.get("type") != "ready":
        raise AssertionError(ready)
    return conn, rest


def post_json(port, path, body):
    data = json.dumps(body).encode("utf-8")
    request = urllib.request.Request(
        "http://127.0.0.1:%s%s" % (port, path),
        data=data,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=5) as response:
        return json.loads(response.read().decode("utf-8"))


def main():
    clock = ManualClock()
    rcon = ListRcon()
    bridge = bridge_mod.Bridge(
        {"token": TOKEN, "ws_host": "127.0.0.1", "ws_port": 0, "http_port": 0},
        clock=clock,
        rcon=rcon,
    )
    threading.Thread(target=bridge.serve, name="bridge", daemon=True).start()
    if not bridge.ready.wait(5):
        raise SystemExit("bridge did not bind")
    if bridge.http_address[0] != "127.0.0.1":
        raise SystemExit("http is not loopback: %s" % (bridge.http_address,))
    ws_port = bridge.ws_port()
    http_port = bridge.http_address[1]

    conn, rest = connect(ws_port, "engine", ENGINE_ID)
    box = {}

    def do_eval():
        box["result"] = post_json(http_port, "/eval", {"code": "return 1"})

    worker = threading.Thread(target=do_eval)
    worker.start()
    message, rest = read_server_frame(conn, rest)
    if message.get("type") != "eval" or message.get("code") != "return 1":
        raise SystemExit("expected eval, got %s" % message)
    conn.sendall(client_frame(json.dumps({
        "type": "result",
        "id": message["id"],
        "ok": True,
        "values": [1],
        "output": "",
    })))
    worker.join(5)
    if box.get("result", {}).get("values") != [1]:
        raise SystemExit("eval result missing: %s" % box)
    print("hello-eval ok", flush=True)

    huge = b"x" * (bridge_mod.FRAME_LIMIT + 1)
    conn.sendall(client_frame(huge))
    rejected, _rest = read_server_frame(conn)
    if rejected.get("error") != "too_large":
        raise SystemExit("oversized frame was not rejected: %s" % rejected)
    print("oversized rejected", flush=True)
    conn.close()

    stalled, _rest = connect(ws_port, "engine", ENGINE_ID)
    stalled_box = {}

    def do_stall():
        try:
            stalled_box["result"] = post_json(http_port, "/eval", {"code": "while true do end"})
        except Exception as exc:
            stalled_box["error"] = str(exc)

    stall_thread = threading.Thread(target=do_stall)
    stall_thread.start()
    stall_msg, _rest = read_server_frame(stalled)
    if stall_msg.get("type") != "eval":
        raise SystemExit("expected stalled eval, got %s" % stall_msg)
    clock.advance(10)
    if not rcon.event.wait(5):
        raise SystemExit("shutdown was not issued: %s" % rcon.commands)
    expected = "computercraft shutdown #%s" % ENGINE_ID
    if rcon.commands != [expected]:
        raise SystemExit("rcon commands: %s" % rcon.commands)
    if any("turn-on" in command for command in rcon.commands):
        raise SystemExit("turn-on was sent")
    print("shutdown %s" % expected, flush=True)
    print("no turn-on", flush=True)
    stall_thread.join(5)
    bridge.close()
    clock.advance(1)


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print("FAILED %s" % exc, file=sys.stderr)
        raise
