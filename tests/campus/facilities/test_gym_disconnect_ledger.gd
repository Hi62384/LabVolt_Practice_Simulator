extends SceneTree
const Ledger=preload("res://scripts/inventory_authority/ledger.gd")
const Profile=preload("res://scripts/electronics_profile.gd")
const Adapter=preload("res://scripts/campus/facilities/ledger_adapter.gd")
const Host=preload("res://scripts/campus/facilities/facility_host.gd")
var present:=true
var now:=1000
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var ledger=Ledger.new()
	var path:="user://gym-disconnect-ledger"
	var ok: bool=ledger.open(path)==OK
	var profile=Profile.new();profile.open("gym-disconnect-profile")
	var identity:=str(profile.data.dorm.owner);var secret:="b".repeat(64)
	if ok:
		var binding: Dictionary=ledger.bind(2,identity,secret,profile.data)
		ok=binding.ok
		if not ok:printerr("Initial binding failed: ",binding)
	var adapter=Adapter.new();adapter.ledger=ledger;adapter.is_authority=func():return true
	var host=Host.new();host.authority=func():return true
	host.clock=func():return now
	host.context=func(_peer):return {"identity":identity,"position":Vector3.ZERO,"room_id":"gym","allowed":true,"grounded":true} if present else {}
	host.load_profile=adapter.load_facilities;host.commit_profile=adapter.commit
	host.anchors={"gym/pushup":{"kind":"pushup","room_id":"gym","position":Vector3.ZERO}}
	if ok:
		var started: Dictionary=host.act(2,{"op":"start","station":"gym/pushup","exercise":"pushup","weight":0,"sequence":1})
		ok=started.ok
		if not ok:printerr("Starting set failed: ",started)
	if ok:
		for phase in 2:
			now+=int(host.active[2].half_ms)
			var beat: Dictionary=host.act(2,{"op":"beat","sequence":int(ledger.account(2).profile.facilities.last_sequence)+1})
			if not beat.ok:ok=false;printerr("Workout phase failed: ",beat);break
	present=false
	if ok:host.clear_activity(2,"interrupted")
	present=true
	if ok:
		now+=7200000
		ok=host.commit_recovery(2)
	ledger.unbind(2)
	var reopened=Ledger.new()
	if ok:ok=reopened.open(path)==OK
	if ok:
		var rebound: Dictionary=reopened.bind(3,identity,secret,profile.data)
		ok=rebound.ok
		if not ok:printerr("Rebinding failed: ",rebound)
	var history: Array=reopened.account(3).get("profile",{}).get("facilities",{}).get("gym",{}).get("history",[]) if ok else []
	ok=ok and history.size()==1 and history[0].get("outcome","")=="interrupted" and history[0].get("reps",0)==1
	if ok:
		var muscles: Dictionary=reopened.account(3).profile.facilities.gym.muscles
		ok=muscles.has("chest") and float(muscles.chest.get("size",0.0))>0.0
	if not ok:push_error("Interrupted workout was not saved to the authoritative ledger")
	print("GYM_DISCONNECT_LEDGER ","PASS" if ok else "FAIL")
	quit(0 if ok else 1)
