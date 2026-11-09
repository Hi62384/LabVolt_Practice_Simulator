extends VBoxContainer
const Board=preload("res://scripts/breadboard_model.gd")
const Schema=preload("res://scripts/inventory_authority/firmware_schema.gd")
const Document=preload("res://scripts/firmware_backends/program_document.gd")
var ui: Node
var device := ""
var kit_id := ""
var editor: Control
var refresh_left := 0.0
func build(studio: Node) -> void:
 ui=studio;kit_id=str(ui.profile.data.equipped)
 var picker := OptionButton.new();add_child(picker)
 for entry in Board.devices(ui.profile.data.kits[kit_id].board):
  if entry.part.type in ["native_uno","native_pico","native_nano"]:
   picker.add_item(("Nano classic" if entry.part.type=="native_nano" else "Uno R3" if entry.part.type=="native_uno" else "Pico")+" · "+str(entry.id).trim_prefix("board/"));picker.set_item_metadata(picker.item_count-1,{"id":entry.id,"board":str(entry.part.type).trim_prefix("native_")})
 if picker.item_count==0:
  ui.label(self,"Add an Arduino Uno or Raspberry Pi Pico from Components to your kit, then place it on the board.");return
 picker.item_selected.connect(func(index):select(picker.get_item_metadata(index)))
 select(picker.get_item_metadata(0))
func select(choice: Dictionary) -> void:
 device=str(choice.id)
 if is_instance_valid(editor):remove_child(editor);editor.queue_free()
 var design: Dictionary=ui.profile.data.kits[kit_id].board
 var program: Dictionary=design.get("programs",{}).get(device,{})
 var source_part := {}
 for entry in Board.devices(design):
  if entry.id==device:source_part=entry.part;break
 var firmware: Dictionary=program.get("native_firmware",source_part.get("native_firmware",{}))
 var sources: Dictionary=program.get("native_sources",source_part.get("native_sources",{}))
 editor=preload("res://scripts/firmware_backends/native_ide.gd").new();add_child(editor);editor.build(choice.board,firmware,sources)
 var selected_id := device
 var selected_editor := editor
 editor.draft_requested.connect(func(files):
  if not Schema.files(files,false):selected_editor.status.text="Invalid source files";return
  var before: Dictionary=ui.profile.data.duplicate(true)
  var design_now: Dictionary=ui.profile.data.kits[kit_id].board
  if not design_now.get("programs") is Dictionary:design_now.programs={}
  var record: Dictionary=design_now.programs.get(selected_id,{}).duplicate(true)
  record.native_sources=files.duplicate(true);design_now.programs[selected_id]=record
  if ui.profile.save()!=OK:ui.profile.data=before;selected_editor.status.text="Could not save source draft";return
  selected_editor.status.text="Source draft saved; compiled image unchanged."
 )
 editor.save_requested.connect(func(image,files):save_program(selected_id,selected_editor,image,files,false))
 editor.upload_requested.connect(func(image,files):save_program(selected_id,selected_editor,image,files,true))
 editor.control_requested.connect(func(controls):
  if not live_owner():selected_editor.status.text="Deploy your board at a DC bench before operating its CPU";return
  if controls.has("run"):
   var before: Dictionary=ui.profile.data.duplicate(true)
   var design_now: Dictionary=ui.profile.data.kits[kit_id].board
   if not design_now.get("programs") is Dictionary:design_now.programs={}
   var record: Dictionary=design_now.programs.get(selected_id,{}).duplicate(true)
   record.run=bool(controls.run);design_now.programs[selected_id]=record
   if ui.profile.save()!=OK:ui.profile.data=before;selected_editor.status.text="Could not save run state";return
  ui.game.dc_lab.request(ui.bench,{"op":"native_control","id":selected_id,"board_epoch":int(ui.game.dc_lab.states[ui.bench].board_epoch),"controls":controls})
 )
func save_program(id: String,target: Control,image: Dictionary,files: Dictionary,upload: bool) -> void:
 var check := Document.validate(str(target.board),image,files,upload and live_owner())
 if not check.ok:target.status.text=check.error;return
 var before: Dictionary=ui.profile.data.duplicate(true)
 Document.store(ui.profile.data.kits[kit_id].board,id,image,files)
 if ui.profile.save()!=OK:ui.profile.data=before;target.status.text="Could not save the program";return
 if upload and live_owner():
  if not ui.game.dc_lab.has_method("upload_native"):target.status.text="Saved. This host lacks the native upload adapter.";return
  ui.game.dc_lab.upload_native(ui.bench,id,image,files)
  target.status.text="Saved; upload sent. Runtime state below confirms host execution."
 else:target.status.text="Saved in your kit. Deploy this board at a DC bench to run it."
func live_owner() -> bool:
 return is_instance_valid(ui) and ui.bench>=0 and ui.bench<ui.game.dc_lab.states.size() and ui.game.dc_lab.states[ui.bench].get("board_owner",0)==multiplayer.get_unique_id()
func _process(delta: float) -> void:
 refresh_left-=delta
 if refresh_left>0:return
 refresh_left=.1
 if not is_instance_valid(editor):return
 if ui.bench<0 or ui.bench>=ui.game.dc_lab.states.size():editor.set_snapshot({"status":"Not deployed"});return
 var snapshot: Dictionary=ui.game.dc_lab.states[ui.bench].get("firmware",{}).get(device,{})
 if not snapshot.is_empty():editor.set_snapshot(snapshot)
