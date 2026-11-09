extends SceneTree
# Real production paths only. No transaction/store doubles or fabricated success.
const Ledger=preload("res://scripts/inventory_authority/ledger.gd")
const Profile=preload("res://scripts/electronics_profile.gd")
const Board=preload("res://scripts/breadboard_model.gd")
const Custom=preload("res://scripts/custom_circuit.gd")
const Resistor=preload("res://scripts/physical_resistors.gd")
var checks := 0
var failed := false
var fixture: Dictionary
var path := "user://economy_recovery_v1"
func _initialize() -> void:call_deferred("run")
func check(ok: bool,label: String) -> void:
 checks+=1
 if not ok:
  failed=true
  push_error("ECONOMY_FAIL "+label)
func seed_profile() -> Dictionary:
 var p=Profile.new()
 p.open("economy-recovery-v1-seed")
 p.data.dollars=int(fixture.initial_dollars)
 return p.data.duplicate(true)
func bind_accounts(ledger,count: int=2) -> void:
 for peer in range(1,count+1):
  check(ledger.bind(peer,str(peer).repeat(48),str(peer+4).repeat(64),seed_profile()).ok,"bind fixture "+str(peer))
func totals(ledger) -> Dictionary:
 var result := {}
 for a in ledger.state.accounts.values():
  for type in a.profile.inventory:result[type]=int(result.get(type,0))+int(a.profile.inventory[type])
 return result
func owners(ledger,identity: String) -> int:
 var count := 0
 for a in ledger.state.accounts.values():
  if a.profile.get("component_instances",{}).has(identity):count+=1
 return count
func unchanged(ledger,before: Dictionary,label: String) -> void:
 check(Profile.same(ledger.state,before),label+" complete state")
func run() -> void:
 var run_root := OS.get_environment("LABVOLT_ECONOMY_RUN_ROOT").replace("\\","/").simplify_path().to_lower().trim_suffix("/")
 var user_dir := OS.get_user_data_dir().replace("\\","/").simplify_path().to_lower()
 if run_root.is_empty() or not run_root.is_absolute_path() or not user_dir.begins_with(run_root+"/"):
  push_error("Refusing non-isolated profile: explicit LABVOLT_ECONOMY_RUN_ROOT must contain user data directory")
  quit(2)
  return
 fixture=JSON.parse_string(FileAccess.get_file_as_string("res://tests/acceptance/economy_recovery/fixtures.json"))
 var args := OS.get_cmdline_user_args()
 var scenario := args[0] if args.size()==1 else ""
 if scenario not in ["correctness","history","crash_prepare","crash_recover"]:
  push_error("One explicit scenario required")
  quit(2)
  return
 # Each ordinary scenario needs a fresh isolated directory. Crash phases share one.
 path+="_crash" if scenario.begins_with("crash_") else "_"+scenario
 if scenario=="crash_recover":
  recover_crash()
 elif scenario=="crash_prepare":
  await prepare_crash()
  return
 elif scenario=="history":history()
 else:
  shop_and_ordering()
  custom_and_physical()
  storage_and_legacy()
  snapshot_ordering()
 print(JSON.stringify({"suite":"economy_recovery_v1","scenario":scenario,"checks":checks,"ok":not failed,"scope":"production local persistence; no multiplayer or soak claim"}))
 quit(1 if failed else 0)
func fresh(suffix: String,count: int=2):
 var ledger=Ledger.new()
 check(not FileAccess.file_exists(path+suffix+".0") and not FileAccess.file_exists(path+suffix+".1"),"fresh profile required")
 check(ledger.open(path+suffix)==OK,"open ledger")
 bind_accounts(ledger,count)
 return ledger
func shop_and_ordering() -> void:
 var ledger=fresh("shop",4)
 var before: Dictionary=ledger.state.duplicate(true)
 var result: Dictionary=ledger.transact(1,"buy-b","buy",[fixture.buy.type,int(fixture.buy.quantity)])
 check(result.ok,"production buy committed")
 check(int(ledger.account(1).profile.dollars)==998,"independent shop money delta")
 check(int(ledger.account(1).profile.inventory.r1000)==10,"independent shop stock delta")
 var after: Dictionary=ledger.state.duplicate(true)
 check(ledger.transact(1,"buy-b","buy",["r1000",2]).ok,"same request duplicate")
 unchanged(ledger,after,"duplicate receipt")
 check(not ledger.transact(1,"buy-b","buy",["r1000",3]).ok,"different payload same id rejected")
 unchanged(ledger,after,"conflicting receipt")
 check(ledger.transact(1,"buy-a","buy",["r1000",1]).ok,"earlier named request delivered late")
 check(ledger.transact(1,"buy-c","buy",["r1000",3]).ok,"later request")
 check(int(ledger.account(1).profile.inventory.r1000)==14 and int(ledger.account(1).profile.dollars)==994,"reordered independent requests each apply once")
 check(int(ledger.account(1).revision)==3,"one revision per new successful request")
 var metadata: Dictionary=ledger.account(1).profile.duplicate(true)
 metadata.dollars=999999;metadata.inventory.r1000=99999
 check(ledger.transact(1,"forge","metadata",[metadata]).ok,"metadata routed through host whitelist")
 check(int(ledger.account(1).profile.dollars)==994 and int(ledger.account(1).profile.inventory.r1000)==14,"host quantities authoritative")
 var board := Board.empty();board.parts=[{"id":"r","type":"r1000","a":"A1","b":"F1"}]
 check(ledger.deploy(1,0,board)=="","reserve owned component")
 check(ledger.free_stock(1,"r1000")==13,"reservation subtracts free stock only")
 before=ledger.state.duplicate(true)
 check(not ledger.exchange("oversell",[1,2],{1:{"r1000":14},2:{}},{}).ok,"reserved stock blocked")
 unchanged(ledger,before,"oversell rollback")
 check(ledger.recall(1),"recall")
 var conserved := totals(ledger)
 check(ledger.exchange("trade",[1,2],{1:{"r1000":2},2:{"r220":1}},{}).ok,"production exchange")
 check(Profile.same(totals(ledger),conserved),"component conservation across all four accounts")
 after=ledger.state.duplicate(true)
 check(ledger.exchange("trade",[1,2],{1:{"r1000":2},2:{"r220":1}},{}).ok,"exact exchange replay")
 unchanged(ledger,after,"exchange replay")
 var location: String=ledger.store.path
 ledger.store.path=path+"/nonexistent-parent/ledger"
 before=ledger.state.duplicate(true)
 check(not ledger.transact(1,"write-fail","buy",["r1000",1]).ok,"real failed file open rejects purchase")
 unchanged(ledger,before,"purchase failure")
 check(not ledger.exchange("write-fail-trade",[1,2],{1:{"r1000":1},2:{}},{}).ok,"real failed file open rejects exchange")
 unchanged(ledger,before,"two-account failure")
 ledger.store.path=location
 check(ledger.transact(1,"write-fail","buy",["r1000",1]).ok,"failed receipt can retry once storage restored")
 check(int(ledger.account(1).profile.inventory.r1000)==13,"retry changes stock once")
 var restarted=Ledger.new()
 check(restarted.open(location)==OK,"reopen production generations")
 check(Profile.same(restarted.state,ledger.state),"entire committed state survives reopen")
 bind_accounts(restarted,4)
 before=restarted.state.duplicate(true)
 check(restarted.transact(1,"write-fail","buy",["r1000",1]).ok,"receipt after reopen")
 unchanged(restarted,before,"durable replay")
func custom_and_physical() -> void:
 var ledger=fresh("custom")
 var source := Board.empty()
 source.parts=[{"id":"m","type":"lv_mcu","a":"A1","b":"F1","pins":["A1","F1","A2","F2","A3","F3"],"firmware":fixture.program,"code_files":{"main.lvs":fixture.program}}]
 var leaf := Board.blueprint(source,"Program leaf")
 leaf.programs={"m":{"firmware":fixture.program,"run":true}}
 var outer := Board.empty();outer.ports=["A1","F1"]
 outer.parts=[{"id":"child","type":"ic:recovery-leaf","a":"A1","b":"F1","pins":["A1","F1"]}]
 # Explicit stable pins keep the nested interface two-terminal.
 leaf.pins=[{"name":"VIN","node":"L1"},{"name":"GND","node":"R1"}]
 var parent := Board.blueprint(outer,"Nested PCB")
 parent.package="PCB";parent.footprint={"width":8,"height":8,"color":"24775b"}
 parent.layout={"rows":outer.rows,"parts":outer.parts.duplicate(true),"wires":[]}
 var library := {"ic:recovery-leaf":leaf,"ic:recovery-pcb":parent}
 check(Custom.validate("ic:recovery-pcb",library)=="","real nested PCB fixture validates")
 var incoming: Dictionary=ledger.account(1).profile.duplicate(true);incoming.blueprints=library
 check(ledger.transact(1,"library","metadata",[incoming]).ok,"host validates library metadata")
 check(ledger.transact(1,"custom-buy","obtain",["ic:recovery-pcb",false]).ok,"custom PCB bought via production operation")
 check(int(ledger.account(1).profile.inventory.get("ic:recovery-pcb",0))==1,"custom stock created once")
 if failed:return
 var conserved := totals(ledger)
 check(ledger.exchange("pcb-trade",[1,2],{1:{"ic:recovery-pcb":1},2:{}},library).ok,"nested PCB trade")
 check(Profile.same(totals(ledger),conserved),"nested PCB stock conservation")
 if failed:return
 check(Profile.same(ledger.account(2).profile.blueprints["ic:recovery-leaf"],leaf),"exact nested program bytes preserved")
 check(Profile.same(ledger.account(2).profile.blueprints["ic:recovery-pcb"],parent),"PCB layout and footprint preserved")
 check(ledger.transact(1,"physical-buy","buy",[fixture.physical.type,1]).ok,"rated resistor shop purchase")
 var board := Board.empty();board.parts=[{"id":"unit","type":fixture.physical.type,"a":"A1","b":"F1"}]
 var material: Dictionary=ledger.materialize(1,board)
 check(not material.is_empty() and material.instance_ids.size()==1,"host manufactures owned resistor instance")
 if material.is_empty() or material.instance_ids.is_empty():return
 var identity: String=material.instance_ids.unit
 var item: Dictionary=ledger.account(1).profile.component_instances[identity].duplicate(true)
 var parameters: Dictionary=item.component_runtime["board/unit"]
 check(Resistor.valid(parameters),"production manufactured shape")
 check(float(parameters.nominal)==1000 and float(parameters.tolerance)==0.01 and float(parameters.watts)==0.25,"independent nominal tolerance rating")
 check(float(parameters.actual)>=990 and float(parameters.actual)<=1010,"actual manufacturing value in independent interval")
 check(Profile.same(ledger.materialize(1,board).component_runtime,material.component_runtime),"manufactured value stable on rematerialize")
 var choices := {1:{identity:ledger.instance_hash(item)},2:{}}
 check(ledger.exchange("rated-trade",[1,2],{1:{fixture.physical.type:1},2:{}},{},choices).ok,"reviewed manufactured instance trade")
 check(owners(ledger,identity)==1 and ledger.account(2).profile.component_instances.has(identity),"exactly one resistor owner")
 if failed:return
 check(Profile.same(ledger.account(2).profile.component_instances[identity],item),"manufactured values preserved exactly")
 check(ledger.transact(1,"eeprom-buy","buy",[fixture.eeprom.type,1]).ok,"real EEPROM purchase")
 var memory_board := Board.empty()
 memory_board.parts=[{"id":"nv","type":"eeprom25","a":"A4","b":"F4","pins":["A4","F4","A5","F5","A6","F6","A7","F7"]}]
 # This stage checks persistence of supplied nonvolatile bytes, not electrical writes.
 var states := {"board/nv":{"memory":fixture.eeprom.memory.duplicate(true),"status":int(fixture.eeprom.status),"command":3,"powered":true}}
 check(ledger.capture_components(1,memory_board,states)=="","production capture actual EEPROM type")
 var nv: String=memory_board.instance_ids.get("nv","")
 check(not nv.is_empty(),"EEPROM physical identity")
 if nv.is_empty():return
 var original: Dictionary=ledger.account(1).profile.component_instances[nv].duplicate(true)
 check(not original.component_runtime["board/nv"].has("command") and not original.component_runtime["board/nv"].has("powered"),"volatile state excluded")
 choices={1:{nv:ledger.instance_hash(original)},2:{}}
 check(ledger.exchange("nv-trade",[1,2],{1:{"eeprom25":1},2:{}},{},choices).ok,"reviewed EEPROM transfer")
 check(owners(ledger,nv)==1 and ledger.account(2).profile.component_instances.has(nv),"exactly one EEPROM owner")
 if failed:return
 check(Profile.same(ledger.account(2).profile.component_instances[nv],original),"EEPROM bytes and protection preserved")
 var reopened=Ledger.new();check(reopened.open(ledger.store.path)==OK,"reopen custom persistence")
 check(Profile.same(reopened.state,ledger.state),"program EEPROM resistor and receipt exact recovery")
func storage_and_legacy() -> void:
 var ledger=fresh("storage")
 var location: String=ledger.store.path
 var before: Dictionary=ledger.state.duplicate(true)
 var file := FileAccess.open(location+".0.tmp",FileAccess.WRITE)
 check(file!=null,"create interrupted temp fixture")
 if file!=null:file.store_string("incomplete write");file.close()
 var reopened=Ledger.new();check(reopened.open(location)==OK,"ignore temporary uncommitted file")
 unchanged(reopened,before,"temporary file")
 check(ledger.transact(1,"next-generation","buy",["r1000",1]).ok,"new durable generation")
 var slot := location+"."+str(ledger.store.generation%2)
 file=FileAccess.open(slot,FileAccess.WRITE)
 if file!=null:file.store_string("corrupt newest generation");file.close()
 reopened=Ledger.new();check(reopened.open(location)==OK,"recover previous checked generation")
 unchanged(reopened,before,"corrupt latest falls back one committed generation")
 # Legacy profile: optional registry/blueprints/receipt fields absent.
 var legacy := seed_profile()
 for key in ["component_instances","blueprints","applied_trades","pending_trade","authority_credentials"]:legacy.erase(key)
 check(Profile.valid(legacy),"legacy schema one remains accepted")
 var p=Profile.new();p.path="user://legacy-recovery.json";p.data=legacy
 check(p.save()==OK,"production legacy serialization")
 # Profile.open derives its own path; save again at the actual isolated profile path.
 p.open("legacy-recovery");p.data=legacy;check(p.save()==OK,"legacy identity save")
 var q=Profile.new();q.open("legacy-recovery")
 check(Profile.same(q.data,legacy),"legacy roundtrip preserves economic content")
 var payload := {"id":"prepared","give":{"r1000":1},"take":{"r220":1},"definitions":{}}
 check(q.prepare_trade(payload)=="","durable legacy prepare")
 var resumed=Profile.new();resumed.open("legacy-recovery")
 check(resumed.data.pending_trade.id=="prepared","prepared profile reopened")
 check(resumed.commit_trade("prepared")=="","legacy commit production path")
 var after: Dictionary=resumed.data.duplicate(true)
 check(resumed.commit_trade("prepared")=="" and Profile.same(resumed.data,after),"legacy receipt idempotence")
func history() -> void:
 var ledger=fresh("history")
 for i in int(fixture.history.operations):
  check(ledger.transact(1,"history-%04d"%i,"buy",["r1000",1]).ok,"history operation "+str(i))
 check(int(ledger.account(1).profile.inventory.r1000)==136,"128 independent stock increments")
 check(int(ledger.account(1).profile.dollars)==872,"128 independent dollar debits")
 var retained := 0
 for i in int(fixture.history.operations):
  var receipt: Dictionary=ledger.receipt_history.lookup_op(ledger.state,ledger.bindings[1],"history-%04d"%i)
  if receipt.ok and receipt.found:retained+=1
 check(retained==128,"all128 history receipt IDs retained across hot/archive")
 check(ledger.account(1).receipts.size()<=32,"active receipt map remains bounded")
 var reopened=Ledger.new();check(reopened.open(ledger.store.path)==OK,"history reopen")
 bind_accounts(reopened)
 var before: Dictionary=reopened.state.duplicate(true)
 for i in range(127,-1,-1):check(reopened.transact(1,"history-%04d"%i,"buy",["r1000",1]).ok,"reverse replay "+str(i))
 unchanged(reopened,before,"long history duplicate/reordered replay")
func prepare_crash() -> void:
 var ledger=fresh("phase")
 check(ledger.transact(1,"crash-buy","buy",["r1000",2]).ok,"precrash buy")
 check(ledger.exchange("crash-trade",[1,2],{1:{"r1000":2},2:{"r220":1}},{}).ok,"precrash exchange")
 var file := FileAccess.open(path+"phase.0.tmp",FileAccess.WRITE)
 if file!=null:file.store_string("unfinished candidate");file.flush();file.close()
 if failed:quit(1);return
 print("ECONOMY_CRASH_READY committed buy and exchange; root must terminate only this owned Job")
 # A watchdog is failure, never a simulated crash success.
 await create_timer(30).timeout
 push_error("CRASH_NOT_PERFORMED: owned Job was not terminated within 30 seconds")
 quit(3)
func recover_crash() -> void:
 var ledger=Ledger.new();check(ledger.open(path+"phase")==OK,"postcrash production open")
 bind_accounts(ledger)
 check(int(ledger.account(1).profile.inventory.r1000)==8 and int(ledger.account(1).profile.inventory.r220)==5,"postcrash donor quantities")
 check(int(ledger.account(2).profile.inventory.r1000)==10 and int(ledger.account(2).profile.inventory.r220)==3,"postcrash recipient quantities")
 check(int(ledger.account(1).profile.dollars)==998,"postcrash dollars")
 var before: Dictionary=ledger.state.duplicate(true)
 check(ledger.transact(1,"crash-buy","buy",["r1000",2]).ok,"postcrash buy receipt")
 check(ledger.exchange("crash-trade",[1,2],{1:{"r1000":2},2:{"r220":1}},{}).ok,"postcrash exchange receipt")
 unchanged(ledger,before,"postcrash exactly once")
func snapshot_ordering() -> void:
 var p=Profile.new();p.open("snapshot-ordering-v1")
 var authoritative := seed_profile()
 authoritative.dollars=998;authoritative.inventory.r1000=10
 check(p.accept_authority({"ok":true,"revision":2,"profile":authoritative})==OK,"local snapshot production save")
 var before: Dictionary=p.data.duplicate(true)
 var old := seed_profile()
 check(p.accept_authority({"ok":true,"revision":1,"profile":old})!=OK,"late older snapshot rejected")
 check(Profile.same(p.data,before) and p.authority_revision==2,"older snapshot leaves local state and revision unchanged")
 var location: String=p.path
 p.path="user://missing-snapshot-parent/profile.json"
 authoritative.dollars=997;authoritative.inventory.r1000=11
 check(p.accept_authority({"ok":true,"revision":3,"profile":authoritative})!=OK,"local snapshot save fails through real filesystem")
 check(Profile.same(p.data,before) and p.authority_revision==2,"failed local save restores bytes and revision")
 p.path=location
 check(p.accept_authority({"ok":true,"revision":3,"profile":authoritative})==OK,"local snapshot retry")
 check(int(p.data.dollars)==997 and int(p.data.inventory.r1000)==11,"retried snapshot converges")

