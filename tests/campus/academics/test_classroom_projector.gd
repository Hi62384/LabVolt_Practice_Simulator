extends SceneTree
const Projector=preload("res://scripts/campus/academics/classroom_events/projector.gd")
class Registry:
 func get_room(room: String) -> Dictionary:return {"center":Vector3(0,0,0)} if room=="lecture" else {}
class Campus:
 var registry:=Registry.new()
class Game:
 extends Node
 var campus:=Campus.new()
func _initialize() -> void:call_deferred("run")
func run() -> void:
 var game:=Game.new();root.add_child(game)
 var projector:=Projector.new();root.add_child(projector);projector.configure(game)
 var view:={"mode":"quiz","course":"MTH147","round_number":1,"rounds_total":3,"seconds_left":22.0,"question":{"prompt":"Select the correct value","options":["1","2"]}}
 projector.apply("lecture",view)
 assert(projector.active_room=="lecture" and projector.board.visible)
 assert(projector.board.global_position==Vector3(0,2.18,-5.65))
 assert(projector.board.signature.contains("Select the correct value"))
 assert(not projector.board.signature.contains("secret-answer"))
 view.reveal={"answer":"secret-answer"};view.leaderboard=[{"name":"Student 1","points":145}]
 projector.apply("lecture",view)
 assert(projector.board.signature.contains("secret-answer") and projector.board.signature.contains("Student 1"))
 view.erase("reveal");view.mode="board";view.closed=false;view.shared={"entries":[{"text":"A student's board note"}]}
 projector.apply("lecture",view)
 assert(not projector.board.visible)
 view.mode="demonstration";view.closed=false;view.erase("shared")
 projector.apply("lecture",view)
 assert(not projector.board.signature.contains("Simulated:"))
 view.closed=true;view.reveal={"answer":"6.00 mA","initial_ma":12.0,"changed_ma":6.0,"source":"circuit solver"}
 projector.apply("lecture",view)
 assert(projector.board.signature.contains("Simulated: 12.00 mA → 6.00 mA"))
 projector.apply("lecture",{})
 assert(projector.active_room.is_empty() and not projector.board.visible)
 print("CLASSROOM_PROJECTOR PASS")
 projector.queue_free();game.queue_free();quit(0)
