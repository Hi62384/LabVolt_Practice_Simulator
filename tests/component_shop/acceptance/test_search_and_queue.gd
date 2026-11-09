extends SceneTree
const Catalog=preload("res://scripts/electronics_catalog.gd")
const Values=preload("res://scripts/electronics/component_values/values.gd")
const Ratings=preload("res://scripts/electronics/component_values/shop_services.gd")
const Query=preload("res://scripts/electronics/inventory_value_search/query.gd")
const Selection=preload("res://scripts/electronics/inventory_value_search/selection.gd")
const State=preload("res://scripts/electronics/component_shop_ui/shop_state.gd")

var checks:=0
var failures:=0
func check(condition: bool,message: String) -> void:
	checks+=1
	if not condition:
		failures+=1
		push_error("ACCEPTANCE component_shop FAIL: "+message)

func _init() -> void:
	var fixed: Dictionary=Catalog.all()
	var low: Dictionary=Ratings.quote("r1000",{"value":"800 Ω"},2,fixed,{})
	var high: Dictionary=Ratings.quote("r1000",{"value":"1.2 kΩ"},1,fixed,{})
	check(low.ok and high.ok and low.id!=high.id,"Two distinct rated variants quoted")
	check(low.intent.op=="buy_configured" and low.intent.args.size()==3,"Shop sends validated host intent")
	check(Ratings.quote("r220",{"value":"0.8 kΩ"},2,fixed,{}).id==low.id,"SI spellings and base variants agree")
	check(Values.resolve(low.id,fixed).entry.value==800.0,"Owned variant resolves actual resistance")
	check(Ratings.quote("r1000",{"value":"1000 Ω"},1,fixed,{}).id=="r1000","Existing catalog variant retains ID")
	check(not Ratings.quote("r1000",{"price":0},1,fixed,{}).ok,"Client price setting rejected")
	check(not Ratings.quote("r1000",{"value":"NaN"},1,fixed,{}).ok,"Nonfinite rating rejected")
	check(not Ratings.quote("r1000",{"value":"-1 Ω"},1,fixed,{}).ok,"Negative resistance rejected")
	check(not Ratings.quote("r1000",{"value":"1e999 Ω"},1,fixed,{}).ok,"Overflow rating rejected")
	check(not Ratings.quote("r1000",{"value":"0 Ω"},1,fixed,{}).ok,"Unsupported zero ohm rejected")
	check(State.quantity_error("100000")=="" and State.quantity_error("100001")!="","Shop quantity uses stack bound")
	for raw in ["0","-1","1.1","1e2","NaN"," 2"]:check(State.quantity_error(raw)!="","Malformed shop quantity rejected")
	check(not Ratings.quote("r1000",{},2,fixed,{"r1000":99999}).ok,"Owned stack limit checked at quote")
	var catalog: Dictionary=Values.augment(fixed,[low.id,high.id])
	var profile: Dictionary={"inventory":{low.id:2,high.id:1,"r1000":1,"r220":0},"component_instances":{}}
	var nearest: Dictionary=Query.search_owned(profile,catalog,"R","1 kΩ")
	check(nearest.error=="" and nearest.rows.size()==3,"Only three available resistor stocks returned")
	check(nearest.rows[0].type=="r1000" and nearest.rows[0].distance==0,"Exact owned value first")
	check(nearest.rows[1].type==low.id and nearest.rows[2].type==high.id,"Equal-distance variants keep catalog order")
	var other: Dictionary=Query.search_owned(profile,catalog,"R","850 Ω")
	check(other.rows[0].type==low.id,"Search ranking changes with target")
	check(Query.search_owned(profile,catalog,"R","900 V").error!="","Wrong search unit rejected")
	check(Query.search_owned(profile,catalog,"R","NaN").error!="","Bad search text rejected")
	var reserved: Dictionary={"counts":{low.id:2},"instance_ids":[]}
	var held: Dictionary=Query.search_owned(profile,catalog,"R","900 Ω",reserved)
	check(held.rows.size()==2 and not held.rows.any(func(row):return row.type==low.id),"Reserved stock unavailable")
	var kit: Dictionary={"r1000":1,high.id:1,low.id:0}
	var limited: Dictionary=Query.search_owned(profile,catalog,"R","900 Ω",{},kit)
	check(limited.rows.size()==2 and not limited.rows.any(func(row):return row.type==low.id),"Kit availability respected")
	var selection=Selection.new();selection.refresh(nearest.rows)
	check(selection.choose(low.id) and selection.current().type==low.id,"Select real owned variant")
	selection.refresh(held.rows)
	check(selection.current().is_empty(),"Selection clears when stock becomes unavailable")
	# Transport stand-in: a pending request remains unique until its matching
	# receipt is delivered. This exercises production ShopState correlation.
	var state=State.new()
	var request: String=state.begin_request()
	check(not request.is_empty() and state.begin_request()=="","Rapid duplicate click cannot create a second request")
	check(not state.finish_request("wrong-receipt") and state.pending_id==request,"Wrong receipt cannot clear pending state")
	check(state.finish_request(request) and state.pending_id.is_empty(),"Matching receipt clears pending state")
	check(not state.finish_request(request),"Duplicate receipt cannot complete twice")
	if failures>0:
		print("ACCEPTANCE component_shop search/queue FAIL ",failures,"/",checks)
		quit(1)
	else:
		print("ACCEPTANCE component_shop search/queue PASS ",checks)
		quit()
