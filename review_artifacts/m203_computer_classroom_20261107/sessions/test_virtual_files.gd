extends SceneTree
const Files = preload("res://scripts/campus/computers/virtual_files.gd")
func _initialize() -> void:
	for bad in ["../x","a/../x","/x","C:/x","a\\x","a//x",".","a/","https://x","a b"]:
		assert(Files.path(bad).is_empty(),bad)
	assert(Files.path("code/main.py")=="code/main.py")
	var a := {}
	var b := {}
	var saved := Files.save(a,"main.py","print(1)",0)
	assert(saved.has("files"))
	a=saved.files
	assert(b.is_empty())
	assert(Files.save(a,"main.py","lost",0).has("error"))
	assert(Files.save(a,"main.py","x".repeat(32769),1).has("error"))
	assert(Files.save(a,"../secret","x",0).has("error"))
	var copy := a.duplicate(true)
	copy["main.py"].text="other student"
	assert(a["main.py"].text=="print(1)")
	for i in range(31):a["file%d"%i]={"text":"","version":1}
	assert(Files.validate(a))
	assert(Files.save(a,"overflow","x",0).has("error"))
	print("VIRTUAL_FILES_PASS")
	quit()
