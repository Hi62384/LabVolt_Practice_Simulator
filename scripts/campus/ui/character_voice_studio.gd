extends VBoxContainer
## Host-only voice auditions. Generating and hearing a candidate never changes
## gameplay identity. The host approves the speaker AND a compatible model.
const T=preload("res://scripts/ui/design_system/tokens.gd")
const Voices=preload("res://scripts/campus/academics/teacher_voice_profiles.gd")
const People=preload("res://scripts/campus/academics/class_character_profile.gd")
const Delivery=preload("res://scripts/campus/academics/character_voice_delivery.gd")
const VoiceMixer=preload("res://scripts/campus/voice/audio_voice_mixer.gd")
const Roster=preload("res://scripts/campus/academics/faculty_roster.gd")
const Models=preload("res://scripts/campus/ai/openai_models.gd")
const Toon=preload("res://scripts/toon_character.gd")
const Dossiers=preload("res://scripts/campus/academics/character_dossier_store.gd")
const BASE_AUDITION_MODELS:=["gpt-realtime-2.1-mini","gpt-live-1.1","gpt-realtime-2.1","gpt-audio-1.5","gpt-4o-mini-tts","tts-1","tts-1-hd","gpt-live-1"]
const EMOTIONS:=["normal","happy","excited","amused","irritated","angry","extremely angry","sad","tired","disappointed","dismissive","embarrassed","bored","confused"]
var service: Node
var draft: Dictionary={}
var people: Dictionary={}
var population_source: RefCounted
var student_index: Dictionary={}
var selected_student:=""
var profile_unavailable:=false
var selected_id:="mr_bro"
var character_list: ItemList
var search: LineEdit
var roster_filter: OptionButton
var advanced_toggle: CheckButton
var advanced_box: VBoxContainer
var detail_scroll: ScrollContainer
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
var preset_voice: OptionButton
var preset_button: Button
var regenerate_preset_button: Button
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
var studio_owner:=""
var studio_account:=""
var next_candidate_button: Button
var recover_toggle: CheckButton
var preview_request_id:=""
var core_queue: Array[String]=[]
var batch_active:=false
var batch_stop:=false
var batch_button: Button
var batch_stop_button: Button
var core_button: Button
var overview: Label
var recovery_note: Label
var recover_id: LineEdit
var recover_type: OptionButton
var recover_fit: CheckBox
var recover_button: Button
var clear_pending_button: Button
var recovery_box: VBoxContainer
var legacy_box: VBoxContainer
var legacy_adopt: Button
var legacy_separate: Button

func configure(client: Node,settings: Dictionary={}) -> void:
	service=client;draft=settings.duplicate(true);studio_owner=Dossiers.host_identity
	if is_instance_valid(service) and service.has_method("_account_cache_id"):studio_account=service._account_cache_id(str(draft.get("key","")))
	add_theme_constant_override("separation",12)
	_label(self,"Character Voices",24,T.INK)
	_label(self,"A permanent voice for every character. Browse locally, design a candidate, listen in different moods, then approve. Auditions use paid speech requests; opening this menu makes none.",14,T.MUTED)
	_load_people()
	var split:=HBoxContainer.new();split.size_flags_vertical=Control.SIZE_EXPAND_FILL;split.add_theme_constant_override("separation",16);add_child(split)
	var left_panel:=PanelContainer.new();left_panel.custom_minimum_size=Vector2(230,260);left_panel.add_theme_stylebox_override("panel",T.surface(T.SURFACE,T.BORDER,12));split.add_child(left_panel)
	var left:=VBoxContainer.new();left.add_theme_constant_override("separation",10);left_panel.add_child(left)
	search=LineEdit.new();search.placeholder_text="Find name or program";search.custom_minimum_size.y=40;left.add_child(search)
	roster_filter=OptionButton.new();roster_filter.add_item("Everyone");roster_filter.add_item("Faculty");roster_filter.add_item("Students");left.add_child(roster_filter)
	roster_filter.item_selected.connect(func(_index: int):_fill_list())
	search.text_changed.connect(func(_value: String):_fill_list())
	character_list=ItemList.new();character_list.size_flags_vertical=Control.SIZE_EXPAND_FILL;character_list.custom_minimum_size.y=160;character_list.fixed_column_width=206;character_list.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS;character_list.add_theme_stylebox_override("panel",T.surface(T.SURFACE,T.SURFACE,2));character_list.add_theme_stylebox_override("selected",T.surface(T.RAISED,T.ACCENT,6));left.add_child(character_list)
	character_list.add_theme_stylebox_override("selected_focus",T.surface(T.RAISED,T.ACCENT,6))
	character_list.item_selected.connect(func(index: int):_select(str(character_list.get_item_metadata(index))))
	overview=_label(left,"",12,T.MUTED)
	next_candidate_button=_button(left,"Next candidate",_next_candidate)
	var right_panel:=PanelContainer.new();right_panel.size_flags_horizontal=Control.SIZE_EXPAND_FILL;right_panel.add_theme_stylebox_override("panel",T.surface(T.SURFACE,T.BORDER,14));split.add_child(right_panel)
	detail_scroll=ScrollContainer.new();detail_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;detail_scroll.size_flags_horizontal=Control.SIZE_EXPAND_FILL;detail_scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL;detail_scroll.custom_minimum_size=Vector2(380,260);right_panel.add_child(detail_scroll)
	var details:=VBoxContainer.new();details.size_flags_horizontal=Control.SIZE_EXPAND_FILL;details.add_theme_constant_override("separation",12);detail_scroll.add_child(details)
	var header:=HBoxContainer.new();header.add_theme_constant_override("separation",14);details.add_child(header)
	_build_portrait(header)
	var identity_box:=VBoxContainer.new();identity_box.size_flags_horizontal=Control.SIZE_EXPAND_FILL;header.add_child(identity_box)
	name_label=_label(identity_box,"",21,T.INK)
	identity_label=_label(identity_box,"",14,T.MUTED)
	_label(details,"1 · Permanent voice design",16,T.ACCENT)
	design=TextEdit.new();design.custom_minimum_size.y=118;design.wrap_mode=TextEdit.LINE_WRAPPING_BOUNDARY;details.add_child(design)
	design.tooltip_text="Edit the stable vocal characteristics: perceived age, register, accent, timbre, rhythm, articulation, breathiness, emphasis and mannerisms. Current emotions are controlled separately. Changes affect only a staged candidate."
	_label(details,"Personalized preset · recommended (Realtime Mini)",14,T.ACCENT)
	var preset_row:=HBoxContainer.new();details.add_child(preset_row);_label(preset_row,"Base voice",14,T.INK)
	preset_voice=OptionButton.new();preset_voice.size_flags_horizontal=Control.SIZE_EXPAND_FILL;preset_row.add_child(preset_voice)
	for base: String in ["alloy","ash","ballad","coral","echo","sage","shimmer","verse","marin","cedar"]:
		preset_voice.add_item(base.capitalize());preset_voice.set_item_metadata(preset_voice.item_count-1,base)
		if not Models.voice_compatible("gpt-realtime-2.1-mini",base,"preset"):preset_voice.set_item_disabled(preset_voice.item_count-1,true)
	_label(details,"A shared provider voice with individual vocal instructions. No custom voice creation charge or new provider resource.",12,T.MUTED)
	var preset_actions:=HFlowContainer.new();details.add_child(preset_actions)
	regenerate_preset_button=_button(preset_actions,"Suggest profile from character",_suggest_preset)
	preset_button=_button(preset_actions,"Stage personalized preset",_stage_preset)
	_label(details,"2 · Audition the voice",16,T.ACCENT)
	var model_row:=HBoxContainer.new();details.add_child(model_row);_label(model_row,"Audition model",15,T.INK)
	voice_model=OptionButton.new();voice_model.size_flags_horizontal=Control.SIZE_EXPAND_FILL;model_row.add_child(voice_model)
	voice_model.item_selected.connect(func(_index: int):fit.set_pressed_no_signal(false);_refresh())
	lifecycle_label=_label(details,"",13,T.MUTED)
	use_candidate=CheckButton.new();use_candidate.text="Audition pending candidate";details.add_child(use_candidate)
	use_candidate.toggled.connect(func(_value: bool):_switch_candidate())
	var emotional_row:=HBoxContainer.new();details.add_child(emotional_row);_label(emotional_row,"Delivery",15,T.INK)
	emotion=OptionButton.new();emotion.size_flags_horizontal=Control.SIZE_EXPAND_FILL;emotional_row.add_child(emotion)
	for mood: String in EMOTIONS:emotion.add_item(mood.capitalize());emotion.set_item_metadata(emotion.item_count-1,mood)
	sentence=TextEdit.new();sentence.text="I thought we had this figured out. Let's take another look at what happened.";sentence.custom_minimum_size.y=82;sentence.wrap_mode=TextEdit.LINE_WRAPPING_BOUNDARY;details.add_child(sentence)
	sentence.text_changed.connect(func():
		if is_instance_valid(fit):fit.set_pressed_no_signal(false);_refresh())
	var audition_actions:=HFlowContainer.new();details.add_child(audition_actions)
	preview_button=_button(audition_actions,"Play audition",_preview)
	core_button=_button(audition_actions,"Play all 3 core auditions",_confirm_core)
	stop_button=_button(audition_actions,"Stop",_stop)
	audition_label=_label(details,"",13,T.MUTED)
	fit=CheckBox.new();fit.text="I listened and this voice fits the character";details.add_child(fit)
	fit.toggled.connect(func(_value: bool):_refresh())
	_label(details,"3 · Approve and save",16,T.ACCENT)
	var approval_actions:=HFlowContainer.new();details.add_child(approval_actions)
	approve_button=_button(approval_actions,"Approve voice and model",_approve)
	discard_button=_button(approval_actions,"Discard candidate",_discard)
	advanced_toggle=CheckButton.new();advanced_toggle.text="Advanced · batch generation, recovery and allocation";details.add_child(advanced_toggle)
	advanced_box=VBoxContainer.new();advanced_box.add_theme_constant_override("separation",10);advanced_box.visible=false;details.add_child(advanced_box)
	advanced_toggle.toggled.connect(func(open: bool):advanced_box.visible=open)
	_label(advanced_box,"Optional custom provider voices",16,T.ACCENT)
	generate_button=_button(advanced_box,"Generate original custom voice",_generate)
	_label(advanced_box,"Custom voice allocation",16,T.ACCENT)
	capacity_label=_label(advanced_box,"",13,T.MUTED)
	var capacity_row:=HBoxContainer.new();advanced_box.add_child(capacity_row);_label(capacity_row,"Voices created elsewhere",14,T.INK)
	external_count=SpinBox.new();external_count.min_value=0;external_count.max_value=100;external_count.step=1;external_count.custom_minimum_size.x=100;capacity_row.add_child(external_count)
	external_count.value_changed.connect(func(value: float):
		if not _context_current():
			_refresh()
			return
		if not _refreshing:
			var error:=Voices.set_external_voice_count(int(value))
			if error!=OK:status.text="Could not save voice capacity: "+error_string(error)
			_refresh())
	batch_button=_button(advanced_box,"Generate missing faculty voices",_confirm_batch)
	batch_stop_button=_button(advanced_box,"Stop batch after current creation",func():batch_stop=true;_refresh())
	legacy_box=VBoxContainer.new();advanced_box.add_child(legacy_box)
	_label(legacy_box,"An older, unscoped voice exists for this generated ID. Choose whether it belongs to this saved campus. Nothing is reassigned automatically.",13,T.ACCENT)
	legacy_adopt=_button(legacy_box,"Adopt existing saved voice…",func():_confirm_legacy(true))
	legacy_separate=_button(legacy_box,"Keep separate; initialize this campus voice…",func():_confirm_legacy(false))
	recover_toggle=CheckButton.new();recover_toggle.text="Recover / import saved voice";advanced_box.add_child(recover_toggle)
	recover_toggle.toggled.connect(func(_value: bool):_refresh())
	recovery_box=VBoxContainer.new();advanced_box.add_child(recovery_box)
	_label(recovery_box,"Recover or import an existing custom voice",16,T.ACCENT)
	recovery_note=_label(recovery_box,"",13,T.MUTED)
	_button(recovery_box,"Open OpenAI dashboard",func():OS.shell_open("https://platform.openai.com/"))
	recover_id=LineEdit.new();recover_id.placeholder_text="Saved voice_… ID";recover_id.max_length=128;recovery_box.add_child(recover_id)
	recover_type=OptionButton.new();recover_type.add_item("Original prompt-generated voice");recover_type.set_item_metadata(0,"prompt");recover_type.add_item("Authorized recording-based voice");recover_type.set_item_metadata(1,"audio_sample");recovery_box.add_child(recover_type)
	recover_fit=CheckBox.new();recover_fit.text="I own or am authorized to use this voice and its type is correct";recovery_box.add_child(recover_fit)
	recover_button=_button(recovery_box,"Import as unapproved candidate",_recover)
	clear_pending_button=_button(recovery_box,"Confirm no voice was created…",_confirm_clear_pending)
	status=_label(details,"",14,T.ACCENT)
	audio=AudioStreamPlayer.new();add_child(audio);audio.finished.connect(_heard)
	# Long IDs and translated labels must not force the window off screen.
	for control: Node in find_children("*","Button",true,false):
		if control is Button:control.clip_text=true
		if control is OptionButton:control.fit_to_longest_item=false
	_fill_list();_select(selected_id)

func _load_people() -> void:
	people.clear();student_index.clear();selected_student="";profile_unavailable=false
	for id: String in Roster.all_people():people[id]=People.teacher(id)
	var game:=service.get_parent() if is_instance_valid(service) else null
	if not is_instance_valid(game) or game.get("lecture_classes")==null:return
	var students: Variant=game.lecture_classes.get("classroom_students")
	if students==null or not students.get("population") is RefCounted:return
	population_source=students.population
	var seeds: Variant=population_source.get("people")
	var index: Variant=population_source.get("index")
	if not seeds is Dictionary:return
	for id: String in seeds:
		if not seeds[id] is Dictionary:continue
		var seed: Dictionary=seeds[id]
		var entry: Dictionary=index.get(id,{}) if index is Dictionary else {}
		var origin:=str(seed.get("origin_population",entry.get("origin_population",seed.get("voice_scope",""))))
		var person:={"id":id,"role":"student","name":str(entry.get("name",seed.get("name",id))),"program":str(entry.get("program",seed.get("program",""))),
			"persistent_id":str(seed.get("persistent_id",entry.get("id",id))),"origin_population":origin,
			"voice_scope":origin if not origin.is_empty() else studio_owner.sha256_text() if not studio_owner.is_empty() else ""}
		# Voice status needs only ID and origin scope. Never project every dossier
		# merely to sort/filter the roster or count pending voice candidates.
		student_index[id]=person;people[id]=person

func _hydrate_selection(id: String) -> Dictionary:
	if id==selected_student and not profile_unavailable:return people[id]
	if student_index.has(selected_student):people[selected_student]=student_index[selected_student]
	selected_student="";profile_unavailable=false
	if not student_index.has(id):return people[id]
	selected_student=id
	if not is_instance_valid(population_source) or Dossiers.host_identity!=studio_owner:
		profile_unavailable=true;return {}
	var person: Dictionary=population_source.profile_for(id)
	if person.is_empty() or str(person.get("id",""))!=id:
		profile_unavailable=true;return {}
	for field: String in ["persistent_id","origin_population","voice_scope"]:
		if not person.has(field):person[field]=student_index[id][field]
	people[id]=person
	return person

func _context_current() -> bool:
	if not is_inside_tree() or not is_instance_valid(service) or not service.host_allowed() or Dossiers.host_identity!=studio_owner:return false
	return not service.has_method("_account_cache_id") or str(service._account_cache_id(str(draft.get("key",""))))==studio_account

func _scope(id: String="") -> String:
	return Voices.scope_for(people.get(selected_id if id.is_empty() else id,{}))

func _fill_list() -> void:
	character_list.clear()
	var ids:=people.keys()
	ids.sort_custom(func(a: String,b: String):return str(people[a].get("name",a)).naturalnocasecmp_to(str(people[b].get("name",b)))<0)
	var query:=search.text.strip_edges().to_lower()
	var totals: Dictionary={}
	for id: String in ids:
		var person: Dictionary=people[id]
		var state:=Voices.custom_status(person)
		if roster_filter.selected==1 and not Roster.has(id):continue
		if roster_filter.selected==2 and Roster.has(id):continue
		var name:=str(person.get("name",id))
		var program:=str(person.get("program",""))
		if not query.is_empty() and not name.to_lower().contains(query) and not id.contains(query) and not program.to_lower().contains(query):continue
		totals[state]=int(totals.get(state,0))+1
		var suffix: String={"approved":"Custom approved","candidate":"Ready to audition","creating":"Creating","reconcile":"Recover ID","legacy":"Resolve old voice","missing":"Preset","storage_error":"Storage blocked"}.get(state,state)
		character_list.add_item(name+" · "+suffix)
		var index:=character_list.item_count-1
		character_list.set_item_metadata(index,id)
		character_list.set_item_tooltip(index,name+" — "+suffix+("\n"+program if not program.is_empty() else ""))
		if id==selected_id:character_list.select(index)
	character_list.ensure_current_is_visible.call_deferred()
	overview.text="%d characters · %d custom approved\n%d candidates · %d unresolved\n%d using a preset"%[character_list.item_count,totals.get("approved",0),totals.get("candidate",0),int(totals.get("reconcile",0))+int(totals.get("legacy",0))+int(totals.get("creating",0)),totals.get("missing",0)]

func _next_candidate() -> void:
	if busy or batch_active or audio.playing or not _context_current():return
	var ids: Array=Roster.all_people().keys()
	for id in people:
		if id not in ids:ids.append(id)
	var start:=ids.find(selected_id)
	for offset in range(1,ids.size()+1):
		var id:=str(ids[posmod(start+offset,ids.size())])
		if people.has(id) and Voices.custom_status(people[id])=="candidate":
			search.clear();roster_filter.select(0);_select(id);_fill_list();return

func _select(id: String) -> void:
	if not people.has(id) or not is_inside_tree():return
	if batch_active or (busy and preview_request_id.is_empty()):_fill_list();return
	_stop()
	selected_id=id
	for index in character_list.item_count:
		if str(character_list.get_item_metadata(index))==id:character_list.select(index);character_list.ensure_current_is_visible.call_deferred();break
	fit.set_pressed_no_signal(false)
	recover_fit.set_pressed_no_signal(false)
	recover_id.clear()
	recover_type.select(0)
	var person:=_hydrate_selection(id)
	if person.is_empty():
		name_label.text=str(people[id].get("name",id));design.text="";use_candidate.set_pressed_no_signal(false)
		_rebuild_models({},_default_model())
		if is_instance_valid(portrait_model):portrait_model.queue_free()
		_refresh();return
	var identity:=Voices.identity(person)
	var pending:=Voices.candidate(id,_scope())
	name_label.text=str(person.get("name",id))
	use_candidate.set_pressed_no_signal(not pending.is_empty())
	var shown:=pending if not pending.is_empty() else identity
	if shown.is_empty():
		design.text=str(Voices.Design.draft(person).get("design_description",""))
		status.text="Resolve the saved voice before generating or playing another." if Voices.legacy_conflict(person) else "Voice storage is unavailable. No replacement voice was selected."
	else:
		var proposed:=Voices.creation_design(person) if pending.is_empty() else shown
		design.text=str(proposed.get("design_description",shown.design_description))
	var proposed_preset:=shown if shown.get("voice_type","")=="preset" else Voices.Design.draft(person)
	_select_base_voice(str(proposed_preset.get("permanent_voice_id","alloy")))
	var preferred:=str(identity.get("preferred_model","gpt-realtime-2.1-mini" if identity.get("voice_type","")=="preset" else draft.get("modalities",{}).get("tts",_default_model())))
	if use_candidate.button_pressed:preferred="gpt-live-1.1" if pending.get("voice_type")=="prompt" else "gpt-realtime-2.1-mini"
	_rebuild_models(shown if not shown.is_empty() else Voices.Design.draft(person),preferred)
	if is_instance_valid(portrait_model):portrait_model.queue_free()
	var appearance: Dictionary=Roster.config(id) if Roster.has(id) else person.get("appearance",Toon.defaults())
	portrait_model=Toon.build(appearance);portrait_world.add_child(portrait_model)
	_refresh()

func _select_base_voice(base: String) -> void:
	for index in preset_voice.item_count:
		if str(preset_voice.get_item_metadata(index))==base and not preset_voice.is_item_disabled(index):
			preset_voice.select(index)
			return

func _suggest_preset() -> void:
	if not _context_current() or busy or batch_active or not Voices.candidate(selected_id,_scope()).is_empty():return
	var proposed:=Voices.Design.draft(people.get(selected_id,{}))
	if proposed.is_empty():return
	design.text=str(proposed.design_description)
	_select_base_voice(str(proposed.permanent_voice_id))
	status.text="Suggested from the saved character's vocal descriptions and personality. Edit the instructions or base voice, then stage for audition."

func _stage_preset() -> void:
	if not _context_current() or busy or batch_active or audio.playing or preset_voice.selected<0:return
	var error:=Voices.stage_preset(people[selected_id],str(preset_voice.get_selected_metadata()),design.text)
	if error!=OK:
		status.text="Could not stage the preset: "+error_string(error)+" (use 40–2,000 characters and a supported base voice)."
		return
	_select(selected_id)
	status.text="Preset candidate saved locally. Audition the same sentence in three core moods and approve to use it in gameplay. Your active voice is unchanged."

func _voice() -> Dictionary:
	if profile_unavailable:return {}
	var pending:=Voices.candidate(selected_id,_scope())
	return pending if use_candidate.button_pressed and not pending.is_empty() else Voices.identity(people.get(selected_id,{}))

func _model() -> String:
	return str(voice_model.get_selected_metadata()) if voice_model.selected>=0 else ""

func _rebuild_models(profile: Dictionary,preferred: String) -> void:
	var choices: Array=BASE_AUDITION_MODELS.duplicate()
	var configured:=str(draft.get("modalities",{}).get("tts",_default_model()))
	for model in [preferred,configured,str(profile.get("preferred_model",""))]:
		if not model.is_empty() and model not in choices:choices.append(model)
	voice_model.clear()
	var first:=-1
	var exact:=-1
	for model: String in choices:
		var voice: Variant=str(profile.get("permanent_voice_id","")) if profile.get("voice_type","preset")=="preset" else {"id":str(profile.get("permanent_voice_id",""))}
		var compatible:=not profile.is_empty() and Models.voice_compatible(model,voice,str(profile.get("voice_type","preset")))
		voice_model.add_item(model if compatible else model+" · incompatible")
		var index:=voice_model.item_count-1
		voice_model.set_item_metadata(index,model)
		voice_model.set_item_disabled(index,not compatible)
		if compatible and first<0:first=index
		if compatible and model==preferred:exact=index
	voice_model.select(exact if exact>=0 else first)

func _switch_candidate() -> void:
	_stop()
	fit.set_pressed_no_signal(false)
	var profile:=_voice()
	if not profile.is_empty():
		var proposed:=profile if use_candidate.button_pressed else Voices.creation_design(people[selected_id])
		design.text=str(proposed.get("design_description",profile.design_description))
		_rebuild_models(profile,str(profile.get("preferred_model",_model())))
	_refresh()

func _refresh() -> void:
	if _refreshing or not is_inside_tree() or not is_instance_valid(status) or not people.has(selected_id):return
	_refreshing=true
	var person: Dictionary=people[selected_id]
	var scope:=_scope()
	var profile:=_voice()
	var pending:=Voices.candidate(selected_id,scope)
	var journal:=Voices.pending_creation(selected_id,scope)
	var active:=Voices.peek(person)
	var legacy:=Voices.legacy_conflict(person)
	var current:=_context_current()
	var locked:=busy or batch_active or audio.playing or not core_queue.is_empty() or not current
	var online:=_can_request()
	var valid:=not profile.is_empty() and not legacy
	var selected_model:=_model()
	var resolved:=Voices.resolve(person,selected_model,profile) if valid else {"ok":false,"error":"No usable saved voice."}
	var lifecycle: Dictionary=service.model_status(selected_model,"tts",draft) if is_instance_valid(service) and service.has_method("model_status") else Models.lifecycle(selected_model)
	if valid:
		identity_label.text="%s · intended age %d\n%s\n%s · %s\nVoice: %s\n%s"%[str(profile.vocal_presentation).capitalize(),int(profile.perceived_age),str(profile.pitch_range),str(profile.timbre),str(profile.accent),str(profile.permanent_voice_id),str(profile.approval_status).replace("_"," ").capitalize()]
		if profile.voice_type!="preset":identity_label.text+="\nCustom provider voice; acoustic fit requires listening."
		else:identity_label.text+="\nPersonalized shared preset; acoustic uniqueness is not guaranteed."
		if not str(active.get("preferred_model","")).is_empty():identity_label.text+="\nGameplay model pinned to "+str(active.preferred_model)
		if use_candidate.button_pressed and not pending.is_empty():identity_label.text+="\nGameplay retains the existing voice until approval."
	else:identity_label.text="Voice unavailable — no speaker was silently reassigned."
	var availability:="listed for this API key" if lifecycle.get("account_listed",false) else "not listed; explicit audition can test access" if lifecycle.get("catalog_known",false) else "account access not tested"
	if lifecycle.get("access_failure",false):availability="previous request failed; explicit retry available"
	lifecycle_label.text=Models.lifecycle_description(selected_model)+" · "+availability+"\n"+("Voice-compatible. Speech uses the same speaker in each mood." if resolved.get("ok",false) else str(resolved.get("error","")))
	lifecycle_label.add_theme_color_override("font_color",T.MUTED if bool(resolved.get("ok",false)) else T.ERROR)
	var heard:=Voices.auditions_for(profile,selected_model,sentence.text)
	var completed:=0
	for mood: String in Voices.AUDITION_MOODS:
		if heard.has(mood):completed+=1
	audition_label.text="Core auditions for this exact model and script: %d/3 — normal, sad, angry. Listen and confirm the fit."%completed
	use_candidate.visible=not pending.is_empty()
	use_candidate.disabled=locked
	discard_button.visible=not pending.is_empty()
	discard_button.disabled=locked or not current
	voice_model.disabled=locked or not valid
	emotion.disabled=locked or not valid
	design.editable=not locked and valid and pending.is_empty() and journal.is_empty()
	preset_voice.disabled=not design.editable
	preset_button.disabled=not design.editable
	regenerate_preset_button.disabled=not design.editable
	sentence.editable=not locked and valid
	var text_valid:=not sentence.text.strip_edges().is_empty() and sentence.text.strip_edges().length()<=1200
	preview_button.disabled=locked or not online or not bool(resolved.get("ok",false)) or not text_valid
	core_button.disabled=preview_button.disabled
	stop_button.disabled=not audio.playing and preview_request_id.is_empty() and core_queue.is_empty()
	fit.disabled=locked or completed!=3 or not valid
	approve_button.disabled=locked or not bool(resolved.get("ok",false)) or completed!=3 or not fit.button_pressed
	var capacity:=Voices.capacity(person)
	capacity_label.text="%d known + %d elsewhere + %d unresolved · %d/%d slots remain. %d reserved for established faculty.\n%s"%[capacity.get("known",0),capacity.get("external",0),capacity.get("unresolved",0),capacity.get("remaining",0),capacity.get("limit",100),capacity.get("faculty_reserved",0),str(capacity.get("note",""))]
	external_count.value=int(capacity.get("external",0))
	external_count.editable=not locked and current
	generate_button.disabled=locked or not online or not valid or not pending.is_empty() or not journal.is_empty() or not bool(capacity.get("available",false))
	var missing:=Voices.missing_faculty(people).size()
	batch_button.text="Generate missing faculty voices (%d)"%missing
	batch_button.disabled=locked or not online or not current or missing==0 or int(capacity.get("remaining",0))==0
	batch_stop_button.visible=batch_active
	batch_stop_button.disabled=batch_stop
	legacy_box.visible=legacy
	legacy_adopt.disabled=locked or not current
	legacy_separate.disabled=legacy_adopt.disabled
	recover_toggle.visible=valid and pending.is_empty()
	recover_toggle.disabled=locked or not journal.is_empty()
	if not journal.is_empty():recover_toggle.set_pressed_no_signal(true)
	recovery_box.visible=recover_toggle.visible and recover_toggle.button_pressed
	next_candidate_button.disabled=locked or not current or not people.values().any(func(p: Dictionary):return Voices.custom_status(p)=="candidate")
	recovery_note.text="Previous request: "+str(journal.get("name",""))+". Find this resource in the provider dashboard. Do not generate another until reconciled." if not journal.is_empty() else "Import a saved voice from your own project. Prompt voices require GPT-Live. Recording-based voices require the speaker's authorized consent. Import does not approve a voice or verify provider access."
	recover_id.editable=not locked and valid and not journal.get("in_flight",false)
	recover_type.disabled=not recover_id.editable
	recover_fit.disabled=not recover_id.editable
	recover_button.disabled=not recover_id.editable
	clear_pending_button.visible=not journal.is_empty()
	clear_pending_button.disabled=locked or not current or bool(journal.get("in_flight",false))
	if profile_unavailable:
		status.text="Saved character details could not be loaded. The existing voice is retained. Select the character again to retry, or reopen after restoring the saved profile."
	elif not current:
		status.text="Browse saved character information here. Only the current host can edit voices. Reopen this menu if the host profile or account changed."
	elif not online:
		status.text="Saved characters and voices are available offline. Connect the host's OpenAI account to generate or audition a voice."
	_refreshing=false

func _default_model() -> String:
	return str(service.tts_model) if is_instance_valid(service) else "gpt-realtime-2.1-mini"

func _can_request() -> bool:
	if not _context_current():return false
	return not str(draft.get("key","")).is_empty() or not service.has_method("configured") or bool(service.configured())

func _confirm(title_text: String,message: String,action: Callable) -> void:
	var dialog:=ConfirmationDialog.new()
	dialog.title=title_text;dialog.dialog_text=message;dialog.ok_button_text="Continue"
	add_child(dialog)
	dialog.confirmed.connect(func():dialog.queue_free();action.call())
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered(Vector2i(480,180))

func _preview() -> void:
	if busy or batch_active or not _can_request():return
	_stop()
	await _start_preview(str(emotion.get_selected_metadata()))

func _confirm_core() -> void:
	if core_button.disabled:return
	_confirm("Three paid speech auditions","Play normal, sad and angry using this same voice, model and script. Each preview is a billable speech request. Stop at any time; approval still requires your listening judgment.",_play_core)

func _play_core() -> void:
	if busy or batch_active or not _context_current():return
	_stop()
	core_queue.assign(Voices.AUDITION_MOODS)
	await _preview_next()

func _preview_next() -> void:
	if core_queue.is_empty() or not _context_current():_refresh();return
	var mood: String=core_queue.pop_front()
	for index in emotion.item_count:
		if str(emotion.get_item_metadata(index))==mood:emotion.select(index);break
	await _start_preview(mood)

func _start_preview(mood: String) -> void:
	if not _can_request():core_queue.clear();_refresh();return
	var text:=sentence.text.strip_edges()
	var profile:=_voice()
	if text.is_empty() or text.length()>1200 or profile.is_empty():core_queue.clear();status.text="Select a usable voice and a 1–1,200 character script.";_refresh();return
	var model:=_model()
	var spoken_mood:="steady" if mood=="normal" else mood
	var delivery:=Delivery.build(people[selected_id],model,2,spoken_mood,{},"converse",{"voice_override":profile,"emotion_audition":true})
	if not bool(delivery.get("ok",false)):core_queue.clear();status.text=str(delivery.get("error","This voice is unavailable."));_refresh();return
	preview_ticket+=1
	var ticket:=preview_ticket
	var character_id:=selected_id
	var scope:=_scope()
	var request_id:="voice_audition_"+Crypto.new().generate_random_bytes(12).hex_encode()
	preview_request_id=request_id;delivery.request_id=request_id
	busy=true;fit.set_pressed_no_signal(false);status.text="Generating "+mood+" audition. Usage is recorded in OpenAI settings.";_refresh()
	var preview_draft:=draft.duplicate(true)
	if not preview_draft.get("modalities") is Dictionary:preview_draft.modalities={}
	preview_draft.modalities.tts=model
	preview_draft.tts_enabled=true
	preview_draft.request_type="test"
	var metadata:={"character_id":character_id,"scope":scope,"voice_id":str(profile.permanent_voice_id),"profile_version":int(profile.profile_version),"mood":mood,"model":model,"script":text}
	var playback:={"started":false}
	var started_at:=Time.get_ticks_msec()
	# Play the verified waveform before the provider finishes usage accounting.
	var mix_delivery:=delivery.duplicate(true)
	delivery._audio_ready=func(value: Dictionary):
		if not playback.started:
			playback.started=_play_preview_audio(value,ticket,metadata,mix_delivery,started_at)
	var result: Dictionary=await service.speak(text,preview_draft,delivery.voice,delivery)
	if not is_inside_tree() or ticket!=preview_ticket:return
	preview_request_id="";busy=false
	if not _context_current() or character_id!=selected_id or scope!=_scope():_stop();return
	if not bool(result.get("ok",false)):
		_stop();status.text=str(result.get("error","The voice preview could not be played."));_refresh();return
	if not playback.started:
		playback.started=_play_preview_audio(result,ticket,metadata,mix_delivery,started_at)
		if not playback.started:
			core_queue.clear();status.text="The voice preview contained no playable audio.";_refresh();return
	_refresh()
	# Both the request and playback must finish before the next batch audition.
	if playing.is_empty() and not core_queue.is_empty():_preview_next.call_deferred()

func _play_preview_audio(result: Dictionary,ticket: int,metadata: Dictionary,delivery: Dictionary,started_at: int) -> bool:
	if not is_inside_tree() or ticket!=preview_ticket or not _context_current() or metadata.character_id!=selected_id or metadata.scope!=_scope():return false
	if not result.get("ok",false) or not result.get("stream") is AudioStreamWAV or result.stream.get_length()<=0.:return false
	playing=metadata.duplicate()
	audio.stream=VoiceMixer.normalise(result.stream,delivery);audio.play()
	status.text="Playing "+str(metadata.mood)+" · audio ready in %.2f s. Compare the delivery while listening."%[float(Time.get_ticks_msec()-started_at)/1000.]
	_refresh()
	return true

func _heard() -> void:
	if playing.is_empty():return
	if not _context_current():playing.clear();core_queue.clear();_refresh();return
	var completed:=playing.duplicate()
	playing.clear()
	var error:=Voices.record_audition(str(completed.character_id),str(completed.voice_id),str(completed.mood),str(completed.model),str(completed.script),str(completed.scope),int(completed.profile_version))
	status.text="Audition played. Confirm the character fit after listening." if error==OK else "The audition played, but its record could not be saved."
	if error!=OK:core_queue.clear()
	_refresh()
	if not busy and not core_queue.is_empty():_preview_next.call_deferred()

func _stop() -> void:
	preview_ticket+=1;playing.clear();core_queue.clear()
	if not preview_request_id.is_empty():
		if is_instance_valid(service) and service.has_method("cancel_speech_request"):service.cancel_speech_request(preview_request_id)
		preview_request_id="";busy=false
	if is_instance_valid(audio):audio.stop();audio.stream=null
	if is_instance_valid(stop_button):stop_button.disabled=true
	if is_instance_valid(status):_refresh()

func _generate() -> void:
	if busy or batch_active or profile_unavailable or not _can_request():return
	_stop()
	var id:=selected_id
	var person: Dictionary=people[id]
	var prompt:=design.text
	var hint:=sentence.text
	busy=true;fit.set_pressed_no_signal(false);status.text="Creating one original voice candidate. This does not replace the current voice.";_refresh()
	var result:=await Voices.generate_candidate(service,person,prompt,hint,draft)
	if not is_inside_tree():return
	busy=false
	if not _context_current():_refresh();return
	if not bool(result.get("ok",false)):status.text=str(result.get("error","Voice creation failed."));_fill_list();_refresh();return
	_fill_list()
	if _context_current() and id==selected_id:
		use_candidate.set_pressed_no_signal(true)
		var candidate:=Voices.candidate(id,_scope())
		design.text=str(candidate.get("design_description",prompt))
		_rebuild_models(candidate,"gpt-live-1.1")
	status.text="Candidate saved. Play normal, sad and angry auditions, then approve only if the voice fits."
	_refresh()

func _confirm_batch() -> void:
	if batch_button.disabled:return
	var count:=Voices.missing_faculty(people).size()
	_confirm("Generate missing faculty voices","Create up to %d original voice candidates sequentially, skipping saved custom voices, candidates and unresolved requests. Prompt creation is free; auditions are separate paid requests. No gameplay voice changes until you approve it. Stop after the current creation at any time."%count,_generate_missing_faculty)

func _generate_missing_faculty() -> void:
	if busy or batch_active or not _can_request():return
	_stop();batch_active=true;batch_stop=false
	fit.set_pressed_no_signal(false)
	var ids:=Voices.missing_faculty(people)
	var created:=0
	var failure:=""
	for id: String in ids:
		if batch_stop or not _context_current():break
		var person: Dictionary=people[id]
		if Voices.custom_status(person)!="missing":continue
		var identity:=Voices.identity(person)
		if identity.is_empty() or not Voices.capacity(person).get("available",false):
			failure="No safe capacity or saved identity for "+str(person.get("name",id))+".";break
		status.text="Generating %s · %d/%d saved"%[str(person.get("name",id)),created,ids.size()]
		_refresh()
		var proposed:=Voices.creation_design(person)
		var result:=await Voices.generate_candidate(service,person,str(proposed.get("design_description",identity.design_description)),"",draft)
		if not is_inside_tree():return
		if not bool(result.get("ok",false)):failure=str(result.get("error","Creation failed."));break
		created+=1
		_fill_list()
	batch_active=false
	if not _context_current():return
	_select(selected_id)
	status.text="%d candidate(s) saved. %s"%[created,failure if not failure.is_empty() else "Stopped after current creation." if batch_stop else "Audition and approve each candidate when ready."]
	_fill_list();_refresh()

func _approve() -> void:
	if busy or batch_active or audio.playing or not _context_current():return
	var profile:=_voice()
	if profile.is_empty():return
	var error:=Voices.approve(selected_id,str(profile.permanent_voice_id),fit.button_pressed,_model(),sentence.text,_scope(),int(profile.profile_version))
	if error!=OK:status.text="Voice approval could not be saved: "+error_string(error);return
	use_candidate.set_pressed_no_signal(false)
	fit.set_pressed_no_signal(false)
	status.text="Approved. This character keeps this exact voice and compatible model across sessions."
	_fill_list();_refresh()

func _discard() -> void:
	if busy or batch_active or not _context_current():return
	_stop()
	var error:=Voices.discard_candidate(selected_id,_scope())
	use_candidate.set_pressed_no_signal(false);fit.set_pressed_no_signal(false)
	var active:=Voices.peek(people[selected_id])
	if not active.is_empty():design.text=str(active.design_description);_rebuild_models(active,str(active.get("preferred_model",_default_model())))
	status.text="Candidate removed from this audition. Its remote voice is retained and still counts toward allocation." if error==OK else "Could not discard the candidate: "+error_string(error)
	_fill_list();_refresh()

func _recover() -> void:
	if busy or batch_active or profile_unavailable or not _context_current():return
	var error:=Voices.recover_candidate(people[selected_id],recover_id.text,str(recover_type.get_selected_metadata()),design.text,recover_fit.button_pressed)
	if error!=OK:status.text="Could not import the candidate: "+error_string(error);return
	var pending:=Voices.candidate(selected_id,_scope())
	use_candidate.set_pressed_no_signal(true);fit.set_pressed_no_signal(false)
	design.text=str(pending.design_description)
	_rebuild_models(pending,"gpt-live-1.1" if pending.voice_type=="prompt" else "gpt-realtime-2.1-mini")
	recover_id.clear();recover_fit.set_pressed_no_signal(false)
	status.text="Imported as an unapproved candidate. Auditions must confirm access and suitability before gameplay uses it."
	_fill_list();_refresh()

func _confirm_clear_pending() -> void:
	var id:=selected_id
	var scope:=_scope()
	_confirm("Reconcile unresolved creation","Continue only if you checked the correct OpenAI project and confirmed the previous request did not create a saved voice. If a voice exists, import its ID instead.",func():
		if not _context_current() or id!=selected_id or scope!=_scope():return
		var error:=Voices.clear_unconfirmed_creation(id,scope,true)
		status.text="Unresolved creation cleared." if error==OK else "Could not reconcile: "+error_string(error)
		_fill_list();_refresh())

func _confirm_legacy(adopt: bool) -> void:
	var id:=selected_id
	var scope:=_scope()
	_confirm("Resolve previous unscoped voice","Adopt the saved voice only if it belongs to this same fictional character and campus. Otherwise keep the older identity separate and create a new provisional preset for this campus.",func():
		if profile_unavailable or not _context_current() or selected_id!=id or _scope()!=scope:return
		var error:=Voices.resolve_legacy(people[id],adopt,true)
		if error==OK:_select(id);_fill_list()
		else:status.text="Could not resolve the old voice: "+error_string(error)
		_refresh())

func _build_portrait(parent: Control) -> void:
	var container:=SubViewportContainer.new();container.custom_minimum_size=Vector2(138,170);container.stretch=true;parent.add_child(container)
	var viewport:=SubViewport.new();viewport.size=Vector2i(138,170);viewport.own_world_3d=true;viewport.render_target_update_mode=SubViewport.UPDATE_WHEN_VISIBLE;container.add_child(viewport)
	portrait_world=Node3D.new();viewport.add_child(portrait_world)
	var environment:=WorldEnvironment.new();var settings:=Environment.new();settings.background_mode=Environment.BG_COLOR;settings.background_color=T.SURFACE;settings.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;settings.ambient_light_color=Color(.75,.87,.95);settings.ambient_light_energy=.75;environment.environment=settings;portrait_world.add_child(environment)
	var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-30,-35,0);light.light_energy=1.3;portrait_world.add_child(light)
	var camera:=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=2.25;camera.position=Vector3(0,1.15,3.25);portrait_world.add_child(camera);camera.look_at(Vector3(0,.95,0));camera.current=true

func _label(parent: Node,text: String,size: int,color: Color) -> Label:
	var label:=Label.new();label.text=text;label.add_theme_font_size_override("font_size",size);label.add_theme_color_override("font_color",color);label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;label.size_flags_horizontal=Control.SIZE_EXPAND_FILL;parent.add_child(label);return label

func _button(parent: Node,text: String,callback: Callable) -> Button:
	var button:=Button.new();button.text=text;button.custom_minimum_size.y=40;button.pressed.connect(callback)
	# FlowContainer relies on minimum width. clip_text alone otherwise makes
	# every action collapse to a narrow, unlabelled pill.
	if parent is FlowContainer:button.custom_minimum_size.x=clampf(button.get_theme_font("font").get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,button.get_theme_font_size("font_size")).x+32.,76.,300.)
	button.add_theme_stylebox_override("normal",T.surface(T.RAISED,T.BORDER,10));button.add_theme_stylebox_override("hover",T.surface(T.RAISED.lightened(.1),T.ACCENT,10));button.add_theme_stylebox_override("disabled",T.surface(T.SURFACE,T.BORDER.darkened(.3),10))
	parent.add_child(button);return button

func _exit_tree() -> void:
	batch_stop=true
	preview_ticket+=1;playing.clear();core_queue.clear()
	if not preview_request_id.is_empty() and is_instance_valid(service) and service.has_method("cancel_speech_request"):service.cancel_speech_request(preview_request_id)
	preview_request_id=""
	if is_instance_valid(audio):audio.stop()
