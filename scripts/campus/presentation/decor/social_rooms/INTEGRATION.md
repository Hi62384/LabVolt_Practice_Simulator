# Five social room mount contract

Source state inspected 2026-11-06. `scripts/campus_integration.gd` SHA-256 before any main edit: `164F110768D0C9712D2A07227AE6C4F5621BE5D35D877A0DA1991AB1D4BB293A`. Recheck before patching. This worker did not edit that file.

The cafeteria is absent because `CampusDecor.register_streamed` is never called in the inspected composition and `FacilityRoom.build` excludes `cafeteria`. This provider creates presentation only; it does not create functional seat, food, or transaction anchors in the cafeteria. Main must decide whether to add a cafeteria facility service separately. No claim of usable cafeteria seating is made.

Mount hook, after `facilities.mount_room` and before player use:

```gdscript
var social_decor := preload("res://scripts/campus/presentation/decor/social_rooms/social_rooms.gd").new()
social_decor.name = "SocialRoomDecor"
game.campus.add_child(social_decor)
for id in ["cafeteria", "tim_hortons", "subway", "library", "study"]:
    # The provider stages all meshes before register_content. Failure leaves
    # preexisting visuals intact; do not exclude generic dressing on failure.
    if social_decor.build_room(id, game.campus.registry, game.campus):
        # If generic decor has been mounted separately, exclude this id from its
        # allowlist before generic registration. Existing generic content already
        # mounted needs explicit removal only after this succeeds.
        if id in ["tim_hortons", "subway"]:
            if not social_decor.adopt_restaurant_visuals(id, facilities.rooms.get(id)):
                # Leave existing visuals intact; do not claim completed adoption.
                push_warning("Restaurant furniture visual handoff failed: " + id)
```

The existing zone streamer has one loader slot per room. Avoid a second `register_loader` call for these IDs, since the last call overwrites the first. This provider uses eager room construction then `register_content`, which applies zone visibility. `adopt_restaurant_visuals` checks the precise fixed direct BoxMesh positions and full expected count before hiding them; collision bodies remain children of those meshes and are not disabled. Menu labels, stations, `placed_food`, and `sync_food` remain. Call `restore_restaurant_visuals` for fallback. If adoption fails, the new room decor should be removed via `roots[id].queue_free()` and the existing restaurant remains intact.

`cafeteria_seat_anchors()` returns sixteen stable `FacilityHost` seat entries at safe approach points behind the authored chairs. The existing host handles ownership, sit/stand, movement lock, and saves. It does not teleport avatars onto the visual chair; that is consistent with existing facility seat activity. Main's small shared hook after all five `build_room` calls:

```gdscript
if social_decor.roots.has("cafeteria"):
    facilities.controller.host.anchors.merge(social_decor.cafeteria_seat_anchors(), true)
    facilities.cafeteria_seat_source = social_decor
```

`facility_service.gd` needs one field `var cafeteria_seat_source: Node` and an early branch in `nearest(position_value)` after `room_id` is computed:

```gdscript
if room_id == "cafeteria" and is_instance_valid(cafeteria_seat_source):
    return cafeteria_seat_source.nearest_cafeteria_seat(position_value)
```

This reuses existing `FacilityHost.act("sit")` and `act("stand")` and does not add food sales. The serving island is decorative. No existing cafeteria service was found in the inspected composition. Main must apply this small hook before cafeteria seats become interactive; the worker owns no shared service file.

Static admission: `python tools/campus/decor/social_rooms/validate.py` passed. It checks full transformed footprint rectangles against entry lanes and the existing restaurant order aisle, and all transformed corners against registry shell bounds. There are 41 original OBJ material surfaces, 128 room batches total, at most 27 per visible room. Placement counts: cafeteria 121; Tim Hortons 55; Subway 55; library 120; study 120. Expanded triangle estimates respectively 21,528; 11,144; 11,760; 51,080; 51,080. The restaurant's four table and seat centers match the existing facility furniture positions; removed the two additional decorative dining islands because they lacked matching collision. Existing facility collisions remain under the hidden exact BoxMesh visual children. The authored counter footprint matches the old counter top's 6.2 by 1m outline; curved chairs fit within the old 0.65m seat footprints. There is no new physics, light, per-frame processing, network state, or saved state. Actual Godot import, winding, visibility, draw calls, occlusion, collision and visual quality still require testing at a safe boundary.
