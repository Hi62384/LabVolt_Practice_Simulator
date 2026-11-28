extends SceneTree
## Counts actual production-pipeline provider invocations with a zero-network
## fixture. This is a protocol comparison, not model quality, API tokens or
## remote response latency. The same probe can run on the pre-dossier baseline.
const Interaction=preload("res://scripts/campus/academics/character_interaction.gd")
const Mind=preload("res://scripts/campus/academics/character_mind.gd")
const Brain=preload("res://scripts/campus/academics/teacher_brain.gd")
const Profiles=preload("res://scripts/campus/academics/class_character_profile.gd")

class CountClient extends Node:
	var busy:=false
	var calls: Array[String]=[]
	var context_bytes: Array[int]=[]
	func ready_for_class()->bool:return true
	func moderate(_text: String)->Dictionary:
		calls.append("moderation")
		return {"ok":true,"flagged":false}
	func semantics()->Dictionary:
		return {"event":"chat","tone":"neutral","severity":0.,"meaning":"The speaker casually greets the character.","topic":"greeting","domain":"conversation","question_kind":"casual","difficulty":0.,"assessment_request":"social","requested_action":"","memories":[]}
	func interpret_character(_instructions: String,context: Dictionary,_question: String)->Dictionary:
		calls.append("interpretation")
		context_bytes.append(JSON.stringify(context).to_utf8_buffer().size())
		return {"ok":true,"text":JSON.stringify(semantics())}
	func respond_character(_instructions: String,context: Dictionary,_question: String,_visual:=false)->Dictionary:
		calls.append("dialogue")
		context_bytes.append(JSON.stringify(context).to_utf8_buffer().size())
		return {"ok":true,"text":JSON.stringify({"speech":"Afternoon. I was just checking something.","interpretation":semantics(),"behavior":{"mode":"engage","intention":"Acknowledge a casual greeting."},"delivery":{"emotion":str(context.get("emotional_state",{}).get("emotion","steady")),"knowledge_mode":"personal_conversation"},"biography_facts":[],"belief_updates":[],"memories":[]})}

func _initialize()->void:call_deferred("run")
func run()->void:
	var brain:=Brain.new()
	brain.memory_path="user://request_accounting_fixture.json"
	var mind:=Mind.new()
	brain.bind_mind(mind)
	var pipeline:=Interaction.new()
	pipeline.bind(mind,brain)
	var client:=CountClient.new()
	root.add_child(client)
	var person:=Profiles.teacher("brian")
	var started:=Time.get_ticks_usec()
	var prepared:=await pipeline.prepare(client,person,"fixture_listener",{},"Good afternoon.")
	var response:=await pipeline.generate(client,prepared)
	var duration:=Time.get_ticks_usec()-started
	assert(response.source=="ai" and response.line=="Afternoon. I was just checking something.")
	assert(client.calls.count("moderation")==2,"Both input and output moderation remain required")
	assert(client.calls.count("dialogue")==1,"A valid ordinary reply needs one dialogue generation")
	var result:={"source":"deterministic provider instrumentation; no live AI or network","calls":client.calls,"semantic_model_calls":client.calls.count("interpretation")+client.calls.count("dialogue"),"moderation_calls":client.calls.count("moderation"),"context_utf8_bytes":client.context_bytes,"context_measurement":"bytes, not tokens","local_pipeline_usec":duration,"actual_input_tokens":null,"actual_output_tokens":null,"remote_response_latency_ms":null}
	print("CHARACTER_REQUEST_ACCOUNTING "+JSON.stringify(result))
	print("CHARACTER_REQUEST_ACCOUNTING PASS")
	client.queue_free();await process_frame
	quit(0)
