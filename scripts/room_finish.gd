extends RefCounted
static func build(game: Node3D) -> void:
	for x in [-8,-5,5]:
		game._solid(Vector3(x,.87,9.45),Vector3(1.5,1.7,.65),Color("6b8580"))
		for door in [-.37,.37]:
			game._box(game,Vector3(x+door,.88,9.108),Vector3(.72,1.58,.04),Color("829893"))
			game._box(game,Vector3(x+door+.22,.92,9.071),Vector3(.025,.22,.03),Color("c7c9b9"))
	var plant = preload("res://scripts/campus/presentation/decor/potted_plant.gd")
	for x in [-9.1,9.1]:
		plant.mount(game, Vector3(x, .016, -1.4))
