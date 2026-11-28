extends SceneTree
## Run with isolated Godot user data. Check the bytes on disk as well as the
## playable fallback: a successful-looking class must not erase a saved campus.
const Legacy=preload("res://tests/campus/academics/dossier/legacy_population_fixture.gd")
const Population=preload("res://scripts/campus/academics/student_population.gd")
const Memory=preload("res://scripts/campus/academics/character_memory.gd")
const PRIMARY_DAMAGE:="{interrupted campus write"
const BACKUP_DAMAGE:="a damaged previous campus"
const SPECIAL_ID:="campus_student_24"
var failures: Array[String]=[]
var paths: Array[String]=[]
var prefix:=""
var checks:=0

func check(condition: bool,message: String) -> void:
	checks+=1
	if not condition:failures.append(message)

func _initialize() -> void:
	prefix="population-corruption-%d"%Time.get_ticks_usec()
	_missing_and_double_corruption()
	_known_identity_survives_damage()
	_backup_recovery_preserves_evidence()
	_host_switching_retains_unsaved_identities()
	_bounded_cache_never_evicts_unsaved_people()
	_backup_namespace_and_legacy_migration()
	_schema_corruption()
	_cleanup()
	for failure in failures:printerr("FAIL: "+failure)
	print("STUDENT_POPULATION_CORRUPTION %s (%d checks): damaged bytes preserved, backup recovery, session identity, host isolation, bounded cache"%["PASS" if failures.is_empty() else "FAIL",checks])
	quit(0 if failures.is_empty() else 1)

func _path(label: String) -> String:
	var result:="user://"+prefix+"-"+label+".json"
	paths.append(result)
	return result

func _scoped(label: String) -> String:
	var profile_id:=prefix+"-"+label
	paths.append(Memory.profile_prefix(profile_id)+".population.json")
	return profile_id

func _write(destination: String,content: String) -> void:
	DirAccess.make_dir_recursive_absolute(destination.get_base_dir())
	var file:=FileAccess.open(destination,FileAccess.WRITE)
	check(file!=null,"fixture can write "+destination.get_file())
	if file==null:return
	file.store_string(content);file.flush()
	check(file.get_error()==OK,"fixture flushes "+destination.get_file())
	file.close()

func _damage(path: String) -> void:
	_write(path,PRIMARY_DAMAGE)
	_write(path+".bak",BACKUP_DAMAGE)

func _unchanged_damage(path: String) -> void:
	check(FileAccess.get_file_as_string(path)==PRIMARY_DAMAGE,"damaged primary is byte-for-byte unchanged")
	check(FileAccess.get_file_as_string(path+".bak")==BACKUP_DAMAGE,"damaged backup is byte-for-byte unchanged")
	check(not FileAccess.file_exists(path+".tmp"),"blocked persistence never opens a replacement temporary file")

func _saved_roster(destination: String) -> RefCounted:
	var roster:=Population.new()
	Legacy.bind(roster,destination)
	check(not roster.load_population(),"a missing campus keeps the existing new-campus return value")
	check(roster.people.is_empty() and FileAccess.file_exists(destination),"a fresh campus persists an empty reserve without synthesizing people")
	Legacy.seed(roster,30)
	var person: Dictionary=roster.people[SPECIAL_ID]
	person.name="Avery Saved-Identity"
	person.biography.saved_detail="I repaired a hand-built radio with my aunt."
	person.traits.confidence=.91;person.traits.shyness=.87
	person.appearance.hair="Bun";person.appearance.top="375a86"
	roster.dirty=true
	Legacy.sync(roster)
	check(roster.save_population()==OK and roster.save_population()==OK,"custom identities are saved in primary and backup")
	return roster

func _identity_intact(roster: RefCounted,message: String) -> void:
	var person: Dictionary=roster.profile_for(SPECIAL_ID)
	check(person.get("name","")=="Avery Saved-Identity",message+": name")
	check(person.get("biography",{}).get("saved_detail","")=="I repaired a hand-built radio with my aunt.",message+": history")
	check(is_equal_approx(float(person.get("traits",{}).get("confidence",0.)),.91) and is_equal_approx(float(person.get("traits",{}).get("shyness",0.)),.87),message+": independent traits")
	check(person.get("appearance",{}).get("hair","")=="Bun" and person.get("appearance",{}).get("top","")=="375a86",message+": appearance")

func _missing_and_double_corruption() -> void:
	var destination:=_path("double")
	_saved_roster(destination)
	_damage(destination)
	var fallback:=Population.new()
	Legacy.bind(fallback,destination)
	check(not fallback.load_population(),"two damaged copies are not reported as a loaded save")
	check(fallback.persistence_blocked and not fallback.profile_blocked,"save damage does not prohibit a session roster")
	check(fallback.last_load_error==ERR_FILE_CORRUPT and fallback.last_save_error==ERR_FILE_CORRUPT,"damage is reported explicitly for loading and persistence")
	check(fallback.people.size()==30 and fallback.available({},6,42).size()==6,"damaged population reuses separately persisted valid identities")
	check(fallback.save_population()==ERR_FILE_CORRUPT,"temporary fallback cannot replace damaged save")
	_unchanged_damage(destination)
	fallback.people.campus_student_00.name="Session identity remains"
	fallback.people.campus_student_00.biography.session_detail="Remember this during the current session."
	Legacy.seed(fallback,31)
	check(not fallback.load_population(),"repeated load does not pretend unsaved fallback is durable")
	check(fallback.people.size()==31 and fallback.profile_for("campus_student_00").name=="Session identity remains","repeated load preserves session roster and its generated IDs")
	check(fallback.profile_for("campus_student_00").biography.session_detail=="Remember this during the current session.","repeated load retains session history")
	var status:=fallback.diagnostics()
	check(status.persistence_state=="blocked_unsaved" and status.unsaved_data,"diagnostics distinguish session-only people from saved people")
	_unchanged_damage(destination)
	var lone_backup:=_path("only-bad-backup")
	_write(lone_backup+".bak",BACKUP_DAMAGE)
	var blocked:=Population.new()
	Legacy.bind(blocked,lone_backup)
	check(not blocked.load_population() and blocked.persistence_blocked,"a damaged backup without a primary is not a missing campus")
	check(not FileAccess.file_exists(lone_backup) and FileAccess.get_file_as_string(lone_backup+".bak")==BACKUP_DAMAGE,"fallback does not create a new primary over a damaged-only backup")

func _known_identity_survives_damage() -> void:
	var destination:=_path("already-loaded")
	var roster:=_saved_roster(destination)
	_damage(destination)
	check(not roster.load_population() and roster.persistence_blocked,"reload detects on-disk damage after a successful load")
	_identity_intact(roster,"previously loaded identity remains available")
	check(roster.people.size()==30,"reload retains all known students instead of rebuilding 24")
	_unchanged_damage(destination)
	var direct_path:=_path("damaged-before-save")
	var direct:=_saved_roster(direct_path)
	_damage(direct_path)
	direct.people[SPECIAL_ID].biography.new_detail="An unsaved continuation."
	direct.dirty=true
	check(direct.save_population()==ERR_FILE_CORRUPT and direct.persistence_blocked,"save independently detects later corruption before writing")
	_identity_intact(direct,"save failure retains known identity")
	_unchanged_damage(direct_path)

func _backup_recovery_preserves_evidence() -> void:
	var destination:=_path("backup")
	_saved_roster(destination)
	var valid_backup:=FileAccess.get_file_as_bytes(destination+".bak")
	_write(destination,PRIMARY_DAMAGE)
	var recovered:=Population.new()
	Legacy.bind(recovered,destination)
	check(recovered.load_population() and recovered.recovered_backup,"a valid backup recovers the saved campus")
	check(not recovered.persistence_blocked and recovered.last_save_error==OK and not recovered.dirty,"recovered roster safely repairs the primary")
	_identity_intact(recovered,"backup restores saved person")
	var archive:=destination+".corrupt-"+PRIMARY_DAMAGE.sha256_text()
	check(FileAccess.file_exists(archive) and FileAccess.get_file_as_string(archive)==PRIMARY_DAMAGE,"repair retains the original corrupt primary bytes in a named archive")
	check(archive in recovered.diagnostics().preserved_corrupt_paths,"recovery reports where damaged evidence was retained")
	check(FileAccess.get_file_as_bytes(destination+".bak")==valid_backup,"recovery never overwrites the valid backup with corrupt data")
	var restarted:=Population.new()
	Legacy.bind(restarted,destination)
	check(restarted.load_population() and not restarted.recovered_backup,"repaired primary loads normally on restart")
	_identity_intact(restarted,"restart preserves recovered identities")
	_write(destination+".bak",BACKUP_DAMAGE)
	restarted.people[SPECIAL_ID].biography.new_detail="A new detail after recovery."
	restarted.dirty=true
	check(restarted.save_population()==OK,"a valid primary can safely replace a corrupt backup")
	check(FileAccess.get_file_as_string(destination+".bak.corrupt-"+BACKUP_DAMAGE.sha256_text())==BACKUP_DAMAGE,"backup replacement also preserves the corrupt backup bytes")

func _host_switching_retains_unsaved_identities() -> void:
	var host_a:=_scoped("host-a")
	var host_b:=_scoped("host-b")
	var a_path:=Memory.profile_prefix(host_a)+".population.json"
	_damage(a_path)
	var roster:=Population.new()
	check(roster.set_host_profile(host_a)==OK and not roster.load_population(),"damaged scoped profile selects an empty blocked campus")
	check(roster.people.is_empty(),"corruption without any valid identity source creates no generic people")
	Legacy.seed(roster,24)
	roster.people.campus_student_00.name="Only host A knows this name"
	roster.people.campus_student_00.biography.private_detail="Only host A heard this story."
	roster.people.campus_student_00.appearance.hair="Bun"
	Legacy.seed(roster,29)
	Legacy.sync(roster)
	check(roster.set_host_profile(host_b)==OK,"another host can play while host A's damaged save stays blocked")
	roster.load_population()
	Legacy.seed(roster,24)
	check(not roster.profile_for("campus_student_00").biography.has("private_detail") and roster.profile_for("campus_student_00").name!="Only host A knows this name","host B does not inherit host A's temporary identity or history")
	check(roster.diagnostics().cached_unsaved_profiles==1 and not roster.diagnostics().profile_cache_durable,"inactive session state is explicitly temporary and cached by owner")
	roster.people.campus_student_00.biography.host_b_detail="A different host's history."
	roster.dirty=true
	Legacy.sync(roster)
	check(roster.set_host_profile(host_a)==OK and not roster.load_population(),"returning to damaged host restores its unsaved roster")
	check(roster.people.size()==29 and roster.profile_for("campus_student_00").name=="Only host A knows this name","host switch retains temporary identities and expanded roster")
	check(roster.profile_for("campus_student_00").biography.get("private_detail","")=="Only host A heard this story." and not roster.profile_for("campus_student_00").biography.has("host_b_detail"),"host switch retains only the correct private history")
	check(roster.profile_for("campus_student_00").appearance.hair=="Bun" and roster.persistence_blocked,"host switch restores appearance and write block")
	_unchanged_damage(a_path)
	check(roster.set_host_profile("")==ERR_INVALID_PARAMETER and roster.profile_blocked,"invalid profile selection fails closed")
	check(roster.available({},6,12).is_empty(),"failed selection cannot expose the old host's roster through allocation")
	check(roster.set_host_profile(host_a)==OK and not roster.load_population(),"reselecting the original host restores authorization without rerolling")
	check(roster.profile_for("campus_student_00").name=="Only host A knows this name","failed selection retains recoverable in-memory identity")
	check(roster.set_host_profile(host_b)==OK and roster.load_population(),"normal host saves remain durable across damaged-profile visits")
	check(roster.profile_for("campus_student_00").biography.get("host_b_detail","")=="A different host's history.","host B's saved history survives a round trip")
	var b_path:=Memory.profile_prefix(host_b)+".population.json"
	_damage(b_path)
	check(not roster.dirty,"on-disk corruption can occur while the loaded roster is clean")
	check(roster.set_host_profile(host_a)==OK,"switch checks for later disk corruption even without in-memory edits")
	roster.load_population()
	check(roster.set_host_profile(host_b)==OK and not roster.load_population(),"clean roster detected as damaged is retained under its owner")
	check(roster.profile_for("campus_student_00").biography.get("host_b_detail","")=="A different host's history." and roster.persistence_blocked,"host switch does not discard the last known saved identities after later damage")
	_unchanged_damage(b_path)

func _bounded_cache_never_evicts_unsaved_people() -> void:
	var roster:=Population.new()
	var hosts: Array[String]=[]
	for index in Population.MAX_CACHED_PROFILES+2:
		var host:=_scoped("cache-%d"%index)
		hosts.append(host)
		_damage(Memory.profile_prefix(host)+".population.json")
	for index in Population.MAX_CACHED_PROFILES+1:
		check(roster.set_host_profile(hosts[index])==OK,"cache admits a bounded outgoing roster %d"%index)
		roster.load_population()
		Legacy.seed(roster,24)
		roster.people.campus_student_00.name="Unsaved host %d"%index
		Legacy.sync(roster)
	check(roster.set_host_profile(hosts.back())==ERR_OUT_OF_MEMORY,"full cache refuses a switch instead of evicting unsaved identities")
	check(roster.people.campus_student_00.name=="Unsaved host %d"%Population.MAX_CACHED_PROFILES and roster.profile_blocked,"failed switch retains current roster and fails closed")
	check(roster.diagnostics().cached_unsaved_profiles==Population.MAX_CACHED_PROFILES,"unsaved roster cache has a fixed maximum")
	check(roster.set_host_profile(hosts[0])==OK,"returning to an existing entry works even at cache capacity")
	roster.load_population()
	check(roster.people.campus_student_00.name=="Unsaved host 0" and roster.persistence_blocked,"full-cache return restores the exact earlier identity")
	check(roster.set_host_profile(hosts[Population.MAX_CACHED_PROFILES])==OK,"outgoing state is retained while consuming a cache entry")
	roster.load_population()
	check(roster.people.campus_student_00.name=="Unsaved host %d"%Population.MAX_CACHED_PROFILES,"cache-capacity transition loses no in-memory identities")

func _backup_namespace_and_legacy_migration() -> void:
	var legacy:="user://campus_student_population.json"
	var marker:="user://character_memory/legacy_owner.txt"
	# Never alter an existing real legacy save when someone runs this test
	# without the documented isolated user-data environment.
	if FileAccess.file_exists(legacy) or FileAccess.file_exists(legacy+".bak") or FileAccess.file_exists(marker):
		print("STUDENT_POPULATION_CORRUPTION SKIP legacy fixture: existing user data")
		return
	paths.append(legacy);paths.append(marker)
	var legacy_roster:=_saved_roster(legacy)
	legacy_roster.people[SPECIAL_ID].name="Legacy campus person"
	legacy_roster.dirty=true
	check(legacy_roster.save_population()==OK,"legacy migration fixture saves")
	var host:=_scoped("backup-owner")
	var selected:=Memory.profile_prefix(host)+".population.json"
	_saved_roster(selected)
	DirAccess.remove_absolute(selected)
	var scoped:=Population.new()
	check(scoped.set_host_profile(host)==OK,"host with missing primary and valid backup selects")
	check(not FileAccess.file_exists(selected),"profile selection does not copy legacy people over an existing backup")
	check(scoped.load_population() and scoped.recovered_backup,"missing primary recovers its own scoped backup")
	_identity_intact(scoped,"scoped backup wins over unrelated legacy roster")
	_damage(legacy)
	var first_owner:=_scoped("damaged-legacy-owner")
	var migrated:=Population.new()
	check(migrated.set_host_profile(first_owner)==OK and not migrated.load_population() and migrated.persistence_blocked,"first owner adopts corruption status instead of discarding damaged legacy identities")
	_unchanged_damage(legacy)
	_unchanged_damage(migrated.path)
	var other:=Population.new()
	check(other.set_host_profile(_scoped("different-legacy-owner"))==OK,"different owner can open an independent campus")
	other.load_population()
	check(not other.persistence_blocked,"damaged legacy state is not copied to every host")

func _schema_corruption() -> void:
	for content in ["{\"version\":[],\"people\":{}}","{\"version\":1,\"people\":{},\"next_index\":{}}","{\"version\":1,\"people\":{},\"next_index\":2.5}"]:
		var destination:=_path("schema-%d"%checks)
		_write(destination,content)
		var roster:=Population.new()
		Legacy.bind(roster,destination)
		check(not roster.load_population() and roster.persistence_blocked,"invalid metadata is corruption, without type-conversion runtime errors")
		check(FileAccess.get_file_as_string(destination)==content,"invalid metadata remains recoverable on disk")

func _cleanup() -> void:
	for destination in paths:
		var directory:=DirAccess.open(destination.get_base_dir())
		if directory==null:continue
		for file in directory.get_files():
			if file==destination.get_file() or file.begins_with(destination.get_file()+"."):
				DirAccess.remove_absolute(destination.get_base_dir().path_join(file))
