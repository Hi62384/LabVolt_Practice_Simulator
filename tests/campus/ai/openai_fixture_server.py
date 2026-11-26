"""Loopback Responses API fixture; no real OpenAI credential is used."""

import io
import json
import os
import wave
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


class Handler(BaseHTTPRequestHandler):
    def _reply(self, code, data):
        self._reply_bytes(code, json.dumps(data).encode(), "application/json")

    def _reply_bytes(self, code, body, content_type):
        self.send_response(code)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _authorized(self):
        return self.headers.get("Authorization") == "Bearer sk-test-12345678901234567890"

    def do_GET(self):
        if self.headers.get("Authorization") == "Bearer sk-rate-limited-12345678901234567890":
            return self._reply(429, {"error": {"message": "rate limited"}})
        if not self._authorized():
            return self._reply(401, {"error": {"message": "secret details must stay private"}})
        if self.path == "/v1/models":
            identifiers = ["gpt-5.4-mini", "gpt-6.2-astra", "gpt-4.1",
                           "gpt-3.5-turbo", "ft:gpt-4.1-mini-2025-04-14:local:custom:id",
                           "text-embedding-3-small", "fixture-future-model", "gpt-image-2.6-sunburst",
                           "gpt-4o-mini-tts", "gpt-4o-mini-transcribe", "gpt-5-nano"]
            return self._reply(200, {"object": "list", "data": [
                {"id": identifier, "object": "model"} for identifier in identifiers
            ]})
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
        if self.path == "/v1/audio/speech":
            if body.get("model") != "gpt-4o-mini-tts" or body.get("response_format") != "wav":
                return self._reply(400, {"error": {"message": "wrong speech request"}})
            data = io.BytesIO()
            with wave.open(data, "wb") as audio:
                audio.setparams((1, 2, 16000, 0, "NONE", "not compressed"))
                audio.writeframes(bytes(32000))
            return self._reply_bytes(200, data.getvalue(), "audio/wav")
        if self.path == "/v1/images/generations":
            if body != {"model": "gpt-image-2.6-sunburst", "prompt": "Draw a blue dot", "size": "1024x1024",
                        "output_format": "png", "quality": "low", "n": 1}:
                return self._reply(400, {"error": {"message": "wrong image request"}})
            png = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGNgYPgPAAEDAQAIicLsAAAAAElFTkSuQmCC"
            return self._reply(200, {"data": [{"b64_json": png}], "usage": {"input_tokens": 4, "output_tokens": 12}})
        if self.path == "/v1/chat/completions" and body.get("model") == "gpt-3.5-turbo":
            if body.get("messages") != [{"role": "user", "content": "test prompt"}]:
                return self._reply(400, {"error": {"message": "wrong chat request"}})
            return self._reply(200, {"choices": [{"message": {"content": "legacy answer"}}],
                                     "usage": {"prompt_tokens": 5, "completion_tokens": 3}})
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
            if isinstance(request_input, str) and request_input.startswith("Prepare a new classroom assessment plan"):
                plan = {"focus": "evidence", "scenarios": [37, 526, 1044]}
                return self._reply(200, {"status": "completed", "output": [{"type": "message", "content": [{"type": "output_text", "text": json.dumps(plan)}]}]})
            if request_input == "Reply with the single word Ready.":
                if body.get("model") != "gpt-5.4-mini":
                    return self._reply(403, {"error": {"message": "unavailable model"}})
                return self._reply(200, {"status": "completed", "output": [{"type": "message", "content": [{"type": "output_text", "text": "Ready"}]}]})
            if isinstance(request_input, str) and request_input.startswith("You are an assistant inside a fictional campus browser"):
                return self._reply(200, {"status": "completed", "output": [{"type": "message", "content": [{"type": "output_text", "text": '{"answer":"Page answer"}'}]}]})
            if isinstance(request_input, list) and request_input and isinstance(request_input[0], dict):
                parts = request_input[0].get("content", [])
                if len(parts) == 2 and parts[0].get("type") == "input_text" and parts[1].get("type") == "input_image" and str(parts[1].get("image_url", "")).startswith("data:image/jpeg;base64,"):
                    return self._reply(200, {"status": "completed", "output": [{"type": "message", "content": [{"type": "output_text", "text": '{"answer":"Image answer"}'}]}]})
        if self.path != "/v1/responses" or body.get("store") is not False or body.get("max_output_tokens") != 64 or body.get("input") != "test prompt":
            return self._reply(400, {"error": {"message": "request shape was wrong"}})
        if body.get("model") == "gpt-6.2-astra" and body.get("reasoning") != {"effort": "max"}:
            return self._reply(400, {"error": {"message": "wrong thinking effort"}})
        self._reply(200, {"status": "completed",
                          "usage": {"input_tokens": 10, "output_tokens": 20,
                                    "output_tokens_details": {"reasoning_tokens": 8}},
                          "output": [{"type": "message", "content": [{"type": "output_text", "text": "fixture answer"}]}]})

    def log_message(self, *_args):
        pass


if __name__ == "__main__":
    ThreadingHTTPServer(("127.0.0.1", int(os.environ.get("LABVOLT_OPENAI_FIXTURE_PORT", "28768"))), Handler).serve_forever()
