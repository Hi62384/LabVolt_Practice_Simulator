# Room integration handoff

Copy `computer_station.gd` and `m203_room.gd` to `res://scripts/campus/presentation/decor/computer_rooms/` without editing the staged sources. In `scripts/campus_integration.gd`, add:

```gdscript
var m203_room: Node3D
```

near the existing finish fields. Immediately after `room_finish_results.m103=...`, add:

```gdscript
	m203_room=preload("res://scripts/campus/presentation/decor/computer_rooms/m203_room.gd").new()
	add_child(m203_room)
	room_finish_results.m203=m203_room.mount(game.campus,game.campus.registry)
```

The exact preimage for this insertion is the current `scripts/campus_integration.gd` block:

```gdscript
	var m103_finish=preload("res://scripts/campus/presentation/decor/m103_room_finish.gd").new()
	add_child(m103_finish)
	room_finish_results.m103=m103_finish.mount(game.campus,game.campus.registry)
	service_decor=preload("res://scripts/campus/presentation/decor/service_rooms/service_room_decor.gd").new()
```

For session owner, `m203_room.stations` maps station IDs to nodes; anchor markers are described in `STATION_CONTRACT.md`. Teaching adapter owner may attach to `m203_room.root.get_node("TeachingDisplayMount")` after successful mount. Do not add a static display panel over the existing live academic whiteboard. The room mount only creates geometry and anchors; interactions remain with the session owner.

Current `teaching_finish` and `reference_finish` already mount M203. Their trim and light meshes can coexist, though the integration owner may remove `computer` from those two approved ID lists if the duplicate visual layers are too heavy. Keep the M101 lists and behavior unchanged.
