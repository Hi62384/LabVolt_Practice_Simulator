extends RefCounted

# Broad downward cones avoid the six shadow-map passes of an omni fixture.
static func ceiling_omni(parent: Node3D, diffuser_position: Vector3, energy := 1.65, reach := 5.4, shadows := true) -> void:
	var light:=down(parent,diffuser_position-Vector3(0,.055,0),energy,reach,Vector3.DOWN,68.0)
	light.name="FixtureCeilingLight"
	light.shadow_enabled=false

static func down(parent: Node3D, point: Vector3, energy: float, reach: float, aim := Vector3.DOWN, angle := 62.0) -> SpotLight3D:
	var light := SpotLight3D.new()
	light.name = "FixtureLight"
	light.transform = Transform3D(Basis.looking_at(aim, Vector3.BACK), point)
	light.light_color = Color("fff2dc")
	light.light_energy = energy
	light.light_specular = .18
	light.spot_range = reach
	light.spot_angle = angle
	light.spot_attenuation = 1.15
	light.spot_angle_attenuation = .65
	light.distance_fade_enabled=false
	light.set_meta("room_fixture", true)
	parent.add_child(light)
	return light

