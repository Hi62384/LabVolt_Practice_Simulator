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
const DEPARTURE_TIMEOUT_MS:=2000
const REQUEST_TIMEOUT_MS:=15000
const UPDATE_RECEIPT_TIMEOUT_MS:=5000
const UPDATE_ATTEMPTS:=3
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
var sent_profiles: Dictionary={}
var pending_receipts: Dictionary={}
var peer_identities: Dictionary={}
var _bound_ready:=false
var _bound_server:=false
var _bound_brain: RefCounted
var _bound_transport: MultiplayerPeer
var _elapsed:=0.
var _refresh:=0.
var last_error:=""
var _departure_nonce:=""
var _departure_waiting: Dictionary={}
var _departure_failed:=false
var _departure_requests: Dictionary={}
var _received_update_error:=false
var _received_update_failures: Dictionary={}
var last_departure: Dictionary={}

func configure(owner: Node) -> void:
	game=owner
	if game.session.has_signal("leaving") and not game.session.leaving.is_connected(_flush):game.session.leaving.connect(_flush)
	if game.session.has_method("set_departure_barrier"):game.session.set_departure_barrier(prepare_departure)
	if not multiplayer.peer_disconnected.is_connected(_forget_peer):multiplayer.peer_disconnected.connect(_forget_peer)
	set_process(true)

func _bind() -> bool:
	if not _game_ready():return false
	var selected:=str(game.school.local_identity)
	if selected.is_empty():return false
	var transport: MultiplayerPeer=multiplayer.multiplayer_peer
	if transport==null or transport.get_connection_status()==MultiplayerPeer.CONNECTION_DISCONNECTED:return false
	var server:=multiplayer.is_server()
	if _bound_ready and selected==identity and population!=null and brain!=null and _bound_server==server and _bound_transport==transport:
		if not server or (brain==game.faculty.brain and population==game.lecture_classes.classroom_students.population and brain.host_profile()==identity and population._host_profile==identity):return true
	if _bound_brain!=null and _bound_brain.social_record_changed.is_connected(_on_social_changed):_bound_brain.social_record_changed.disconnect(_on_social_changed)
	_bound_ready=false
	identity=selected
	_bound_server=server
	_bound_transport=transport
	manifests.clear();manifest_offsets.clear();requested.clear();pending.clear();sent.clear();sent_profiles.clear();pending_receipts.clear();peer_identities.clear();_pending_bonds.clear()
	_departure_nonce="";_departure_waiting.clear();_departure_requests.clear();_received_update_error=false;_received_update_failures.clear()
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
	var archive_error:=archive.configure(identity)
	if archive.owner!=identity:
		last_error="The previous profile has unsaved student memories; its local storage must recover before syncing another profile."
		return false
	if archive_error!=OK:last_error="Student social memory storage is unavailable on this device."
	_bound_brain=brain
	if server and not brain.social_record_changed.is_connected(_on_social_changed):brain.social_record_changed.connect(_on_social_changed)
	# Recover the narrowly scoped social receipt if a previous process stopped
	# after its archive rename but before the main memory snapshot was flushed.
	for receipt in archive.records.values():
		if str(receipt.get("player",""))=="_npc_mood":
			var mood_id:=str(population.local_id(str(receipt.get("character",""))))
			if not mood_id.is_empty() and brain.export_mood_record(mood_id).is_empty():brain.import_mood_record(mood_id,receipt.snapshot.get("mood",{}),true)
			continue
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
			_forget_peer(int(peer))
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
	for peer in requested.keys():
		if _expire_requests(int(peer)):
			for course in Programs.COURSES:_queue_candidates(int(peer),course)
	_sync_active_records()
	# A finished class can still have an unacknowledged final memory update.
	# Retry delivery from current local state, without regenerating any AI work.
	for key in pending_receipts.keys():
		var waiting: Dictionary=pending_receipts[key]
		if int(waiting.attempts)>=UPDATE_ATTEMPTS or Time.get_ticks_msec()-int(waiting.sent_at)<UPDATE_RECEIPT_TIMEOUT_MS:continue
		_send_update(int(str(key).get_slice(":",0)),str(key).get_slice(":",1),str(waiting.player),str(waiting.fingerprint))

func prepare_course(course: String) -> void:
	if course not in Programs.COURSES or not multiplayer.is_server():return
	for peer in manifests:_queue_candidates(int(peer),course)

func _queue_candidates(peer: int,course: String) -> void:
	_expire_requests(peer)
	var ready:=0
	var candidates: Array=manifests.get(peer,{}).values()
	candidates.sort_custom(func(a,b):return int(a.get("appearances",0))>int(b.get("appearances",0)))
	for item in candidates:
		if course not in item.get("courses",Programs.courses_for(str(item.get("program","")))):continue
		if ready>=READY_PER_COURSE:break
		ready+=1
		var id:=str(item.id)
		var local:=str(population.local_id(id))
		var own_digest:=str(item.get("social_digest",""))
		var known_digest:=str(archive.records.get(id+":"+str(peer_identities.get(peer,"")),{}).get("digest",""))
		var known_progress: String=Population._digest({"learning":population.people.get(local,{}).get("learning",{}),"weeks":population.people.get(local,{}).get("learning_weeks",{})})
		var mood_digest:=str(item.get("mood_digest",""))
		var known_mood:=str(archive.records.get(id+":_npc_mood",{}).get("digest",""))
		if not local.is_empty() and int(item.get("revision",1))<=int(population.people[local].get("dossier_revision",1)) and (own_digest.is_empty() or own_digest==known_digest) and str(item.get("progress_digest",known_progress))==known_progress and (mood_digest.is_empty() or mood_digest==known_mood):continue
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
		var mood:=_mood_receipt(local,str(entry.id))
		if not mood.is_empty():entry.mood_digest=str(mood.digest)
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
		var courses: Variant=entry.get("courses",Programs.courses_for(str(entry.program)))
		if not courses is Array or courses.size()>Programs.COURSES.size():return
		for course in courses:
			if not course is String or course not in Programs.COURSES:return
		for key in ["appearances","revision"]:
			var value: Variant=entry.get(key,0)
			if not (value is int or value is float) or not is_finite(float(value)) or float(value)<0 or float(value)>1000000:return
		for key in ["social_digest","progress_digest","mood_digest"]:
			if not entry.get(key,"") is String or str(entry.get(key,"")).length()>64:return
		if target.size()>=MAX_MANIFEST and not target.has(str(entry.id)):return
		target[str(entry.id)]={"id":str(entry.id),"name":str(entry.name),"program":str(entry.program),"courses":courses.duplicate(),"appearances":clampi(int(entry.get("appearances",0)),0,1000000),"revision":clampi(int(entry.get("revision",1)),1,1000000),"social_digest":str(entry.get("social_digest","")),"progress_digest":str(entry.get("progress_digest","")),"mood_digest":str(entry.get("mood_digest",""))}
	if offset+entries.size()<total and entries.size()==32:
		manifest_offsets[peer]=offset+32
		_manifest_request.rpc_id(peer,offset+32)
	for course in Programs.COURSES:_queue_candidates(peer,course)

@rpc("authority","call_remote","reliable")
func _person_request(id: String) -> void:
	if multiplayer.is_server() or not _bind() or not Population.valid_identity(id):return
	var payload:=_export(id,identity)
	if not payload.is_empty():_person_reply.rpc_id(1,payload)
	else:_person_unavailable.rpc_id(1,id)

@rpc("any_peer","call_remote","reliable")
func _person_unavailable(id: String) -> void:
	var peer:=multiplayer.get_remote_sender_id()
	if not _authenticated(peer) or not requested.get(peer,{}).has(id):return
	requested[peer].erase(id)
	manifests.get(peer,{}).erase(id)

@rpc("any_peer","call_remote","reliable")
func _person_reply(payload: Dictionary) -> void:
	var peer:=multiplayer.get_remote_sender_id()
	if not _authenticated(peer) or not payload.get("person") is Dictionary:return
	var id:=str(payload.get("person",{}).get("id",""))
	if not requested.get(peer,{}).has(id):return
	requested[peer].erase(id)
	if JSON.stringify(payload).to_utf8_buffer().size()>MAX_PACKET_BYTES:return
	_receive(payload,str(game.school.identities[peer]),peer)

func _expire_requests(peer: int,now:=Time.get_ticks_msec()) -> bool:
	var expired:=false
	var active: Dictionary=requested.get(peer,{})
	for id in active.keys():
		if now-int(active[id])>=REQUEST_TIMEOUT_MS:active.erase(id);expired=true
	return expired

func _authenticated(peer: int) -> bool:
	return multiplayer.is_server() and peer>1 and is_instance_valid(game) and game.school.identities.has(peer) and str(peer_identities.get(peer,""))==str(game.school.identities[peer])

func _export(id: String,player: String) -> Dictionary:
	var local:=str(population.local_id(id))
	if local.is_empty():return {}
	var person: Dictionary=population.export_person(id)
	if person.is_empty():return {}
	var profile: Dictionary=population.profile_for(local)
	var data:={"person":person,"social":{},"npc_bonds":[],"canon":brain.export_identity_canon(profile),"mood":_mood_receipt(local,id)}
	var voice:=Voices.portable_profile(profile)
	if not voice.is_empty():
		voice.character_id=id
		data.voice=voice
	var snapshot: Dictionary=brain.export_social_record(local,player)
	if not snapshot.is_empty():
		_remap_snapshot(snapshot,local,id,player,player)
		data.social=archive.observe(id,player,snapshot)
		if data.social.is_empty():return {}
	# Public NPC-to-NPC social bonds contain neither human dialogue nor grades.
	for other in population.people:
		if other==local or data.npc_bonds.size()>=8:continue
		var bond: Dictionary=brain.export_social_record(local,str(other))
		if bond.is_empty():continue
		var other_global:=str(population.profile_for(str(other)).persistent_id)
		_remap_snapshot(bond,local,id,str(other),other_global)
		var receipt:=archive.observe(id,other_global,bond)
		if receipt.is_empty():return {}
		data.npc_bonds.append(receipt)
		if JSON.stringify(data).to_utf8_buffer().size()>MAX_PACKET_BYTES:data.npc_bonds.pop_back();break
	return data if JSON.stringify(data).to_utf8_buffer().size()<=MAX_PACKET_BYTES else {}

func _receive(payload: Dictionary,player: String,peer: int) -> bool:
	if not payload.get("person") is Dictionary:return false
	var accepted: Dictionary=population.import_person(payload.person,peer) if payload.person.has("dossier") else population.import_progress(payload.person)
	if not accepted.get("ok",false):last_error=str(accepted.get("error","Profile rejected."));return false
	var local:=str(accepted.id)
	var profile: Dictionary=population.profile_for(local)
	var saved:=true
	if payload.get("voice") is Dictionary:
		var voice_record: Dictionary=payload.voice.duplicate(true)
		if str(voice_record.get("character_id",""))!=str(accepted.persistent_id):return false
		voice_record.character_id=local
		var voice_error:=Voices.accept_portable_profile(profile,voice_record)
		if voice_error==ERR_ALREADY_EXISTS:last_error="Contributed voice conflicts with the saved permanent voice; the saved identity was retained."
		elif voice_error!=OK:last_error="Saved custom voice is unavailable in this session; its identity was retained."
	if payload.get("mood") is Dictionary and not payload.mood.is_empty():saved=_receive_mood(payload.mood,local,str(accepted.persistent_id)) and saved
	if payload.get("canon") is Dictionary:
		var canon: Dictionary=brain.import_identity_canon(profile,payload.canon)
		if not canon.get("conflicts",[]).is_empty():last_error="Contradictory personal facts retained for review: "+", ".join(canon.conflicts)
	var social: Variant=payload.get("social",{})
	if social is Dictionary and not social.is_empty():
		if str(social.get("player",""))==player and str(social.get("character",""))==str(accepted.persistent_id):saved=_receive_social(social,local,player) and saved
		else:saved=false
	var bonds: Variant=payload.get("npc_bonds",[])
	if bonds is Array and bonds.size()<=8:
		for bond in bonds:
			if not bond is Dictionary or str(bond.get("character",""))!=str(accepted.persistent_id):continue
			var other:=str(population.local_id(str(bond.get("player",""))))
			if not other.is_empty():saved=_receive_social(bond,local,other) and saved
			elif Archive.valid(bond) and _pending_bonds.size()<128:_pending_bonds[str(bond.character)+":"+str(bond.player)]=bond.duplicate(true)
	for key in _pending_bonds.keys():
		var bond: Dictionary=_pending_bonds[key]
		var actor:=str(population.local_id(str(bond.character)))
		var other:=str(population.local_id(str(bond.player)))
		if not actor.is_empty() and not other.is_empty():
			if _receive_social(bond,actor,other):_pending_bonds.erase(key)
			else:saved=false
	saved=brain.save_memory()==OK and saved
	if not saved:last_error="Student state arrived, but recent memories could not all be saved locally."
	return saved

func _receive_social(entry: Dictionary,local: String,player: String) -> bool:
	var kind:=archive.classify(entry)
	if kind=="invalid":return false
	if kind=="older":return true
	if kind=="same" and brain.relationships.has(local+":"+player):return not archive.dirty or archive.save()==OK
	var snapshot: Dictionary=entry.snapshot.duplicate(true)
	_remap_snapshot(snapshot,str(entry.character),local,str(entry.player),player)
	if not brain.import_social_record(local,player,snapshot,kind in ["new","descendant"]):return false
	var merged: Dictionary=brain.export_social_record(local,player)
	_remap_snapshot(merged,local,str(entry.character),player,str(entry.player))
	return archive.receive(entry,merged)

static func _remap_snapshot(snapshot: Dictionary,old_character: String,new_character: String,old_player: String,new_player: String) -> void:
	var relationship: Variant=snapshot.get("relationship",{})
	if not relationship is Dictionary or not relationship.get("episodes",[]) is Array:return
	for episode in relationship.get("episodes",[]):
		if not episode is Dictionary:continue
		if episode.get("character")==old_character:episode.character=new_character
		if episode.get("speaker")==old_player:episode.speaker=new_player

func _sync_active_records() -> void:
	if population==null:return
	for activity in game.lecture_classes.classes.values():
		for id in activity.get("classmates",{}):
			var profile: Dictionary=population.profile_for(str(id))
			if profile.is_empty():continue
			var global_id:=str(profile.persistent_id)
			var mood:=_mood_receipt(str(id),global_id)
			for peer in game.school.identities:
				var player:=str(game.school.identities[peer])
				if not activity.get("students",{}).has(player):continue
				var snapshot: Dictionary=brain.export_social_record(str(id),player)
				_remap_snapshot(snapshot,str(id),global_id,player,player)
				var record:=archive.observe(global_id,player,snapshot) if not snapshot.is_empty() else {}
				if int(peer)==1 or not bool(game.session.online):continue
				var key:=str(peer)+":"+global_id
				var fingerprint:=_state_fingerprint(profile,record,mood)
				if sent.get(key,"")==fingerprint:continue
				_send_update(int(peer),global_id,player,fingerprint)

static func _state_fingerprint(profile: Dictionary,record: Dictionary,mood: Dictionary) -> String:
	return str(record.get("digest",""))+":"+str(profile.get("dossier_revision",0))+":"+str(profile.get("attendance",{}).get("count",profile.get("appearances",0)))+":"+Archive.digest({"learning":profile.get("learning",{}),"weeks":profile.get("learning_weeks",{})})+":"+str(mood.get("digest",""))

@rpc("authority","call_remote","reliable")
func _receive_update(payload: Dictionary) -> void:
	if multiplayer.is_server() or not _bind() or JSON.stringify(payload).to_utf8_buffer().size()>MAX_PACKET_BYTES:return
	var id:=str(payload.get("person",{}).get("id","")) if payload.get("person") is Dictionary else ""
	var saved:=_receive(payload,identity,1)
	if saved:_received_update_failures.erase(id)
	elif _received_update_failures.size()<MAX_MANIFEST:_received_update_failures[id]=true
	_received_update_error=not _received_update_failures.is_empty()
	var token:=str(payload.get("sync_token",""))
	if Population.valid_identity(id) and token.length()==32 and token.is_valid_hex_number():_update_receipt.rpc_id(1,id,token,saved)

func diagnostics() -> Dictionary:
	return {"local_population":population.people.size() if population!=null else 0,"contributors":manifests.size(),"social_records":archive.records.size(),"social_conflicts":archive.conflicts.size(),"last_error":last_error,"storage_error":archive.last_error,"social_storage_blocked":archive.blocked,"social_unsaved":archive.dirty,"pending_receipts":pending_receipts.size(),"unsaved_received_students":_received_update_failures.size()}

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
		_send_update(int(peer),global_id,player)

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

func _mood_receipt(local: String,global_id: String) -> Dictionary:
	var mood: Dictionary=brain.export_mood_record(local)
	if mood.is_empty():return {}
	var previous: Dictionary=archive.records.get(global_id+":_npc_mood",{})
	if not previous.is_empty():
		var last: Dictionary=previous.get("snapshot",{}).get("mood",{})
		# Do not turn a refreshed clock value into a new emotional event.
		if Archive.digest({"values":last.get("values",{}),"history":last.get("history",[])})==Archive.digest({"values":mood.values,"history":mood.history}):return previous.duplicate(true) if not archive.dirty or archive.save()==OK else {}
	return archive.observe(global_id,"_npc_mood",{"mood":mood})

func _receive_mood(receipt: Dictionary,local: String,global_id: String) -> bool:
	if str(receipt.get("character",""))!=global_id or receipt.get("player")!="_npc_mood" or not Archive.valid(receipt):return false
	var current: Dictionary=brain.export_mood_record(local)
	if not current.get("history",[]).is_empty():_mood_receipt(local,global_id)
	var kind:=archive.classify(receipt)
	if kind=="invalid":return false
	if kind=="older":return true
	if kind=="same" and not current.is_empty():return not archive.dirty or archive.save()==OK
	var mood: Variant=receipt.snapshot.get("mood",{})
	if not mood is Dictionary or not brain.import_mood_record(local,mood,kind=="descendant" or current.get("history",[]).is_empty()):return false
	return archive.receive(receipt,{"mood":brain.export_mood_record(local)})

func _send_update(peer: int,global_id: String,player: String,fingerprint: String="") -> bool:
	if not _bind() or not multiplayer.is_server() or peer not in multiplayer.get_peers() or str(game.school.identities.get(peer,""))!=player:return false
	if peer_identities.has(peer) and str(peer_identities[peer])!=player:_forget_peer(peer)
	var payload:=_export(global_id,player)
	if payload.is_empty():return false
	var key:=str(peer)+":"+global_id
	var digest:=str(payload.person.get("digest",""))
	if fingerprint.is_empty():fingerprint=_state_fingerprint(population.profile_for(population.local_id(global_id)),payload.get("social",{}),payload.get("mood",{}))
	var previous: Dictionary=pending_receipts.get(key,{})
	var attempts:=0
	if str(previous.get("fingerprint",""))==fingerprint:
		attempts=int(previous.get("attempts",0))
		if attempts>=UPDATE_ATTEMPTS or Time.get_ticks_msec()-int(previous.get("sent_at",0))<UPDATE_RECEIPT_TIMEOUT_MS:return false
	elif not pending_receipts.has(key) and pending_receipts.size()>=128:return false
	# Biography/appearance are sent once per changed profile. Later emotional,
	# relationship, attendance and learning updates are small state packets.
	if sent_profiles.get(key,"")==digest:
		payload.person.erase("dossier")
	var token:=Crypto.new().generate_random_bytes(16).hex_encode()
	payload.sync_token=token
	if rpc_id(peer,"_receive_update",payload)!=OK:return false
	# Reliable delivery acknowledges a packet, not a successful disk write.
	# Only a matching durable receipt permits future biography omission.
	pending_receipts[key]={"token":token,"profile_digest":digest,"fingerprint":fingerprint,"player":player,"sent_at":Time.get_ticks_msec(),"attempts":attempts+1}
	return true

@rpc("any_peer","call_remote","reliable")
func _update_receipt(global_id: String,token: String,saved: bool) -> void:
	var peer:=multiplayer.get_remote_sender_id()
	if not multiplayer.is_server() or not _game_ready() or peer<=1 or not Population.valid_identity(global_id):return
	var key:=str(peer)+":"+global_id
	var waiting: Dictionary=pending_receipts.get(key,{})
	if waiting.is_empty() or str(waiting.token)!=token or str(game.school.identities.get(peer,""))!=str(waiting.player):return
	if not saved:
		last_error="Another device could not save a student update; delivery will retry within its bounded retry budget."
		return
	sent[key]=str(waiting.fingerprint);sent_profiles[key]=str(waiting.profile_digest)
	pending_receipts.erase(key)

func _forget_peer(peer: int) -> void:
	# Invalidate immediately on disconnect. A new connection can reuse a peer
	# number before the periodic manifest timer has another chance to run.
	peer_identities.erase(peer);manifests.erase(peer);manifest_offsets.erase(peer);requested.erase(peer);pending.erase(peer)
	_departure_requests.erase(peer)
	for key in sent.keys():
		if str(key).begins_with(str(peer)+":"):sent.erase(key)
	for key in sent_profiles.keys():
		if str(key).begins_with(str(peer)+":"):sent_profiles.erase(key)
	for key in pending_receipts.keys():
		if str(key).begins_with(str(peer)+":"):pending_receipts.erase(key)
	if _departure_waiting.has(peer):_departure_waiting.erase(peer);_departure_failed=true

func prepare_departure() -> bool:
	# Checkpoints share the reliable ordered channel used by _receive_update.
	# A receipt can therefore only follow processing of the preceding updates.
	# This is a bounded handoff, never a promise to survive a lost connection.
	if not _bind():return false
	_flush()
	var local_saved:=_persist_checkpoint()
	var transport: MultiplayerPeer=multiplayer.multiplayer_peer
	if not bool(game.session.online) or transport==null or transport.get_connection_status()!=MultiplayerPeer.CONNECTION_CONNECTED:return local_saved
	var owner:=identity
	_departure_nonce=Crypto.new().generate_random_bytes(16).hex_encode()
	var nonce:=_departure_nonce
	_departure_waiting.clear();_departure_failed=not local_saved
	last_departure={"acknowledged":false,"timed_out":false,"missing":[],"local_saved":local_saved}
	if multiplayer.is_server():
		for peer in multiplayer.get_peers():
			var player:=str(game.school.identities.get(peer,""))
			if player.is_empty():continue
			_departure_waiting[int(peer)]=player
			if rpc_id(int(peer),"_departure_checkpoint",nonce,player)!=OK:_departure_waiting.erase(int(peer));_departure_failed=true
	else:
		_departure_waiting[1]=identity
		if rpc_id(1,"_departure_request",nonce,identity)!=OK:_departure_waiting.clear();_departure_failed=true
	var deadline:=Time.get_ticks_msec()+DEPARTURE_TIMEOUT_MS
	while not _departure_waiting.is_empty() and Time.get_ticks_msec()<deadline:
		if multiplayer.multiplayer_peer!=transport or transport.get_connection_status()!=MultiplayerPeer.CONNECTION_CONNECTED or not _game_ready() or str(game.school.local_identity)!=owner or _departure_nonce!=nonce:
			_departure_failed=true
			break
		var peers:=multiplayer.get_peers()
		for peer in _departure_waiting.keys():
			if int(peer) not in peers:_departure_waiting.erase(peer);_departure_failed=true
		if _departure_waiting.is_empty():break
		await get_tree().process_frame
	last_departure.missing=_departure_waiting.keys()
	last_departure.timed_out=not _departure_waiting.is_empty() and Time.get_ticks_msec()>=deadline
	last_departure.acknowledged=_departure_waiting.is_empty() and not _departure_failed
	_departure_waiting.clear();_departure_nonce=""
	if not local_saved:last_error="Recent changes could not all be saved locally before disconnect."
	elif not last_departure.acknowledged:last_error="Recent changes remain saved on this device; another device did not confirm its final copy before disconnect."
	return bool(last_departure.acknowledged)

func _persist_checkpoint() -> bool:
	var saved: bool=brain.save_memory()==OK
	if population.dirty:saved=population.save_population()==OK and saved
	return archive.save()==OK and saved

@rpc("any_peer","call_remote","reliable")
func _departure_request(nonce: String,player: String) -> void:
	var peer:=multiplayer.get_remote_sender_id()
	if not multiplayer.is_server() or not _bind() or peer<=1 or nonce.length()!=32 or not nonce.is_valid_hex_number():return
	if str(game.school.identities.get(peer,""))!=player or player.is_empty() or peer not in multiplayer.get_peers():return
	var now:=Time.get_ticks_msec()
	if now-int(_departure_requests.get(peer,-1000))<1000:return
	_departure_requests[peer]=now
	_flush()
	_departure_checkpoint.rpc_id(peer,nonce,player)

@rpc("authority","call_remote","reliable")
func _departure_checkpoint(nonce: String,player: String) -> void:
	if multiplayer.is_server() or not _bind() or nonce.length()!=32 or not nonce.is_valid_hex_number() or player!=identity:return
	var saved:=_persist_checkpoint() and not _received_update_error
	_departure_ack.rpc_id(1,nonce,identity,saved)
	if nonce==_departure_nonce and _departure_waiting.has(1):
		_departure_failed=not saved
		_departure_waiting.erase(1)

@rpc("any_peer","call_remote","reliable")
func _departure_ack(nonce: String,player: String,saved: bool) -> void:
	var peer:=multiplayer.get_remote_sender_id()
	if not multiplayer.is_server() or nonce!=_departure_nonce or not _departure_waiting.has(peer):return
	if not _game_ready() or str(_departure_waiting[peer])!=player or str(game.school.identities.get(peer,""))!=player:return
	_departure_failed=_departure_failed or not saved
	_departure_waiting.erase(peer)
