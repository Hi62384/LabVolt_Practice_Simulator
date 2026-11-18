extends RefCounted

# Broad downward cones avoid the six shadow-map passes of an omni fixture.
static func ceiling_omni(parent: Node3D, diffuser_position: Vector3, energy := 1.65, reach := 5.4, shadows := false) -> SpotLight3D:
	var light:=down(parent,diffuser_position-Vector3(0,.055,0),energy,reach,Vector3.DOWN,68.0)
	light.name="FixtureCeilingLight"
	light.shadow_enabled=shadows
	light.shadow_bias=.055
	light.shadow_normal_bias=.85
	light.shadow_blur=1.45
	return light

static func down(parent: Node3D, point: Vector3, energy: float, reach: float, aim := Vector3.DOWN, angle := 68.0, tint := Color("fff3e5")) -> SpotLight3D:
	var light := SpotLight3D.new()
	light.name = "FixtureLight"
	light.transform = Transform3D(Basis.looking_at(aim, Vector3.BACK), point)
	light.light_color = tint
	light.light_energy = energy * 1.55
	light.light_specular = .66
	light.spot_range = reach * 1.18
	light.spot_angle = angle
	light.spot_attenuation = 1.05
	light.spot_angle_attenuation = .62
	light.distance_fade_enabled=false
	light.set_meta("ultra_distance_fade", true)
	light.distance_fade_begin=34.0
	light.distance_fade_length=6.0
	light.distance_fade_shadow=12.0
	# Reuse a fixed set of ceiling shadow maps as the camera moves.
	if aim == Vector3.DOWN:
		var index := int(parent.get_meta("ceiling_fixture_count", 0))
		parent.set_meta("ceiling_fixture_count", index + 1)
		light.set_meta("ultra_shadow_fixture", index % 3 == 0)
	light.set_meta("room_fixture", true)
	parent.add_child(light)
	return light


# Short local fill simulates light spilling back toward the fixture housing.
static func ceiling_spill(parent: Node3D, point: Vector3, tint := Color("fff0dd")) -> void:
	var light := OmniLight3D.new()
	light.name="CeilingSpill"
	light.position=point
	light.light_color=tint
	light.light_energy=.30
	light.light_specular=0.0
	light.omni_range=1.50
	light.omni_attenuation=1.6
	light.set_meta("room_fixture",true)
	parent.add_child(light)
