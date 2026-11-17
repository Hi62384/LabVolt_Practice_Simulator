extends SceneTree
class FakeSession extends Node:
 signal desktop_changed(snapshot: Dictionary)
 signal operation_failed(message: String)
func _initialize():call_deferred("run")
func run():
 var session=FakeSession.new();root.add_child(session)
 var desktop=preload("res://scripts/campus/computers/desktop_ui.gd").new();root.add_child(desktop);desktop.build(session)
 desktop._switch_app("Calculator")
 var calc=desktop.content.get_child(0)
 assert(calc.model=="calculator")
 calc.display.text="2+3"
 calc.evaluate()
 assert(calc.result.text.contains("5"))
 print("PASS desktop calculator app")
 desktop.queue_free();session.queue_free();await process_frame
 quit()
