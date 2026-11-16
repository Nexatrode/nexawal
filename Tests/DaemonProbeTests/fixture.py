"""Loopback-only synthetic daemon; no wallet, keys, or upstream RPC."""
import gzip
import http.server
import json
import sys
import threading
import time

counts = {}
sent = {}
disconnected = set()
lock = threading.Lock()
normal = json.dumps({"result": {"height": 42, "target_height": 45}}).encode()
large = json.dumps({"result": {"height": 42, "target_height": 45}, "padding": "x" * 70000}).encode()


class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def do_POST(self):
        self.rfile.read(int(self.headers.get("Content-Length", 0)))
        self.respond()

    def do_GET(self):
        self.respond()

    def respond(self):
        parts = self.path.strip("/").split("/")
        mode = parts[0]
        if mode in ("stats", "sent", "disconnected"):
            with lock:
                value = counts.get(parts[1], 0) if mode == "stats" else sent.get(parts[1], 0) if mode == "sent" else int(parts[1] in disconnected)
                body = str(value).encode()
            self.send_response(200)
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        with lock:
            counts[mode] = counts.get(mode, 0) + 1
        fallback = self.command == "GET"
        status, body = 200, normal
        if mode == "slow":
            time.sleep(1.5)
        if mode in ("large", "unknown", "chunked", "gzip") or (mode == "fallback-large" and fallback):
            body = large
        elif mode == "slow-stream":
            body = normal + b" " * (1024 * 1024)
        elif mode == "exact":
            body = normal + b" " * (65536 - len(normal))
        elif mode in ("fallback", "fallback-large"):
            status, body = (200, b'{"height":40}') if fallback else (404, b"unsupported")
        elif mode == "http-error":
            status, body = 503, b"x" * 10000
        elif mode == "decode-error":
            body = b"x" * 10000
        elif mode == "rpc-error":
            body = json.dumps({"error": {"code": -1, "message": "x" * 10000}}).encode()
            if fallback:
                status = 503
        elif mode == "redirect":
            status = 302
        if mode == "gzip":
            body = gzip.compress(body)
        self.send_response(status)
        self.send_header("Connection", "close")
        if mode == "gzip":
            self.send_header("Content-Encoding", "gzip")
        if mode == "redirect":
            self.send_header("Location", "/normal")
        if mode == "chunked":
            self.send_header("Transfer-Encoding", "chunked")
        elif mode not in ("unknown", "slow-stream"):
            self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        try:
            for start in range(0, len(body), 1024):
                chunk = body[start:start + 1024]
                if mode == "chunked":
                    self.wfile.write(("%x\r\n" % len(chunk)).encode() + chunk + b"\r\n")
                else:
                    self.wfile.write(chunk)
                self.wfile.flush()
                with lock:
                    sent[mode] = sent.get(mode, 0) + len(chunk)
                if mode == "slow-stream":
                    time.sleep(0.005)
            if mode == "chunked":
                self.wfile.write(b"0\r\n\r\n")
        except (BrokenPipeError, ConnectionResetError):
            with lock:
                disconnected.add(mode)


server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
with open(sys.argv[1], "w") as output:
    output.write("http://127.0.0.1:%d" % server.server_port)
server.serve_forever()
