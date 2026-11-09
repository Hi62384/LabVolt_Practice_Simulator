extends CharacterBody3D

const MAX_SWIVEL_SPEED := 9.0
var roll_audio: AudioStreamPlayer3D
var previous_position := Vector3.ZERO
var occupant := 0
var fixed_seat := false
var fixed_yaw := 0.0
var drive := Vector2.ZERO
var drive_yaw := 0.0
var turn_target := 0.0
var network_target := Vector3.ZERO
var network_yaw := 0.0
var network_ready := false
var rider: CharacterBody3D
var rider_collision: CollisionShape3D
var swivel: Node3D
var spin := 0.0
var spin_goal := 0.0
var previous_turn_target := 0.0
var wheels: Array = []

func build(game: Node3D) -> void:
	roll_audio=AudioStreamPlayer3D.new()
	roll_audio.bus = "Effects"
	roll_audio.stream=game.sfx.bank.roll
	roll_audio.max_distance=7
	roll_audio.volume_db=-32
	add_child(roll_audio)
	# Rolling bodies must accumulate gentle pushes instead of treating them as standing still.
	floor_stop_on_slope=false
	collision_layer=1
	collision_mask=1
	var collision := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius=.36
	shape.height=.56
	collision.shape=shape
	collision.position.y=.3
	add_child(collision)
	rider_collision=CollisionShape3D.new()
	var rider_shape := CapsuleShape3D.new()
	rider_shape.radius=.30
	rider_shape.height=.84
	rider_collision.shape=rider_shape
	rider_collision.position.y=.82
	rider_collision.disabled=true
	add_child(rider_collision)
	game._cylinder(self,Vector3(0,.27,0),.045,.42,Color("b6bcc0"),.85)
	for i in range(5):
		var angle := TAU*i/5
		var tip := Vector3(sin(angle)*.32,.10,cos(angle)*.32)
		game._line(self,Vector3(0,.16,0),tip,.025,Color("7b858c"),.8)
		var wheel: MeshInstance3D = game._cylinder(self,tip-Vector3(0,.045,0),.055,.065,Color("20262b"))
		wheel.rotation.z=PI*.5
		wheels.append(wheel)
	swivel=Node3D.new()
	add_child(swivel)
	game._box(swivel,Vector3(0,.51,0),Vector3(.55,.12,.53),Color("30434d"))
	game._box(swivel,Vector3(0,.83,.23),Vector3(.53,.52,.09),Color("30434d"))
	for x in [-.3,.3]:
		game._line(swivel,Vector3(x,.49,.1),Vector3(x,.72,.1),.018,Color("6d777c"),.7)
		game._box(swivel,Vector3(x,.73,0),Vector3(.065,.045,.35),Color("20292e"))
	var target := StaticBody3D.new()
	target.set_meta("role","chair")
	target.set_meta("label","Rolling chair")
	var hit := CollisionShape3D.new()
	var hit_shape := BoxShape3D.new()
	hit_shape.size=Vector3(.58,.6,.56)
	hit.shape=hit_shape
	hit.position.y=.72
	target.add_child(hit)
	add_child(target)
	add_collision_exception_with(target)

func _physics_process(delta: float) -> void:
	if roll_audio!=null:
		var speed := position.distance_to(previous_position)/maxf(delta,.001)
		previous_position=position
		roll_audio.volume_db=-38+clampf(speed*8,0,12)
		if speed>.08 and not roll_audio.playing:
			roll_audio.play()
		elif speed<=.08:
			roll_audio.stop()
	if swivel==null:
		return
	var occupied := occupant!=0 or is_instance_valid(rider)
	if rider_collision.disabled==occupied:
		rider_collision.disabled=not occupied
	var has_turn_input := false
	if not multiplayer.is_server() and not is_instance_valid(rider):
		if network_ready:
			position=position.lerp(network_target,1-exp(-18*delta))
			swivel.rotation.y=lerp_angle(swivel.rotation.y,network_yaw,1-exp(-18*delta))
		return
	var wish := drive
	var facing := drive_yaw
	if is_instance_valid(rider):
		wish = Vector2(float(rider.down("right"))-float(rider.down("left")),float(rider.down("back"))-float(rider.down("forward"))).normalized()
		facing = rider.global_rotation.y
		turn_target=rider.seated_look.chair_turn
	if occupied:
		var direction := Basis(Vector3.UP, facing)*Vector3(wish.x,0,wish.y)
		var horizontal := Vector3(velocity.x,0,velocity.z)
		# Opposing pushes brake harder than ordinary acceleration.
		var acceleration := 2.8 if direction.dot(horizontal)<-.05 else .60
		horizontal+=direction*acceleration*delta
		horizontal=horizontal.limit_length(6.5)
		velocity.x=horizontal.x
		velocity.z=horizontal.z
		# Mouse displacement supplies angular impulse, rather than a target angle
		# that would automatically pull the chair back after coasting.
		var turn_input := wrapf(turn_target-previous_turn_target,-PI,PI)
		has_turn_input=absf(turn_input)>0.00001
		var braking := turn_input*spin<0
		spin_goal=clampf(spin_goal+turn_input * (12.0 if braking else 3.8), -MAX_SWIVEL_SPEED, MAX_SWIVEL_SPEED)
	previous_turn_target=turn_target
	if not has_turn_input:
		spin_goal*=exp(-.85*delta)
	var angular_acceleration := 14.0 if spin_goal * spin < 0 else 6.0 if absf(spin_goal) < absf(spin) else 5.0
	spin=move_toward(spin,spin_goal,angular_acceleration*delta)
	if not has_turn_input:
		spin*=exp(-.28*delta)
		if absf(spin_goal)<0.002:spin_goal=0.0
		if absf(spin)<0.002:spin=0.0
	swivel.rotation.y+=spin*delta
	var horizontal := Vector2(velocity.x,velocity.z).move_toward(Vector2.ZERO,.20*delta)
	velocity.x=horizontal.x
	velocity.z=horizontal.y
	velocity.y=-2
	move_and_slide()
	for wheel in wheels:
		wheel.rotate_y(Vector2(velocity.x,velocity.z).length()*delta/.055)

