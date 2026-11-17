from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from threading import Lock
import hashlib
import re

claimed = set()
reserved = {}
lock = Lock()

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        token = self.headers.get("Authorization", "").removeprefix("Bearer ")
        match = re.fullmatch(r"/v1/claims/([a-f0-9]{64})", self.path)
        if not match or not re.fullmatch(r"[a-f0-9]{32}", token) or hashlib.sha256(token.encode()).hexdigest() != match[1]:
            self.send_response(401)
        else:
            with lock:
                taken = match[1] in claimed
                held = match[1] in reserved
            self.send_response(200 if taken else 423 if held else 404)
        self.end_headers()

    def do_POST(self):
        token = self.headers.get("Authorization", "").removeprefix("Bearer ")
        match = re.fullmatch(r"/v1/claims/([a-f0-9]{64})(?:/(reserve|commit|release))?", self.path)
        if not match or not re.fullmatch(r"[a-f0-9]{32}", token) or hashlib.sha256(token.encode()).hexdigest() != match[1]:
            self.send_response(401)
        else:
            holder = self.headers.get("X-Claim-Holder", "")
            with lock:
                digest, operation = match[1], match[2]
                if digest in claimed:
                    status = 409
                elif operation == "reserve":
                    if digest in reserved and reserved[digest] != holder: status = 423
                    else: reserved[digest] = holder; status = 200
                elif operation in ("commit", "release"):
                    if reserved.get(digest) != holder: status = 404
                    elif operation == "commit": claimed.add(digest); reserved.pop(digest); status = 200
                    else: reserved.pop(digest); status = 200
                elif digest in reserved: status = 423
                else: claimed.add(digest); status = 201
            self.send_response(status)
        self.end_headers()

    def log_message(self, *_args):
        pass

ThreadingHTTPServer(("127.0.0.1", 28767), Handler).serve_forever()
