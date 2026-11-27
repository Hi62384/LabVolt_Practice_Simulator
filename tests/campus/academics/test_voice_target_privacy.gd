extends SceneTree
const Targeting=preload("res://scripts/campus/voice/conversation_targeting.gd")
func _initialize() -> void:
	var behind:={"id":"teacher","position":Vector3(0,0,-4),"visible":true}
	var human:=Vector3(0,0,-1.5)
	assert(Targeting.select([behind],Vector3.ZERO,Vector3.FORWARD,"",[human]).is_empty(),"An aligned NPC behind a human must not capture a new private human conversation")
	assert(Targeting.select([behind],Vector3.ZERO,Vector3.FORWARD,"",[Vector3(.12,0,-1.5)]).is_empty(),"Slight player movement must not route an aligned human conversation to AI")
	assert(Targeting.select([behind],Vector3.ZERO,Vector3.FORWARD,"",[Vector3(2,0,-1.5)]).id=="teacher","A human outside the addressed cone must not block an NPC conversation")
	var nearby:={"id":"near","position":Vector3(0,0,-1.5),"visible":true}
	assert(Targeting.select([nearby],Vector3.ZERO,Vector3.FORWARD,"",[Vector3(0,0,-4)]).id=="near","A farther human does not hide the nearer addressed NPC")
	assert(Targeting.select([behind],Vector3.ZERO,Vector3.FORWARD,"teacher",[human]).id=="teacher","An existing explicit conversation retains its follow-up target")
	behind.invited=true
	assert(Targeting.select([behind],Vector3.ZERO,Vector3.FORWARD,"",[human]).id=="teacher","A teacher invitation can address the player across a classroom")
	behind.invited=false;behind.visible=false
	assert(Targeting.select([behind],Vector3.ZERO,Vector3.FORWARD,"teacher").is_empty(),"Following a conversation never bypasses hearing visibility")
	var ambiguous:=[{"id":"left","position":Vector3(-.1,0,-2),"visible":true},{"id":"right","position":Vector3(.1,0,-2),"visible":true}]
	assert(Targeting.select(ambiguous,Vector3.ZERO,Vector3.FORWARD).is_empty(),"Ambiguous first contact does not fan out to multiple NPCs")
	print("VOICE_TARGET_PRIVACY PASS (nearby human occlusion, explicit follow-up, invitations and ambiguous targets)")
	quit(0)
