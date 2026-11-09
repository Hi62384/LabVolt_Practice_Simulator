extends SceneTree
const Ledger=preload("res://scripts/inventory_authority/ledger.gd")
const Profile=preload("res://scripts/electronics_profile.gd")
const Board=preload("res://scripts/breadboard_model.gd")
var checks := 0
func check(condition: bool,label: String) -> void:
	checks+=1
	if not condition:push_error("FAIL "+label);quit(1);assert(false,label)
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var root_path := "user://authority_unit_"+Crypto.new().generate_random_bytes(6).hex_encode()
	var p=Profile.new();p.open(root_path)
	var a := "a".repeat(48);var b := "b".repeat(48);var sa := "1".repeat(64);var sb := "2".repeat(64)
	var ledger=Ledger.new();check(ledger.open(root_path)==OK,"open empty ledger")
	check(ledger.bind(11,a,sa,p.data).ok,"initial import")
	check(ledger.bind(22,b,sb,p.data).ok,"second import")
	check(not ledger.bind(33,a,sa,p.data).ok,"simultaneous profile clone blocked")
	ledger.unbind(11)
	check(not ledger.bind(33,a,sb,p.data).ok,"stolen public identity blocked")
	check(ledger.bind(33,a,sa,p.data).profile.inventory.r1000==8,"reconnect imports local stock")
	check(ledger.offer_error(33,{"r1000":9},{})!="","forged offer")
	for bad in [-1,1.5,NAN,INF,"2",{},100001]:check(ledger.offer_error(33,{"r1000":bad},{})!="","invalid quantity "+str(bad))
	check(ledger.transact(33,"buy-1","buy",["r1000",2]).profile.inventory.r1000==10,"host purchase")
	check(ledger.transact(33,"buy-1","buy",["r1000",2]).profile.inventory.r1000==10,"purchase replay")
	check(not ledger.transact(33,"buy-1","buy",["r1000",3]).ok,"same ID different payload")
	check(not ledger.transact(33,"forged-reward","reward",["grade",100,2,false]).ok,"client reward unavailable")
	check(ledger.award(33,"grade",100,0,false).earned==60,"host reward")
	check(ledger.award(33,"grade",100,0,false).earned==0,"reward replay")
	var dollars: int=ledger.account(33).profile.dollars
	var metadata: Dictionary= ledger.account(33).profile.duplicate(true);metadata.dollars=999999;metadata.inventory.r1000=99999;metadata.analyzer=true;metadata.capacity=99999
	check(ledger.transact(33,"metadata","metadata",[metadata]).ok,"metadata accepted")
	check(ledger.account(33).profile.dollars==dollars and ledger.account(33).profile.inventory.r1000==10 and not ledger.account(33).profile.analyzer and ledger.account(33).profile.capacity==40,"economy forgery discarded")
	check(ledger.account(33).profile.reward_ids.has("grade"),"reward receipts cannot be cleared by metadata")
	check(not ledger.transact(33,"bad-bundle","bundle",[{"r1000":1000},0]).ok,"client cannot invent free bundle")
	check(ledger.transact(33,"bundle","bundle",[{"diode":6,"led":6}]).profile.dollars==dollars-24,"bundle price derived by host")
	check(not ledger.transact(33,"fraction","buy",["r1000",1.5]).ok,"fractional purchase rejected")
	check(ledger.transact(33,"capacity","capacity",[]).profile.capacity==60,"capacity host purchase")
	check(ledger.transact(33,"capacity","capacity",[]).profile.capacity==60,"capacity replay")
	var board := Board.empty();board.parts=[{"id":"r","type":"r1000","a":"A1","b":"F1"}]
	check(ledger.deploy(33,0,board)=="","owned deployment")
	check(ledger.free_stock(33,"r1000")==9,"reservation")
	check(ledger.deploy(33,1,board)!="","second deployment blocked")
	check(ledger.offer_error(33,{"r1000":10},{})!="","deployed stock cannot trade")
	var bad_board := board.duplicate(true);bad_board.parts[0].type="r100000"
	check(ledger.deployment_error(33,bad_board)!="","unowned deployment")
	bad_board=board.duplicate(true);bad_board.rows={}
	check(ledger.deployment_error(33,bad_board)!="","malformed deployment")
	check(ledger.recall(33),"recall")
	check(ledger.free_stock(33,"r1000")==10,"release stock")
	ledger.creative=true
	check(ledger.deployment_error(33,board)=="","creative deployment")
	check(ledger.offer_error(33,{"r1000":1},{})!="","creative trade excluded")
	check(not ledger.award(33,"creative-grade",100,2,false).ok,"creative reward excluded")
	check(ledger.account(33).profile.inventory.r1000==10,"creative stock unchanged")
	ledger.creative=false
	var offers := {33:{"r1000":2},22:{"r220":1}}
	check(ledger.exchange("trade-1",[33,22],offers,{}).ok,"atomic trade")
	check(ledger.account(33).profile.inventory.r1000==8 and ledger.account(22).profile.inventory.r1000==10,"two-sided stock")
	check(ledger.exchange("trade-1",[33,22],offers,{}).ok and ledger.account(33).profile.inventory.r1000==8,"duplicate trade")
	var restarted=Ledger.new();check(restarted.open(root_path)==OK,"restart ledger")
	check(restarted.bind(44,a,sa,ledger.account(33).profile).profile.inventory.r1000==8,"restart/rebind same identity")
	check(restarted.bind(55,b,sb,ledger.account(22).profile).profile.inventory.r220==3,"restart other participant")
	check(restarted.state.transactions.has("trade-1"),"durable decision and complete delivery snapshots")
	check(restarted.transact(44,"buy-1","buy",["r1000",2]).profile.inventory.r1000==8,"receipt survives restart")
	var original: Dictionary=restarted.state.duplicate(true)
	restarted.store.path="user://missing-parent/ledger"
	check(not restarted.exchange("save-fail",[44,55],{44:{"r1000":1},55:{}},{}).ok,"failed write rejects trade")
	check(restarted.state==original,"failed write rolls back both participants")
	var corrupt=FileAccess.open(root_path+".0.tmp",FileAccess.WRITE);corrupt.store_string("interrupted");corrupt.close()
	var recovered=Ledger.new();check(recovered.open(root_path)==OK and recovered.state==original,"uncommitted temporary file ignored")
	var kit_data: Dictionary=ledger.account(33).profile.duplicate(true)
	kit_data.kits.copy=kit_data.kits.starter.duplicate(true)
	check(ledger.transact(33,"duplicate-template","metadata",[kit_data]).ok,"templates may reuse master stock")
	check(ledger.account(33).profile.inventory.r1000==8,"copying template does not mint stock")
	check(ledger.exchange("drain",[33,22],{33:{"r1000":8},22:{}},{}).ok,"trade all stock")
	check(ledger.deployment_error(33,board)!="","stale kit blocks deployment after trade")
	# Nested definitions retain firmware/source and transfer by identity without overwriting.
	var leaf := {"name":"Program","revision":1,"pins":[{"name":"p","node":"n"},{"name":"g","node":"g"}],"parts":[{"id":"m","type":"lv_mcu","a":"n","b":"g","nodes":["n","g","d0","d1","a0","pwm"],"firmware":"mode D0 out\nwrite D0 1\nhalt"}],"wires":[],"programs":{"m":{"firmware":"mode D0 out\nwrite D0 1\nhalt","run":true}}}
	var fixture: Dictionary= p.data.duplicate(true);fixture.blueprints={"ic:leaf":leaf,"ic:parent":{"name":"Nested","revision":1,"pins":leaf.pins,"parts":[{"id":"child","type":"ic:leaf","nodes":["n","g"]}],"wires":[]}};fixture.inventory["ic:parent"]=1
	check(Profile.valid(fixture),"firmware fixture")
	var custom_ledger=Ledger.new();check(custom_ledger.open(root_path+"custom")==OK,"custom ledger")
	check(custom_ledger.bind(1,a,sa,fixture).ok and custom_ledger.bind(2,b,sb,p.data).ok,"custom profiles")
	check(custom_ledger.exchange("programmed",[1,2],{1:{"ic:parent":1},2:{}},fixture.blueprints).ok,"nested firmware trade")
	check(custom_ledger.account(2).profile.blueprints["ic:leaf"]==leaf,"firmware and dependency preserved")
	check(custom_ledger.offer_error(2,{"ic:parent":1},{"ic:leaf":{}})!="","modified blueprint rejected")
	var portable := fixture.duplicate(true);portable.notebook="Offline notes";portable.kits.starter.name="Offline template";portable.inventory.r1000=900
	custom_ledger.unbind(1)
	check(custom_ledger.bind(3,a,sa,portable).ok,"portable metadata rejoin")
	check(custom_ledger.account(3).profile.notebook=="Offline notes" and custom_ledger.account(3).profile.kits.starter.name=="Offline template","offline notebook and kit edits preserved")
	check(custom_ledger.account(3).profile.inventory.r1000==900,"offline stock is used when rejoining")
	var broken_path := root_path+"broken"
	for suffix in [".0",".1"]:
		var file := FileAccess.open(broken_path+suffix,FileAccess.WRITE);file.store_var({});file.close()
	var broken=Ledger.new();check(broken.open(broken_path)==ERR_FILE_CORRUPT,"two corrupt generations fail closed")
	var invalid: Dictionary=p.data.duplicate(true);invalid.kits.starter.board.rows={}
	check(not Profile.valid(invalid),"bad shape rejected before typed validator")
	print("PASS authority ledger: %d checks"%checks);quit()


