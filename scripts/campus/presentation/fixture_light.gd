extends RefCounted

static func ceiling_omni(parent: Node3D, diffuser_position: Vector3, energy := 1.65, reach := 5.4, shadows := true) -> void:
	var light := OmniLight3D.new()
	light.name = "FixtureOmniLight"
	light.position = diffuser_position - Vector3(0, .055, 0)
	light.light_color = Color("fff2dc")
	light.light_energy = energy
	light.light_specular = .15
	light.omni_range = reach
	light.omni_attenuation = 1.15
	light.shadow_enabled = shadows
	light.set_meta("room_fixture", true)
	parent.add_child(light)

static func down(parent: Node3D, point: Vector3, energy: float, reach: float, aim := Vector3.DOWN, angle := 62.0) -> SpotLight3D:
	var light := SpotLight3D.new()
	light.name = "FixtureLight"
	light.transform = Transform3D(Basis.looking_at(aim, Vector3.BACK), point)
	light.light_color = Color("fff2dc")
	light.light_energy = energy
	light.light_specular = .18
	light.spot_range = reach
	light.spot_angle = angle
	light.spot_attenuation = .85
	light.spot_angle_attenuation = .65
	light.set_meta("room_fixture", true)
	parent.add_child(light)
	return light

