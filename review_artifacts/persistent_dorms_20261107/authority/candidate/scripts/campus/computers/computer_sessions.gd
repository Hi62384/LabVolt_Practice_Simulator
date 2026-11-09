extends Node
signal desktop_changed(snapshot: Dictionary)
signal occupancy_changed(occupancy: Dictionary)
signal operation_failed(message: String)
const Files = preload("res://scripts/campus/computers/virtual_files.gd")
const Documents = preload("res://scripts/campus/computers/local_documents.gd")
var game: Node
var stations := {}
var sessions := {}
var workspaces := {}
var workspace_identities := {}
var restored := {}
var last_request := {}
var serial := 0
var local_snapshot := {}
var local_profile := ""
var timer: Timer
func build(owner_game: Node) -> void:
	game=owner_game
	game.session.roster_changed.connect(_prune)
	game.session.leaving.connect(_reset)
	timer=Timer.new()
	timer.wait_time=.25
	timer.timeout.connect(_prune)
	add_child(timer)
	timer.start()
func register_station(id: String, chair_index: int, anchor: Vector3) -> bool:
	if id.length()>48 or Files.path(id)!=id or id.contains("/") or stations.has(id) or not anchor.is_finite():return false
	if chair_index<0 or chair_index>=game.chairs.size():return false
	for entry in stations.values():
		if entry.chair==chair_index:return false
	stations[id]={"chair":chair_index,"anchor":anchor}
	return true
func set_private_owner(id: String,owner: String) -> bool:
	if not stations.has(id):return false
	stations[id].private_owner=owner
	if multiplayer.is_server():
		for peer in sessions.keys():
			if sessions[peer].station==id and not _private_allowed(peer,stations[id]):_close(peer,true)
	return true
func _identity(peer: int) -> String:
	if not game.session.roster.has(peer):return ""
	return str(game.electronics_trade.authority.ledger.bindings.get(peer,"")) if game.session.online else (game.school.local_identity if peer==1 else "")
func _private_allowed(peer: int,entry: Dictionary) -> bool:
	return not entry.has("private_owner") or (not str(entry.private_owner).is_empty() and _identity(peer)==entry.private_owner)
func request(action: Dictionary) -> void:
	if action.get("op","")=="exit" and game.get("player")!=null and game.player.seated!=null:
		game._stand_from_chair()
		if game.player.seated!=null:
			operation_failed.emit("Move clear of the desk before standing.")
			return
	if action.get("op","")=="enter":
		var identity: String=game.school.local_identity
		if identity.is_empty():operation_failed.emit("Select a student profile first.");return
		local_profile=identity
	if multiplayer.is_server():_accept(multiplayer.get_unique_id(),action)
	elif game.session.online:_request.rpc_id(1,action)
@rpc("any_peer","call_remote","reliable",6)
func _request(action: Dictionary) -> void:
	if multiplayer.is_server():_accept(multiplayer.get_remote_sender_id(),action)
func _accept(peer: int, action: Dictionary) -> void:
	if not game.session.roster.has(peer) or action.size()>9 or action.has("owner") or action.has("profile") or action.has("identity"):return
	var op: String=str(action.get("op",""))
	if op=="enter":
		if sessions.has(peer):
			var previous: Dictionary=sessions[peer]
			if str(previous.get("identity",""))==_identity(peer) and _private_allowed(peer,stations[previous.station]):_reply(peer);return
			_close(peer,true)
		var id: String=str(action.get("station",""))
		if not stations.has(id):return
		var entry: Dictionary=stations[id]
		if not _private_allowed(peer,entry):return
		var position: Vector3=game.session.poses.get(peer,{}).get("position",Vector3.INF)
		if position.distance_to(entry.anchor)>3:return
		var chair = game.chairs[entry.chair]
		if chair.occupant==0:game._claim_chair(peer,entry.chair)
		if chair.occupant!=peer:return
		serial+=1
		var identity := _identity(peer)
		if workspace_identities.get(peer,"__unbound__")!=identity:
			workspaces.erase(peer);restored.erase(peer)
		workspace_identities[peer]=identity
		sessions[peer]={"station":id,"lease":serial,"revision":0,"identity":identity}
		if not workspaces.has(peer):workspaces[peer]={"files":{},"editor":{}}
		_publish()
		_reply(peer)
		return
	if not sessions.has(peer):return
	var session: Dictionary=sessions[peer]
	if str(session.get("identity",""))!=_identity(peer) or not _private_allowed(peer,stations[session.station]):_close(peer,true);return
	if action.get("lease",-1)!=session.lease or action.get("revision",-1)!=session.revision:return
	if op=="exit":_close(peer,true);return
	var entry: Dictionary=stations[session.station]
	if game.chairs[entry.chair].occupant!=peer:_close(peer,false);return
	if op in ["browser","run"]:_error(peer,"Unavailable: browser and code execution are not installed.");return
	var now := Time.get_ticks_msec()
	if now-int(last_request.get(peer,-1000))<60:_error(peer,"Please retry after the current operation.");return
	last_request[peer]=now
	var workspace: Dictionary=workspaces[peer]
	match op:
		"restore":
			if restored.has(peer):_error(peer,"This connection has already restored its files.");return
			var files = action.get("files",{})
			if not files is Dictionary or not Files.validate(files):_error(peer,"Invalid saved documents.");return
			workspace.files=files.duplicate(true)
			var editor = action.get("editor",{})
			if editor is Dictionary and workspace.files.has(str(editor.get("path",""))):
				workspace.editor={"path":str(editor.path),"cursor":clampi(int(editor.get("cursor",0)),0,str(workspace.files[editor.path].text).length())}
			restored[peer]=true
		"save":
			if not restored.has(peer):_error(peer,"Restore documents before editing.");return
			if not action.get("text") is String or not action.get("version") is int:return
			var result := Files.save(workspace.files,str(action.get("path","")),action.text,action.version)
			if result.has("error"):_error(peer,result.error);return
			workspace.files=result.files
		"rename":
			var source := Files.path(str(action.get("path","")))
			var target := Files.path(str(action.get("new_path","")))
			if source.is_empty() or target.is_empty() or not workspace.files.has(source) or workspace.files.has(target) or int(workspace.files.get(source,{}).get("version",0))>=2147483646:
				_error(peer,"Choose an existing source and an unused valid destination.")
				return
			workspace.files[target]=workspace.files[source].duplicate(true)
			workspace.files[target].version+=1
			workspace.files.erase(source)
			if workspace.editor.get("path","")==source:workspace.editor.path=target
		"editor":
			var path := Files.path(str(action.get("path","")))
			if not workspace.files.has(path):return
			workspace.editor={"path":path,"cursor":clampi(int(action.get("cursor",0)),0,str(workspace.files[path].text).length())}
		"refresh":
			pass
		"answer", "submit":
			if not _assignment(peer,action):return
		_:
			return
	session.revision+=1
	_reply(peer)
func _assignment(peer: int, action: Dictionary) -> bool:
	var id := int(action.get("paper",0))
	var paper: Dictionary=game.school.papers.get(id,{})
	if paper.is_empty() or paper.owner!=peer or not paper.get("mark",{}).is_empty():return false
	# Preserve classroom authority, seating, deadlines and grade policy. Lab hand-in
	# still requires the teacher; do not silently bypass its physical evidence checks.
	if action.op=="submit" and game.school.activity.get("kind","")!="lecture":
		_error(peer,"Take this lab paper to the teacher for submission.")
		return false
	var a := {"op":str(action.op),"id":id}
	if action.op=="answer":
		if not action.get("value") is String or str(action.value).length()>512:return false
		a.key=str(action.get("question",""))
		a.value=action.value
	game.school.apply(peer,a)
	return true
func _reply(peer: int) -> void:
	var packet: Dictionary=sessions[peer].duplicate(true)
	packet.erase("identity")
	packet.merge(workspaces[peer].duplicate(true))
	packet.restored=restored.has(peer)
	packet.assignments=[]
	for paper in game.school.papers.values():
		if paper.owner!=peer:continue
		var safe: Dictionary=game.school._public_project(paper.project,not paper.mark.is_empty() or paper.lesson)
		packet.assignments.append({"id":paper.id,"title":str(safe.get("title","Assignment")),"questions":safe.get("questions",[]),"answers":paper.answers.duplicate(true),"mark":paper.mark.duplicate(true),"can_submit":paper.mark.is_empty() and game.school.activity.get("kind","")=="lecture"})
	packet.materials=[]
	if game.school.phase=="lesson":
		var stage: Dictionary=game.school.teaching_stage()
		packet.materials.append({"title":str(stage.get("title","Lesson")),"text":str(stage.get("text",stage.get("caption","")))})
	if peer==multiplayer.get_unique_id():_receive(packet)
	elif game.session.online:_private.rpc_id(peer,packet)
@rpc("authority","call_remote","reliable",6)
func _private(packet: Dictionary) -> void:
	if multiplayer.get_remote_sender_id()==1:_receive(packet)
func _receive(packet: Dictionary) -> void:
	local_snapshot=packet.duplicate(true)
	if packet.is_empty():desktop_changed.emit({});return
	if not packet.get("restored",false):
		request({"op":"restore","lease":packet.lease,"revision":packet.revision,"files":Documents.load_documents(local_profile),"editor":Documents.load_editor(local_profile)})
		return
	var error := Documents.save_documents(local_profile,packet.files,packet.editor)
	if error!=OK:operation_failed.emit("Documents are in memory; local save failed (%d)."%error)
	desktop_changed.emit(local_snapshot.duplicate(true))
func _error(peer: int, message: String) -> void:
	if peer==multiplayer.get_unique_id():operation_failed.emit(message)
	elif game.session.online:_failed.rpc_id(peer,message)
@rpc("authority","call_remote","reliable",6)
func _failed(message: String) -> void:
	if multiplayer.get_remote_sender_id()==1:operation_failed.emit(message)
func _publish() -> void:
	var public := {}
	for peer in sessions:public[sessions[peer].station]=peer
	occupancy_changed.emit(public)
	if game.session.online:_occupancy.rpc(public)
@rpc("authority","call_remote","reliable",6)
func _occupancy(public: Dictionary) -> void:
	if multiplayer.get_remote_sender_id()==1:occupancy_changed.emit(public)
func _close(peer: int, release: bool) -> void:
	if not sessions.has(peer):return
	sessions.erase(peer)
	if release:
		game._release_chair(peer)
		game._send_chairs()
		if peer==multiplayer.get_unique_id() and game.player.seated!=null:game.player.stand_up()
	if peer==multiplayer.get_unique_id():_receive({})
	elif game.session.online and game.session.roster.has(peer):_private.rpc_id(peer,{})
	_publish()
func _prune() -> void:
	if not multiplayer.is_server():return
	for peer in sessions.keys():
		var entry: Dictionary=stations[sessions[peer].station]
		if not game.session.roster.has(peer) or not _private_allowed(peer,entry) or game.chairs[entry.chair].occupant!=peer:_close(peer,false)
	for peer in workspaces.keys():
		if not game.session.roster.has(peer):
			workspaces.erase(peer);workspace_identities.erase(peer)
			restored.erase(peer)
			last_request.erase(peer)
func _reset() -> void:
	set_meta("resetting",true)
	sessions.clear()
	workspaces.clear();workspace_identities.clear()
	restored.clear()
	last_request.clear()
	local_snapshot.clear()
	local_profile=""
	desktop_changed.emit({})
	occupancy_changed.emit({})
	set_meta("resetting",false)

