extends SceneTree
const Query = preload("res://scripts/electronics/inventory_value_search/query.gd")
const Selection = preload("res://scripts/electronics/inventory_value_search/selection.gd")

func _initialize() -> void:
	var catalog := {
		"r1": {"name":"1 Ω resistor","kind":"R","value":1.0,"unit":"Ω","rating":"¼ W","rarity":"Common"},
		"r2": {"name":"2 Ω resistor","kind":"R","value":2.0,"unit":"Ω","rating":"½ W","rarity":"Rare"},
		"r3": {"name":"3 Ω resistor","kind":"R","value":3.0,"unit":"Ω","rating":"1 W","rarity":"Common"},
		"c1": {"name":"Capacitor","kind":"C","value":1e-6,"unit":"F","rating":"50 V","rarity":"Common"}}
	var desc := {"r1":{"family":"R","value":1.0,"unit":"Ω"},"r2":{"family":"R","value":2.0,"unit":"Ω"},"r3":{"family":"R","value":3.0,"unit":"Ω"},"c1":{"family":"C","value":1e-6,"unit":"F"}}
	var profile := {"inventory":{"r1":3,"r2":2,"r3":1,"c1":7},"component_instances":{
		"unit-a":{"type":"r1"},"unit-b":{"type":"r1"},"unit-c":{"type":"r2"}}}
	var found := Query.search(profile,catalog,desc,"R",2.0)
	assert(found.error=="" and found.rows.size()==6)
	assert(found.rows[0].type=="r2" and found.rows[0].instance_id=="unit-c")
	assert(found.rows[1].type=="r2" and found.rows[1].instance_id=="")
	assert(found.rows[0].distance==0.0 and found.rows[1].distance==0.0)
	assert(found.rows[2].type=="r1" and found.rows[3].type=="r1" and found.rows[4].type=="r1")
	assert(found.rows[4].quantity==1)
	assert(found.rows[5].type=="r3")
	assert(Query.search(profile,catalog,desc,"R").rows[0].type=="r1")
	assert(Query.search(profile,catalog,desc,"R",INF).error!="")
	assert(Query.search(profile,catalog,desc,"R",0.0,{"counts":{"r1":2},"instance_ids":["unit-a"]}).rows.size()==4)
	assert(Query.search(profile,catalog,desc,"R",0.0,{}, {"r3":1}).rows.size()==1)
	assert(Query.search_owned(profile,catalog,"R","2 Ω").rows[0].type=="r2")
	assert(Query.search_owned(profile,catalog,"R","0").rows[0].type=="r1")
	assert(Query.search_owned(profile,catalog,"C","1 µF").rows[0].type=="c1")
	assert(Query.search_owned(profile,catalog,"R","bogus").error!="")
	var fractional := {"a":{"name":"A","kind":"C","value":1e-9,"unit":"F"},"b":{"name":"B","kind":"C","value":2e-9,"unit":"F"}}
	assert(Query.search_owned({"inventory":{"a":1,"b":1},"component_instances":{}},fractional,"C","1.5 nF").rows.size()==2)
	var huge := {"a":{"name":"A","kind":"R","value":1e9,"unit":"Ω"},"b":{"name":"B","kind":"R","value":9e8,"unit":"Ω"}}
	assert(Query.search_owned({"inventory":{"a":1,"b":1},"component_instances":{}},huge,"R","900 MΩ").rows[0].type=="b")
	var picker := Selection.new();picker.refresh(found.rows)
	assert(picker.choose("r2","unit-c"))
	var board := {"parts":[{"id":"new","type":"r2"}],"instance_ids":{}}
	assert(picker.bind_new_parts(board,{"parts":[]})=="")
	assert(board.instance_ids.new=="unit-c")
	assert(picker.bind_new_parts(board,board)=="")
	var repeated := {"parts":[{"id":"new","type":"r2"},{"id":"other","type":"r2"}],"instance_ids":{"new":"unit-c"}}
	assert(picker.bind_new_parts(repeated,board)!="")
	assert(repeated.instance_ids.size()==1)
	var after := Query.search({"inventory":{"r2":1},"component_instances":{}},catalog,desc,"R")
	picker.refresh(after.rows)
	assert(picker.current().is_empty())
	print("PASS: owned stock, identity, canonical distance, ties, reservations, kit limits, search parsing and binding")
	quit()
