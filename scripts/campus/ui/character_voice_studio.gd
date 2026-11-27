extends VBoxContainer
## Host-only voice auditions. Generating and hearing a candidate never changes
## gameplay identity. The host approves the speaker AND a compatible model.
const T=preload("res://scripts/ui/design_system/tokens.gd")
const Voices=preload("res://scripts/campus/academics/teacher_voice_profiles.gd")
const People=preload("res://scripts/campus/academics/class_character_profile.gd")
const Delivery=preload("res://scripts/campus/academics/character_voice_delivery.gd")
const Roster=preload("res://scripts/campus/academics/faculty_roster.gd")
const Models=preload("res://scripts/campus/ai/openai_models.gd")
const Toon=preload("res://scripts/toon_character.gd")
const EMOTIONS:=["normal","happy","excited","amused","irritated","angry","extremely angry","sad","tired","disappointed","dismissive","embarrassed","bored","confused"]
var service: Node
var draft: Dictionary={}
var people: Dictionary={}
var selected_id:="mr_bro"
var character_list: ItemList
var search: LineEdit
var name_label: Label
var identity_label: Label
var lifecycle_label: Label
var capacity_label: Label
var audition_label: Label
var status: Label
var design: TextEdit
var sentence: TextEdit
var voice_model: OptionButton
var emotion: OptionButton
var use_candidate: CheckButton
var fit: CheckBox
var preview_button: Button
var generate_button: Button
var approve_button: Button
var discard_button: Button
var stop_button: Button
var external_count: SpinBox
var portrait_world: Node3D
var portrait_model: Node3D
var audio: AudioStreamPlayer
var busy:=false
var preview_ticket:=0
var playing: Dictionary={}
var _refreshing:=false

func configure(client: Node,settings: Dictionary={}) -> void:
	service=client;draft=settings.duplicate(true)
	add_theme_constant_override("separation",12)
	if not service.host_allowed():_label(self,"Only the host can configure character voices.",16,T.ERROR);return
	_label(self,"Character Voices",24,T.INK)
	_label(self,"Original AI-generated adult voices. Preview the same sentence across moods, then approve a voice and its compatible model. Every preview and voice creation uses the host's API account.",14,T.MUTED)
	for id: String in Roster.all_people():people[id]=People.teacher(id)
	# The active host roster may provide persisted students. No private player
	# profile or microphone data is shown in this developer-facing interface.
	var game:=service.get_parent()
	if is_instance_valid(game) and game.get("lecture_classes")!=null:
		var students: Variant=game.lecture_classes.get("classroom_students")
		if students!=null and students.get("population")!=null:
			var population: Variant=students.population.get("people")
			if population is Dictionary:
				for id: String in population:
					if population[id] is Dictionary:people[id]=population[id]
	var split:=HBoxContainer.new();split.add_theme_constant_override("separation",16);add_child(split)
	var left:=VBoxContainer.new();left.custom_minimum_size=Vector2(190,520);split.add_child(left)
	search=LineEdit.new();search.placeholder_text="Find a character";left.add_child(search)
	search.text_changed.connect(func(_value: String):_fill_list())
	character_list=ItemList.new();character_list.size_flags_vertical=Control.SIZE_EXPAND_FILL;character_list.custom_minimum_size.y=300;left.add_child(character_list)
	character_list.item_selected.connect(func(index: int):_select(str(character_list.get_item_metadata(index))))
	var scroll:=ScrollContainer.new();scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;scroll.size_flags_horizontal=Control.SIZE_EXPAND_FILL;scroll.custom_minimum_size=Vector2(380,520);split.add_child(scroll)
	var details:=VBoxContainer.new();details.size_flags_horizontal=Control.SIZE_EXPAND_FILL;details.add_theme_constant_override("separation",12);scroll.add_child(details)
	var header:=HBoxContainer.new();header.add_theme_constant_override("separation",14);details.add_child(header)
	_build_portrait(header)
	var identity_box:=VBoxContainer.new();identity_box.size_flags_horizontal=Control.SIZE_EXPAND_FILL;header.add_child(identity_box)
	name_label=_label(identity_box,"",21,T.INK)
	identity_label=_label(identity_box,"",14,T.MUTED)
	_label(details,"Voice design",16,T.ACCENT)
	design=TextEdit.new();design.custom_minimum_size.y=118;design.wrap_mode=TextEdit.LINE_WRAPPING_BOUNDARY;details.add_child(design)
	design.tooltip_text="The original stable voice design. Current emotions are controlled separately below. Editing this text only affects the next generated candidate."
	var model_row:=HBoxContainer.new();details.add_child(model_row);_label(model_row,"Audition model",15,T.INK)
	voice_model=OptionButton.new();voice_model.size_flags_horizontal=Control.SIZE_EXPAND_FILL;model_row.add_child(voice_model)
	var choices: Array[String]=["gpt-live-1.1","gpt-realtime-2.1-mini","gpt-realtime-2.1","gpt-4o-mini-tts"]
	var configured:=str(draft.get("modalities",{}).get("tts",service.tts_model))
	if not configured.is_empty() and configured not in choices:choices.append(configured)
	for model: String in choices:voice_model.add_item(model);voice_model.set_item_metadata(voice_model.item_count-1,model)
	voice_model.item_selected.connect(func(_index: int):_refresh())
	lifecycle_label=_label(details,"",13,T.MUTED)
	use_candidate=CheckButton.new();use_candidate.text="Audition pending custom candidate";details.add_child(use_candidate)
	use_candidate.toggled.connect(func(_value: bool):fit.button_pressed=false;_refresh())
	var emotional_row:=HBoxContainer.new();details.add_child(emotional_row);_label(emotional_row,"Delivery",15,T.INK)
	emotion=OptionButton.new();emotion.size_flags_horizontal=Control.SIZE_EXPAND_FILL;emotional_row.add_child(emotion)
	for mood: String in EMOTIONS:emotion.add_item(mood.capitalize());emotion.set_item_metadata(emotion.item_count-1,mood)
	sentence=TextEdit.new();sentence.text="I thought we had this figured out. Let's take another look at what happened.";sentence.custom_minimum_size.y=82;sentence.wrap_mode=TextEdit.LINE_WRAPPING_BOUNDARY;details.add_child(sentence)
	var audition_actions:=HBoxContainer.new();details.add_child(audition_actions)
	preview_button=_button(audition_actions,"Play audition",_preview)
	stop_button=_button(audition_actions,"Stop",_stop)
	audition_label=_label(details,"",13,T.MUTED)
	fit=CheckBox.new();fit.text="I listened and this voice fits the character";details.add_child(fit)
	fit.toggled.connect(func(_value: bool):_refresh())
	var approval_actions:=HBoxContainer.new();details.add_child(approval_actions)
	approve_button=_button(approval_actions,"Approve voice and model",_approve)
	discard_button=_button(approval_actions,"Discard candidate",_discard)
	_label(details,"Custom voice allocation",16,T.ACCENT)
	capacity_label=_label(details,"",13,T.MUTED)
	var capacity_row:=HBoxContainer.new();details.add_child(capacity_row);_label(capacity_row,"Voices created elsewhere",14,T.INK)
	external_count=SpinBox.new();external_count.min_value=0;external_count.max_value=100;external_count.step=1;external_count.custom_minimum_size.x=100;capacity_row.add_child(external_count)
	external_count.value_changed.connect(func(value: float):
		if not _refreshing:
			var error:=Voices.set_external_voice_count(int(value))
			if error!=OK:status.text="Could not save voice capacity: "+error_string(error)
			_refresh())
	generate_button=_button(details,"Generate original voice candidate",_generate)
	status=_label(details,"",14,T.ACCENT)
	audio=AudioStreamPlayer.new();add_child(audio);audio.finished.connect(_heard)
	_fill_list();_select(selected_id)

func _fill_list() -> void:
	character_list.clear()
	var ids:=people.keys()
	ids.sort_custom(func(a: String,b: String):return str(people[a].name).naturalnocasecmp_to(str(people[b].name))<0)
	var query:=search.text.strip_edges().to_lower()
	for id: String in ids:
		var person: Dictionary=people[id]
		if not query.is_empty() and not str(person.name).to_lower().contains(query) and not id.contains(query):continue
		character_list.add_item(str(person.name))
		var index:=character_list.item_count-1;character_list.set_item_metadata(index,id)
		if id==selected_id:character_list.select(index)

func _select(id: String) -> void:
	if not people.has(id):return
	_stop();selected_id=id;fit.button_pressed=false
	var identity:=Voices.identity(people[id])
	if identity.is_empty():status.text="The saved voice could not be read. No replacement voice was selected.";return
	design.text=str(identity.design_description)
	name_label.text=str(people[id].name)
	use_candidate.set_pressed_no_signal(not Voices.candidate(id).is_empty())
	var model:=str(identity.get("preferred_model",draft.get("modalities",{}).get("tts",service.tts_model)))
	if use_candidate.button_pressed:model="gpt-live-1.1"
	for index in voice_model.item_count:
		if str(voice_model.get_item_metadata(index))==model:voice_model.select(index);break
	if is_instance_valid(portrait_model):portrait_model.queue_free()
	var appearance: Dictionary=Roster.config(id) if Roster.has(id) else people[id].get("appearance",Toon.defaults())
	portrait_model=Toon.build(appearance);portrait_world.add_child(portrait_model)
	_refresh()

func _voice() -> Dictionary:
	return Voices.candidate(selected_id) if use_candidate.button_pressed and not Voices.candidate(selected_id).is_empty() else Voices.identity(people.get(selected_id,{}))

func _model() -> String:
	return str(voice_model.get_selected_metadata())

func _refresh() -> void:
	if not is_instance_valid(status) or not people.has(selected_id):return
	_refreshing=true
	var profile:=_voice()
	if profile.is_empty():_refreshing=false;return
	var pending:=Voices.candidate(selected_id)
	var active:=Voices.identity(people[selected_id])
	var candidate_active:=use_candidate.button_pressed and not pending.is_empty()
	identity_label.text="%s · perceived age %s\n%s\n%s · %s\nVoice: %s\n%s"%[str(profile.vocal_presentation).capitalize(),str(profile.perceived_age),str(profile.pitch_range),str(profile.timbre),str(profile.accent),str(profile.permanent_voice_id),str(profile.approval_status).replace("_"," ").capitalize()]
	if not str(active.get("preferred_model","")).is_empty():identity_label.text+="\nGameplay model pinned to "+str(active.preferred_model)
	if candidate_active:identity_label.text+="\nGameplay keeps the existing voice until approval."
	use_candidate.visible=not pending.is_empty()
	discard_button.visible=not pending.is_empty()
	var resolved:=Voices.resolve(people[selected_id],_model(),profile)
	var lifecycle: Dictionary=service.model_status(_model(),"tts") if service.has_method("model_status") else Models.lifecycle(_model())
	var text:=str(lifecycle.get("status","unknown")).capitalize()
	if not str(lifecycle.get("shutdown","")).is_empty():text+=" · shutdown "+str(lifecycle.shutdown)
	if not str(lifecycle.get("shutdown_date","")).is_empty():text+=" · shutdown "+str(lifecycle.shutdown_date)
	if not str(lifecycle.get("replacement","")).is_empty():text+=" · migration "+str(lifecycle.replacement)
	var availability:=str(lifecycle.get("account_availability","unknown"))
	lifecycle_label.text=text+" · account availability: "+availability+"\n"+("Voice-compatible. Emotional performance is requested from the selected model." if bool(resolved.ok) else str(resolved.error))
	lifecycle_label.add_theme_color_override("font_color",T.MUTED if bool(resolved.ok) and lifecycle.get("status")=="active" else T.ERROR)
	var heard: Dictionary=profile.get("auditions",{})
	var completed: Array[String]=[]
	for mood: String in Voices.AUDITION_MOODS:
		if heard.has(mood):completed.append(mood)
	audition_label.text="Core auditions played: %d/3 — normal, sad and angry. Approval also requires your listening judgment."%completed.size()
	preview_button.disabled=busy or not bool(resolved.ok) or availability=="unavailable"
	stop_button.disabled=not audio.playing
	approve_button.disabled=busy or not bool(resolved.ok) or availability=="unavailable" or completed.size()!=3 or not fit.button_pressed
	discard_button.disabled=busy
	var capacity:=Voices.capacity(people[selected_id])
	capacity_label.text="%d known + %d elsewhere · %d of %d slots remain. %d slots are reserved for faculty.\n%s"%[capacity.get("known",0),capacity.get("external",0),capacity.get("remaining",0),capacity.get("limit",100),capacity.get("faculty_reserved",0),str(capacity.get("note",""))]
	external_count.value=int(capacity.get("external",0))
	generate_button.disabled=busy or not pending.is_empty() or not bool(capacity.get("available",false))
	_refreshing=false

func _preview() -> void:
	if busy:return
	var text:=sentence.text.strip_edges()
	if text.is_empty() or text.length()>1200:status.text="Use an audition sentence between 1 and 1,200 characters.";return
	var profile:=_voice()
	var mood:=str(emotion.get_selected_metadata())
	var spoken_mood:="steady" if mood=="normal" else mood
	var delivery:=Delivery.build(people[selected_id],_model(),2,spoken_mood,{},"converse",{"voice_override":profile})
	if not bool(delivery.get("ok",false)):status.text=str(delivery.get("error","This voice is unavailable."));return
	_stop();preview_ticket+=1
	var ticket:=preview_ticket
	var request_id:=selected_id
	busy=true;status.text="Creating your audition. API usage is recorded in OpenAI settings.";_refresh()
	var preview_draft:=draft.duplicate(true)
	if not preview_draft.get("modalities") is Dictionary:preview_draft.modalities={}
	preview_draft.modalities.tts=_model()
	var result: Dictionary=await service.speak(text,preview_draft,delivery.voice,delivery)
	if not is_inside_tree():return
	busy=false
	if ticket!=preview_ticket or request_id!=selected_id:_refresh();return
	if not bool(result.get("ok",false)) or not result.get("stream") is AudioStream:
		status.text=str(result.get("error","The voice preview could not be played."));_refresh();return
	playing={"character_id":selected_id,"voice_id":str(profile.permanent_voice_id),"mood":mood}
	audio.stream=result.stream;audio.play()
	status.text="Listen for identity, audibility and emotional delivery. Generation alone does not establish voice quality."
	_refresh()

func _heard() -> void:
	if playing.is_empty():return
	var error:=Voices.record_audition(str(playing.character_id),str(playing.voice_id),str(playing.mood))
	playing.clear()
	status.text="Preview played. Judge whether this sounds like the character before approving." if error==OK else "The audition played, but its record could not be saved."
	_refresh()

func _stop() -> void:
	preview_ticket+=1;playing.clear()
	if is_instance_valid(audio):audio.stop();audio.stream=null
	if is_instance_valid(stop_button):stop_button.disabled=true

func _generate() -> void:
	if busy:return
	_stop();busy=true;fit.button_pressed=false;status.text="Creating one original voice candidate. This does not replace the current voice.";_refresh()
	var id:=selected_id
	var result:=await Voices.generate_candidate(service,people[id],design.text,sentence.text,draft)
	if not is_inside_tree():return
	busy=false
	if not bool(result.get("ok",false)):status.text=str(result.get("error","Voice creation failed."));_refresh();return
	if id==selected_id:
		use_candidate.set_pressed_no_signal(true)
		for index in voice_model.item_count:
			if str(voice_model.get_item_metadata(index))=="gpt-live-1.1":voice_model.select(index)
	status.text="Candidate saved. Play normal, sad and angry auditions, then approve only if the voice fits."
	_refresh()

func _approve() -> void:
	var profile:=_voice()
	var error:=Voices.approve(selected_id,str(profile.permanent_voice_id),fit.button_pressed,_model())
	if error!=OK:status.text="Voice approval could not be saved: "+error_string(error);return
	use_candidate.set_pressed_no_signal(false)
	status.text="Approved. This character now keeps this voice and compatible model across sessions."
	_refresh()

func _discard() -> void:
	_stop()
	var error:=Voices.discard_candidate(selected_id)
	use_candidate.set_pressed_no_signal(false);fit.button_pressed=false
	status.text="Candidate removed from this audition. Its provider voice is retained and still counts toward known allocation." if error==OK else "Could not discard the local candidate: "+error_string(error)
	_refresh()

func _build_portrait(parent: Control) -> void:
	var container:=SubViewportContainer.new();container.custom_minimum_size=Vector2(138,170);container.stretch=true;parent.add_child(container)
	var viewport:=SubViewport.new();viewport.size=Vector2i(138,170);viewport.own_world_3d=true;viewport.render_target_update_mode=SubViewport.UPDATE_WHEN_VISIBLE;container.add_child(viewport)
	portrait_world=Node3D.new();viewport.add_child(portrait_world)
	var environment:=WorldEnvironment.new();var settings:=Environment.new();settings.background_mode=Environment.BG_COLOR;settings.background_color=T.SURFACE;settings.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;settings.ambient_light_color=Color(.75,.87,.95);settings.ambient_light_energy=.75;environment.environment=settings;portrait_world.add_child(environment)
	var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-30,-35,0);light.light_energy=1.3;portrait_world.add_child(light)
	var camera:=Camera3D.new();camera.position=Vector3(0,1.35,3.25);portrait_world.add_child(camera);camera.look_at(Vector3(0,1.1,0));camera.current=true

func _label(parent: Node,text: String,size: int,color: Color) -> Label:
	var label:=Label.new();label.text=text;label.add_theme_font_size_override("font_size",size);label.add_theme_color_override("font_color",color);label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;label.size_flags_horizontal=Control.SIZE_EXPAND_FILL;parent.add_child(label);return label

func _button(parent: Node,text: String,callback: Callable) -> Button:
	var button:=Button.new();button.text=text;button.custom_minimum_size.y=40;button.pressed.connect(callback);parent.add_child(button);return button

func _exit_tree() -> void:
	_stop()
