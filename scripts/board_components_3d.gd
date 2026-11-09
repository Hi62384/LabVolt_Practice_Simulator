extends Node3D
# Surface coordinates and recursive IDs are supplied by the existing canvas.
# Bodies are educational package art, not manufacturer dimension claims.
var signature := ""
var lights := {}
var battery_labels := {}
var actuators := {}
var elevations := {}
var native_lights := {}
var renderers := {}
var renderer_instances := {}
var breadboard_io_scale := 1.0
var enlarge_mounted_io := false
const SurfaceLayout = preload("res://scripts/pcb_design/surface_layout.gd")
const SILVER := Color("aeb5b8")

func board_point(point: Vector2,height: float=.032) -> Vector3:
 return Vector3((point.x/1000.-.5)*1.88,height,(point.y/440.-.5)*.78)

func label(text: String,pos: Vector3,height: float=.009) -> Label3D:
 var node := Label3D.new();node.text=text;node.font_size=40;node.pixel_size=height/40.
 node.position=pos;node.rotation.x=-PI/2;node.modulate=Color("e9eadc")
 node.outline_size=2;node.no_depth_test=false;add_child(node);return node

func update_models(game: Node,canvas: Control,result: Dictionary) -> void:
 var devices: Array=canvas.surface_devices()
 enlarge_mounted_io = bool(canvas.board.get("standalone",false))
 var next := str(devices)+str(canvas.board.get("definitions",{}))+str(breadboard_io_scale)+str(enlarge_mounted_io)
 if next!=signature:
  signature=next;battery_labels.clear();native_lights={};lights={};actuators={};elevations={};renderer_instances={}
  for child in get_children():remove_child(child);child.queue_free()
  build_packages(game,canvas)
  var catalog: Dictionary=preload("res://scripts/breadboard_model.gd").catalog(canvas.board)
  if io_support_available():
   catalog.merge(load("res://scripts/io_devices/catalog.gd").all(),false)
  for device in devices:
   var model: Dictionary=catalog.get(device.type,{})
   build_device(game,device,model)
 for id in battery_labels:
  var entry: Dictionary = battery_labels[id]
  if entry.has("source"):
   entry.label.text=preload("res://scripts/electronics/portable_sources.gd").readout(entry.source,canvas.board.get("controls",{}).get(id,{}))
   continue
  var charge := float(result.get("charge",{}).get(id,-1.0))
  entry.label.text = entry.voltage if charge < 0.0 else "%s · %d%%" % [entry.voltage, roundi(charge * 100.0)]
 for id in renderer_instances:
  var renderer: Node=renderer_instances[id]
  if renderer.has_method("update_solved"):renderer.update_solved(result,str(id))
 var states := {}
 if not actuators.is_empty():
  for device in preload("res://scripts/breadboard_model.gd").devices(canvas.board):states[device.id]=device.part
 for id in lights:
  var entry: Dictionary=lights[id]
  var current := maxf(0.,float(result.get("i",{}).get(id,0)))
  var active := current>0.0
  var strength := log(1.0+current/.006)
  var material: StandardMaterial3D=entry.mesh.material_override
  material.albedo_color=entry.color.darkened(.72).lerp(entry.color,1.0-exp(-strength))
  material.emission_enabled=active;material.emission=entry.color
  material.emission_energy_multiplier=2.5*strength
 for id in native_lights:
  var entry: Dictionary=native_lights[id];var runtime: Dictionary=canvas.device_states.get(id,{})
  var on: bool=runtime.get("powered",false) and float(runtime.get("outputs",{}).get(entry.pin,0))>.5
  var material: StandardMaterial3D=entry.mesh.material_override
  material.albedo_color=Color("f5bb4d") if on else Color("60482e");material.emission_enabled=on;material.emission=Color("f5bb4d")
 for id in actuators:
  var entry: Dictionary=actuators[id];var state: Dictionary=states.get(id,{}).duplicate(true)
  state.merge(canvas.board.get("controls",{}).get(id,{}),true)
  if entry.kind=="pot":entry.mesh.rotation.y=lerpf(-PI*.75,PI*.75,clampf(float(state.get("setting",.5)),0,1))
  elif entry.kind=="toggle":entry.mesh.rotation.x=-.4 if state.get("pressed",false) else .4
  else:entry.mesh.position.y=entry.rest-(.004 if state.get("pressed",false) else 0.)

func build_device(game: Node,device: Dictionary,model: Dictionary) -> void:
 var kind := str(model.get("kind",""));var pos := board_point(device.center)+Vector3(0,float(elevations.get(device.id,0)),0)
 var pins: Array=device.get("pins",[])
 if renderers.has(kind):
  var custom: Node3D=renderers[kind].build(game,self,device,model)
  if custom!=null:renderer_instances[str(device.id)]=custom
  return
 # Screens retain the live canvas pixels; no opaque decorative display covers them.
 if kind in ["spi_display","seven_segment","hd44780","ssd1306","ili9341","xpt2046","ws2812"] or kind.begins_with("io_"):return
 if kind=="native_controller" and not device.has("surface_size"):
  build_native(game,device,model);return
 var body := Node3D.new();body.position=pos;body.set_meta("device_id",str(device.id));add_child(body)
 var size := Vector3(.045,.019,.029)
 if kind=="controller":size=Vector3(.085,.012,.055)
 elif kind in ["speaker","buzzer","C","L","pot"]:size=Vector3(.038,.026,.038)
 elif kind=="bjt":size=Vector3(.025,.026,.021)
 elif kind=="LED":size=Vector3(.024,.025,.024)
 elif kind=="solar_panel":size=Vector3(.092,.012,.061)
 if pins.size()>=2:
  var delta := board_point(pins[1])-board_point(pins[0])
  body.rotation.y=-atan2(delta.z,delta.x)
 var prominent: bool = model.get("category","") in ["Input","Output"] or kind in ["variable_cap","variable_inductor","photodiode","speaker","buzzer"]
 if device.has("surface_size"):
  var footprint: Vector2 = device.surface_size
  var room := Vector2(footprint.x*1.88/1000.,footprint.y*.78/440.)*.87
  var angle := float(device.rotation)
  body.rotation.y = -angle
  if posmod(roundi(angle/(PI/2)),2) == 1: room = Vector2(room.y,room.x)
  body.scale = Vector3(minf(1,room.x/maxf(size.x,.03)),1,minf(1,room.y/maxf(size.z,.03)))
  if prominent and enlarge_mounted_io:
   body.scale *= breadboard_io_scale
  body.position.y = .015+float(elevations.get(device.id,0))+size.y*body.scale.y*.5
 elif prominent:
  body.scale = Vector3.ONE*breadboard_io_scale
  body.position.y += size.y*(breadboard_io_scale-1.0)*.5
 var dip: bool = pins.size() >= 8 and model.get("category") == "IC"
 if dip:
  var bounds := AABB()
  for pin in pins:
   var point := body.to_local(to_global(board_point(pin,pos.y)))
   bounds = AABB(point,Vector3.ZERO) if pin == pins[0] else bounds.expand(point)
  body.position += body.basis * bounds.get_center()
  size.x = bounds.size.x + .012
  size.z = maxf(.019,bounds.size.z - .009)
 # Each bent lead terminates at a distinct package edge, never the center.
 for index in pins.size():
  var base := board_point(pins[index],.015+float(elevations.get(device.id,0)))
  var local := body.to_local(to_global(base));var edge: Vector3
  if device.get("solar_footprint",false):edge=Vector3(clampf(local.x,-size.x*.5,size.x*.5),0,-size.z*.5)
  elif pins.size()==2:edge=Vector3((-1. if index==0 else 1.)*size.x*.5,0,0)
  elif dip:
   edge = Vector3(local.x,-.003,signf(local.z)*size.z*.5)
  else:
   edge=Vector3(clampf(local.x,-size.x*.5,size.x*.5),0,clampf(local.z,-size.z*.5,size.z*.5))
   if absf(local.x)/size.x>absf(local.z)/size.z:edge.x=signf(local.x)*size.x*.5
   else:edge.z=signf(local.z)*size.z*.5
  var tip := to_local(body.to_global(edge));var bend := Vector3(base.x,tip.y,base.z)
  if dip:
   game._line(self,base,bend,.0017,SILVER,.65)
   game._line(self,bend,tip,.0017,SILVER,.65)
  else:
   game._line(self,base,bend,.0013,SILVER,.65);game._line(self,bend,tip,.0013,SILVER,.65)
  var names: Array=model.get("pins",[])
  var pin_label := label(str(names[index]) if index<names.size() else str(index+1),base+Vector3(0,.009,.012),.007)
  pin_label.modulate=Color("293733")
  pin_label.set_meta("device_id",str(device.id));pin_label.set_meta("pin_index",index)
 if kind=="R" or kind=="D":
  var axial: MeshInstance3D=game._cylinder(body,Vector3.ZERO,.009,size.x,Color("bfa277") if kind=="R" else Color("24282c"));axial.rotation.z=PI/2
  if kind=="D":game._box(body,Vector3(.014,0,0),Vector3(.004,.019,.019),Color("d6d6cd"))
  if kind == "R":
   var bands := preload("res://scripts/electronics/component_shop_ui/resistor_bands.gd").bands(float(model.value),float(model.get("resistance_tolerance",.05)))
   for i in bands.size():
    var x := -.013 + i*.0057 + (.002 if i == bands.size()-1 else 0.0)
    var band: MeshInstance3D = game._cylinder(body,Vector3(x,0,0),.00925,.0022,Color(bands[i].color))
    band.rotation.z = PI/2
  label(str(model.get("name",device.type)),pos+Vector3(0,.019,-.019),.009)
 elif kind=="LED":
  game._cylinder(body,Vector3.ZERO,.013,.006,Color("3b332c"))
  var dome: MeshInstance3D=game._cylinder(body,Vector3(0,.009,0),.011,.022,Color("60332a"))
  dome.material_override=dome.material_override.duplicate()
  lights[device.id]={"mesh":dome,"color":Color(str(model.get("color","ff493c")))}
 elif kind in ["button","toggle","pot","variable_cap","variable_inductor","photodiode"]:
  game._box(body,Vector3.ZERO,size,Color("252c31"))
  var knob: MeshInstance3D=game._cylinder(body,Vector3(0,.02,0),.012,.018,Color("b5bac0") if kind=="pot" else Color("c34b42"))
  if kind=="pot":game._box(knob,Vector3(0,.01,-.006),Vector3(.003,.002,.009),Color("202328"))
  elif kind=="toggle":knob.scale=Vector3(.3,1.5,.3)
  actuators[device.id]={"mesh":knob,"kind":"pot" if kind in ["variable_cap","variable_inductor","photodiode"] else kind,"rest":knob.position.y}
 elif kind=="solar_panel":
  game._box(body,Vector3.ZERO,size,Color("243968"))
  for x in [-.024,0.0,.024]:game._box(body,Vector3(x,.007,0),Vector3(.001,.001,.059),Color("a4b6c7"))
 elif kind in ["C","L","polar_cap","buzzer","speaker"]:
  game._cylinder(body,Vector3(0,.008,0),size.x*.5,size.y,Color("264858") if kind in ["C","polar_cap"] else Color("332f2c"))
  if kind in ["speaker","buzzer"]:
   game._cylinder(body,Vector3(0,.023,0),size.x*.4,.003,Color("15191b"))
   for n in 3:game._box(body,Vector3((n-1)*.008,.026,0),Vector3(.002,.002,.022),Color("7b8181"))
  elif kind in ["C","polar_cap"]:label("+ C −" if kind=="polar_cap" else "C",pos+Vector3(0,.024,0),.011)
  else:
   for n in 5:game._box(body,Vector3((n-2)*.006,.023,0),Vector3(.003,.003,.026),Color("aa7043"))
 elif kind=="controller":
  game._box(body,Vector3.ZERO,size,Color("22634c"))
  game._box(body,Vector3(0,.012,0),Vector3(.025,.012,.025),Color("262b30"))
  label("LV MICRO · LV SCRIPT",pos+Vector3(0,.026,-.022),.009)
  # This is the supported educational six-pin board, not Arduino/Pico art.
  for pin in pins:game._cylinder(self,board_point(pin,.024+float(elevations.get(device.id,0))),.003,.015,Color("d3ad53"),.7)
 elif kind in ["V","portable_source"]:
  game._box(body,Vector3.ZERO,Vector3(.065,.026,.04),Color("476774"))
  var volts := preload("res://scripts/electronics/component_values/values.gd").format_value(float(model.value),"V")
  battery_labels[device.id] = {"voltage":volts,"label":label(volts,pos+Vector3(0,.019,0),.010)}
  if kind=="portable_source":battery_labels[device.id].source=model
 else:
  game._box(body,Vector3.ZERO,size,Color("292b30"))
  # Pin-one dot and package title follow catalog truth for educational ICs.
  game._cylinder(body,Vector3(-size.x*.32,.011,-size.z*.28),.003,.002,Color("d8c68d"))
  label(str(model.get("name",device.type)),body.position+Vector3(0,.018,0),.008)

# Optional PACKAGE CONTRACT v1. Metadata never changes electrical node mapping.
func package_rect(canvas: Control,part: Dictionary,definition: Dictionary) -> Rect2:
 if not definition.has("surface_layout") and not canvas.board.get("standalone",false) and ResourceLoader.exists("res://scripts/package_editor/package_geometry.gd"):
  var geometry=load("res://scripts/package_editor/package_geometry.gd")
  var placement: Dictionary=geometry.placement(part,definition)
  if placement.get("ok",false):
   var rect: Rect2i=placement.rect
   var letters: String=canvas.LETTERS
   if rect.position.y>=0 and rect.end.y<=letters.length():
    var a: Vector2=canvas.at(letters[rect.position.y]+str(rect.position.x+1))
    var b: Vector2=canvas.at(letters[rect.end.y-1]+str(rect.end.x))
    return Rect2(a-Vector2(8,8)*canvas.zoom,b-a+Vector2(16,16)*canvas.zoom)
 return canvas.pcb_rect(part,definition)

func package_layers(canvas: Control) -> Array:
 var layers: Array=[]
 for part in canvas.board.get("parts",[]):
  var bp: Dictionary=canvas.board.get("definitions",{}).get(part.type,{})
  if bp.has("layout") and bp.has("footprint"):_package_layer(canvas,bp,package_rect(canvas,part,bp),"board/"+str(part.id)+"/",0.,layers,0,canvas._surface_mounting(part,bp))
 return layers

func _package_layer(canvas: Control,bp: Dictionary,rect: Rect2,prefix: String,base: float,layers: Array,depth: int,mounting := 0) -> void:
 if depth>=8:return
 var pcb: bool=bp.get("package","IC")=="PCB"
 var height := preload("res://scripts/pcb_design/substrate.gd").standalone_height(bp) if pcb and canvas.board.get("standalone",false) and depth==0 else float(bp.footprint.get("thickness_mm" if pcb else "body_height_mm",0))*.001
 layers.append({"bp":bp,"rect":rect,"prefix":prefix,"base":base,"height":height})
 for child in bp.layout.parts:
  if not SurfaceLayout.visible(bp,str(child.id)):continue
  var id := prefix+str(child.id);elevations[id]=base+height
  if str(child.type).begins_with("ic:"):
   var inner: Dictionary=canvas.board.get("definitions",{}).get(child.type,{})
   if inner.has("layout") and inner.has("footprint"):_package_layer(canvas,inner,canvas._nested_rect(child,bp.layout,rect,bp,mounting),id+"/",base+height,layers,depth+1)

func build_packages(game: Node,canvas: Control) -> void:
 for layer in package_layers(canvas):
  var bp: Dictionary=layer.bp;var rect: Rect2=layer.rect;var center := board_point(rect.get_center(),.015+float(layer.base))
  var size := Vector3(rect.size.x/1000.*1.88,float(layer.height),rect.size.y/440.*.78)
  if size.y>0:
   game._box(self,center+Vector3(0,size.y*.5,0),size,Color(str(bp.footprint.get("color","303b40"))))
   # Lift the live canvas texture with the substrate, including genuine displays.
   var face := MeshInstance3D.new();var plane := PlaneMesh.new();plane.size=Vector2(size.x,size.z);face.mesh=plane
   face.position=center+Vector3(0,size.y+.0005,0)
   var mat := StandardMaterial3D.new();mat.albedo_texture=canvas.get_viewport().get_texture();mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
   mat.uv1_scale=Vector3(rect.size.x/1000.,rect.size.y/440.,1);mat.uv1_offset=Vector3(rect.position.x/1000.,rect.position.y/440.,0)
   face.material_override=mat;add_child(face)
  var top := .017+float(layer.base)+size.y
  var marking := str(bp.get("marking",""))
  if not marking.is_empty():label(marking,board_point(rect.position+Vector2(rect.size.x*.5,24),top),.011)
  var marker := str(bp.get("orientation_marker","dot"))
  # Absent metadata preserves the legacy flat canvas; explicit marker opts in.
  if bp.has("orientation_marker") and marker!="none":
   var point := board_point(rect.position+Vector2(10,10),top)
   if marker=="dot":game._cylinder(self,point,.004,.001,Color("e4dab3"))
   elif marker=="notch":game._box(self,point,Vector3(.018,.002,.005),Color("d5c69b"))
   else:
    game._line(self,point+Vector3(-.005,0,.005),point+Vector3(0,0,-.005),.001,Color("e4dab3"))
    game._line(self,point+Vector3(0,0,-.005),point+Vector3(.005,0,.005),.001,Color("e4dab3"))
    game._line(self,point+Vector3(.005,0,.005),point+Vector3(-.005,0,.005),.001,Color("e4dab3"))

# Optional renderer adapters build(game,parent,device,model)->Node3D. The adapter
# owns parenting and may implement update_solved(result,device_id). Surface
# device coordinates/IDs remain unchanged; the adapter must honor elevations.
func register_renderer(kind: String,adapter: Object) -> void:
 renderers[kind]=adapter;signature=""

func io_support_available() -> bool:
 for file in ["catalog.gd","physical_surface.gd","surface.gd","controls.gd"]:
  if not ResourceLoader.exists("res://scripts/io_devices/"+file):return false
 return true

func build_native(game: Node,device: Dictionary,model: Dictionary) -> void:
 var pins: Array=device.pins
 if pins.is_empty():return
 var rect := Rect2(Vector2(pins[0]),Vector2.ONE)
 for pin in pins:rect=rect.expand(Vector2(pin))
 rect=rect.grow(8)
 var level := .04+float(elevations.get(device.id,0))
 var center := board_point(rect.get_center(),level)
 var size := Vector3(maxf(.08,rect.size.x/1000.*1.88),.009,maxf(.055,rect.size.y/440.*.78))
 var body := Node3D.new();body.position=center;body.set_meta("device_id",str(device.id));add_child(body)
 game._box(body,Vector3.ZERO,size,Color("2866a2") if model.board=="nano" else Color("237c91") if model.board=="uno" else Color("288160"))
 game._box(body,Vector3(0,.012,0),Vector3(.035,.015,.035),Color("17252b"))
 game._box(body,Vector3(-size.x*.5,.016,0),Vector3(.025,.024,.032),Color("a9b5b9"),.7)
 if model.board=="uno":game._cylinder(body,Vector3(-size.x*.35,.015,size.z*.25),.012,.025,Color("1c2329"))
 for index in pins.size():
  var point := board_point(Vector2(pins[index]),level+.01)
  game._box(self,point,Vector3(.015,.014,.015),Color("1b2529"))
  if model.board=="uno":game._box(self,point+Vector3(0,.008,0),Vector3(.007,.002,.007),Color("b4a16d"),.6)
  else:game._box(self,point+Vector3(0,.01,0),Vector3(.004,.023,.004),Color("d4ba78"),.7)
  var pin_label := label(str(model.pins[index]),point+Vector3(0,.014,.012 if point.z<center.z else -.012),.007)
  pin_label.set_meta("pin_index",index);pin_label.set_meta("device_id",str(device.id))
 label(str(model.name),center+Vector3(0,.016,size.z*.28),.012)
 var led: MeshInstance3D=game._box(body,Vector3(size.x*.25,.011,0),Vector3(.008,.004,.006),Color("60482e"))
 native_lights[device.id]={"mesh":led,"pin":"D13" if model.board in ["uno","nano"] else "GP25"}
