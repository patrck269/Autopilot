"""LAN websocket bridge for the ship debug shell. Standard library only."""

import hashlib
import hmac
import json
import os
import socket
import struct
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

FRAME_LIMIT = 96 * 1024
WS_GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
EVAL_HTTP_WAIT = 8
EVAL_SHUTDOWN_AFTER = 10


class MonoClock:
    def time(self):
        return time.monotonic()

    def sleep(self, seconds):
        time.sleep(seconds)


class NullRcon:
    def send(self, command):
        return None


class MinecraftRcon:
    def __init__(self, host, port, password):
        self.host = host
        self.port = int(port)
        self.password = password

    def send(self, command):
        sock = socket.create_connection((self.host, self.port), timeout=5)
        try:
            self._packet(sock, 1, 3, self.password)
            self._read_packet(sock)
            self._packet(sock, 2, 2, command)
            self._read_packet(sock)
        finally:
            sock.close()

    def _packet(self, sock, request_id, kind, payload):
        body = struct.pack("<ii", request_id, kind) + payload.encode("utf-8") + b"\x00\x00"
        sock.sendall(struct.pack("<i", len(body)) + body)

    def _exact(self, sock, size):
        buf = b""
        while len(buf) < size:
            chunk = sock.recv(size - len(buf))
            if not chunk:
                raise ConnectionError("rcon closed")
            buf += chunk
        return buf

    def _read_packet(self, sock):
        length = struct.unpack("<i", self._exact(sock, 4))[0]
        return self._exact(sock, length)


def server_frame(payload, opcode=0x1):
    data = payload if isinstance(payload, bytes) else payload.encode("utf-8")
    header = bytearray([0x80 | opcode])
    length = len(data)
    if length < 126:
        header.append(length)
    elif length < 65536:
        header.append(126)
        header += length.to_bytes(2, "big")
    else:
        header.append(127)
        header += length.to_bytes(8, "big")
    return bytes(header) + data


def _exact(conn, size):
    buf = b""
    while len(buf) < size:
        chunk = conn.recv(size - len(buf))
        if not chunk:
            raise ConnectionError("socket closed")
        buf += chunk
    return buf


def read_frame(conn):
    header = _exact(conn, 2)
    opcode = header[0] & 0x0F
    masked = header[1] & 0x80
    length = header[1] & 0x7F
    if length == 126:
        length = int.from_bytes(_exact(conn, 2), "big")
    elif length == 127:
        length = int.from_bytes(_exact(conn, 8), "big")
    mask = _exact(conn, 4) if masked else None
    if length > FRAME_LIMIT:
        remaining = length
        while remaining > 0:
            chunk = conn.recv(min(remaining, 65536))
            if not chunk:
                raise ConnectionError("socket closed")
            remaining -= len(chunk)
        return "too_large", b""
    payload = _exact(conn, length) if length else b""
    if mask:
        payload = bytes(payload[i] ^ mask[i % 4] for i in range(len(payload)))
    return opcode, payload


class Bridge:
    def __init__(self, settings, clock=None, rcon=None):
        self.settings = settings
        self.token = settings.get("token") or ""
        self.clock = clock or MonoClock()
        self.rcon = rcon if rcon is not None else NullRcon()
        self.lock = threading.Lock()
        self.send_lock = threading.Lock()
        self.ready = threading.Event()
        self.running = False
        self.engine_conn = None
        self.watchdog_conn = None
        self.engine_id = None
        self.armed = False
        self.latched = False
        self.shutdown_sent = False
        self.status = None
        self.last_status_at = None
        self.next_id = 1
        self.waiters = {}
        self.eval_sent_at = None
        self.eval_id = None
        self.frame_after_eval = False
        self.ws_sock = None
        self.http_server = None
        self.http_address = None

    def serve(self):
        host = self.settings.get("ws_host") or "127.0.0.1"
        ws_port = int(self.settings.get("ws_port") or 0)
        http_port = int(self.settings.get("http_port") or 8767)
        self.ws_sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.ws_sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.ws_sock.bind((host, ws_port))
        self.ws_sock.listen(8)
        self.ws_sock.settimeout(0.5)
        handler = self._http_handler()
        self.http_server = ThreadingHTTPServer(("127.0.0.1", http_port), handler)
        self.http_address = self.http_server.server_address
        self.running = True
        threading.Thread(target=self._ws_loop, name="ship-shell-ws", daemon=True).start()
        threading.Thread(target=self.http_server.serve_forever, name="ship-shell-http", daemon=True).start()
        self.ready.set()
        try:
            while self.running:
                self._scan()
                self.clock.sleep(0.05)
        finally:
            self.close()

    def close(self):
        self.running = False
        if self.http_server is not None:
            self.http_server.shutdown()
        if self.ws_sock is not None:
            try:
                self.ws_sock.close()
            except OSError:
                pass

    def ws_port(self):
        return self.ws_sock.getsockname()[1]

    def session_body(self):
        with self.lock:
            age = None
            if self.last_status_at is not None:
                age = self.clock.time() - self.last_status_at
            return {
                "engine_connected": self.engine_conn is not None,
                "watchdog_connected": self.watchdog_conn is not None,
                "engine_id": self.engine_id,
                "armed": self.armed,
                "latched": self.latched,
                "status_age": age,
                "shutdown_sent": self.shutdown_sent,
            }

    def _scan(self):
        command = None
        with self.lock:
            if (
                not self.shutdown_sent
                and self.eval_sent_at is not None
                and not self.frame_after_eval
                and self.engine_id is not None
                and self.clock.time() - self.eval_sent_at >= EVAL_SHUTDOWN_AFTER
            ):
                self.shutdown_sent = True
                command = "computercraft shutdown #%s" % self.engine_id
        if command is not None:
            print("shutdown %s" % command, flush=True)
            self.rcon.send(command)

    def _ws_loop(self):
        while self.running:
            try:
                conn, _addr = self.ws_sock.accept()
            except socket.timeout:
                continue
            except OSError:
                return
            threading.Thread(target=self._client, args=(conn,), daemon=True).start()

    def _client(self, conn):
        role = None
        try:
            self._handshake(conn)
            while self.running:
                opcode, payload = read_frame(conn)
                if opcode == "too_large":
                    self._send_json(conn, {"type": "error", "error": "too_large"})
                    return
                if opcode == 8:
                    return
                if opcode == 9:
                    self._send_raw(conn, server_frame(payload, 0xA))
                    continue
                if opcode != 1 or not payload:
                    continue
                msg = json.loads(payload.decode("utf-8"))
                if role is None:
                    role = self._hello(conn, msg)
                    if role is None:
                        return
                    continue
                if role == "engine":
                    self._on_engine(msg)
        except (ConnectionError, OSError, json.JSONDecodeError, UnicodeError):
            return
        finally:
            self._detach(conn)
            try:
                conn.close()
            except OSError:
                pass

    def _handshake(self, conn):
        data = b""
        while b"\r\n\r\n" not in data:
            chunk = conn.recv(4096)
            if not chunk:
                raise ConnectionError("handshake closed")
            data += chunk
            if len(data) > 8192:
                raise ConnectionError("handshake too large")
        header = data.split(b"\r\n\r\n", 1)[0].decode("latin1")
        key = None
        for line in header.split("\r\n"):
            if line.lower().startswith("sec-websocket-key:"):
                key = line.split(":", 1)[1].strip()
        if not key:
            raise ConnectionError("missing websocket key")
        accept = hashlib.sha1((key + WS_GUID).encode("ascii")).digest()
        import base64
        response = (
            "HTTP/1.1 101 Switching Protocols\r\n"
            "Upgrade: websocket\r\n"
            "Connection: Upgrade\r\n"
            "Sec-WebSocket-Accept: %s\r\n"
            "\r\n" % base64.b64encode(accept).decode("ascii")
        )
        conn.sendall(response.encode("ascii"))

    def _hello(self, conn, msg):
        token = msg.get("token")
        if (
            msg.get("type") != "hello"
            or not self.token
            or not isinstance(token, str)
            or not hmac.compare_digest(token, self.token)
        ):
            return None
        role = msg.get("role")
        if role == "engine":
            engine_id = msg.get("id")
            if not isinstance(engine_id, int):
                return None
            with self.lock:
                self.engine_conn = conn
                self.engine_id = engine_id
            print("engine connected %s" % engine_id, flush=True)
            self._send_json(conn, {"type": "ready"})
            self._arm_watchdog()
            return "engine"
        if role == "watchdog":
            with self.lock:
                self.watchdog_conn = conn
            print("watchdog connected", flush=True)
            self._send_json(conn, {"type": "ready"})
            self._arm_watchdog()
            return "watchdog"
        return None

    def _arm_watchdog(self):
        with self.lock:
            watchdog = self.watchdog_conn
            engine_id = self.engine_id
            engine_up = self.engine_conn is not None
        if watchdog is not None and engine_up and engine_id is not None:
            self._send_json(watchdog, {"type": "arm", "engine_id": engine_id})
            with self.lock:
                self.armed = True

    def _detach(self, conn):
        disarm = None
        with self.lock:
            if self.engine_conn is conn:
                self.engine_conn = None
                disarm = self.watchdog_conn
                print("engine disconnected", flush=True)
            if self.watchdog_conn is conn:
                self.watchdog_conn = None
                print("watchdog disconnected", flush=True)
        if disarm is not None:
            try:
                self._send_json(disarm, {"type": "disarm"})
            except OSError:
                pass
            with self.lock:
                if not self.latched:
                    self.armed = False

    def _on_engine(self, msg):
        kind = msg.get("type")
        with self.lock:
            if self.eval_sent_at is not None:
                self.frame_after_eval = True
            if kind == "status":
                self.status = msg
                self.last_status_at = self.clock.time()
            if kind == "result":
                waiter = self.waiters.get(msg.get("id"))
                if waiter is not None:
                    waiter["result"] = msg
                    waiter["event"].set()
                if msg.get("id") == self.eval_id:
                    self.eval_sent_at = None
                    self.eval_id = None

    def _request(self, payload, timeout):
        with self.lock:
            if self.engine_conn is None:
                return {"ok": False, "error": "engine down"}
            request_id = str(self.next_id)
            self.next_id += 1
            conn = self.engine_conn
            event = threading.Event()
            self.waiters[request_id] = {"event": event, "result": None}
            if payload.get("type") == "eval":
                self.eval_sent_at = self.clock.time()
                self.eval_id = request_id
                self.frame_after_eval = False
                print("eval %s" % request_id, flush=True)
        body = dict(payload)
        body["id"] = request_id
        self._send_json(conn, body)
        deadline = self.clock.time() + timeout
        while self.clock.time() < deadline:
            if event.wait(0.01):
                break
        with self.lock:
            found = self.waiters.pop(request_id, None)
        if found is not None and found["result"] is not None:
            return found["result"]
        return {"ok": False, "error": "timeout", "id": request_id}

    def _send_both(self, payload):
        with self.lock:
            targets = [conn for conn in (self.engine_conn, self.watchdog_conn) if conn is not None]
        for conn in targets:
            try:
                self._send_json(conn, payload)
            except OSError:
                pass

    def _send_json(self, conn, obj):
        self._send_raw(conn, server_frame(json.dumps(obj, separators=(",", ":")).encode("utf-8")))

    def _send_raw(self, conn, frame):
        with self.send_lock:
            conn.sendall(frame)

    def _http_handler(self):
        bridge = self

        class Handler(BaseHTTPRequestHandler):
            protocol_version = "HTTP/1.1"

            def log_message(self, fmt, *args):
                return

            def _json(self, code, obj):
                data = json.dumps(obj).encode("utf-8")
                self.send_response(code)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)

            def _read_json(self):
                length = int(self.headers.get("Content-Length") or "0")
                if length > FRAME_LIMIT:
                    return None
                raw = self.rfile.read(length) if length else b""
                if not raw:
                    return {}
                return json.loads(raw.decode("utf-8"))

            def do_GET(self):
                path = self.path.split("?", 1)[0]
                if path == "/session":
                    self._json(200, bridge.session_body())
                    return
                if path == "/status":
                    self._json(200, bridge.status or {})
                    return
                if path == "/read":
                    query = self.path.split("?", 1)[1] if "?" in self.path else ""
                    file_path = ""
                    for part in query.split("&"):
                        if part.startswith("path="):
                            from urllib.parse import unquote
                            file_path = unquote(part[5:])
                    result = bridge._request({"type": "read", "path": file_path}, EVAL_HTTP_WAIT)
                    self._json(200, result)
                    return
                self._json(404, {"ok": False, "error": "not found"})

            def do_POST(self):
                path = self.path.split("?", 1)[0]
                try:
                    body = self._read_json()
                except (json.JSONDecodeError, UnicodeError):
                    self._json(400, {"ok": False, "error": "bad json"})
                    return
                if body is None:
                    self._json(400, {"ok": False, "error": "too_large"})
                    return
                if path == "/eval":
                    self._json(200, bridge._request({"type": "eval", "code": body.get("code", "")}, EVAL_HTTP_WAIT))
                    return
                if path == "/write":
                    self._json(200, bridge._request({
                        "type": "write",
                        "path": body.get("path", ""),
                        "content": body.get("content", ""),
                    }, EVAL_HTTP_WAIT))
                    return
                if path == "/reboot":
                    self._json(200, bridge._request({"type": "reboot"}, EVAL_HTTP_WAIT))
                    return
                if path == "/zero":
                    bridge._send_both({"type": "zero"})
                    with bridge.lock:
                        bridge.latched = True
                    self._json(200, {"ok": True})
                    return
                if path == "/clear":
                    bridge._send_both({"type": "clear"})
                    with bridge.lock:
                        bridge.latched = False
                    self._json(200, {"ok": True})
                    return
                self._json(404, {"ok": False, "error": "not found"})

        return Handler


def load_settings(path):
    with open(path, "r", encoding="utf-8") as handle:
        return json.load(handle)


def build_rcon(settings):
    host = settings.get("rcon_host")
    if not host:
        return NullRcon()
    return MinecraftRcon(host, settings.get("rcon_port", 25575), settings.get("rcon_password", ""))


def main(argv):
    default = os.path.join(os.path.dirname(os.path.abspath(__file__)), "bridge.local.json")
    path = argv[1] if len(argv) > 1 else default
    settings = load_settings(path)
    bridge = Bridge(settings, rcon=build_rcon(settings))
    bridge.serve()


if __name__ == "__main__":
    main(sys.argv)
