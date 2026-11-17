extends SceneTree
const Room=preload("res://scripts/campus/facilities/clothing_store/room_builder.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var room:=Room.new()
	room.position=Vector3(2,5,49)
	room.rotation.y=PI/2
	root.add_child(room)
	await process_frame
	# The campus shell owns the glazing and hides these authored wall panels.
	for child in room.get_children():
		if str(child.name) in ["Floor","BackWall","LeftWall","RightWall","EntryHeader","EntryLeft","EntryRight","FeatureWall","BrandPanel"]:child.hide()
	for x in [-5.5,5.5]:
		var aperture:=Vector3(x,1.6,8.0)
		for child in room.get_children():
			if not child is MeshInstance3D or not child.visible or not child.mesh is BoxMesh:continue
			if child.name in ["EntryLeft","EntryRight","EntryHeader","FeatureWall"]:
				var half: Vector3=child.mesh.size*.5
				assert(not (absf(aperture.x-child.position.x)<half.x and absf(aperture.y-child.position.y)<half.y and absf(aperture.z-child.position.z)<half.z))
	var mannequins: Array=[]
	var curtains: Array=[]
	for child in room.get_children():
		if child is MeshInstance3D and child.mesh is SphereMesh and absf(absf(child.position.x)-5.5)<.01 and absf(child.position.y-2.12)<.01 and absf(child.position.z-7.32)<.01:mannequins.append(child)
		if child is MeshInstance3D and child.mesh is BoxMesh and absf(absf(child.position.x)-5.5)<.01 and absf(child.position.y-1.98)<.01 and absf(child.position.z-6.82)<.01:curtains.append(child)
	assert(mannequins.size()==2 and curtains.size()==2)
	for head in mannequins:
		assert(head.position.z>curtains[0].position.z and head.position.z<8)
		assert(absf(head.global_position.x-9.32)<.02)
		assert(absf(absf(head.global_position.z-49)-5.5)<.02)
	print("CLOTHING_WINDOW_DISPLAYS PASS")
	quit(0)
