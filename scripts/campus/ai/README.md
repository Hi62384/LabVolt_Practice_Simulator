# Host OpenAI connection

The host can configure OpenAI under **Settings → Host Server → OpenAI API**. Paste a project API key for the current game process, or set `OPENAI_API_KEY` in the host process environment before starting the game. The key is never saved in `user://`, placed in a multiplayer message, or shown again after entry. The settings file stores only the model, enable switch, request limits, and daily usage count.

The default model is `gpt-5.4-mini`. The host can change the model ID and set a maximum of 16–2,048 output tokens per response, 1–10 requests per minute, and 1–200 requests per UTC day. Defaults are 384 tokens, 4 per minute, and 20 per day. The connection starts disabled. A connection check requests the selected model metadata without generating text; it still counts toward the limits. **Send Prompt** makes a Responses API request with `store: false`, no tools, and a 4,000-character input cap. Only one request can run at a time. The host client is local to the game process and has no RPC entry point.

Failures return short messages for invalid credentials, unavailable models, rate limits, timeouts, and server errors. Response bodies and API keys are never included in player-facing errors or logs. There is no automatic retry. A failed or canceled request still counts toward the game's request limits, so reconnect loops cannot bypass the host's cap. OpenAI's own account limits and billing remain independent of these game limits.

The local fixture is `tests/campus/ai/test_host_openai_client.gd` with `openai_fixture_server.py`. It checks request shape, parsing, limits, persistence, credential non-persistence, and error handling. An optional unauthenticated TLS probe checks the real OpenAI endpoint without using a key or generating a paid response.
