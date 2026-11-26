import base64
import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse


class Handler(BaseHTTPRequestHandler):
    def reply(self, value, status=200):
        body = json.dumps(value).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        path = urlparse(self.path).path
        if path == "/languages":
            self.reply(
                [{"id": 71, "name": "Python (3.8.1)"}, {"id": 54, "name": "C++ (GCC 9.2.0)"}]
            )
        elif path == "/auth/languages":
            self.reply({}, 401)
        elif path == "/submissions/python-fixture-accepted":
            self.reply(
                {"status": {"id": 3, "description": "Accepted"}, "stdout": "NDIK",
                 "time": "0.02", "memory": 4096}
            )
        elif path == "/submissions/fixture-pending":
            self.reply({"status": {"id": 2, "description": "Processing"}})
        else:
            self.reply({}, 404)

    def do_POST(self):
        parsed = urlparse(self.path)
        if parsed.path != "/submissions":
            self.reply({}, 404)
            return
        data = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        assert parse_qs(parsed.query) == {"base64_encoded": ["true"], "wait": ["false"]}
        assert data["enable_network"] is False and data["cpu_time_limit"] == 3
        assert data["wall_time_limit"] == 8 and data["memory_limit"] == 262144
        assert data["max_file_size"] == 16 and data["language_id"] == 71
        source = base64.b64decode(data["source_code"]).decode()
        if source == "rate":
            self.reply({}, 429)
        elif source == "pending":
            self.reply({"token": "fixture-pending"}, 201)
        else:
            assert source == "print(int(input()) * 2)"
            assert base64.b64decode(data["stdin"]) == b"21\n"
            self.reply({"token": "python-fixture-accepted"}, 201)


if __name__ == "__main__":
    ThreadingHTTPServer(("127.0.0.1", 28769), Handler).serve_forever()
