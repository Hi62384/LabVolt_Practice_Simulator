extends SceneTree
## A compiled AVR must execute inside an invention's mounted PCB station.
const Board=preload("res://scripts/breadboard_model.gd")
const Custom=preload("res://scripts/custom_circuit.gd")
const Runtime=preload("res://scripts/campus/facilities/circuit_studio/assembly_pcb_runtime.gd")
const HostConfig=preload("res://scripts/firmware_backends/native_host_config.gd")
var failures:=0

func check(ok: bool,message: String) -> void:
    if not ok:
        failures+=1
        printerr("FAIL ",message)

func _initialize() -> void:call_deferred("_run")

func _run() -> void:
    var node: String=OS.get_environment("LABVOLT_TEST_NODE")
    check(FileAccess.file_exists(node),"CI exposes a trusted absolute Node executable")
    if not FileAccess.file_exists(node):quit(1);return
    HostConfig.cached_node=node
    var source: Dictionary=Board.empty()
    source.rows=40
    var physical: Array=[]
    for index in 32:physical.append("A"+str(index+1))
    source.parts=[{"id":"uno","type":"native_uno","a":physical[0],"b":physical[-1],
        "pins":physical,
        "native_firmware":{"schema":1,"board":"uno","format":"intel_hex",
            "image":FileAccess.get_file_as_string("res://assets/workers/firmware/uno-toggle.hex")}}]
    var bp: Dictionary=Board.blueprint(source,"Invention AVR")
    bp.package="PCB"
    bp.footprint={"width":8,"height":8,"color":"24775b"}
    bp.layout={"rows":40,"parts":source.parts.duplicate(true),"wires":[]}
    bp.pins=[{"name":"5V","node":"L5"},{"name":"GND","node":"L6"},{"name":"GPIO 13","node":"L28"}]
    var defs: Dictionary={"ic:invention_avr":bp}
    check(Custom.validate("ic:invention_avr",defs)=="","Native MCU blueprint validates")
    if failures>0:quit(1);return
    var runtime:=Runtime.new()
    check(runtime.configure("ic:invention_avr",defs,{"power":0,"ground":1,"A":2,"B":-1}),
        "Native MCU mounted PCB configures")
    if failures>0:quit(1);return
    var first: Dictionary=runtime.tick(.05)
    check(runtime.native_host.active and runtime.native_host.fault.is_empty(),
        "Mounted PCB attaches to the host-owned native sidecar")
    if failures>0:
        runtime.close()
        quit(1)
        return
    var active:=false
    for frame in 250:
        var result: Dictionary=runtime.tick(.0005)
        if not result.get("ok",false):
            check(false,"Native firmware runtime: "+str(result.get("error","")))
            break
        var state: Dictionary=runtime.station.firmware_states.get("board/pcb/uno",{})
        if state.get("powered",false) and int(state.get("outputs",{}).get("D13",0))==1 and float(result.get("A",0))>2.5:
            active=true
            break
        await create_timer(.01).timeout
    check(active,"Actual Uno D13 output drives mounted PCB's external output above 2.5 V")
    runtime.close()
    print("MOUNTED_NATIVE_FIRMWARE ", "PASS" if failures==0 else "FAIL ",failures)
    quit(failures)
