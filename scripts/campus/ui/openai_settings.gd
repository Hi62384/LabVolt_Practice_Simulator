extends VBoxContainer

const Widgets = preload("res://scripts/ui/design_system/widgets.gd")
const T = preload("res://scripts/ui/design_system/tokens.gd")
const Models = preload("res://scripts/campus/ai/openai_models.gd")

const Comparison=preload("res://scripts/campus/ai/model_comparison.gd")

var game: Node
var show_notice: Callable
var draft_key: String=""
var verified_signature: String=""
var service: Node
var credential: Label
var key_row: HBoxContainer
var key_field: LineEdit
var remove_key: Button
var connect_button: Button
var options: VBoxContainer
var model: Button
var model_buttons: Dictionary={}
var model_ids: Array=[]
var chosen: Dictionary={}
var picker: Popup
var picker_title: Label
var capability_heading: Label
var pricing_heading: Label
var picker_sources: LinkButton
var picker_legend: Label
var picker_scroll: ScrollContainer
var model_rows: VBoxContainer
var picker_models: Dictionary={}
var model_search: LineEdit
var show_versions: CheckBox
var picker_purpose: String=""
var tts_enabled: CheckButton
var stt_enabled: CheckButton
var output: OptionButton
var effort: OptionButton
var effort_row: HBoxContainer
var accept: Button
var ai_test: Button
var test_panel: Window
var image_effort: OptionButton
var image_model_efforts: Dictionary={}
var model_efforts: Dictionary={}
var fetching_models := false

func build(owner: Node, notice: Callable, done: Callable) -> void:
	game=owner
	show_notice=notice
	service=game.host_openai
	if not service.host_allowed():
		_label("Only the game host can configure or use the OpenAI connection.",15)
		return
	_label("The host's API key stays in this game process. It is never saved in game settings or sent to other players. You can also set OPENAI_API_KEY before starting the host.",14,T.MUTED,self,true)
	credential=_label("API key available" if service.configured() else "Enter an API key to connect",15,T.ACCENT)
	key_row=_row("API key for this run")
	key_field=LineEdit.new()
	key_field.secret=true
	key_field.placeholder_text="Paste an OpenAI API key"
	key_field.size_flags_horizontal=SIZE_EXPAND_FILL
	key_row.add_child(key_field)
	var key_actions:=HBoxContainer.new();add_child(key_actions)
	connect_button=_button(key_actions,"Connect API Key","network",func():_load_models(key_field.text.strip_edges(),true))
	remove_key=_button(key_actions,"Remove connected API key","close",_disconnect_key)
	key_field.text_submitted.connect(func(value: String):_load_models(value.strip_edges(),true))
	options=VBoxContainer.new()
	options.add_theme_constant_override("separation",8)
	add_child(options)
	options.visible=service.configured()
	model=_model_button("Text model","text")
	effort=_openai_choice(options,"Thinking effort",[],null)
	effort_row=effort.get_parent()
	effort.item_selected.connect(func(_index):model_efforts[_selected_model()]=effort.get_selected_metadata())
	output=_openai_choice(options,"Maximum output tokens",[16,32,64,128,256,384,512,768,1024,1536,2048,4096,8192,16384,32768],service.max_output_tokens)
	_model_button("Image analysis","image")
	image_effort=_openai_choice(options,"Thinking effort",[],null)
	image_effort.item_selected.connect(func(_index):image_model_efforts[chosen.image]=image_effort.get_selected_metadata())
	_model_button("Image generation","image_generation")
	tts_enabled=_voice_switch("Text-to-speech",service.tts_enabled)
	_model_button("Voice model","tts")
	stt_enabled=_voice_switch("Speech-to-text",service.stt_enabled)
	_model_button("Transcription model","stt")
	_build_picker()
	ai_test=_button(key_actions,"AI Test","play",_open_test)
	_key_controls(options.visible)
	ai_test.tooltip_text="Try each AI feature with the settings selected here."
	tts_enabled.toggled.connect(func(_value: bool):_model_changed())
	stt_enabled.toggled.connect(func(_value: bool):_model_changed())
	var actions:=HBoxContainer.new()
	add_child(actions)
	accept=_button(actions,"Accept","check",func():
		if service.accept_setup(_read_draft(),verified_signature)==OK:done.call()
		else:show_notice.call("Could not save OpenAI settings."))
	accept.visible=options.visible
	_button(actions,"Cancel","close",done)
	service.usage_changed.connect(_refresh_picker)
	model_efforts[service.model]=service.reasoning_effort
	image_model_efforts[service.image_model]=service.image_reasoning_effort
	chosen={"text":service.model,"image":service.image_model,"image_generation":service.image_generation_model,"tts":service.tts_model,"stt":service.stt_model}
	_set_models(chosen.values() if service.configured() else [],service.model)
	if service.configured():_load_models.call_deferred("",false)

func _key_controls(connected: bool) -> void:
	key_row.visible=not connected
	connect_button.visible=not connected
	remove_key.visible=connected
	ai_test.visible=connected

func _disconnect_key() -> void:
	if fetching_models:return
	draft_key=""
	verified_signature=""
	service.disconnect_key()
	model_ids.clear()
	key_field.clear()
	credential.text="Enter an API key to connect"
	options.hide()
	accept.hide()
	_key_controls(false)
	key_field.grab_focus()

func _open_test() -> void:
	if is_instance_valid(test_panel):return
	test_panel=preload("res://scripts/campus/ui/openai_test_panel.gd").new()
	add_child(test_panel)
	test_panel.open(service,_read_draft(),func(signature: String):verified_signature=signature)

func _load_models(candidate: String, refresh: bool) -> void:
	if fetching_models:return
	if candidate.is_empty():candidate=draft_key
	fetching_models=true
	connect_button.disabled=true
	remove_key.disabled=true
	_model_changed()
	credential.text="Loading available models…"
	var result: Dictionary=await service.list_models(candidate,refresh)
	if not is_inside_tree():return
	fetching_models=false
	connect_button.disabled=false
	remove_key.disabled=false
	if result.get("ok",false):
		if draft_key!=candidate:verified_signature=""
		draft_key=candidate
		key_field.clear()
		credential.text="API key connected"
		options.show()
		_key_controls(true)
		accept.show()
		var preferred:=_selected_model()
		_set_models(result.models,preferred if not preferred.is_empty() else str(service.model))
	else:
		credential.text=str(result.get("error","Could not load available models."))
		_model_changed()

func _set_models(ids: Array, preferred: String) -> void:
	model_ids=ids
	chosen.text=preferred
	for purpose: String in model_buttons:
		var candidates:=ids.filter(func(id: String):return Models.supports(id,purpose))
		if chosen.get(purpose,"") not in candidates:
			var primary:=candidates.filter(func(id: String):return id==Models.family(id))
			chosen[purpose]=str(primary[0]) if not primary.is_empty() else str(candidates[0]) if not candidates.is_empty() else ""
	_model_changed()
	_refresh_picker()

func _model_changed() -> void:
	var id:=_selected_model()
	_update_effort(effort,id,model_efforts)
	_update_effort(image_effort,str(chosen.get("image","")),image_model_efforts)
	for purpose: String in model_buttons:
		var entry: Button=model_buttons[purpose]
		var selection:=str(chosen.get(purpose,""))
		entry.text=selection+"   ▾" if not selection.is_empty() else "No compatible model"
		entry.disabled=fetching_models or selection.is_empty() or (purpose=="tts" and not tts_enabled.button_pressed) or (purpose=="stt" and not stt_enabled.button_pressed)
	var unavailable:=id.is_empty() or Models.endpoint(id).is_empty() or fetching_models
	accept.disabled=unavailable
	ai_test.disabled=fetching_models

func _update_effort(dropdown: OptionButton,id: String,saved: Dictionary) -> void:
	var values:=Models.efforts(id)
	dropdown.clear()
	dropdown.add_item("Model default")
	dropdown.set_item_metadata(0,"")
	for value: String in values:
		dropdown.add_item(value.capitalize())
		dropdown.set_item_metadata(dropdown.item_count-1,value)
	dropdown.select(values.find(saved.get(id,""))+1)
	dropdown.get_parent().visible=not values.is_empty()

func _selected_model() -> String:
	return str(chosen.get("text",""))

func _read_draft() -> Dictionary:
	return {"key":draft_key,"model":_selected_model(),"output":output.get_selected_metadata(),"effort":effort.get_selected_metadata(),
		"image_effort":image_effort.get_selected_metadata(),"modalities":chosen.duplicate(),"tts_enabled":tts_enabled.button_pressed,"stt_enabled":stt_enabled.button_pressed}

func _relative_percent(amount: float, lowest: float, highest: float) -> int:
	if is_equal_approx(lowest,highest):return 100 if highest>0 else 0
	return roundi(100.0*inverse_lerp(lowest,highest,amount))

func _usage_details(id: String) -> String:
	var usage: Dictionary=service.model_usage.get(id,{})
	if int(usage.get("requests",0))==0:return "No game usage recorded for "+id+"."
	var description: String="%s · %s\n%d requests · %d input tokens · %d output tokens"%[id,Models.tier(id),usage.get("requests",0),usage.get("input",0),usage.get("output",0)]
	if int(usage.get("reasoning",0))>0:description+=" (%d thinking)"%usage.reasoning
	if float(usage.get("seconds",0))>0:description+=" · %.1f s audio"%usage.seconds
	if Models.endpoint(id).is_empty():description+="\nRequires its specialized API. Select a text model for classroom prompts."
	return description

func _model_button(title: String,purpose: String) -> Button:
	var button:=_button(_row(title,options),"Choose model","",func():_open_picker(title,purpose))
	button.size_flags_horizontal=SIZE_EXPAND_FILL
	button.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	model_buttons[purpose]=button
	return button

func _open_picker(title: String,purpose: String) -> void:
	picker_purpose=purpose
	picker_title.text=title
	capability_heading.text={"text":"GPQA Diamond","image":"MMMU-Pro"}.get(purpose,"Benchmark")
	pricing_heading.text="USD / 1M tokens" if purpose in ["text","image"] else "USD / 1M image tokens" if purpose=="image_generation" else "API price"
	picker_legend.text="Published benchmark accuracy · Standard API rates" if purpose in ["text","image"] else "Standard API rates · Audio minute prices are estimates" if purpose in ["tts","stt"] else "Image token rates · Cost per image varies by size and quality"
	model_search.clear()
	var screen:=get_viewport_rect().size
	var anchor: Rect2=model_buttons[purpose].get_global_rect()
	var width:=mini(680,int(screen.x)-20)
	var below:=screen.y-anchor.end.y-12.0
	var above:=anchor.position.y-12.0
	var open_below:=below>=310.0 or below>=above
	var height:=mini(400,maxi(220,int(below if open_below else above)))
	var x:=clampi(int(anchor.get_center().x)-width/2,10,maxi(10,int(screen.x)-width-10))
	var y:=int(anchor.end.y)+6 if open_below else int(anchor.position.y)-height-6
	y=clampi(y,10,maxi(10,int(screen.y)-height-10))
	picker.popup(Rect2i(x,y,width,height))
	picker.size=Vector2i(width,height)
	picker.position=Vector2i(x,y)
	_refresh_picker()
	picker_scroll.scroll_vertical=0
	model_search.grab_focus()

func _voice_switch(title: String,value: bool) -> CheckButton:
	var toggle:=CheckButton.new()
	toggle.text="Enable"
	toggle.button_pressed=value
	_row(title,options).add_child(toggle)
	return toggle

func _build_picker() -> void:
	picker=Popup.new()
	picker.wrap_controls=false
	add_child(picker)
	var card:=PanelContainer.new()
	card.add_theme_stylebox_override("panel",T.surface(Color("102633"),T.BORDER,14))
	picker.add_child(card)
	card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var stack:=VBoxContainer.new()
	stack.add_theme_constant_override("separation",8)
	card.add_child(stack)
	picker_title=_label("",20,T.INK,stack)
	var filters:=HBoxContainer.new()
	stack.add_child(filters)
	model_search=LineEdit.new()
	model_search.placeholder_text="Search models"
	model_search.size_flags_horizontal=SIZE_EXPAND_FILL
	model_search.text_changed.connect(func(_value: String):_refresh_picker())
	filters.add_child(model_search)
	show_versions=CheckBox.new()
	show_versions.text="Dated versions"
	show_versions.toggled.connect(func(_value: bool):_refresh_picker())
	filters.add_child(show_versions)
	var headings:=HBoxContainer.new()
	stack.add_child(headings)
	_picker_column(_label("Model",14,T.MUTED,headings),2.0)
	capability_heading=_label("Benchmark",14,T.MUTED,headings)
	_picker_column(capability_heading,1.0)
	pricing_heading=_label("API price",14,T.MUTED,headings)
	_picker_column(pricing_heading,1.45)
	picker_scroll=ScrollContainer.new()
	picker_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	picker_scroll.vertical_scroll_mode=ScrollContainer.SCROLL_MODE_RESERVE
	picker_scroll.size_flags_vertical=SIZE_EXPAND_FILL
	stack.add_child(picker_scroll)
	model_rows=VBoxContainer.new()
	model_rows.size_flags_horizontal=SIZE_EXPAND_FILL
	model_rows.add_theme_constant_override("separation",6)
	picker_scroll.add_child(model_rows)
	var footer:=HBoxContainer.new()
	stack.add_child(footer)
	picker_legend=_label("",13,T.MUTED,footer)
	picker_sources=LinkButton.new()
	picker_sources.text="OpenAI pricing"
	picker_sources.uri=Comparison.PRICING_URL
	footer.add_child(picker_sources)
	picker_legend.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS

func _picker_column(control: Control, ratio: float) -> void:
	control.size_flags_horizontal=SIZE_EXPAND_FILL
	control.size_flags_stretch_ratio=ratio

func _choose_model(id: String) -> void:
	chosen[picker_purpose]=id
	picker.hide()
	_model_changed()

func _meter(parent: Control, percent: int, caption: String, fill: Color, ratio: float) -> void:
	var meter:=ProgressBar.new()
	meter.show_percentage=false
	meter.value=maxi(0,percent)
	meter.custom_minimum_size.y=32
	meter.add_theme_stylebox_override("background",T.surface(Color("12232d"),Color("365765"),0))
	meter.add_theme_stylebox_override("fill",T.surface(fill,fill.lightened(0.15),0))
	_picker_column(meter,ratio)
	parent.add_child(meter)
	var value:=Label.new()
	value.text=caption
	value.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	value.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	value.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	value.add_theme_font_size_override("font_size",13)
	value.add_theme_color_override("font_color",T.INK)
	value.mouse_filter=Control.MOUSE_FILTER_IGNORE
	meter.add_child(value)
	value.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _refresh_picker() -> void:
	if not is_instance_valid(picker) or not picker.visible or picker_purpose.is_empty():return
	for child in model_rows.get_children():
		model_rows.remove_child(child)
		child.queue_free()
	picker_models.clear()
	var candidates:=model_ids.filter(func(id: String):return Models.supports(id,picker_purpose))
	var selected:=str(chosen.get(picker_purpose,""))
	if candidates.has(selected):
		candidates.erase(selected)
		candidates.push_front(selected)
	var prices: Dictionary={}
	for candidate: String in candidates:
		var rate:=Comparison.pricing(candidate,picker_purpose)
		if not rate.is_empty():prices.get_or_add(rate.basis,[]).append(float(rate.compare))
	var query:=model_search.text.strip_edges().to_lower()
	for id: String in candidates:
		if not query.is_empty() and not query in id.to_lower():continue
		if query.is_empty() and not show_versions.button_pressed and id!=chosen.get(picker_purpose) and id!=Models.family(id) and Models.family(id) in candidates:continue
		var score:=Comparison.score(id,picker_purpose)
		var rated:=roundi(score) if score>=0 else -1
		var rate:=Comparison.pricing(id,picker_purpose)
		var cost_meter:=-1
		if not rate.is_empty():
			var costs: Array=prices[rate.basis]
			cost_meter=_relative_percent(rate.compare,costs.min(),costs.max())
		var row:=HBoxContainer.new()
		row.tooltip_text=_usage_details(id)
		if not rate.is_empty():row.tooltip_text+="\n"+str(rate.label)+" · "+str(rate.unit)
		model_rows.add_child(row)
		var select:=_button(row,id,"check" if id==chosen.get(picker_purpose) else "",func():_choose_model(id))
		select.alignment=HORIZONTAL_ALIGNMENT_LEFT
		select.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
		select.tooltip_text=row.tooltip_text
		_picker_column(select,2.0)
		_meter(row,rated,"%.1f%%"%score if rated>=0 else "No comparable score",Color("246653"),1.0)
		_meter(row,cost_meter,str(rate.get("label","Rate unavailable")),Color("285985"),1.45)
		picker_models[id]={"benchmark":score,"price":rate}
	if picker_models.is_empty():_label("No matching models.",15,T.MUTED,model_rows)

func _openai_choice(parent: Control, title: String, values: Array, saved: Variant) -> OptionButton:
	if saved!=null and not values.has(saved):
		values.append(saved)
		if saved is int:values.sort()
	var dropdown:=OptionButton.new()
	dropdown.custom_minimum_size.y=34
	dropdown.size_flags_horizontal=SIZE_EXPAND_FILL
	dropdown.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	for value in values:
		dropdown.add_item(str(value))
		dropdown.set_item_metadata(dropdown.item_count-1,value)
	dropdown.select(values.find(saved))
	_row(title,parent).add_child(dropdown)
	return dropdown

func _row(title: String, parent: Control=null) -> HBoxContainer:
	var row:=HBoxContainer.new()
	(parent if parent!=null else self).add_child(row)
	var label:=Widgets.text(title)
	label.custom_minimum_size.x=158
	label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	row.add_child(label)
	return row

func _label(title: String, text_size: int, color := T.INK, parent: Control=null, wrap := false) -> Label:
	var label:=Widgets.text(title)
	label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART if wrap else TextServer.AUTOWRAP_OFF
	label.add_theme_font_size_override("font_size",text_size)
	label.add_theme_color_override("font_color",color)
	(parent if parent!=null else self).add_child(label)
	return label

func _button(parent: Node, title: String, icon: String, action: Callable) -> Button:
	var button:=Widgets.action(title,icon,action)
	button.custom_minimum_size.y=36
	parent.add_child(button)
	return button
