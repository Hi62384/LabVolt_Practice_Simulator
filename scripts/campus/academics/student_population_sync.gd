extends Node
## One bounded session exchange. Index pages identify candidates; complete
## dossiers are requested only for a small ready reserve or active classmates.
const Population=preload("res://scripts/campus/academics/student_population.gd")
const Memory=preload("res://scripts/campus/academics/character_memory.gd")
const Store=preload("res://scripts/campus/academics/character_dossier_store.gd")
const Programs=preload("res://scripts/campus/academics/academic_programs.gd")
const Archive=preload("res://scripts/campus/academics/student_social_archive.gd")
const Voices=preload("res://scripts/campus/academics/teacher_voice_profiles.gd")
const MAX_MANIFEST:=4096
const READY_PER_COURSE:=6
const MAX_PACKET_BYTES:=786432
var game: Node
var population: RefCounted
var brain: RefCounted
var archive:=Archive.new()
var identity:=""
var manifests: Dictionary={}
var manifest_offsets: Dictionary={}
var requested: Dictionary={}
var _pending_bonds: Dictionary={}
var pending: Dictionary={}
var sent: Dictionary={}
var peer_identities: Dictionary={}
var _bound_ready:=false
var _bound_server:=false
var _bound_brain: RefCounted
var _elapsed:=0.
var _refresh:=0.
var last_error:=""

func configure(owner: Node) -> void:
	game=owner
	if game.session.has_signal("leaving") and not game.session.leaving.is_connected(_flush):game.session.leaving.connect(_flush)
	set_process(true)

func _bind() -> bool:
	if not _game_ready():return false
	var selected:=str(game.school.local_identity)
	if selected.is_empty():return false
	var server:=multiplayer.is_server()
	if _bound_ready and selected==identity and population!=null and brain!=null and _bound_server==server:
		if not server or (brain==game.faculty.brain and population==game.lecture_classes.classroom_students.population and brain.host_profile()==identity and population._host_profile==identity):return true
	if _bound_brain!=null and _bound_brain.social_record_changed.is_connected(_on_social_changed):_bound_brain.social_record_changed.disconnect(_on_social_changed)
	_bound_ready=false
	identity=selected
	_bound_server=server
	manifests.clear();manifest_offsets.clear();requested.clear();pending.clear();sent.clear();peer_identities.clear()
	if multiplayer.is_server():
		population=game.lecture_classes.classroom_students.population
		brain=game.faculty.brain
		if population==null or brain==null:return false
		if brain.host_profile()!=identity or population._host_profile!=identity:return false
	else:
		population=Population.new()
		if population.set_host_profile(identity)!=OK:return false
		population.load_population()
		brain=Memory.new()
		if brain.set_host_profile(identity)!=OK or not brain.load_memory():return false
	archive.configure(identity)
	_bound_brain=brain
	if server and not brain.social_record_changed.is_connected(_on_social_changed):brain.social_record_changed.connect(_on_social_changed)
	# Recover the narrowly scoped social receipt if a previous process stopped
	# after its archive rename but before the main memory snapshot was flushed.
	for receipt in archive.records.values():
		if str(receipt.get("player",""))!=identity:continue
		var local:=str(population.local_id(str(receipt.get("character",""))))
		if local.is_empty() or brain.relationships.has(local+":"+identity):continue
		var snapshot: Dictionary=receipt.snapshot.duplicate(true)
		_remap_snapshot(snapshot,str(receipt.character),local,identity,identity)
		brain.import_social_record(local,identity,snapshot,true)
	brain.save_memory()
	_bound_ready=true
	return true

func _process(delta: float) -> void:
	_elapsed+=delta
	if _elapsed<2.:return
	_elapsed=0.
	if not _bind():return
	if not multiplayer.is_server():return
	_refresh+=2.
	var online: bool=bool(game.session.online)
	var peers: Array=game.school.identities.keys()
	for peer in peer_identities.keys():
		if peer not in peers or str(game.school.identities.get(peer,""))!=str(peer_identities[peer]):
			# Admitted people remain in the authoritative local collection; only
			# the unavailable device's future fetch work is discarded.
			peer_identities.erase(peer);manifests.erase(peer);manifest_offsets.erase(peer);requested.erase(peer);pending.erase(peer)
	for peer in peers:
		if int(peer)==1 or not online:continue
		var player:=str(game.school.identities[peer])
		if player.is_empty():continue
		if not peer_identities.has(peer) or _refresh>=30.:
			peer_identities[peer]=player
			if not manifests.has(peer):manifests[peer]={}
			manifest_offsets[peer]=0
			_manifest_request.rpc_id(int(peer),0)
	if _refresh>=30.:_refresh=0.
	for peer in pending:
		var queue: Array=pending[peer]
		for _index in mini(2,queue.size()):
			var id:=str(queue.pop_front())
			requested.get_or_add(peer,{})[id]=Time.get_ticks_msec()
			_person_request.rpc_id(int(peer),id)
	_sync_active_records()

func prepare_course(course: String) -> void:
	if course not in Programs.COURSES or not multiplayer.is_server():return
	for peer in manifests:_queue_candidates(int(peer),course)

func _queue_candidates(peer: int,course: String) -> void:
	var ready:=0
	var candidates: Array=manifests.get(peer,{}).values()
	candidates.sort_custom(func(a,b):return int(a.get("appearances",0))>int(b.get("appearances",0)))
	for item in candidates:
		if course not in Programs.courses_for(str(item.get("program",""))):continue
		if ready>=READY_PER_COURSE:break
		ready+=1
		var id:=str(item.id)
		var local:=str(population.local_id(id))
		var own_digest:=str(item.get("social_digest",""))
		var known_digest:=str(archive.records.get(id+":"+str(peer_identities.get(peer,"")),{}).get("digest",""))
		if not local.is_empty() and int(item.get("revision",1))<=int(population.people[local].get("dossier_revision",1)) and (own_digest.is_empty() or own_digest==known_digest):continue
		var queue: Array=pending.get_or_add(peer,[])
		if not requested.get(peer,{}).has(id) and id not in queue and queue.size()<32:queue.append(id)

@rpc("authority","call_remote","reliable")
func _manifest_request(offset: int) -> void:
	if multiplayer.is_server() or not _bind() or offset<0 or offset>=MAX_MANIFEST:return
	var entries: Array=population.manifest(offset,32)
	for entry in entries:
		var local:=str(population.local_id(str(entry.id)))
		var snapshot: Dictionary=brain.export_social_record(local,identity)
		if not snapshot.is_empty():
			_remap_snapshot(snapshot,local,str(entry.id),identity,identity)
			entry.social_digest=Archive.digest(snapshot)
	_manifest_reply.rpc_id(1,offset,entries,population.people.size())

@rpc("any_peer","call_remote","reliable")
func _manifest_reply(offset: int,entries: Array,total: int) -> void:
	var peer:=multiplayer.get_remote_sender_id()
	if not _authenticated(peer) or int(manifest_offsets.get(peer,-1))!=offset or offset<0 or offset>=MAX_MANIFEST or entries.size()>32 or total<0 or total>MAX_MANIFEST:return
	if JSON.stringify(entries).to_utf8_buffer().size()>32768:return
	manifest_offsets.erase(peer)
	var target: Dictionary=manifests.get_or_add(peer,{})
	if offset==0:target.clear()
	for entry in entries:
		if not entry is Dictionary or not Population.valid_identity(str(entry.get("id",""))) or not entry.get("name") is String or str(entry.name).length()>80:return
		if not entry.get("program") is String or str(entry.program).length()>160:return
		for key in ["appearances","revision"]:
			var value: Variant=entry.get(key,0)
			if not (value is int or value is float) or not is_finite(float(value)) or float(value)<0 or float(value)>1000000:return
		if not entry.get("social_digest","") is String or str(entry.get("social_digest","")).length()>64:return
		if target.size()>=MAX_MANIFEST and not target.has(str(entry.id)):return
		target[str(entry.id)]={"id":str(entry.id),"name":str(entry.name),"program":str(entry.program),"appearances":clampi(int(entry.get("appearances",0)),0,1000000),"revision":clampi(int(entry.get("revision",1)),1,1000000),"social_digest":str(entry.get("social_digest",""))}
	if offset+entries.size()<total and entries.size()==32:
		manifest_offsets[peer]=offset+32
		_manifest_request.rpc_id(peer,offset+32)
	for course in Programs.COURSES:_queue_candidates(peer,course)

@rpc("authority","call_remote","reliable")
func _person_request(id: String) -> void:
	if multiplayer.is_server() or not _bind() or not Population.valid_identity(id):return
	var payload:=_export(id,identity)
	if not payload.is_empty():_person_reply.rpc_id(1,payload)

@rpc("any_peer","call_remote","reliable")
func _person_reply(payload: Dictionary) -> void:
	var peer:=multiplayer.get_remote_sender_id()
	var id:=str(payload.get("person",{}).get("id",""))
	if not _authenticated(peer) or not requested.get(peer,{}).has(id):return
	requested[peer].erase(id)
	if JSON.stringify(payload).to_utf8_buffer().size()>MAX_PACKET_BYTES:return
	_receive(payload,str(game.school.identities[peer]),peer)

func _authenticated(peer: int) -> bool:
	return multiplayer.is_server() and peer>1 and is_instance_valid(game) and game.school.identities.has(peer) and str(peer_identities.get(peer,""))==str(game.school.identities[peer])

func _export(id: String,player: String) -> Dictionary:
	var local:=str(population.local_id(id))
	if local.is_empty():return {}
	var person: Dictionary=population.export_person(id)
	if person.is_empty():return {}
	var profile: Dictionary=population.profile_for(local)
	var data:={"person":person,"social":{},"npc_bonds":[],"canon":brain.export_identity_canon(profile)}
	var voice:=Voices.portable_profile(profile)
	if not voice.is_empty():
		voice.character_id=id
		data.voice=voice
	var snapshot: Dictionary=brain.export_social_record(local,player)
	if not snapshot.is_empty():
		_remap_snapshot(snapshot,local,id,player,player)
		data.social=archive.observe(id,player,snapshot)
	# Public NPC-to-NPC social bonds contain neither human dialogue nor grades.
	for other in population.people:
		if other==local or data.npc_bonds.size()>=8:continue
		var bond: Dictionary=brain.export_social_record(local,str(other))
		if bond.is_empty():continue
		var other_global:=str(population.profile_for(str(other)).persistent_id)
		_remap_snapshot(bond,local,id,str(other),other_global)
		data.npc_bonds.append(archive.observe(id,other_global,bond))
		if JSON.stringify(data).to_utf8_buffer().size()>MAX_PACKET_BYTES:data.npc_bonds.pop_back();break
	return data if JSON.stringify(data).to_utf8_buffer().size()<=MAX_PACKET_BYTES else {}

func _receive(payload: Dictionary,player: String,peer: int) -> bool:
	if not payload.get("person") is Dictionary:return false
	var accepted: Dictionary=population.import_person(payload.person,peer)
	if not accepted.get("ok",false):last_error=str(accepted.get("error","Profile rejected."));return false
	var local:=str(accepted.id)
	var profile: Dictionary=population.profile_for(local)
	if payload.get("voice") is Dictionary:
		var voice_record: Dictionary=payload.voice.duplicate(true)
		if str(voice_record.get("character_id",""))!=str(accepted.persistent_id):return false
		voice_record.character_id=local
		var voice_error:=Voices.accept_portable_profile(profile,voice_record)
		if voice_error==ERR_ALREADY_EXISTS:last_error="Contributed voice conflicts with the saved permanent voice; the saved identity was retained."
		elif voice_error!=OK:last_error="Saved custom voice is unavailable in this session; its identity was retained."
	if payload.get("canon") is Dictionary:
		var canon: Dictionary=brain.import_identity_canon(profile,payload.canon)
		if not canon.get("conflicts",[]).is_empty():last_error="Contradictory personal facts retained for review: "+", ".join(canon.conflicts)
	var social: Variant=payload.get("social",{})
	if social is Dictionary and not social.is_empty():
		if str(social.get("player",""))==player and str(social.get("character",""))==str(accepted.persistent_id):_receive_social(social,local,player)
	var bonds: Variant=payload.get("npc_bonds",[])
	if bonds is Array and bonds.size()<=8:
		for bond in bonds:
			if not bond is Dictionary or str(bond.get("character",""))!=str(accepted.persistent_id):continue
			var other:=str(population.local_id(str(bond.get("player",""))))
			if not other.is_empty():_receive_social(bond,local,other)
			elif Archive.valid(bond) and _pending_bonds.size()<128:_pending_bonds[str(bond.character)+":"+str(bond.player)]=bond.duplicate(true)
	for key in _pending_bonds.keys():
		var bond: Dictionary=_pending_bonds[key]
		var actor:=str(population.local_id(str(bond.character)))
		var other:=str(population.local_id(str(bond.player)))
		if not actor.is_empty() and not other.is_empty():_receive_social(bond,actor,other);_pending_bonds.erase(key)
	brain.save_memory()
	return true

func _receive_social(entry: Dictionary,local: String,player: String) -> void:
	var kind:=archive.classify(entry)
	if kind in ["invalid","older"]:return
	if kind=="same" and brain.relationships.has(local+":"+player):return
	var snapshot: Dictionary=entry.snapshot.duplicate(true)
	_remap_snapshot(snapshot,str(entry.character),local,str(entry.player),player)
	if not brain.import_social_record(local,player,snapshot,kind in ["new","descendant"]):return
	var merged: Dictionary=brain.export_social_record(local,player)
	_remap_snapshot(merged,local,str(entry.character),player,str(entry.player))
	archive.receive(entry,merged)

static func _remap_snapshot(snapshot: Dictionary,old_character: String,new_character: String,old_player: String,new_player: String) -> void:
	for episode in snapshot.get("relationship",{}).get("episodes",[]):
		if episode.get("character")==old_character:episode.character=new_character
		if episode.get("speaker")==old_player:episode.speaker=new_player

func _sync_active_records() -> void:
	if population==null:return
	for activity in game.lecture_classes.classes.values():
		for id in activity.get("classmates",{}):
			var profile: Dictionary=population.profile_for(str(id))
			if profile.is_empty():continue
			var global_id:=str(profile.persistent_id)
			for peer in game.school.identities:
				var player:=str(game.school.identities[peer])
				if not activity.get("students",{}).has(player):continue
				var snapshot: Dictionary=brain.export_social_record(str(id),player)
				_remap_snapshot(snapshot,str(id),global_id,player,player)
				var record:=archive.observe(global_id,player,snapshot) if not snapshot.is_empty() else {}
				if int(peer)==1 or not bool(game.session.online):continue
				var key:=str(peer)+":"+global_id
				var fingerprint:=str(record.get("digest",""))+":"+str(profile.get("dossier_revision",0))+":"+str(profile.get("appearances",0))
				if sent.get(key,"")==fingerprint:continue
				var payload:=_export(global_id,player)
				if not payload.is_empty():
					_receive_update.rpc_id(int(peer),payload)
					sent[key]=fingerprint

@rpc("authority","call_remote","reliable")
func _receive_update(payload: Dictionary) -> void:
	if multiplayer.is_server() or not _bind() or JSON.stringify(payload).to_utf8_buffer().size()>MAX_PACKET_BYTES:return
	_receive(payload,identity,1)

func diagnostics() -> Dictionary:
	return {"local_population":population.people.size() if population!=null else 0,"contributors":manifests.size(),"social_records":archive.records.size(),"social_conflicts":archive.conflicts.size(),"last_error":last_error,"storage_error":archive.last_error,"social_storage_blocked":archive.blocked}

func _on_social_changed(character: String,participant: String) -> void:
	if not _game_ready() or not multiplayer.is_server() or population==null or brain==null or not population.people.has(character):return
	var profile: Dictionary=population.profile_for(character)
	var global_id:=str(profile.persistent_id)
	var snapshot: Dictionary=brain.export_social_record(character,participant)
	_remap_snapshot(snapshot,character,global_id,participant,participant)
	archive.observe(global_id,participant,snapshot)
	brain.save_memory()
	if not bool(game.session.online):return
	var audience:={participant:true}
	if population.people.has(participant):
		for activity in game.lecture_classes.classes.values():
			if activity.get("classmates",{}).has(character):
				for player in activity.get("students",{}):audience[str(player)]=true
	for peer in game.school.identities:
		var player:=str(game.school.identities[peer])
		if int(peer)==1 or not audience.has(player):continue
		var payload:=_export(global_id,player)
		if not payload.is_empty():_receive_update.rpc_id(int(peer),payload)

func _flush() -> void:
	if population==null or brain==null:return
	if multiplayer.is_server() and _game_ready():_sync_active_records()
	brain.save_memory()
	if population.dirty:population.save_population()

func _exit_tree() -> void:
	# At teardown the transport may already be closed. Durable local writes are
	# still safe; validated interaction callbacks queued recipient updates earlier.
	if brain!=null:brain.save_memory()
	if population!=null and population.dirty:population.save_population()

func _game_ready() -> bool:
	if not is_instance_valid(game) or game.is_queued_for_deletion():return false
	for field in ["school","faculty","lecture_classes","session"]:
		var node: Variant=game.get(field)
		if not is_instance_valid(node):return false
		if node is Node and node.is_queued_for_deletion():return false
	var students: Variant=game.lecture_classes.get("classroom_students")
	return is_instance_valid(students) and (not students is Node or not students.is_queued_for_deletion())
