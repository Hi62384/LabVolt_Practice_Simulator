extends SceneTree

const Client=preload("res://scripts/campus/ai/host_openai_client.gd")
const Evaluation=preload("res://scripts/campus/ai/openai_evaluation.gd")
const ID:="gpt-5.4-mini"
const EFFORT:="low"
const MODE:="standard"

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	create_timer(15).timeout.connect(func():quit(1))
	var endpoint:=OS.get_environment("LABVOLT_OPENAI_FIXTURE_PORT")
	if endpoint.is_empty():endpoint="28768"
	var client:=Client.new()
	root.add_child(client)
	assert(client.set_local_test_endpoint("http://127.0.0.1:%s/v1"%endpoint))
	assert(client.set_session_key("sk-test-12345678901234567890"))
	var eval:=Evaluation.new()
	var cap:=eval.estimate(ID)
	var signature:=eval.key(ID,EFFORT,MODE)
	assert(cap>0 and eval.record(ID,EFFORT,MODE).is_empty())
	await eval.run(client,ID,EFFORT,MODE,cap-1,{},func(_state: String):pass)
	assert(not eval.progress.has(signature) and client.model_usage.is_empty())
	await eval.run(client,ID,EFFORT,MODE,cap,{},func(state: String):
		if state.begins_with("Question"):eval.canceled=true)
	assert(eval.progress[signature].next==1 and client.model_usage[ID].requests==1)
	var resumed:=Evaluation.new()
	assert(resumed.progress[signature].next==1)
	await resumed.run(client,ID,EFFORT,MODE,cap,{},func(_state: String):pass)
	var measured:=resumed.record(ID,EFFORT,MODE)
	assert(measured.correct==2 and measured.questions==8 and measured.score_percent==25.)
	assert(measured.usage.input==80 and measured.usage.output==160 and measured.usage.reasoning==64)
	assert(measured.cost==780000 and measured.snapshots==["gpt-5.4-mini-2026-03-17"])
	assert(client.reasoning_effort.is_empty() and not client.enabled)
	var stored:=Evaluation.new().record(ID,EFFORT,MODE)
	assert(stored.run_id==measured.run_id and stored.usage==measured.usage and stored.cost==measured.cost)
	for edge in 2:assert(is_equal_approx(stored.interval[edge],measured.interval[edge]))
	print("OPENAI_EVALUATION_FIXTURE PASS")
	quit()
