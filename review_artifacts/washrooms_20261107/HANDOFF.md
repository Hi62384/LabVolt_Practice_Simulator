# Both washrooms: private integration handoff

The registry confirms `washroom_1` is M107 at `(0, 0, 47)` with its east entrance and `washroom_2` is M206 at `(26, 5, 33)` with its west entrance. Both are 20 × 4 × 12. The new provider builds the same four-stall north bank and four-sink south bank at each origin. It mirrors the privacy return for the west entrance.

`washroom_finish.gd` is the source candidate. `stall_state.gd` holds host-only door/occupancy rules. `test_stall_state.gd` is a Godot source test for inside locking, outsider denial, inside exit, flush reach, invalid targets, and disconnect release. `INTEGRATION.patch` contains surgical edits for `scripts/game.gd`, `scripts/campus_integration.gd`, and the two registry title strings. Apply against exact current source; shared production files were not changed by this worker.

The old shared service mesh is queued for removal only after the replacement registers successfully. Zone streaming continues to own visibility of the new room roots. The M105 Gym profile remains untouched. The washroom finish adds only local decorative tap visuals; stall door state and locks are host-authoritative and replicate to peers, including late join refresh. It adds no saves or hygiene system.

Source checks passed on the current preimages and registry IDs. No Godot engine was launched here. Runtime owner should run `godot --headless --path . --script res://review_artifacts/washrooms_20261107/test_stall_state.gd` at the agreed safe boundary, then test both room entrances, stall collision/swing, inside lock/unlock, client join/disconnect, sink attachment, visual lighting, UI title, and screenshots from several angles. The current source check is not visual or multiplayer acceptance.

Potential runtime concern: the host uses the existing `game.avatars` positions for remote reach checks. Verify those positions are present and current during room interaction. Also inspect opening-door clearance with a player standing next to the toilet; adjust the door swing/stop if physics overlap is observed. The registry title patch repairs the confirmed `Â·` mojibake at its source.
