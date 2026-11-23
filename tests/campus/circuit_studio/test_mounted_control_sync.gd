extends SceneTree
## Mounted PCB inputs should reflect authoritative settings without echo commands.
const MountedPanel=preload("res://scripts/campus/facilities/circuit_studio/assembly_pcb_panel.gd")
const World=preload("res://scripts/campus/facilities/circuit_studio/invention_world.gd")
var failures:=0

class FakeSession extends Node:
    var roster: Dictionary={1:{"name":"Host"}}
    var online:=false

class FakeWorld extends Node:
    var placed: Dictionary={}
    var requests: Array=[]
    func request_pcb_input(invention_key: String,id: String,pressed: bool,reverse: bool=false,command: Dictionary={}) -> void:
        requests.append({"key":invention_key,"id":id,"pressed":pressed,"reverse":reverse,"command":command})

class FakeGame extends Node3D:
    var invention_world: Node
    var session:=FakeSession.new()
    var player:=Node3D.new()
    var front: Dictionary={"in_game":false}
    func release_mouse() -> void:pass
    func capture() -> void:pass

class LongInputRuntime extends RefCounted:
    var current: Dictionary={}
    func input(id: String,pressed: bool,_reverse: bool=false,_command: Dictionary={}) -> bool:
        current[id]={"pressed":pressed}
        return true
    func input_states() -> Dictionary:return current.duplicate(true)

func check(ok: bool,message: String) -> void:
    if not ok:
        failures+=1
        printerr("FAIL ",message)

func _initialize() -> void:call_deferred("_run")

func _run() -> void:
    var game:=FakeGame.new()
    var world:=FakeWorld.new()
    game.invention_world=world
    root.add_child(game)
    game.add_child(world)
    var control_states: Dictionary={
        "board/slider":{"revision":2,"x":.8},
        "board/selector":{"revision":1,"position":2},
        "board/touch":{"revision":1,"x":.2,"y":.7,"pressed":false},
        "board/source":{"source_voltage":7.0,"source_frequency":41.0,"source_wave":2},
        "board/toggle":{"pressed":true}
    }
    world.placed={"fixture":{
        "pcb_inputs":[
            {"kind":"io_slider","id":"board/slider","name":"Slider"},
            {"kind":"io_selector","id":"board/selector","name":"Selector"},
            {"kind":"xpt2046","id":"board/touch","name":"Touch"},
            {"kind":"battery_generator_adjustable","id":"board/source","name":"Generator"},
            {"kind":"toggle","id":"board/toggle","name":"Switch"}
        ],
        "pcb_controls":control_states,
        "pcb_error":"",
        "pcb_voltage":{"A":0.0,"B":0.0}
    }}
    var panel:=MountedPanel.new()
    panel.open_board(game,"fixture",false)
    var widgets: Dictionary=panel.control_widgets
    check(is_equal_approx(float(widgets["board/slider"].x.value),.8),
        "Slider opens at the real host position")
    check(int(widgets["board/selector"].selector.selected)==2,
        "Selector opens at the host's selected detent")
    check(is_equal_approx(float(widgets["board/touch"].x.value),.2) and
        is_equal_approx(float(widgets["board/touch"].y.value),.7),
        "Touch coordinates are restored without sending a touch")
    check(widgets["board/toggle"].toggle.text=="On" and
        "7.0 V" in widgets["board/source"].readout.text,
        "Switch and generator readouts match live hardware")
    check(world.requests.is_empty(),"Host state synchronization causes no input echoes")
    world.placed.fixture.pcb_controls["board/slider"].x=.35
    world.placed.fixture.pcb_controls["board/selector"].position=1
    panel._sync_controls()
    check(is_equal_approx(float(widgets["board/slider"].x.value),.35) and
        widgets["board/selector"].selector.selected==1,
        "A second player's changes update the open panel")
    check(world.requests.is_empty(),"Updating displayed controls does not submit commands")
    panel._selector_changed(0,"board/selector")
    check(world.requests.size()==1 and world.requests[0].command.position==0,
        "Selector changes still transmit the user's command")
    panel.free()
    game.queue_free()
    await process_frame

    var id: String="board/"+("nested/".repeat(20))+"switch"
    check(id.length()>96,"Nested control fixture crosses the former 96-character limit")
    var fake_game:=FakeGame.new()
    var actual:=World.new()
    fake_game.add_child(fake_game.session)
    fake_game.add_child(fake_game.player)
    fake_game.invention_world=actual
    root.add_child(fake_game)
    fake_game.add_child(actual)
    actual.game=fake_game
    var runtime:=LongInputRuntime.new()
    actual.placed["fixture"]={"position":Vector3.ZERO,"pcb_inputs":[{"id":id,"kind":"button"}],
        "pcb_controls":{}}
    actual.simulators["fixture"]={"runtime":runtime}
    actual._apply(1,{"op":"pcb_input","key":"fixture","id":id,"pressed":true,"reverse":false,"command":{}})
    check(runtime.current.has(id) and bool(runtime.current[id].pressed),
        "Host accepts valid deeply nested PCB input IDs")
    check(actual.placed.fixture.pcb_controls.has(id) and actual.pending_motion.has("fixture"),
        "Host publishes the new input state after a nested control command")
    fake_game.queue_free()
    await process_frame
    print("MOUNTED_CONTROL_SYNC ", "PASS" if failures==0 else "FAIL ",failures)
    quit(failures)
