extends Node3D
## M105 cosmetic equipment adapter. Bind to FacilityController.room_event.
## Events are reliable phase changes; motion is interpolated locally on each peer.
const BAR_STATIONS := {
	"gym/benchpress": {"origin": Vector3(4, 1.25, 30.2), "travel": .32},
	"gym/squat": {"origin": Vector3(-5, 1.35, 35.8), "travel": .34},
	"gym/barbell_rack_2": {"origin": Vector3(-1.5, 1.35, 35.8), "travel": .34}
}
# Approximate hand positions relative to the bench bar's rest position, used
# when the exercising avatar is not present locally (such as first person).
const BENCH_GRIPS := {
	"incline_press":[Vector2(.31,.89),Vector2(.52,.56)],
	"overhead_press":[Vector2(-.47,1.75),Vector2(-.08,1.72)],
	"front_raise":[Vector2(-.79,1.31),Vector2(-.45,1.76)],
	"curl":[Vector2(-.685,1.558),Vector2(-.348,1.644)],
	"wrist_curl":[Vector2(-.572,1.68),Vector2(-.572,1.68)],
	"overhead_extension":[Vector2(-.084,.944),Vector2(.080,1.058)],
	"good_morning":[Vector2(-.29,1.31),Vector2(-.33,1.48)],
	"chest_supported_row":[Vector2(-.35,.77),Vector2(-.46,.56)]
}
var grip_position := Callable()
var tracked_grips := {}
var occupied: Dictionary = {}
var bars: Dictionary = {}
var target_height: Dictionary = {}
var target_depth: Dictionary = {}
var progress: Dictionary = {}
var plates: Dictionary = {}

func _ready() -> void:
	for key in BAR_STATIONS:
		var spec: Dictionary = BAR_STATIONS[key]
		var assembly := Node3D.new()
		assembly.name = key.get_file().to_pascal_case() + "Bar"
		assembly.position = spec.origin
		add_child(assembly)
		var shaft := CylinderMesh.new()
		shaft.height = 2.5
		shaft.top_radius = .035
		shaft.bottom_radius = .035
		shaft.radial_segments = 10
		var metal := _material(Color("aab8ba"), .35, .7)
		_part(assembly, shaft, Vector3.ZERO, Vector3(0, 0, PI/2), metal)
		var reach: float = 1.04
		plates[key] = []
		bars[key] = assembly
		target_height[key] = 0.0
		target_depth[key] = 0.0
	set_process(false)

func on_room_event(peer: int, event: Dictionary) -> void:
	var station := str(event.get("station", ""))
	if event.get("activity", "")=="trapped" and BAR_STATIONS.has(station):
		tracked_grips.erase(station)
		occupied[station]=peer
		var remaining:=1.0-float(event.get("progress",0.0))
		target_height[station]=-.22*remaining
		target_depth[station]=(.45+.62*remaining) if station=="gym/benchpress" else 0.0
		set_process(true);return
	if event.get("activity", "") != "exercise" or event.get("equipment", "") == "dumbbell":
		for key in occupied.keys():
			if int(occupied[key]) == peer:
				occupied.erase(key)
				tracked_grips.erase(key)
				target_height[key] = 0.0
				target_depth[key] = 0.0
				for plate in plates[key]:plate.scale = Vector3.ONE
		# Keep animating until the bar settles back to its resting height.
		set_process(true)
		return
	if not BAR_STATIONS.has(station): return
	occupied[station] = peer
	if station=="gym/benchpress":tracked_grips[station]=peer
	var diameter := clampf(.79 + float(event.get("weight", 0)) * .006, .82, 1.32)
	for plate in plates[station]:plate.scale = Vector3(diameter, 1, diameter)
	var phase:=float(event.get("phase",0))
	if station=="gym/benchpress" and str(event.get("exercise",""))=="benchpress":
		target_height[station]=lerpf(.014,-.211,phase)
		target_depth[station]=lerpf(.651,1.068,phase)
	elif station=="gym/benchpress" and BENCH_GRIPS.has(str(event.get("exercise",""))):
		var grip: Array=BENCH_GRIPS[str(event.exercise)]
		var point: Vector2=grip[0].lerp(grip[1],clampf(phase,0.0,1.0))
		target_height[station]=point.x;target_depth[station]=point.y
	elif station=="gym/squat":
		target_height[station]=-.30*phase
		target_depth[station]=0.0
	else:
		target_height[station] = float(BAR_STATIONS[station].travel) * phase
		target_depth[station]=0.0
	progress[station] = {"reps": int(event.get("reps", 0)), "phase": int(event.get("phase", 0))}
	set_process(true)

func _process(delta: float) -> void:
	var moving := false
	for key in bars:
		var bar: Node3D = bars[key]
		var target := float(target_height.get(key, 0.0))
		var depth_target:=float(BAR_STATIONS[key].origin.z)+float(target_depth.get(key,0.0))
		if tracked_grips.has(key) and grip_position.is_valid():
			var grip: Variant=grip_position.call(int(tracked_grips[key]))
			if grip is Vector3 and grip.is_finite():
				var local_grip:=to_local(grip)
				target=local_grip.y-float(BAR_STATIONS[key].origin.y)
				depth_target=local_grip.z
		var speed:=4.0 if tracked_grips.has(key) and grip_position.is_valid() else .9
		bar.position.y = move_toward(bar.position.y, float(BAR_STATIONS[key].origin.y) + target, delta * speed)
		bar.position.z=move_toward(bar.position.z,depth_target,delta*speed)
		moving = moving or absf(bar.position.y - float(BAR_STATIONS[key].origin.y) - target) > .001 or absf(bar.position.z-depth_target)>.001
	set_process(moving or not occupied.is_empty())

func _part(parent: Node3D, mesh: Mesh, pos: Vector3, rot: Vector3, mat: Material) -> void:
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.position = pos
	part.rotation = rot
	part.material_override = mat
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(part)

func _material(color: Color, roughness: float, metallic: float) -> Material:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	mat.metallic = metallic
	return mat
