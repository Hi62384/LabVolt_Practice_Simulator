# Geometry integration patch

Preimage: `scripts/campus/world/campus_world.gd` SHA256 `5393697770EBCF3B523F6129E54FFAC66FC1951C9258E218341C1EE9B468B424`.

1. Copy `hallway_finish.gd` to `res://scripts/campus/presentation/hallway_finish.gd`.
2. In `campus_world.gd`, after the `HallwayGeometry` preload, add:

```gdscript
const HallwayFinish = preload("res://scripts/campus/presentation/hallway_finish.gd")
```

3. In `build()`, immediately after `_stairs()` and before `_elevator()`, add:

```gdscript
HallwayFinish.apply(self)
```

Recheck preimage and reconcile other lanes before applying.
