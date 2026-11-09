extends VBoxContainer
## Candidate destination UI. Mount under ClothingStorePanel's existing root.
signal purchase_requested(request: Dictionary)
signal wear_requested(item_id: String)
const Catalog = preload("res://scripts/campus/facilities/clothing_store/legacy_cosmetic_adapter.gd")
const UI = preload("res://scripts/ui/design_system/widgets.gd")
var profile: Dictionary = {}
var pending_id := ""
var request_id_factory := Callable()
var status: Label
var cards: VBoxContainer

func _ready() -> void:
	add_child(UI.text("Laboratory wear", "SubtitleLabel"))
	add_child(UI.text("Safety glasses, gloves, coat and hard hat for your selected character.", "MutedLabel"))
	status = UI.text("")
	add_child(status)
	cards = VBoxContainer.new()
	add_child(cards)
	_refresh()

func open_profile(snapshot: Dictionary) -> void:
	profile = snapshot.duplicate(true)
	pending_id = ""
	_refresh()

func accept_receipt(result: Dictionary, snapshot: Dictionary) -> void:
	if pending_id.is_empty(): return
	pending_id = ""
	if result.get("ok", false):
		profile = snapshot.duplicate(true)
		status.text = "Purchase complete"
	else: status.text = str(result.get("error", result.get("message", "Purchase failed")))
	_refresh()

func show_wear_result(message: String) -> void:
	status.text = message

func _refresh() -> void:
	if cards == null: return
	for child in cards.get_children(): child.queue_free()
	for row in Catalog.rows(profile):
		var tile := UI.card(str(row.name), "Owned" if row.owned else "$%d" % int(row.price), "palette", "Common")
		cards.add_child(tile)
		var id: String = row.id
		var action := UI.action("Wear" if row.owned else "Buy · $%d" % int(row.price), "check" if row.owned else "cart", func(): _activate(id, bool(row.owned)), true)
		action.disabled = not pending_id.is_empty()
		tile.get_node("Content/Copy").add_child(action)

func _activate(id: String, owned: bool) -> void:
	if owned:
		if not Catalog.wear_settings(id, profile).is_empty(): wear_requested.emit(id)
		return
	if not pending_id.is_empty() or not request_id_factory.is_valid():
		status.text = "Purchase service unavailable"
		return
	var request := Catalog.purchase_request(id, str(request_id_factory.call()))
	if request.is_empty(): return
	pending_id = id
	status.text = "Processing purchase…"
	_refresh()
	purchase_requested.emit(request)
