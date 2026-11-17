extends SceneTree
const Archive=preload("res://scripts/campus/computers/usb_archive.gd")
const Drive=preload("res://scripts/campus/computers/device_filesystem.gd")
const ID="eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"
var game: Node
var deadline: int
func _initialize() -> void:call_deferred("run")
func until(check: Callable,label: String) -> bool:
	while Time.get_ticks_msec()<deadline:
		if check.call():return true
		await create_timer(.05).timeout
	push_error("CROSS HOST TIMEOUT: "+label);quit(1);return false
func fail(message: String) -> void:push_error(message);quit(1)
func run() -> void:
	var args:=OS.get_cmdline_user_args()
	if args.size()!=3 or args[0] not in ["a","b","client"]:fail("Invalid arguments");return
	var role:=str(args[0]);var a:=int(args[1]);var b:=int(args[2])
	game=load("res://scenes/Main.tscn").instantiate();root.add_child(game)
	for i in 4:await process_frame
	var profile=game.electronics.profile;profile.open("laptop-cross-host-"+role)
	game.school.local_identity=profile.data.dorm.owner
	deadline=Time.get_ticks_msec()+90000
	if role in ["a","b"]:
		if game.session.host_game("Host "+role,a if role=="a" else b)!=OK:fail("Host failed");return
		print("CROSS_HOST_"+role.to_upper()+"_READY")
		if not await until(func():return game.session.roster.size()==2,"client joined"):return
		if role=="a":
			if not await until(func():return game.electronics_trade.authority.ledger.bindings.size()==2,"first bind"):return
			if not await until(func():return game.session.roster.size()==1,"first departure"):return
			if not await until(func():return game.session.roster.size()==2 and game.electronics_trade.authority.ledger.bindings.size()==2,"return bind"):return
		else:
			await create_timer(3.0).timeout
			if game.electronics_trade.authority.ledger.bindings.size()!=1:fail("Different host accepted unresolved inventory");return
		if not await until(func():return game.session.roster.size()==1,"client left"):return
		print("CROSS_HOST_"+role.to_upper()+" PASS")
	else:
		profile.data.dollars=10000;profile.buy_usb(8)
		var usb: String=profile.data.dorm.usb_drives.keys()[0]
		var drive=Drive.new(8*1024*1024);drive.write_file("note.txt","preserved".to_utf8_buffer())
		if Archive.save(game.school.local_identity,usb,"USB drive",8,drive)!=OK:fail("Archive setup failed");return
		if game.session.join_game("127.0.0.1","Student",a)!=OK:fail("First join failed");return
		var authority=game.electronics_trade.authority
		if not await until(func():return authority.bound,"first bind"):return
		var first_host: String=authority.bound_host
		profile.data.laptop_purchase_pending={ID:{"tier":"standard","host":first_host}}
		var callback: Callable=profile.authority_submit;profile.authority_submit=Callable()
		if profile.save()!=OK:fail("Marker save failed");return
		profile.authority_submit=callback
		game.session.leave();await create_timer(2.0).timeout
		if game.session.join_game("127.0.0.1","Student",b)!=OK:fail("Second join failed");return
		if not await until(func():return game.session.roster.size()==2,"second host joined"):return
		await create_timer(4.0).timeout
		if authority.bound or not profile.data.get("laptop_purchase_pending",{}).has(ID):fail("Different host resolved pending purchase");return
		var saved: Dictionary=Archive.load(game.school.local_identity,usb,8)
		if saved.has("error") or saved.drive.entries["note.txt"].data.get_string_from_utf8()!="preserved":fail("USB archive changed");return
		game.session.leave();await create_timer(2.0).timeout
		if game.session.join_game("127.0.0.1","Student",a)!=OK:fail("Return join failed");return
		if not await until(func():return authority.bound and profile.data.get("laptop_purchase_pending",{}).is_empty(),"original host recovery"):return
		if profile.data.dorm.get("portable_laptops",{}).has(ID) or not profile.data.dorm.usb_drives.has(usb):fail("Uncommitted purchase or USB changed");return
		print("CROSS_HOST_CLIENT PASS")
	await create_timer(.5).timeout
	game.session.leave();game.queue_free();await process_frame;quit()
