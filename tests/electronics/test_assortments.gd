extends SceneTree
const Profile=preload("res://scripts/electronics_profile.gd")
func _initialize():
	var p=Profile.new();p.open("assortment-regression")
	p.data.dollars=1000
	for name in p.BOXES:
		var box=p.BOXES[name];var total=0
		for chance in box.pool.values():total+=chance
		assert(total==100)
		var before=p.data.inventory.duplicate();var money=p.data.dollars
		assert(p.buy_box(name).begins_with("Received:"))
		var received=0
		for id in p.data.inventory:received+=int(p.data.inventory[id])-int(before.get(id,0))
		assert(received==box.draws);assert(p.data.dollars==money-box.price)
	for id in p.COSMETICS:
		assert(p.buy_cosmetic(id)=="Accessory purchased")
		var money=p.data.dollars
		assert(p.buy_cosmetic(id)=="Already owned");assert(p.data.dollars==money)
	var loaded=Profile.new();loaded.open("assortment-regression")
	assert(loaded.data.inventory.size()==p.data.inventory.size())
	for id in p.data.inventory:assert(int(loaded.data.inventory.get(id,-1))==int(p.data.inventory[id]))
	assert(loaded.data.cosmetics==p.data.cosmetics)
	p.data.pending_trade={"id":"pending"};var before=p.data.duplicate(true)
	assert(p.buy_box("Basic assortment")=="Finish the pending trade first");assert(p.data==before)
	p.data.erase("pending_trade");p.data.dollars=0;before=p.data.duplicate(true)
	assert(p.buy_box("Basic assortment")=="Not enough dollars");assert(p.data==before)
	print("PASS: assortment draw counts, probabilities, prices, accessory uniqueness, persistence, insufficient funds and trade locks")
	quit()
