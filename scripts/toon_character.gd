extends RefCounted
const BodyDeformation = preload("res://scripts/avatar_cosmetics/body_deformation/rig_adapter.gd")
const Face = preload("res://scripts/campus/academics/character_face.gd")
# Original LabVolt toy-like character geometry. All settings are portable JSON.
const VERSION := 2
const HAIR := ["Sweep", "Curls", "Bob", "Bun", "Spikes", "Crop", "Bald"]
const OUTFITS := ["Varsity", "Hoodie", "Workwear", "Lab coat", "Tee"]
const GLASSES := ["None", "Round", "Square", "Safety"]
const EXPRESSIONS := ["Smile", "Calm", "Grin", "Curious", "Stern", "Frown"]
const SKINS := ["f3cbb1", "deb08c", "c78e64", "a86c49", "805037", "54382e"]
static func defaults() -> Dictionary:
	return {"creator":"labvolt_toon", "version":VERSION, "name":"New character", "height":1.0,"build":1.0,"head":1.0,"face_width":1.0,"eye_size":1.0,"eye_spacing":1.0,"nose":1.0,"hair":"Sweep","outfit":"Varsity","glasses":"None","expression":"Smile","freckles":false,"earrings":false,"beard":false,"skin":"deb08c","hair_color":"352b31","eye_color":"397a83","top":"398e91","accent":"f5c16c","pants":"293951","shoes":"f3e9d6","shoulders":1.0,"waist":1.0,"body_depth":1.0,"arm_length":1.0,"hand_size":1.0,"leg_length":1.0,"shoe_size":1.0,"face_height":1.0,"jaw":1.0,"ear_size":1.0,"nose_length":1.0,"mouth_width":1.0,"eye_height":1.0,"pupil_size":1.0,"brow_thickness":1.0,"hair_volume":1.0,"fringe_length":1.0,"hair_width":1.0,"hat":"None","bow_tie":false,"gloves":false,"watch":false,"mustache":false,"hat_color":"497d83","glove_color":"e4e9e8"}
static func preset(index: int) -> Dictionary:
	var c := defaults()
	var entries := [
		{"name":"Alex","hair":"Sweep","outfit":"Varsity","top":"398e91","accent":"f5c16c"},
		{"name":"Mika","hair":"Bob","skin":"f3cbb1","hair_color":"633748","outfit":"Hoodie","top":"b36f92","accent":"f6ddba","glasses":"Round","freckles":true},
		{"name":"Jules","hair":"Curls","skin":"805037","hair_color":"241d29","outfit":"Workwear","top":"d3a354","accent":"f3e3c7","build":1.12,"earrings":true},
		{"name":"Riley","hair":"Bun","skin":"c78e64","hair_color":"422b29","outfit":"Lab coat","top":"e7eff0","accent":"659b84","glasses":"Safety","height":1.07},
		{"name":"Kit","hair":"Spikes","skin":"deb08c","hair_color":"829eaf","outfit":"Tee","top":"ca7459","accent":"ead7a6","height":.94,"expression":"Grin"},
		{"name":"Sam","hair":"Crop","skin":"54382e","hair_color":"231e23","outfit":"Varsity","top":"695f94","accent":"e4b66c","glasses":"Square","build":1.17,"beard":true}]
	c.merge(entries[posmod(index,entries.size())],true)
	return c
static func sanitize(raw: Dictionary) -> Dictionary:
	var c := defaults()
	for key in c:
		if not raw.has(key):continue
		if c[key] is float:
			if (raw[key] is float or raw[key] is int) and is_finite(float(raw[key])):c[key]=clampf(float(raw[key]),.65,1.4)
		elif c[key] is bool:c[key]=raw[key] == true
		elif c[key] is String:c[key]=str(raw[key]).left(48)
	for key in ["skin","hair_color","eye_color","top","accent","pants","shoes","hat_color","glove_color"]:
		if not Color.html_is_valid(c[key]):c[key]=defaults()[key]
	for pair in [["hair",HAIR],["outfit",OUTFITS],["glasses",GLASSES],["expression",EXPRESSIONS],["hat",["None","Beanie","Cap","Hard hat"]]]:
		if not c[pair[0]] in pair[1]:c[pair[0]]=pair[1][0]
	c.creator="labvolt_toon";c.version=VERSION
	c.name=c.name.strip_edges().left(32)
	if c.name.is_empty():c.name="Lab friend"
	return c
static func material(color: String, roughness := .75) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color=Color(color);m.roughness=roughness
	return m
static func ellipsoid(parent: Node3D, at: Vector3, size: Vector3, mat: Material, label := "Detail") -> MeshInstance3D:
	var mesh := SphereMesh.new();mesh.radius=1;mesh.height=2;mesh.radial_segments=24;mesh.rings=16
	var node := MeshInstance3D.new();node.name=label;node.mesh=mesh;node.material_override=mat;node.position=at;node.scale=size
	node.set_meta("toon_part", label)
	parent.add_child(node);return node
static func link(parent: Node3D,a: Vector3,b: Vector3,radius: float,mat: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new();var mesh := CylinderMesh.new()
	mesh.top_radius=radius;mesh.bottom_radius=radius;mesh.height=a.distance_to(b);mesh.radial_segments=12
	node.mesh=mesh;node.material_override=mat;node.position=(a+b)*.5
	var axis := (b-a).normalized();var side := Vector3.RIGHT
	if abs(axis.dot(side))>.95:side=Vector3.FORWARD
	var z := side.cross(axis).normalized();node.basis=Basis(axis.cross(z).normalized(),axis,z)
	parent.add_child(node)
	return node
static func line(parent: Node3D,points: Array,radius: float,mat: Material) -> void:
	for i in range(points.size()-1):link(parent,points[i],points[i+1],radius,mat)
static func ring(parent: Node3D,center: Vector3,rx: float,ry: float,mat: Material,radius := .008) -> void:
	var points: Array=[]
	for i in 33:
		var a := TAU*i/32.;points.append(center+Vector3(cos(a)*rx,sin(a)*ry,0))
	line(parent,points,radius,mat)
static func form(parent: Node3D,rows: Array,mat: Material,label: String) -> MeshInstance3D:
	# Elliptical sections produce tailored, rounded silhouettes rather than boxes.
	var st := SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES);st.set_smooth_group(0)
	for row in range(rows.size()-1):
		for i in 32:
			var points: Array=[]
			for pair in [[row,i],[row+1,i],[row+1,i+1],[row,i+1]]:
				var r: Vector3=rows[pair[0]];var a: float=TAU*pair[1]/32.
				points.append(Vector3(cos(a)*r.y,r.x,sin(a)*r.z))
			for index in [0,2,1,0,3,2]:
				var v: Vector3=points[index]
				var row_index: int=row if index in [0,3] else row+1
				var before: Vector3=rows[maxi(0,row_index-1)];var after: Vector3=rows[mini(rows.size()-1,row_index+1)]
				var radial := Vector3(v.x/maxf(rows[row_index].y,.001),0,v.z/maxf(rows[row_index].z,.001))
				var slope: float=((after.y-before.y)*radial.x*radial.x+(after.z-before.z)*radial.z*radial.z)/maxf(after.x-before.x,.001)
				var normal := Vector3(radial.x,-slope,radial.z).normalized()
				if radial.length_squared()<.01:normal=Vector3.DOWN if row_index==0 else Vector3.UP
				# The campus graphics settings enable anisotropic material filtering.
				# An explicit UV stream is required even for plain-color materials:
				# missing UV attributes render these surfaces black in compatibility.
				var u: float=(float(i)+(1.0 if index in [2,3] else 0.0))/32.0
				var v_coord: float=inverse_lerp(rows[0].x,rows[-1].x,v.y)
				st.set_uv(Vector2(u,v_coord));st.set_normal(normal);st.add_vertex(v)
	var node := MeshInstance3D.new();node.name=label;node.mesh=st.commit();node.material_override=mat;node.set_meta("toon_part",label);parent.add_child(node);return node
static func _torso_width_at(y: float,c: Dictionary) -> float:
	# Keep the waist and shoulder controls independent while blending the ribcage between them.
	return lerpf(c.waist,c.shoulders,smoothstep(.87,1.24,y))
static func _torso_base_radius(y: float) -> float:
	if y<=.87:return .23
	if y<=.96:return lerpf(.23,.22,inverse_lerp(.87,.96,y))
	if y<=1.24:return lerpf(.22,.255,inverse_lerp(.96,1.24,y))
	if y<=1.30:return lerpf(.255,.21,inverse_lerp(1.24,1.30,y))
	return lerpf(.21,0.0,clampf(inverse_lerp(1.30,1.33,y),0.0,1.0))
static func _torso_radius_at(y: float,width: float,c: Dictionary) -> float:
	var coat: bool=c.outfit=="Lab coat"
	var rows := [Vector2(.67 if coat else .85,0),Vector2(.69 if coat else .87,.23*width),Vector2(.96,.22*width),Vector2(1.24,.255*width),Vector2(1.30,.21*width),Vector2(1.32,.13),Vector2(1.33,0)]
	for i in range(rows.size()-1):
		if y<=rows[i+1].x:
			var a: Vector2=rows[i];var b: Vector2=rows[i+1]
			return lerpf(a.y*_torso_width_at(a.x,c),b.y*_torso_width_at(b.x,c),clampf(inverse_lerp(a.x,b.x,y),0,1))
	return 0.0
static func _arm_rest_splay(width: float,c: Dictionary) -> float:
	# Very wide waists with narrow shoulders need a wider natural arm rest pose. The arm
	# still pivots at the shoulder; animation tracks rotate on X and preserve this Z splay.
	var angle := .12
	for iteration in 3:
		for local_drop in [.12,.20,.28,.37]:
			var scaled_drop: float=local_drop*c.arm_length
			var world_y: float=1.24-cos(angle)*scaled_drop
			var torso_x := _torso_radius_at(world_y,width,c)
			var normal_torso_x: float=_torso_base_radius(world_y)*width*float(c.shoulders)
			var required_sine: float=sin(.12)+maxf(0.0,torso_x-normal_torso_x)/scaled_drop
			if required_sine>sin(angle):angle=asin(clampf(required_sine,0.0,1.0))
	return angle
static func _torso_row(y: float,radius_x: float,radius_z: float,c: Dictionary) -> Vector3:
	return Vector3(y,radius_x*_torso_width_at(y,c),radius_z*c.body_depth)
static func _torso_point(point: Vector3,c: Dictionary) -> Vector3:
	return Vector3(point.x*_torso_width_at(point.y,c),point.y,point.z*c.body_depth)
static func _torso_ellipsoid(parent: Node3D,at: Vector3,size: Vector3,mat: Material,label: String,c: Dictionary) -> MeshInstance3D:
	var width_scale := _torso_width_at(at.y,c)
	return ellipsoid(parent,_torso_point(at,c),Vector3(size.x*width_scale,size.y,size.z*c.body_depth),mat,label)
static func _torso_link(parent: Node3D,a: Vector3,b: Vector3,radius: float,mat: Material,c: Dictionary) -> void:
	link(parent,_torso_point(a,c),_torso_point(b,c),radius,mat)
	parent.get_child(-1).name = "ClothingDetail"
	parent.get_child(-1).set_meta("toon_part", "ClothingDetail")
static func _torso_line(parent: Node3D,points: Array,radius: float,mat: Material,c: Dictionary) -> void:
	for i in range(points.size()-1):
		_torso_link(parent,points[i],points[i+1],radius,mat,c)
static func build(raw: Dictionary, modern_body: Dictionary = {}) -> Node3D:
	var c := sanitize(raw)
	var root := Node3D.new();root.name="ToonCharacter"
	root.scale=Vector3.ONE*c.height
	var skin := material(c.skin);var hair := material(c.hair_color);var top := material(c.top);var accent := material(c.accent)
	var pants := material(c.pants);var shoe := material(c.shoes);var dark := material("28303e");var white := material("fff9ed");var iris := material(c.eye_color,.35)
	var body := Node3D.new();body.name="Body";root.add_child(body)
	var width: float=c.build
	var coat: bool=c.outfit=="Lab coat"
	form(body,[Vector3(.67 if coat else .85,0,0),_torso_row(.69 if coat else .87,.23*width,.13,c),_torso_row(.96,.22*width,.14,c),_torso_row(1.24,.255*width,.14,c),_torso_row(1.30,.21*width,.11,c),_torso_row(1.32,.13,.09,c),Vector3(1.33,0,0)],top,"TailoredTop")
	ellipsoid(body,Vector3(0,1.33,0),Vector3(.085,.105,.075),skin,"Neck")
	# Independent limbs allow readable walk and seated poses in multiplayer.
	for side in [-1,1]:
		var leg := Node3D.new();leg.name="LegL" if side<0 else "LegR";leg.position=Vector3(side*.12*width,.86,0);root.add_child(leg)
		form(leg,[Vector3(-.72,0,0),Vector3(-.70,.078,.085),Vector3(-.37,.09,.095),Vector3(-.05,.105,.115),Vector3(.02,0,0)],pants,"Trouser")
		ellipsoid(leg,Vector3(0,-.74,.045),Vector3(.096,.075,.16),shoe,"Sneaker")
		ellipsoid(leg,Vector3(0,-.785,.045),Vector3(.10,.028,.165),white,"Sole")
		for j in 3:
			link(leg,Vector3(-.046,-.695,.075+j*.025),Vector3(.046,-.695,.075+j*.025),.006,accent)
			leg.get_child(-1).name = "ShoeLace"
			leg.get_child(-1).set_meta("toon_part", "ShoeLace")
		var arm := Node3D.new();arm.name="ArmL" if side<0 else "ArmR";arm.position=Vector3(side*.255*width*c.shoulders,1.24,0);arm.rotation.z=side*_arm_rest_splay(width,c);body.add_child(arm)
		var short_sleeve: bool=c.outfit=="Tee" or c.outfit=="Workwear"
		var sleeve_mat: Material=accent if c.outfit=="Varsity" else top
		form(arm,[Vector3(-.20 if short_sleeve else -.40,0,0),Vector3(-.19 if short_sleeve else -.39,.073,.078),Vector3(-.08,.083,.09),Vector3(.035,.066,.075),Vector3(.06,0,0)],sleeve_mat,"Sleeve")
		if short_sleeve:ellipsoid(arm,Vector3(0,-.30,0),Vector3(.061,.15,.063),skin,"Forearm")
		else:ellipsoid(arm,Vector3(0,-.40,0),Vector3(.076,.035,.079),accent,"Cuff")
		ellipsoid(arm,Vector3(0,-.48,.012),Vector3(.064,.085,.046),skin,"Hand")
		ellipsoid(arm,Vector3(-side*.05,-.455,.028),Vector3(.027,.045,.028),skin,"Thumb")
	# Clothing details: collars, ribbing, closures and pockets.
	if c.outfit=="Hoodie":
		_torso_ellipsoid(body,Vector3(0,1.27,-.085),Vector3(.18,.12,.12),accent,"Hood",c)
		_torso_ellipsoid(body,Vector3(0,1.0,.134),Vector3(.13,.067,.018),accent,"KangarooPocket",c)
		for side in [-1,1]:_torso_link(body,Vector3(side*.06,1.27,.12),Vector3(side*.065,1.10,.153),.008,white,c)
	elif c.outfit!="Tee":
		for side in [-1,1]:
			var collar := _torso_ellipsoid(body,Vector3(side*.07,1.265,.105),Vector3(.065,.028,.04),accent,"Collar",c);collar.rotation.z=side*.45
		_torso_link(body,Vector3(0,.88,.145),Vector3(0,1.25,.145),.007,accent,c)
		for j in 4:_torso_ellipsoid(body,Vector3(.018,1.19-j*.075,.15),Vector3(.012,.012,.007),white,"Button",c)
		_torso_ellipsoid(body,Vector3(-.135,1.16,.14),Vector3(.056,.047,.013),accent,"ChestPocket",c)
		if coat:
			for side in [-1,1]:_torso_ellipsoid(body,Vector3(side*.14,.85,.13),Vector3(.06,.055,.014),accent,"CoatPocket",c)
	else:
		_torso_ellipsoid(body,Vector3(0,1.13,.145),Vector3(.075,.075,.012),accent,"Badge",c)
		_torso_line(body,[Vector3(.018,1.185,.16),Vector3(-.025,1.13,.163),Vector3(.018,1.13,.163),Vector3(-.018,1.08,.16)],.008,white,c)
	if not coat:_torso_ellipsoid(body,Vector3(0,.89,0),Vector3(.235*width,.027,.135),accent,"Hem",c)
	var head := Node3D.new();head.name="Head";head.position=Vector3(0,1.56,0);head.scale=Vector3(c.head*c.face_width,c.head*c.face_height,c.head);body.add_child(head)
	Face.tag(head,"head");head.set_meta("character_mouth_width",c.mouth_width)
	form(head,[Vector3(-.205,0,0),Vector3(-.19,.10,.10),Vector3(-.12,.195,.148),Vector3(.015,.225,.17),Vector3(.14,.205,.155),Vector3(.22,.135,.105),Vector3(.24,0,0)],skin,"Face")
	for side in [-1,1]:
		ellipsoid(head,Vector3(side*.222,-.01,0),Vector3(.046,.065,.038),skin,"Ear")
		ellipsoid(head,Vector3(side*.242,-.012,.025),Vector3(.021,.035,.012),material(Color(c.skin).darkened(.18).to_html()),"InnerEar")
		var x: float=side*.087*c.eye_spacing
		# Construct both eyes identically. Searching duplicate mesh names after
		# Godot renames siblings left one eye outside the blinking hierarchy.
		var eye:=Node3D.new();eye.name="EyeL" if side<0 else "EyeR"
		eye.position=Vector3(x,.015,0);eye.scale.y=c.eye_height;head.add_child(eye);Face.tag(eye,"eye",side)
		var blink:=Node3D.new();blink.name="Blink";eye.add_child(blink);Face.tag(blink,"blink",side)
		Face.tag(ellipsoid(blink,Vector3(0,0,.155),Vector3(.051*c.eye_size,.062*c.eye_size,.024),white,"EyeWhite"),"eye_white",side)
		Face.tag(ellipsoid(blink,Vector3(0,-.002,.179),Vector3(.026*c.eye_size,.035*c.eye_size,.011),iris,"Iris"),"iris",side)
		Face.tag(ellipsoid(blink,Vector3(0,-.001,.189),Vector3(.013*c.eye_size*c.pupil_size,.023*c.eye_size*c.pupil_size,.006),dark,"Pupil"),"pupil",side)
		Face.tag(ellipsoid(blink,Vector3(-.008,.014,.195),Vector3(.008,.01,.004),white,"EyeSpark"),"eye_spark",side)
		var brow:=Node3D.new();brow.name="BrowL" if side<0 else "BrowR"
		brow.position=Vector3(x,.102+(.014 if c.expression=="Curious" and side==1 else 0),0)
		head.add_child(brow);Face.tag(brow,"brow",side);brow.set_meta("toon_part","Brow")
		var brow_points: Array[Vector3]=[Vector3(-.038,-.004,.165),Vector3(0,.007,.17),Vector3(.038,-.004,.165)]
		if c.expression=="Stern":
			for i in brow_points.size():brow_points[i].y+=brow_points[i].x*side*.36
		for i in 2:
			var segment:=link(brow,brow_points[i],brow_points[i+1],.009*c.brow_thickness,hair)
			segment.name="Segment%d"%i;segment.set_meta("toon_part","Brow");Face.tag(segment,"brow_segment",side)
		if c.freckles:
			for j in 4:ellipsoid(head,Vector3(side*(.11+j*.018),-.055+(j%2)*.014,.155-j*.006),Vector3(.004,.004,.002),material("9b614a"),"Freckle")
		if c.earrings:ring(head,Vector3(side*.244,-.067,.018),.022,.03,accent,.006)
	ellipsoid(head,Vector3(0,-.038,.179),Vector3(.033*c.nose,.037,.037*c.nose*c.nose_length),skin,"Nose")
	var mouth := material("6c3940")
	var points: Array=[]
	for i in 17:
		var x: float=(i/16.-.5)*.112*c.mouth_width
		var y: float=-.122+(-.018*pow(x/(.056*c.mouth_width),2) if c.expression in ["Stern","Frown"] else (.022*pow(x/(.056*c.mouth_width),2) if c.expression!="Calm" else 0.))
		points.append(Vector3(x,y,.144-abs(x)*.03))
	var lips:=Node3D.new();lips.name="NeutralMouth";head.add_child(lips)
	lips.set_meta("toon_part","Mouth");Face.tag(lips,"mouth_lips")
	for i in range(points.size()-1):
		var segment:=link(lips,points[i],points[i+1],.006,mouth)
		segment.name="Lip%d"%i;segment.set_meta("toon_part","Mouth");Face.tag(segment,"lip")
	if c.expression=="Grin":
		var teeth:=MeshInstance3D.new();teeth.name="Teeth"
		var tooth_mesh:=BoxMesh.new();tooth_mesh.size=Vector3(.078*c.mouth_width,.012,.004)
		teeth.mesh=tooth_mesh;teeth.material_override=white;teeth.position=Vector3(0,-.109,.146)
		lips.add_child(teeth);teeth.set_meta("toon_part","Teeth");Face.tag(teeth,"teeth")
	if c.beard:
		for i in 15:
			var a: float=PI+i*PI/14.
			ellipsoid(head,Vector3(cos(a)*.136,-.07+sin(a)*.10,.127),Vector3(.026,.033,.022),hair,"Beard")
	var hair_group := Node3D.new();hair_group.name="Hair";head.add_child(hair_group)
	_hair(hair_group,c,hair)
	hair_group.scale=Vector3(c.hair_width,c.hair_volume,1)
	for node in hair_group.get_children():
		if str(node.name).begins_with("Fringe"):node.scale.y*=c.fringe_length
	_details(root,body,head,c,skin,accent)
	_glasses(head,c,dark,accent)
	BodyDeformation.apply(root,modern_body,c)
	_animations(root)
	return root
static func _hair(head: Node3D,c: Dictionary,mat: Material) -> void:
	var style: String=c.hair
	if style=="Bald":return
	# A fitted cap, with an open forehead and sculpted masses for each style.
	form(head,[Vector3(.115,.205,.156),Vector3(.18,.205,.16),Vector3(.245,.15,.12),Vector3(.27,0,0)],mat,"HairCap")
	if style=="Crop":return
	if style in ["Bob","Bun"]:
		for side in [-1,1]:ellipsoid(head,Vector3(side*.195,.02,-.035),Vector3(.065,.18,.125),mat,"SideHair")
		ellipsoid(head,Vector3(0,.04,-.115),Vector3(.21,.20,.10),mat,"BackHair")
	if style=="Bun":ellipsoid(head,Vector3(.025,.27,-.10),Vector3(.105,.10,.095),mat,"Bun")
	elif style=="Curls":
		for row in 3:
			for i in 9:
				var a: float=TAU*i/9.+row*.21
				var radius: float=.19-row*.048
				ellipsoid(head,Vector3(cos(a)*radius,.16+row*.064,sin(a)*radius*.78),Vector3(.067,.064,.06),mat,"Curl")
	elif style=="Spikes":
		for i in 7:
			var tuft := ellipsoid(head,Vector3((i-3)*.054,.25-abs(i-3)*.018,.045),Vector3(.05,.095,.065),mat,"Tuft");tuft.rotation.z=(3-i)*.19
	else:
		for i in 5:
			var tuft := ellipsoid(head,Vector3(-.12+i*.055,.19-i*.013,.106),Vector3(.065,.07,.085),mat,"Fringe");tuft.rotation.z=-.48
static func _glasses(head: Node3D,c: Dictionary,dark: Material,accent: Material) -> void:
	if c.glasses=="None":return
	var mat: Material=accent if c.glasses=="Safety" else dark
	var frame:=Node3D.new();frame.name="Glasses";head.add_child(frame);Face.tag(frame,"glasses")
	for side in [-1,1]:
		var x: float=side*.087*c.eye_spacing
		if c.glasses=="Round":ring(frame,Vector3(x,.013,.207),.064,.071,mat,.007)
		else:
			line(frame,[Vector3(x-.062,.071,.205),Vector3(x+.062,.071,.205),Vector3(x+.062,-.043,.205),Vector3(x-.062,-.043,.205),Vector3(x-.062,.071,.205)],.007,mat)
		link(frame,Vector3(side*.15,.03,.20),Vector3(side*.22,.02,.015),.006,mat)
	link(frame,Vector3(-.025,.025,.209),Vector3(.025,.025,.209),.006,mat)
static func _details(root: Node3D,body: Node3D,head: Node3D,c: Dictionary,skin: Material,accent: Material) -> void:
	for node in head.get_children():
		if str(node.get_meta("toon_part","")) in ["Ear","InnerEar"]:node.scale*=c.ear_size
		if str(node.name).begins_with("Face"):node.scale.x*=c.jaw
	for side in [-1,1]:
		var suffix := "L" if side<0 else "R"
		var arm: Node3D=body.get_node("Arm"+suffix);arm.scale.y=c.arm_length
		for child in arm.get_children():
			if str(child.name).begins_with("Hand") or str(child.name).begins_with("Thumb"):
				child.scale*=c.hand_size
				if c.gloves:child.material_override=material(c.glove_color)
		var leg: Node3D=root.get_node("Leg"+suffix);leg.scale.y=c.leg_length
		leg.position.y+=.8*(c.leg_length-1)
		for child in leg.get_children():
			if str(child.name).begins_with("Sneaker") or str(child.name).begins_with("Sole"):child.scale.x*=c.shoe_size;child.scale.z*=c.shoe_size
	body.position.y=.8*(c.leg_length-1)
	if c.bow_tie:
		for side in [-1,1]:_torso_ellipsoid(body,Vector3(side*.046,1.285,.138),Vector3(.043,.03,.018),accent,"BowTie",c)
		_torso_ellipsoid(body,Vector3(0,1.285,.155),Vector3(.016,.018,.015),accent,"TieKnot",c)
	if c.watch:
		ellipsoid(body.get_node("ArmL"),Vector3(0,-.405,0),Vector3(.08,.025,.08),material("303a45"),"WatchStrap")
		ellipsoid(body.get_node("ArmL"),Vector3(0,-.405,.077),Vector3(.035,.03,.012),accent,"WatchFace")
	if c.mustache:
		for side in [-1,1]:ellipsoid(head,Vector3(side*.03,-.086,.163),Vector3(.04,.015,.015),material(c.hair_color),"Mustache")
	if c.hat!="None":
		var hat_mat := material(c.hat_color)
		ellipsoid(head,Vector3(0,.21,0),Vector3(.24,.13,.185),hat_mat,"Hat")
		if c.hat in ["Cap","Hard hat"]:ellipsoid(head,Vector3(0,.15,.15),Vector3(.25,.025,.15),hat_mat,"Brim")
		if c.hat=="Beanie":ellipsoid(head,Vector3(0,.35,0),Vector3(.055,.055,.055),accent,"Pom")
static func _animations(root: Node3D) -> void:
	var player := AnimationPlayer.new();player.name="AnimationPlayer";root.add_child(player)
	var library := AnimationLibrary.new()
	for name in ["Idle","Walk","Seated"]:
		var anim := Animation.new();anim.length=4.0;anim.loop_mode=Animation.LOOP_LINEAR
		for path in ["LegL","LegR","Body/ArmL","Body/ArmR","Body/Head"]:
			var track := anim.add_track(Animation.TYPE_ROTATION_3D);anim.track_set_path(track,NodePath(path))
			var side := -1.0 if path.ends_with("L") else 1.0
			var node: Node3D=root.get_node(path)
			for step in range(33):
				var t := step/8.0
				var angle := sin(t*TAU)*(.55 if path.begins_with("Leg") else -.4)*side if name=="Walk" else sin(t*TAU/4)*.025
				if name=="Seated":angle=-1.35 if path.begins_with("Leg") else -.35+sin(t*TAU/4)*.025
				if path.ends_with("Head"):angle=sin(t*TAU/4)*.035
				anim.rotation_track_insert_key(track,t,node.quaternion*Quaternion(Vector3.RIGHT,angle))
		for eye_root in ["Body/Head/EyeL","Body/Head/EyeR"]:
			# The bundled legacy GLB still has group-only eyes. Keep its existing
			# animation seam while newly built rigs isolate blink on a child.
			var eye: String=eye_root+"/Blink" if root.has_node(eye_root+"/Blink") else eye_root
			var track := anim.add_track(Animation.TYPE_SCALE_3D);anim.track_set_path(track,NodePath(eye))
			for key in [[0,1],[2.7,1],[2.78,.06],[2.86,1],[4,1]]:anim.scale_track_insert_key(track,key[0],Vector3(1,key[1],1))
		library.add_animation(name,anim)
	player.add_animation_library("",library)
static func save_glb(config: Dictionary,path: String,modern_body: Dictionary = {}) -> Error:
	var model := build(config,modern_body)
	var document := GLTFDocument.new();var state := GLTFState.new()
	var error := document.append_from_scene(model,state)
	if error==OK:error=document.write_to_filesystem(state,path)
	model.free()
	return error
