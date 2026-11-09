extends SceneTree
## Run in a private combined fixture with the hash-pinned shared core dependency.
const Core = preload("res://scripts/mth147/math_core.gd")
const Workspace = preload("res://scripts/math_ui/workspace.gd")
var checks:=0
var failures:=0
var dependency:="unspecified"
func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:failures+=1;push_error(message)
func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--dependency="):dependency=arg.trim_prefix("--dependency=")
	call_deferred("run")
func run() -> void:
	var w:=Workspace.new();root.add_child(w)
	w.configure({"id":"exact","input":{"kind":"expression"}},true,{},Callable(Core,"parse"))
	await process_frame
	w.fields.answer._edit_leaf("(x+1)*(x-1)")
	check(Core.equivalent(w.answer(),"x^2-1").equivalent,"UI factors reach shared exact equivalence")
	w.fields.answer.set_value({"op":"num","value":"1"});w.fields.answer.insert_template("a/b");w.fields.answer.selected_path=[1];w.fields.answer._edit_leaf("3")
	check(Core.equivalent(w.answer(),"1/3").equivalent,"fraction keyboard remains exact")
	w.fields.answer._select([]);w.fields.answer._edit_leaf("sqrt(8)")
	check(Core.equivalent(w.answer(),"2*sqrt(2)").equivalent,"exact radical source")
	w.fields.answer._edit_leaf("1.20e3");check(w.answer()=="1.20e3","significant trailing zero preserved")
	check(absf(Core.evaluate(w.answer()).value-1200)<1e-8,"scientific input through core")
	w.fields.answer._edit_leaf("log(8,2)");check(absf(Core.evaluate(w.answer()).value-3)<1e-8,"arbitrary log base through core")
	w.fields.answer._edit_leaf("sin(pi/6)");check(absf(Core.evaluate(w.answer(),{},"radians").value-0.5)<1e-8,"explicit radian context through core")
	w.fields.answer._edit_leaf("sin(30)");check(absf(Core.evaluate(w.answer(),{},"degrees").value-0.5)<1e-8,"degree default through core")
	w.configure({"id":"restricted","input":{"kind":"rational"}},true,{},Callable(Core,"parse"))
	w.fields.expression._edit_leaf("(x+1)/(x-2)");w.fields.excluded._edit_leaf("2")
	check(w.answer().excluded==["2"] and Core.parse(w.answer().expression).ok,"domain entry separate from expression")
	w.configure({"id":"set","input":{"kind":"solutions"}},true,{},Callable(Core,"parse"))
	w.fields.values.set_value("root(3,27),sqrt(4)")
	check(w.answer().values.size()==2 and Core.evaluate(w.answer().values[0]).value==3,"set entry preserves root arity")
	w.fields.values.set_value("get_node('/root')")
	check(not Core.parse(w.answer().values[0]).ok,"unsupported input rejected by shared parser")
	if dependency in ["core-v2","core-v3"]:
		w.configure({"id":"identity","input":{"kind":"expression"}},true,{},Callable(Core,"parse"))
		for identity in [["sin(2*x)","2*sin(x)*cos(x)"],["sin(x+y)","sin(x)*cos(y)+cos(x)*sin(y)"],["sin(x)^2+cos(x)^2","1"]]:
			w.fields.answer._edit_leaf(identity[0]);check(Core.equivalent(w.answer(),identity[1]).get("equivalent",false),"v2 exact identity through UI: "+identity[0])
		w.fields.answer._edit_leaf("(x+1)*(x-1)")
		check(not Core.inspect_form("expanded",w.answer(),"x^2-1").ok,"value equivalence does not erase required expansion")
		check(Core.inspect_form("factored",w.answer(),"(x+1)*(x-1)").ok,"factor structure preserved")
		w.fields.answer._edit_leaf("1.20e3")
		check(Core.inspect_form("significant",w.answer(),"1200",{"digits":3}).ok,"required significant form preserved")
		check(not Core.evaluate("log(-2,3)").ok and not Core.evaluate("1/(2-2)").ok,"undefined input rejected by shared core")
		w.configure({"id":"projection","input":{"kind":"graph"},"answer_key":"SECRET_KEY_SENTINEL","parameters":{"secret":"SECRET_PARAMETERS_SENTINEL"},"rubric":{"hidden":"SECRET_RUBRIC_SENTINEL"},"diagram":{"kind":"graph","points":[{"x":1,"y":2}]}},true)
		var serialized:=JSON.stringify(w.snapshot())
		check(not "SECRET_" in serialized and w.answer().points.is_empty(),"widget persistence projects only student state")
		var encoded=load("res://scripts/math_ui/answer_codec.gd").encode(JSON.parse_string(serialized))
		check(encoded.ok and load("res://scripts/math_ui/answer_codec.gd").decode(encoded.text,"projection").ok,"versioned JSON envelope through combined dependency")
	if dependency=="core-v3":
		w.configure({"id":"v3","input":{"kind":"expression"}},true,{},Callable(Core,"parse"))
		w.fields.answer.set_value({"op":"num","value":"-3"});check(Core.evaluate(w.answer()).value==-3,"signed AST numeric output")
		w.fields.answer._edit_leaf("sin(θ)^2+cos(θ)^2");check(Core.equivalent(w.answer(),"1").get("equivalent",false),"Greek identity roundtrip")
		w.fields.answer._edit_leaf("root(3/1,27)");check(Core.evaluate(w.answer()).value==3,"root-index expression roundtrip")
		w.fields.answer._edit_leaf("1e-300");check(not Core.evaluate(w.answer()).ok,"underflow is rejected, never displayed as valid zero")
	w.free()
	print("MATH_UI_SHARED_RESULT dependency=%s checks=%d failures=%d"%[dependency,checks,failures])
	quit(1 if failures else 0)
