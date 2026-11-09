# Mount patch for main integration owner

Preimage: `scripts/campus/dorms/world/dorm_hall.gd` SHA-256
`2aafa8a9bb6c7452459a3c7f1b19b637954f454b314c5c96f1263750b0d24d1c`.

Copy `dorm_hall_finish.gd` into `scripts/campus/dorms/world/` after review.
After the existing `for contract in room_contracts: _build_room(contract)` loop
in `DormHall.build`, append:

```gdscript
var finish := preload("res://scripts/campus/dorms/world/dorm_hall_finish.gd").new()
finish.install(self, room_contracts)
```

The provider creates only noncolliding visuals. Existing door bodies, pivots,
collision, IDs, assignment, and synchronized `PI/2` rotation stay authoritative.
Do not mount twice. Visually verify both side swings, all door plaques, tile
seams, end bench clearance, and the entry transition before adopting.
