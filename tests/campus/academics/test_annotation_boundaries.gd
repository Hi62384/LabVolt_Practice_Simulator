extends SceneTree

class School:
	extends "res://scripts/school_session.gd"
	var broadcasts := 0
	func broadcast() -> void:
		broadcasts+=1

class Game:
	extends Node
	var session := {"poses":{11:{"position":Vector3.ZERO}}}

func annotation() -> Dictionary:
	return {
		"id":"note",
		"kind":"text",
		"text":"Working",
		"position":Vector2(0.5,0.5),
		"font":"Sans",
		"color":"263743"
	}

func reset(school) -> void:
	school.last_requests.clear()
	school.identities={11:"a".repeat(48)}
	school.activity={}
	school.phase="freeplay"
	school.papers={
		7:{
			"id":7,
			"owner":11,
			"identity":"a".repeat(48),
			"held":true,
			"position":Vector3.ZERO,
			"lesson":true,
			"class_round":0,
			"project":{"questions":[]},
			"mark":{},
			"revision":0,
			"annotations":{}
		}
	}

func send(school, item: Dictionary, peer: int=11) -> void:
	school.apply(peer,{"op":"annotation","id":7,"item":item,"page":0})

func rejected(school, item: Dictionary, peer: int=11) -> void:
	var before: Dictionary=school.papers.duplicate(true)
	var broadcasts: int=school.broadcasts
	send(school,item,peer)
	assert(school.papers==before,"rejected request mutated paper")
	assert(school.broadcasts==broadcasts,"rejected request broadcast")

func _initialize() -> void:
	var game=Game.new()
	var school=School.new()
	school.game=game
	# Neither node enters the tree; build/_process/save/network never run.

	reset(school)
	send(school,annotation())
	var saved: Dictionary=school.papers[7].annotations["0"][0]
	assert(saved.angle==0.0 and saved.font_size==24)

	for missing in ["angle","font_size"]:
		reset(school)
		var item=annotation()
		item.angle=0.25
		item.font_size=30
		item.erase(missing)
		send(school,item)
		saved=school.papers[7].annotations["0"][0]
		assert(saved.angle==(0.0 if missing=="angle" else 0.25))
		assert(saved.font_size==(24 if missing=="font_size" else 30))

	for field in ["angle","font_size"]:
		for bad in [{},[],true,"24",null,NAN,INF,-INF]:
			reset(school)
			var item=annotation()
			item[field]=bad
			rejected(school,item)

	for extreme in [-1.0e300,1.0e300]:
		reset(school)
		var item=annotation()
		item.angle=extreme
		item.font_size=extreme
		send(school,item)
		saved=school.papers[7].annotations["0"][0]
		assert(saved.font_size==(10 if extreme<0 else 72))
		assert(is_equal_approx(saved.angle,-PI if extreme<0 else PI))

	reset(school)
	rejected(school,annotation(),22) # Unidentified sender.

	reset(school)
	school.identities[22]="b".repeat(48)
	rejected(school,annotation(),22) # Identified nonowner.

	reset(school)
	school.papers[7].mark={"score":100}
	rejected(school,annotation()) # Marked work is immutable.

	reset(school)
	school.papers[7].held=false
	school.papers[7].position=Vector3(100,0,100)
	rejected(school,annotation()) # Remote paper is unreachable.

	reset(school)
	var baked=annotation()
	baked.angle=0.0
	baked.font_size=24
	baked.baked=true
	school.papers[7].annotations={"0":[baked.duplicate(true)]}
	rejected(school,annotation()) # Existing baked object is immutable.

	school.free()
	game.free()
	print("PASS production annotation apply boundaries; no RPC/durable-save proof")
	quit()
