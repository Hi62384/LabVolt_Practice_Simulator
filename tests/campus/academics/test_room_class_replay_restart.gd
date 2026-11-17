extends SceneTree

func _initialize() -> void:call_deferred("run")

func run() -> void:
	var role: String=str(OS.get_cmdline_user_args()[0])
	var game=load("res://scenes/Main.tscn").instantiate()
	root.add_child(game)
	for i in 4:await process_frame
	var records: Dictionary=game.school.archive if role=="host" else game.school.gradebook
	var credits: Array=[]
	for value in records.values():
		var candidates: Array=value.values() if role=="host" and value is Dictionary else [value]
		for item in candidates:
			if item is Dictionary and item.get("gradebook_assessment_id","")=="lecture:1" and item.has("score"):credits.append(item)
	if credits.size()!=1 or (role=="client" and str(credits[0].get("profile",""))!=game.school.local_identity) or float(credits[0].score)<99.0:
		push_error("Restart lost or duplicated the official grade: "+str(credits));quit(1);return
	print("ROOM_REPLAY_RESTART_",role.to_upper()," PASS")
	game.queue_free()
	await process_frame
	quit(0)
