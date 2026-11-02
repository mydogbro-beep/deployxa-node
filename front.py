#!/usr/bin/env python3
"""Zero-write front server for the Deployxa node.

Listens on 0.0.0.0:3000 (the platform-facing port) and does exactly
three things:

  * GET /                       -> 200 "ok"  (platform health check)
  * <NODE_PATH> + WS Upgrade    -> raw TCP relay to Xray on 127.0.0.1:3001
  * anything else               -> 404

Python 3 stdlib only, and it never writes to disk (the platform runs
the container with a restricted filesystem, which is what killed the
previous nginx front). NODE_PATH is read from the environment; if it
is unset the WebSocket route simply never matches.
"""

import os
import select
import socket
import sys
from socketserver import ThreadingTCPServer, BaseRequestHandler

LISTEN_HOST = "0.0.0.0"
LISTEN_PORT = 3000
UPSTREAM = ("127.0.0.1", 3001)
MAX_HEAD = 64 * 1024
NODE_PATH = os.environ.get("NODE_PATH") or None

RESP_200 = (b"HTTP/1.1 200 OK\r\n"
            b"Content-Type: text/plain\r\n"
            b"Content-Length: 2\r\n"
            b"Connection: close\r\n"
            b"\r\n"
            b"ok")
RESP_404 = (b"HTTP/1.1 404 Not Found\r\n"
            b"Content-Type: text/plain\r\n"
            b"Content-Length: 0\r\n"
            b"Connection: close\r\n"
            b"\r\n")


def log(msg):
    print("[front] %s" % msg, flush=True)


class Handler(BaseRequestHandler):
    def handle(self):
        try:
            self._handle()
        except (BrokenPipeError, ConnectionResetError, OSError):
            pass  # client went away mid-flight; nothing to do

    def _handle(self):
        conn = self.request
        head, rest = self._read_head(conn)
        if head is None:
            return
        lines = head.split(b"\r\n")
        parts = lines[0].split(b" ")
        if len(parts) < 2:
            return
        method = parts[0].decode("latin-1")
        target = parts[1].decode("latin-1")
        headers = {}
        for line in lines[1:]:
            if b":" in line:
                k, v = line.split(b":", 1)
                headers[k.strip().decode("latin-1").lower()] = \
                    v.strip().decode("latin-1")

        peer = "%s:%s" % self.client_address

        if method == "GET" and target == "/":
            log("health %s" % peer)
            conn.sendall(RESP_200)
            return

        if (NODE_PATH is not None and target == NODE_PATH
                and "websocket" in headers.get("upgrade", "").lower()):
            log("ws relay %s" % peer)
            self._relay(conn, head, rest)
            return

        log("404 %s %s %s" % (peer, method, target))
        conn.sendall(RESP_404)

    @staticmethod
    def _read_head(conn):
        """Read until end of the request head; return (head, leftover)."""
        buf = b""
        while b"\r\n\r\n" not in buf:
            if len(buf) > MAX_HEAD:
                return None, b""
            try:
                chunk = conn.recv(8192)
            except OSError:
                return None, b""
            if not chunk:
                return None, b""
            buf += chunk
        head, rest = buf.split(b"\r\n\r\n", 1)
        return head + b"\r\n\r\n", rest

    @staticmethod
    def _relay(client, head, rest):
        try:
            upstream = socket.create_connection(UPSTREAM, timeout=10)
        except OSError:
            return
        try:
            upstream.sendall(head)
            if rest:
                upstream.sendall(rest)
            sockets = [client, upstream]
            while True:
                readable, _, _ = select.select(sockets, [], [], 300)
                if not readable:
                    break
                for src in readable:
                    try:
                        data = src.recv(65536)
                    except OSError:
                        data = b""
                    if not data:
                        return
                    dst = upstream if src is client else client
                    try:
                        dst.sendall(data)
                    except OSError:
                        return
        finally:
            try:
                upstream.close()
            except OSError:
                pass


class Server(ThreadingTCPServer):
    daemon_threads = True
    allow_reuse_address = True  # SO_REUSEADDR


def main():
    with Server((LISTEN_HOST, LISTEN_PORT), Handler) as srv:
        log("listening on %s:%d (ws path %s)"
            % (LISTEN_HOST, LISTEN_PORT,
               "set" if NODE_PATH else "unset"))
        try:
            srv.serve_forever()
        except KeyboardInterrupt:
            pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
