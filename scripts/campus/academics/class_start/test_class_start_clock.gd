extends SceneTree
const Clock = preload("res://scripts/campus/academics/class_start/class_start_clock.gd")

func _initialize() -> void:
	var c = Clock.new()
	assert(c.arm("session-a",1000000))
	assert(not c.arm("session-a",90000000)) # duplicate start cannot extend the wait
	assert(c.remaining(1000000)==120.0)
	assert(not c.arrive("host",120999999).late)
	assert(not c.due(120999999))
	assert(c.arrive("client",121000000).late) # equality is late
	assert(not c.arrive("host",121000001).late) # reconnect retains first arrival
	assert(c.begin_if_due(121000000))
	assert(not c.begin_if_due(121000001))
	assert(c.snapshot(121000001).started)
	c.cancel()
	assert(not c.due(999999999))
	assert(c.arm("session-b",200000000))
	assert(c.arrivals.is_empty())
	assert(c.arrive("host",200000000).late==false)
	assert(c.remaining(320000000)==0.0)
	assert(c.restore("session-b",3.5,400000000,{"host":false,"client":true}))
	assert(c.remaining(400000000)==3.5)
	assert(not c.arrive("host",403500000).late)
	assert(c.arrive("client",400000000).late)
	assert(c.begin_if_due(403500000))
	quit()
