extends SceneTree
## Regression tests for long-window measurements, designer continuity and DRC.
const Station=preload("res://scripts/dc_station.gd")
const Solver=preload("res://scripts/electronics_solver.gd")
const Debug=preload("res://scripts/electronics/circuit_workspace/debug_instruments.gd")
const Board=preload("res://scripts/breadboard_model.gd")
const Custom=preload("res://scripts/custom_circuit.gd")
const Maker=preload("res://scripts/electronics/circuit_workspace/maker_canvas.gd")
const Electronics=preload("res://scripts/electronics_ui.gd")
var failures:=0

func check(ok: bool,message: String) -> void:
    if not ok:
        failures+=1
        printerr("FAIL ",message)

func _initialize() -> void:
    call_deferred("_run")

func _rows(step: float,frequency: float) -> Array:
    var rows: Array=[]
    for index in 512:
        var time:=index*step
        rows.append([time,0.0,0.0,sin(TAU*frequency*time),0.0])
    return rows

func _meter() -> void:
    var fast:=_rows(.0005,.1)
    var medium:=_rows(.005,.1)
    var slow:=_rows(.05,.1)
    var window: Array=Station.measurement_window(fast,medium,slow,3)
    var stats: Dictionary=Station.statistics(window,3)
    check(window==slow and absf(float(stats.frequency)-.1)<.005,
        "0.1 Hz uses the slow measurement window and resolves a full period")
    check(absf(Station.ac_rms_only(window,3)-sqrt(.5))<.05,
        "0.1 Hz AC RMS uses multiple periods, not the recent quarter-second")
    fast=_rows(.0005,1.0);medium=_rows(.005,1.0);slow=_rows(.05,1.0)
    window=Station.measurement_window(fast,medium,slow,3)
    stats=Station.statistics(window,3)
    check(window==medium and absf(float(stats.frequency)-1.0)<.02,
        "1 Hz uses the intermediate window without aliasing")
    fast=_rows(.0005,60.0);medium=_rows(.005,60.0);slow=_rows(.05,60.0)
    window=Station.measurement_window(fast,medium,slow,3)
    stats=Station.statistics(window,3)
    check(window==fast and absf(float(stats.frequency)-60.0)<1.0,
        "60 Hz uses 2 kHz data rather than aliased low-rate history")
    var station:=Station.new()
    station.meter_medium_samples=[1]
    station.meter_slow_samples=[1]
    station._clear_measurement_history()
    check(station.meter_medium_samples.is_empty() and station.meter_slow_samples.is_empty(),
        "Reset clears all retained measurement history")

func _debug_ohms() -> void:
    var meter: Dictionary={"type":Debug.METER,"debug":{"mode":"Ohms"}}
    var parts: Array=Debug.expand(Debug.METER,"meter",["a","b"],meter,0.0)
    check(parts.size()==2 and float(parts[0].value)>=1e11 and float(parts[1].value)<=.000001,
        "Debug ohmmeter does not impose a 10 MOhm load")
    var open: Dictionary=Solver.new().solve(parts)
    check(open.get("ok",false) and absf(float(open.get("v",{}).get("a",0))-float(open.get("v",{}).get("b",0)))>100.0,
        "Open-circuit meter input remains solvable and exceeds measurement range")
    parts.append({"id":"r","kind":"R","a":"a","b":"b","value":10000000.0})
    var loaded: Dictionary=Solver.new().solve(parts)
    var measured: float=absf(float(loaded.get("v",{}).get("a",0))-float(loaded.get("v",{}).get("b",0)))/.000001
    check(loaded.get("ok",false) and absf(measured/10000000.0-1.0)<.001,
        "10 MOhm resistor is not misreported as 5 MOhm")

func _terminal_validation() -> void:
    var source: Dictionary=Board.empty()
    source.parts=[{"id":"pot","type":"pot10k","a":"A1","b":"A3","pins":["A1","A2","A3"]}]
    var bp: Dictionary=Board.blueprint(source,"3 pin fixture")
    var defs: Dictionary={"ic:fixture":bp}
    check(Custom.validate("ic:fixture",defs)=="","Valid 3-pin source package validates")
    defs["ic:fixture"].parts[0].nodes[2]=""
    check(not Custom.validate("ic:fixture",defs).is_empty(),
        "Malformed third terminal is rejected before package flattening")

func _preview() -> void:
    var board: Dictionary=Board.empty()
    board.parts=[
        {"id":"sw","type":"toggle","a":"A1","b":"A2","pressed":true},
        {"id":"storage","type":"c10.0","a":"B2","b":"F1"},
        {"id":"source","type":Debug.SOURCE,"a":"B1","b":"G1"}]
    board.controls={"board/sw":{"pressed":true}}
    check(Board.validate(board,{},true)=="","Designer RC switch test is placeable")
    var ui:=Electronics.new()
    root.add_child(ui)
    ui.set_process(false)
    var canvas:=Maker.new()
    canvas.board=board
    canvas.inventory_catalog=Board.catalog(board)
    root.add_child(canvas)
    await process_frame
    ui.canvas=canvas
    ui.active=true
    ui.designing=true
    ui._process(.02)
    var original=ui.design_preview
    var charged:=float(original.solver.memory.get("board/storage",0.0))
    check(charged>4.0 and original.result.get("ok",false),
        "Capacitor charges while preview switch is closed")
    canvas.board.parts[0].pressed=false
    canvas.board.controls["board/sw"].pressed=false
    ui._process(.02)
    check(is_same(ui.design_preview,original) and absf(original.solver.time-.04)<.000001,
        "Toggling the switch keeps its solver instance and time")
    check(float(original.solver.memory.get("board/storage",0.0))>4.0,
        "Stored capacitor voltage survives an interactive switch edit")
    ui._process(.1)
    check(absf(original.solver.time-.14)<.000001,
        "Slow preview frame integrates its complete 100 ms without dropping time")
    ui.active=false
    canvas.queue_free()
    ui.queue_free()
    await process_frame

func _run() -> void:
    _meter()
    _debug_ohms()
    _terminal_validation()
    await _preview()
    print("ADDITIONAL_ELECTRONICS_REGRESSIONS ", "PASS" if failures==0 else "FAIL ",failures)
    quit(failures)
