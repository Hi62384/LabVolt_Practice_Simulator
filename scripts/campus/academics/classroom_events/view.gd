extends Control
## Owner supplies transport and mouse policy.
const PracticePanel=preload("res://scripts/campus/academics/classroom_events/practice_panel.gd")
signal action_requested(class_id: String,event_id: String,op: String,payload: Variant)
signal opened
signal closed
var panel: Control
var panel_scroll: ScrollContainer

func _ready() -> void:
 resized.connect(_fit_panel)

func _fit_panel() -> void:
 if not is_instance_valid(panel_scroll): return
 var width := minf(540.0, maxf(1.0, size.x - 40.0))
 var top_inset := clampf(size.y * .12, 24.0, 108.0)
 var bottom_inset := clampf(size.y * .19, 84.0, 160.0)
 var height := minf(maxf(1.0, size.y - top_inset - bottom_inset), panel.get_combined_minimum_size().y + 4.0)
 panel_scroll.position = Vector2((size.x - width) * .5, top_inset)
 panel_scroll.size = Vector2(width, height)
var active_id: String=""
var active_class: String=""
var dismissed_key: String=""
var reopen_hint: Label
var announcement: Label

func _ensure_hint() -> void:
 if is_instance_valid(reopen_hint):return
 reopen_hint=Label.new();reopen_hint.text="F7 · Return to practice"
 reopen_hint.mouse_filter=Control.MOUSE_FILTER_IGNORE
 reopen_hint.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
 reopen_hint.offset_left=-230;reopen_hint.offset_right=-18;reopen_hint.offset_top=90;reopen_hint.offset_bottom=116
 reopen_hint.hide();add_child(reopen_hint)

func _ensure_announcement() -> void:
 if is_instance_valid(announcement):return
 announcement=Label.new();announcement.mouse_filter=Control.MOUSE_FILTER_IGNORE
 announcement.add_theme_color_override("font_color",Color("c5f4e8"))
 announcement.add_theme_color_override("font_shadow_color",Color("071923"))
 announcement.add_theme_constant_override("shadow_offset_x",2)
 announcement.add_theme_constant_override("shadow_offset_y",2)
 announcement.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
 announcement.offset_left=-360;announcement.offset_right=-20;announcement.offset_top=90;announcement.offset_bottom=124
 announcement.hide();add_child(announcement)

func apply(view: Dictionary) -> void:
 _ensure_hint()
 _ensure_announcement()
 var id:=str(view.get("event_id",""));var class_id:=str(view.get("class_id",""))
 if view.is_empty() or id.is_empty() or class_id.is_empty():
  _clear();dismissed_key="";return
 if view.get("stage","")=="announcing":
  _clear();announcement.text="Class activity starting · %d s"%ceili(float(view.get("seconds_left",0.0)));announcement.show();return
 announcement.hide()
 var key:=class_id+":"+id
 if key==dismissed_key:
  if is_instance_valid(panel):panel.update_state(view);_fit_panel.call_deferred()
  return
 if id!=active_id or class_id!=active_class:
  _clear();dismissed_key=""
  var question: Variant=view.get("question",{})
  if not question is Dictionary:return
  panel_scroll=ScrollContainer.new()
  panel_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
  add_child(panel_scroll)
  var next:=PracticePanel.new()
  next.size_flags_horizontal=Control.SIZE_EXPAND_FILL
  panel_scroll.add_child(next)
  if not next.build(question,str(view.get("course",""))):
   panel_scroll.queue_free();panel_scroll=null;return
  panel=next;active_id=id;active_class=class_id
  _fit_panel.call_deferred()
  next.submitted.connect(func(response):action_requested.emit(class_id,id,"submit",response))
  next.hand_changed.connect(func(raised):action_requested.emit(class_id,id,"hand",raised))
  next.hint_requested.connect(func():action_requested.emit(class_id,id,"hint",null))
  next.declined.connect(func():action_requested.emit(class_id,id,"decline",null))
  next.contributed.connect(func(value):action_requested.emit(class_id,id,"contribute",value))
  next.explained.connect(func(value):action_requested.emit(class_id,id,"explain",value))
  next.vote_requested.connect(func(agree):action_requested.emit(class_id,id,"vote",agree))
  next.dismissed.connect(func():
   dismissed_key=key;panel.hide();panel_scroll.hide();reopen_hint.show();closed.emit()
  )
  opened.emit()
 if is_instance_valid(panel):panel.update_state(view);_fit_panel.call_deferred()

func action_status(class_id: String,event_id: String,op: String,status: String) -> void:
 if class_id==active_class and event_id==active_id and is_instance_valid(panel):panel.action_status(op,status)

func reopen() -> bool:
 if dismissed_key.is_empty() or not is_instance_valid(panel):return false
 dismissed_key="";reopen_hint.hide();panel_scroll.show();panel.show();opened.emit();return true

func _clear() -> void:
 var had_panel:=is_instance_valid(panel)
 var was_visible:=had_panel and panel.is_visible_in_tree()
 if is_instance_valid(panel_scroll):panel_scroll.queue_free()
 panel_scroll=null
 panel=null;active_id="";active_class=""
 if is_instance_valid(reopen_hint):reopen_hint.hide()
 if is_instance_valid(announcement):announcement.hide()
 if was_visible:closed.emit()
