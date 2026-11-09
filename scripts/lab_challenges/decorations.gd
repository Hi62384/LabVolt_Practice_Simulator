extends RefCounted
const DEFINITIONS := {"team_plaque":{"name":"Teamwork plaque","count":1,"kind":"","text":"TEAM / VOLT","color":"80dfc5"},"phasor_print":{"name":"Phasor honours print","count":3,"kind":"","text":"PHASOR TEAM\n0° · −120° · +120°","color":"7caef2"},"pf_badge":{"name":"Reactive power award","count":5,"kind":"power_factor","text":"PF / TEAMWORK","color":"f0ca6b"},"motor_honours":{"name":"Motor diagnostics honours","count":8,"kind":"motor_open_phase","text":"MOTOR HONOURS","color":"d8a4de"}}
# Baseline AC laboratory backboards: fixtures sit above instruments, never on
# walking surfaces, connectors, stairs or doors. Cosmetic meshes have no collision.
const ANCHORS := {"left_award":Vector3(-1.5,3.98,-3.17),"right_award":Vector3(1.5,3.98,-3.17)}
static func unlocks(profile: Dictionary) -> Array:
	var result: Array=[]
	for id in DEFINITIONS:
		var rule: Dictionary=DEFINITIONS[id]
		if int(profile.get("count",0))>=int(rule.count) and (rule.kind=="" or int(profile.get("kinds",{}).get(rule.kind,0))>0):result.append(id)
	return result
static func render(parent: Node3D, station: int, choices: Dictionary) -> Node3D:
	var root := Node3D.new();root.name="ChallengeDecorations";parent.add_child(root)
	if station<0 or station>2:return root
	var offset := Vector3([0.0,-6.0,6.0][station],0,0)
	for anchor in ANCHORS:
		var id := str(choices.get(anchor,{}).get("id",""))
		if not DEFINITIONS.has(id):continue
		var definition: Dictionary=DEFINITIONS[id]
		var mesh := MeshInstance3D.new();var box := BoxMesh.new();box.size=Vector3(1.05,.28,.025);mesh.mesh=box;mesh.position=ANCHORS[anchor]+offset;mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var material := StandardMaterial3D.new();material.albedo_color=Color("18313c");material.roughness=.9;mesh.material_override=material;root.add_child(mesh)
		var label := Label3D.new();label.text=definition.text;label.font_size=60;label.pixel_size=.0016;label.modulate=Color(definition.color);label.position=mesh.position+Vector3(0,0,.018);label.no_depth_test=false;root.add_child(label)
	return root
