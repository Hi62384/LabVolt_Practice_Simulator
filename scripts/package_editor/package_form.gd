extends VBoxContainer
const Chrome = preload("res://scripts/ui/circuit_editor_panels/chrome.gd")
signal saved(message: String)
const Geometry=preload("res://scripts/package_editor/package_geometry.gd")
const Board=preload("res://scripts/breadboard_model.gd")
var rows: Array=[]
func text_field(parent: Node,value: String,width: int,limit: int) -> LineEdit:
	var field := LineEdit.new();field.text=value;field.max_length=limit;field.custom_minimum_size.x=width;parent.add_child(field);return field
func spin(parent: Node,title: String,value: float,minimum: float,maximum: float,step_size := 1.0) -> SpinBox:
	var field := SpinBox.new();field.min_value=minimum;field.max_value=maximum;field.step=step_size;field.value=value;field.custom_minimum_size.x=90;parent.add_child(field);Chrome.labeled(field,title);return field
func option(parent: Node,values: Array,value: String) -> OptionButton:
	var field := OptionButton.new()
	for entry in values:field.add_item(str(entry))
	field.select(maxi(0,values.find(value)));parent.add_child(field);return field
func note(value: String) -> void:
	var label := Label.new();label.text=value;label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;add_child(label)
func action(parent: Node,title: String,callback: Callable) -> void:
	Chrome.action(parent,title,callback)
func build(profile: RefCounted,draft: Dictionary) -> void:
	Chrome.setup(self)
	Chrome.heading(self,"Circuit package", "Define its body, exposed controls and stable external pin map.", "chip")
	var design: Dictionary=profile.data.kits[profile.data.equipped].board
	var kind := option(self,["IC","PCB"],str(draft.get("package","IC")))
	note("Footprint: width × length in 2.54 mm grid positions. Oversized PCBs use standalone mounting. Physical height/thickness is in mm.")
	var dimensions := HFlowContainer.new();add_child(dimensions)
	var width := spin(dimensions,"Width",draft.get("footprint",{}).get("width",8),2,80)
	var length := spin(dimensions,"Length",draft.get("footprint",{}).get("height",6),2,80)
	var body_height := spin(dimensions,"IC height mm",draft.get("footprint",{}).get("body_height_mm",3),.1,100,.1)
	var thickness := spin(dimensions,"PCB thickness mm",draft.get("footprint",{}).get("thickness_mm",1.6),.1,100,.1)
	var color := ColorPickerButton.new();color.color=Color(draft.get("footprint",{}).get("color","24775b"));color.custom_minimum_size=Vector2(60,32);dimensions.add_child(color)
	var title := text_field(self,str(draft.get("name","")),300,40);title.placeholder_text="Circuit name"
	var description := text_field(self,str(draft.get("description","")),300,1000);description.placeholder_text="Description"
	var marking := text_field(self,str(draft.get("marking","")),300,80);marking.placeholder_text="Surface marking"
	var marker := option(self,["dot","notch","triangle","none"],str(draft.get("orientation_marker","dot")))
	Chrome.labeled(kind,"Package type")
	Chrome.labeled(title,"Circuit name")
	Chrome.labeled(description,"Description")
	Chrome.labeled(marking,"Surface marking")
	Chrome.labeled(marker,"Orientation marker")
	Chrome.labeled(color,"Body color")
	Chrome.section(self,"Body and identity", "chip", kind.get_parent(), marker.get_parent())
	var exposed: Array=draft.get("exposed",[]).duplicate()
	var exposed_start := get_child_count()
	note("Expose individual IC surface devices. A PCB always displays every installed component. Edit the circuit layout in the designer.")
	for part in design.parts:
		if part.type not in ["button","toggle","pot10k","led","led_green","led_blue","led_yellow","seven_segment","spi_display","lv_mcu","buzzer","speaker"] and not str(part.type).begins_with("ic:") and not str(part.type).begins_with("io_"):continue
		var toggle := CheckButton.new();toggle.text="Expose "+str(part.id)+" · "+str(profile.catalog().get(part.type,{}).get("name",part.type));toggle.button_pressed=str(part.id) in exposed;add_child(toggle)
		toggle.disabled=kind.text=="PCB"
		kind.item_selected.connect(func(_i):toggle.disabled=kind.text=="PCB")
		toggle.toggled.connect(func(on):
			if on and str(part.id) not in exposed:exposed.append(str(part.id))
			elif not on:exposed.erase(str(part.id))
		)
	Chrome.section(self,"Surface controls", "switch", get_child(exposed_start), get_child(get_child_count()-1))
	var tools := HFlowContainer.new();add_child(tools)
	var count := spin(tools,"Pins (bounded to 64)",draft.get("pins",[0,0,0,0]).size(),1,Geometry.MAX_PINS)
	var physical := CheckButton.new();physical.text="Explicit grid positions";physical.button_pressed=draft.is_empty() or Geometry.explicit_pins(draft);tools.add_child(physical)
	var pitch := spin(tools,"Pin pitch (grid)",1,1,20)
	note("Each row defines an electrical node and a physical connector. Grid x/y starts at zero; spacing is an integer grid multiple. Role labels do not change electrical behavior. ↑/↓ reorders external X pin numbering while retaining stable IDs.")
	var list := VBoxContainer.new();add_child(list)
	for index in Geometry.MAX_PINS:
		var old: Dictionary=draft.get("pins",[])[index] if index<draft.get("pins",[]).size() else {}
		var pin_card := PanelContainer.new();pin_card.theme_type_variation="CardPanel";pin_card.visible=index<int(count.value);list.add_child(pin_card)
		var row := HFlowContainer.new();pin_card.add_child(row)
		var number := Label.new();number.text="X%d"%(index+1);row.add_child(number)
		var hole := str(design.ports[index]) if index<4 else "A"+str(index%int(design.rows)+1)
		if old.has("node"):
			for r in range(1,int(design.rows)+1):
				for col in Board.hole_letters(design):
					if Board.node(col+str(r),int(design.rows))==str(old.node):hole=col+str(r)
		var fields := {"id":str(old.get("id","pin_%d"%(index+1))),"name":text_field(row,str(old.get("name","Pin %d"%(index+1))),135,24),"hole":text_field(row,hole,55,3)}
		fields.role=option(row,Geometry.ROLES,str(old.get("role","unspecified")))
		fields.connector=option(row,Geometry.CONNECTORS,str(old.get("connector","male_header")))
		var half := ceili(count.value/2.)
		fields.x=spin(row,"x",old.get("position",{}).get("x",index%maxi(1,half)),0,79)
		fields.y=spin(row,"y",old.get("position",{}).get("y",0 if index<half else int(length.value)-1),0,79)
		Chrome.labeled(fields.name,"Pin name")
		Chrome.labeled(fields.hole,"Board hole")
		Chrome.labeled(fields.role,"Electrical role")
		Chrome.labeled(fields.connector,"Connector")
		rows.append(fields)
		action(row,"Move pin up",func():swap(index,index-1,int(count.value)))
		action(row,"Move pin down",func():swap(index,index+1,int(count.value)))
	count.value_changed.connect(func(value):
		for index in Geometry.MAX_PINS:list.get_child(index).visible=index<int(value)
	)
	action(tools,"Generate two header rows",func():
		var half := ceili(count.value/2.)
		for index in int(count.value):rows[index].x.value=(index%half)*int(pitch.value);rows[index].y.value=0 if index<half else int(length.value)-1
	)
	Chrome.section(self,"External pins", "circuit", tools, list)
	var result := Label.new();result.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;result.text="Ready to validate and save package.";add_child(result)
	Chrome.finish(self)
	action(self,"Save circuit package",func():
		var pin_map: Array=[]
		for index in int(count.value):
			var fields: Dictionary=rows[index]
			var pin := {"id":fields.id,"name":fields.name.text.strip_edges(),"hole":fields.hole.text.strip_edges().to_upper(),"role":fields.role.text,"connector":fields.connector.text}
			if physical.button_pressed:pin.position={"x":int(fields.x.value),"y":int(fields.y.value)}
			pin_map.append(pin)
		var options := {"name":title.text.strip_edges(),"description":description.text,"package":kind.text,"exposed":exposed,"marking":marking.text,"orientation_marker":marker.text,"footprint":{"width":int(width.value),"height":int(length.value),"color":color.color.to_html(false),"body_height_mm":body_height.value,"thickness_mm":thickness.value}}
		var message: String=preload("res://scripts/package_editor/package_store.gd").save_package(profile,options,pin_map)
		result.text=message
		saved.emit(message)
	)
func values(fields: Dictionary) -> Dictionary:
	return {"id":fields.id,"name":fields.name.text,"hole":fields.hole.text,"role":fields.role.selected,"connector":fields.connector.selected,"x":fields.x.value,"y":fields.y.value}
func fill(fields: Dictionary,value: Dictionary) -> void:
	fields.id=value.id;fields.name.text=value.name;fields.hole.text=value.hole;fields.role.select(value.role);fields.connector.select(value.connector);fields.x.value=value.x;fields.y.value=value.y
func swap(a: int,b: int,count: int) -> void:
	if a<0 or b<0 or a>=count or b>=count:return
	var first := values(rows[a]);fill(rows[a],values(rows[b]));fill(rows[b],first)
