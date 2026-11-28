extends SceneTree
## Actual disk migration, lazy hydration and corruption recovery. Synthetic
## dossiers exercise storage contracts, never live generation quality.
const Store=preload("res://scripts/campus/academics/character_dossier_store.gd")
const Population=preload("res://scripts/campus/academics/student_population.gd")
const Fixture=preload("res://tests/campus/academics/dossier/dossier_fixture.gd")
var checks:=0
var failures: Array[String]=[]
var owner:=""

func check(value: bool,message: String) -> void:
	checks+=1
	if not value:failures.append(message);printerr("LAZY STORE FAIL: "+message)

func write_file(path: String,content: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file:=FileAccess.open(path,FileAccess.WRITE)
	if file==null:check(false,"fixture write opens");return
	file.store_string(content);file.flush();file.close()

func reopen() -> void:
	check(Store.set_host_profile(owner+"-other")==OK,"temporary namespace opens")
	check(Store.set_host_profile(owner)==OK,"original namespace reopens")

func _initialize() -> void:
	owner="lazy-dossier-"+str(Time.get_ticks_usec())
	var path:="user://character_memory/"+owner.sha256_text()+".dossiers.json"
	var legacy:={"version":1,"dossiers":{},"jobs":{}}
	for number in 24:
		var id:="campus_student_"+(owner+str(number)).sha256_text().left(32)
		var dossier:=Fixture.make(id,"Saved Student "+str(number))
		dossier.version=1;dossier.revision=1;dossier.generation={"status":"complete"};dossier.subjects=["ELM253","MTH147"]
		dossier.identity.origin_population="f".repeat(64) if number==0 else owner.sha256_text()
		legacy.dossiers[id]=dossier
	var text:=JSON.stringify(legacy)
	write_file(path,text)
	check(Store.set_host_profile(owner)==OK,"legacy v1 migrates after all blobs commit")
	check(Store.hydrated_count==0 and Store.dossiers.size()==24 and Store.dossiers.values().all(func(entry):return entry.has("_blob")),"migration leaves a cold lightweight manifest")
	check(FileAccess.get_file_as_string(path+".legacy-v1.json")==text,"original legacy bytes remain recoverable")
	var manifest: Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
	check(manifest is Dictionary and manifest.version==2,"manifest storage version is independent of dossier schema")
	check(FileAccess.get_file_as_string(path).length()<text.length()/8,"manifest excludes biography and example bulk")
	var id:=str(legacy.dossiers.keys()[0])
	var selected:=Store.get_dossier(id)
	check(selected.identity.name==legacy.dossiers[id].identity.name and selected.life_history==legacy.dossiers[id].life_history,"selected identity hydrates exactly")
	check(Store.hydrated_count==1,"one selected dossier performs one hydration")
	Store.get_dossier(id)
	check(Store.hydrated_count==1,"selected dossier uses current-session cache")
	check(Store.save()==OK,"lightweight manifest checkpoint saves")
	reopen()
	var population:=Population.new()
	check(population.set_host_profile(owner)==OK,"population shares the existing dossier authority")
	population.load_population()
	check(population.people.size()==24 and population.people.values().all(func(person):return person.get("dossier_ref",false)),"population recovers index rows without eager biographies")
	check(Store.hydrated_count==0,"loading population and index does not hydrate dossiers")
	check(population.people[id].origin_population=="f".repeat(64),"dossier-only recovery preserves a foreign student's original population")
	for person in population.people.values():Store.queue(person)
	check(Store.hydrated_count==0 and Store.jobs.is_empty(),"completed index entries never trigger re-generation or hydration")
	var classmates:=population.available({},3,87,"ELM253")
	check(classmates.size()==3 and Store.hydrated_count==3,"selection hydrates only its three chosen identities")
	check(classmates.all(func(person):return person.has("appearance") and person.has("personality_description")),"selected runtime profiles are complete")
	check(population.save_population()==OK,"lightweight population persists")
	var saved_population: Variant=JSON.parse_string(FileAccess.get_file_as_string(population.path))
	check(saved_population.version==4 and not JSON.stringify(saved_population).contains("personality_description"),"population file stores references rather than duplicate personality prose")
	var origin_before:=str(population.people[id].origin_population)
	reopen()
	var restarted:=Population.new();restarted.set_host_profile(owner);restarted.load_population()
	check(Store.hydrated_count==0 and str(restarted.people[id].origin_population)==origin_before,"cold restart preserves origin without full dossier reads")
	var entry: Dictionary=Store.summary(id)
	var blob:=Store._blob_path(str(entry._blob))
	write_file(blob,"{damaged immutable dossier")
	var corrupt_hash:=FileAccess.get_sha256(blob)
	check(not Store.get_dossier(id).is_empty() and FileAccess.file_exists(blob+".corrupt-"+corrupt_hash),"validated blob backup repairs primary and preserves damaged bytes")
	reopen()
	write_file(blob,"{double primary damage");write_file(blob+".bak","{double backup damage")
	check(Store.get_dossier(id).is_empty() and Store.unavailable.has(id) and Store.dossiers.has(id),"double corruption retains unavailable identity without a replacement")
	check(restarted.profile_for(id).is_empty(),"missing dossier never projects a stub as a playable person")
	Store.queue(restarted.people[id])
	check(not Store.jobs.has(id),"missing established biography cannot be silently regenerated")
	var excluded:={}
	for other in restarted.people:
		if other!=id:excluded[other]=true
	check(restarted.available(excluded,1,4,"ELM253").is_empty() and restarted.people.has(id),"selection omits unavailable identity while retaining its index")
	check(Store.save()==OK,"saving another index update does not erase missing references")
	write_file(path,"{damaged manifest")
	reopen()
	check(Store.recovered_backup and Store.dossiers.size()==24 and Store.hydrated_count==0,"manifest backup restores indexes without eager blobs")
	var interrupted_owner:=owner+"-interrupted"
	var interrupted_path:="user://character_memory/"+interrupted_owner.sha256_text()+".dossiers.json"
	write_file(interrupted_path,text)
	DirAccess.make_dir_recursive_absolute(interrupted_path+".tmp")
	check(Store.set_host_profile(interrupted_owner)!=OK,"failed manifest commit reports migration failure")
	check(FileAccess.get_file_as_string(interrupted_path)==text,"interrupted migration preserves complete legacy authority")
	DirAccess.remove_absolute(interrupted_path+".tmp")
	check(Store.save()==OK,"migration resumes from already committed blobs")
	check(not Store.publish({"identity":[]}).get("ok",true),"malformed generation identity is rejected before nested access")
	print("DOSSIER_LAZY_STORE %s (%d checks)"%["PASS" if failures.is_empty() else "FAIL",checks])
	quit(0 if failures.is_empty() else 1)
