extends SceneTree
const Runtime=preload("res://scripts/firmware_runtime.gd")
const Project=preload("res://scripts/firmware_backends/source_project.gd")
const Bridge=preload("res://scripts/firmware_backends/native_bridge.gd")
const Adapter=preload("res://scripts/firmware_backends/board_adapter.gd")
var fails := 0
var checks := 0
func check(ok: bool,message: String) -> void:
	checks+=1;print("PASS " if ok else "FAIL ",message)
	if not ok:fails+=1
func _initialize() -> void:call_deferred("run")
func exchange(bridge: RefCounted,command: Dictionary) -> Dictionary:
	if not bridge.request(command):return {"ok":false,"error":bridge.last_error}
	for i in 500:
		var result: Dictionary=bridge.poll()
		if not result.is_empty():return result
		await create_timer(.01).timeout
	return {"ok":false,"error":"Test timeout"}
func run() -> void:
	var built := Project.build({"main.lvs":"#include \"init.lvs\"\nwrite D0 1\nwait 10\ngoto 2","init.lvs":"mode D0 out"})
	check(built.ok and built.source=="mode D0 out\nwrite D0 1\nwait 10\ngoto 2","multi-file include flattens and relocates local jumps")
	check(not Project.build({"main.lvs":"#include \"a.lvs\"","a.lvs":"#include \"main.lvs\""}).ok,"include cycle rejected")
	check(not Project.build({"main.lvs":"#include \"../host.lvs\""}).ok,"include cannot access host files")
	check(not Project.build({"main.lvs":"#include \"a.lvs\"","a.lvs":"write NOPE 1"}).ok,"included file diagnostics validate actual instructions")
	var diagnostic := Project.build({"main.lvs":"#include \"a.lvs\"","a.lvs":"halt\nbogus"})
	check(diagnostic.file=="a.lvs" and diagnostic.line==2,"diagnostic maps back to included file/line")
	var runtime := Runtime.new();var nodes := ["v","g","d0","d1","a0","pwm"];var voltages := {"v":5.0,"g":0.0}
	runtime.debug_breakpoints([2]);var state := runtime.tick("mode D0 out\nwrite D0 1\ngoto 2",nodes,voltages,.001)
	check(state.status=="Breakpoint" and not state.outputs.has("D0"),"LV breakpoint pauses before selected source instruction")
	runtime.debug_step();state=runtime.tick("mode D0 out\nwrite D0 1\ngoto 2",nodes,voltages,.001)
	check(state.outputs.D0==1.0 and state.paused,"LV single step updates real output and pauses")
	state=runtime.tick("bad",nodes,voltages,.001);runtime.reset();state=runtime.tick("bad",nodes,voltages,.001)
	check(state.status.begins_with("Line 1:"),"invalid source stays invalid after reset")
	check(runtime.tick("halt",[],{},.001).status=="Invalid firmware tick inputs","invalid node list fails safely")
	check(load("res://scripts/firmware_ide.gd").can_instantiate(),"multi-file IDE script parses")
	check(load("res://scripts/firmware_backends/native_runtime.gd").can_instantiate(),"native lockstep runtime parses")
	var native_editor=load("res://scripts/firmware_backends/native_ide.gd").new();root.add_child(native_editor);native_editor.build("uno",{}, {"Blink.ino":"void setup() {}","library.h":"#pragma once"})
	check(native_editor.editors.size()==2,"native IDE preserves source tabs without pretending to compile C++")
	native_editor.set_snapshot({"pc":2,"status":"Paused","time":.001});native_editor.queue_free()
	var bridge := Bridge.new();var node_path := OS.get_environment("LABVOLT_TEST_NODE")
	check(bridge.start(node_path),"native bridge launches trusted configured Node")
	if bridge.process.is_empty():print(bridge.last_error);quit(1);return
	var reply: Dictionary=await exchange(bridge,{"op":"load","board":"uno","image":FileAccess.get_file_as_string("res://assets/workers/firmware/uno-toggle.hex")})
	check(reply.get("ok",false),"Godot pipe loads AVR image")
	reply=await exchange(bridge,{"op":"tick","vcc":5,"dt":.001,"breakpoints":[4]})
	check(reply.get("ok",false) and reply.state.outputs.get("D13",0)==1,"Godot receives actual AVR output state")
	var model: Dictionary=Adapter.catalog().uno
	var pin_nodes: Array=[]
	for pin in model.pins:pin_nodes.append(str(pin))
	var primitives := Adapter.expand(model,"board/native",pin_nodes,{}, {"VCC":5,"GND":0},{"board/native":reply.state})
	primitives.append_array([{"id":"supply","kind":"V","a":"VCC","b":"GND","value":5.0},{"id":"resistor","kind":"R","a":"D13","b":"anode","value":220.0},{"id":"led","kind":"LED","a":"anode","b":"GND","vf":1.8,"ron":10.0}])
	var solver=load("res://scripts/electronics_solver.gd").new()
	var solved: Dictionary=solver.solve(primitives,[],.001)
	check(solved.ok and float(solved.i.get("led",0))>.01,"native AVR D13 drives actual solver LED current")
	reply=await exchange(bridge,{"op":"tick","vcc":0,"dt":.001})
	check(reply.ok and not reply.state.powered and reply.state.outputs.is_empty(),"Godot/native power loss releases GPIO")
	var pico_spec: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/workers/firmware/pico-toggle.json"))
	var padded := Marshalls.base64_to_raw(pico_spec.image);padded.resize(8192);pico_spec.image=Marshalls.raw_to_base64(padded);pico_spec.op="load"
	reply=await exchange(bridge,pico_spec)
	check(reply.get("ok",false),"chunked Godot pipe upload loads Pico flash image")
	reply=await exchange(bridge,{"op":"tick","vcc":3.3,"dt":.001,"breakpoints":[0x10000016]})
	check(reply.get("ok",false) and reply.state.outputs.get("GP0",0)==1,"Godot receives actual Cortex-M0 GPIO state")
	model=Adapter.catalog().pico;pin_nodes=[]
	for pin in model.pins:pin_nodes.append(str(pin))
	primitives=Adapter.expand(model,"board/pico",pin_nodes,{}, {"3V3":3.3,"GND":0},{"board/pico":reply.state})
	primitives.append_array([{"id":"supply","kind":"V","a":"3V3","b":"GND","value":3.3},{"id":"resistor","kind":"R","a":"GP0","b":"anode","value":220.0},{"id":"led","kind":"LED","a":"anode","b":"GND","vf":1.8,"ron":10.0}])
	solved=solver.solve(primitives,[],.001)
	check(solved.ok and float(solved.i.get("led",0))>.005,"Pico GP0 drives LED current at 3V3 through same circuit solver")
	bridge.close()
	check(bridge.process.is_empty(),"owned sidecar closes")
	print("WORKER CHECKS: %d; FAILURES: %d"%[checks,fails]);quit(fails)

