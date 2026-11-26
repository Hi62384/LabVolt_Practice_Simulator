extends VBoxContainer

const Widgets = preload("res://scripts/ui/design_system/widgets.gd")
const T = preload("res://scripts/ui/design_system/tokens.gd")
const Models = preload("res://scripts/campus/ai/openai_models.gd")

var game: Node
var show_notice: Callable
var draft_key: String=""
var verified_signature: String=""
var service: Node
var credential: Label
var key_field: LineEdit
var connect_button: Button
var options: VBoxContainer
var model: Button
var model_buttons: Dictionary={}
var model_ids: Array=[]
var chosen: Dictionary={}
var picker: PanelContainer
var model_tree: Tree
var model_search: LineEdit
var show_versions: CheckBox
var picker_purpose: String=""
var tts_enabled: CheckButton
var stt_enabled: CheckButton
var output: OptionButton
var effort: OptionButton
var effort_row: HBoxContainer
var model_details: Label
var accept: Button
var test_button: Button
var prompt_button: Button
var image_test_button: Button
var model_efforts: Dictionary={}
var fetching_models := false

func build(owner: Node, notice: Callable, done: Callable) -> void:
	game=owner
	show_notice=notice
	service=game.host_openai
	if not service.host_allowed():
		_label("Only the game host can configure or use the OpenAI connection.",15)
		return
	var note:=_label("The host's API key stays in this game process. It is never saved in game settings or sent to other players. You can also set OPENAI_API_KEY before starting the host.",14)
	note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	credential=_label("API key available" if service.configured() else "Enter an API key to connect",15,T.ACCENT)
	var key_row:=_row("API key for this run")
	key_field=LineEdit.new()
	key_field.secret=true
	key_field.placeholder_text="Paste an OpenAI API key"
	key_field.size_flags_horizontal=SIZE_EXPAND_FILL
	key_row.add_child(key_field)
	var key_actions:=HBoxContainer.new();add_child(key_actions)
	connect_button=_button(key_actions,"Connect API Key","network",func():_load_models(key_field.text.strip_edges(),true))
	key_field.text_submitted.connect(func(value: String):_load_models(value.strip_edges(),true))
	options=VBoxContainer.new()
	options.add_theme_constant_override("separation",8)
	add_child(options)
	options.visible=service.configured()
	model=_model_button("Text model","text")
	_model_button("Image analysis","image")
	_model_button("Image generation","image_generation")
	tts_enabled=_voice_switch("Text-to-speech",service.tts_enabled)
	_model_button("Voice model","tts")
	stt_enabled=_voice_switch("Speech-to-text",service.stt_enabled)
	_model_button("Transcription model","stt")
	_build_picker()
	model_details=_label("",14,T.MUTED,options)
	model_details.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	output=_openai_choice(options,"Maximum output tokens",[16,32,64,128,256,384,512,768,1024,1536,2048,4096,8192,16384,32768],service.max_output_tokens)
	effort=_openai_choice(options,"Thinking effort",[],null)
	effort_row=effort.get_parent()
	effort.item_selected.connect(func(_index):model_efforts[_selected_model()]=effort.get_selected_metadata())
	var actions:=HBoxContainer.new()
	add_child(actions)
	accept=_button(actions,"Accept","check",func():
		if service.accept_setup(_read_draft(),verified_signature)==OK:done.call()
		else:show_notice.call("Could not save OpenAI settings."))
	accept.visible=options.visible
	_button(actions,"Cancel","close",done)
	var prompt_row:=_row("Try a prompt",options)
	var prompt_field:=LineEdit.new()
	prompt_field.placeholder_text="Ask a short question"
	prompt_field.max_length=4000
	prompt_field.size_flags_horizontal=SIZE_EXPAND_FILL
	prompt_row.add_child(prompt_field)
	var answer:=_label("",14,T.ACCENT,options)
	answer.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	var run_prompt:=func(prompt: String,verify: bool):
		answer.text="Waiting for OpenAI…"
		var result: Dictionary=await service.preview_setup_prompt(prompt,_read_draft())
		if not is_inside_tree():return
		_update_model_details()
		if result.get("ok",false):
			verified_signature=result.signature
			credential.text="API key connected"
		answer.text="Response verified. Accept to use this connection in class." if verify and result.get("ok",false) else str(result.get("text",result.get("error","No response.")))
	var tests:=HBoxContainer.new()
	options.add_child(tests)
	test_button=_button(tests,"Test Connection","network",func():run_prompt.call("Reply with the single word Ready.",true))
	prompt_button=_button(tests,"Send Prompt","play",func():run_prompt.call(prompt_field.text,false))
	var voice_player:=AudioStreamPlayer.new()
	add_child(voice_player)
	var voice_test:=_button(tests,"Test Voice","volume",func():
		var result: Dictionary=await service.speak("Welcome to Campus.",_read_draft())
		if not is_inside_tree():return
		if result.get("ok",false):voice_player.stream=result.stream;voice_player.play()
		else:answer.text=str(result.error))
	voice_test.visible=tts_enabled.button_pressed
	var image_preview:=TextureRect.new()
	image_preview.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	image_preview.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image_preview.custom_minimum_size.y=256
	image_preview.hide()
	image_test_button=_button(tests,"Test Image","scope",func():
		image_test_button.disabled=true
		image_preview.hide()
		answer.text="Generating an image…"
		var result: Dictionary=await service.generate_image(prompt_field.text,_read_draft())
		if not is_inside_tree():return
		_model_changed()
		if result.get("ok",false):
			image_preview.texture=ImageTexture.create_from_image(result.image)
			image_preview.show()
			answer.text="Image generated"
		else:answer.text=str(result.error))
	image_test_button.tooltip_text="Generate one image from the test prompt using your API key."
	options.add_child(image_preview)
	tts_enabled.toggled.connect(func(value: bool):voice_test.visible=value;_model_changed())
	stt_enabled.toggled.connect(func(_value: bool):_model_changed())
	var usage_note:=_label("Game usage counts requests made by this installation. Account-wide usage is available in the OpenAI dashboard.",13,T.MUTED,options)
	usage_note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	service.usage_changed.connect(func():_update_model_details();_refresh_picker())
	model_efforts[service.model]=service.reasoning_effort
	chosen={"text":service.model,"image":service.image_model,"image_generation":service.image_generation_model,"tts":service.tts_model,"stt":service.stt_model}
	_set_models(chosen.values() if service.configured() else [],service.model)
	if service.configured():_load_models.call_deferred("",false)

func _load_models(candidate: String, refresh: bool) -> void:
	if fetching_models:return
	if candidate.is_empty():candidate=draft_key
	fetching_models=true
	connect_button.disabled=true
	_model_changed()
	credential.text="Loading available models…"
	var result: Dictionary=await service.list_models(candidate,refresh)
	if not is_inside_tree():return
	fetching_models=false
	connect_button.disabled=false
	if result.get("ok",false):
		if draft_key!=candidate:verified_signature=""
		draft_key=candidate
		key_field.clear()
		credential.text="API key connected"
		options.show()
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
	var values:=Models.efforts(id)
	effort.clear()
	effort.add_item("Model default")
	effort.set_item_metadata(0,"")
	for value: String in values:
		effort.add_item(value.capitalize())
		effort.set_item_metadata(effort.item_count-1,value)
	effort.select(values.find(model_efforts.get(id,""))+1)
	effort_row.visible=not values.is_empty()
	_update_model_details()
	for purpose: String in model_buttons:
		var entry: Button=model_buttons[purpose]
		var selection:=str(chosen.get(purpose,""))
		entry.text=selection+"   ▾" if not selection.is_empty() else "No compatible model"
		entry.disabled=fetching_models or selection.is_empty() or (purpose=="tts" and not tts_enabled.button_pressed) or (purpose=="stt" and not stt_enabled.button_pressed)
	var unavailable:=id.is_empty() or Models.endpoint(id).is_empty() or fetching_models
	accept.disabled=unavailable
	test_button.disabled=unavailable
	prompt_button.disabled=unavailable
	image_test_button.disabled=fetching_models or str(chosen.get("image_generation","")).is_empty()

func _selected_model() -> String:
	return str(chosen.get("text",""))

func _read_draft() -> Dictionary:
	return {"key":draft_key,"model":_selected_model(),"output":output.get_selected_metadata(),"effort":effort.get_selected_metadata(),
		"modalities":chosen.duplicate(),"tts_enabled":tts_enabled.button_pressed,"stt_enabled":stt_enabled.button_pressed}

func _usage_summary(id: String) -> String:
	var usage: Dictionary=service.model_usage.get(id,{})
	if int(usage.get("requests",0))==0:return "No game usage yet"
	var tokens: int=int(usage.get("input",0))+int(usage.get("output",0))
	var amount: String="%d tokens"%tokens
	if float(usage.get("seconds",0))>0:amount="%.1f s audio"%usage.seconds
	elif tokens==0 and int(usage.get("requests",0))>0:amount="%d requests"%usage.requests
	return amount

func _usage_details(id: String) -> String:
	var usage: Dictionary=service.model_usage.get(id,{})
	if int(usage.get("requests",0))==0:return "No game usage recorded for "+id+"."
	var description: String="%s · %s\n%d requests · %d input tokens · %d output tokens"%[id,Models.tier(id),usage.get("requests",0),usage.get("input",0),usage.get("output",0)]
	if int(usage.get("reasoning",0))>0:description+=" (%d thinking)"%usage.reasoning
	if float(usage.get("seconds",0))>0:description+=" · %.1f s audio"%usage.seconds
	if Models.endpoint(id).is_empty():description+="\nRequires its specialized API. Select a text model for classroom prompts."
	return description

func _model_button(title: String,purpose: String) -> Button:
	var button:=_button(_row(title,options),"Choose model","",func():
		picker.visible=not picker.visible or picker_purpose!=purpose
		picker_purpose=purpose
		model_search.clear()
		_refresh_picker()
		if picker.visible:model_search.grab_focus())
	button.size_flags_horizontal=SIZE_EXPAND_FILL
	button.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	model_buttons[purpose]=button
	return button

func _voice_switch(title: String,value: bool) -> CheckButton:
	var toggle:=CheckButton.new()
	toggle.text="Enable"
	toggle.button_pressed=value
	_row(title,options).add_child(toggle)
	return toggle

func _build_picker() -> void:
	picker=PanelContainer.new()
	picker.add_theme_stylebox_override("panel",T.surface(T.SURFACE,T.BORDER,10))
	options.add_child(picker)
	var stack:=VBoxContainer.new()
	picker.add_child(stack)
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
	model_tree=Tree.new()
	model_tree.columns=3
	model_tree.hide_root=true
	model_tree.column_titles_visible=true
	model_tree.set_column_title(0,"Model")
	model_tree.set_column_title(1,"Capability")
	model_tree.set_column_title(2,"Game usage")
	model_tree.set_column_expand_ratio(0,3)
	model_tree.set_column_expand_ratio(1,2)
	model_tree.set_column_expand_ratio(2,2)
	model_tree.custom_minimum_size.y=250
	stack.add_child(model_tree)
	model_tree.item_activated.connect(_choose_tree_model)
	_button(filters,"Choose","check",_choose_tree_model)
	picker.hide()

func _choose_tree_model() -> void:
	var row:=model_tree.get_selected()
	if row==null:return
	chosen[picker_purpose]=str(row.get_metadata(0))
	picker.hide()
	_model_changed()

func _refresh_picker() -> void:
	if not is_instance_valid(model_tree) or picker_purpose.is_empty():return
	model_tree.clear()
	var root:=model_tree.create_item()
	var aliases:=model_ids.filter(func(id: String):return id==Models.family(id))
	var query:=model_search.text.strip_edges().to_lower()
	for id: String in model_ids:
		if not Models.supports(id,picker_purpose) or (not query.is_empty() and not query in id.to_lower()):continue
		if query.is_empty() and not show_versions.button_pressed and id!=chosen.get(picker_purpose) and id!=Models.family(id) and Models.family(id) in aliases:continue
		var row:=model_tree.create_item(root)
		row.set_text(0,id)
		var capability:=Models.tier(id)
		match picker_purpose:
			"image_generation":capability="Image generation"
			"tts":capability="Speech output"
			"stt":capability="Transcription"
		row.set_text(1,capability)
		row.set_text(2,_usage_summary(id))
		row.set_tooltip_text(2,_usage_details(id))
		row.set_metadata(0,id)
		if id==chosen.get(picker_purpose):row.select(0)

func _update_model_details() -> void:
	var id:=_selected_model()
	model_details.text=_usage_details(id) if not id.is_empty() else "No models available for this key."

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

func _label(title: String, text_size: int, color := T.INK, parent: Control=null) -> Label:
	var label:=Widgets.text(title)
	label.add_theme_font_size_override("font_size",text_size)
	label.add_theme_color_override("font_color",color)
	(parent if parent!=null else self).add_child(label)
	return label

func _button(parent: Node, title: String, icon: String, action: Callable) -> Button:
	var button:=Widgets.action(title,icon,action)
	button.custom_minimum_size.y=36
	parent.add_child(button)
	return button
