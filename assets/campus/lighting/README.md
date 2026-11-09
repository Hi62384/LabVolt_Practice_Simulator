# Campus lighting rig

`campus_lighting_rig.tscn` provides the campus sky, ambient fill, filmic tonemapping,
and its single shadow-casting directional light. It is authored for this project's
GL Compatibility renderer; it intentionally avoids volumetric fog, SDFGI, glow,
and arrays of dynamic room lights.

Minimal integration into the shared campus/world owner:

```gdscript
const CAMPUS_LIGHTING := preload("res://assets/campus/lighting/campus_lighting_rig.tscn")

func _ready() -> void:
	add_child(CAMPUS_LIGHTING.instantiate())
	build()
```

If a clock exists, drive the rig rather than creating another environment or sun:

```gdscript
var lighting := get_node("CampusLightingRig") as CampusLightingRig
lighting.set_time_of_day(simulation_hour) # 0.0 .. 24.0
```

Graphics settings may call `set_lighting_enabled(false)` for a full lighting
disable. Changing `brightness_scale` preserves the day/night color balance.
