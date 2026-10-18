#!/usr/bin/env python3
"""Focused protocol tests for the dependency-free WebSocket ProxyCommand."""

from __future__ import annotations

import base64
import hashlib
from pathlib import Path
import socket
import struct
import subprocess
import threading


ROOT = Path(__file__).resolve().parents[1]
PROXY = ROOT / "client" / "wsproxy.py"
GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"


def run_case(frame: bytes = b"", *, bad_accept: bool = False) -> subprocess.CompletedProcess:
    listener = socket.socket()
    listener.bind(("127.0.0.1", 0))
    listener.listen(1)
    port = listener.getsockname()[1]
    seen: dict[str, str] = {}

    def serve() -> None:
        conn, _ = listener.accept()
        try:
            request = b""
            while b"\r\n\r\n" not in request:
                request += conn.recv(4096)
            request_text = request.decode("ascii")
            seen["request"] = request_text
            key = next(
                line.split(":", 1)[1].strip()
                for line in request_text.split("\r\n")
                if line.lower().startswith("sec-websocket-key:")
            )
            accept = base64.b64encode(
                hashlib.sha1((key + GUID).encode("ascii")).digest()
            ).decode("ascii")
            if bad_accept:
                accept = "invalid"
            response = (
                "HTTP/1.1 101 Switching Protocols\r\n"
                "Upgrade: websocket\r\n"
                "Connection: Upgrade\r\n"
                f"Sec-WebSocket-Accept: {accept}\r\n\r\n"
            ).encode("ascii")
            conn.sendall(response + frame)
        finally:
            conn.close()
            listener.close()

    server = threading.Thread(target=serve)
    server.start()
    result = subprocess.run(
        ["python3", str(PROXY), f"ws://127.0.0.1:{port}/test"],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=5,
        check=False,
    )
    server.join(timeout=5)
    assert not server.is_alive(), "fake WebSocket server did not stop"
    assert f"Host: 127.0.0.1:{port}\r\n" in seen["request"]
    return result


def main() -> None:
    bad_accept = run_case(bad_accept=True)
    assert bad_accept.returncode != 0
    assert b"Sec-WebSocket-Accept does not match" in bad_accept.stderr

    masked = run_case(frame=b"\x82\x81\0\0\0\0x")
    assert masked.returncode != 0
    assert b"masked frame" in masked.stderr

    oversized = run_case(
        frame=b"\x82\x7f" + struct.pack("!Q", (1 << 20) + 1)
    )
    assert oversized.returncode != 0
    assert b"exceeds 1 MiB" in oversized.stderr

    print("WebSocket proxy protocol tests passed")


if __name__ == "__main__":
    main()
