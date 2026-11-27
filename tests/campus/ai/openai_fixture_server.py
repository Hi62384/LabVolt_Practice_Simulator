"""Loopback Responses API fixture; no real OpenAI credential is used."""

import io
import json
import math
import os
import struct
import threading
import wave
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


class Handler(BaseHTTPRequestHandler):
    # The fixture records only fake request bodies, never authorization headers.
    # Native transport tests inspect these to verify the real HTTP envelope.
    requests = []
    request_sequence = 0
    request_lock = threading.Lock()

    def _record_request(self, body):
        with self.request_lock:
            Handler.request_sequence += 1
            Handler.requests.append({"sequence": Handler.request_sequence, "path": self.path, "body": body})
            del Handler.requests[:-256]

    def _text(self, text, status="completed", **metadata):
        return self._reply(200, {"status": status, **metadata, "output": [
            {"type": "message", "content": [{"type": "output_text", "text": text}]}]})

    @staticmethod
    def _character_input(body):
        try:
            data = json.loads(body.get("input", ""))
        except (ValueError, TypeError):
            return None
        if not isinstance(data, dict) or not isinstance(data.get("context"), dict) or not isinstance(data.get("player_dialogue"), str):
            return None
        return data

    @staticmethod
    def _interpret(request):
        # These authored fixture labels test orchestration, not semantic quality.
        hostile = "HTTP_FIXTURE_SEMANTIC_INSULT" in request
        return {"event": "insult" if hostile else "chat", "tone": "hostile" if hostile else "neutral",
                "severity": 0.9 if hostile else 0.1, "meaning": "The speaker attacks the teacher's competence." if hostile else "The speaker makes a fixture conversation request.",
                "topic": "fixture conversation", "domain": "conversation", "difficulty": 0.0,
                "assessment_request": "social", "requested_action": "", "memories": [],
                "sincere": False, "constructive": False, "topic_changed": False,
                "important": False, "current_information": False}

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
        if self.path == "/v1/fixture/requests":
            with self.request_lock:
                return self._reply(200, {"requests": list(self.requests)})
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
        self._record_request(body)
        if self.path == "/v1/audio/speech":
            if body.get("model") != "gpt-4o-mini-tts" or body.get("response_format") != "wav":
                return self._reply(400, {"error": {"message": "wrong speech request"}})
            data = io.BytesIO()
            with wave.open(data, "wb") as audio:
                audio.setparams((1, 2, 16000, 0, "NONE", "not compressed"))
                audio.writeframes(b"".join(struct.pack("<h", int(800 * math.sin(i * .09))) for i in range(16000)))
            streamed = bytearray(data.getvalue())
            streamed[4:8] = b"\xff" * 4
            streamed[40:44] = b"\xff" * 4
            return self._reply_bytes(200, streamed, "audio/wav")
        if self.path == "/v1/images/generations":
            if body != {"model": "gpt-image-2.6-sunburst", "prompt": "Draw a blue dot", "size": "1024x1024",
                        "output_format": "png", "quality": "low", "n": 1}:
                return self._reply(400, {"error": {"message": "wrong image request"}})
            png = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGNgYPgPAAEDAQAIicLsAAAAAElFTkSuQmCC"
            return self._reply(200, {"data": [{"b64_json": png}], "usage": {"input_tokens": 4, "output_tokens": 12}})
        if self.path == "/v1/chat/completions" and body.get("model") == "gpt-3.5-turbo":
            messages = body.get("messages", [])
            if messages and "HTTP_FIXTURE_CHAT_LIMIT" in str(messages[-1].get("content", "")):
                return self._reply(200, {"choices": [{"message": {"content": "An unfinished answer"}, "finish_reason": "length"}]})
            if body.get("messages") != [{"role": "user", "content": "test prompt"}]:
                return self._reply(400, {"error": {"message": "wrong chat request"}})
            return self._reply(200, {"choices": [{"message": {"content": "legacy answer"}}],
                                     "usage": {"prompt_tokens": 5, "completion_tokens": 3}})
        if self.path == "/v1/moderations":
            if body.get("model") != "omni-moderation-latest":
                return self._reply(400, {"error": {"message": "bad moderation model"}})
            return self._reply(200, {"results": [{"flagged": body.get("input") == "flag this"}]})
        instructions = str(body.get("instructions", ""))
        if self.path == "/v1/responses" and instructions.startswith("Interpret one perceived interaction"):
            character_input = self._character_input(body)
            if character_input is None or body.get("store") is not False or int(body.get("max_output_tokens", 0)) < 900:
                return self._reply(400, {"error": {"message": "invalid semantic character envelope or budget"}})
            if "TEST_INJECTION" in instructions:
                return self._reply(400, {"error": {"message": "player input reached semantic instructions"}})
            return self._text(json.dumps(self._interpret(character_input["player_dialogue"])))
        if self.path == "/v1/responses" and (
                "You are teaching a simulator classroom" in instructions
                or str(body.get("input", "")).startswith("You are teaching a simulator classroom")):
            if body.get("store") is not False:
                return self._reply(400, {"error": {"message": "visual requests must not be stored"}})
            prompt = body["input"]
            request = json.loads(prompt)["player_dialogue"] if instructions else prompt.split(" Student request: ")[-1]
            if "pause" in request.lower() and "cue" not in request.lower():
                plan = {"speech": "I have paused the moving arrow.", "action": {"op": "pause"}}
            elif "twice" in request.lower():
                plan = {"speech": "The frequency is now twice as high.",
                        "action": {"op": "parameter", "id": "frequency", "value": 2}}
            else:
                plan = {"speech": "Watch how the arrow's angle changes with time.", "action": {"op": "create", "scene": {
                    "version": 1, "title": "Rotating phasor", "duration": 12, "loop": True,
                    "parameters": {"frequency": [1, 0.2, 3]},
                    "objects": [
                        {"type": "circle", "id": "dial", "x": 300, "y": 285, "radius": 150, "color": "82c8dc"},
                        {"type": "arrow", "id": "phasor", "x": 300, "y": 285, "width": 145,
                         "height": 0, "color": "ffc671", "bindings": {"rotation": "t * 90 * frequency"}},
                        {"type": "graph", "id": "wave", "x": 495, "y": 140, "width": 415, "height": 290,
                         "color": "46dfc1", "function": "sin(u * frequency)"},
                    ],
                }}}
                if "pause cue" in request.lower():
                    plan["action"]["scene"]["cues"] = [
                        {"id": "inspect", "at": 1.25, "label": "Inspect the phasor", "pause": True}
                    ]
            if "HTTP_FIXTURE_VISUAL_LONG" in request:
                plan["speech"] = "The arrow and the graph show the same cycle from two different viewpoints. " * 16
                plan["speech"] = plan["speech"].strip()
                plan.update(memory="", memories=[], biography=None, biography_facts=[], belief_updates=[])
            return self._reply(200, {"status": "completed", "output": [
                {"type": "message", "content": [{"type": "output_text", "text": json.dumps(plan)}]}]})
        if self.path == "/v1/responses" and (
            instructions.startswith("You are ")
            or str(body.get("input", "")).startswith(("You are a fictional classroom instructor", "Speak in character as this classroom instructor"))
        ):
            if instructions:
                character_input = self._character_input(body)
                if character_input is None:
                    return self._reply(400, {"error": {"message": "missing character context or player dialogue"}})
                if "TEST_INJECTION" in instructions:
                    return self._reply(400, {"error": {"message": "player content reached trusted instructions"}})
            if body.get("store") is not False:
                return self._reply(400, {"error": {"message": "request stored"}})
            request = character_input["player_dialogue"] if instructions else str(body.get("input", ""))
            if "HTTP_FIXTURE_OUTPUT_LIMIT" in request:
                return self._text('{"speech":"An unfinished answer', "incomplete", incomplete_details={"reason": "max_output_tokens"})
            if "HTTP_FIXTURE_UNFINISHED_RESPONSE" in request:
                return self._text("A response that must not be delivered", "incomplete", incomplete_details={"reason": "content_filter"})
            if "HTTP_FIXTURE_TRUNCATED_HTTP" in request:
                return self._reply_bytes(200, b'{"status":"completed","output":[', "application/json")
            if "HTTP_FIXTURE_OVERSIZED_TEXT" in request:
                return self._text("A complete fixture sentence. " * 650)
            if "HTTP_FIXTURE_BAD_DIALOGUE_JSON" in request:
                return self._text('{"speech":"This JSON never closes')
            answer = "The board shows a current path."
            if "HTTP_FIXTURE_LONG_SPEECH" in request:
                answer = ("This complete sentence belongs to a long fixture explanation. " * 20).strip()
            if "Return JSON with speech," in instructions:
                if "decision" not in character_input["context"]:
                    return self._reply(400, {"error": {"message": "missing authoritative character decision"}})
                if int(body.get("max_output_tokens", 0)) < 1400:
                    return self._reply(400, {"error": {"message": "character speech budget is too small"}})
                answer = json.dumps({"speech": answer, "event": "", "memory": "", "memories": [],
                                     "biography": None, "biography_facts": [], "belief_updates": []})
            return self._reply(200, {"status": "completed", "output": [{"type": "message", "content": [{"type": "output_text", "text": answer}]}]})
        if self.path == "/v1/responses" and body.get("store") is False:
            request_input = body.get("input")
            if isinstance(request_input, str) and request_input.startswith("Choose one answer."):
                if (body.get("model") != "gpt-5.4-mini" or body.get("service_tier") != "default"
                        or body.get("max_output_tokens") != 512 or body.get("reasoning") != {"effort": "low"}):
                    return self._reply(400, {"error": {"message": "comparison request shape was wrong"}})
                return self._reply(200, {"status": "completed", "model": "gpt-5.4-mini-2026-03-17",
                                         "service_tier": "default", "reasoning": {"effort": "low"},
                                         "usage": {"input_tokens": 10, "output_tokens": 20,
                                                   "output_tokens_details": {"reasoning_tokens": 8}},
                                         "output": [{"type": "message", "content": [{"type": "output_text", "text": "B"}]}]})
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
