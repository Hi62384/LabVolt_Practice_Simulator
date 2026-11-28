# Provider invocation comparison

The same `test_character_request_accounting.gd` probe ran successfully on the
pre-dossier baseline `7ec6c95241fca70e724783d6234dc3f445a6630c` and the integration
tree. It invokes the actual production preparation and generation pipeline
for one ordinary greeting. A deterministic, zero-network provider records
which methods the production pipeline calls; it returns a valid structured
reply and does not supply fabricated token usage.

| Observed protocol | Baseline | Current |
| --- | --- | --- |
| Invocation order | Input moderation → interpretation → dialogue → output moderation | Input moderation → combined dialogue → output moderation |
| Interpretation/dialogue model invocations | 2 | 1 |
| Moderation invocations | 2 | 2 |
| Structured context payloads | 9,218 and 10,550 UTF-8 bytes | 6,827 UTF-8 bytes |
| Measured local pipeline execution for this probe | 1.483 ms | 3.139 ms |
| Actual remote input/output tokens | Unavailable | Unavailable |
| Remote response or speech latency | Unavailable | Unavailable |

The response passed production validation in both versions. The current
ordinary turn reuses its combined interpretation/dialogue draft and retains
both required moderation calls. These counts exclude generation of a new
character, exceptional repairs, consequential consistency review and
independent perception by a second character.

Payload sizes above measure only serialized context bytes. They exclude the
instruction prefix and API wrapper and must not be reported as token counts.
The local timings include production retrieval and validation around an
instantaneous provider fixture. They are single observations, not averages,
network latency or user-perceived response time. The extra local retrieval
work is visible in these measurements; no claim is made that this probe proves
a particular end-to-end speedup.

Unmodified logs and the machine-readable comparison are in
`request-accounting/`. Live API generation time, actual token usage, speaking
quality and microphone-to-audio latency require configured credentials and
the separate live acceptance harness. This environment did not provide them.
