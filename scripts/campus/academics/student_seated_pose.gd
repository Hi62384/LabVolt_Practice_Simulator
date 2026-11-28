extends RefCounted
## Articulation for generated classroom students. Player/imported avatar rigs
## and cosmetic deformation keep their existing authored hierarchy.
const Toon=preload("res://scripts/toon_character.gd")

static func install(model: Node3D) -> void:
	if model.has_meta("student_seated_rig"):return
	var player:=model.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if player==null or not player.has_animation("Seated"):return
	var height:=maxf(.1,model.scale.y)
	var body:=model.get_node_or_null("Body") as Node3D
	if body==null:return
	var hip:=model.get_node_or_null("LegL") as Node3D
	if hip==null:return
	var drop:=hip.position.y-.53/height
	for suffix in ["L","R"]:
		var leg:=model.get_node_or_null("Leg"+suffix) as Node3D
		var trouser:=leg.get_node_or_null("Trouser") as MeshInstance3D
		if trouser==null:return
		trouser.hide()
		var pants: Material=trouser.material_override
		Toon.form(leg,[Vector3(-.40,0,0),Vector3(-.38,.09,.095),Vector3(-.05,.105,.115),Vector3(.02,0,0)],pants,"SeatedThigh")
		var knee:=Node3D.new();knee.name="Knee";knee.position.y=-.37;leg.add_child(knee)
		Toon.form(knee,[Vector3(-.35,0,0),Vector3(-.33,.078,.085),Vector3(-.02,.09,.095),Vector3(.025,0,0)],pants,"SeatedShin")
		for child in leg.get_children():
			if not child is Node3D:continue
			if str(child.name).begins_with("Sneaker") or str(child.name).begins_with("Sole") or str(child.name).begins_with("ShoeLace"):
				var local: Vector3=child.position
				child.reparent(knee,false);child.position=local+Vector3(0,.37,0)
		for name in ["Idle","Walk","Seated"]:
			var animation:=player.get_animation(name)
			var seated: bool=name=="Seated"
			var rotation_track:=animation.add_track(Animation.TYPE_ROTATION_3D)
			animation.track_set_path(rotation_track,NodePath("Leg"+suffix+"/Knee"))
			animation.rotation_track_insert_key(rotation_track,0.,Quaternion(Vector3.RIGHT,PI*.5 if seated else 0.))
			var position_track:=animation.add_track(Animation.TYPE_POSITION_3D)
			animation.track_set_path(position_track,NodePath("Leg"+suffix))
			animation.position_track_insert_key(position_track,0.,leg.position-Vector3(0,drop if seated else 0.,0))
			if seated:
				for track in animation.get_track_count():
					if animation.track_get_type(track)!=Animation.TYPE_ROTATION_3D or str(animation.track_get_path(track))!="Leg"+suffix:continue
					for key in animation.track_get_key_count(track):animation.track_set_key_value(track,key,Quaternion(Vector3.RIGHT,-PI*.5))
	for name in ["Idle","Walk","Seated"]:
		var animation:=player.get_animation(name)
		var track:=animation.add_track(Animation.TYPE_POSITION_3D)
		animation.track_set_path(track,NodePath("Body"))
		animation.position_track_insert_key(track,0.,body.position-Vector3(0,drop if name=="Seated" else 0.,0))
	model.set_meta("student_seated_rig",true)
