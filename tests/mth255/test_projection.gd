extends SceneTree
const P=preload("res://scripts/mth255/provider.gd")
var failures=0
func check(ok: bool,message: String) -> void:
	if not ok:failures+=1;print("FAIL "+message)
func scan(value: Variant,path: String="public") -> void:
	if value is Dictionary:
		for key in value:
			check(key not in ["answer","parameters","rubric","steps","seed","verification","verified","answer_key","target","host_only","reference_points","critical_points"],path+" leaked "+key)
			scan(value[key],path+"."+key)
	elif value is Array:
		for i in range(value.size()):scan(value[i],path+"["+str(i)+"]")
func _initialize() -> void:
	var p=P.new();var tested=0
	for topic in ["wave_from_graph","waveform","wave_graph","complex_convert","exact_trig","complex_roots","impedance","impedance_network","statistics","frequency","dice","coins","cards","quadratic_vertex","rc_model"]:
		for d in range(5):
			var private_problem=p.generate_problem(topic,d,812+d);check(not private_problem.has("error"),"generate "+topic)
			if private_problem.has("error"):continue
			var assignment={"course":"MTH255","seed":"PRIVATE_SENTINEL","questions":[private_problem]}
			private_problem.diagram.host_only={"answer_key":"PRIVATE_SENTINEL"};private_problem.input.nested=[{"target":"PRIVATE_SENTINEL"}]
			var saved=JSON.parse_string(JSON.stringify(assignment));var first=p.public_copy(assignment);var reconnect=p.public_copy(saved);var late=p.public_copy(JSON.parse_string(JSON.stringify(saved)))
			check(JSON.stringify(first)==JSON.stringify(reconnect) and JSON.stringify(first)==JSON.stringify(late),"public saved/reconnect/late join "+topic)
			check(not JSON.stringify(first).contains("PRIVATE_SENTINEL"),"nested sentinel "+topic);scan(first)
			check(JSON.stringify(p.public_copy(first))==JSON.stringify(first),"idempotent public projection "+topic)
			var public_problem=first.questions[0];check(not public_problem.id.contains("."+str(812+d)),"opaque id "+topic)
			if private_problem.diagram.has("function"):
				check(not public_problem.diagram.has("function"),"hidden function "+topic)
				check(public_problem.diagram.curves.size()==1 and public_problem.diagram.curves[0].kind=="samples" and public_problem.diagram.curves[0].points.size()==129,"visible sampled curve "+topic)
				check(public_problem.diagram.get("points",[]).is_empty(),"reference points do not prefill "+topic)
			if topic=="complex_convert" and private_problem.expected_form=="rectangular":check(public_problem.diagram.points.is_empty(),"rectangular target coordinates")
			if topic=="exact_trig":check(public_problem.diagram.points.is_empty(),"exact trig target coordinate")
			if topic in ["dice","coins","cards"]:check(public_problem.diagram.outcomes.is_empty(),"probability target counts")
			if topic in ["impedance","impedance_network"]:check(public_problem.diagram.components.size()>=2,"preserve circuit givens")
			if topic in ["statistics","frequency"]:check(public_problem.diagram.rows.size()>0,"preserve data givens")
			tested+=1
	print("MTH255_PUBLIC_PROJECTION cases=%d failures=%d"%[tested,failures]);quit(0 if failures==0 else 1)
