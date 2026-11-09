extends RefCounted
# Known ledger-v1 -> v2 only. No profile schema changes or history deletion.
const Profile=preload("res://scripts/electronics_profile.gd")
const HOT_PER_ACCOUNT := 32
const HOT_OPS := 128
const HOT_TRADES := 8
const HOT_BYTES := 2097152
const MAX_RECORD := 4194304
const MAX_SEGMENT := 8388608
const MAX_RECORDS := 64
const MAX_FILE := 67108864
const MAX_LEDGER := 62914560
const MAX_SEGMENTS := 1000000
static func digest(bytes: PackedByteArray) -> String:
 var context := HashingContext.new()
 context.start(HashingContext.HASH_SHA256);context.update(bytes)
 return context.finish().hex_encode()
static func hex_id(value: Variant,size: int) -> bool:
 if not value is String or value.length()!=size:return false
 for c in value:
  if not c in "0123456789abcdefABCDEF":return false
 return true
static func identifier(value: Variant) -> bool:
 return value is String and not value.is_empty() and value.length()<=96
static func root(value: Variant) -> bool:
 if not value is Dictionary or value.size()!=2 or not value.get("head") is String or not value.get("segments") is int:return false
 if value.segments<0 or value.segments>MAX_SEGMENTS:return false
 return value.head=="" if value.segments==0 else hex_id(value.head,64)
static func trade(value: Variant) -> bool:
 if not value is Dictionary or value.get("ok")!=true or not value.get("deliveries") is Dictionary or value.deliveries.size()!=2:return false
 for owner in value.deliveries:
  var delivery=value.deliveries[owner]
  if not hex_id(owner,48) or not delivery is Dictionary or not delivery.get("revision") is int or delivery.revision<0 or not Profile.valid(delivery.get("profile")):return false
 if value.has("request"):
  var request=value.request
  if not request is Dictionary or not request.get("offers") is Dictionary or not request.get("choices") is Dictionary or not request.get("definitions") is Dictionary:return false
 return true
static func record(value: Variant) -> bool:
 if not value is Dictionary or not identifier(value.get("id")):return false
 if value.get("kind")=="op":
  if value.size()!=4 or not hex_id(value.get("owner"),48) or not hex_id(value.get("value"),64):return false
 elif value.get("kind")=="trade":
  if value.size()!=3 or not trade(value.get("value")):return false
 else:return false
 return var_to_bytes(value).size()<=MAX_RECORD
static func segment(value: Variant) -> bool:
 if not value is Dictionary or value.size()!=3 or value.get("schema")!=1:return false
 if value.get("previous")!="" and not hex_id(value.get("previous"),64):return false
 if not value.get("records") is Array or value.records.is_empty() or value.records.size()>MAX_RECORDS:return false
 for item in value.records:
  if not record(item):return false
 return true
static func state(value: Variant) -> bool:
 if not value is Dictionary or value.get("schema") not in [1,2] or not value.get("accounts") is Dictionary or not value.get("transactions") is Dictionary:return false
 if value.schema==2 and not root(value.get("receipt_archive")):return false
 if value.schema==1 and value.has("receipt_archive"):return false
 for owner in value.accounts:
  var account=value.accounts[owner]
  if not hex_id(owner,48) or not account is Dictionary or not account.get("receipts") is Dictionary or not Profile.valid(account.get("profile")):return false
  if not account.get("revision") is int or account.revision<0 or not hex_id(account.get("credential"),64) or not account.get("deployment") is Dictionary:return false
  for id in account.receipts:
   if not identifier(id) or not hex_id(account.receipts[id],64):return false
 for id in value.transactions:
  if not identifier(id) or not trade(value.transactions[id]):return false
 return true
static func op_record(owner: String,id: String,value: String) -> Dictionary:
 return {"kind":"op","owner":owner,"id":id,"value":value}
static func trade_record(id: String,value: Dictionary) -> Dictionary:
 return {"kind":"trade","id":id,"value":value}
static func hot_size(value: Dictionary) -> int:
 var size := 0
 for owner in value.accounts:
  for id in value.accounts[owner].receipts:size+=var_to_bytes(op_record(owner,id,value.accounts[owner].receipts[id])).size()
 for id in value.transactions:size+=var_to_bytes(trade_record(id,value.transactions[id])).size()
 return size
static func bounded(value: Dictionary) -> bool:
 var total := 0
 for account in value.accounts.values():
  if account.receipts.size()>HOT_PER_ACCOUNT:return false
  total+=account.receipts.size()
 return total<=HOT_OPS and value.transactions.size()<=HOT_TRADES and hot_size(value)<=HOT_BYTES
