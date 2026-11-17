extends SceneTree
const Profile=preload("res://scripts/electronics_profile.gd")
const Products=preload("res://scripts/ui/store_bundles_equipment/module.gd")
const Ledger=preload("res://scripts/inventory_authority/ledger.gd")
func _initialize():
 var p=Profile.new();p.open("bundle_"+Crypto.new().generate_random_bytes(6).hex_encode());p.data.dollars=10000
 var available=Products.products(p)
 for name in ["ETY155 lab kit","DGS266 digital lab kit"]:
  var entries=available.filter(func(x):return x.name==name)
  assert(entries.size()==1)
  var product:Dictionary=entries[0];var old_count:int=p.data.kits.size()
  assert(p.purchase_bundle(product.items,product.price)=="Bundle purchased")
  assert(p.data.kits.size()==old_count+1)
  var found:bool=false
  for id in p.data.kits:
   if p.data.kits[id].name==name:
    found=true;assert(p.data.kits[id].items==product.items);assert(p.kit_error(id)=="")
  assert(found)
 var ledger=Ledger.new();assert(ledger.open("user://bundle_ledger_"+Crypto.new().generate_random_bytes(6).hex_encode())==OK)
 var binding:Dictionary=ledger.bind(11,str(p.data.dorm.owner),"1".repeat(64),p.data);assert(binding.ok)
 var product:Dictionary=available.filter(func(x):return x.name=="DGS266 digital lab kit")[0]
 var result:Dictionary=ledger.transact(11,"digital-kit-test","bundle",[product.items])
 assert(result.ok)
 assert(not ledger.transact(11,"forged","bundle",[{"r330":999}]).ok)
 print("PASS ETY and DGS kit contents, capacity and host-authoritative pricing")
 quit()


