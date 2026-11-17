"""Loopback Responses API fixture; no real OpenAI credential is used."""

import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


class Handler(BaseHTTPRequestHandler):
    def _reply(self, code, data):
        body = json.dumps(data).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _authorized(self):
        return self.headers.get("Authorization") == "Bearer sk-test-12345678901234567890"

    def do_GET(self):
        if not self._authorized():
            return self._reply(401, {"error": {"message": "secret details must stay private"}})
        if self.path == "/v1/models/rate-limited":
            return self._reply(429, {"error": {"message": "rate limited"}})
        if self.path == "/v1/models/gpt-5.4-mini":
            return self._reply(200, {"id": "gpt-5.4-mini", "object": "model"})
        return self._reply(404, {"error": {"message": "unknown model"}})

    def do_POST(self):
        if not self._authorized():
            return self._reply(401, {"error": {"message": "secret details must stay private"}})
        if self.path == "/v1/audio/transcriptions":
            body = self.rfile.read(int(self.headers.get("Content-Length", "0")))
            if b"gpt-4o-mini-transcribe" not in body or b"RIFF" not in body or b"question.wav" not in body:
                return self._reply(400, {"error": {"message": "bad audio form"}})
            return self._reply(200, {"text": "What does the board show?"})
        try:
            body = json.loads(self.rfile.read(int(self.headers.get("Content-Length", "0"))))
        except (ValueError, TypeError):
            return self._reply(400, {"error": {"message": "bad JSON"}})
        if self.path == "/v1/moderations":
            if body.get("model") != "omni-moderation-latest":
                return self._reply(400, {"error": {"message": "bad moderation model"}})
            return self._reply(200, {"results": [{"flagged": body.get("input") == "flag this"}]})
        if self.path == "/v1/responses" and str(body.get("input", "")).startswith("You are a fictional classroom instructor"):
            if body.get("store") is not False:
                return self._reply(400, {"error": {"message": "request stored"}})
            return self._reply(200, {"status": "completed", "output": [{"type": "message", "content": [{"type": "output_text", "text": "The board shows a current path."}]}]})
        if self.path == "/v1/responses" and body.get("store") is False:
            request_input = body.get("input")
            if isinstance(request_input, str) and request_input.startswith("You are an assistant inside a fictional campus browser"):
                return self._reply(200, {"status": "completed", "output": [{"type": "message", "content": [{"type": "output_text", "text": '{"answer":"Page answer"}'}]}]})
            if isinstance(request_input, list) and request_input and isinstance(request_input[0], dict):
                parts = request_input[0].get("content", [])
                if len(parts) == 2 and parts[0].get("type") == "input_text" and parts[1].get("type") == "input_image" and str(parts[1].get("image_url", "")).startswith("data:image/jpeg;base64,"):
                    return self._reply(200, {"status": "completed", "output": [{"type": "message", "content": [{"type": "output_text", "text": '{"answer":"Image answer"}'}]}]})
        if self.path != "/v1/responses" or body.get("store") is not False or body.get("max_output_tokens") != 64 or body.get("input") != "test prompt":
            return self._reply(400, {"error": {"message": "request shape was wrong"}})
        self._reply(200, {"status": "completed", "output": [{"type": "message", "content": [{"type": "output_text", "text": "fixture answer"}]}]})

    def log_message(self, *_args):
        pass


if __name__ == "__main__":
    ThreadingHTTPServer(("127.0.0.1", 28768), Handler).serve_forever()
