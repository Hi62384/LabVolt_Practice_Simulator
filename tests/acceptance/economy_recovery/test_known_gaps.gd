extends SceneTree
# Regression for purchase failures and participant-bound trade replay; baseline H failed five criteria.
const Ledger=preload("res://scripts/inventory_authority/ledger.gd")
const Profile=preload("res://scripts/electronics_profile.gd")
var failures := 0
func _initialize() -> void:call_deferred("run")
func require(ok: bool,label: String) -> void:
 if not ok:failures+=1;push_error("GAP "+label)
func run() -> void:
 var isolated := OS.get_environment("LABVOLT_ECONOMY_RUN_ROOT").replace("\\","/").simplify_path().to_lower().trim_suffix("/")
 var actual := OS.get_user_data_dir().replace("\\","/").simplify_path().to_lower()
 if isolated.is_empty() or not isolated.is_absolute_path() or not actual.begins_with(isolated+"/"):
  push_error("Refusing non-isolated saves");quit(2);return
 var p=Profile.new();p.open("economy-gaps-v1")
 var ledger=Ledger.new()
 var location := "user://economy_known_gaps_v1"
 if FileAccess.file_exists(location+".0") or FileAccess.file_exists(location+".1"):
  push_error("Fresh isolated profile required");quit(2);return
 require(ledger.open(location)==OK,"real store opens")
 for peer in range(1,4):require(ledger.bind(peer,str(peer).repeat(48),str(peer+4).repeat(64),p.data).ok,"fixture bind")
 if failures:quit(1);return
 require(ledger.exchange("collision",[1,2],{1:{"r1000":1},2:{}},{}).ok,"initial valid exchange")
 var before: Dictionary=ledger.state.duplicate(true)
 require(not ledger.exchange("collision",[1,2],{1:{"r1000":2},2:{}},{}).ok,"changed trade payload must reject reused id")
 require(not ledger.exchange("collision",[1,3],{1:{"r1000":1},3:{}},{}).ok,"changed authenticated participant must reject reused id")
 require(not ledger.exchange("collision",[99,100],{99:{},100:{}},{}).ok,"unbound replay must not expose participant profiles")
 require(Profile.same(before,ledger.state),"all collision attempts leave state unchanged")
 # A rejected purchase must not be reported as a successful transaction/receipt.
 before=ledger.state.duplicate(true)
 require(not ledger.transact(1,"unaffordable","buy",["lv_mcu",100]).ok,"insufficient funds reports rejection")
 require(Profile.same(before,ledger.state),"insufficient funds adds no successful receipt or revision")
 print(JSON.stringify({"suite":"economy_known_gaps_v1","unmet_criteria":failures,"baseline_expected_to_fail":false}))
 quit(1 if failures else 0)
