extends VBoxContainer

const Widgets = preload("res://scripts/ui/design_system/widgets.gd")
const T = preload("res://scripts/ui/design_system/tokens.gd")
const Models = preload("res://scripts/campus/ai/openai_models.gd")

const Comparison=preload("res://scripts/campus/ai/model_comparison.gd")
const Pricing=preload("res://scripts/campus/ai/model_pricing.gd")
const Evaluation=preload("res://scripts/campus/ai/openai_evaluation.gd")
const PURPOSES:={"text":"Text","image":"Image analysis","image_generation":"Image generation","tts":"Speech output","stt":"Transcription"}
const EFFORTS:=["","none","minimal","low","medium","high","xhigh","max"]
const SCENARIOS:={"Teacher reply":[800,200],"Teaching explanation":[1800,500],"Lesson plan":[4000,1000],"Image analysis":[1400,260],"Custom":[1000,300]}
const SORTS:=["Benchmark","Estimated cost","Input rate","Output rate","Latency","Newest snapshot","Model name","Local requests"]
const METRIC_SCORE:=Color("8de4cc")
const METRIC_TIME:=Color("8abef5")
const METRIC_PRICE:=Color("f2bd88")
const METRIC_REQUESTS:=Color("cbb1f3")

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
var preview_effort: OptionButton
var preview_mode: OptionButton
var category_filter: OptionButton
var sort_by: OptionButton
var scenario: OptionButton
var pricing_tier: OptionButton
var custom_input: SpinBox
var custom_output: SpinBox
var assumptions: Label
var show_deprecated: CheckBox
var show_advanced: CheckBox
var account_only: CheckBox
var detail_id:=""
var pinned: Array[String]=[]
var evaluation:=Evaluation.new()
var evaluation_status: Label
var usage_name: LineEdit
var actual_mode: OptionButton
var actual_image_mode: OptionButton
var saved_modes: Dictionary={}
var saved_image_modes: Dictionary={}
var compare_measurements: CheckBox
var picker_scroll: ScrollContainer
var model_rows: VBoxContainer
var picker_models: Dictionary={}
var model_search: LineEdit
var show_versions: CheckBox
var picker_purpose: String=""
var tts_enabled: CheckButton
var stt_enabled: CheckButton
var voice_notices: Dictionary={}
var voice_studio: Window
var account_models_known:=false
var output: OptionButton
var effort: OptionButton
var effort_row: HBoxContainer
var accept: Button
var ai_test: Button
var test_panel: Window
var image_size: OptionButton
var image_quality: OptionButton
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
	_button(key_actions,"Refresh models","",func():_load_models(draft_key,true))
	key_field.text_submitted.connect(func(value: String):_load_models(value.strip_edges(),true))
	options=VBoxContainer.new()
	options.add_theme_constant_override("separation",8)
	add_child(options)
	options.visible=true
	model=_model_button("Text model","text")
	effort=_openai_choice(options,"Thinking effort",[],null)
	effort_row=effort.get_parent()
	effort.item_selected.connect(func(_index):model_efforts[_selected_model()]=effort.get_selected_metadata())
	actual_mode=_openai_choice(options,"Reasoning mode",["standard","pro"],"standard")
	actual_mode.item_selected.connect(func(_index):saved_modes[_selected_model()]=actual_mode.get_selected_metadata())
	output=_openai_choice(options,"Maximum output tokens",[16,32,64,128,256,384,512,768,1024,1536,2048,4096,8192,16384,32768],service.max_output_tokens)
	_model_button("Image analysis","image")
	image_effort=_openai_choice(options,"Thinking effort",[],null)
	image_effort.item_selected.connect(func(_index):image_model_efforts[chosen.image]=image_effort.get_selected_metadata())
	actual_image_mode=_openai_choice(options,"Reasoning mode",["standard","pro"],"standard")
	actual_image_mode.item_selected.connect(func(_index):saved_image_modes[chosen.image]=actual_image_mode.get_selected_metadata())
	_model_button("Image generation","image_generation")
	image_size=_openai_choice(options,"Image resolution",["1024x1024","1536x1024","1024x1536"],service.image_generation_options.size)
	image_quality=_openai_choice(options,"Image quality",["low","medium","high","auto","xhigh","max"],service.image_generation_options.quality)
	tts_enabled=_voice_switch("NPC speech",service.tts_enabled)
	_model_button("Speech output model","tts")
	voice_notices.tts=_label("",13,T.ACCENT,options,true)
	stt_enabled=_voice_switch("Speech recognition",service.stt_enabled)
	_model_button("Transcription model","stt")
	voice_notices.stt=_label("",13,T.ACCENT,options,true)
	_label("NPC voices are AI-generated. Microphone turns are recorded locally, transcribed, answered by the character, then spoken. GPT-Live and Realtime perform dialogue through short speech-only sessions. Character voices and saved designs remain available offline.",13,T.MUTED,options,true)
	_button(options,"Character Voices…","play",_open_voice_studio)
	usage_name=LineEdit.new()
	usage_name.max_length=36
	usage_name.placeholder_text="Optional · one name per project or organization"
	usage_name.text=str(service.usage_profile)
	usage_name.size_flags_horizontal=SIZE_EXPAND_FILL
	_row("Local usage profile",options).add_child(usage_name)
	_build_picker()
	ai_test=_button(key_actions,"AI Test","play",_open_test)
	_key_controls(service.configured())
	ai_test.tooltip_text="Try each AI feature with the settings selected here."
	tts_enabled.toggled.connect(func(_value: bool):_model_changed())
	stt_enabled.toggled.connect(func(_value: bool):_model_changed())
	var actions:=HBoxContainer.new()
	add_child(actions)
	accept=_button(actions,"Accept","check",func():
		if service.accept_setup(_read_draft(),verified_signature)==OK:done.call()
		else:show_notice.call("Could not save OpenAI settings."))
	accept.visible=true
	_button(actions,"Cancel","close",done)
	service.usage_changed.connect(_refresh_picker)
	saved_modes[service.model]=service.reasoning_mode
	saved_image_modes[service.image_model]=service.image_reasoning_mode
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
	options.show()
	accept.show()
	_key_controls(false)
	_model_changed()
	key_field.grab_focus()

func _open_test() -> void:
	if is_instance_valid(test_panel):return
	test_panel=preload("res://scripts/campus/ui/openai_test_panel.gd").new()
	add_child(test_panel)
	test_panel.open(service,_read_draft(),func(signature: String):verified_signature=signature)

func _open_voice_studio() -> void:
	if is_instance_valid(voice_studio):voice_studio.grab_focus();return
	voice_studio=Window.new()
	voice_studio.title="Character Voices"
	voice_studio.min_size=Vector2i(720,460)
	voice_studio.size=Vector2i(1060,700).min(Vector2i(get_viewport_rect().size)-Vector2i(40,60))
	add_child(voice_studio)
	voice_studio.close_requested.connect(func():voice_studio.queue_free())
	var backdrop:=PanelContainer.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var style:=StyleBoxFlat.new();style.bg_color=T.SURFACE
	backdrop.add_theme_stylebox_override("panel",style)
	voice_studio.add_child(backdrop)
	var margin:=MarginContainer.new()
	for side in ["left","right","top","bottom"]:margin.add_theme_constant_override("margin_"+side,16)
	backdrop.add_child(margin)
	var studio: Control=load("res://scripts/campus/ui/character_voice_studio.gd").new()
	studio.size_flags_horizontal=SIZE_EXPAND_FILL;studio.size_flags_vertical=SIZE_EXPAND_FILL
	margin.add_child(studio)
	studio.configure(service,_read_draft())
	voice_studio.popup_centered(voice_studio.size)

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
		account_models_known=true
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
		if str(chosen.get(purpose,"")).is_empty():chosen[purpose]=Models.recommended_choice(ids,purpose)
	_model_changed()
	_refresh_picker()

func _model_changed() -> void:
	var generation:=Models.image_generation_options(str(chosen.get("image_generation","")))
	var old_quality: Variant=image_quality.get_selected_metadata()
	image_quality.clear()
	var qualities: Array=generation.get("qualities",["low"])
	for quality in qualities:
		image_quality.add_item(str(quality));image_quality.set_item_metadata(image_quality.item_count-1,quality)
	image_quality.select(maxi(0,qualities.find(old_quality)))
	image_size.get_parent().visible=not generation.is_empty()
	image_quality.get_parent().visible=not generation.is_empty()
	var id:=_selected_model()
	_update_effort(effort,id,model_efforts)
	_update_effort(image_effort,str(chosen.get("image","")),image_model_efforts)
	_update_mode(actual_mode,id,saved_modes)
	_update_mode(actual_image_mode,str(chosen.get("image","")),saved_image_modes)
	for purpose: String in model_buttons:
		var entry: Button=model_buttons[purpose]
		var selection:=str(chosen.get(purpose,""))
		entry.text=selection+"   ▾" if not selection.is_empty() else "Compare models"
		if not selection.is_empty() and (selection not in model_ids or not Models.available_for(selection,purpose)):
			entry.text=selection+" · Unavailable"
			entry.tooltip_text="Your saved choice is unavailable. Open the picker to choose a replacement."
		else:entry.tooltip_text=""
		if voice_notices.has(purpose):
			var message:=Models.lifecycle_description(selection) if not selection.is_empty() else "Choose a model."
			if account_models_known and selection not in model_ids:message+=" Not listed for this API account."
			if purpose=="tts" and Models.supports(selection,"live"):message+=" Prompt-generated voices supported. Dialogue is verified before playback."
			elif purpose=="tts" and Models.supports(selection,"realtime"):message+=" Preset or recording-based voices. Prompt-generated voices require GPT-Live."
			voice_notices[purpose].text=message
		entry.disabled=fetching_models or (purpose=="tts" and not tts_enabled.button_pressed) or (purpose=="stt" and not stt_enabled.button_pressed)
	var unavailable:=id not in model_ids or not Models.available_for(id,"text") or fetching_models
	for purpose in ["image","image_generation"]:
		var selected:=str(chosen.get(purpose,""))
		if not selected.is_empty() and (not Models.available_for(selected,purpose) or (account_models_known and selected not in model_ids)):unavailable=true
	for purpose in ["tts","stt"]:
		var active: bool={"tts":tts_enabled.button_pressed,"stt":stt_enabled.button_pressed}[purpose]
		if active and (not Models.available_for(str(chosen.get(purpose,"")),purpose) or (account_models_known and chosen.get(purpose) not in model_ids)):unavailable=true
	accept.disabled=unavailable
	ai_test.disabled=fetching_models

func _update_effort(dropdown: OptionButton,id: String,saved: Dictionary) -> void:
	var values:=Models.efforts(id)
	dropdown.clear()
	dropdown.add_item("Model default")
	dropdown.set_item_metadata(0,"")
	for value: String in values:
		dropdown.add_item(Comparison.display_effort(value))
		dropdown.set_item_metadata(dropdown.item_count-1,value)
	dropdown.select(values.find(saved.get(id,""))+1)
	dropdown.get_parent().visible=not values.is_empty()

func _update_mode(dropdown: OptionButton,id: String, saved: Dictionary) -> void:
	dropdown.get_parent().visible=Models.has_pro_mode(id)
	dropdown.select(1 if Models.has_pro_mode(id) and saved.get(id)=="pro" else 0)

func _selected_model() -> String:
	return str(chosen.get("text",""))

func _read_draft() -> Dictionary:
	return {"key":draft_key,"model":_selected_model(),"output":output.get_selected_metadata(),"effort":effort.get_selected_metadata(),
		"image_effort":image_effort.get_selected_metadata(),"mode":actual_mode.get_selected_metadata(),"image_mode":actual_image_mode.get_selected_metadata(),
		"image_generation_options":{"size":image_size.get_selected_metadata(),"quality":image_quality.get_selected_metadata(),"output_format":"png"},
		"usage_profile":usage_name.text,"modalities":chosen.duplicate(),"tts_enabled":tts_enabled.button_pressed,"stt_enabled":stt_enabled.button_pressed,"live_enabled":false}

func _model_button(title: String,purpose: String) -> Button:
	var button:=_button(_row(title,options),"Choose model","",func():_open_picker(title,purpose))
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

func _open_picker(_title: String,purpose: String) -> void:
	category_filter.select(PURPOSES.keys().find(purpose))
	detail_id=""
	model_search.clear()
	_set_purpose(purpose)
	var viewport:=get_viewport_rect().size
	var bounds:=Vector2i(minf(1100,viewport.x-36),minf(642,viewport.y-68))
	var at:=Vector2i((viewport-Vector2(bounds))*.5)
	picker.popup(Rect2i(at,bounds))
	picker.size=bounds
	picker.position=at
	_refresh_picker()
	picker_scroll.scroll_vertical=0
	model_search.grab_focus()

func _set_purpose(purpose: String) -> void:
	picker_purpose=purpose
	var reasoning:=purpose in ["text","image"]
	preview_effort.get_parent().visible=reasoning
	preview_mode.get_parent().visible=reasoning
	scenario.get_parent().visible=reasoning
	compare_measurements.visible=purpose=="text"
	if not reasoning:
		preview_effort.select(0)
		preview_mode.select(0)
		detail_id=""
	_refresh_picker()

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
	var title_row:=HBoxContainer.new()
	stack.add_child(title_row)
	picker_title=_label("Choose AI Model",23,T.INK,title_row)
	picker_title.size_flags_horizontal=SIZE_EXPAND_FILL
	_button(title_row,"Close","close",picker.hide)
	var settings:=HFlowContainer.new()
	stack.add_child(settings)
	category_filter=_filter(settings,"Category",PURPOSES.values(),PURPOSES.keys())
	category_filter.item_selected.connect(func(_index):_set_purpose(str(category_filter.get_selected_metadata())))
	var effort_names:=EFFORTS.map(func(value: String):return Comparison.display_effort(value))
	preview_effort=_filter(settings,"Preview Thinking Effort",effort_names,EFFORTS)
	preview_effort.tooltip_text="For comparison only. The effort used for real requests is set in OpenAI Settings."
	preview_mode=_filter(settings,"Preview mode",["Standard","Pro"],["standard","pro"])
	scenario=_filter(settings,"Workload",SCENARIOS.keys(),SCENARIOS.keys())
	pricing_tier=_filter(settings,"Rate card",["Standard","Batch","Flex","Fast","Ultrafast","Background 2h","Background 8h"],["standard","batch","flex","fast","ultrafast","background_2h","background_8h"])
	pricing_tier.tooltip_text="Rate preview only. LabVolt requests use Standard processing."
	sort_by=_filter(settings,"Sort by",SORTS,SORTS)
	for selector in [preview_effort,preview_mode,scenario,pricing_tier,sort_by]:
		selector.item_selected.connect(func(_index):_refresh_picker())
	var filters:=HFlowContainer.new()
	stack.add_child(filters)
	model_search=LineEdit.new()
	model_search.placeholder_text="Search model IDs"
	model_search.custom_minimum_size.x=200
	model_search.text_changed.connect(func(_value: String):_refresh_picker())
	filters.add_child(model_search)
	show_versions=_check_filter(filters,"Dated snapshots",false)
	show_advanced=_check_filter(filters,"Advanced alternatives",false)
	show_deprecated=_check_filter(filters,"Deprecated / retired",false)
	account_only=_check_filter(filters,"Account listed only",false)
	compare_measurements=_check_filter(filters,"Local evaluation",false)
	custom_input=_token_control(filters,"Input",1000)
	custom_output=_token_control(filters,"Output",300)
	assumptions=_label("",13,T.MUTED,stack,true)
	picker_scroll=ScrollContainer.new()
	picker_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	picker_scroll.vertical_scroll_mode=ScrollContainer.SCROLL_MODE_RESERVE
	picker_scroll.size_flags_vertical=SIZE_EXPAND_FILL
	stack.add_child(picker_scroll)
	model_rows=VBoxContainer.new()
	model_rows.size_flags_horizontal=SIZE_EXPAND_FILL
	model_rows.add_theme_constant_override("separation",6)
	picker_scroll.add_child(model_rows)
	var footer:=HFlowContainer.new()
	stack.add_child(footer)
	_link(footer,"OpenAI pricing",Pricing.PRICING_URL)
	_link(footer,"Account usage","https://platform.openai.com/usage")
	_link(footer,"View OpenAI billing","https://platform.openai.com/settings/organization/billing/overview")
	_label("Usage recorded by this LabVolt installation",13,T.MUTED,footer)
	evaluation_status=_label("",13,T.ACCENT,stack,true)
	evaluation_status.hide()

func _filter(parent: Control,title: String,labels: Array, values: Array) -> OptionButton:
	var column:=VBoxContainer.new()
	parent.add_child(column)
	_label(title,12,T.MUTED,column)
	var menu:=OptionButton.new()
	column.add_child(menu)
	for index in labels.size():
		menu.add_item(str(labels[index]))
		menu.set_item_metadata(index,values[index])
	return menu

func _check_filter(parent: Control,title: String,pressed: bool) -> CheckBox:
	var filter:=CheckBox.new()
	filter.text=title
	filter.button_pressed=pressed
	filter.toggled.connect(func(_value: bool):_refresh_picker())
	parent.add_child(filter)
	return filter

func _token_control(parent: Control,title: String,value: int) -> SpinBox:
	var spin:=SpinBox.new()
	spin.prefix=title
	spin.max_value=1000000
	spin.step=10
	spin.value=value
	spin.value_changed.connect(func(_value):_refresh_picker())
	parent.add_child(spin)
	return spin

func _link(parent: Control,title: String,url: String) -> void:
	var link:=LinkButton.new()
	link.text=title
	link.uri=url
	parent.add_child(link)

func _choose_model(id: String) -> void:
	if not Models.available_for(id,picker_purpose) or (account_models_known and id not in model_ids):return
	chosen[picker_purpose]=id
	picker.hide()
	_model_changed()

func _workload() -> Array:
	var mode:=str(scenario.get_selected_metadata())
	if mode=="Custom":return [int(custom_input.value),int(custom_output.value)]
	return SCENARIOS.get(mode,SCENARIOS["Teacher reply"])

func _preview_measurement(id: String) -> Dictionary:
	var mode:=str(preview_mode.get_selected_metadata())
	var level:=str(preview_effort.get_selected_metadata())
	if picker_purpose not in ["text","image"]:
		return {"status":"missing","label":"Not benchmarked"}
	var published:=Comparison.measurement(id,picker_purpose,level,mode)
	if compare_measurements.button_pressed and picker_purpose=="text" and published.get("status","")!="unsupported":
		var record:=evaluation.record(id,level,mode)
		if not record.is_empty():return record
		published={"status":"missing","label":"No local test at "+Comparison.display_effort(level)}
	elif published.has("score_percent"):
		return published
	var reference:=Comparison.published_reference(id,picker_purpose)
	if reference.is_empty():return published
	reference.preview_status=published.label
	return reference

func _sort_key(row: Dictionary, method: String) -> Variant:
	match method:
		"Benchmark":return -row.benchmark if row.benchmark>=0 else 1000.
		"Estimated cost":return row.cost if row.cost>=0 else INF
		"Input rate":return row.price.get("input",INF)
		"Output rate":return row.price.get("output",INF)
		"Latency":return row.get("latency",INF)
		"Local requests":return -int(row.usage.get("requests",0))
		"Newest snapshot":return -int(str(row.id.right(10)).replace("-","")) if row.id in Models.DOCUMENTED_SNAPSHOTS else 0
	return str(row.id)

func _refresh_picker() -> void:
	if not is_instance_valid(picker) or not picker.visible or picker_purpose.is_empty():return
	for child in model_rows.get_children():
		model_rows.remove_child(child)
		child.queue_free()
	picker_models.clear()
	var workload:=_workload()
	var read_preview:=str(preview_effort.get_selected_metadata())
	var mode:=str(preview_mode.get_selected_metadata())
	var tier:=str(pricing_tier.get_selected_metadata())
	var text_category:=picker_purpose in ["text","image"]
	custom_input.visible=text_category and str(scenario.get_selected_metadata())=="Custom"
	custom_output.visible=custom_input.visible
	assumptions.text="%d input · %d output tokens · no cache. Thinking-token usage varies by effort."%workload if text_category else "Published rates in USD. Image and speech costs depend on the measured token or audio usage."
	assumptions.text+=" Benchmark bars use a 0–100% scale. Other bars compare the visible models."
	var query:=model_search.text.strip_edges().to_lower()
	var known_ids:=model_ids.duplicate()
	for id: String in Models.catalog_ids(picker_purpose):
		if id not in known_ids:known_ids.append(id)
	var saved:=str(chosen.get(picker_purpose,""))
	if not saved.is_empty() and saved not in known_ids:known_ids.append(saved)
	var candidates:=known_ids.filter(func(id: String):return id==saved or Models.documented_for(id,picker_purpose))
	var rows: Array[Dictionary]=[]
	var scope: String=service.usage_scope(_read_draft())
	for id: String in candidates:
		var life:=Models.lifecycle(id)
		if id!=saved:
			if not query.is_empty() and query not in id.to_lower():continue
			if account_only.button_pressed and account_models_known and id not in model_ids:continue
			if life.status in ["deprecated","retired"] and not show_deprecated.button_pressed:continue
			if id in Models.DOCUMENTED_SNAPSHOTS and not show_versions.button_pressed:continue
			if query.is_empty() and not show_advanced.button_pressed and not Models.recommended(id,picker_purpose) and not (show_deprecated.button_pressed and life.status in ["deprecated","retired"]) and not (show_versions.button_pressed and id in Models.DOCUMENTED_SNAPSHOTS):continue
		var measured:=_preview_measurement(id)
		var rate:=Comparison.pricing(id,picker_purpose,tier,int(workload[0]))
		var cost:=Pricing.token_cost(rate,{"input":workload[0],"output":workload[1]})
		var usage: Dictionary=service.usage_tracker.summary(id,scope)
		var sample:=evaluation.record(id,read_preview,mode) if picker_purpose=="text" else {}
		var avg: float=sample.get("avg_ms",INF)
		if not is_finite(avg) and not text_category and int(usage.get("requests",0))>0:avg=float(usage.get("latency_ms",0))/float(usage.requests)
		if avg<0.:avg=INF
		var row:={"id":id,"life":life,"measurement":measured,"benchmark":float(measured.get("score_percent",-1.)),
			"price":rate,"cost":cost,"usage":usage,"latency":avg,"sample":sample}
		picker_models[id]=row
		rows.append(row)
	var sorting:=str(sort_by.get_selected_metadata())
	rows.sort_custom(func(a: Dictionary,b: Dictionary):
		var first: Variant=_sort_key(a,sorting)
		var second: Variant=_sort_key(b,sorting)
		return str(a.id)<str(b.id) if first==second else first<second)
	if rows.is_empty():
		_label("No matching models.",15,T.MUTED,model_rows)
		return
	if not detail_id.is_empty() and picker_models.has(detail_id):_build_detail(picker_models[detail_id])
	var maxima: Dictionary={}
	for row in rows:
		_record_maximum(maxima,"latency",row.latency)
		_record_maximum(maxima,"cost",row.cost)
		_record_maximum(maxima,"requests",float(row.usage.get("requests",-1)))
		for rate in _rate_metrics(row.price):
			_record_maximum(maxima,rate.key,rate.amount)
	for row in rows:_build_model_row(row,maxima)

func _record_maximum(maxima: Dictionary,key: String,value: float) -> void:
	if is_finite(value) and value>=0.:
		maxima[key]=maxf(maxima.get(key,0.),value)

func _rate_metrics(price: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary]=[]
	for item in [["input","Input"],["output","Output"],["text_input","Text in"],["image_output","Image out"],["audio_input","Audio in"],["audio_output","Audio out"]]:
		if not price.has(item[0]):continue
		var amount:=float(price[item[0]])
		result.append({"key":item[0],"amount":amount,"label":"%s $%s"%[item[1],Pricing.money_rate(amount)]})
	if price.has("rate"):
		result.append({"key":price.unit,"amount":float(price.rate),"label":str(price.label)})
	return result

func _metric_cell(parent: Control,title: String, ratio: float) -> VBoxContainer:
	var cell:=VBoxContainer.new()
	cell.add_theme_constant_override("separation",5)
	cell.size_flags_horizontal=SIZE_EXPAND_FILL
	cell.size_flags_stretch_ratio=ratio
	parent.add_child(cell)
	_label(title,11,T.MUTED,cell,true)
	return cell

func _meter(cell: Control, label: String, value: float, maximum: float, accent: Color, scale: String) -> void:
	var available:=is_finite(value) and value>=0.
	var meter:=VBoxContainer.new()
	meter.add_theme_constant_override("separation",3)
	cell.add_child(meter)
	var number:=_label(label,13,T.INK if available else T.MUTED,meter,true)
	number.mouse_filter=MOUSE_FILTER_PASS
	number.tooltip_text=scale
	var bar:=ProgressBar.new()
	bar.custom_minimum_size.y=7
	bar.show_percentage=false
	bar.max_value=maximum if maximum>0. else 1.
	bar.step=0.
	bar.value=value if available else 0.
	bar.mouse_filter=MOUSE_FILTER_PASS
	bar.tooltip_text=scale
	var track:=T.surface(Color("0a1d28"),Color("345365") if available else Color("263f4d"),0)
	track.set_corner_radius_all(4)
	var fill:=T.surface(accent,accent,0)
	fill.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("background",track)
	bar.add_theme_stylebox_override("fill",fill)
	meter.add_child(bar)

func _build_model_row(row: Dictionary,maxima: Dictionary) -> void:
	var surface:=PanelContainer.new()
	surface.add_theme_stylebox_override("panel",T.surface(Color("173341"),Color("355363"),8))
	model_rows.add_child(surface)
	var split:=VBoxContainer.new()
	split.add_theme_constant_override("separation",9)
	surface.add_child(split)
	var header:=HBoxContainer.new()
	split.add_child(header)
	var name:=_button(header,Models.display_name(row.id),"check" if row.id==chosen.get(picker_purpose) else "",func():detail_id=row.id;_refresh_picker();picker_scroll.set_deferred("scroll_vertical",0))
	name.alignment=HORIZONTAL_ALIGNMENT_LEFT
	name.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	name.tooltip_text=row.id
	name.size_flags_horizontal=SIZE_EXPAND_FILL
	var life: Dictionary=row.life
	var tag: String={"retired":"Retired","deprecated":"Deprecated · "+str(life.get("shutdown","")),"active":"Active","unknown":"Compatibility unknown"}[life.status]
	if not Models.supports(row.id,picker_purpose):tag+=" · Adapter not implemented"
	elif account_models_known and row.id not in model_ids:tag+=" · Not listed for account"
	_label(tag,12,T.MUTED,header)
	_label(row.id,12,T.MUTED,split,true)
	if life.status=="deprecated":_label("Replacement: "+str(life.get("replacement","")),12,T.ACCENT,split,true)
	var apply:=_button(header,"Select","",_choose_model.bind(row.id))
	apply.disabled=not Models.available_for(row.id,picker_purpose) or (account_models_known and row.id not in model_ids)
	var stats:=HBoxContainer.new()
	stats.add_theme_constant_override("separation",9)
	split.add_child(stats)
	var record: Dictionary=row.measurement
	var benchmark:=_metric_cell(stats,record.get("benchmark",Comparison.benchmark_name(picker_purpose)),1.40)
	_meter(benchmark,"%.1f%%"%row.benchmark if row.benchmark>=0. else str(record.get("label","Not benchmarked")),
		row.benchmark,100.,METRIC_SCORE,str(record.get("preview_status","Benchmark score out of 100%")))
	if row.benchmark>=0.:
		var tested_effort:=str(record.reasoning_effort)
		var effort_label:=Comparison.display_effort(tested_effort) if not tested_effort.is_empty() else "Effort unspecified"
		_label(("Reference · " if record.get("reference",false) else "")+effort_label,11,T.MUTED,benchmark,true)
	var latency:=_metric_cell(stats,"Measured latency",.95)
	_meter(latency,"%.2f s"%(row.latency/1000.) if is_finite(row.latency) else "Unavailable",
		row.latency,maxima.get("latency",0.),METRIC_TIME,"Time relative to the slowest visible measurement")
	var rate_title:="Published rate"
	if row.price.get("basis") in ["tokens","image_tokens","audio_tokens","embedding_tokens"]:rate_title+=" / 1M tokens"
	var published:=_metric_cell(stats,rate_title,1.35)
	var rates:=_rate_metrics(row.price)
	if rates.is_empty():_meter(published,"Rate unavailable",-1.,0.,METRIC_PRICE,"No rate in this rate card")
	for rate in rates:
		_meter(published,rate.label,rate.amount,maxima.get(rate.key,0.),METRIC_PRICE,"Relative to the highest visible rate for this unit")
	var estimate:=_metric_cell(stats,"Estimate / request",1.0)
	_meter(estimate,Pricing.usd(row.cost) if row.cost>=0 else "Unavailable",row.cost,maxima.get("cost",0.),
		METRIC_PRICE,"Cost relative to the highest visible estimate for this workload")
	var requests:=_metric_cell(stats,"Local requests",.8)
	_meter(requests,str(row.usage.get("requests","—")),float(row.usage.get("requests",-1)),maxima.get("requests",0.),
		METRIC_REQUESTS,"Requests recorded for this connection profile relative to the highest visible count")

func _build_detail(row: Dictionary) -> void:
	var surface:=PanelContainer.new()
	surface.add_theme_stylebox_override("panel",T.surface(Color("1b3d4b"),T.BORDER,10))
	model_rows.add_child(surface)
	var body:=VBoxContainer.new()
	surface.add_child(body)
	var header:=HBoxContainer.new();body.add_child(header)
	var name:=_label(row.id,21,T.INK,header,true);name.size_flags_horizontal=SIZE_EXPAND_FILL
	_button(header,"Hide details","close",func():detail_id="";_refresh_picker())
	var metadata:=Models.metadata(row.id,picker_purpose)
	if not bool(metadata.implemented):_label("Documented by OpenAI, but this workflow has no implemented game adapter. Selection is disabled.",14,T.ACCENT,body,true)
	var settings:=PackedStringArray()
	for level in metadata.efforts:settings.append(Comparison.display_effort(level))
	var endpoint: String=metadata.get("endpoint","")
	var options_text: String=" · ".join(settings) if not settings.is_empty() else "Not applicable" if not endpoint.is_empty() else "Unknown"
	_label("Endpoint %s   ·   Efforts %s   ·   Default %s"%[endpoint if not endpoint.is_empty() else "Unknown",options_text,Comparison.display_effort(metadata.default_effort) if not metadata.default_effort.is_empty() else "Unspecified"],13,T.MUTED,body,true)
	if int(metadata.context)>0:_label("%d context tokens · %d max output tokens"%[metadata.context,metadata.output],13,T.MUTED,body,true)
	if row.life.has("replacement"):_label("Published replacement · "+str(row.life.replacement),13,T.ACCENT,body,true)
	if picker_purpose in ["tts","stt"]:
		var capabilities:=Models.voice_capabilities(row.id)
		var labels: Array[String]=[]
		if capabilities.expressive:labels.append("Expressive delivery")
		if capabilities.prompt_voices:labels.append("Prompt-generated voices")
		if capabilities.recording_voices:labels.append("Consented recording voices")
		if capabilities.streaming:labels.append("Streaming transport")
		if capabilities.full_duplex:labels.append("Full duplex")
		if capabilities.transcription:labels.append("Transcription")
		_label(" · ".join(labels)+" · verified "+str(capabilities.verified_at),13,T.ACCENT,body,true)
		_label(Models.lifecycle_description(row.id),13,T.MUTED,body,true)
		if capabilities.endpoint=="/realtime":_label("Uses the Realtime API. This model is not sent to the legacy speech endpoint. Prompt-generated custom voices require GPT-Live.",13,T.MUTED,body,true)
	var rate: Dictionary=row.price
	if not rate.is_empty():
		var cost_lines:=PackedStringArray()
		for key in ["cached","write_30m","write_12h","text_input","text_cached","text_output","image_input","image_cached","image_output","audio_input","audio_cached","audio_output","standby_rate"]:
			if rate.has(key) and float(rate[key])>=0.:cost_lines.append("%s $%s"%[key.replace("_"," ").capitalize(),Pricing.money_rate(rate[key])])
		if not cost_lines.is_empty():_label(" · ".join(cost_lines)+" · "+str(rate.unit),13,T.MUTED,body,true)
		if rate.has("promotional_until"):_label("Promotional rate through "+str(rate.promotional_until),13,T.MUTED,body)
		var links:=HFlowContainer.new();body.add_child(links)
		_link(links,"Published rate · "+str(rate.verified_at),str(rate.source_url))
		if rate.has("estimator"):_link(links,"Image cost calculator",str(rate.estimator))
	if row.cost>=0:_label("Estimated %s per request · %s per 100 requests"%[Pricing.usd(row.cost),Pricing.usd(row.cost*100)],14,T.INK,body)
	var workload_sample: Dictionary=row.sample
	if not workload_sample.is_empty() and workload_sample.usage.has("input") and workload_sample.usage.has("output"):
		var count: int=workload_sample.questions
		var typical: Dictionary={}
		for key in ["input","output","cached"]:
			typical[key]=roundi(float(workload_sample.usage.get(key,0))/count)
		var measured_rate:=Pricing.pricing(row.id,picker_purpose,str(pricing_tier.get_selected_metadata()),typical.input)
		var measured_cost:=Pricing.token_cost(measured_rate,typical)
		if measured_cost>=0:
			_label("Measured workload estimate · %s per request · %d input / %d output tokens on average"%[Pricing.usd(measured_cost),typical.input,typical.output],13,T.ACCENT,body,true)
	_link(body,"Model documentation",str(metadata.source_url))
	var usage: Dictionary=row.usage
	if not usage.is_empty():
		var recorded: Array=[]
		for key in ["input","cached","output","reasoning","text_input","text_output","audio_input","audio_output","audio_cached","image_input","image_output","seconds","characters"]:
			if usage.has(key):recorded.append("%s %s"%[str(usage[key]),key])
		_label("%d succeeded · %d failed · %s · %s estimated from %d priced requests"%[usage.get("success",0),int(usage.get("requests",0))-int(usage.get("success",0))," · ".join(recorded),Pricing.usd(int(usage.get("estimate_nano",-1))),usage.get("priced",0)],13,T.MUTED,body,true)
	elif service.model_usage.has(row.id):
		_label("Historical installation totals are saved separately from this connection profile.",13,T.MUTED,body,true)
	var record: Dictionary=row.measurement
	if record.get("source_type","")=="published":
		if record.get("reference",false):_label(str(record.preview_status)+" · Showing a published reference score",13,T.MUTED,body,true)
		_label(str(record.methodology)+" · Verified "+str(record.verified_at),13,T.MUTED,body,true)
		_link(body,"Published benchmark source",str(record.source_url))
	elif record.get("source_type","")=="local":
		_label("%d / %d correct · 95%% interval %.1f–%.1f%% · %s · %s"%[record.correct,record.questions,record.interval[0],record.interval[1],record.timestamp,Pricing.usd(record.cost)],13,T.MUTED,body,true)
		_label("Local test totals "+str(record.usage),13,T.MUTED,body,true)
	if picker_purpose in ["text","image"]:
		var pinned_button:=_button(body,"Unpin from chart" if row.id in pinned else "Pin to effort chart","",func():
			if row.id in pinned:pinned.erase(row.id)
			elif pinned.size()<3:pinned.append(row.id)
			_refresh_picker())
		pinned_button.tooltip_text="Show up to three pinned models alongside the selected model."
		var plot:=preload("res://scripts/campus/ui/openai_effort_chart.gd").new()
		body.add_child(plot)
		var points: Array=[]
		var ids: Array=[row.id]
		for id in pinned:
			if id not in ids:ids.append(id)
		var mode:=str(preview_mode.get_selected_metadata())
		var measured:=compare_measurements.button_pressed and picker_purpose=="text"
		for id in ids:
			if measured:
				for effort_value in EFFORTS:
					if effort_value.is_empty():continue
					var sample:=evaluation.record(id,effort_value,mode)
					if not sample.is_empty():points.append(sample)
			elif mode=="standard":
				for point in Comparison.benchmark_records(id,picker_purpose):
					if not str(point.reasoning_effort).is_empty():points.append(point)
		_label(("Local evaluation" if measured else Comparison.benchmark_name(picker_purpose))+" by thinking effort · "+", ".join(ids),14,T.ACCENT,body,true)
		plot.configure(points,str(preview_effort.get_selected_metadata()),"Performance by thinking effort")
	if picker_purpose=="text" and Models.available_for(row.id,"text"):
		var button:=_button(body,"Run Comparison Test…","play",_confirm_evaluation.bind(row.id))
		button.disabled=evaluation.running or evaluation.estimate(row.id)<0 or row.measurement.get("status","")=="unsupported"
	if evaluation.running:_button(body,"Pause after current request","",func():evaluation.canceled=true)

func _confirm_evaluation(id: String) -> void:
	if evaluation.running or service.busy:return
	var level:=str(preview_effort.get_selected_metadata())
	var mode:=str(preview_mode.get_selected_metadata())
	var signature:=evaluation.key(id,level,mode)
	var from:=int(evaluation.progress.get(signature,{}).get("next",0))
	var ceiling:=evaluation.estimate(id,from)
	if ceiling<0:return
	var dialog:=ConfirmationDialog.new()
	dialog.title="Run Comparison Test"
	add_child(dialog)
	var body:=VBoxContainer.new();body.custom_minimum_size.x=380;dialog.add_child(body)
	_label("%s · %s · %s · %d questions remaining"%[id,Comparison.display_effort(level),mode.capitalize(),Evaluation.QUESTIONS.size()-from],15,T.INK,body,true)
	_label("Estimated ceiling %s. Each question allows up to %d output tokens, including thinking. Pausing leaves the current request running."%[Pricing.usd(ceiling),Evaluation.OUTPUT_LIMIT],13,T.MUTED,body,true)
	var budget:=SpinBox.new()
	budget.prefix="Budget $";budget.min_value=.01;budget.max_value=5.;budget.step=.01;budget.value=.25
	body.add_child(budget)
	dialog.ok_button_text="Approve API requests"
	dialog.confirmed.connect(func():
		var approved:=roundi(budget.value*1000000000.)
		dialog.queue_free()
		evaluation_status.show()
		evaluation.run(service,id,level,mode,approved,_read_draft(),func(message: String):
			if not is_inside_tree():return
			evaluation_status.text=message
			_refresh_picker()))
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered()

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

func _exit_tree() -> void:
	evaluation.canceled=true
