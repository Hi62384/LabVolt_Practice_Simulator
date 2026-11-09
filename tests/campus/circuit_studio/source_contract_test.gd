extends SceneTree
const Contract=preload("res://scripts/campus/facilities/circuit_studio/studio_contract.gd")

func _init() -> void:
	var room:=Contract.room_record()
	assert(Contract.valid_room_record(room))
	assert(Contract.ACTION_PAGES.ic_builder!=Contract.ACTION_PAGES.pcb_builder)
	assert(Contract.ACTION_PAGES.has("prototype_bench"))
	var low:=Contract.vector(room.bounds_min);var high:=Contract.vector(room.bounds_max)
	var keep_min:=Vector3(16,5,45.8);var keep_max:=Vector3(20,7.4,48.2)
	var manifest: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(Contract.MANIFEST_PATH))
	for values in manifest.workstations.values():
		var p:=Contract.vector(values)
		assert(p.x>low.x and p.x<high.x and p.z>low.z and p.z<high.z)
		assert(not (p.x>=keep_min.x and p.x<=keep_max.x and p.z>=keep_min.z and p.z<=keep_max.z))
	var mount_source:=FileAccess.get_file_as_string("res://scripts/campus/facilities/circuit_studio/mount_controller.gd")
	assert(mount_source.contains("mount_succeeded=room.is_ready()"))
	assert(mount_source.contains("return not mount_succeeded"))
	var ui_source:=FileAccess.get_file_as_string("res://scripts/electronics_ui.gd")
	for action in ["Open circuit designer","New empty circuit design","Inspect package","Edit a copy","Outline / copper","Use standalone","Craft from components"]:
		assert(ui_source.contains(action),"Existing action missing: "+action)
	print("CIRCUIT_STUDIO_SOURCE_CONTRACT_OK")
	quit()

