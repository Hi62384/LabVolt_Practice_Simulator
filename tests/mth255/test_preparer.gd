extends SceneTree
const Prep=preload("res://scripts/mth255/preparer.gd")
const P=preload("res://scripts/mth255/provider.gd")
var failures=0
func check(ok: bool,message: String) -> void:
	if not ok:failures+=1;print("FAIL "+message)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var prep=Prep.new();root.add_child(prep)
	var start=Time.get_ticks_usec();check(prep.prepare("test-attempt-1",5,4,255,8).get("ok",false),"preparation started")
	check(prep.prepare("test-attempt-2",2,4,256).has("error"),"one job per instance")
	var result=await prep.prepared;var elapsed=(Time.get_ticks_usec()-start)/1000.0
	check(result[0]=="test-attempt-1" and not result[1].has("error"),"prepared callback")
	if not result[1].has("error"):
		var p=P.new();var private_assignment=result[1].private_assignment;var public_assignment=result[1].public_assignment
		check(not p.restore(private_assignment).has("error"),"prepared assignment verifies")
		check(public_assignment.questions.size()==8 and not public_assignment.questions[0].has("answer"),"prepared public projection")
		check(not private_assignment.has("started_at") and not private_assignment.has("reward"),"preparation does not start academic lifecycle")
	check(not prep.busy(),"worker joined")
	var signaled=[false];prep.prepared.connect(func(_id,_result):signaled[0]=true)
	check(prep.prepare("cancelled",2,4,257).get("ok",false),"second preparation")
	prep.cancel_preparation()
	var deadline=Time.get_ticks_msec()+5000
	while prep.busy() and Time.get_ticks_msec()<deadline:await create_timer(0.01).timeout
	check(not signaled[0] and not prep.busy(),"cancelled preparation never issued")
	prep.free();print("MTH255_ASYNC failures=%d elapsed_first_job_ms=%s"%[failures,elapsed]);quit(0 if failures==0 else 1)
