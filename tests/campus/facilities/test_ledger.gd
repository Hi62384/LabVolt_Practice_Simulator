extends SceneTree
const Ledger=preload("res://scripts/inventory_authority/ledger.gd")
const Profile=preload("res://scripts/electronics_profile.gd")
const Adapter=preload("res://scripts/campus/facilities/ledger_adapter.gd")
const Rules=preload("res://scripts/campus/facilities/facility_host.gd")
var failed:=0
var checks:=0
func check(v: bool,label: String) -> void:
	checks+=1
	if not v:failed+=1;printerr("FAIL "+label)
func _initialize() -> void:
	var path:="user://facilities-ledger-"+str(Time.get_ticks_usec())
	var l=Ledger.new();check(l.open(path)==OK,"open real ledger")
	var p=Profile.new();p.open("ledger-facility-fixture");p.data.dollars=100;p.data.facilities=Rules.empty_profile()
	p.data.facilities.xp=999999;p.data.facilities.unlocks=["wave","victory"]
	var identity:="a".repeat(48);var secret:="b".repeat(64)
	check(l.bind(2,identity,secret,p.data).ok,"authenticated existing-ledger binding")
	var a=Adapter.new();a.ledger=l;a.is_authority=func():return true
	var f: Dictionary=a.load_facilities(identity)
	check(f.xp==0 and not "victory" in f.unlocks,"client-imported gym rewards ignored")
	f.revision=1;f.last_sequence=1;f.xp=100;f.unlocks=["wave","cheer"]
	check(a.commit(identity,-7,f),"ledger purchase commit")
	check(l.account(2).profile.dollars==93 and l.account(2).profile.facilities.xp==100,"one authoritative transaction")
	check(not a.commit(identity,-7,f),"duplicate revision rejected")
	var reopened=Ledger.new();check(reopened.open(path)==OK,"reopen ledger generation")
	check(reopened.bind(7,identity,secret,p.data).ok,"reconnect with stale local snapshot")
	check(reopened.account(7).profile.dollars==93 and reopened.account(7).profile.facilities.xp==100,"stale client cannot overwrite facilities or dollars")
	check(not a.commit("c".repeat(48),-2,f),"unbound identity denied")
	l.unbind(2)
	check(a.load_facilities(identity).is_empty(),"disconnected profile cannot transact")
	print("LEDGER checks=",checks," failures=",failed)
	quit(1 if failed else 0)
