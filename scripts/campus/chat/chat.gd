extends Node
## Host-relayed player chat, with compact HUD and temporary world-space bubbles.
const MAX_LENGTH := 100
const LIFETIME := 15.0
const IDLE_SECONDS := 10.0
var game: Node
var layer: CanvasLayer
var panel: VBoxContainer
var log: VBoxContainer
var entry: LineEdit
var last_message := 0.0
var clock := 0.0
var known := {}
var dead := {}
var bubbles := {}
var hovering := false
var typing := false

func build(owner_game: Node) -> void:
 game=owner_game
 layer=CanvasLayer.new();layer.layer=32;add_child(layer)
 panel=VBoxContainer.new();panel.position=Vector2(14,12);panel.custom_minimum_size=Vector2(350,0);panel.mouse_filter=Control.MOUSE_FILTER_PASS;layer.add_child(panel)
 panel.mouse_entered.connect(func():hovering=true;_wake())
 panel.mouse_exited.connect(func():hovering=false)
 log=VBoxContainer.new();log.add_theme_constant_override("separation",3);log.mouse_filter=Control.MOUSE_FILTER_IGNORE;panel.add_child(log)
 entry=LineEdit.new();entry.placeholder_text="Press / to chat";entry.max_length=MAX_LENGTH;entry.custom_minimum_size=Vector2(350,34)
 entry.add_theme_font_size_override("font_size",15);entry.add_theme_color_override("font_color",Color("eef7f5"));entry.add_theme_color_override("font_placeholder_color",Color("a8bbc2"))
 var style:=StyleBoxFlat.new();style.bg_color=Color(.035,.105,.14,.88);style.border_color=Color("79bbae");style.set_border_width_all(1);style.set_corner_radius_all(8);style.set_content_margin_all(8)
 entry.add_theme_stylebox_override("normal",style);entry.add_theme_stylebox_override("focus",style.duplicate());panel.add_child(entry)
 entry.text_submitted.connect(_submit)
 entry.focus_entered.connect(_focus)
 game.session.chat_received.connect(_received)
 game.session.roster_changed.connect(_roster)
 game.session.restarted.connect(_reset_session)
 _roster()

func _reset_session() -> void:
 known.clear();dead.clear()
 for peer in bubbles:
  for item in bubbles[peer]:
   if is_instance_valid(item.node):item.node.queue_free()
 bubbles.clear()
 for child in log.get_children():log.remove_child(child);child.queue_free()
 _roster()

func route_event(event: InputEvent) -> bool:
 if not is_instance_valid(game.front) or not game.front.in_game:return false
 if event is InputEventKey and event.pressed and not event.echo and event.keycode==KEY_SLASH and not typing and Input.mouse_mode==Input.MOUSE_MODE_CAPTURED:
  _focus();entry.grab_focus();return true
 if typing and event is InputEventKey and event.pressed and not event.echo and event.keycode==KEY_ESCAPE:
  _unfocus();return true
 if typing and event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT:
  if not panel.get_global_rect().has_point(get_viewport().get_mouse_position()):_unfocus();return true
 return false

func _focus() -> void:
 if typing:return
 typing=true;game.player.chat_typing=true;Input.mouse_mode=Input.MOUSE_MODE_VISIBLE;_wake()
func _unfocus() -> void:
 typing=false;game.player.chat_typing=false;entry.release_focus();last_message=clock
 if game.front.in_game and not game.front.screen.visible:Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
func _submit(value: String) -> void:
 var text:=value.strip_edges().replace("\n"," ").left(MAX_LENGTH)
 entry.clear()
 if not text.is_empty():game.session.chat(text)
 _unfocus()
func _wake() -> void:
 last_message=clock
 panel.modulate.a=1.0
func _line(value: String, system := false) -> void:
 var label:=Label.new();label.text=value;label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;label.custom_minimum_size.x=350;label.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN
 label.add_theme_font_size_override("font_size",14);label.add_theme_color_override("font_color",Color("a4d5ca") if system else Color("f0f6f4"));label.add_theme_color_override("font_outline_color",Color(.02,.05,.07,.95));label.add_theme_constant_override("outline_size",4)
 log.add_child(label)
 while log.get_child_count()>6:log.get_child(0).free()
 _wake()
func _received(peer: int,sender: String,message: String) -> void:
 _line(sender+": "+message)
 _bubble(peer,message)
func _roster() -> void:
 var current: Dictionary=game.session.roster
 for peer in current:
  if not known.has(peer):_line(str(current[peer].get("name","Student"))+" joined",true)
 for peer in known:
  if not current.has(peer):_line(str(known[peer])+" left",true);dead.erase(peer)
 known.clear()
 for peer in current:known[peer]=str(current[peer].get("name","Student"))
func _bubble(peer: int,message: String) -> void:
 if not bubbles.has(peer):bubbles[peer]=[]
 var list: Array=bubbles[peer]
 var anchor:=Node3D.new();game.add_child(anchor)
 var viewport:=SubViewport.new();viewport.size=Vector2i(512,144);viewport.transparent_bg=true;viewport.render_target_update_mode=SubViewport.UPDATE_ONCE;anchor.add_child(viewport)
 var card:=PanelContainer.new();card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 var skin:=StyleBoxFlat.new();skin.bg_color=Color(.035,.105,.14,.93);skin.border_color=Color("91d6c3");skin.set_border_width_all(3);skin.set_corner_radius_all(20);skin.set_content_margin_all(12);card.add_theme_stylebox_override("panel",skin);viewport.add_child(card)
 var text:=Label.new();text.text=message;text.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;text.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;text.vertical_alignment=VERTICAL_ALIGNMENT_CENTER;text.add_theme_font_size_override("font_size",28);text.add_theme_color_override("font_color",Color("f3faf7"));card.add_child(text)
 var sprite:=Sprite3D.new();sprite.texture=viewport.get_texture();sprite.pixel_size=.0027;sprite.billboard=BaseMaterial3D.BILLBOARD_ENABLED;sprite.no_depth_test=false;anchor.add_child(sprite)
 list.append({"node":anchor,"expires":clock+LIFETIME})
 while list.size()>4:
  var old: Dictionary=list.pop_front();old.node.queue_free()
func _process(delta: float) -> void:
 if not is_instance_valid(game) or not is_instance_valid(game.front):return
 clock+=delta
 layer.visible=game.front.in_game and not game.front.screen.visible
 if typing and not layer.visible:_unfocus()
 var target:=1.0 if typing or hovering or clock-last_message<IDLE_SECONDS else 0.0
 panel.modulate.a=move_toward(panel.modulate.a,target,delta*2.0)
 if is_instance_valid(game.health):
  for peer in game.health.people:
   var is_dead: bool=bool(game.health.people[peer].get("dead",false))
   if is_dead and not dead.get(peer,false):_line(str(known.get(peer,"Student"))+" died",true)
   dead[peer]=is_dead
 for peer in bubbles.keys():
  var list: Array=bubbles[peer]
  for item in list.duplicate():
   if clock>=float(item.expires) or not game.session.roster.has(peer):
    item.node.queue_free();list.erase(item)
  var point: Vector3=game.player.global_position if int(peer)==multiplayer.get_unique_id() else game.session.poses.get(peer,{}).get("position",Vector3.INF)
  for i in list.size():
   var node: Node3D=list[i].node
   node.visible=point.is_finite() and int(peer)!=multiplayer.get_unique_id()
   if node.visible:node.global_position=point+Vector3.UP*(2.55+float(list.size()-1-i)*.41)
  if list.is_empty():bubbles.erase(peer)
