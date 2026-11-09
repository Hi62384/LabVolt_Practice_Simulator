class_name ClothingStoreCatalog
extends RefCounted

const Catalog = preload("res://scripts/avatar_cosmetics/core/catalog.gd")
const CatalogAdapter = preload("res://scripts/avatar_cosmetics/ui/catalog_adapter.gd")
const SOURCES := [
	"res://assets/cosmetics/footwear/catalog.json",
	"res://assets/cosmetics/clothing/catalog.json",
	"res://assets/cosmetics/accessories/catalog.json",
	"res://assets/cosmetics/faces_hair/catalog.json",
]
const SHOP_CATEGORIES := ["tops", "bottoms", "shoes", "accessories", "hair", "facial_hair", "faces"]

var items: Dictionary = {}
var errors: Array = []

func _init() -> void:
	var definitions: Array = []
	for path in SOURCES:
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not parsed is Dictionary or not parsed.get("items") is Array:
			errors.append("Invalid cosmetic catalog: " + path)
			continue
		definitions.append_array(parsed.items)
	var collected := Catalog.collect(definitions)
	items = collected.items
	errors.append_array(collected.errors)

func browse(category := "", query := "") -> Array:
	var rows: Array = []
	var needle := query.strip_edges().to_lower()
	for definition in items.values():
		if definition.get("legacy", false):
			continue
		if category != "" and definition.get("category", "") != category:
			continue
		if not needle.is_empty() and not (str(definition.get("name", "")) + " " + str(definition.get("id", ""))).to_lower().contains(needle):
			continue
		rows.append(definition.duplicate(true))
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var price_order := int(a.get("price", 0)) - int(b.get("price", 0))
		return price_order < 0 if price_order != 0 else str(a.name).naturalnocasecmp_to(str(b.name)) < 0)
	return rows

func supported_parameters(item_id: String) -> Dictionary:
	return CatalogAdapter.supported_parameters(items.get(item_id, {}))

func item(item_id: String) -> Dictionary:
	return items.get(item_id, {}).duplicate(true)
