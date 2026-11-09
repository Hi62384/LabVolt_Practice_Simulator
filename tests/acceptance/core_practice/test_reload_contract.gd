extends SceneTree
const Profile=preload("res://scripts/electronics_profile.gd")
const Guard=preload("res://tests/acceptance/core_practice/reload_guard.gd")
var checks:=0
var failures:=0
var outcomes: Array=[]
func check(value: bool,label: String) -> void:
	checks+=1;outcomes.append({"label":label,"pass":value});print("PASS " if value else "FAIL ",label)
	if not value:failures+=1
func _initialize() -> void:
	if OS.get_environment("LABVOLT_CORE_PRACTICE_LEASE")!="practice-J3":quit(77);return
	var spec: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/acceptance/core_practice/expected_package.json"))
	var input:="res://tests/acceptance/core_practice/saved_profile_j2.json"
	check(FileAccess.get_sha256(input)==spec.input_sha256,"Exact frozen J2 end-of-run saved bytes")
	var bytes:=FileAccess.get_file_as_bytes(input)
	var parsed: Variant=JSON.parse_string(bytes.get_string_from_utf8())
	check(Profile.valid(parsed),"Original production schema accepts exact saved profile")
	var expected: Array=spec.pins.duplicate(true)
	# Reconstruct original PackageForm int(fields.x/y.value) contract ONLY on
	# expected fixture coordinates. Actual parsed/reloaded values are untouched.
	for pin in expected:
		pin.position.x=int(pin.position.x);pin.position.y=int(pin.position.y)
	var bootstrap=Profile.new();bootstrap.open(str(spec.identity))
	check(bootstrap.path.get_file()==spec.original_profile_basename,"Same profile filename/identity contract as J2")
	var file:=FileAccess.open(bootstrap.path,FileAccess.WRITE);file.store_buffer(bytes);file.close()
	var reloaded=Profile.new();reloaded.open(str(spec.identity))
	var present: bool=reloaded.data.get("blueprints",{}).has(spec.package_id)
	check(present,"Actual Profile.open retains package")
	var pins: Variant=reloaded.data.get("blueprints",{}).get(spec.package_id,{}).get("pins",null)
	var inventory: Variant=reloaded.data.inventory.get(spec.package_id,null)
	var proof:=Guard.inspect(expected,pins,inventory)
	proof.package_present=present;proof.input_sha256=spec.input_sha256;proof.reloaded_file_sha256=FileAccess.get_sha256(reloaded.path)
	proof.schema_valid=Profile.valid(reloaded.data);proof.authority_bound=reloaded.authority_submit.is_valid();proof.profile_path=reloaded.path
	proof.original_compound_result=present and proof.raw_array_equal and int(reloaded.data.inventory.get(spec.package_id,0))==1
	print("SAVED_BYTES_TYPED_PREDICATES_JSON="+JSON.stringify(proof))
	check(proof.reloaded_file_sha256==spec.input_sha256,"Loader leaves accepted saved bytes unchanged")
	check(proof.schema_valid and not proof.authority_bound,"Actual offline loader schema/authority contract")
	check(proof.raw_array_equal or proof.get("numeric_grid_type_transition_only",false),"Raw pin mismatch limited to observed numeric grid type transition")
	check(Guard.matches(expected,pins,inventory),"Complete strict semantic pins and inventory positive")
	if pins is Array:
		for key in ["id","name","node","role","connector"]:
			var mutated: Array=pins.duplicate(true);mutated[0][key]="mutated_"+str(mutated[0][key])
			check(not Guard.matches(expected,mutated,inventory),"Reject mutated pin "+key)
		var changed: Array=pins.duplicate(true);changed.reverse();check(not Guard.matches(expected,changed,inventory),"Reject pin order change")
		changed=pins.duplicate(true);changed[0].position.x=float(changed[0].position.x)+1.;check(not Guard.matches(expected,changed,inventory),"Reject changed coordinate value")
		changed=pins.duplicate(true);changed[0].position.x=.5;check(not Guard.matches(expected,changed,inventory),"Reject fractional coordinate")
		changed=pins.duplicate(true);changed[0].position.x="0";check(not Guard.matches(expected,changed,inventory),"Reject numeric string coordinate")
		changed=pins.duplicate(true);changed[0].position.x=NAN;check(not Guard.matches(expected,changed,inventory),"Reject nonfinite coordinate")
		changed=pins.duplicate(true);changed[0].erase("name");check(not Guard.matches(expected,changed,inventory),"Reject missing pin field")
		changed=pins.duplicate(true);changed[0].extra="unexpected";check(not Guard.matches(expected,changed,inventory),"Reject extra pin field")
		changed=pins.duplicate(true);changed.remove_at(0);check(not Guard.matches(expected,changed,inventory),"Reject removed pin")
		changed=pins.duplicate(true);changed[0].position.extra=0;check(not Guard.matches(expected,changed,inventory),"Reject extra coordinate key")
	for i in 6:
		var wrong: Variant=[0,2,1.5,"1",true,NAN][i]
		check(not Guard.matches(expected,pins,wrong),"Reject invalid inventory variant "+str(i))
	var report:={"scope":"J3 saved-byte contract only, not manual practice coverage","checks":checks,"failures":failures,"proof":proof,"negative_cases":outcomes,"input_timing":spec.capture_timing,"original_J2_failure":"preserved, not retagged"}
	file=FileAccess.open(OS.get_environment("LABVOLT_PRACTICE_WORK").path_join("reload-contract-result.json"),FileAccess.WRITE);file.store_string(JSON.stringify(report));file.close()
	print("RELOAD CONTRACT checks=",checks," failures=",failures)
	quit(1 if failures else 0)
