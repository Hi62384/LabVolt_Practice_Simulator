# Dorm world static checks

Run `tools/campus/dorms/validate_dorm_world.ps1` from PowerShell. The check is
deliberately non-engine: it binds room count to the real ENet host capacity,
checks the z=68 campus connection, room stride, door clearance, stable anchor
paths, physical workstation props, and the no-per-room-light budget while the
game is active.

The integration owner should instantiate `DormHall`, add it beside `Campus`,
call `build(authoritative_player_capacity)`, and register `room_contracts` plus
`door_targets`. Ownership, replication, door authorization, and interaction UI
must remain in shared authoritative services.
