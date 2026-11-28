extends SceneTree
## Fault injection at lazy-store boundaries. Real files, synthetic identities;
## malformed metadata must reject without engine errors or cross-owner writes.
const Store=preload("res://scripts/campus/academics/character_dossier_store.gd")
const Population=preload("res://scripts/campus/academics/student_population.gd")
const Memory=preload("res://scripts/campus/academics/character_memory.gd")
const Fixture=preload("res://tests/campus/academics/dossier/dossier_fixture.gd")
var failures: Array[String]=[]
var checks:=0

func check(value: bool,message: String) -> void:
	checks+=1
	if not value:failures.append(message)

func write_file(path: String,text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file:=FileAccess.open(path,FileAccess.WRITE)
	check(file!=null,"Fault fixture opens")
	if file!=null:file.store_string(text);file.flush();file.close()

func complete(id: String,name: String) -> Dictionary:
	var dossier:=Fixture.make(id,name)
	dossier.version=1;dossier.revision=1;dossier.generation={"status":"complete"};dossier.subjects=["ELM253"]
	return dossier

func _initialize() -> void:
	var suffix:=str(Time.get_ticks_usec())
	var owner_a:="scope-a-"+suffix
	var owner_b:="scope-b-"+suffix
	var id:="campus_student_00"
	var population:=Population.new()
	check(population.set_host_profile(owner_a)==OK,"First owner opens")
	Store.dossiers[id]=complete(id,"Only Alice Knows");Store.dirty=true
	check(Store.save()==OK,"First owner's complete identity is durable")
	population.load_population()
	check(population.profile_for(id).get("name")=="Only Alice Knows","First owner's projection is cached")
	var a_path:=population.path
	var b_path:=Memory.profile_prefix(owner_b)+".population.json"
	var b_profile:=Population._create(0);b_profile.name="Only Bob Knows"
	write_file(b_path,JSON.stringify({"version":3,"next_index":1,"requested_size":12,"people":{id:b_profile}}))
	var before_b:=FileAccess.get_sha256(b_path)
	# Fill the documented bounded fallback cache and make the outgoing store's
	# temporary manifest unwritable. No permission assumption is needed as root.
	for index in 8:Store._session_cache["held-"+str(index)]={"dossiers":{},"jobs":{},"blocked":true,"error":ERR_CANT_OPEN}
	Store.dirty=true
	var obstacle:=Store.path+".tmp"
	check(DirAccess.make_dir_recursive_absolute(obstacle)==OK,"Manifest write obstacle created")
	check(population.set_host_profile(owner_b)!=OK,"Failed dossier handoff rejects owner switch")
	check(population._host_profile==owner_a and population.path==a_path and Store.host_identity==owner_a,"Failed handoff preserves one consistent outgoing owner")
	check(population.people.get(id,{}).get("name")=="Only Alice Knows","Failed handoff retains original in-memory identity")
	check(population.set_host_profile(owner_b)!=OK and population.profile_blocked,"Same selection retry stays blocked while obstacle remains")
	check(not population.load_population(),"Failed handoff cannot load a different owner's population")
	check(FileAccess.get_sha256(b_path)==before_b,"Failed switch and retry do not rewrite destination population")
	check(DirAccess.remove_absolute(obstacle)==OK,"Write obstacle removed")
	Store._session_cache.clear()
	check(population.set_host_profile(owner_b)==OK and population.load_population(),"Recovered handoff can be retried normally")
	check(Store.host_identity==owner_b and population.profile_for(id).get("name")=="Only Bob Knows","Recovered owner sees only its own same-ID character")
	var durable_b:=FileAccess.get_sha256(b_path)
	check(Store.set_host_profile(owner_a)==OK,"Independent authority switch fixture opens")
	check(population.profile_for(id).is_empty(),"Old population object cannot project through another owner's store")
	check(not population.load_population() and population.save_population()!=OK,"Mismatched authority blocks load and save")
	check(FileAccess.get_sha256(b_path)==durable_b,"Authority mismatch leaves destination bytes unchanged")
	check(population.set_host_profile(owner_b)==OK and population.profile_for(id).get("name")=="Only Bob Knows","Same-path rebind clears stale authority without foreign projection")
	# Migration can fail after the backing store has already selected its new
	# owner. Fixing the disk obstacle must make a normal retry possible too.
	var owner_c:="scope-migration-"+suffix
	var c_path:="user://character_memory/"+owner_c.sha256_text()+".dossiers.json"
	var c_dossier:=complete(id,"Migration Owner")
	write_file(c_path,JSON.stringify({"version":1,"dossiers":{id:c_dossier},"jobs":{}}))
	check(DirAccess.make_dir_recursive_absolute(c_path+".tmp")==OK,"Incoming migration commit obstacle created")
	check(population.set_host_profile(owner_c)!=OK,"Incoming migration commit failure is reported")
	check(population.profile_for(id).is_empty(),"Post-switch migration failure does not expose a foreign owner")
	var checkpoint:=JSON.stringify(population.people)
	population.record_attendance(id,"ELM253","blocked-handoff-event",[])
	check(JSON.stringify(population.people)==checkpoint,"Blocked handoff cannot mutate the checkpointed outgoing population")
	check(population.set_host_profile(owner_c)!=OK and population.profile_blocked,"Incoming migration retry remains blocked while commit still fails")
	check(DirAccess.remove_absolute(c_path+".tmp")==OK,"Incoming migration obstacle removed")
	check(population.set_host_profile(owner_c)==OK,"Normal retry recovers from failed incoming migration")
	population.load_population()
	check(population._host_profile==owner_c and Store.host_identity==owner_c and population.profile_for(id).get("name")=="Migration Owner","Recovered migration uses only the selected owner's identity")
	var valid:=complete("campus_student_"+"d".repeat(32),"Envelope Fixture")
	var malformed: Array=[]
	for field in ["generation","subjects"]:
		var bad:=valid.duplicate(true);bad[field]=[] if field=="generation" else 1.5;malformed.append(bad)
	for revision in [0,-1,1.5,INF,NAN]:
		var bad:=valid.duplicate(true);bad.revision=revision;malformed.append(bad)
	for bad in malformed:
		var bytes:=JSON.stringify(bad,"",true)
		var digest:=bytes.sha256_text()
		var blob:=Store._blob_path(digest)
		write_file(blob,bytes)
		check(Store._read_blob(blob,str(bad.identity.id),digest).is_empty(),"Malformed saved envelope cannot hydrate")
		check(Store._store_blob(str(bad.identity.id),bad).is_empty(),"Malformed envelope returns normal save rejection")
		check(not Store.import_identity(bad).get("ok",true),"Malformed contributed envelope cannot publish")
	for failure in failures:printerr("FAIL: "+failure)
	print("DOSSIER_SCOPE_FAILURES %s (%d checks)"%["PASS" if failures.is_empty() else "FAIL",checks])
	quit(0 if failures.is_empty() else 1)
