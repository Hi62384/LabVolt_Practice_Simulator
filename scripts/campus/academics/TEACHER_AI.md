# AI instructors

The host enables the OpenAI connection in Host Server settings. With a key and the toggle on, each active class board stage can receive a short generated teaching point. A student within four metres of the instructor can type a question or deliberately record up to six seconds of speech in the instructor conversation panel. The recording is transcribed by the host through OpenAI, then the transcript follows the same question route. Questions and generated replies are moderated before a reply is shown. Teacher speech and subtitles use the existing local voice settings.

The host supplies course, week, lesson title, personality and the current authored board stage. The model cannot change grades, course state, inventory or the board. Replies are discarded when a class ends or the instructor changes. The host checks roster membership, room and distance before each request and publishes replies through its existing teacher reaction RPC. In freeplay, nearby lab instructors can answer without lesson board context.

Host Server settings can create up to 12 original fictional instructors per session. Profiles are validated, sent to connected players, and enter the eligible course roster. Generated instructors use the existing local voice fallback. They are cleared when the session ends.

The OpenAI connection is disabled by default and uses the host's API key and request limits. Typed questions, transcribed speech, lesson context and audio recordings are sent to OpenAI only after the relevant action. Recordings are kept in memory for that request, not saved as game files. The host pays for API usage. If the API, moderation or transcription fails, the game keeps its authored offline teacher dialogue available.

Fixture: run `tests/campus/ai/openai_fixture_server.py` and `tests/campus/ai/test_teacher_ai.gd` with isolated Godot user data. The fixture uses no real API key. The required menu smoke remains `tests/menu_startup/test_menu_routes.gd`.
