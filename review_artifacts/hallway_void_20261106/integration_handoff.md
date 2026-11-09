# Hallway void safety handoff — 2026-11-06

## Root cause and applied repair

The continuous corridor floor is only six metres wide (`x=10..16`). Room shells provide the visible/colliding edge walls, but their Z bounds do not meet. Seven uncovered Z spans therefore appeared to be hallway openings and had no floor beyond the corridor edge. `campus_world.gd` now installs 14 visible/colliding wall sections (both corridor edges) for exactly those spans through `hallway_geometry.gd`.

Door openings, the stair footprint, and the east elevator entrance (`x>=15.75, z=56..60`) are excluded. No colliders overlap existing room walls, and no new walkable floor surface was layered over an old one.

## Reserved player integration

`first_person.gd` was not edited. `first_person_safe_recovery.patch` is bound to preimage SHA-256 `BD9BC5A028B154DBF71D99810E1B16D90BC0D42DFDB7C20630097A2AC63156D4`. It records only grounded points inside known campus bounds and recovers below `y=-8`; it resets velocity and relies on the existing owning-peer pose stream. It contains no RPC, reward, inventory, ledger, course, or session mutation.

## Protected layout contract

`protected_bounds.json` is the decor/lighting placement contract. Keep all listed circulation volumes clear and preserve a radius-0.27 m capsule path through every declared room door.

## Verification performed

- `tests/campus/navigation_safety/test_geometry_contract.ps1`: PASS — all 14 room doors are clear of the seven closure spans; stairs/elevator stay open.
- `tests/campus/navigation_safety/test_recovery_contract.ps1`: PASS — recovery patch is preimage-bound and pose-only.
- Godot/physics/runtime: intentionally not run because the user is actively playing.
- Screenshot: referenced Library asset could not be materialized from the delegated environment; no caption was treated as pixel inspection.

## Content hashes (SHA-256)

- `scripts/campus/world/campus_world.gd`: `7DADA66F0D8F30EB0DE950A6366476B45CD039FED8850198DD693717C9ABA37E`
- `scripts/campus/presentation/navigation_safety/hallway_geometry.gd`: `5FDE2BA5674349F0C69E652AEE1A0AB4D9D6E6CA74D8C45C9E0E689E5AA81637`
- `scripts/campus/presentation/navigation_safety/safe_recovery.gd`: `9EC2C882D8711E22E52C0B2B7E8E7DD1EF0083B10CF3B09C9779BAEB4A165EA4`
- `tests/campus/navigation_safety/test_geometry_contract.ps1`: `976A5AA0A381187BF53512E31AEB3A762E920CBBA9E3CF95DDB1166CF7B3C0E6`
- `tests/campus/navigation_safety/test_recovery_contract.ps1`: `A54C0EBF3B68724B84DDAEA009C82831C2BB1A1811550B2DED782C377EBCB590`
- `review_artifacts/hallway_void_20261106/protected_bounds.json`: `9912B68D81F97F0967B3C4892DCC0B50568C0D094CFC3827CB4BD77A71945169`
- `review_artifacts/hallway_void_20261106/first_person_safe_recovery.patch`: `039ED999BDDB7FC7F295318326DCAC13605789803E27ED99E4BC6F5DDC7A0466`
