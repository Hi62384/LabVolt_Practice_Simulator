extends RefCounted
# Archive data precedes atomic Store.commit. Receipts are moved, never discarded.
const Format=preload("res://scripts/inventory_authority/receipt_archive/format.gd")
const BlobStore=preload("res://scripts/inventory_authority/receipt_archive/blob_store.gd")
const Profile=preload("res://scripts/electronics_profile.gd")
var blobs=BlobStore.new()
var checkpoint := Callable() # Optional host-owned observation barrier; may abort, never force success.
var configured := false
var healthy := true
var last_error := ""
func configure(path: String) -> void:
 healthy=true;last_error="";configured=false
 var absolute := ProjectSettings.globalize_path(path).replace("\\","/").simplify_path()
 var user_root := OS.get_user_data_dir().replace("\\","/").simplify_path().trim_suffix("/")
 if OS.get_name()=="Windows":absolute=absolute.to_lower();user_root=user_root.to_lower()
 if path.is_empty() or not absolute.is_absolute_path() or not absolute.begins_with(user_root+"/"):
  failure("Receipt archive ledger path must remain inside engine user data");return
 blobs.root=path+".receipts";blobs.checkpoint=checkpoint;configured=true
func failure(message: String) -> Dictionary:
 healthy=false;last_error=message
 return {"ok":false,"error":message}
func _scan(state: Dictionary,kind: String="",owner: String="",id: String="",visit: Callable=Callable()) -> Dictionary:
 if not healthy:return failure(last_error)
 if not configured:return failure("Receipt archive has no scoped ledger path")
 if state.get("schema")!=2 or not Format.root(state.get("receipt_archive")):return failure("Unsupported receipt ledger schema/root")
 var hash: String=state.receipt_archive.head
 var found := false;var value: Variant=null
 for index in int(state.receipt_archive.segments):
  if hash.is_empty():return failure("Receipt archive chain is incomplete")
  var result: Dictionary=blobs.read_segment(hash)
  if not result.ok:return failure(result.error)
  for item in result.segment.records:
   if item.kind==kind and item.id==id and (kind!="op" or item.owner==owner):
    if found and not Profile.same(value,item.value):return failure("Conflicting immutable historical receipts")
    found=true;value=item.value.duplicate(true) if item.value is Dictionary else item.value
   if visit.is_valid():visit.call(item)
  hash=result.segment.previous
 if not hash.is_empty():return failure("Receipt archive chain length/cycle mismatch")
 return {"ok":true,"found":found,"value":value}
func verify(state: Dictionary) -> Dictionary:
 if not healthy:return failure(last_error)
 if not Format.state(state) or state.schema!=2:return failure("Unsupported or invalid receipt ledger")
 return _scan(state)
func lookup_op(state: Dictionary,owner: String,id: String) -> Dictionary:
 var cold := _scan(state,"op",owner,id)
 if not cold.ok:return cold
 var hot: Dictionary=state.get("accounts",{}).get(owner,{}).get("receipts",{})
 if hot.has(id):
  if cold.found and not Profile.same(cold.value,hot[id]):return failure("Hot/archive operation receipt conflict")
  return {"ok":true,"found":true,"value":hot[id]}
 return cold
func lookup_trade(state: Dictionary,id: String) -> Dictionary:
 var cold := _scan(state,"trade","",id)
 if not cold.ok:return cold
 var hot: Dictionary=state.get("transactions",{})
 if hot.has(id):
  if cold.found and not Profile.same(cold.value,hot[id]):return failure("Hot/archive trade receipt conflict")
  return {"ok":true,"found":true,"value":hot[id].duplicate(true)}
 return cold
func open_store(store) -> Dictionary:
 configure(store.path)
 if not healthy:return failure(last_error)
 if store.value.is_empty():
  return {"ok":true,"state":{"schema":2,"accounts":{},"transactions":{},"receipt_archive":{"head":"","segments":0}}}
 if not Format.state(store.value):return failure("Unsupported or invalid known-v1/v2 ledger")
 if store.value.schema==2:
  var checked := verify(store.value)
  if not checked.ok:return checked
  if not Format.bounded(store.value):return failure("Active receipt state exceeds configured bounds")
  return {"ok":true,"state":store.value.duplicate(true)}
 # Preserve exact original on-disk generation bytes before changing any ledger reference.
 var backups := []
 for slot in [".0",".1"]:
  if not FileAccess.file_exists(store.path+slot):continue
  var backed: Dictionary=blobs.backup_generation(store.path,slot)
  if not backed.ok:return failure(backed.error)
  backups.append({"slot":slot,"sha256":backed.sha256})
 if backups.is_empty():return failure("Known v1 ledger has no original generation to preserve")
 var old: Dictionary=store.value.duplicate(true);old.receipt_v1_backup=backups
 var prepared := _prepare(old,true)
 if not prepared.ok:return prepared
 if checkpoint.is_valid() and checkpoint.call("archive_verified_before_ledger_commit",store.path)==false:return failure("Migration publication aborted by observer")
 if store.commit(prepared.state)!=OK:return failure("Migration ledger publication failed; original v1 retained")
 if checkpoint.is_valid() and checkpoint.call("ledger_committed",store.path)==false:return failure("Migration observation aborted after durable commit")
 return {"ok":true,"state":prepared.state}
func _flush(work: Dictionary,batch: Array) -> bool:
 if batch.is_empty():return true
 var segment: Dictionary={"schema":1,"previous":work.receipt_archive.head,"records":batch}
 var segments: int=int(work.receipt_archive.segments)+1
 if not str(work.receipt_archive.head).is_empty():
  var head: Dictionary=blobs.read_segment(str(work.receipt_archive.head))
  if not head.ok:failure(head.error);return false
  var combined: Array=head.segment.records.duplicate()
  combined.append_array(batch)
  var merged: Dictionary={"schema":1,"previous":head.segment.previous,"records":combined}
  if combined.size()<=Format.MAX_RECORDS and var_to_bytes(merged).size()<=Format.MAX_SEGMENT:
   # Publish a NEW immutable head containing all old+new receipts. Earlier
   # ledger generations still reference their original untouched head blob.
   segment=merged
   segments=int(work.receipt_archive.segments)
 if segments>Format.MAX_SEGMENTS:failure("Archive segment-count hard limit");return false
 var result: Dictionary=blobs.put_segment(segment)
 if not result.ok:failure(result.error);return false
 work.receipt_archive={"head":result.hash,"segments":segments}
 batch.clear()
 return true
func _move(work: Dictionary,batch: Array,item: Dictionary,check_existing: bool=true) -> bool:
 if not Format.record(item):failure("Receipt exceeds archive record contract");return false
 # Known-v1 dictionaries have unique (kind,owner,id) keys and no prior archive.
 # Avoid quadratic re-reading of segments created by this same migration.
 if check_existing:
  var previous := _scan(work,item.kind,str(item.get("owner","")),item.id)
  if not previous.ok:return false
  if previous.found:
   if not Profile.same(previous.value,item.value):failure("Cannot replace an archived receipt");return false
   return true
 var candidate := batch.duplicate();candidate.append(item)
 if candidate.size()>Format.MAX_RECORDS or var_to_bytes({"schema":1,"previous":work.receipt_archive.head,"records":candidate}).size()>Format.MAX_SEGMENT:
  if not _flush(work,batch):return false
 batch.append(item)
 return true
func prepare(value: Dictionary) -> Dictionary:
 return _prepare(value,false)
func _prepare(value: Dictionary,migration: bool) -> Dictionary:
 if not healthy:return failure(last_error)
 if not Format.state(value):return failure("Unsupported or invalid ledger state for receipt preparation")
 if value.schema==1 and not migration:return failure("Known-v1 migration requires backup-gated open_store")
 var work := value.duplicate(true)
 if work.schema==1:
  work.schema=2;work.receipt_archive={"head":"","segments":0}
 else:
  var checked := verify(work)
  if not checked.ok:return checked
 var batch := [];var count := 0
 for owner in work.accounts:
  var receipts: Dictionary=work.accounts[owner].receipts
  while receipts.size()>Format.HOT_PER_ACCOUNT:
   var id: String=receipts.keys()[0]
   if not _move(work,batch,Format.op_record(owner,id,receipts[id]),not migration):return failure(last_error)
   receipts.erase(id)
  count+=receipts.size()
 for owner in work.accounts:
  var receipts: Dictionary=work.accounts[owner].receipts
  while count>Format.HOT_OPS and not receipts.is_empty():
   var id: String=receipts.keys()[0]
   if not _move(work,batch,Format.op_record(owner,id,receipts[id]),not migration):return failure(last_error)
   receipts.erase(id);count-=1
 # Legacy trades without request proof remain historical and can never be unseen.
 for id in work.transactions.keys():
  if work.transactions[id].has("request"):continue
  if not _move(work,batch,Format.trade_record(id,work.transactions[id]),not migration):return failure(last_error)
  work.transactions.erase(id)
 while work.transactions.size()>Format.HOT_TRADES or (Format.hot_size(work)>Format.HOT_BYTES and not work.transactions.is_empty()):
  var id: String=work.transactions.keys()[0]
  if not _move(work,batch,Format.trade_record(id,work.transactions[id]),not migration):return failure(last_error)
  work.transactions.erase(id)
 if not _flush(work,batch):return failure(last_error)
 if not Format.bounded(work) or var_to_bytes(work).size()>Format.MAX_LEDGER:return failure("Active ledger hard bound exceeded; no state published")
 var verified := verify(work)
 return {"ok":true,"state":work} if verified.ok else verified
func delivery_hints(state: Dictionary,journal: Dictionary) -> bool:
 # Verify whole history before modifying even non-economic delivery hints.
 if not verify(state).ok:return false
 # Scratch membership is reset every pass, never trusted from a saved journal.
 for id in journal:
  if journal[id] is Dictionary:journal[id]._archive_seen=false
 var remember := func(item: Dictionary):
  if item.kind!="trade":return
  var previous=journal.get(item.id,{})
  var trusted: bool = previous is Dictionary and previous.get("authoritative") is bool and previous.authoritative and previous.get("deliveries") is Dictionary
  var deliveries := {}
  for owner in item.value.deliveries:
   var acknowledged=previous.deliveries.get(owner,false) if trusted else false
   deliveries[owner]=acknowledged if acknowledged is bool else false
  # Authoritative decision defines exactly the two owners. Never fabricate an ack.
  journal[item.id]={"deliveries":deliveries,"authoritative":true,"_archive_seen":true}
 var scanned := _scan(state,"","","",remember)
 if not scanned.ok:return false
 for id in state.transactions:remember.call(Format.trade_record(id,state.transactions[id]))
 return true
