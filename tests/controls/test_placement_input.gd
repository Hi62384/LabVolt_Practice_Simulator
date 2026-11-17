extends SceneTree

const Routing = preload("res://scripts/campus/items/placement_input.gd")

func _initialize() -> void:
	var keys := {"place_item":KEY_F,"inspect":KEY_I}
	assert(Routing.action(_key(KEY_F),keys,true,true,true,false,false)=="place")
	assert(Routing.action(_key(KEY_I),keys,true,true,true,false,false)=="inspect")
	assert(Routing.action(_key(KEY_F),keys,true,true,true,true,false)=="")
	assert(Routing.action(_key(KEY_I),keys,true,true,true,true,false)=="inspect")
	assert(Routing.action(_key(KEY_F),keys,true,true,true,false,true)=="")
	assert(Routing.action(_key(KEY_F),keys,false,true,true,false,false)=="")
	assert(Routing.action(_key(KEY_F),keys,true,false,true,false,false)=="")
	assert(Routing.action(_key(KEY_F),keys,true,true,false,false,false)=="")
	var repeated:=_key(KEY_F);repeated.echo=true
	assert(Routing.action(repeated,keys,true,true,true,false,false)=="")
	var released:=_key(KEY_F);released.pressed=false
	assert(Routing.action(released,keys,true,true,true,false,false)=="")
	assert(Routing.action(_key(KEY_G),keys,true,true,true,false,false)=="")
	assert(Routing.action(InputEventMouseButton.new(),keys,true,true,true,false,false)=="")
	keys.place_item=KEY_J
	assert(Routing.action(_key(KEY_F),keys,true,true,true,false,false)=="")
	assert(Routing.action(_key(KEY_J),keys,true,true,true,false,false)=="place")
	print("PLACEMENT_INPUT PASS")
	quit(0)

func _key(code: int) -> InputEventKey:
	var event:=InputEventKey.new()
	event.keycode=code
	event.physical_keycode=code
	event.pressed=true
	return event
