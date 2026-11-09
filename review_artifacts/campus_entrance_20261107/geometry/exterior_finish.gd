extends Node3D
## Exterior presentation only. Existing shells, entrance, collision and signage own function.
const WALL := Color("c9d1d2")
const BLUE := Color("718b9a")
const FRAME := Color("304958")
const GLASS := Color("526977")
const WOOD := Color("a88362")
const GREEN := Color("66836c")
var mats: Dictionary={}

func mount(campus: Node3D) -> bool:
	if not is_instance_valid(campus) or get_parent()!=null:return false
	campus.add_child(self)
	name="ExteriorFinish"
	# Facade cladding sits in front of existing z=-11 wall segments; x10..16 portal stays open.
	for x in [0.0,26.0]:
		_box(Vector3(x,1.0,-11.285),Vector3(19.6,1.72,.045),BLUE)
		_box(Vector3(x,3.0,-11.285),Vector3(19.6,2.20,.045),WALL)
		_box(Vector3(x,5.0,-11.285),Vector3(19.6,.17,.13),FRAME)
		for wx in [x-6.5,x-2.2,x+2.2,x+6.5]:
			_window(wx,2.55,-11.338)
	# Upper roof silhouette is lightweight and held above corridor height.
	for x in [0.0,26.0]:_box(Vector3(x,8.95,-3.08),Vector3(19.6,.16,.28),FRAME)
	# Frame at the actual six-metre opening. No door leaf or collision.
	for x in [9.72,16.28]:_box(Vector3(x,2.25,-11.32),Vector3(.25,4.5,.35),FRAME)
	_box(Vector3(13,4.54,-11.32),Vector3(6.9,.32,.42),FRAME)
	_box(Vector3(13,4.34,-11.55),Vector3(6.45,.10,.16),BLUE)
	# Existing concrete is still the walkable collision. Turf is visual and well
	# below feet; the 5.5 m central approach remains open from z=-25 to -11.
	for x in [-4.6,30.6]:
		_box(Vector3(x,-.063,-18),Vector3(8.0,.025,12.0),GREEN)
		_bench(Vector3(x,-.055,-16))
		_tree(Vector3(x-2.6,-.05,-21.3))
		_tree(Vector3(x+2.6,-.05,-13.5))
	# Narrow path edging defines the existing x10..16 walkable slab without
	# adding a second broad coplanar floor or touching its collision.
	for x in [10.3,15.7]:_box(Vector3(x,.013,-18),Vector3(.065,.026,13.2),Color("aeb9b7"))
	return true

func _window(x: float,y: float,z: float) -> void:
	_box(Vector3(x,y,z),Vector3(2.5,1.4,.04),FRAME)
	_box(Vector3(x,y,z-.027),Vector3(2.27,1.17,.025),GLASS)
	_box(Vector3(x,y,z-.05),Vector3(.065,1.17,.035),FRAME)
	_box(Vector3(x,y,z-.05),Vector3(2.27,.06,.035),FRAME)

func _bench(at: Vector3) -> void:
	_box(at+Vector3(0,.48,0),Vector3(1.75,.11,.47),WOOD)
	_box(at+Vector3(0,.86,.22),Vector3(1.75,.65,.10),WOOD)
	for x in [-.7,.7]:_box(at+Vector3(x,.23,0),Vector3(.06,.46,.42),FRAME)

func _tree(at: Vector3) -> void:
	_cylinder(at+Vector3(0,.65,0),.095,1.3,WOOD)
	_cylinder(at+Vector3(0,1.67,0),.48,1.10,GREEN,true)

func _material(color: Color) -> StandardMaterial3D:
	var key:=color.to_html()
	if mats.has(key):return mats[key]
	var mat:=StandardMaterial3D.new();mat.albedo_color=color;mat.roughness=.88;mats[key]=mat;return mat

func _box(at: Vector3,size: Vector3,color: Color) -> void:
	var mesh:=BoxMesh.new();mesh.size=size
	var visual:=MeshInstance3D.new();visual.mesh=mesh;visual.material_override=_material(color);visual.position=at;visual.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;add_child(visual)

func _cylinder(at: Vector3,radius: float,height: float,color: Color,taper:=false) -> void:
	var mesh:=CylinderMesh.new();mesh.bottom_radius=radius;mesh.top_radius=.12 if taper else radius;mesh.height=height;mesh.radial_segments=8
	var visual:=MeshInstance3D.new();visual.mesh=mesh;visual.material_override=_material(color);visual.position=at;visual.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;add_child(visual)
