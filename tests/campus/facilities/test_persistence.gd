extends SceneTree
const Profile=preload("res://scripts/electronics_profile.gd")
const Adapter=preload("res://scripts/campus/facilities/profile_adapter.gd")
const Rules=preload("res://scripts/campus/facilities/facility_host.gd")
var failed:=0
var checks:=0
func check(v: bool,label: String) -> void:
	checks+=1
	if not v:failed+=1;printerr("FAIL "+label)
func _initialize() -> void:
	var p=Profile.new()
	# A fresh deterministic fixture path in this test's isolated APPDATA.
	p.open("facility-persistence-fixture")
	p.data.dollars=100;p.data.facilities=Rules.empty_profile()
	check(p.save()==OK,"actual ElectronicsProfile initial save")
	var adapter=Adapter.new();adapter.profiles["stable-id"]=p;adapter.is_authority=func():return true
	var f: Dictionary=adapter.load_facilities("stable-id")
	f.revision=1;f.last_sequence=1;f.xp=300;f.unlocks=["wave","cheer","flex"];f.records={"curl":{"reps":20}};f.held={"item":"coffee","servings":3,"station":""}
	check(adapter.commit("stable-id",-3,f),"real dollar/profile atomic adapter")
	var reloaded=Profile.new();reloaded.open("facility-persistence-fixture")
	check(reloaded.data.dollars==97 and reloaded.data.facilities.xp==300,"existing profile disk roundtrip")
	check(reloaded.data.facilities.held.item=="coffee" and reloaded.data.facilities.records.curl.reps==20,"food and record persist")
	check(not adapter.commit("stable-id",-3,f) and p.data.dollars==97,"stale transaction rejects")
	f.revision=2;f.last_sequence=2
	check(not adapter.commit("stable-id",-100,f) and p.data.dollars==97,"insufficient funds rollback")
	check(not adapter.commit("stable-id",10,f),"cannot mint dollars")
	var real_path: String=p.path
	p.path="res://tests/campus/facilities/missing-dir/profile.json"
	check(not adapter.commit("stable-id",-3,f),"save failure propagated")
	check(p.data.dollars==97 and p.data.facilities.revision==1,"save failure restores memory")
	p.path=real_path
	adapter.is_authority=func():return false
	check(not adapter.commit("stable-id",-3,f) and adapter.load_facilities("stable-id").is_empty(),"client adapter denied")
	print("PERSISTENCE checks=",checks," failures=",failed)
	quit(1 if failed else 0)
