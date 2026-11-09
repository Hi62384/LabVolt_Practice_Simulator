extends RefCounted
const Geometry=preload("res://scripts/package_editor/package_geometry.gd")
const Board=preload("res://scripts/breadboard_model.gd")
const Store=preload("res://scripts/package_editor/package_store.gd")
var design: Dictionary
var draft: Dictionary
var pins: Array=[]
var error: String=""

func open(board: Dictionary,package_draft: Dictionary,kind: String) -> void:
	design=board.duplicate(true);draft=package_draft.duplicate(true);draft.package=kind
	if not draft.has("footprint"):draft.footprint={"width":8,"height":6,"color":"24775b","body_height_mm":3.0,"thickness_mm":1.6}
	pins=draft.get("pins",[]).duplicate(true)
	if pins.is_empty():
		for i in 4:
			pins.append({"id":"pin_%d"%(i+1),"name":"Pin %d"%(i+1),"hole":str(design.ports[i]),"role":"unspecified","connector":"male_header","position":{"x":i%2,"y":0 if i<2 else int(draft.footprint.height)-1}})
	else:
		for i in pins.size():
			if not pins[i].has("id"):pins[i].id="pin_%d"%(i+1)
			if not pins[i].has("hole"):
				pins[i].hole=_hole_for_node(str(pins[i].get("node","")))
			if not pins[i].has("position"):
				pins[i].position={"x":i%int(draft.footprint.width),"y":0 if i<pins.size()/2 else int(draft.footprint.height)-1}
	validate()

func _hole_for_node(node: String) -> String:
	for row in range(1,int(design.rows)+1):
		for col in Board.hole_letters(design):
			var hole:=col+str(row)
			if Board.node(hole,int(design.rows))==node:return hole
	return ""

func set_pin(index: int,changes: Dictionary) -> bool:
	if index<0 or index>=pins.size():return false
	var before: Dictionary=pins[index].duplicate(true)
	for key in changes:pins[index][key]=changes[key]
	if validate()!="":pins[index]=before;return false
	return true

func add_pin(point: Vector2i) -> bool:
	if pins.size()>=Geometry.MAX_PINS:error="Maximum 64 pins";return false
	var used:={}
	for pin in pins:used[str(pin.id)]=true
	var n:=1
	while used.has("pin_"+str(n)):n+=1
	var hole:=str(design.ports[mini(pins.size(),3)])
	pins.append({"id":"pin_"+str(n),"name":"Pin "+str(n),"hole":hole,"role":"unspecified","connector":"male_header","position":{"x":point.x,"y":point.y}})
	if validate()!="":pins.pop_back();return false
	return true

func remove_pin(index: int) -> bool:
	if pins.size()<=1:error="Keep at least one pin";return false
	if index<0 or index>=pins.size():return false
	pins.remove_at(index);return validate()==""

func rotate() -> bool:
	var old_pins:=pins.duplicate(true);var old_footprint: Dictionary=draft.footprint.duplicate(true)
	var width:=int(draft.footprint.width);var height:=int(draft.footprint.height)
	draft.footprint.width=height;draft.footprint.height=width
	for pin in pins:
		var old: Dictionary=pin.position
		pin.position={"x":height-1-int(old.y),"y":int(old.x)}
	if validate()!="":pins=old_pins;draft.footprint=old_footprint;return false
	return true

func apply_layout(layout: int, spacing: int) -> bool:
	var width := int(draft.footprint.width)
	var height := int(draft.footprint.height)
	spacing = maxi(1, spacing)
	var points: Array[Vector2i] = []
	if layout == 0:
		var half := ceili(pins.size() / 2.0)
		for row in [0, height - 1]:
			for pin in (half if row == 0 else pins.size() - half):
				var x := pin * spacing
				if x < width: points.append(Vector2i(x,row))
	elif layout == 1:
		for x in range(0, width, spacing):
			points.append(Vector2i(x, 0))
	else:
		var edge: Array[Vector2i] = []
		for x in width:edge.append(Vector2i(x, 0))
		for y in range(1, height):edge.append(Vector2i(width - 1, y))
		for x in range(width - 2, -1, -1):edge.append(Vector2i(x, height - 1))
		for y in range(height - 2, 0, -1):edge.append(Vector2i(0, y))
		for i in range(0, edge.size(), spacing):
			if edge[i].distance_to(edge[0]) >= spacing or i == 0:
				points.append(edge[i])
	if points.size() < pins.size():
		error = "This layout fits %d of %d pins. Increase the footprint or reduce spacing." % [points.size(), pins.size()]
		return false
	for i in pins.size():
		pins[i].position = {"x":points[i].x, "y":points[i].y}
	error = ""
	return true

func validate() -> String:
	if pins.size()<1 or pins.size()>Geometry.MAX_PINS:error="Use 1–64 pins";return error
	var bp:={"package":draft.package,"footprint":draft.footprint,"pins":pins,"marking":draft.get("marking",""),"orientation_marker":draft.get("orientation_marker","dot")}
	error=Geometry.validate(bp)
	if error!="":return error
	for pin in pins:
		if Board.node(str(pin.get("hole","")),int(design.rows))=="":error="Each pin needs a valid internal breadboard hole";return error
	return ""

func save(profile: RefCounted) -> String:
	if profile.data.kits[profile.data.equipped].board!=design:return "Source circuit changed; reopen the package editor before saving."
	if validate()!="":return error
	var options := draft.duplicate(true)
	options.erase("pins")
	return Store.save_package(profile,options,pins.duplicate(true))

func validate_package(profile: RefCounted) -> String:
	if validate() != "":return error
	return str(Store.prepare_package(profile, draft, pins).get("error", ""))

func save_draft(profile: RefCounted, copy_name := "") -> String:
	var data: Dictionary = profile.data
	if not data.get("pending_trade", {}).is_empty():return "Finish the pending trade first."
	var kit: Dictionary = data.kits[data.equipped]
	if kit.board != design:return "The source circuit changed. Reopen the package editor."
	var before := data.duplicate(true)
	if not copy_name.is_empty():
		var id := "package_" + Crypto.new().generate_random_bytes(8).hex_encode()
		kit = kit.duplicate(true)
		kit.name = copy_name
		data.kits[id] = kit
		data.equipped = id
	kit.package_draft = draft.duplicate(true)
	kit.package_draft.pins = pins.duplicate(true)
	if profile.save() != OK:
		profile.data = before
		return "Save failed. The draft is still open."
	return "Draft saved: " + str(kit.get("name", "Current project"))
