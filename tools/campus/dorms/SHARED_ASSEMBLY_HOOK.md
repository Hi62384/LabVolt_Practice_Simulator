# Shared dorm assembly hook

This is staged for the main integration owner and is **not applied** by the
dorm-world slice. It changes shared campus composition.

## 1. Open the connected ground-floor portal

Target: `res://scripts/campus/world/campus_world.gd`

Authoring preimage SHA-256:
`7dada66f0d8f30eb0de950a6366476b45cd039fed8850198dd693717c9aba37e`

Exact preimage inside the `for floor in [0,1]` circulation loop:

```gdscript
box(self,Vector3(13,y+2,68),Vector3(6,4,.16),"a6b9b4")
```

Replace only that statement with:

```gdscript
if floor == 0:
	# Four-metre clear portal into the capacity-driven dorm hall.
	for x in [10.5, 15.5]:
		box(self, Vector3(x, y + 2, 68), Vector3(1.0, 4, .16), "a6b9b4")
	box(self, Vector3(13, y + 3.6, 68), Vector3(4.0, .8, .16), "34606a")
else:
	box(self, Vector3(13, y + 2, 68), Vector3(6, 4, .16), "a6b9b4")
```

This retains the upper-floor end wall and makes the ground route physically
connected. If the hash or exact preimage differs, re-review the current corridor
edge instead of applying blindly.

## 2. Assemble without duplicating authority

After `Campus` exists, add a sibling built from
`res://scripts/campus/dorms/world/dorm_hall.gd`:

```gdscript
var dorm_hall := preload("res://scripts/campus/dorms/world/dorm_hall.gd").new()
add_child(dorm_hall)
dorm_hall.build(authoritative_player_capacity)
```

Pass the live capacity derived by the shared session/network layer (currently
7 ENet clients + host = 8). Register `dorm_hall.room_contracts` and
`dorm_hall.door_targets` with the shared dorm registry/authority. Do not assign
owners or accept door input in this presentation node.

The stable target/anchor paths and room bounds are specified in
`assets/campus/dorms/dorm_layout_contract.json`.
