# AI instructors

The host enables OpenAI in the session setup. A configured key and enabled AI teaching allow class to start. The first successful class request verifies the connection. The teacher uses the current curriculum stage for short explanations and answers. A student near the instructor can type or record a question in the conversation panel. Students can also raise their hand during a lecture and speak when called on. Questions and generated replies are moderated before a reply is shown. Conversation text and captions format common inline math, including fractions, roots, exponents and electrical notation.

Automatic conversation listening is a separate opt-in under Audio. During a teacher conversation, the game listens for speech and sends detected turns through the host's transcription route. Escape or leaving the conversation area stops listening. Speech output uses the host's selected OpenAI voice model when enabled. Local voices and subtitles remain available.

The host supplies course, week, lesson title, personality and the current authored board stage. The model cannot change grades, course state, inventory or the board. Replies are discarded when a class ends or the instructor changes. The host checks roster membership, room and distance before each request and publishes replies through its existing teacher reaction RPC. In freeplay, nearby lab instructors can answer without lesson board context.

Host Server settings can create up to 12 original fictional instructors per session. Profiles are validated, sent to connected players, and enter the eligible course roster. Generated instructors use the existing local voice fallback. They are cleared when the session ends.

The OpenAI connection is disabled by default and uses the host's API key and request limits. Typed questions, lesson context and recorded speech are sent to OpenAI during the relevant interaction. Audio is kept in memory for the request. The host saves bounded recent teacher dialogue and relationship history by teacher and student identity. The host pays for API usage. Authored teacher dialogue remains available when the service fails.

Fixture: run `tests/campus/ai/openai_fixture_server.py` and `tests/campus/ai/test_teacher_ai.gd` with isolated Godot user data. The fixture uses no real API key. The required menu smoke remains `tests/menu_startup/test_menu_routes.gd`.
