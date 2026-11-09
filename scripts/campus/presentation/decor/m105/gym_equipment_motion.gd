extends Node3D
## M105 cosmetic equipment adapter. Bind to FacilityController.room_event.
## Events are reliable phase changes; motion is interpolated locally on each peer.
const BAR_STATIONS := {
	"gym/benchpress": {"origin": Vector3(4, 1.25, 30.2), "travel": .32},
	"gym/squat": {"origin": Vector3(-5, 1.35, 35.8), "travel": .34},
	"gym/curl": {"origin": Vector3(-.5, .82, 35.3), "travel": .3}
}
var occupied: Dictionary = {}
var bars: Dictionary = {}
var target_height: Dictionary = {}
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
		shaft.height = 2.5 if key != "gym/curl" else .62
		shaft.top_radius = .035
		shaft.bottom_radius = .035
		shaft.radial_segments = 10
		var metal := _material(Color("aab8ba"), .35, .7)
		_part(assembly, shaft, Vector3.ZERO, Vector3(0, 0, PI/2), metal)
		var reach: float = 1.04 if key != "gym/curl" else .25
		plates[key] = []
		for side in [-1.0, 1.0]:
			for index in 2:
				var plate := CylinderMesh.new()
				plate.height = .105
				plate.top_radius = .25 if key != "gym/curl" else .14
				plate.bottom_radius = plate.top_radius
				plate.radial_segments = 16
				_part(assembly, plate, Vector3(side * (reach + index * .11), 0, 0), Vector3(0,0,PI/2), _material(Color("343c40"), .9, 0))
				plates[key].append(assembly.get_child(-1))
		bars[key] = assembly
		target_height[key] = 0.0
	set_process(false)

func on_room_event(peer: int, event: Dictionary) -> void:
	var station := str(event.get("station", ""))
	if event.get("activity", "") != "exercise":
		for key in occupied.keys():
			if int(occupied[key]) == peer:
				occupied.erase(key)
				target_height[key] = 0.0
				for plate in plates[key]:plate.scale = Vector3.ONE
		# Keep animating until the bar settles back to its resting height.
		set_process(true)
		return
	if not BAR_STATIONS.has(station): return
	occupied[station] = peer
	var diameter := clampf(.79 + float(event.get("weight", 0)) * .006, .82, 1.32)
	for plate in plates[station]:plate.scale = Vector3(diameter, 1, diameter)
	target_height[station] = float(BAR_STATIONS[station].travel) * float(event.get("phase", 0))
	progress[station] = {"reps": int(event.get("reps", 0)), "phase": int(event.get("phase", 0))}
	set_process(true)

func _process(delta: float) -> void:
	var moving := false
	for key in bars:
		var bar: Node3D = bars[key]
		var target := float(target_height.get(key, 0.0))
		bar.position.y = move_toward(bar.position.y, float(BAR_STATIONS[key].origin.y) + target, delta * .9)
		moving = moving or absf(bar.position.y - float(BAR_STATIONS[key].origin.y) - target) > .001
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
