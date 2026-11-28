# OpenAI model catalog integration checkpoint — 2026-11-27

This work builds on the combined audio and character dossier integration at `0b8e8f78c56172a3acbf29c2ecf761e5a636a4ec`. It does not replace approved character voices, player profiles or persistent memories.

## Implemented

- Recommended, advanced, deprecated/retired, snapshot and account-listed model filters, explicit refresh, and preservation of the selected model even when filters hide it. Unimplemented transports are identified and cannot be selected.
- Updated text/vision, image, voice and transcription catalog entries, lifecycle metadata, published price units, and support for additional documented audio price schedules. Character-generation requests use text pricing.
- GPT-Audio 1.5 speech through Chat Completions with a WAV response and mandatory transcript comparison before playback. Existing Realtime fixed-line speech and Live delegated character speech remain available.
- GPT-Live-Transcribe and GPT-Realtime-Whisper through a dedicated Realtime transcription WebSocket. The existing host-owned microphone flow submits a completed utterance; the adapter resamples PCM to 24 kHz, appends bounded chunks, commits one turn, matches item IDs, and rejects mismatched/stale output. The AI test dialog displays partial transcription where supplied.
- Persisted, model-validated PNG image generation dimensions and quality. Existing square/low defaults are preserved.
- Loopback fixtures and regression tests for the catalog, streaming transcription, GPT-Audio speech, mismatch rejection, existing voice adapters, and the native Live bridge. The runner requires the pass markers in addition to exit status.

## Scope remaining / limitations

- No native Godot/.NET runtime is installed in the current execution environment and the Windows command tunnel is offline. The new tests have been authored but not executed here. No real OpenAI account was used, so actual provider access, latency, acoustic quality and hardware microphone behavior have not been verified.
- The new WebSocket transcription transport currently starts after local speech capture completes; it does not yet forward microphone frames continuously while a player is speaking.
- Native conversational delegation is implemented for GPT-Live, not for the newly documented Realtime conversation options. Realtime remains available for fixed-line speech. Unsupported conversation models are disabled in the selector.
- Embedding models and their published rates are catalogued; optional semantic retrieval against persistent character memories is not implemented. Existing local retrieval remains authoritative.
- PNG generation supports a bounded set of sizes/qualities. Image editing, reference-image generation, additional output formats and transparency controls remain out of scope for this checkpoint.
- Live standby rates are documented but standby-versus-active accounting is not fully integrated. Existing usage tracking is retained and unknown costs must not be represented as measured zero.
- This is a partial implementation of the full model-catalog specification, not a claim that all requested acceptance criteria have passed.

## Sources consulted

- https://developers.openai.com/api/docs/models
- https://developers.openai.com/api/docs/pricing
- https://developers.openai.com/api/docs/deprecations
- https://developers.openai.com/api/docs/guides/realtime-transcription
- https://developers.openai.com/api/docs/guides/live
- https://developers.openai.com/api/docs/models/gpt-audio-1.5
- https://developers.openai.com/api/docs/guides/image-generation
- https://developers.openai.com/api/docs/guides/embeddings

## Native regression command

With Godot 4.5.1 Mono, the project imported, and its C# assembly built:

```powershell
python -m pip install aiohttp
python tests/campus/ai/run_voice_provider_tests.py --godot "<path-to-Godot-console-executable>"
```

The runner uses loopback-only credentials and isolated local user data. Real-provider smoke tests require a host-configured key and explicit user consent.
