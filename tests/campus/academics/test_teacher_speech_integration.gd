extends SceneTree
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var game=load("res://scenes/Main.tscn").instantiate();root.add_child(game)
	for i in 4:await process_frame
	game.front.entered()
	var faculty=game.faculty
	var room="ac_lab"
	var id: String=str(faculty.current[room])
	var point: Vector3=game.school_world.teacher.global_position
	faculty._show_reaction(room,id,"A class reminder",point,1,1)
	assert(faculty.speech_player.last_serial[room]==1)
	assert(faculty.speech_player.active.is_empty() and faculty.speech_player.subtitles.has(room))
	assert(not faculty.speech_player.accept(room,"Teacher",1,"stale",4,game.school_world.teacher))
	faculty._reaction(room,id,"Stale bubble",point,1,4)
	assert(faculty.reaction_labels[room].text=="A class reminder")
	faculty._show_reaction(room,id,"Safety warning",point,2,4)
	assert(faculty.speech_player.last_serial[room]==2)
	faculty._clear_speech()
	assert(faculty.speech_player.last_serial.is_empty() and faculty.speech_player.subtitles.is_empty())
	faculty._sync_lab_teachers()
	var fixture:=AudioStreamWAV.new();fixture.format=AudioStreamWAV.FORMAT_16_BITS;fixture.mix_rate=22050
	var pcm:=PackedByteArray();pcm.resize(22050)
	for i in 11025:
		var sample:=roundi(sin(float(i)*TAU*220.0/22050.0)*8000.0)
		pcm[i*2]=sample&255;pcm[i*2+1]=(sample>>8)&255
	fixture.data=pcm
	var key: String=faculty.speech_cache_key(id,"Cached fixture")
	assert(faculty.speech_player.cache_stream(key,fixture))
	faculty._show_reaction(room,id,"Cached fixture",point,1,2)
	assert(faculty.speech_player.active.has(room))
	faculty.speech_player.cancel(room)
	assert(faculty.speech_player.active.is_empty())
	var lecture="ety155_lecture"
	game.lecture_classes.public_classes[lecture]={"teacher":"jeff","phase":"lesson"}
	faculty._sync_lectures()
	assert(faculty.lecture_models.has(lecture))
	faculty._show_reaction(lecture,"jeff","Class question",game.lecture_classes.signs[lecture].desk,1,1)
	assert(faculty.speech_player.subtitles.has(lecture))
	game.lecture_classes.public_classes[lecture].phase="assignment"
	faculty._sync_lectures()
	assert(not faculty.speech_player.subtitles.has(lecture))
	game.lecture_classes.public_classes.erase(lecture)
	faculty._sync_lectures()
	assert(not faculty.lecture_models.has(lecture))
	print("TEACHER_SPEECH_INTEGRATION PASS (fixture audio; no teacher voice asset)")
	game.queue_free();await process_frame;quit(0)
