extends AcceptDialog

const T = preload("res://scripts/ui/design_system/tokens.gd")
const Widgets = preload("res://scripts/ui/design_system/widgets.gd")
const Models = preload("res://scripts/campus/ai/openai_models.gd")
const Images = preload("res://scripts/campus/items/decoration_document.gd")
const CATEGORIES := ["text","image","image_generation","tts","stt"]
const TABS := ["Text","Image analysis","Image generation","Speech output","Transcription"]
const DESCRIPTIONS := [
	"Send a prompt to check the text model and its thinking settings.",
	"Choose an image and ask a question about it.",
	"Describe an image to generate a preview.",
	"Enter a short script to hear the selected voice model.",
	"Choose a 0.15–180 second mono, 16 kHz PCM16 WAV recording. This explicit test sends that recording to the configured speech service."
]
const ACTIONS := ["Send Prompt","Analyze Image","Generate Image","Generate Speech","Transcribe Audio"]
const DEFAULT_PROMPTS := ["Give me three tips for studying for a lab exam.","What is visible in this image?","An evening view of a college library","Welcome to Campus OS.",""]

var service: Node
var draft: Dictionary
var on_verified: Callable
var tabs: TabBar
var description: Label
var model_label: Label
var voice_row: HBoxContainer
var voice: OptionButton
var emotion: OptionButton
var prompt: TextEdit
var browse: Button
var file_label: Label
var status: Label
var run: Button
var verify: Button
var replay: Button
var preview: TextureRect
var audio: AudioStreamPlayer
var attachment := PackedByteArray()
var image_preview: Texture2D
var running := false

func open(client: Node, settings: Dictionary, verified: Callable) -> void:
	service=client
	draft=settings
	on_verified=verified
	title="AI Test"
	ok_button_text="Close"
	dialog_hide_on_ok=false
	unresizable=false
	min_size=Vector2i(420,300)
	confirmed.connect(queue_free)
	canceled.connect(queue_free)
	var stack:=VBoxContainer.new()
	stack.add_theme_constant_override("separation",10)
	add_child(stack)
	tabs=TabBar.new()
	tabs.clip_tabs=true
	for name_text in TABS:tabs.add_tab(name_text)
	stack.add_child(tabs)
	var scroll:=ScrollContainer.new()
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL
	stack.add_child(scroll)
	var content:=VBoxContainer.new()
	content.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation",10)
	scroll.add_child(content)
	var header:=PanelContainer.new()
	header.add_theme_stylebox_override("panel",T.surface(T.SURFACE,T.BORDER,12))
	content.add_child(header)
	var header_text:=VBoxContainer.new()
	header.add_child(header_text)
	model_label=_label(header_text,"",18,T.ACCENT)
	description=_label(header_text,"",15,T.INK)
	voice_row=HBoxContainer.new()
	content.add_child(voice_row)
	_label(voice_row,"Speaker voice",15,T.INK)
	voice=OptionButton.new()
	voice.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	voice_row.add_child(voice)
	emotion=OptionButton.new()
	for mood in ["steady","happy","excited","amused","irritated","angry","sad","tired","disappointed","dismissive"]:
		emotion.add_item(mood.capitalize());emotion.set_item_metadata(emotion.item_count-1,mood)
	voice_row.add_child(emotion)
	for choice: String in Models.speech_voices(str(draft.modalities.get("tts",""))):
		voice.add_item(choice.capitalize())
		voice.set_item_metadata(voice.item_count-1,choice)
	prompt=TextEdit.new()
	prompt.wrap_mode=TextEdit.LINE_WRAPPING_BOUNDARY
	prompt.custom_minimum_size.y=92
	content.add_child(prompt)
	var files:=HBoxContainer.new()
	content.add_child(files)
	browse=_action(files,"Choose File","folder",_choose_file)
	file_label=_label(files,"",14,T.MUTED)
	file_label.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	var actions:=HBoxContainer.new()
	content.add_child(actions)
	run=_action(actions,"Run","play",func():_run_test(false))
	verify=_action(actions,"Test Connection","network",func():_run_test(true))
	replay=_action(actions,"Replay","volume",func():audio.play())
	var result_card:=PanelContainer.new()
	result_card.add_theme_stylebox_override("panel",T.surface(Color("102633"),T.BORDER,12))
	content.add_child(result_card)
	var result_box:=VBoxContainer.new()
	result_card.add_child(result_box)
	_label(result_box,"Result",14,T.ACCENT)
	status=_label(result_box,"",15,T.INK)
	preview=TextureRect.new()
	preview.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.custom_minimum_size.y=170
	result_box.add_child(preview)
	audio=AudioStreamPlayer.new()
	add_child(audio)
	tabs.tab_changed.connect(_select_tab)
	_select_tab(0)
	var screen: Vector2=get_parent().get_viewport_rect().size
	popup_centered(Vector2i(minf(690,screen.x-24),minf(530,screen.y-24)))

func _label(parent: Control, value: String, font_size: int, color: Color) -> Label:
	var item:=Widgets.text(value)
	item.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	item.add_theme_font_size_override("font_size",font_size)
	item.add_theme_color_override("font_color",color)
	parent.add_child(item)
	return item

func _action(parent: Control, value: String, icon: String, callback: Callable) -> Button:
	var button:=Widgets.action(value,icon,callback)
	parent.add_child(button)
	return button

func _select_tab(index: int) -> void:
	var category: String=CATEGORIES[index]
	var selected:=str(draft.modalities.get(category,""))
	var selected_effort:=str(draft.effort if category=="text" else draft.image_effort if category=="image" else "")
	model_label.text=selected if not selected.is_empty() else "No compatible model"
	if not selected_effort.is_empty():model_label.text+="  ·  "+selected_effort.capitalize()+" effort"
	description.text=DESCRIPTIONS[index]
	voice_row.visible=category=="tts" and voice.item_count>0
	attachment.clear()
	image_preview=null
	audio.stop()
	replay.hide()
	preview.hide()
	preview.texture=null
	status.text="Ready to test with your connected API key."
	status.add_theme_color_override("font_color",T.MUTED)
	run.text=ACTIONS[index]
	prompt.visible=category!="stt"
	prompt.text=DEFAULT_PROMPTS[index]
	browse.visible=category in ["image","stt"]
	browse.text="Choose Image" if category=="image" else "Choose WAV"
	file_label.visible=browse.visible
	file_label.text="No file selected"
	verify.visible=category=="text"
	if selected.is_empty():status.text="This API key has no compatible model."
	elif category in ["tts","stt"] and not bool(draft.get(category+"_enabled",false)):
		status.text="Enable this feature in OpenAI Settings to test it."
	_update_actions()

func _update_actions() -> void:
	var category: String=CATEGORIES[tabs.current_tab]
	var available:=Models.available_for(str(draft.modalities.get(category,"")),category)
	if category in ["tts","stt"]:available=available and bool(draft.get(category+"_enabled",false))
	run.disabled=running or not available or (browse.visible and attachment.is_empty())
	verify.disabled=running or not available
	browse.disabled=running or not available
	voice.disabled=running or not available

func _choose_file() -> void:
	var dialog:=FileDialog.new()
	var is_image: bool=CATEGORIES[tabs.current_tab]=="image"
	dialog.use_native_dialog=true
	dialog.access=FileDialog.ACCESS_FILESYSTEM
	dialog.file_mode=FileDialog.FILE_MODE_OPEN_FILE
	if is_image:dialog.add_filter("*.png,*.jpg,*.jpeg,*.webp","Images")
	else:dialog.add_filter("*.wav","WAV audio")
	add_child(dialog)
	dialog.file_selected.connect(func(path: String):
		_attach(path,is_image)
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered_ratio(0.75)

func _attach(path: String,is_image: bool) -> void:
	attachment.clear()
	image_preview=null
	preview.hide()
	file_label.text="No file selected"
	var file:=FileAccess.open(path,FileAccess.READ)
	var limit:=Images.MAX_IMPORT if is_image else 5760044
	if file==null or file.get_length()>limit:
		_set_result("Could not read that file, or it exceeds the size limit.",false)
	else:
		var bytes:=file.get_buffer(file.get_length())
		if is_image:
			var image:=Images.import_image(bytes,path.get_extension().to_lower())
			if image!=null:
				var scale:=minf(1.0,768.0/float(maxi(image.get_width(),image.get_height())))
				if scale<1.0:image.resize(maxi(1,roundi(image.get_width()*scale)),maxi(1,roundi(image.get_height()*scale)),Image.INTERPOLATE_LANCZOS)
				var jpeg:=image.save_jpg_to_buffer(0.7)
				if jpeg.size()<=262144:
					attachment=jpeg
					image_preview=ImageTexture.create_from_image(image)
					preview.texture=image_preview
					preview.show()
		else:
			attachment=bytes
		if attachment.is_empty():_set_result("Could not load that file. Choose a supported image or WAV recording.",false)
		else:
			file_label.text=path.get_file()
			_set_result("File ready. Run the test to send it to OpenAI.",true)
	_update_actions()

func _set_result(message: String,success: bool) -> void:
	status.text=message
	status.add_theme_color_override("font_color",T.INK if success else T.ERROR)

func _run_test(connection: bool) -> void:
	if running:return
	running=true
	for index in TABS.size():tabs.set_tab_disabled(index,index!=tabs.current_tab)
	_update_actions()
	audio.stop()
	replay.hide()
	preview.visible=image_preview!=null
	_set_result("Waiting for OpenAI…",true)
	var result: Dictionary
	match CATEGORIES[tabs.current_tab]:
		"text":
			var input_text: String="Reply with the single word Ready." if connection else prompt.text
			result=await service.preview_setup_prompt(input_text,draft)
		"image":result=await service.respond_with_image(prompt.text,attachment,draft)
		"image_generation":result=await service.generate_image(prompt.text,draft)
		"tts":
			var delivery:={"instructions":"Keep the same voice. Perform the exact words with "+str(emotion.get_selected_metadata())+" emotional delivery."}
			result=await service.speak(prompt.text,draft,str(voice.get_selected_metadata()),delivery)
		"stt":
			var settings:=draft.duplicate(true)
			settings._transcription_progress=func(partial: String):
				if is_inside_tree():_set_result(partial,true)
			result=await service.transcribe_wav(attachment,settings)
	if not is_inside_tree():return
	running=false
	for index in TABS.size():tabs.set_tab_disabled(index,false)
	_update_actions()
	if not result.get("ok",false):
		_set_result(str(result.get("error","No response.")),false)
		return
	if result.has("signature"):on_verified.call(result.signature)
	if result.has("stream"):
		audio.stream=result.stream
		audio.play()
		replay.show()
		_set_result("Speech generated. "+voice.get_item_text(voice.selected),true)
	elif result.has("image"):
		preview.texture=ImageTexture.create_from_image(result.image)
		preview.show()
		_set_result("Image generated.",true)
	else:
		_set_result("Connection verified. Accept to use it in class." if connection else str(result.get("text","")),true)
