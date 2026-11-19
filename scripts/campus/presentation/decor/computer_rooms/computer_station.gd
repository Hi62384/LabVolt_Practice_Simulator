extends Node3D
## Reusable static workstation. Session and input ownership belong to the caller.

const PALETTE := {
	"wood": "a98265", "steel": "596771", "dark": "26333d", "bezel": "17232c",
	"screen": "08090b", "key": "bdc8d0", "mouse": "c9d1d7", "chair": "3d6477",
	"edge":"697984", "vent":"161d24", "usb":"577b9b", "button":"718392", "rubber":"28333a"
}
static var shared_meshes: Dictionary = {}
static var shared_materials: Dictionary = {}
static var keyboard_keys: MultiMesh

var station_id := ""
var seat_anchor: Marker3D
var interaction_anchor: Marker3D
var screen_anchor: Marker3D
var worksheet_anchor: Marker3D
var screen: MeshInstance3D
var power_led: MeshInstance3D
var screen_material: StandardMaterial3D
var led_material: StandardMaterial3D
var baked_floor_shadows := false

func configure(id: String, use_baked_floor_shadows := false) -> void:
	station_id=id
	baked_floor_shadows=use_baked_floor_shadows
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
	_box(desk,Vector3(0,.73,0),shape.size,"wood",true)
	for x in [-.76,.76]:
		for z in [-.35,.35]:_box(desk,Vector3(x,.365,z),Vector3(.055,.73,.055),"steel",true)
	_box(self,Vector3(0,1.16,-.17),Vector3(.70,.43,.045),"bezel",true)
	var panel := QuadMesh.new()
	panel.size=Vector2(.657,.370)
	screen=MeshInstance3D.new()
	screen.name="DesktopDisplay"
	screen.mesh=panel
	screen.position=Vector3(0,1.165,-.139)
	screen.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	screen_material=StandardMaterial3D.new()
	screen_material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	screen.material_override=screen_material
	add_child(screen)
	_box(self,Vector3(0,.947,-.146),Vector3(.70,.012,.012),"edge")
	_box(self,Vector3(0,.870,-.22),Vector3(.063,.18,.063),"steel")
	_box(self,Vector3(0,.783,-.20),Vector3(.27,.018,.18),"steel")
	_box(self,Vector3(0,.913,-.197),Vector3(.10,.038,.05),"edge")
	_box(self,Vector3(.10,.785,.19),Vector3(.49,.022,.175),"dark")
	if keyboard_keys==null:
		var key_mesh := BoxMesh.new()
		key_mesh.size=Vector3(.030,.008,.028)
		keyboard_keys=MultiMesh.new()
		keyboard_keys.transform_format=MultiMesh.TRANSFORM_3D
		keyboard_keys.mesh=key_mesh
		keyboard_keys.instance_count=42
		var index := 0
		for row in range(4):
			for key in range(12):
				if row==3 and key in range(3,9):continue
				keyboard_keys.set_instance_transform(index,Transform3D(Basis.IDENTITY,Vector3(-.108+key*.038,.800,.128+row*.039)))
				index+=1
	var key_bank := MultiMeshInstance3D.new()
	key_bank.multimesh=keyboard_keys
	key_bank.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(key_bank)
	_box(self,Vector3(.101,.800,.245),Vector3(.211,.008,.028),"key")
	key_bank.material_override=shared_materials["key"]
	_box(self,Vector3(.531,.774,.177),Vector3(.17,.004,.17),"rubber")
	var mouse := MeshInstance3D.new()
	var shell := CapsuleMesh.new()
	shell.radius=.036
	shell.height=.11
	mouse.mesh=shell
	mouse.rotation.x=PI*.5
	mouse.scale.z=.40
	mouse.position=Vector3(.54,.793,.19)
	mouse.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mouse)
	mouse.material_override=shared_materials.get("key")
	_box(self,Vector3(.54,.807,.157),Vector3(.005,.008,.025),"steel")
	_box(self,Vector3(.50,.91,-.16),Vector3(.22,.27,.32),"dark",true)
	_box(self,Vector3(.50,.91,.004),Vector3(.205,.25,.014),"bezel")
	_box(self,Vector3(.50,.777,-.16),Vector3(.24,.014,.34),"steel")
	for i in range(6):
		_box(self,Vector3(.612,.875-i*.015,-.148),Vector3(.006,.006,.214),"vent")
		_box(self,Vector3(.51,.81+i*.012,.013),Vector3(.139,.004,.003),"vent")
	_box(self,Vector3(.58,.98,.014),Vector3(.035,.035,.012),"button")
	_box(self,Vector3(.47,.88,.015),Vector3(.071,.036,.008),"edge")
	_box(self,Vector3(.47,.88,.020),Vector3(.056,.018,.006),"usb")
	power_led=_box(self,Vector3(.552,.98,.027),Vector3(.012,.012,.006),"vent")
	power_led.name="PowerIndicator"
	led_material=StandardMaterial3D.new()
	led_material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	power_led.material_override=led_material
	_box(self,Vector3(.24,.776,-.31),Vector3(.42,.009,.009),"rubber")
	_box(self,Vector3(.446,.776,-.21),Vector3(.009,.009,.20),"rubber")
	set_display(false)
	# Chair back stays behind the desk and has no collision trap around the seat.
	_box(self,Vector3(0,.45,.98),Vector3(.50,.09,.47),"chair",true)
	_box(self,Vector3(0,.77,1.23),Vector3(.50,.60,.08),"chair",true)
	_box(self,Vector3(0,.24,.98),Vector3(.06,.40,.06),"steel",true)
	_box(self,Vector3(0,.035,.98),Vector3(.48,.05,.42),"steel",true)

func set_display(powered: bool, source: Texture2D = null) -> void:
	# Graphics filtering may have localized either material since the last power event.
	screen_material=screen.material_override
	led_material=power_led.material_override
	screen_material.albedo_texture=source if powered else null
	screen_material.albedo_color=Color.WHITE if powered and source!=null else Color("050608")
	led_material.albedo_color=Color("69e6c0") if powered else Color("1a252b")

func _box(parent: Node3D,at: Vector3,size: Vector3,key: String,casts_shadow := false) -> MeshInstance3D:
	var mesh_key:=str(size)
	if not shared_meshes.has(mesh_key):
		var mesh:=BoxMesh.new();mesh.size=size;shared_meshes[mesh_key]=mesh
	if not shared_materials.has(key):
		var material:=StandardMaterial3D.new();material.albedo_color=Color(str(PALETTE[key]));material.roughness=.45 if key in ["steel","edge"] else .82;material.metallic=.55 if key in ["steel","edge"] else .04
		shared_materials[key]=material
	var part:=MeshInstance3D.new();part.mesh=shared_meshes[mesh_key];part.material_override=shared_materials[key]
	part.position=at
	part.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_ON if casts_shadow and not baked_floor_shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(part)
	return part
