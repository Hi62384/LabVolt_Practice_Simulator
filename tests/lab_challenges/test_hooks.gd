extends SceneTree
var failures := 0
var assertions := 0
func _initialize() -> void:call_deferred("run")
func check(ok: bool,msg: String) -> void:
	assertions+=1
	if not ok:failures+=1;push_error(msg)
func run() -> void:
	var original: Script=load("res://scripts/session.gd")
	var probe: Node=original.new()
	var properties: Array=probe.get_property_list().map(func(property):return str(property.name))
	var integrated := "lab_challenge_guard" in properties and "lab_challenge_observer" in properties and "lab_challenge_brief" in properties
	probe.free()
	print("BASE_HOOK_MODE ","installed production hooks" if integrated else "proposal in-memory only; core source untouched")
	var source := FileAccess.get_file_as_string("res://scripts/session.gd").replace("\r\n","\n")
	if not integrated:
		source=source.replace("var academic_equipment_observer", "var lab_challenge_guard := Callable()\nvar lab_challenge_observer := Callable()\nvar lab_challenge_brief := Callable()\nvar academic_equipment_observer")
		source=source.replace("if academic_equipment_observer.is_valid() else {}","if academic_equipment_observer.is_valid() or lab_challenge_observer.is_valid() else {}")
		var old := "var error: String = labs[station].act(id,action,poses.get(id,{}).get(\"position\",Vector3.ZERO),id==1)"
		check(source.count(old)==1,"immutable Session hook target matches")
		source=source.replace(old,"var error: String=str(lab_challenge_guard.call(id,station,action)) if lab_challenge_guard.is_valid() else \"\"\n\tif error==\"\":error=labs[station].act(id,action,poses.get(id,{}).get(\"position\",Vector3.ZERO),id==1)")
		old="if error==\"\" and academic_equipment_observer.is_valid():academic_equipment_observer.call(id,station,action,before)"
		source=source.replace(old,old+"\n\tif error==\"\" and lab_challenge_observer.is_valid():lab_challenge_observer.call(id,station,action,before)")
		source=source.replace("\tdata[\"stations\"]=extra\n\treturn data","\tif lab_challenge_brief.is_valid():\n\t\tdata[\"team_challenge\"]=lab_challenge_brief.call(0)\n\t\tfor i in extra.size():extra[i][\"team_challenge\"]=lab_challenge_brief.call(i+1)\n\tdata[\"stations\"]=extra\n\treturn data")
	var script := GDScript.new();script.source_code=source
	check(script.reload()==OK,"proposed Session callbacks compile in memory without source write")
	var session: Node=script.new();root.add_child(session)
	session.initialize(preload("res://tests/fixture.gd").ids(),preload("res://tests/fixture.gd").locations())
	session.add_station(preload("res://tests/fixture.gd").ids(),preload("res://tests/fixture.gd").locations())
	session.roster={1:{"name":"Student","ready":true}};session.poses={1:{"position":Vector3(-4.2,0,-1.4)}}
	var events: Array=[]
	session.lab_challenge_guard=func(_peer,_bench,action):return "team guard denied" if action.op=="reset" else ""
	session.lab_challenge_observer=func(peer,bench,action,before):events.append({"peer":peer,"bench":bench,"op":action.op,"before":before})
	session.lab_challenge_brief=func(bench):return {"title":"Host challenge","objective":"bench%d"%bench}
	var revision: int=session.lab.revision
	session.apply_action(1,{"op":"reset","station":0})
	check(session.lab.revision==revision and events.is_empty(),"guard prevents real reset and suppresses success evidence")
	session.last_actions.clear();session.apply_action(1,{"op":"check","station":0})
	check(events.size()==1 and events[0].op=="check" and events[0].before.has("cables") and not events[0].before.checked and session.lab.checked,"observer receives actual pre-action snapshot after accepted electrical action")
	var snapshot: Dictionary=session.world_snapshot()
	check(snapshot.team_challenge.objective=="bench0" and snapshot.stations[0].team_challenge.objective=="bench1","public brief uses correct actual station index")
	session.queue_free();await process_frame
	print("BASE_HOOKS_RESULT assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
