extends Node
## Host-owned AI requests. Browser pages and clients never receive the API key.
signal reply_received(request_id: int,result: Dictionary)
const Policy=preload("res://scripts/campus/ai/browser_assistant_policy.gd")
const MAX_PHOTO_BYTES:=262144
var game: Node
var busy: Dictionary={}
var last_request: Dictionary={}

func build(owner: Node) -> void:
	game=owner
	game.session.leaving.connect(_clear)
	game.session.restarted.connect(_clear)

func _clear() -> void:
	busy.clear();last_request.clear()

func ask(payload: Dictionary) -> void:
	if multiplayer.is_server():_accept(multiplayer.get_unique_id(),payload)
	elif game.session.online:_request.rpc_id(1,payload)

@rpc("any_peer","call_remote","reliable",6)
func _request(payload: Dictionary) -> void:
	if multiplayer.is_server():_accept(multiplayer.get_remote_sender_id(),payload)

func _accept(peer: int,payload: Dictionary) -> void:
	if not multiplayer.is_server() or not game.session.roster.has(peer) or payload.size()>9 or busy.has(peer):return
	var now:=Time.get_ticks_msec()
	if now-int(last_request.get(peer,-10000))<1000:return
	last_request[peer]=now
	var request_id:=int(payload.get("request_id",0))
	var kind:=str(payload.get("kind",""))
	var device_id:=str(payload.get("device_id",""))
	var lease:=str(payload.get("lease",""))
	if request_id<=0 or not _device_allowed(peer,kind,device_id,lease):return
	var question:=str(payload.get("question","")).strip_edges()
	var wav: Variant=payload.get("wav",PackedByteArray())
	var raw_page: Variant=payload.get("page",{})
	if not wav is PackedByteArray or wav.size()>192044 or (question.is_empty() and wav.is_empty()) or question.length()>Policy.MAX_QUESTION or not raw_page is Dictionary:_send(peer,request_id,{"error":"Enter a shorter question or record speech."});return
	var view: Dictionary=Policy.page(raw_page)
	if view.is_empty():_send(peer,request_id,{"error":"Open an HTTP or HTTPS page before asking about it."});return
	var attachment: Variant=payload.get("attachment",{})
	if not attachment is Dictionary:_send(peer,request_id,{"error":"Invalid attachment."});return
	var file_text: String=""
	var photo:=PackedByteArray()
	if not attachment.is_empty():
		if kind=="computer" and attachment.get("kind","")=="virtual_file":
			var path:=str(attachment.get("name",""))
			var session: Dictionary=game.computers.sessions.get(peer,{})
			var files: Dictionary=game.computers.workspaces.get(peer,{}).get("files",{})
			if session.is_empty() or not files.has(path):_send(peer,request_id,{"error":"That virtual file is unavailable."});return
			file_text=str(files[path].get("text","")).left(350)
		elif kind=="phone" and attachment.get("kind","")=="photo":
			var supplied: Variant=payload.get("photo",PackedByteArray())
			if not supplied is PackedByteArray or supplied.size()<4 or supplied.size()>MAX_PHOTO_BYTES or supplied[0]!=255 or supplied[1]!=216:_send(peer,request_id,{"error":"Choose a smaller phone photo."});return
			photo=supplied
		else:_send(peer,request_id,{"error":"This device cannot attach that item."});return
	busy[peer]=request_id
	_answer(peer,request_id,kind,device_id,lease,question,view,file_text,photo,wav)

func _device_allowed(peer: int,kind: String,device_id: String,lease: String) -> bool:
	if kind=="computer":
		var session: Dictionary=game.computers.sessions.get(peer,{})
		if session.is_empty() or str(session.get("station",""))!=device_id or str(session.get("lease",""))!=lease:return false
		var station: Dictionary=game.computers.stations.get(device_id,{})
		return not station.is_empty() and game.computers._private_allowed(peer,station) and game.computers._has_access(peer,station)
	if kind=="phone" and lease==device_id:
		var identity: String=game.dorm_interactions.authenticated_identity(peer)
		return not identity.is_empty() and game.smartphones._valid_classroom_phone(peer,device_id,identity)
	return false

func _answer(peer: int,request_id: int,kind: String,device_id: String,lease: String,question: String,view: Dictionary,file_text: String,photo: PackedByteArray,wav: PackedByteArray) -> void:
	var output: Dictionary={"error":"The host AI connection is unavailable."}
	var client: Node=game.host_openai
	if is_instance_valid(client) and client.enabled and client.configured():
		if not wav.is_empty():
			var transcript: Dictionary=await client.transcribe_wav(wav)
			if not transcript.get("ok",false):
				busy.erase(peer)
				_send(peer,request_id,{"error":str(transcript.get("error","Speech was not recognized."))})
				return
			question=str(transcript.get("text",""))
		var check: Dictionary=await client.moderate(question)
		if check.get("flagged",false):output={"error":"That question cannot be sent to the assistant."}
		elif not check.get("ok",false):output={"error":str(check.get("error","Moderation is unavailable."))}
		else:
			var prompt:=Policy.prompt(question,view,file_text)
			var result: Dictionary=await client.respond_with_image(prompt,photo) if not photo.is_empty() else await client.respond(prompt)
			if not result.get("ok",false):output={"error":str(result.get("error","The assistant could not answer."))}
			else:
				var parsed: Dictionary=Policy.result(str(result.get("text","")),view.targets)
				var answer:=str(parsed.get("answer",""))
				var outgoing: Dictionary=await client.moderate(answer) if not answer.is_empty() else {"ok":false}
				if outgoing.get("ok",false) and not outgoing.get("flagged",false):output={"answer":answer,"action":parsed.get("action",{}),"url":view.url}
				else:output={"error":"The assistant response could not be shown."}
	busy.erase(peer)
	if _device_allowed(peer,kind,device_id,lease):_send(peer,request_id,output)

func _send(peer: int,request_id: int,result: Dictionary) -> void:
	if peer==multiplayer.get_unique_id():reply_received.emit(request_id,result)
	elif game.session.online and game.session.peer_connected_now(peer):_receive.rpc_id(peer,request_id,result)

@rpc("authority","call_remote","reliable",6)
func _receive(request_id: int,result: Dictionary) -> void:
	if multiplayer.get_remote_sender_id()==1:reply_received.emit(request_id,result)
