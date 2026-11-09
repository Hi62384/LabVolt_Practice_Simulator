extends RefCounted
static var templates := {}
const MAX_BYTES := 67108864
static func valid(bytes: PackedByteArray) -> bool:
	if bytes.size()<20 or bytes.size()>MAX_BYTES or bytes.decode_u32(0)!=0x46546c67 or bytes.decode_u32(4)!=2 or bytes.decode_u32(8)!=bytes.size():return false
	var length := bytes.decode_u32(12)
	if length>bytes.size()-20 or bytes.decode_u32(16)!=0x4e4f534a:return false
	var data=JSON.parse_string(bytes.slice(20,20+length).get_string_from_utf8())
	if not data is Dictionary:return false
	for key in ["buffers","images"]:
		for entry in data.get(key,[]):
			if not entry is Dictionary or entry.has("uri"):return false
	return data.get("nodes",[]).size()<10000
static func build(bytes: PackedByteArray) -> Node3D:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	var key := context.finish().hex_encode()
	if templates.has(key):return templates[key].instantiate()
	if not valid(bytes):return null
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	if document.append_from_buffer(bytes,"",state)!=OK:return null
	var model := document.generate_scene(state)
	if model==null:return null
	model.rotation.y=PI
	var packed := PackedScene.new()
	if packed.pack(model)==OK:
		if templates.size()>=4:templates.erase(templates.keys()[0])
		templates[key]=packed
	return model
static func animate(model: Node, walking: bool,seated := false,resting := false) -> void:
	preload("res://scripts/campus/dorms/rest/rest_pose.gd").apply(model as Node3D,resting)
	if resting:return
	var player: AnimationPlayer=(model.get_meta("animation_player") if model.has_meta("animation_player") else null) as AnimationPlayer
	if player==null:
		for child in model.find_children("*","AnimationPlayer",true,false):
			player=child
			break
	if player==null:return
	model.set_meta("animation_player",player)
	var desired := "Seated" if seated else ("Walk" if walking else "Idle")
	for name in player.get_animation_list():
		if name.to_lower().ends_with(desired.to_lower()):
			if player.current_animation!=name:
				player.get_animation(name).loop_mode=Animation.LOOP_LINEAR
				player.play(name,.2)
			return
