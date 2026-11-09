extends SceneTree
const Session = preload("res://scripts/session.gd")
const Fixture = preload("res://tests/fixture.gd")
var session: Node
var latest := {}
var role := "host"
var sync_pass := false
var late_pass := false
var server_left := false
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func pause(seconds: float) -> void:
	await create_timer(seconds).timeout

func action(data: Dictionary) -> void:
	session.send_pose({"position":Vector3(-4.2,1.5,-1.4)})
	await pause(.12)
	session.request(data)
	await pause(.12)

func expect(ok: bool,text: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL "+role+": "+text)
	else:
		print("PASS "+role+": "+text)

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size()>0:
		role = args[0]
	session = Session.new()
	session.name = "Session"
	root.add_child(session)
	session.changed.connect(func(data): latest=data)
	session.message_received.connect(func(text):
		print(role+" message: "+text)
		if text.contains("Host disconnected"):
			server_left=true
	)
	session.chat_received.connect(func(_peer,_sender,text):
		if text.contains("SYNC_PASS"):
			sync_pass=true
		if text.contains("LATE_PASS"):
			late_pass=true
	)
	session.initialize(Fixture.ids(),Fixture.locations())
	if role=="host":
		expect(session.host_game("Host",24991)==OK,"ENet host created")
		for i in range(100):
			await pause(.1)
			if session.lab.completed().size()==1:
				break
		expect(session.lab.completed().size()==1,"client created shared wire")
		for i in range(15):
			session.send_pose({"position":Vector3(-4.2,1.5,-1.4)})
			await pause(.1)
		await action({"op":"switch","kind":"R","index":0,"expected":false})
		await action({"op":"pickup","color":3})
		await action({"op":"plug","port":"R0_N"})
		await action({"op":"plug","port":"P_N"})
		await action({"op":"power"})
		expect(absf(latest.readings.p-12)<.001,"host solves cross-player circuit")
		for i in range(120):
			await pause(.1)
			if sync_pass and late_pass and session.roster.size()==1:
				break
		expect(sync_pass,"client confirms identical readings and switches")
		expect(late_pass,"late join confirms complete current state")
		expect(session.lab.completed().size()==2,"installed leads survive client disconnect")
		expect(session.lab.cables.any(func(c): return c.owner==0 and c.a=="P_B" and c.b==""),"disconnect releases carried lead and preserves attached end")
		await pause(1)
		session.leave()
	elif role=="client":
		expect(session.join_game("127.0.0.1","Client",24991)==OK,"ENet client initiated")
		for i in range(60):
			await pause(.1)
			if session.roster.size()==2:
				break
		expect(session.roster.size()==2,"lobby roster synchronized")
		# Teleport isn't accepted: walk the authoritative pose to the rack.
		for i in range(15):
			session.send_pose({"position":Vector3(-4.2,1.5,-1.4)})
			await pause(.1)
		await action({"op":"pickup","color":0})
		await action({"op":"plug","port":"P_A"})
		await action({"op":"plug","port":"R0_P"})
		for i in range(60):
			await pause(.1)
			if latest.get("powered",false):
				break
		expect(latest.powered and latest.switches.R[0],"host power and switch reach client")
		expect(absf(latest.readings.p-12)<.001,"authoritative meter parity")
		expect(latest.cables.size()==2,"cross-client cables synchronized")
		session.chat("SYNC_PASS")
		await pause(2)
		await action({"op":"power"})
		await action({"op":"pickup"})
		await action({"op":"plug","port":"P_B"})
		await pause(1)
		session.leave()
	else:
		expect(session.join_game("127.0.0.1","Late",24991)==OK,"late ENet client initiated")
		for i in range(60):
			await pause(.1)
			if latest.get("cables",[]).size()>=2 and latest.get("powered",false):
				break
		expect(latest.cables.size()>=2 and latest.switches.R[0],"late join receives cables and switches")
		# Joining while energized proves readings are in the full authoritative snapshot.
		expect(latest.powered and absf(latest.readings.p-12)<.001,"late join receives energized readings")
		session.chat("LATE_PASS")
		for i in range(220):
			await pause(.1)
			if server_left:
				break
		expect(server_left,"host shutdown handled")
	print("NETWORK "+role+": "+str(failures)+" failures")
	quit(1 if failures else 0)
