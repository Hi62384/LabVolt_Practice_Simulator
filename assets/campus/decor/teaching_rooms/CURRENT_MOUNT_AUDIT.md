# Current room presentation adoption (source inspection)

The current registry contains 16 named rooms. `game.gd` constructs the campus,
AC equipment, DC lab, shop, and circuit studio. `shop_room.gd` indirectly mounts
the physical component shop and trading fitout. `campus_integration.gd` mounts
the restaurant and gym facilities, all five social decor roots, and clothing
store. Neither game composition file currently calls `TeachingRoomFinish`,
`ServiceRoomDecor` or `CampusDecor` directly.

| Registry IDs | Intended presentation | Current mount |
|---|---|---|
| ac_lab | Existing M101 finish and equipment; optional teaching finish | Existing world mounted; teaching finish absent |
| dc_lab | Existing functional DC benches; teaching finish | DC benches mounted; teaching finish absent |
| elm253_lecture, ety155_lecture, computer | Teaching finish and existing classroom furniture | Teaching finish absent; lecture furniture created by SchoolWorld; computer furniture requires separate review |
| cafeteria, tim_hortons, subway, library, study | SocialRoomDecor | All five mounted in CampusIntegration |
| gym | Gym facility plus ServiceRoomDecor | Facility mounted; service decor absent |
| washroom_1, washroom_2 | ServiceRoomDecor | Service decor absent |
| shop | Existing shop plus ComponentShopFitout | Fitout mounted indirectly in `ShopRoom.build_campus()` → `build()` when its activation contract succeeds; old shop/trade bodies are fallback only |
| clothing_store | Clothing room builder | Mounted in CampusIntegration |
| circuit_studio | Studio mount controller | Mounted in game |

Minimal main-owned additions after `campus_services.build(self)` in `game.gd`:

```gdscript
var teaching := preload("res://scripts/campus/presentation/decor/teaching_rooms/teaching_room_finish.gd").new()
teaching.name = "TeachingRoomFinish"
campus.add_child(teaching)
var result: Dictionary = teaching.mount_approved(campus, campus.registry,
    ["ac_lab", "dc_lab", "elm253_lecture", "ety155_lecture", "computer"])
if not result.failed.is_empty(): push_warning("Teaching finish skipped: " + str(result.failed))

var service_decor := preload("res://scripts/campus/presentation/decor/service_rooms/service_room_decor.gd").new()
service_decor.name = "ServiceRoomDecor"
campus.add_child(service_decor)
for id in ["gym", "washroom_1", "washroom_2"]:
    if not service_decor.mount_profile(id, campus): push_warning("Service decor skipped: " + id)
```

No `CampusDecor` generic registration is needed for those eight IDs; it would
stack its old props with the intended providers. Do not mount a second shop
fitout. `game.gd` calls `shop_room.build_campus(self,campus)`; `ShopRoom.build()`
constructs both physical stations, moves trading to `(26,0,-1)`, and skips the
two legacy bodies only after `activation_contract_valid()` succeeds.
`ShopRoom.interact()` routes their `page` metadata through the existing
electronics UI. Other legacy pages and the return station remain during their
separate replacement handoffs. The fitout is a child of `ShopRoom` under `game`,
not a streamed campus child, but is reachable in campus mode.

The current cafeteria already has social furniture and
seat anchors; the gym currently has a usable facility but its presentation
provider needs the service mount above. None of these source facts establishes
visual acceptance in the active game.
