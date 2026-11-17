extends Node
const Shock=preload("res://scripts/campus/health/shock_model.gd")
const RESPAWN=Vector3(13,.05,-18)
var game: Node
var people := {}
var elapsed := 0.0
var send_clock := 0.0
var last_sent := {}
var bar: ProgressBar
var health_caption: Label
var health_value: Label
var death_screen: Control
var death_count: Label
var overlay: CanvasLayer
var shock_flash: ColorRect
var shock_audio: AudioStreamPlayer
var shock_clock := 0.0
var spark_views := {}
var shock_pose := {}

func build(owner_game: Node) -> void:
 game=owner_game
 overlay=CanvasLayer.new();overlay.layer=48;add_child(overlay)
 bar=ProgressBar.new();bar.min_value=0;bar.max_value=100;bar.value=100;bar.show_percentage=false
 bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
 bar.offset_left=-253;bar.offset_right=275;bar.offset_top=-117;bar.offset_bottom=-99
 var back:=StyleBoxFlat.new();back.bg_color=Color("351a21");back.set_corner_radius_all(3)
 var fill:=StyleBoxFlat.new();fill.bg_color=Color("e04450");fill.set_corner_radius_all(3)
 bar.add_theme_stylebox_override("background",back);bar.add_theme_stylebox_override("fill",fill);overlay.add_child(bar)
 health_caption=Label.new();health_caption.text="+";health_caption.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;health_caption.add_theme_font_size_override("font_size",22)
 health_caption.add_theme_color_override("font_color",Color("ffffff"));health_caption.add_theme_color_override("font_shadow_color",Color("14242c"))
 health_caption.add_theme_constant_override("shadow_offset_x",1);health_caption.add_theme_constant_override("shadow_offset_y",1)
 health_caption.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
 health_caption.offset_left=-281;health_caption.offset_right=-257;health_caption.offset_top=-123;health_caption.offset_bottom=-96
 overlay.add_child(health_caption)
 health_value=Label.new();health_value.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;health_value.add_theme_font_size_override("font_size",12)
 health_value.add_theme_color_override("font_color",Color("ffffff"));health_value.add_theme_color_override("font_shadow_color",Color("14242c"))
 health_value.add_theme_constant_override("shadow_offset_x",1);health_value.add_theme_constant_override("shadow_offset_y",1)
 health_value.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
 health_value.offset_left=-70;health_value.offset_right=70;health_value.offset_top=-117;health_value.offset_bottom=-99
 overlay.add_child(health_value)
 shock_flash=ColorRect.new();shock_flash.mouse_filter=Control.MOUSE_FILTER_IGNORE
 shock_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);shock_flash.color=Color(0.7,0.86,1.0,0);overlay.add_child(shock_flash)
 shock_audio=AudioStreamPlayer.new();shock_audio.stream=_shock_sound();shock_audio.volume_db=-16;add_child(shock_audio)
 death_screen=ColorRect.new();death_screen.color=Color(.08,.015,.025,.91);death_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);overlay.add_child(death_screen)
 var center:=CenterContainer.new();center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);death_screen.add_child(center)
 var column:=VBoxContainer.new();center.add_child(column)
 var heading:=Label.new();heading.text="YOU DIED";heading.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;heading.add_theme_font_size_override("font_size",56);column.add_child(heading)
 death_count=Label.new();death_count.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;death_count.add_theme_font_size_override("font_size",22);column.add_child(death_count)
 death_screen.hide()
 game.session.health_block_action=blocks_action
 game.session.health_pose_guard=guard_position
 game.session.roster_changed.connect(_roster_changed)
 game.session.leaving.connect(_reset)
 game.session.restarted.connect(_reset)
 multiplayer.peer_disconnected.connect(_remove)
 _roster_changed()
func _new() -> Dictionary:return {"health":100.0,"arrested":false,"dead":false,"remaining":0.0,"position":Vector3.ZERO,"shocked":false}
func _reset() -> void:
 people.clear();last_sent.clear();game.player.shock_locked=false
 for peer in shock_pose.keys():
  if game.avatars.has(peer) and is_instance_valid(game.avatars[peer]):
   game.avatars[peer].rotation.x=shock_pose[peer].x
   game.avatars[peer].rotation.z=shock_pose[peer].y
 shock_pose.clear()
 for spark in spark_views.values():
  if is_instance_valid(spark):spark.queue_free()
 spark_views.clear()
 if is_instance_valid(shock_audio):shock_audio.stop()
 if is_instance_valid(shock_flash):shock_flash.color.a=0
 if is_instance_valid(death_screen):death_screen.hide()
func _remove(peer: int) -> void:
 if multiplayer.is_server():people.erase(peer)
func _roster_changed() -> void:
 if not multiplayer.is_server():return
 for peer in game.session.roster:
  if not people.has(peer):people[peer]=_new()
 _broadcast(true)
func heal_from_food(peer: int) -> void:
 if not multiplayer.is_server() or not people.has(peer):return
 var person: Dictionary=people[peer]
 if person.get("dead",false):return
 person.health=minf(100.0,float(person.health)+8.0)
 _broadcast(true)

func locked(peer: int) -> bool:
 var p:Dictionary=people.get(peer,{})
 return bool(p.get("dead",false)) or bool(p.get("arrested",false))
func blocks_action(peer: int, _action: Dictionary) -> bool:return locked(peer)
func guard_position(peer: int, proposed: Vector3) -> Vector3:
 var p:Dictionary=people.get(peer,{})
 return p.get("position",proposed) if locked(peer) else proposed
func _voltage_at(peer: int) -> float:
 var result:=0.0
 for lab in game.session.labs:
  if not lab.powered:continue
  var cable:Dictionary=lab.holding(peer)
  if cable.is_empty():continue
  var anchor:String=str(cable.a if cable.a!="" else cable.b)
  if anchor.is_empty() or (cable.a!="" and cable.b!=""):continue
  var ac:Vector2=lab.readings.get("voltages",{}).get(anchor,Vector2.ZERO)
  var dc:Vector2=lab.readings.get("dc_voltages",{}).get(anchor,Vector2.ZERO)
  result=maxf(result,sqrt(ac.length_squared()+dc.length_squared()))
 var dc_lab=game.dc_lab
 if dc_lab.carried_leads.has(peer) and dc_lab.pending_endpoints.has(peer):
  var endpoint:Dictionary=dc_lab.pending_endpoints[peer]
  var index:int=int(endpoint.get("station",-1));var port:String=str(endpoint.get("port",""))
  if index>=0 and index<dc_lab.benches.size():
   var station=dc_lab.benches[index]
   var potentials:Dictionary=station.result.get("v",{})
   if potentials.has(port):
    var v:float=float(potentials[port])
    var reference:float=float(potentials.get("GND",potentials.get("REF",potentials.get("COM",0.0))))
    result=maxf(result,absf(v-reference))
 return result
func _process(delta: float) -> void:
 if not is_instance_valid(game):return
 bar.visible=is_instance_valid(game.front) and game.front.in_game and game.player.enabled and not death_screen.visible
 health_caption.visible=bar.visible;health_value.visible=bar.visible
 if multiplayer.is_server():
  elapsed+=minf(delta,.25);send_clock+=delta
  if elapsed>=.2:
   var dt:=elapsed;elapsed=0
   for peer in game.session.roster.keys():
    if not people.has(peer):people[peer]=_new()
    var p:Dictionary=people[peer]
    if p.dead:
     p.remaining=maxf(0.0,float(p.remaining)-dt)
     if p.remaining<=0:_respawn_peer(int(peer))
     continue
    var was_locked:bool=p.arrested
    var result:Dictionary=Shock.apply_exposure(float(p.health),_voltage_at(int(peer)),dt,game.dc_lab.carried_leads.has(peer) and game.dc_lab.pending_endpoints.has(peer))
    p.shocked=float(result.health)<float(p.health)
    p.health=result.health;p.arrested=result.arrested
    if p.arrested and not was_locked:p.position=_position(int(peer))
    if p.health<=0:
     p.dead=true;p.arrested=false;p.shocked=false;p.remaining=Shock.RESPAWN_SECONDS;p.position=_position(int(peer))
     _release_wire(int(peer))
     _spawn_burst(p.position)
     if game.session.online:_burst.rpc(p.position)
   if send_clock>=.25:send_clock=0;_broadcast()
 _apply_local()
 _shock_feedback(delta)
 for id in game.avatars:
  if is_instance_valid(game.avatars[id]):game.avatars[id].visible=not bool(people.get(id,{}).get("dead",false))
func _position(peer: int) -> Vector3:
 return game.player.global_position if peer==multiplayer.get_unique_id() else game.session.poses.get(peer,{}).get("position",Vector3.ZERO)
func _release_wire(peer: int) -> void:
 var changed:=false
 for lab in game.session.labs:
  var lab_changed:=false
  for cable in lab.cables:
   if cable.owner==peer:cable.owner=0;changed=true;lab_changed=true
  if lab_changed:lab.revision+=1
 if changed:game.session.broadcast()
 var dc=game.dc_lab
 dc.carried_leads.erase(peer);dc.carried_lead_stations.erase(peer);dc.pending_endpoints.erase(peer)
 if peer==multiplayer.get_unique_id():dc._finish_kit_lead()
 elif game.session.online:dc._finish_kit_lead.rpc_id(peer)
func _respawn_peer(peer: int) -> void:
 people[peer]=_new()
 if game.session.poses.has(peer):
  game.session.poses[peer].position=RESPAWN
  game.session.last_pose[peer]=Time.get_ticks_msec()
 if peer==multiplayer.get_unique_id():_respawn()
 elif game.session.online:_respawn.rpc_id(peer)
@rpc("authority","call_remote","reliable")
func _respawn() -> void:
 game.player.global_position=RESPAWN;game.player.velocity=Vector3.ZERO
 game.player.safe_recovery=preload("res://scripts/campus/presentation/navigation_safety/safe_recovery.gd").new(RESPAWN)
 game.session.send_pose({"position":RESPAWN,"yaw":game.player.rotation.y,"pitch":0.0,"crouch":false})
func _broadcast(force := false) -> void:
 if not multiplayer.is_server():return
 if not force and people==last_sent:return
 last_sent=people.duplicate(true)
 if game.session.online:
  for peer in game.session.connected_peers():_receive.rpc_id(peer,people)
@rpc("authority","call_remote","reliable")
func _receive(data: Dictionary) -> void:
 if multiplayer.get_remote_sender_id()!=1:return
 people=data
func _apply_local() -> void:
 var p:Dictionary=people.get(multiplayer.get_unique_id(),_new())
 game.player.shock_locked=bool(p.dead) or bool(p.arrested)
 bar.value=float(p.health)
 health_value.text="%d / 100" % roundi(clampf(float(p.health),0.0,100.0))
 death_screen.visible=bool(p.dead)
 if p.dead:death_count.text="Respawning in %d seconds" % ceili(float(p.remaining))
@rpc("authority","call_remote","reliable")
func _burst(position: Vector3) -> void:_spawn_burst(position)
func _spawn_burst(position: Vector3) -> void:
 var particles:=CPUParticles3D.new();particles.position=position+Vector3.UP
 particles.amount=250;particles.lifetime=1.8;particles.one_shot=true;particles.explosiveness=1.0
 particles.direction=Vector3.UP;particles.spread=180.0;particles.initial_velocity_min=4.0;particles.initial_velocity_max=10.0
 particles.gravity=Vector3(0,-12,0);particles.scale_amount_min=.04;particles.scale_amount_max=.13
 var mesh:=SphereMesh.new();mesh.radius=.06;mesh.height=.12
 var mat:=StandardMaterial3D.new();mat.albedo_color=Color("a51324");mesh.material=mat;particles.mesh=mesh
 game.add_child(particles);particles.emitting=true
 var timer:=get_tree().create_timer(3.0)
 timer.timeout.connect(func():if is_instance_valid(particles):particles.queue_free())

func _shock_sound() -> AudioStreamWAV:
 var sample_rate := 22050
 var samples := PackedByteArray();samples.resize(int(sample_rate*.16)*2)
 var random := RandomNumberGenerator.new();random.seed=1782
 for i in samples.size()/2:
  var t := float(i)/sample_rate
  var envelope := 1.0-t/.16
  var wave := sin(TAU*110.0*t)*.35+random.randf_range(-1.0,1.0)*.4
  var sample := int(clampf(wave*envelope,-1.0,1.0)*20000.0)
  samples.encode_s16(i*2,sample)
 var sound := AudioStreamWAV.new();sound.format=AudioStreamWAV.FORMAT_16_BITS;sound.mix_rate=sample_rate;sound.data=samples
 return sound

func _shock_feedback(delta: float) -> void:
 shock_clock+=delta
 var local: Dictionary=people.get(multiplayer.get_unique_id(),{})
 var active: bool = bool(local.get("shocked",false)) and not bool(local.get("dead",false)) and game.front.in_game
 shock_flash.color=Color(.65,.80,1.0,(.10+.10*absf(sin(shock_clock*25.0))) if active else 0.0)
 if active and not shock_audio.playing:shock_audio.play()
 elif not active and shock_audio.playing:shock_audio.stop()
 for peer in people:
  var person: Dictionary=people[peer]
  var show_sparks: bool = bool(person.get("shocked",false)) and not bool(person.get("dead",false)) and game.front.in_game
  if game.avatars.has(peer) and is_instance_valid(game.avatars[peer]):
   var avatar: Node3D=game.avatars[peer]
   if show_sparks:
    if not shock_pose.has(peer):shock_pose[peer]=Vector2(avatar.rotation.x,avatar.rotation.z)
    avatar.rotation.x=shock_pose[peer].x+sin(shock_clock*37.0+float(peer))*.035
    avatar.rotation.z=shock_pose[peer].y+sin(shock_clock*29.0+float(peer)*.7)*.055
   elif shock_pose.has(peer):
    avatar.rotation.x=shock_pose[peer].x
    avatar.rotation.z=shock_pose[peer].y
    shock_pose.erase(peer)
  if show_sparks:
   if not spark_views.has(peer):spark_views[peer]=_make_sparks()
   var spark: CPUParticles3D=spark_views[peer]
   spark.global_position=_position(int(peer))+Vector3.UP
  elif spark_views.has(peer):
   spark_views[peer].queue_free();spark_views.erase(peer)
 for peer in spark_views.keys():
  if not people.has(peer):spark_views[peer].queue_free();spark_views.erase(peer)
 for peer in shock_pose.keys():
  if people.has(peer):continue
  if game.avatars.has(peer) and is_instance_valid(game.avatars[peer]):
   game.avatars[peer].rotation.x=shock_pose[peer].x
   game.avatars[peer].rotation.z=shock_pose[peer].y
  shock_pose.erase(peer)

func _make_sparks() -> CPUParticles3D:
 var particles := CPUParticles3D.new();particles.amount=18;particles.lifetime=.25;particles.emitting=true
 particles.emission_shape=CPUParticles3D.EMISSION_SHAPE_SPHERE;particles.emission_sphere_radius=.4
 particles.direction=Vector3.UP;particles.spread=180;particles.initial_velocity_min=1.0;particles.initial_velocity_max=3.0
 particles.gravity=Vector3(0,-4,0);particles.scale_amount_min=.15;particles.scale_amount_max=.4
 var mesh := SphereMesh.new();mesh.radius=.035;mesh.height=.07
 var material := StandardMaterial3D.new();material.albedo_color=Color("d3edff");material.emission_enabled=true;material.emission=Color("79bfff");material.emission_energy_multiplier=2.0;mesh.material=material
 particles.mesh=mesh;game.add_child(particles);return particles
