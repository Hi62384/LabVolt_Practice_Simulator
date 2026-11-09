extends RefCounted
## Called by Toon.build AFTER details and BEFORE animation keys are generated.
## Empty body dictionary means the historical Toon build, byte-for-byte source
## geometry/transform behavior. Renderer opts in with a validated modern body.
const Fit = preload("res://scripts/avatar_cosmetics/body_deformation/body_fit.gd")
const Warp = preload("res://scripts/avatar_cosmetics/body_deformation/mesh_warp.gd")
const Envelope = preload("res://scripts/avatar_cosmetics/body_deformation/mesh_envelope.gd")
const META := &"body_deformation_context"

static func apply(avatar: Node3D, raw: Dictionary, legacy: Dictionary) -> void:
	if raw.is_empty() or avatar.has_meta(META): return
	var p := Fit.parameters(Fit.provider_context(raw,legacy))
	avatar.set_meta(META,p)
	if not Fit.has_deformation(p): return
	var body := avatar.get_node("Body") as Node3D
	for child in body.get_children():
		if child is not MeshInstance3D: continue
		if str(child.name)=="Neck":
			Warp.deform_tree(child,func(v: Vector3) -> Vector3:
				return Vector3(v.x*float(p.neck_width),Fit.neck_y(v.y,p),v.z*float(p.neck_width)),p.live)
		else: Warp.deform_tree(child,func(v: Vector3) -> Vector3: return Fit.torso_point(v,p),p.live)
	var head := body.get_node("Head") as Node3D
	# Keep the bottom face/neck join anchored as head dimensions change. Legacy
	# direct Toon.build remains unchanged; head-local face/hair transforms survive.
	head.position.y += .44*(float(p.torso_length)-1.0) + .135*(float(p.neck_length)-1.0) + .205*(head.scale.y-1.0)
	for side in [-1.0,1.0]:
		var suffix := "L" if side < 0 else "R"
		var arm := body.get_node("Arm"+suffix) as Node3D
		arm.position.x *= Fit.extra_width(1.24,p)
		arm.position.y = Fit.torso_y(1.24,p)
		for child in arm.get_children():
			if child is MeshInstance3D and not str(child.name).begins_with("Hand") and not str(child.name).begins_with("Thumb"):
				Warp.deform_tree(child,func(v: Vector3) -> Vector3: return Vector3(v.x*Fit.arm_factor(p),v.y,v.z*Fit.arm_factor(p)),p.live)
		var leg := avatar.get_node("Leg"+suffix) as Node3D
		leg.position.x *= Fit.hip_factor(p)
		for child in leg.get_children():
			if child is MeshInstance3D and str(child.name).begins_with("Trouser"):
				Warp.deform_tree(child,func(v: Vector3) -> Vector3: return Vector3(v.x*Fit.leg_factor(p),v.y,v.z*Fit.leg_factor(p)),p.live)
	# A fitted pants bridge connects displaced leg roots underneath the hem.
	# Default/average creates no geometry, preserving the existing default mesh.
	if not is_equal_approx(Fit.hip_factor(p),1.0) or not is_equal_approx(Fit.leg_factor(p),1.0): _pelvis(avatar,p)
	if not p.live: _adjust_splay(avatar,false)

static func _pelvis(avatar: Node3D, p: Dictionary) -> void:
	var body := avatar.get_node("Body") as Node3D
	var leg := avatar.get_node("LegL") as Node3D
	var trouser := leg.get_node("Trouser") as MeshInstance3D
	var edges := Envelope.collect(trouser,trouser.transform)
	var rows: Array[Vector3] = [Vector3(.785,0,0)]
	for y in [.80,.83,.86]:
		var bounds := Envelope.at_y(edges,(y-.86)/float(p.leg_length))
		var radius := absf(leg.position.x)+maxf(absf(bounds.x),absf(bounds.y))
		rows.append(Vector3(y,radius,.11*Fit.leg_factor(p)))
	var top := Fit._radii(.89,p)
	rows.append(Vector3(Fit.torso_y(.89,p),top.x,top.y))
	rows.append(Vector3(Fit.torso_y(.92,p),0,0))
	var pelvis := MeshInstance3D.new(); pelvis.name = "Pelvis"; pelvis.mesh = Warp.section_mesh(rows)
	pelvis.material_override = trouser.material_override
	body.add_child(pelvis)

## Renderer calls once AFTER equipment attachment. Uses the visible fitted meshes
## to finish shoulder clearance, then rebases existing rotation keys onto that
## rest quaternion. AnimationPlayer paths, positions and limb scales stay intact.
static func finish(avatar: Node3D) -> void:
	if not avatar.has_meta(META): return
	var context: Dictionary = avatar.get_meta(META)
	if not Fit.has_deformation(context):return
	var pelvis := avatar.get_node_or_null("Body/Pelvis") as MeshInstance3D
	if pelvis != null:
		for child in avatar.get_node("LegL").get_children():
			if child is MeshInstance3D and str(child.name).begins_with("LegL") and child.mesh.get_surface_count()>0:
				var mat: Material = child.get_surface_override_material(0)
				if mat==null: mat=child.mesh.surface_get_material(0)
				if mat!=null: pelvis.material_override=mat.duplicate(true)
	if not context.live: _adjust_splay(avatar,true)

static func _adjust_splay(avatar: Node3D, rebase: bool) -> void:
	var body := avatar.get_node("Body") as Node3D
	var torso: Array[Vector4] = []
	for child in body.get_children():
		if child is Node3D and str(child.name) in ["TailoredTop","Hem","Torso","Waist","Pelvis"]:
			torso.append_array(Envelope.collect(child,child.transform))
	for side in [-1.0,1.0]:
		var arm := body.get_node("ArmL" if side<0 else "ArmR") as Node3D
		var old_rest := arm.quaternion
		var local: Array[Vector4] = []
		for child in arm.get_children():
			if child is Node3D and not str(child.name).begins_with("Accessory_"):
				local.append_array(Envelope.collect(child,child.transform))
		var mirrored: Array[Vector4] = []
		local = Envelope.convex_edges(local)
		for e in torso: mirrored.append(Vector4(e.x*side,e.y,e.z*side,e.w))
		var pivot := Vector2(absf(arm.position.x),arm.position.y)
		var lower := maxf(.12,absf(arm.rotation.z))
		var upper := lower
		var limit := pivot.y - Envelope.joint_drop(local,arm.scale.y)
		var clear := Envelope.clears(mirrored,Envelope.pose(local,pivot,arm.scale.y,side,upper),limit)
		if not clear:
			for trial in [.25,.40,.60,.85,1.10,1.35,1.55]:
				if trial <= lower: continue
				upper = trial
				if Envelope.clears(mirrored,Envelope.pose(local,pivot,arm.scale.y,side,upper),limit):
					clear = true; break
				lower = upper
			if clear:
				for iteration in 10:
					var middle := (lower+upper)*.5
					if Envelope.clears(mirrored,Envelope.pose(local,pivot,arm.scale.y,side,middle),limit): upper=middle
					else: lower=middle
		if not clear: push_warning("Body fit: shoulder clearance requires visual review at this envelope")
		arm.rotation.z = side*upper
		if rebase and not old_rest.is_equal_approx(arm.quaternion): _rebase_arm_tracks(avatar,arm,old_rest)

static func _rebase_arm_tracks(avatar: Node3D, arm: Node3D, old_rest: Quaternion) -> void:
	var player := avatar.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if player==null: return
	var path := NodePath("Body/"+str(arm.name))
	var delta := arm.quaternion*old_rest.inverse()
	for name in player.get_animation_list():
		var animation := player.get_animation(name)
		for track in animation.get_track_count():
			if animation.track_get_type(track)!=Animation.TYPE_ROTATION_3D or animation.track_get_path(track)!=path: continue
			for key in animation.track_get_key_count(track):
				var rotation: Quaternion = animation.track_get_key_value(track,key)
				animation.track_set_key_value(track,key,delta*rotation)
