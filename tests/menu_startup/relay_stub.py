"""One-connection relay fixture for exercising the menu's host route."""
import base64
import hashlib
import socket

with socket.socket() as server:
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind(("127.0.0.1", 28766))
    server.listen(1)
    server.settimeout(35)
    print("RELAY_FIXTURE_READY", flush=True)
    client, _ = server.accept()
    with client:
        client.settimeout(20)
        request = b""
        while b"\r\n\r\n" not in request and len(request) < 16384:
            request += client.recv(4096)
        headers = {}
        for line in request.decode("latin1").split("\r\n")[1:]:
            if ":" in line:
                key, value = line.split(":", 1)
                headers[key.strip().lower()] = value.strip()
        accept = base64.b64encode(hashlib.sha1((headers["sec-websocket-key"] + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").encode()).digest())
        client.sendall(b"HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: " + accept + b"\r\n\r\n")
        payload = b'{"type":"ready","id":1,"code":"ABCDEFGHJK"}'
        client.sendall(bytes((0x81, len(payload))) + payload)
        try:
            while client.recv(4096):
                pass
        except (ConnectionError, socket.timeout):
            pass
