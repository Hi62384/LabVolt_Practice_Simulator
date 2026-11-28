extends RefCounted
## Semantic facial parts and the single compositor for speech-mouth visibility.
## Expression and blink have separate pivots. Audio only supplies an aperture;
## it never rescales an authored eye, lip or tooth mesh.
const ROLE := &"character_facial_role"
const SIDE := &"character_facial_side"
const REST := &"character_facial_rest"

static func tag(node: Node3D, role: String, side := 0) -> void:
	node.set_meta(ROLE,role)
	node.set_meta(SIDE,side)
	node.set_meta(REST,node.transform)

static func head_for(anchor: Node3D) -> Node3D:
	if not is_instance_valid(anchor):return null
	var cached: Node3D=anchor.get_meta("character_facial_head") as Node3D if anchor.has_meta("character_facial_head") else null
	if is_instance_valid(cached):return cached
	var head: Node3D=anchor if str(anchor.get_meta(ROLE,""))=="head" else anchor.find_child("Head",true,false) as Node3D
	if head!=null:anchor.set_meta("character_facial_head",head)
	return head

static func parts(parent: Node, role: String) -> Array[Node3D]:
	var found: Array[Node3D]=[]
	if not is_instance_valid(parent):return found
	for child in parent.get_children():
		if child is Node3D and str(child.get_meta(ROLE,""))==role:found.append(child)
		found.append_array(parts(child,role))
	return found

static func expression(head: Node3D, curve: float, strength: float) -> void:
	if not is_instance_valid(head):return
	head.set_meta("character_mouth_curve",curve)
	head.set_meta("character_mouth_strength",strength)
	_compose(head,0.)

static func begin_speech(head: Node3D) -> MeshInstance3D:
	if not is_instance_valid(head):return null
	var mouth: MeshInstance3D=head.get_node_or_null("SpeechMouth") as MeshInstance3D
	if mouth==null:
		mouth=MeshInstance3D.new();mouth.name="SpeechMouth"
		var vertices:=PackedVector3Array()
		for sector in 20:
			var a:=TAU*float(sector)/20.
			var b:=TAU*float(sector+1)/20.
			vertices.append(Vector3.ZERO)
			for angle in [b,a]:
				var x: float=cos(angle)*.044
				vertices.append(Vector3(x,sin(angle)*.020,-absf(x)*.14))
		var arrays: Array=[];arrays.resize(Mesh.ARRAY_MAX);arrays[Mesh.ARRAY_VERTEX]=vertices
		var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays);mouth.mesh=mesh
		var material:=StandardMaterial3D.new();material.albedo_color=Color("352423")
		material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
		mouth.material_override=material
		mouth.position=Vector3(0,-.125,.151)
		mouth.scale=Vector3(float(head.get_meta("character_mouth_width",1.)),.12,1.)
		head.add_child(mouth);tag(mouth,"speech_aperture")
	head.set_meta("character_audio_active",true)
	head.set_meta("character_audio_aperture",.12)
	_compose(head,0.)
	return mouth

static func speech_level(mouth: MeshInstance3D, level: float, delta: float) -> void:
	if not is_instance_valid(mouth):return
	var head:=mouth.get_parent() as Node3D
	if head==null:return
	head.set_meta("character_audio_aperture",.12+clampf(level*5.,0.,1.25))
	_compose(head,maxf(delta,0.))

static func end_speech(mouth: MeshInstance3D) -> void:
	if not is_instance_valid(mouth):return
	var head:=mouth.get_parent() as Node3D
	if head==null:return
	head.set_meta("character_audio_active",false)
	head.set_meta("character_audio_aperture",.12)
	_compose(head,0.)

static func _compose(head: Node3D, delta: float) -> void:
	var speaking:=bool(head.get_meta("character_audio_active",false))
	var neutral:=head.get_node_or_null("NeutralMouth") as Node3D
	# Cosmetic face replacement owns its own visible surface. Do not expose the
	# hidden legacy mouth when an audio stream ends underneath that cosmetic.
	var cosmetics: Dictionary=head.get_meta("faces_hair_legacy_state",{})
	var legacy_visible:=not cosmetics.has("faces")
	if neutral!=null:neutral.visible=not speaking and legacy_visible
	var mouth:=head.get_node_or_null("SpeechMouth") as MeshInstance3D
	if mouth!=null:
		mouth.visible=speaking and legacy_visible
		mouth.position.y=-.125+float(head.get_meta("character_mouth_curve",0.))*.08
		mouth.scale.y=lerpf(mouth.scale.y,float(head.get_meta("character_audio_aperture",.12)),1.-exp(-delta*20.)) if speaking else .12
	# A resting grin is a thin fitted strip, never a sphere. It is suppressed
	# together with the lips while speaking and whenever the expression frowns.
	var show_teeth:=float(head.get_meta("character_mouth_strength",0.))<.01 or float(head.get_meta("character_mouth_curve",0.))>.002
	var teeth: Array=head.get_meta("character_teeth_parts",[])
	if not head.has_meta("character_teeth_parts"):
		teeth=parts(head,"teeth");head.set_meta("character_teeth_parts",teeth)
	for tooth in teeth:
		if is_instance_valid(tooth):tooth.visible=show_teeth and not speaking and legacy_visible
