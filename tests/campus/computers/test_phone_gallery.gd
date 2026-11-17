extends SceneTree
const Photos=preload("res://scripts/campus/phones/photo_library.gd")
const PhoneService=preload("res://scripts/campus/phones/phone_service.gd")
const Tiers=preload("res://scripts/campus/phones/phone_tiers.gd")
class FakeProfile extends Node:
	var data: Dictionary={}
class FakeElectronics extends Node:
	var profile: FakeProfile
class FakeSchool extends Node:
	var local_identity: String=""
class FakeHotbar extends Node:
	var active:=0
	var slots: Array=[{"kind":"smartphone","id":""}]
class FakeGame extends Node:
	var electronics: FakeElectronics
	var school: FakeSchool
	var hotbar: FakeHotbar

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var owner: String="e".repeat(48)
	var phone_id: String=Crypto.new().generate_random_bytes(16).hex_encode()
	var ids: Array[String]=[]
	var image:=Image.create(1024,576,false,Image.FORMAT_RGB8)
	image.fill(Color("56a6bb"))
	var ok:=true
	for index in 8:
		var saved: Dictionary=Photos.capture(owner,phone_id,image,Tiers.TIERS.premium.storage_bytes)
		if not saved.has("id"):ok=false;break
		ids.append(str(saved.id))
	var service=PhoneService.new()
	service.set_process(false)
	root.add_child(service)
	service.set_process(false)
	var game:=FakeGame.new();service.game=game
	game.electronics=FakeElectronics.new();game.add_child(game.electronics)
	game.electronics.profile=FakeProfile.new();game.electronics.add_child(game.electronics.profile)
	game.electronics.profile.data={"dorm":{"owner":owner,"smartphones":{},"carry_items":["phone:"+phone_id]}}
	game.electronics.profile.data.dorm.smartphones[phone_id]={"tier":"premium","location":"hotbar"}
	game.school=FakeSchool.new();game.school.local_identity=owner;game.add_child(game.school)
	game.hotbar=FakeHotbar.new();game.hotbar.slots[0].id=phone_id;game.add_child(game.hotbar)
	service.current_id=phone_id
	service.status=Label.new();service.add_child(service.status)
	service.content=VBoxContainer.new();service.add_child(service.content)
	ok=ok and service.selected()==phone_id
	if ok:
		service._gallery({"tier":"premium"})
		var previews: Array=service.content.get_children().filter(func(child):return child is TextureRect)
		ok=previews.size()==6
		for preview in previews:
			ok=ok and preview.texture.get_width()<=512 and preview.texture.get_height()<=288
		for child in service.content.get_children():service.content.remove_child(child);child.queue_free()
		service.photo_page=1
		service._gallery({"tier":"premium"})
		ok=ok and service.content.get_children().filter(func(child):return child is TextureRect).size()==2
		for child in service.content.get_children():service.content.remove_child(child);child.queue_free()
		var damaged_id: String=Photos.list(owner,phone_id).photos[6].id
		var damaged:=FileAccess.open(Photos.directory(owner,phone_id)+"/"+damaged_id+".jpg",FileAccess.WRITE)
		if damaged==null:ok=false
		else:damaged.store_string("invalid jpg");damaged.close()
		service._gallery({"tier":"premium"})
		ok=ok and service.content.get_children().any(func(child):return child is Label and child.text.begins_with("Photo unavailable"))
		game.electronics.profile.data.dorm.smartphones[phone_id].location="cabinet"
		ok=ok and service.selected().is_empty()
		game.electronics.profile.data.dorm.smartphones[phone_id].location="hotbar"
		game.electronics.profile.data.dorm.carry_items.clear()
		ok=ok and service.selected().is_empty()
		game.electronics.profile.data.dorm.carry_items.append("phone:"+phone_id)
		game.school.local_identity="0".repeat(48)
		ok=ok and service.selected().is_empty()
		game.school.local_identity=owner
		ok=ok and service.selected()==phone_id
		for index in range(1,ids.size()):Photos.delete_photo(owner,phone_id,ids[index])
		for child in service.content.get_children():service.content.remove_child(child);child.queue_free()
		service._gallery({"tier":"premium"})
		ok=ok and service.photo_page==0 and service.content.get_children().filter(func(child):return child is TextureRect).size()==1
	for id in ids:Photos.delete_photo(owner,phone_id,id)
	print("PHONE_GALLERY ","PASS" if ok else "FAIL")
	quit(0 if ok else 1)
