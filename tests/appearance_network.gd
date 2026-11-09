extends SceneTree
var session: Node
var received := false
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var role: String=OS.get_cmdline_user_args()[0]
	session=preload("res://scripts/session.gd").new()
	session.name="Session"
	root.add_child(session)
	var fixture=preload("res://tests/fixture.gd")
	session.initialize(fixture.ids(),fixture.locations())
	var expected := FileAccess.get_file_as_bytes("res://assets/default_avatar.glb")
	session.appearance_received.connect(func(_peer,data):
		if data==expected:received=true
	)
	if role=="host":
		session.set_appearance(expected)
		session.host_game("Host",24909)
	else:
		session.set_appearance(expected)
		session.join_game("127.0.0.1","Guest",24909)
	for i in range(500):
		await create_timer(.05).timeout
		if received:break
	print("APPEARANCE "+role+": "+("PASS exact 33 MB avatar transfer" if received else "FAIL"))
	if role=="host":await create_timer(2).timeout
	session.leave()
	await process_frame
	quit(0 if received else 1)
