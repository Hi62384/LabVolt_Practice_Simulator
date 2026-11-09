extends SceneTree
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var Profile=load("res://scripts/electronics_profile.gd")
	var a=Profile.new();var b=Profile.new();a.open("trade-a");b.open("trade-b")
	var start_a=a.data.inventory.duplicate();var start_b=b.data.inventory.duplicate()
	var pa={"id":"exchange-1","host":"host-a","give":{"r1000":2},"take":{"r220":1},"definitions":{}}
	var pb={"id":"exchange-1","host":"host-a","give":{"r220":1},"take":{"r1000":2},"definitions":{}}
	assert(a.prepare_trade(pa)=="");assert(b.prepare_trade(pb)=="")
	assert(a.buy("r1000",1)=="Finish the pending trade first")
	var restarted=Profile.new();restarted.open("trade-a")
	assert(restarted.data.pending_trade.id=="exchange-1")
	assert(restarted.commit_trade("exchange-1")=="");assert(b.commit_trade("exchange-1")=="")
	assert(restarted.commit_trade("exchange-1")=="")
	assert(restarted.data.inventory.r1000==start_a.r1000-2)
	assert(restarted.data.inventory.r220==start_a.r220+1)
	assert(b.data.inventory.r1000==start_b.r1000+2)
	assert(b.data.inventory.r220==start_b.r220-1)
	assert(restarted.prepare_trade({"id":"bad","give":{"r1000":10000},"take":{},"definitions":{}})!="")
	var Custom=load("res://scripts/custom_circuit.gd")
	var defs={"ic:leaf":{"name":"R","pins":[{"name":"a","node":"a"},{"name":"b","node":"b"}],"parts":[{"id":"r","type":"r1000","a":"a","b":"b"}],"wires":[]}}
	for level in 7:
		var parts=[]
		for i in 48:parts.append({"id":str(i),"type":"ic:leaf" if level==0 else "ic:"+str(level-1),"nodes":["a","b"]})
		defs["ic:"+str(level)]={"name":"Large","pins":defs["ic:leaf"].pins,"parts":parts,"wires":[]}
	assert("exceeds" in Custom.validate("ic:6",defs))
	assert(restarted.prepare_trade({"id":"cancelled","give":{},"take":{},"definitions":{}})=="")
	restarted.abort_trade("cancelled");assert(not restarted.data.has("pending_trade"))
	print("PASS: durable prepare/restart/commit, duplicate commit is idempotent, purchases locked, insufficient inventory rejected, cancellation, bounded nested expansion")
	quit()
