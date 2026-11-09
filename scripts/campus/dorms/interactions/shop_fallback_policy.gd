class_name DormShopFallbackPolicy
extends RefCounted

## Shared shop code can query this policy before presenting a legacy personal
## station. Purchasing, custom circuits and trading are never suppressed.

const PERSONAL_PAGES := ["kits","inventory","notes"]

static func legacy_station_enabled(router: DormPersonalStationRouter, page: String) -> bool:
	if page not in PERSONAL_PAGES:return true
	if not is_instance_valid(router):return true
	return not router.shop_page_has_dorm_replacement(page)

static func filter_legacy_station(router: DormPersonalStationRouter, station: Node) -> void:
	if not is_instance_valid(station):return
	var enabled := legacy_station_enabled(router,str(station.get_meta("page","")))
	if station is CollisionObject3D:station.collision_layer=4 if enabled else 0
	if station is Node3D:station.visible=enabled
