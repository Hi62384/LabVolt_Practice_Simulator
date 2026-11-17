extends SceneTree
class FakeAssistant extends Node:
 signal reply_received(request_id: int,result: Dictionary)
 var payload: Dictionary={}
 func ask(value: Dictionary) -> void:payload=value
class FakeGame extends Node:
 var browser_assistant: Node
var failures: Array[String]=[]
func _initialize() -> void:call_deferred("_run")
func _run() -> void:
 var game:=FakeGame.new();root.add_child(game)
 game.browser_assistant=FakeAssistant.new();game.add_child(game.browser_assistant)
 var surface:=preload("res://scripts/campus/computers/browser_surface.gd").new();surface.game=game;root.add_child(surface)
 surface.size=Vector2(900,650)
 surface.configure("computer","fixture","lease",[])
 if not surface.renderer_available():failures.append("Browser renderer unavailable");_finish(surface);return
 var browser: Variant=surface._browser()
 browser.load_data_uri("<html><head><title>Assistant Fixture</title></head><body><h1>Visible lesson</h1><input type='text' aria-label='Search topic'><script>document.querySelector('input').addEventListener('input',()=>document.title='filled:'+document.querySelector('input').value)</script></body></html>","text/html")
 var deadline:=Time.get_ticks_msec()+8000
 while browser.get_title()!="Assistant Fixture" and Time.get_ticks_msec()<deadline:await process_frame
 if browser.get_title()!="Assistant Fixture":failures.append("Fixture did not load");_finish(surface);return
 for i in 20:await process_frame
 surface._assistant_request_page("What is visible?",PackedByteArray())
 deadline=Time.get_ticks_msec()+5000
 while game.browser_assistant.payload.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
 var payload: Dictionary=game.browser_assistant.payload
 if payload.is_empty():failures.append("Page bridge did not report context")
 else:
  var view: Dictionary=payload.get("page",{})
  if not str(view.get("text","")).contains("Visible lesson") or view.get("targets",[]).size()!=1:failures.append("Visible page context or safe target missing")
  surface._assistant_reply(int(payload.request_id),{"answer":"This page has a lesson.","action":{"kind":"fill","index":0,"value":"voltage"}})
  if not surface.assistant_action_button.visible:failures.append("Suggested page action was not offered for confirmation")
  else:
   surface._assistant_apply_action()
   deadline=Time.get_ticks_msec()+3000
   while browser.get_title()!="filled:voltage" and Time.get_ticks_msec()<deadline:await process_frame
   if browser.get_title()!="filled:voltage":failures.append("Confirmed form fill did not reach the page")
  surface._assistant_download()
  if not surface.status.text.contains("Answer saved to "):failures.append("Explicit answer download failed")
 _finish(surface)
func _finish(surface: Node) -> void:
 surface.close_session()
 for failure in failures:push_error(failure)
 print("BROWSER_ASSISTANT_SURFACE ","PASS" if failures.is_empty() else "FAIL (%d)"%failures.size())
 quit(0 if failures.is_empty() else 1)
