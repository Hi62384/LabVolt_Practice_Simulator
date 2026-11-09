extends Node3D
var drawing: Control
var view: SubViewport
var drawn_board := {}
var drawn_epoch := -1
var drawn_currents := {}
var drawn_firmware := {}
var drawn_charge := {}
var controls: Node3D
var station_index := 0
var layout_signature := ""
var audio: Node3D
var game: Node
var external_ports := {}
var component_models: Node3D
# Optional IO surfaces are presentation only; host input requests use existing APIs.
signal io_command_requested(station: int,device_id: String,command: Dictionary)
var io_views := {}
var io_retiring := {}
var io_root: Node3D
var io_interact_enabled := true
var forward_io_commands := true
var io_held := false
var held_owner := 0
var display_scale := 1.0
var standalone_pcb := false
var portable_kit_board := false
var portable_shell: MeshInstance3D
var socket_face: MeshInstance3D
var jumper_models: Node3D
var socket_layout := ""
var jumper_layout := {}

var io_allowed := false
var io_catalog := {}
var io_pointer_positions := {}
var board_epoch := 0
var legacy_substrate_nodes: Array=[]
var board_hit: StaticBody3D
var lead_hole_marker: MeshInstance3D
var outline_hit_key := ""
var pcb_bounds := AABB()
const PcbSubstrate = preload("res://scripts/pcb_design/substrate.gd")
var presented_board: Dictionary
var presented_result: Dictionary
var presented_firmware: Dictionary
var presented := false
var presented_held := false
var presented_visible := false
func build(owner_game: Node,index: int) -> void:
 game=owner_game
 audio=preload("res://scripts/circuit_audio.gd").new();add_child(audio)
 component_models=preload("res://scripts/pcb_design/routed_components.gd").new();add_child(component_models)
 station_index=index;controls=Node3D.new();add_child(controls)
 io_root=Node3D.new();add_child(io_root)
 if component_models.io_support_available():
  io_catalog=load("res://scripts/io_devices/catalog.gd").surfaces()
 position=game.dc_lab.board_home(index)
 portable_shell=game._box(self,Vector3.ZERO,Vector3.ONE,Color("e6e1c9"))
 portable_shell.mesh=BoxMesh.new()
 portable_shell.hide()
 socket_face=MeshInstance3D.new();socket_face.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;add_child(socket_face)
 jumper_models=Node3D.new();add_child(jumper_models)
 game._box(self,Vector3.ZERO,Vector3(1.9,.025,.8),Color("e6e1c9"))
 # Raised rim and feet preserve the original board surface/hit coordinates.
 for side in [-1.,1.]:
  game._box(self,Vector3(side*.948,.004,0),Vector3(.008,.022,.8),Color("b9b5a5"))
  for end in [-1.,1.]:game._box(self,Vector3(side*.8,-.019,end*.29),Vector3(.1,.014,.07),Color("343a3b"))
 for child in get_children():
  if child is MeshInstance3D and child!=portable_shell and child!=socket_face:
   legacy_substrate_nodes.append(child)
 view=SubViewport.new();view.size=Vector2i(1000,440);view.transparent_bg=false;view.render_target_update_mode=SubViewport.UPDATE_DISABLED;add_child(view)
 drawing=preload("res://scripts/breadboard_canvas.gd").new();view.add_child(drawing);drawing.custom_minimum_size=Vector2.ZERO;drawing.size=Vector2(1000,440);drawing.mouse_filter=Control.MOUSE_FILTER_IGNORE;drawing.set_process(false)
 var surface := MeshInstance3D.new();var plane := PlaneMesh.new();plane.size=Vector2(1.88,.78);surface.mesh=plane;surface.position.y=.014
 var surface_material := StandardMaterial3D.new();surface_material.albedo_texture=view.get_texture();surface_material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;surface_material.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR;surface_material.cull_mode=BaseMaterial3D.CULL_DISABLED;surface.material_override=surface_material;surface.set_meta("role","board_canvas");add_child(surface)
 var body := StaticBody3D.new();body.collision_layer=4;body.collision_mask=0;add_child(body);board_hit=body
 var hit := CollisionShape3D.new();var shape := BoxShape3D.new();shape.size=Vector3(1.9,.06,.8);hit.shape=shape;body.add_child(hit)
 body.set_meta("role","dc_board");body.set_meta("dc_station",index);body.set_meta("label","Left click: pick up board · Right click: use board")
func suspend_presentation() -> void:
 if not visible:return
 hide()
 audio.update_circuit({}, {})
 held_owner=0
 board_hit.collision_layer=0
 for control in controls.get_children():control.collision_layer=0
 presented=false

func update_state(state: Dictionary) -> void:
 var next_epoch := int(state.get("board_epoch",0))
 var epoch_changed := next_epoch!=board_epoch
 if epoch_changed:
  for entry in io_views.values():_discard_io(entry)
  for entry in io_retiring.values():_discard_io(entry)
  io_views={};io_retiring={};io_pointer_positions={};board_epoch=next_epoch
 var held: bool=state.get("board_held",false)
 var board: Dictionary=state.get("board",{})
 standalone_pcb=board.get("standalone",false)
 portable_kit_board=not standalone_pcb and not str(board.get("authority_kit_id","")).is_empty()
 display_scale=.20 if portable_kit_board or (standalone_pcb and board.get("authority_kit_id","existing_kit")=="") else 1.0
 portable_shell.visible=not standalone_pcb
 socket_face.visible=not standalone_pcb
 jumper_models.visible=not standalone_pcb
 drawing.physical_surface=portable_kit_board
 io_held=held
 held_owner = int(state.get("board_owner",0)) if held else 0
 if held:_position_in_hand()
 else:
  position=state.get("board_position",Vector3.ZERO)
  if position==Vector3.ZERO:position=game.dc_lab.board_home(station_index)
  rotation=Vector3(0,float(state.get("board_rotation",0)),0)
  scale=Vector3.ONE*display_scale
 visible=not state.get("board",{}).is_empty() and not state.get("board_stowed",false)
 var result: Dictionary=state.get("result",{})
 var firmware: Dictionary=state.get("firmware",{})
 # Host and interest snapshots replace these dictionaries. The compressed
 # legacy route merges only the outer state, replacing changed fields.
 if presented and not epoch_changed and presented_held==held and presented_visible==visible and is_same(presented_board,board) and is_same(presented_result,result) and is_same(presented_firmware,firmware):
  return
 presented=true
 presented_held=held
 presented_visible=visible
 presented_board=board
 presented_result=result
 presented_firmware=firmware
 audio.update_circuit(board if visible else {},result)
 var elevated := false
 var placed: Dictionary=state.get("board",{})
 if placed.get("standalone",false) and placed.get("parts",[]).size()==1:
  var definition: Dictionary=placed.get("definitions",{}).get(placed.parts[0].type,{})
  elevated=definition.get("package","")=="PCB" and definition.has("footprint")
 drawing.physical_pcb_surface=elevated
 for child in get_children():
  if child.get_meta("role","")=="board_canvas":child.visible=standalone_pcb and not elevated
 for child in get_children():
  if child is StaticBody3D:child.collision_layer=4 if visible and not held else 0
 controls.visible=visible
 for control in controls.get_children():control.collision_layer=4 if visible and not held else 0
 if not visible:
  if board.is_empty():drawn_epoch=-1
  for id in io_views.keys():_retire_io(str(id))
  _present_retiring(state)
  _update_io_interactivity()
  return
 var currents: Dictionary=result.get("i",{})
 var charge := {}
 for id in result.get("charge",{}):charge[id]=roundi(float(result.charge[id])*100.0)
 # The host advances the epoch for design edits. Lab lead holes can move
 # independently of the design, while input state only updates the devices.
 var layout_changed: bool = drawn_epoch!=next_epoch or drawn_board.get("ports",[])!=board.get("ports",[])
 if not layout_changed and drawn_board==board and drawn_currents==currents and drawn_firmware==firmware and drawn_charge==charge:
  sync_io_surfaces(state)
  return
 drawn_epoch=next_epoch
 drawn_board=board;drawn_currents=currents;drawn_firmware=firmware;drawn_charge=charge
 drawing.device_states=firmware;drawing.board=board;drawing.currents=currents
 if layout_changed:
  # The socket mesh keeps this transform between simulation updates.
  var board_extent: Vector2 = drawing.board_extent()
  drawing.zoom=minf(1.0,minf(422.0/board_extent.y,940.0/(35+int(board.rows)*23)))
  drawing.pan=Vector2.ZERO
  if not standalone_pcb:
   var extent: Vector2 = board_extent*drawing.zoom
   drawing.pan=(Vector2(1000,440)-extent)*.5-Vector2(8,12)*drawing.zoom
   var dimensions := Vector3(extent.x*1.88/1000.,.075,extent.y*.78/440.)
   portable_shell.position.y=.013-dimensions.y*.5
   (portable_shell.mesh as BoxMesh).size=dimensions
   portable_shell.ignore_occlusion_culling=true
   var collision: CollisionShape3D=board_hit.get_child(0)
   var shape := BoxShape3D.new();shape.size=dimensions
   collision.shape=shape;collision.position=portable_shell.position
 if not standalone_pcb:
  if layout_changed:_update_breadboard_geometry()
  view.render_target_update_mode=SubViewport.UPDATE_DISABLED
 elif layout_changed or not elevated:
  drawing.queue_redraw()
  view.render_target_update_mode=SubViewport.UPDATE_ONCE
 component_models.breadboard_io_scale=1.65
 component_models.update_models(game,drawing,result)
 if layout_changed:sync_outline_hit();rebuild_controls()
 for device in drawing.surface_devices():
  if audio.voices.has(device.id):audio.voices[device.id].position=component_models.board_point(device.center,.06)
 sync_io_surfaces(state)

func _update_breadboard_geometry() -> void:
 var board: Dictionary=drawing.board
 var key := "%d:%s" % [int(board.rows),str(board.get("expanded",false))]
 if socket_layout!=key:
  socket_layout=key
  var surface := SurfaceTool.new()
  surface.begin(Mesh.PRIMITIVE_TRIANGLES)
  var letters: String = drawing.hole_letters()
  for letter in letters:
   var rail: bool = letter in "PNWXYZ"
   var stripe := Color("b45249") if letter in "PWY" else Color("467ca0")
   for column in range(1,int(board.rows)+1):
    var center: Vector3=component_models.board_point(drawing.at(letter+str(column)),.014)
    var radius: float=.010*drawing.zoom
    _socket_quad(surface,center,Vector2.ONE*radius*1.38,Color("a7aaa0"))
    _socket_quad(surface,center+Vector3.UP*.001,Vector2.ONE*radius,Color("343c3f"))
    if rail and column<int(board.rows) and column!=int(board.rows)/2:
     var next: Vector3=component_models.board_point(drawing.at(letter+str(column+1)),.014)
     _socket_quad(surface,(center+next)*.5-Vector3(0,0,.013*drawing.zoom),Vector2((next.x-center.x)*.5,.0026),stripe)
  for pair in [["E","F"],["O","Q"]] if board.get("expanded",false) else [["E","F"]]:
   var a: Vector3=component_models.board_point(drawing.at(pair[0]+"1"),.014)
   var b: Vector3=component_models.board_point(drawing.at(pair[1]+str(board.rows)),.014)
   _socket_quad(surface,(a+b)*.5,Vector2((b.x-a.x)*.5+.019,.010*drawing.zoom),Color("9a9d90"))
  var material := StandardMaterial3D.new()
  material.vertex_color_use_as_albedo=true
  material.cull_mode=BaseMaterial3D.CULL_DISABLED
  socket_face.mesh=surface.commit()
  socket_face.material_override=material
 var next_jumpers := {"layout":key,"wires":board.wires,"colors":board.get("wire_colors",{})}
 if jumper_layout==next_jumpers:return
 jumper_layout=next_jumpers
 for child in jumper_models.get_children():
  jumper_models.remove_child(child);child.queue_free()
 var model := preload("res://scripts/breadboard_model.gd")
 var cable := preload("res://scripts/cable_mesh.gd")
 for wire in board.wires:
  var a: Vector3=component_models.board_point(drawing.at(wire[0]),.016)
  var b: Vector3=component_models.board_point(drawing.at(wire[1]),.016)
  var points: Array[Vector3]=[]
  for i in 9:
   var t := i/8.0
   points.append(a.lerp(b,t)+Vector3.UP*sin(PI*t)*.053)
  var mesh := MeshInstance3D.new()
  mesh.mesh=cable.tube(points)
  mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
  mesh.material_override=cable.jacket_material(Color.from_string(str(jumper_layout.colors.get(model.wire_key(wire),"e3ab5c")),Color("e3ab5c")))
  jumper_models.add_child(mesh)

func _socket_quad(surface: SurfaceTool, center: Vector3, half: Vector2, color: Color) -> void:
 var a := center+Vector3(-half.x,0,-half.y)
 var b := center+Vector3(half.x,0,-half.y)
 var c := center+Vector3(half.x,0,half.y)
 var d := center+Vector3(-half.x,0,half.y)
 for point in [a,b,c,a,c,d]:
  surface.set_color(color)
  surface.set_normal(Vector3.UP)
  surface.add_vertex(point)

func hole_at_world(point: Vector3) -> String:
 var local := to_local(point)
 var pixel := (Vector2(local.x/1.88,local.z/.78)+Vector2(.5,.5))*Vector2(1000,440)
 return drawing.nearest_hole(pixel)

func pcb_port_at_world(point: Vector3) -> String:
 var local := to_local(point)
 var nearest := ""
 var best := .065*.065
 for port in external_ports:
  var pin: Vector3 = external_ports[port]
  var distance := Vector2(local.x-pin.x,local.z-pin.z).length_squared()
  if distance >= best:continue
  nearest = port
  best = distance
 return nearest

func cable_bounds() -> AABB:
 if not visible or io_held:return AABB()
 if standalone_pcb:return global_transform*pcb_bounds
 return portable_shell.global_transform*portable_shell.get_aabb()

func show_lead_hole(hole: String) -> void:
 if hole.is_empty():
  if is_instance_valid(lead_hole_marker):lead_hole_marker.hide()
  return
 if not is_instance_valid(lead_hole_marker):
  lead_hole_marker=MeshInstance3D.new()
  var ring := TorusMesh.new()
  ring.inner_radius=.011
  ring.outer_radius=.018
  ring.rings=16
  ring.ring_segments=6
  lead_hole_marker.mesh=ring
  lead_hole_marker.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
  var material := StandardMaterial3D.new()
  material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
  material.albedo_color=Color("64f8c4")
  lead_hole_marker.material_override=material
  add_child(lead_hole_marker)
 if standalone_pcb:
  lead_hole_marker.position=external_ports[hole]+Vector3.UP*.004
  lead_hole_marker.scale=Vector3.ONE*1.4
 else:
  lead_hole_marker.position=component_models.board_point(drawing.at(hole),.021)
  lead_hole_marker.scale=Vector3.ONE*drawing.zoom
 lead_hole_marker.show()

func rebuild_controls() -> void:
 var next := str(drawing.board)
 if next==layout_signature:return
 layout_signature=next;external_ports={}
 if not drawing.board.get("standalone",false):
  var mapped: Array=drawing.board.get("ports",[])
  for i in mini(4,mapped.size()):
   if preload("res://scripts/breadboard_model.gd").valid_hole(drawing.board,str(mapped[i])):
    external_ports["B%d"%(i+1)]=component_models.board_point(drawing.at(mapped[i]),.014)
 for old in controls.get_children():controls.remove_child(old);old.queue_free()
 if drawing.board.get("standalone",false):
  var part: Dictionary=drawing.board.parts[0];var definition: Dictionary=drawing.board.definitions[part.type]
  var top := .015+PcbSubstrate.standalone_height(definition)
  for i in part.pins.size():
   var point: Vector2=drawing.at(part.pins[i]);var socket := StaticBody3D.new();socket.collision_layer=4;socket.collision_mask=0
   socket.position=component_models.board_point(point,top);controls.add_child(socket)
   var pin: Dictionary=definition.pins[i]
   var connector := Node3D.new()
   connector.scale=Vector3(2.6,2.6,2.6)
   socket.add_child(connector)
   var seat := build_connector(connector,pin)*connector.scale.y
   var shape := CollisionShape3D.new();var sphere := SphereShape3D.new();sphere.radius=.030;shape.shape=sphere;shape.position.y=seat*.7+.006;socket.add_child(shape)
   var port := "X%d" % (i+1)
   var pin_name := str(pin.get("name","")).strip_edges()
   socket.set_meta("role","dc_port")
   socket.set_meta("dc_station",station_index)
   socket.set_meta("dc_port",port)
   socket.set_meta("label",port if pin_name.is_empty() else "%s · %s" % [port,pin_name])
   socket.set_meta("pin_id",connector.get_meta("pin_id"))
   socket.set_meta("electrical_role",connector.get_meta("electrical_role"))
   external_ports[port]=socket.position+Vector3.UP*seat
   var pin_label=component_models.label(str(pin.name),socket.position+Vector3(0,.002,.045),.018)
   pin_label.set_meta("external_pin_index",i)
 if not drawing.board.get("standalone",false):
  for part in drawing.board.get("parts",[]):
   var bp: Dictionary=drawing.board.get("definitions",{}).get(part.type,{})
   if not bp.has("footprint"):continue
   var pins: Array=preload("res://scripts/breadboard_model.gd").pins(part)
   for index in mini(pins.size(),bp.get("pins",[]).size()):
    var holder := Node3D.new();component_models.add_child(holder)
    holder.position=component_models.board_point(drawing.at(pins[index]),.03)
    build_connector(holder,bp.pins[index])
 for part in drawing.exposed_controls():
  var middle: Vector2=part.center
  var control := StaticBody3D.new();control.collision_layer=0 if io_held else 4;control.collision_mask=0
  control.position=component_models.board_point(middle,.05+float(component_models.elevations.get(part.id,0)))
  controls.add_child(control)
  var collision := CollisionShape3D.new();var box := BoxShape3D.new();box.size=Vector3(.075,.045,.065)
  if part.type not in ["lv_mcu","native_uno","native_pico","native_nano"]:
   box.size=Vector3(.090,.083,.082)
   control.position.y+=.006
  var footprint: Vector2 = part.get("surface_size",Vector2.ZERO)
  if footprint != Vector2.ZERO:
   var footprint_scale := 1.65 if standalone_pcb else 1.0
   box.size.x = clampf(footprint.x*1.88/1000.*footprint_scale,.032,.09)
   box.size.z = clampf(footprint.y*.78/440.*footprint_scale,.032,.082)
  collision.shape=box;control.add_child(collision)
  control.set_meta("role","dc_code" if part.type in ["lv_mcu","native_uno","native_pico","native_nano"] else "dc_input");control.set_meta("dc_station",station_index);control.set_meta("part_id",str(part.id))
  control.set_meta("input_type",str(part.type))
  if control.get_meta("role")=="dc_code":
   control.set_meta("label","Open programming editor")
  elif part.type=="button":
   control.set_meta("label","Hold click or Interact to press")
  elif part.type=="toggle":
   control.set_meta("label","Click to toggle switch")
  elif part.type=="battery_generator":
   control.set_meta("label","Click to change waveform")
  elif part.type=="battery_generator_adjustable":
   control.set_meta("label","Click for waveform · Scroll for voltage · Shift+scroll for frequency")
  elif part.type=="battery_adjustable":
   control.set_meta("label","Scroll to adjust DC voltage")
  else:
   control.set_meta("label","Scroll to adjust · Left click +5% · Right click −5%")

func build_connector(socket: Node3D,pin: Dictionary) -> float:
 var type := str(pin.get("connector","male_header"))
 socket.set_meta("pin_id",str(pin.get("id","")));socket.set_meta("electrical_role",str(pin.get("role","unspecified")))
 if type=="terminal_block":
  game._box(socket,Vector3.ZERO,Vector3(.03,.025,.025),Color("337c56"))
  game._cylinder(socket,Vector3(0,.014,0),.007,.003,Color("aeb5b8"),.65)
  return .016
 elif type=="female_header":
  game._box(socket,Vector3.ZERO,Vector3(.018,.015,.018),Color("262c2e"))
  game._box(socket,Vector3(0,.008,0),Vector3(.008,.001,.008),Color("090b0d"))
  return .009
 elif type in ["test_point","test_pad"]:
  game._cylinder(socket,Vector3.ZERO,.009,.004,Color("d4b75f"),.7)
  return .003
 elif type=="through_hole":
  var ring := MeshInstance3D.new();var torus := TorusMesh.new();torus.inner_radius=.004;torus.outer_radius=.007;torus.rings=12;torus.ring_segments=8;ring.mesh=torus
  var mat := StandardMaterial3D.new();mat.albedo_color=Color("d4b75f");mat.metallic=.7;ring.material_override=mat;socket.add_child(ring)
  ring.position.y=.002
  game._cylinder(socket,Vector3(0,.001,0),.004,.002,Color("222828"))
  return .004
 else:
  game._box(socket,Vector3.ZERO,Vector3(.014,.008,.014),Color("262c2e"))
  game._box(socket,Vector3(0,.012,0),Vector3(.004,.02,.004),Color("d4b75f"),.7)
  return .022

func sync_io_surfaces(state: Dictionary) -> void:
 if io_catalog.is_empty():return
 var devices: Array=drawing.surface_devices() # Preserves recursive PCB/exposed-IC eligibility.
 var active := {}
 for device in devices:
  var model: Dictionary=io_catalog.get(str(device.type),{})
  if device.type in ["spi_display","seven_segment"]:
   model={"kind":device.type,"category":"Output"}
  if model.is_empty():continue
  var id := str(device.id);var kind := str(model.kind);active[id]=true
  if io_views.has(id) and str(io_views[id].kind)!=kind:
   # Old controls no longer exist electrically after replacement under one ID.
   _discard_io(io_views[id]);io_views.erase(id);io_pointer_positions.erase(id)
  if io_retiring.has(id):
   if str(io_retiring[id].kind)==kind:io_views[id]=io_retiring[id];io_views[id].view.visible=true
   else:_discard_io(io_retiring[id])
   io_retiring.erase(id)
  if not io_views.has(id):
   var adapter: Node3D=load("res://scripts/io_devices/physical_surface.gd").new()
   io_root.add_child(adapter)
   var token := str(adapter.get_instance_id())
   adapter.command_requested.connect(_io_command.bind(id,board_epoch,token))
   var entry := {"view":adapter,"kind":kind,"collider":null,"token":token}
   if model.get("category","")=="Input":
    var body := StaticBody3D.new();body.collision_layer=0;body.collision_mask=0;body.position.y=.004;adapter.add_child(body)
    var hit := CollisionShape3D.new();var shape := BoxShape3D.new();shape.size=Vector3(.08,.008,.08);hit.shape=shape;body.add_child(hit)
    body.set_meta("role","dc_io");body.set_meta("dc_station",station_index);body.set_meta("part_id",id)
    body.set_meta("input_type",kind);body.set_meta("io_board",self)
    body.set_meta("label",str(model.get("name",kind))+" · operate wired input")
    entry.collider=body
   io_views[id]=entry
  var entry: Dictionary=io_views[id]
  var adapter: Node3D=entry.view
  adapter.position=component_models.board_point(device.center,.045+float(component_models.elevations.get(id,0)))
  var extent := .12
  for other in devices:
   if str(other.id)==id:continue
   var distance: float=component_models.board_point(device.center).distance_to(component_models.board_point(other.center))
   extent=minf(extent,maxf(.024,distance*.7))
  adapter.scale=Vector3(extent/.08,1,extent/.08)
  var pins: Array=device.get("pins",[])
  if pins.size()>=2:
   var delta: Vector3=component_models.board_point(pins[1])-component_models.board_point(pins[0])
   adapter.rotation.y=-atan2(delta.z,delta.x)
  var live: Dictionary=state.get("firmware",{}).get(id,{})
  if kind=="seven_segment":
   var currents: Dictionary=state.get("result",{}).get("i",{})
   var levels: Array=[]
   for segment in 8:levels.append(clampf(float(currents.get("%s/%d" % [id,segment],0.0))/.01,0,1))
   live={"levels":levels}
  adapter.present(kind,live,_io_control(state,id,live))
  if is_instance_valid(entry.collider):
   var hit: CollisionShape3D=entry.collider.get_child(0)
   var shape := hit.shape as BoxShape3D
   var dimensions := Vector3(adapter.physical_size.x,.008,adapter.physical_size.y)
   if shape.size!=dimensions:shape.size=dimensions
  if device.has("surface_size"):
   var footprint: Vector2 = device.surface_size
   var room := Vector2(footprint.x*1.88/1000.,footprint.y*.78/440.)*.90
   var angle := float(device.rotation)
   adapter.rotation.y = -angle
   if posmod(roundi(angle/(PI/2)),2) == 1: room = Vector2(room.y,room.x)
   if standalone_pcb:
    room *= 1.35
   adapter.scale = Vector3(room.x/adapter.physical_size.x,1,room.y/adapter.physical_size.y)
 for id in io_views.keys():
  if not active.has(id):_retire_io(str(id))
 _present_retiring(state)
 _update_io_interactivity()

func _io_control(state: Dictionary,id: String,live: Dictionary) -> Dictionary:
 var control: Dictionary=live.get("control",{}).duplicate(true)
 control.merge(state.get("board",{}).get("io_controls",{}).get(id,{}),true)
 if not control.has("revision"):control.revision=0
 return control

func _io_command(command: Dictionary,id: String,epoch: int,token := "") -> void:
 io_command_requested.emit(station_index,id,command.duplicate(true))
 if forward_io_commands and is_instance_valid(game):
  var lab=game.get("dc_lab")
  if is_instance_valid(lab) and lab.has_method("request"):
   lab.request(station_index,{"op":"input","id":id,"command":command.duplicate(true),"board_epoch":epoch,"view_token":token})

func _retire_io(id: String) -> void:
 if not io_views.has(id):return
 var entry: Dictionary=io_views[id]
 # Retain the adapter's pending release until a host ack/revision pumps it.
 # Collision and visible surface disappear immediately, independently of ack.
 entry.view.set_interact(false);entry.view.visible=false
 if is_instance_valid(entry.collider):entry.collider.collision_layer=0
 io_retiring[id]=entry;io_views.erase(id);io_pointer_positions.erase(id)

func _present_retiring(state: Dictionary) -> void:
 for id in io_retiring:
  var entry: Dictionary=io_retiring[id];var live: Dictionary=state.get("firmware",{}).get(id,{})
  entry.view.present(str(entry.kind),live,_io_control(state,str(id),live))
 _prune_retiring()

func _prune_retiring() -> void:
 for id in io_retiring.keys():
  var entry: Dictionary=io_retiring[id]
  if entry.view.surface.awaiting_revision<0 and entry.view.surface.pending.is_empty():
   _discard_io(entry);io_retiring.erase(id)

func _discard_io(entry: Dictionary) -> void:
 if is_instance_valid(entry.view):
  if is_instance_valid(entry.collider):entry.collider.collision_layer=0
  entry.view.get_parent().remove_child(entry.view);entry.view.queue_free()

# Core calls this on success AND rejection; unchanged snapshots are not acks.
func acknowledge_io(id: String,control: Dictionary,token := "") -> void:
 var entry: Dictionary=io_views.get(id,io_retiring.get(id,{}))
 if token!="" and str(entry.get("token",""))!=token:return
 if not entry.is_empty():entry.view.acknowledge(control)

func set_io_interact(enabled: bool) -> void:
 io_interact_enabled=enabled;_update_io_interactivity()

func _update_io_interactivity() -> void:
 var enabled := visible and not io_held and io_interact_enabled
 if is_instance_valid(game):
  var player=game.get("player")
  if is_instance_valid(player):enabled=enabled and bool(player.get("enabled"))
 io_allowed=enabled
 for entry in io_views.values():
  # Only input surfaces capture gestures. Outputs still receive host publications.
  var input: bool=is_instance_valid(entry.collider)
  if entry.view.surface.interact!=(enabled and input):entry.view.set_interact(enabled and input)
  if input:entry.collider.collision_layer=4 if enabled else 0

func release_io_capture(id: String="") -> void:
 for key in io_views:
  if id=="" or id==str(key):io_views[key].view.release_capture()

func io_pointer(id: String,world_hit: Vector3,pressed: bool) -> bool:
 if not io_views.has(id):return false
 var adapter: Node3D=io_views[id].view
 if not pressed:adapter.pointer_event(adapter.to_local(world_hit),false);return true
 if not io_allowed or not is_instance_valid(io_views[id].collider):return false
 io_pointer_positions[id]=adapter.to_local(world_hit)
 adapter.pointer_event(io_pointer_positions[id],true);return true

func io_pointer_motion(id: String,world_hit: Vector3,relative_pixels: Vector2) -> bool:
 if not io_allowed or not io_views.has(id) or not is_instance_valid(io_views[id].collider):return false
 var adapter: Node3D=io_views[id].view
 io_pointer_positions[id]=adapter.to_local(world_hit)
 adapter.pointer_motion(io_pointer_positions[id],relative_pixels);return true

func io_turn(id: String,steps: int) -> bool:
 if not io_allowed or not io_views.has(id) or io_views[id].kind!="io_encoder":return false
 io_views[id].view.turn(steps);return true

func io_press_switch(id: String,pressed: bool) -> bool:
 if not io_views.has(id) or io_views[id].kind!="io_joystick" or (pressed and not io_allowed):return false
 io_views[id].view.press_switch(pressed);return true

func _position_in_hand() -> void:
 var local := held_owner==multiplayer.get_unique_id()
 var pose: Dictionary=game.session.poses.get(held_owner,{})
 var orientation: Basis=game.camera.global_basis if local else Basis(Vector3.UP,float(pose.get("yaw",0.0)))
 orientation*=Basis(Vector3.RIGHT,.35)
 var fallback: Vector3=game.camera.to_global(Vector3(.37,-.27,-.59)) if local else pose.get("position",Vector3.ZERO)+Vector3(0,1.2,0)
 var hand: Vector3=game.held_item_position(held_owner,fallback)
 if standalone_pcb:
  orientation*=Basis(Vector3.FORWARD,-.32)
  var center := pcb_bounds.get_center() if pcb_bounds.has_volume() else Vector3.ZERO
  var edge := Vector3(pcb_bounds.end.x if pcb_bounds.has_volume() else .91,center.y,center.z)*display_scale
  var grip := hand-orientation.x*.035-orientation.y*.025
  var origin := grip-orientation*edge
  if local:
   var camera: Camera3D=game.camera
   var board_center := origin+orientation*(center*display_scale)
   var depth := -camera.to_local(board_center).z
   var screen := camera.get_viewport().get_visible_rect()
   var safe := Rect2(screen.position+screen.size*Vector2(.12,.15),screen.size*Vector2(.76,.59))
   var point := camera.unproject_position(board_center) if depth>.25 else screen.position+screen.size*Vector2(.68,.68)
   var visible_center := camera.project_position(point.clamp(safe.position,safe.end),maxf(depth,.42))
   origin+=visible_center-board_center
  global_transform=Transform3D(orientation.scaled(Vector3.ONE*display_scale),origin)
  return
 if portable_kit_board:
  orientation*=Basis(Vector3.FORWARD,-.24)
  var grip_edge := Vector3((portable_shell.mesh as BoxMesh).size.x*.5,0,.10)*display_scale
  var grip := hand-orientation.z*.12+orientation.y*.025 if local else hand
  global_transform=Transform3D(orientation.scaled(Vector3.ONE*display_scale),grip-orientation*grip_edge)
  return
 global_transform=Transform3D(orientation.scaled(Vector3.ONE*display_scale),hand-orientation*Vector3(.12,0,.08)*display_scale)

func _process(_delta: float) -> void:
 if held_owner!=0:_position_in_hand()
 _update_io_interactivity()
 # Drain queued releases even when the authoritative snapshot has not changed.
 for entry in io_views.values():entry.view.surface.pump()
 for entry in io_retiring.values():entry.view.surface.pump()
 _prune_retiring()


# Captured mouse motion can drive a virtual pointer without rotating the camera.
func io_drag(id: String,relative_pixels: Vector2) -> bool:
 if not io_allowed or not io_views.has(id) or not io_pointer_positions.has(id):return false
 var local: Vector3=io_pointer_positions[id]
 var dimensions: Vector2=io_views[id].view.physical_size
 local.x=clampf(local.x+relative_pixels.x*dimensions.x/256.,-dimensions.x*.499,dimensions.x*.499)
 local.z=clampf(local.z-relative_pixels.y*dimensions.y/256.,-dimensions.y*.499,dimensions.y*.499)
 return io_pointer_motion(id,io_views[id].view.to_global(local),relative_pixels)

func sync_outline_hit() -> void:
 var bp: Dictionary={}
 if drawing.board.get("standalone",false) and drawing.board.get("parts",[]).size()==1:
  bp=drawing.board.get("definitions",{}).get(drawing.board.parts[0].type,{})
 var routed: bool=preload("res://scripts/pcb_design/design.gd").active(bp)
 for node in legacy_substrate_nodes:
  if is_instance_valid(node):node.visible=standalone_pcb and not bp.has("footprint") and display_scale==1.0
 var key := "pcb:"+str(bp.get("pcb_design",{}))+str(bp.get("footprint",{})) if standalone_pcb else ("portable" if portable_kit_board else "legacy")
 if key==outline_hit_key or not is_instance_valid(board_hit):return
 outline_hit_key=key
 var collision: CollisionShape3D=board_hit.get_child(0)
 if routed:
  collision.position=Vector3.ZERO
  var rect: Rect2=drawing.pcb_rect(drawing.board.parts[0],bp)
  var mesh=PcbSubstrate.mesh(bp,rect,.015,.015+PcbSubstrate.standalone_height(bp))
  pcb_bounds=mesh.get_aabb()
  var shape:=ConcavePolygonShape3D.new();shape.backface_collision=true
  shape.set_faces(mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]);collision.shape=shape
 elif standalone_pcb:
  var rect: Rect2=drawing.pcb_rect(drawing.board.parts[0],bp)
  var height := PcbSubstrate.standalone_height(bp)
  var dimensions := Vector3(rect.size.x*1.88/1000.,height,rect.size.y*.78/440.)
  collision.position=component_models.board_point(rect.get_center(),.015+height*.5)
  var shape:=BoxShape3D.new();shape.size=dimensions;collision.shape=shape
  pcb_bounds=AABB(collision.position-dimensions*.5,dimensions)
