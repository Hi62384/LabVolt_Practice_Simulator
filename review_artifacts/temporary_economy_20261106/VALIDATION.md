# Offline validation record

- Scope: source-only; no Godot/engine/server process was started.
- Policy config is compile-time project source and server-wide for the current
  host, never a client/profile flag.
- The policy writes neither saves nor profiles and represents unlimited funds as
  UI text, not infinity or a large integer.
- Focused source test covers enabled/disabled purchasing, earning suppression,
  unchanged balance, invalid price/catalog, duplicate ownership, replayed
  transaction and authority rejection.
- Integration remains staged as a preimage-hashed handoff because all existing
  integration files are owned by other active workers.
