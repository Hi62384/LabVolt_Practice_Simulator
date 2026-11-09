# AC `activate()` guard exception review — 2026-11-07

The immutable `AC_BASELINE.json` was not changed. Raw guard output is saved verbatim in `AC_GUARD_FAIL_RECEIPT.txt`:

```
AC BASELINE DIFFERENCES:
functions:scripts/game.gd::activate
```

Current `activate()` SHA-256 is `96ec39ef5b6065e7e72d4fec58a7a24fc273b202955b25348ed4df9be1fc4ad0`. The frozen baseline hash is `7a7bf056d7b14d8866949649d4161660ee6fbb13c5adf6cc6dee6284903fee68`. The current function contains the line `if is_instance_valid(washroom_finish) and washroom_finish.interact(current_target):return` exactly once, immediately after the circuit-studio route. Removing exactly that line in memory (no source edit) produces SHA-256 `7a7bf056d7b14d8866949649d4161660ee6fbb13c5adf6cc6dee6284903fee68`, byte-for-byte matching the baseline function. Thus all remaining `activate()` code, including the `kit_world`, `campus`, `shop_room`, `dc_lab`, `school_world` calls and role match arms for AC `socket`, `switch`, `control`, is unchanged.

`washroom_finish.gd::interact` first returns false for an invalid target or any role other than `washroom_fixture`. The AC equipment builder gives pick targets roles `socket`, `switch` and `control`; the AC module root and rack use their existing roles. Therefore, for all AC device targets the inserted call returns false and falls through to the unchanged branches. It does not alter the AC request arguments, priority among existing handlers, reachability or AC fallthrough. Washroom targets alone can be consumed by the new route. This is a source-semantic conclusion, not a runtime claim.

All other protected file and function hashes in `AC_BASELINE.json` match current capture: equipment builder, builder adapter, mesh cache, catalog, lab state/guide, six panel SVGs and import descriptors, and protected game functions including `_build_station`, `_build_room`, `_physics_process`, `_port_position`, `_render_wires`, `_render_stations`, `_sync_supply_controls`, `_input`, `_request`, and inspection. No AC device/resource change was found. The guard must continue to report the one-function difference; main can document this narrowly reviewed exception without regenerating or weakening the frozen baseline. No correction is needed for AC dispatch on the inspected source.
