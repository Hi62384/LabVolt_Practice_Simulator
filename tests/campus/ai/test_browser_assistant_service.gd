extends SceneTree
const Service=preload("res://scripts/campus/ai/browser_assistant_service.gd")
const Policy=preload("res://scripts/campus/ai/browser_assistant_policy.gd")
class FakeSession extends Node:
 signal leaving
 signal restarted
 var roster: Dictionary={1:true}
 var online:=false
class FakeComputers extends Node:
 var sessions: Dictionary={1:{"station":"desk","lease":3}}
 var stations: Dictionary={"desk":{"chair":0}}
 var workspaces: Dictionary={1:{"files":{"notes.txt":{"text":"Host file text","version":1}}}}
 func _private_allowed(_peer: int,_entry: Dictionary) -> bool:return true
 func _has_access(_peer: int,_entry: Dictionary) -> bool:return true
class FakeDorm extends Node:
 func authenticated_identity(_peer: int) -> String:return "student"
class FakePhones extends Node:
 func _valid_classroom_phone(_peer: int,id: String,_identity: String) -> bool:return id=="phone"
class FakeClient extends Node:
 var enabled:=true
 var calls: Array=[]
 func configured() -> bool:return true
 func moderate(value: String) -> Dictionary:calls.append("moderate:"+value.left(12));return {"ok":true,"flagged":false}
 func respond(prompt: String) -> Dictionary:calls.append("text");return {"ok":true,"text":"{\"answer\":\"The page explains voltage.\",\"action\":{\"kind\":\"fill\",\"index\":0,\"value\":\"voltage\"}}"} if prompt.contains("Host file text") else {"ok":false,"error":"Host file missing"}
 func respond_with_image(_prompt: String,jpeg: PackedByteArray) -> Dictionary:calls.append("image");return {"ok":true,"text":"{\"answer\":\"The photo is attached.\"}"} if jpeg.size()==4 else {"ok":false}
 func transcribe_wav(_wav: PackedByteArray) -> Dictionary:calls.append("speech");return {"ok":true,"text":"What does this page show?"}
class FakeGame extends Node:
 var session: FakeSession
 var computers: FakeComputers
 var dorm_interactions: FakeDorm
 var smartphones: FakePhones
 var host_openai: FakeClient
var failures: Array[String]=[]
func _initialize() -> void:call_deferred("_run")
func _run() -> void:
 var game:=FakeGame.new();root.add_child(game)
 game.session=FakeSession.new();game.add_child(game.session)
 game.computers=FakeComputers.new();game.add_child(game.computers)
 game.dorm_interactions=FakeDorm.new();game.add_child(game.dorm_interactions)
 game.smartphones=FakePhones.new();game.add_child(game.smartphones)
 game.host_openai=FakeClient.new();game.add_child(game.host_openai)
 var service:=Service.new();game.add_child(service);service.build(game)
 var replies: Array=[];service.reply_received.connect(func(id,result):replies.append([id,result]))
 var view:={"url":"https://example.com/lesson","title":"Lesson","text":"Visible voltage lesson","targets":[{"kind":"fill","label":"Search"}]}
 var payload:={"request_id":1,"kind":"computer","device_id":"desk","lease":"3","question":"Explain the page","page":view,"attachment":{"kind":"virtual_file","name":"notes.txt"},"photo":PackedByteArray(),"wav":PackedByteArray()}
 service._accept(1,payload)
 if replies.size()!=1 or replies[0][1].get("answer","")!="The page explains voltage." or replies[0][1].get("action",{}).get("kind","")!="fill":failures.append("Computer page and host virtual file did not reach AI")
 var before:=game.host_openai.calls.size()
 payload.request_id=2;payload.lease="wrong";service.last_request.clear();service._accept(1,payload)
 if game.host_openai.calls.size()!=before:failures.append("Invalid computer lease reached AI")
 payload={"request_id":3,"kind":"phone","device_id":"phone","lease":"phone","question":"Describe photo","page":view,"attachment":{"kind":"photo","name":"photo.jpg"},"photo":PackedByteArray([255,216,255,217]),"wav":PackedByteArray()}
 service.last_request.clear();service._accept(1,payload)
 if replies.size()!=2 or replies[1][1].get("answer","")!="The photo is attached." or not game.host_openai.calls.has("image"):failures.append("Phone image did not reach image input")
 payload.request_id=4;payload.attachment={"kind":"virtual_file","name":"notes.txt"};service.last_request.clear();service._accept(1,payload)
 if replies.size()!=3 or not replies[2][1].has("error"):failures.append("Phone accepted a non-image attachment")
 var unsafe:=Policy.result('{"answer":"Fine","action":{"kind":"click","index":0}}',Policy.page(view).targets)
 if not unsafe.action.is_empty():failures.append("Mismatched page action was accepted")
 for failure in failures:push_error(failure)
 print("BROWSER_ASSISTANT_SERVICE ","PASS" if failures.is_empty() else "FAIL (%d)"%failures.size())
 quit(0 if failures.is_empty() else 1)
