# Room integration correction

Use `room_interior.gd` and `room_adapter.gd` from this directory as the room owner's current candidate. The authority assembly in `authority/candidate/scripts/campus/dorms/` captured an earlier room adapter; reconcile this one-line computer correction before adopting it. Its `computer` interaction must call `authority.request_personal_computer(room_id)`. The coordinator already binds station IDs as `personal_` plus the physical bay and enforces authenticated owner access. A fabricated `dorm_` station ID cannot open the desktop.

The coordinator's current `_sync_interiors` binds the four personal callables, registers the host bed anchor, and streams occupied rooms. Its `_open_wardrobe` uses the existing editor host; `_open_storage` sends actual dorm intents. Preserve those authority-owned hooks and their host checks. This renderer does not alter persistent profile or ledger state.

The visual target collection exposes `bed`, `study_chair`, `computer`, `wardrobe`, `storage`, `kit_workshop`, `loadout`, `notes`, `bedside_lamp`, and `desk_lamp`. The kit, backpack and papers remain at the existing world anchor positions. The rest owner registers `bed.global_transform` plus local `(0,.16,.85)` as the foot anchor. This candidate uses the bed target at its geometric center, so confirm its foot direction and capsule stand point in the guarded runtime pass.

Source check: current candidate computer call matches the authority coordinator method; `rg` failed once because a PowerShell command passed a literal `*.gd` path to rg on Windows, not because a source test failed. No engine parser, visual screenshots or live saves were used here. Runtime collision, station reach, rest pose and UI behavior remain acceptance gates.
