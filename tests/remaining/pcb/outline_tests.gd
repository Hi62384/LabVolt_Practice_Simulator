extends SceneTree
const Document=preload("res://scripts/pcb_design/document.gd")
const Design=preload("res://scripts/pcb_design/design.gd")
const View=preload("res://scripts/pcb_design/route_canvas.gd")
var checks := 0
var failures := 0
func check(ok: bool,message: String) -> void:
 checks+=1
 if not ok:failures+=1;push_error(message)
func click(view: Control,point: Vector2,pressed: bool=true,double_click: bool=false,button: int=MOUSE_BUTTON_LEFT) -> void:
 var event:=InputEventMouseButton.new();event.position=point;event.button_index=button;event.pressed=pressed;event.double_click=double_click;view._gui_input(event)
func solved(bp: Dictionary) -> Dictionary:
 var flat: Dictionary=preload("res://scripts/custom_circuit.gd").flatten("ic:test",{"ic:test":bp},"board/unit/",["plus","minus"])
 flat.parts.append({"id":"source","kind":"V","a":"plus","b":"minus","value":10.0})
 return preload("res://scripts/electronics_solver.gd").new().solve(flat.parts,flat.wires)
func _initialize() -> void:call_deferred("run")
func run() -> void:
 var bp: Dictionary=preload("res://tests/remaining/pcb/pcb_tests.gd").fixture()
 bp.pcb_design.outline=[[0,0],[7,0],[7,5],[4,5],[4,4],[2,4],[2,5],[0,5]]
 var doc:=Document.new();doc.open(bp)
 var view:=View.new();root.add_child(view);view.size=Vector2(1000,500);view.document=doc;view.set_outline_mode(true)
 var original:=doc.blueprint.duplicate(true)
 var original_current: float=solved(bp).i["board/unit/r1"]
 # Valid drag changes only preview until release and creates one history entry.
 click(view,Design.map_point(bp,[4,4],view.rect()))
 check(view.drag_index==4 and view.selected_vertex==4,"numbered handle selects vertex")
 var motion:=InputEventMouseMotion.new();motion.position=Design.map_point(bp,[4.13,4.32],view.rect());view._gui_input(motion)
 check(doc.blueprint==original and doc.undo_stack.is_empty(),"drag preview never mutates document or history")
 check(view.drag_outline[4]==[4.25,4.25],"drag uses configured quarter-grid snap")
 check(view.preview_error=="","valid concave preview accepted")
 click(view,motion.position,false)
 check(doc.blueprint.pcb_design.outline[4]==[4.25,4.25] and doc.undo_stack.size()==1,"release commits one undoable edit")
 check(doc.blueprint.pcb_design.routes==original.pcb_design.routes,"outline drag preserves copper")
 check(doc.undo() and doc.blueprint==original,"undo restores original concave cutout")
 check(doc.redo() and doc.blueprint.pcb_design.outline[4]==[4.25,4.25],"redo restores dragged point")
 doc.undo()
 # Self-crossing/out-of-body/pad-invalid preview cannot commit.
 click(view,Design.map_point(bp,[4,4],view.rect()))
 motion.position=Design.map_point(bp,[0,0],view.rect());view._gui_input(motion)
 check(view.preview_error!="","invalid drag gives validation feedback")
 var history_before:=doc.undo_stack.size()
 click(view,motion.position,false)
 check(doc.blueprint==original and doc.undo_stack.size()==history_before,"invalid release rolls back with no history entry")
 check(doc.error!="","invalid release explains rejection")
 # Escape via right-click never creates a change.
 click(view,Design.map_point(bp,[4,4],view.rect()));motion.position=Design.map_point(bp,[4.5,4.5],view.rect());view._gui_input(motion)
 click(view,motion.position,true,false,MOUSE_BUTTON_RIGHT)
 check(view.drag_index==-1 and doc.blueprint==original,"cancel discards preview")
 click(view,Design.map_point(bp,[4,4],view.rect()));motion.position=Design.map_point(bp,[4.5,4.5],view.rect());view._gui_input(motion)
 var escape:=InputEventKey.new();escape.pressed=true;escape.keycode=KEY_ESCAPE;view._gui_input(escape)
 check(view.drag_index==-1 and doc.blueprint==original,"Escape discards drag preview")
 click(view,Design.map_point(bp,[4,4],view.rect()));view._notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
 check(view.drag_index==-1,"focus loss cancels drag safely")
 var corrupted:=original.duplicate(true);corrupted.pcb_design.routes[0].points=[[1,3],[6,3],[6,1],[1,1]]
 check(Design.validate(corrupted)!="" and not doc.commit(corrupted),"authoritative/default validation still checks complete copper clearance")
 check(doc.blueprint==original,"rejected copper cannot enter outline history")
 # Add by edge double-click and remove via toolbar action, including closing edge.
 var count: int=doc.blueprint.pcb_design.outline.size()
 click(view,Design.map_point(bp,[3.5,0],view.rect()),true,true)
 check(doc.blueprint.pcb_design.outline.size()==count+1 and view.selected_vertex==1,"double-click inserts edge point")
 check(view.remove_selected_vertex() and doc.blueprint.pcb_design.outline.size()==count,"remove selected vertex works")
 check(doc.blueprint==original,"adding/removing a collinear point preserves original design")
 view.select_vertex(count-1)
 check(view.add_vertex_after() and view.selected_vertex==count,"add after final point inserts on closing edge")
 check(view.remove_selected_vertex(),"closing-edge inserted point can be removed")
 # Numeric coordinates and DRC validation use same transaction path.
 view.select_vertex(4)
 check(view.move_selected([4.5,4.5]),"numeric coordinate placement accepted")
 check(doc.undo() and doc.blueprint==original,"numeric edit supports undo")
 check(not view.move_selected([NAN,0]) and doc.blueprint==original,"numeric malformed coordinates rejected")
 # Boundaries: minimum3 and maximum64 points.
 var triangle:=Document.new();triangle.open(bp)
 triangle.blueprint.pcb_design.outline=[[0,0],[7,0],[0,5]]
 view.document=triangle;view.select_vertex(0)
 check(not view.remove_selected_vertex() and triangle.blueprint.pcb_design.outline.size()==3,"three-point minimum enforced")
 view.document=doc
 var dense: Array=[]
 for i in 16:dense.append([i*7.0/16,0])
 for i in 16:dense.append([7,i*5.0/16])
 for i in 16:dense.append([7-i*7.0/16,5])
 for i in 16:dense.append([0,5-i*5.0/16])
 check(doc.set_outline(dense),"valid 64-point perimeter supported")
 view.select_vertex(0)
 check(not view.add_vertex_after() and doc.blueprint.pcb_design.outline.size()==64,"64-point limit enforced before insertion")
 check(not view.add_vertex_at(Design.map_point(bp,[.2,0],view.rect())),"double-click insertion respects64-point budget")
 doc.undo()
 # Switching modes cancels preview and preserves source/electrical topology.
 view.select_vertex(4);click(view,Design.map_point(bp,[4,4],view.rect()));motion.position=Design.map_point(bp,[4.5,4.5],view.rect());view._gui_input(motion)
 view.set_outline_mode(false)
 check(view.drag_index==-1 and doc.blueprint==original,"tool switch cancels uncommitted drag")
 check(absf(float(solved(doc.blueprint).i["board/unit/r1"])-original_current)<1e-10,"visual edits preserve actual shared-solver result")
 # Product UI defaults to visual handles and contains no JSON field.
 var profile=preload("res://scripts/electronics_profile.gd").new();profile.open("outline_ui_"+str(Time.get_ticks_usec()))
 var editor=preload("res://scripts/pcb_design/editor.gd").new();root.add_child(editor);editor.build(profile,bp)
 check(editor.view.outline_mode and editor.outline_tools.visible and not editor.trace_tools.visible,"editor opens in visual outline mode")
 check(editor.vertex_list.item_count==8,"vertex selector represents actual polygon")
 editor.view.select_vertex(4)
 check(editor.vertex_x.value==4 and editor.vertex_y.value==4,"coordinate controls follow selected handle")
 var fields:=editor.find_children("*","LineEdit",true,false)
 check(fields.all(func(field):return not field.text.begins_with("[[")),"no JSON outline editor exposed")
 editor.vertex_x.value=4.5;editor.vertex_y.value=4.5
 var move_button: Button=editor.find_children("*","Button",true,false).filter(func(node):return node.text=="Move point")[0]
 move_button.pressed.emit()
 check(editor.document.blueprint.pcb_design.outline[4]==[4.5,4.5],"numeric toolbar action moves selected visual vertex")
 var inventory_before: Dictionary=profile.data.inventory.duplicate(true)
 var messages: Array=[];editor.saved.connect(func(message):messages.append(message))
 var save_button: Button=editor.find_children("*","Button",true,false).filter(func(node):return node.text=="Save board copy")[0]
 save_button.pressed.emit()
 check(messages.size()==1 and messages[0].begins_with("Board copy saved") and not "ic:" in messages[0],"save action gives plain-language confirmation")
 check(profile.data.blueprints.size()==1 and profile.data.inventory==inventory_before,"visual UI saves new definition without minting stock")
 editor.change_mode(1)
 check(not editor.view.outline_mode and editor.trace_tools.visible,"copper routing mode remains available")
 editor.queue_free();view.queue_free();await process_frame
 print("OUTLINE_TESTS checks=",checks," failures=",failures)
 quit(0 if failures==0 else 1)
