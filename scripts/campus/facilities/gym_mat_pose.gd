extends RefCounted
## World-space contacts shared by the observer rig and the first-person view.

static func palm(mat: Vector3, side: float, exercise: String) -> Vector3:
	return mat+Vector3(side*.27,.065,.43 if exercise=="pike_pushup" else .49)

static func toes(mat: Vector3, side: float, exercise: String) -> Vector3:
	return mat+Vector3(side*.13,.06,-.65 if exercise=="pike_pushup" else -.91)

static func hips(mat: Vector3, exercise: String, lowered: float) -> Vector3:
	match exercise:
		"pushup":return mat+Vector3(0,lerpf(.39,.20,lowered),-.15)
		"pike_pushup":return mat+Vector3(0,lerpf(.79,.73,lowered),-.07)
		_:return mat+Vector3(0,.16,.10)
