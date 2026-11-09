extends Node3D
## Reusable static workstation. Session and input ownership belong to the caller.

const PALETTE := {
	"wood": "a98265", "steel": "596771", "dark": "26333d", "bezel": "17232c",
	"screen": "35566b", "key": "d5dce0", "mouse": "d5dce0", "chair": "3d6477"
}
static var shared_meshes: Dictionary = {}
static var shared_materials: Dictionary = {}

var station_id := ""
var seat_anchor: Marker3D
var interaction_anchor: Marker3D
var screen_anchor: Marker3D
var worksheet_anchor: Marker3D

func configure(id: String) -> void:
	station_id=id
	name=id
	seat_anchor=_marker("SeatAnchor",Vector3(0,0,.98))
	interaction_anchor=_marker("InteractionAnchor",Vector3(0,0,1.38))
	screen_anchor=_marker("ScreenAnchor",Vector3(0,1.17,-.17))
	worksheet_anchor=_marker("WorksheetAnchor",Vector3(-.56,.79,.15))
	_build()

func _marker(label: String, at: Vector3) -> Marker3D:
	var marker:=Marker3D.new();marker.name=label;marker.position=at;add_child(marker)
	return marker

func _build() -> void:
	var desk:=StaticBody3D.new();desk.name="Desk";desk.set_meta("role","table");desk.set_meta("label","Computer desk "+station_id);add_child(desk)
	var shape:=BoxShape3D.new();shape.size=Vector3(1.7,.08,.86)
	var hit:=CollisionShape3D.new();hit.shape=shape;hit.position=Vector3(0,.73,0);desk.add_child(hit)
	_box(desk,Vector3(0,.73,0),shape.size,"wood")
	for x in [-.76,.76]:
		for z in [-.35,.35]:_box(desk,Vector3(x,.365,z),Vector3(.055,.73,.055),"steel")
	# Monitor faces the seated user (+Z). Screen material is matte and readable.
	_box(self,Vector3(0,1.16,-.17),Vector3(.70,.43,.045),"bezel")
	_box(self,Vector3(0,1.16,-.14),Vector3(.64,.37,.006),"screen")
	_box(self,Vector3(0,.91,-.19),Vector3(.045,.08,.045),"steel")
	_box(self,Vector3(0,.83,-.19),Vector3(.24,.018,.18),"steel")
	# A shallow key tray, distinct key rows, and a mouse with two buttons.
	_box(self,Vector3(.10,.785,.19),Vector3(.48,.022,.16),"dark")
	for row in range(3):
		for key in range(9):_box(self,Vector3(-.105+key*.052,.799,.135+row*.046),Vector3(.038,.005,.029),"key")
	_box(self,Vector3(.54,.788,.19),Vector3(.075,.028,.115),"mouse")
	_box(self,Vector3(.54,.806,.16),Vector3(.004,.004,.045),"steel")
	# Side tower is kept below the tabletop and out of the seated sightline.
	_box(self,Vector3(.64,.35,-.20),Vector3(.24,.54,.40),"dark")
	for i in range(4):_box(self,Vector3(.762,.44-i*.045,-.20),Vector3(.003,.012,.24),"steel")
	_box(self,Vector3(.762,.55,-.04),Vector3(.004,.018,.018),"screen")
	# Chair back stays behind the desk and has no collision trap around the seat.
	_box(self,Vector3(0,.45,.98),Vector3(.50,.09,.47),"chair")
	_box(self,Vector3(0,.77,1.23),Vector3(.50,.60,.08),"chair")
	_box(self,Vector3(0,.24,.98),Vector3(.06,.40,.06),"steel")
	_box(self,Vector3(0,.035,.98),Vector3(.48,.05,.42),"steel")

func _box(parent: Node3D,at: Vector3,size: Vector3,key: String) -> MeshInstance3D:
	var mesh_key:=str(size)
	if not shared_meshes.has(mesh_key):
		var mesh:=BoxMesh.new();mesh.size=size;shared_meshes[mesh_key]=mesh
	if not shared_materials.has(key):
		var material:=StandardMaterial3D.new();material.albedo_color=Color(str(PALETTE[key]));material.roughness=.88
		shared_materials[key]=material
	var part:=MeshInstance3D.new();part.mesh=shared_meshes[mesh_key];part.material_override=shared_materials[key]
	part.position=at;part.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;parent.add_child(part)
	return part
