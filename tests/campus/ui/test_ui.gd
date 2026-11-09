extends SceneTree
class Crowd:
	extends RefCounted
	var density := ""
	func set_density(value: String) -> void: density=value
class AcademicFixture:
	extends Node
	var local_identity := "private-academic-id"
	var gradebook := {
		"late":{"profile":"private-academic-id","course_id":"ETY155","week":1,"kind":"lecture","score":90.0,"time":"2026-11-04T12:00:00"},
		"early":{"profile":"private-academic-id","course_id":"ETY155","week":1,"kind":"lecture","score":95.0,"time":"2026-11-03T12:00:00"},
		"practice":{"profile":"private-academic-id","course_id":"ETY155","week":1,"kind":"lab","score":99.0,"lesson":true},
		"other":{"profile":"someone-else","course_id":"ETY155","week":1,"kind":"lecture","score":100.0},
		"ac":{"profile":"private-academic-id","course_id":"ELM253","week":1,"kind":"lab","score":88.0}}
var failures := 0
var assertions := 0
func check(ok: bool, message: String) -> void:
	assertions+=1
	if not ok: failures+=1; push_error(message)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var paths := ["campus_theme","profile_visibility","campus_adapter","campus_dashboard","campus_hud","campus_map","graphics_settings","profile_inspector"]
	for path in paths: check(load("res://scripts/campus/ui/"+path+".gd")!=null,"load "+path)
	var Profiles := load("res://scripts/campus/social/public_profiles.gd")
	var source := {"money":{"dollars":120,"password":"SECRET"},"course":{"course_id":"ETY155","overall":92.0},"firmware":{"memory":"SECRET"},"credential":"SECRET"}
	var a: Dictionary=Profiles.project("stable-A","Same",source,{"money":true})
	var b: Dictionary=Profiles.project("stable-B","Same",source,{"money":true})
	check(a.id!=b.id and a.name==b.name,"duplicate names preserve identities")
	check(not JSON.stringify(a).contains("SECRET") and not a.has("firmware"),"no secrets")
	check(not a.has("course"),"privacy default deny")
	var hidden: Dictionary=Profiles.project("stable-A","New",source,{})
	var update: Dictionary=Profiles.delta(a,hidden,3)
	check("money" in update.remove,"privacy change emits removal")
	var merged: Dictionary=Profiles.apply_delta(a,update)
	check(not merged.has("money") and merged.name=="New","delta removes data and renames stable identity")
	check(Profiles.apply_delta(merged,Profiles.delta(hidden,a,2))==merged,"stale revision rejected")
	check(Profiles.clean_name(" <b>Student\n[ADMIN] ").length()<=24,"name bounded")
	var Tags := load("res://scripts/campus/social/name_tags.gd")
	check(Tags.relevant(Vector3.ZERO,Vector3(0,0,5),true,false),"nearby name tag")
	check(not Tags.relevant(Vector3.ZERO,Vector3(0,0,5),true,true),"occluded name tag hidden")
	check(not Tags.relevant(Vector3.ZERO,Vector3(0,0,5),false,false),"out-of-zone name tag hidden")
	var graphics: Node = load("res://scripts/campus/ui/graphics_settings.gd").new()
	root.add_child(graphics)
	var world := Node3D.new(); root.add_child(world)
	var camera := Camera3D.new(); camera.far=500; world.add_child(camera)
	var light := OmniLight3D.new(); light.shadow_enabled=true; world.add_child(light)
	var mesh := MeshInstance3D.new(); mesh.mesh=BoxMesh.new(); mesh.material_override=StandardMaterial3D.new(); world.add_child(mesh)
	var shared: Material=mesh.material_override
	graphics.attach(root,world)
	graphics.set_option("view_distance",60.0); graphics.set_option("shadows",false); graphics.set_option("lights",false); graphics.set_option("aa",2); graphics.set_option("render_scale",0.75)
	check(camera.far==60 and not light.shadow_enabled and not light.visible,"real camera/light settings")
	check(root.msaa_3d==2 and is_equal_approx(root.scaling_3d_scale,0.75),"real viewport settings")
	check(mesh.visibility_range_end==60,"real geometry range")
	graphics.set_option("texture",0)
	check(mesh.get_active_material(0).texture_filter==BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS,"real material texture filter")
	check(mesh.material_override!=shared,"texture changes preserve shared source material")
	graphics.set_option("shadows",true); graphics.set_option("lights",true)
	check(light.shadow_enabled and light.visible,"restore original state")
	graphics.save_settings("user://test_graphics.cfg")
	var second: Node = load("res://scripts/campus/ui/graphics_settings.gd").new(); second.load_settings("user://test_graphics.cfg")
	check(second.options==graphics.options,"settings persistence")
	check(not second.set_option("unknown",42),"reject unknown settings")
	second.free()
	var crowd := Crowd.new(); graphics.set_crowd_adapter(crowd); graphics.set_option("npc_density","Off")
	check(crowd.density=="Off","real crowd adapter receives density")
	var streamed := Camera3D.new(); streamed.far=500; world.add_child(streamed); graphics.register_node(streamed)
	check(streamed.far==60,"streamed camera receives current distance")
	graphics.preset("Medium")
	world.queue_free(); graphics.queue_free()
	var replication: RefCounted=load("res://scripts/campus/social/profile_replication.gd").new()
	replication.publish("stable-A","Same",source,{"money":true})
	var first: Array=replication.collect(2,["stable-A"])
	check(first.size()==1 and first[0].id!="stable-A" and not JSON.stringify(first).contains("stable-A"),"first snapshot conceals private identity")
	check(replication.collect(2,["stable-A"]).is_empty(),"unchanged public fields send nothing")
	replication.publish("stable-A","Changed",source,{})
	var packets: Array=replication.collect(2,["stable-A"])
	check(packets.size()==1 and "money" in packets[0].remove,"replicated privacy revocation")
	check(replication.collect(3,[]).is_empty(),"irrelevant peer receives nothing")
	var cache: RefCounted=load("res://scripts/campus/social/profile_cache.gd").new()
	check(cache.receive(packets[0]),"cache accepts fresh packet")
	var clear_packet: Dictionary=replication.collect(2,[])[0]
	check(clear_packet.clear and cache.receive(clear_packet) and cache.profiles.is_empty(),"interest exit clears stale card")
	check(not cache.receive(packets[0]),"cleared card cannot reappear through stale delta")
	check(cache.receive(replication.collect(2,["stable-A"])[0]) and cache.profiles.has(packets[0].id),"interest reentry restores current projection")
	var academic := AcademicFixture.new()
	var adapter: RefCounted=load("res://scripts/campus/ui/campus_adapter.gd").new(); adapter.configure(academic,null,null)
	var progress: Dictionary=adapter.week_progress("ETY155",1)
	check(progress.lecture.count==2 and progress.lecture.best==95.0 and progress.lecture.recent==90.0,"week progress separates latest and best")
	check(progress.lab.count==0,"progress excludes practice other course and other student")
	academic.free()
	var privacy: RefCounted=load("res://scripts/campus/ui/profile_visibility.gd").new()
	privacy.values.money=true; privacy.save_settings("user://test_privacy.cfg")
	var restored: RefCounted=load("res://scripts/campus/ui/profile_visibility.gd").new(); restored.load_settings("user://test_privacy.cfg")
	check(restored.values.money and not restored.values.course,"privacy persistence")
	var library: Node=load("res://scripts/character_library.gd").new(); root.add_child(library)
	library.selected="stable-test-a"; check(library.rename_selected("Duplicate")==OK,"name save")
	library.selected="stable-test-b"; library.rename_selected("Duplicate")
	library.selected="stable-test-a"; check(library.display_name()=="Duplicate","duplicate name A saved")
	library.rename_selected("Changed"); library.selected="stable-test-b"; check(library.display_name()=="Duplicate","rename doesn't alter other identity")
	library.queue_free()
	print("UI_TEST_RESULT failures=",failures," assertions=",assertions)
	quit(1 if failures else 0)

