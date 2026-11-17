extends SceneTree
const Archive=preload("res://scripts/campus/computers/usb_archive.gd")
const Drive=preload("res://scripts/campus/computers/device_filesystem.gd")
const Ledger=preload("res://scripts/inventory_authority/ledger.gd")
const Profile=preload("res://scripts/electronics_profile.gd")
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var game: Node=load("res://scenes/Main.tscn").instantiate();root.add_child(game)
	for i in 4:await process_frame
	var recipient=game.electronics.profile;recipient.open("usb-cross-host-recipient")
	game.school.local_identity=recipient.data.dorm.owner
	var sender=Profile.new();sender.open("usb-cross-host-sender")
	var id:="d".repeat(32);var token:="e".repeat(32)
	var sender_id: String=sender.data.dorm.owner;var recipient_id: String=recipient.data.dorm.owner
	sender.data.dorm.usb_drives={id:{"name":"USB drive","capacity_mb":8,"location":"handoff"}}
	sender.data.usb_handoff_pending={id:token}
	var drive=Drive.new(8*1024*1024);drive.write_file("notes.txt","staged data".to_utf8_buffer())
	if Archive.save(recipient_id,id,"USB drive",8,drive)!=OK:quit(1);return
	var host_a=Ledger.new();var host_b=Ledger.new()
	if host_a.open("user://cross-host-a")!=OK or host_b.open("user://cross-host-b")!=OK:quit(1);return
	if not host_a.bind(1,sender_id,"a".repeat(64),sender.data).get("ok",false):quit(1);return
	if not host_a.bind(2,recipient_id,"b".repeat(64),recipient.data).get("ok",false):quit(1);return
	var committed: Dictionary=host_a.commit_usb_handoff(1,2,id,token)
	if not committed.get("ok",false):push_error("Fixture commit failed");quit(1);return
	recipient.data.usb_received_pending={id:{"token":token,"host":"original-host"}}
	var elsewhere: Dictionary=host_b.bind(3,recipient_id,"c".repeat(64),recipient.data)
	if not elsewhere.get("ok",false):push_error("Other host rejected pending profile");quit(1);return
	recipient.authority_revision=-1
	game.electronics_trade.authority.receive_snapshot(elsewhere)
	if not recipient.data.get("usb_received_pending",{}).has(id) or recipient.data.dorm.get("usb_drives",{}).has(id) or not game.ui.log_label.text.contains("awaiting confirmation"):
		push_error("Pending warning or reservation was not preserved");quit(1);return
	game.electronics.open("inventory")
	var visible_warning:=false
	for label in game.electronics.screen.find_children("*","Label",true,false):
		if label.text.contains("USB transaction awaiting confirmation"):visible_warning=true
	if not visible_warning:push_error("Persistent inventory warning missing");quit(1);return
	var staged: Dictionary=Archive.load(recipient_id,id,8)
	if staged.has("error") or staged.drive.entries["notes.txt"].data.get_string_from_utf8()!="staged data":push_error("Staged data changed on another host");quit(1);return
	host_a.unbind(2)
	var recovered: Dictionary=host_a.bind(2,recipient_id,"b".repeat(64),recipient.data)
	recipient.authority_revision=-1
	game.electronics_trade.authority.receive_snapshot(recovered)
	if not recipient.data.dorm.get("usb_drives",{}).has(id) or recipient.data.get("usb_received_pending",{}).has(id) or host_a.state.accounts[sender_id].profile.dorm.get("usb_drives",{}).has(id):push_error("Original host did not resolve committed delivery");quit(1);return
	print("USB_CROSS_HOST_PENDING PASS")
	game.queue_free();await process_frame;quit()
