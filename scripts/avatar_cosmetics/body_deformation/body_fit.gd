extends RefCounted
## Coordinate contract for the segmented toon rig. Never mutates appearance data.
const Core = preload("res://scripts/avatar_cosmetics/core/avatar_core.gd")
const Warp = preload("res://scripts/avatar_cosmetics/body_deformation/mesh_warp.gd")
const BUILDS := {
	"average": {"chest":1.0,"hips":1.0,"arm":1.0,"leg":1.0,"depth":1.0},
	"slim": {"chest":.88,"hips":.92,"arm":.86,"leg":.90,"depth":.92},
	"heavy": {"chest":1.16,"hips":1.18,"arm":1.14,"leg":1.18,"depth":1.18},
	"muscular": {"chest":1.20,"hips":1.04,"arm":1.24,"leg":1.14,"depth":1.10}}

static func parameters(raw: Dictionary) -> Dictionary:
	var p := Core.sanitize_body(raw)
	p["shape"] = BUILDS[p.build]
	p["depth"] = float(raw.get("__legacy_body_depth", 1.0))
	p["coat"] = raw.get("__legacy_outfit", "") == "Lab coat"
	p["live"] = raw.get("__live_preview", false)
	return p

static func provider_context(body: Dictionary, legacy: Dictionary) -> Dictionary:
	var result := body.duplicate(true)
	result["__legacy_body_depth"] = float(legacy.get("body_depth", 1.0))
	result["__legacy_outfit"] = str(legacy.get("outfit", "Varsity"))
	return result

static func torso_y(y: float, p: Dictionary) -> float:
	if y <= .86: return y
	return .86 + (y - .86) * float(p.torso_length) if y <= 1.30 else y + .44 * (float(p.torso_length) - 1.0)

static func neck_y(y: float, p: Dictionary) -> float:
	return torso_y(1.30, p) + (y - 1.30) * float(p.neck_length)

static func extra_width(y: float, p: Dictionary) -> float:
	var low: float = p.hips * p.shape.hips
	var high: float = p.torso_width * p.shape.chest
	var value := lerpf(low, high, smoothstep(.87, 1.24, y))
	return lerpf(value, float(p.neck_width), smoothstep(1.24, 1.32, y))

static func torso_point(v: Vector3, p: Dictionary) -> Vector3:
	# Input has ALREADY received legacy width/waist/shoulder/depth deformation.
	return Vector3(v.x * extra_width(v.y, p), torso_y(v.y, p), v.z * float(p.shape.depth))

static func arm_factor(p: Dictionary) -> float:
	return float(p.arm_width) * float(p.shape.arm)

static func leg_factor(p: Dictionary) -> float:
	return float(p.leg_width) * float(p.shape.leg)

static func hip_factor(p: Dictionary) -> float:
	return float(p.hips) * float(p.shape.hips)

static func has_deformation(p: Dictionary) -> bool:
	if p.build != "average": return true
	for key in ["neck_length","neck_width","torso_length","torso_width","hips","arm_width","leg_width"]:
		if not is_equal_approx(float(p[key]),1.0): return true
	return false

static func _radii(y: float, p: Dictionary, neutral := false) -> Vector2:
	# EXACT ring endpoints of toon_character.build(), with linear triangle
	# interpolation between them. Do not evaluate a smoothstep at the query Y.
	var profile_key := "neutral_profile" if neutral else "fitted_profile"
	if profile_key not in p:
		var profile: Array[Vector3] = [Vector3(.69 if p.coat else .87,.23,.13),Vector3(.96,.22,.14),Vector3(1.24,.255,.14),Vector3(1.30,.21,.11),Vector3(1.32,.13,.09)]
		if not neutral:
			for i in range(profile.size()):
				var row := profile[i]
				var width := lerpf(float(p.waist),float(p.shoulders),smoothstep(.87,1.24,row.x))
				row.y *= width * (float(p.width) if row.x < 1.32 else 1.0) * extra_width(row.x,p)
				row.z *= float(p.depth) * float(p.shape.depth)
				profile[i] = row
		p[profile_key] = profile
	var rows: Array = p[profile_key]
	var query := clampf(y,rows[0].x,1.32)
	for i in range(rows.size()-1):
		var a: Vector3 = rows[i]; var b: Vector3 = rows[i+1]
		if query > b.x: continue
		var ar := Vector2(a.y,a.z); var br := Vector2(b.y,b.z)
		return ar.lerp(br,inverse_lerp(a.x,b.x,query))
	return Vector2.ZERO

static func garment_torso_point(v: Vector3, p: Dictionary, fit: float) -> Vector3:
	var base := _radii(v.y,p,true)
	var target := _radii(v.y,p)
	# Fit is ease around the skin envelope. Negative ease must not put the
	# garment inside the body; retain the authored silhouette when it is wider.
	var x := v.x * target.x/base.x * fit
	var z := v.z * target.y/base.y * fit
	var radial := sqrt(pow(x/target.x,2)+pow(z/target.y,2))
	# The inner collar folds around the neck, inside the torso envelope.
	# Keep the fold's thickness and shape when fitting it to the avatar.
	var collar := smoothstep(1.295,1.318,v.y)
	var clearance := lerpf(1.012,radial,collar)
	if radial > .000001 and radial < clearance:
		x *= clearance/radial; z *= clearance/radial
	z = lerpf(z, v.z * float(p.neck_width), collar)
	return Vector3(x,torso_y(v.y,p),z)

static func fit_clothing(root: Node3D, definition: Dictionary, raw: Dictionary, values: Dictionary) -> void:
	var p := parameters(raw)
	var fit := clampf(float(values.get("fit",1.0)),.94,1.08)
	for child in root.get_children():
		match str(child.name):
			"Torso", "Waist":
				Warp.deform_tree(child,func(v: Vector3) -> Vector3: return garment_torso_point(v,p,fit),p.live)
			"SleeveL", "SleeveR":
				# Parent Arm owns length. Never apply it a second time to the sleeve.
				child.scale = Vector3(arm_factor(p)*fit,1.0,arm_factor(p)*fit)
			"LegL", "LegR":
				if str(definition.get("id","")).contains("skirt"):
					# Keep each split skirt panel meeting the centre seam when hips move
					# its animated leg pivot. Parent Leg owns length as with trousers.
					var side := -1.0 if str(child.name)=="LegL" else 1.0
					var old_x: float = side * .12
					var new_x: float = old_x * float(p.width) * hip_factor(p)
					Warp.deform_tree(child,func(v: Vector3) -> Vector3:
						return Vector3((v.x+old_x)*float(p.width)*hip_factor(p)*fit-new_x,v.y,v.z*float(p.depth)*float(p.shape.depth)*fit),p.live)
				else: child.scale = Vector3(leg_factor(p)*fit,1.0,leg_factor(p)*fit)

static func fit_accessory(item: Node3D, slot: String, raw: Dictionary, values: Dictionary) -> void:
	var p := parameters(raw)
	var user := clampf(float(values.get("scale",1.0)),.9,1.1)
	match slot:
		"head", "eyewear", "ears": item.scale = Vector3.ONE * user
		"neck":
			Warp.deform_tree(item,func(v: Vector3) -> Vector3:
				var y := 1.33 + (v.y - 1.33) * user
				var chest := 1.0 - smoothstep(1.27, 1.33, y)
				var x := v.x * float(p.neck_width) * user
				var z := v.z * float(p.neck_width) * user
				if v.z > 0.0:
					var radius := _radii(y, p)
					var front := radius.y * sqrt(maxf(0.0, 1.0 - (x / maxf(.01, radius.x)) ** 2.0))
					var clearance := front + .044
					z = lerpf(z, maxf(z, clearance + (v.z - .15) * .25), chest)
				return Vector3(x, lerpf(neck_y(y, p), torso_y(y, p), chest), z),p.live)
		"back":
			Warp.deform_tree(item,func(v: Vector3) -> Vector3:
				return garment_torso_point(Vector3(v.x*user,1.12+(v.y-1.12)*user,v.z*user),p,1.0),p.live)
		"wrist_left", "wrist_right":
			item.scale = Vector3(arm_factor(p)*user,user/float(p.arm_length),arm_factor(p)*user)
			item.position.y = -.405 + .405 * user/float(p.arm_length)
		_: item.scale = Vector3.ONE * user


