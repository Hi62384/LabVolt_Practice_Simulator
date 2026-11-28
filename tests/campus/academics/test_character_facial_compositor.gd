extends SceneTree
## Geometry/ownership regressions. The separate render probe supplies visual
## evidence; these assertions alone do not establish facial rendering quality.
const Toon=preload("res://scripts/toon_character.gd")
const Motion=preload("res://scripts/campus/academics/character_motion.gd")
const Face=preload("res://scripts/campus/academics/character_face.gd")
const Speech=preload("res://scripts/campus/academics/teacher_speech_player.gd")
const Cosmetics=preload("res://scripts/avatar_cosmetics/faces_hair/faces_hair_provider.gd")
var checks:=0
var failures: Array[String]=[]

func _initialize() -> void:call_deferred("run")

func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:failures.append(message);printerr("FACIAL COMPOSITOR FAIL: "+message)

func run() -> void:
	var speech:=Speech.new();root.add_child(speech)
	for glasses in Toon.GLASSES:
		for proportions in [.65,1.,1.4]:
			var config:=Toon.defaults();config.glasses=glasses;config.expression="Grin"
			config.eye_height=proportions;config.eye_size=proportions;config.pupil_size=proportions
			var model:=Toon.build(config);root.add_child(model)
			var head:=model.get_node("Body/Head") as Node3D
			var left:=head.get_node("EyeL") as Node3D
			var right:=head.get_node("EyeR") as Node3D
			check(left.get_node("Blink").get_child_count()==4 and right.get_node("Blink").get_child_count()==4,"Both eyes own the same four semantic meshes")
			check(left.scale.is_equal_approx(right.scale),"Authored eye proportions are symmetric")
			for role in ["eye_white","iris","pupil","eye_spark"]:
				var pair:=Face.parts(head,role)
				check(pair.size()==2 and pair[0].scale.is_equal_approx(pair[1].scale),"Matching paired geometry for "+role)
			var frame_nodes:=Face.parts(head,"glasses")
			var frame_rest: Dictionary={}
			for frame in frame_nodes:
				for part in frame.get_children():frame_rest[part]=part.transform
			var animation:=model.get_node("AnimationPlayer") as AnimationPlayer
			animation.play("Idle");animation.advance(2.78)
			check(left.get_node("Blink").scale.y<.07 and right.get_node("Blink").scale.y<.07,"The same blink channel closes both eyes")
			var rig:=Motion._rig(model)
			check(rig.eyes.size()==2 and rig.brows.size()==4 and rig.mouth.size()==16,"Only declared facial components enter the rig")
			check(is_equal_approx(rig.eyes[0].scale.y,proportions),"Initializing expressions during a blink keeps the authored rest")
			for animation_name in animation.get_animation_list():
				var track_set:=animation.get_animation(animation_name)
				for track in track_set.get_track_count():
					if str(track_set.track_get_path(track))=="Body/Head":check(not track_set.track_is_enabled(track),"The expression compositor exclusively owns procedural head rotation")
			for mood in ["steady","angry","sad","happy","tired","excited","anxious"]:
				Motion.express(model,mood,1.,"",0.)
				check(left.scale.is_equal_approx(right.scale),"Expression keeps eyes symmetric: "+mood)
				for part in frame_rest:check(part.transform.is_equal_approx(frame_rest[part]),"Glasses frame remains rigid: "+mood)
				for brow in rig.brows:
					var segment:=brow.node as MeshInstance3D
					check(absf(segment.scale.y-1.)<.0001,"Brow rotation preserves segment length: "+mood)
				var teeth:=Face.parts(head,"teeth")
				check(teeth.size()==1 and not teeth[0].mesh is SphereMesh,"Grin teeth are fitted geometry, never a white sphere")
				if mood in ["angry","sad","tired"]:check(not teeth[0].visible,"Frowning and tired expressions suppress resting grin teeth")
			for frame in 180:
				animation.advance(1./60.)
				Motion.express(model,"angry",1./60.,"",float(frame)/60.)
				check(left.scale.is_equal_approx(right.scale) and left.get_node("Blink").scale.is_equal_approx(right.get_node("Blink").scale),"Blink and expression compose without drift")
			Motion.express(model,"sad",1.,"",0.)
			var mouth:=speech._mouth(model)
			Face.speech_level(mouth,.2,1.)
			check(mouth.visible and not head.get_node("NeutralMouth").visible,"Speaking has one visible mouth surface")
			check(not Face.parts(head,"teeth")[0].is_visible_in_tree(),"Teeth cannot protrude above a speaking mouth")
			Face.end_speech(mouth)
			check(not mouth.visible and head.get_node("NeutralMouth").visible and not Face.parts(head,"teeth")[0].visible,"Speech end restores the current sad expression, not a grin")
			Cosmetics._hide_legacy(head,"faces")
			mouth=speech._mouth(model);Face.end_speech(mouth)
			check(not head.get_node("NeutralMouth").visible,"Speech must not expose a hidden cosmetic face's legacy lips")
			for frame in frame_nodes:check(frame.is_visible_in_tree(),"Replacing face cosmetics never hides glasses")
			Cosmetics._restore_legacy(head,"faces")
			Motion.express(model,"steady",1.,"",0.)
			check(left.scale.distance_to(Vector3(1.,proportions,1.))<.0001,"Rest expression returns to the saved eye proportions")
			model.free()
	speech.queue_free();await process_frame
	print("CHARACTER_FACIAL_COMPOSITOR %s checks=%d failures=%d"%["PASS" if failures.is_empty() else "FAIL",checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
