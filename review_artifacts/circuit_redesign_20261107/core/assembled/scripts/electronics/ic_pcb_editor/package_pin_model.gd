extends RefCounted
const Geometry=preload("res://scripts/package_editor/package_geometry.gd")
const Board=preload("res://scripts/breadboard_model.gd")
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
		for col in "PNABCDEFGHIJ":
			var hole:=col+str(row)
			if Board.node(hole,int(design.rows))==node:return hole
	return ""

func set_pin(index: int,changes: Dictionary) -> bool:
	if index<0 or index>=pins.size():return false
	var before:=pins[index].duplicate(true)
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
	var old_pins:=pins.duplicate(true);var old_footprint:=draft.footprint.duplicate(true)
	var width:=int(draft.footprint.width);var height:=int(draft.footprint.height)
	draft.footprint.width=height;draft.footprint.height=width
	for pin in pins:
		var old: Dictionary=pin.position
		pin.position={"x":height-1-int(old.y),"y":int(old.x)}
	if validate()!="":pins=old_pins;draft.footprint=old_footprint;return false
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
	var options:={"name":str(draft.get("name","")),"description":str(draft.get("description","")),"package":str(draft.package),"footprint":draft.footprint.duplicate(true),"marking":str(draft.get("marking","")),"orientation_marker":str(draft.get("orientation_marker","dot")),"exposed":draft.get("exposed",[]).duplicate(true)}
	return preload("res://scripts/package_editor/package_store.gd").save_package(profile,options,pins.duplicate(true))
