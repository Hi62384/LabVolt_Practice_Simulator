extends SceneTree
## Real filesystem failure/recovery; no provider or physical devices.
const Archive=preload("res://scripts/campus/academics/student_social_archive.gd")
const Memory=preload("res://scripts/campus/academics/character_memory.gd")
var checks:=0
var failures: Array[String]=[]

func check(value: bool,message: String) -> void:
	checks+=1
	if not value:failures.append(message)

func _initialize() -> void:
	var owner:="social-durability-"+str(Time.get_ticks_usec())
	var archive:=Archive.new()
	check(archive.configure(owner)==OK,"Local social archive opens")
	var memory:=Memory.new()
	var actor:="campus_student_"+"a".repeat(32)
	var player:="b".repeat(48)
	memory.remember(actor,player,"study",1700000000)
	var snapshot:=memory.export_social_record(actor,player)
	# A directory at the staging-file path reproduces an ordinary write failure
	# without permission-dependent chmod behavior or modifying tracked files.
	check(DirAccess.make_dir_recursive_absolute(archive.path+".tmp")==OK,"Create unavailable staging target")
	var failed:=archive.observe(actor,player,snapshot)
	check(failed.is_empty() and archive.last_error!=OK,"Unsaved social state is never returned as a durable receipt")
	check(archive.configure(owner+"-other")!=OK and archive.owner==owner,"Profile switch preserves unsaved owner's social state")
	check(DirAccess.remove_absolute(archive.path+".tmp")==OK,"Storage becomes available again")
	var recovered:=archive.observe(actor,player,snapshot)
	check(not recovered.is_empty() and archive.last_error==OK,"Identical update retries persistence after write recovery")
	var restart:=Archive.new();restart.configure(owner)
	check(restart.records.has(actor+":"+player),"Recovered receipt survives process-equivalent reload")
	var newer:=snapshot.duplicate(true)
	newer.relationship.dimensions.friendship=.72
	var incoming:=archive.observe(actor,player,newer)
	var malformed:=newer.duplicate(true);malformed.relationship=[]
	var before:=JSON.stringify(restart.records)
	check(not restart.receive(incoming,malformed),"Invalid merged memory is rejected before archive mutation")
	check(JSON.stringify(restart.records)==before,"Rejected merge preserves healthy in-memory and saved records")
	check(restart.receive(incoming,newer),"Valid causal descendant persists after rejected merge")
	var healthy:=Archive.new();healthy.configure(owner)
	check(healthy.records.get(actor+":"+player,{}).get("digest","")==Archive.digest(newer),"Valid merged state survives reload")
	for failure in failures:printerr("FAIL: "+failure)
	print("STUDENT_SOCIAL_DURABILITY %s (%d checks; real filesystem failure and recovery)"%["PASS" if failures.is_empty() else "FAIL",checks])
	quit(0 if failures.is_empty() else 1)
