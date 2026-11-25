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
var model: OptionButton
var output: OptionButton
var effort: OptionButton
var effort_row: HBoxContainer
var model_details: Label
var accept: Button
var test_button: Button
var prompt_button: Button
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
	model=_openai_choice(options,"Model",[],null)
	model.fit_to_longest_item=false
	model.get_popup().max_size=Vector2i(0,480)
	model.get_popup().allow_search=true
	model_details=_label("",14,T.MUTED,options)
	model.item_selected.connect(func(_index):_model_changed())
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
		for index in model.item_count:
			var id: String=model.get_item_metadata(index)
			model.set_item_text(index,_model_label(id))
			model.get_popup().set_item_tooltip(index,_usage_details(id))
		_update_model_details()
		if result.get("ok",false):
			verified_signature=result.signature
			credential.text="API key connected"
		answer.text="Response verified. Accept to use this connection in class." if verify and result.get("ok",false) else str(result.get("text",result.get("error","No response.")))
	var tests:=HBoxContainer.new()
	options.add_child(tests)
	test_button=_button(tests,"Test Connection","network",func():run_prompt.call("Reply with the single word Ready.",true))
	prompt_button=_button(tests,"Send Prompt","play",func():run_prompt.call(prompt_field.text,false))
	_label("Usage counts replies handled by this game installation. Accept to let classroom prompts and requested voice transcription use your OpenAI account.",13,T.MUTED,options)
	model_efforts[service.model]=service.reasoning_effort
	_set_models([service.model] if service.configured() else [],service.model)
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
		_set_models(result.models,_selected_model() if model.selected>=0 else service.model)
	else:
		credential.text=str(result.get("error","Could not load available models."))
		_model_changed()

func _set_models(ids: Array, preferred: String) -> void:
	model.clear()
	var index := -1
	var first_text := -1
	for id: String in ids:
		model.add_item(_model_label(id))
		var row:=model.item_count-1
		model.set_item_metadata(row,id)
		model.get_popup().set_item_tooltip(row,_usage_details(id))
		if id==preferred:index=row
		if first_text<0 and not Models.endpoint(id).is_empty():first_text=row
	model.select(index if index>=0 else first_text if first_text>=0 else 0 if model.item_count>0 else -1)
	_model_changed()

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
	var unavailable:=id.is_empty() or Models.endpoint(id).is_empty() or fetching_models
	accept.disabled=unavailable
	test_button.disabled=unavailable
	prompt_button.disabled=unavailable

func _selected_model() -> String:
	return str(model.get_selected_metadata()) if model.selected>=0 else ""

func _read_draft() -> Dictionary:
	return {"key":draft_key,"model":_selected_model(),"output":output.get_selected_metadata(),"effort":effort.get_selected_metadata()}

func _model_label(id: String) -> String:
	var usage: Dictionary=service.model_usage.get(id,{})
	var tokens: int=int(usage.get("input",0))+int(usage.get("output",0))
	var amount: String="%d tokens"%tokens
	if float(usage.get("seconds",0))>0:amount="%.1f s audio"%usage.seconds
	elif tokens==0 and int(usage.get("requests",0))>0:amount="%d requests"%usage.requests
	return "%s  ·  %s  ·  %s"%[id,Models.tier(id),amount]

func _usage_details(id: String) -> String:
	var usage: Dictionary=service.model_usage.get(id,{})
	var description: String="%s · %s\n%d requests · %d input tokens · %d output tokens"%[id,Models.tier(id),usage.get("requests",0),usage.get("input",0),usage.get("output",0)]
	if int(usage.get("reasoning",0))>0:description+=" (%d thinking)"%usage.reasoning
	if float(usage.get("seconds",0))>0:description+=" · %.1f s audio"%usage.seconds
	if Models.endpoint(id).is_empty():description+="\nRequires its specialized API. Select a text model for classroom prompts."
	return description

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
