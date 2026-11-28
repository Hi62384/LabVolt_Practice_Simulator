extends RefCounted
## Explicit historical save fixtures for persistence/gameplay tests. This helper
## never runs in the game and must not be used as evidence of AI quality.
const Population=preload("res://scripts/campus/academics/student_population.gd")
const Store=preload("res://scripts/campus/academics/character_dossier_store.gd")
const Dossier=preload("res://scripts/campus/academics/character_dossier.gd")
static var run_id:=Crypto.new().generate_random_bytes(6).hex_encode()
static func bind(population: RefCounted,destination: String)->void:
	var owner:="fixture-"+(run_id+destination).sha256_text()
	Store.set_host_profile(owner)
	population._host_profile=owner
	population.path=destination
static func seed(population: RefCounted,count:=24)->void:
	for index in count:
		var id:="campus_student_%02d"%index
		if not population.people.has(id): population.people[id]=Population._create(index)
	population.next_index=maxi(population.next_index,count)
	population.requested_size=maxi(population.requested_size,count)
	population.dirty=true
	sync(population)
static func sync(population: RefCounted)->void:
	for id in population.people:
		if Store.get_dossier(id).get("generation",{}).get("status")=="complete":continue
		var d:=Dossier.migrate(population.people[id])
		d.revision=int(Store.get_dossier(id).get("revision",0))+1
		Store.dossiers[id]=d
	Store.dirty=true
	if not Store.host_identity.is_empty():Store.save()
