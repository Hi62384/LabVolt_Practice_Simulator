extends Node
## Host-only asynchronous preparation. This never creates a ledger entry or starts a timer.
const Provider=preload("res://scripts/mth255/provider.gd")
signal prepared(job_id: String,result: Dictionary)
var _thread: Thread
var _provider: RefCounted
var _output: Dictionary={}
var _busy=false
var _cancelled=false
var _job_id=""
func busy() -> bool:
	return _busy
func prepare(job_id: String,week: int,difficulty: int,seed_value: int,count: int=8,focus: String="") -> Dictionary:
	if not is_inside_tree() or not multiplayer.is_server():return {"error":"Only the host may prepare an official assessment."}
	if _busy:return {"error":"A mathematics preparation job is already running."}
	if job_id.is_empty() or job_id.length()>128:return {"error":"Invalid preparation job id."}
	_provider=Provider.new()
	if _provider._core()==null:return {"error":"Shared math core unavailable."}
	if ResourceLoader.exists("res://scripts/ac_network.gd"):load("res://scripts/ac_network.gd")
	_job_id=job_id;_cancelled=false;_busy=true;_output={};_thread=Thread.new()
	var error=_thread.start(_work.bind(week,difficulty,seed_value,count,focus))
	if error!=OK:_busy=false;return {"error":"Could not start the mathematics preparation worker."}
	return {"ok":true,"job_id":job_id}
func _work(week: int,difficulty: int,seed_value: int,count: int,focus: String) -> void:
	var assignment=_provider.generate(week,difficulty,seed_value,count,focus)
	if assignment.has("error"):_output=assignment
	else:
		assignment.merge({"course_id":"MTH255","kind":"lecture","title":"MTH255 — Applied Mathematics"})
		_output={"private_assignment":assignment,"public_assignment":_provider.public_copy(assignment)}
	call_deferred("_deliver")
func _deliver() -> void:
	if _thread!=null and _thread.is_started():_thread.wait_to_finish()
	_busy=false
	var result=_output;_output={}
	if not _cancelled:prepared.emit(_job_id,result)
func cancel_preparation() -> void:
	_cancelled=true
func _exit_tree() -> void:
	_cancelled=true
	if _thread!=null and _thread.is_started():_thread.wait_to_finish()
	_busy=false
