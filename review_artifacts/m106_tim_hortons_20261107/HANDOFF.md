# M106 Tim Hortons private redesign packet

Production source pins: `scripts/campus_integration.gd` SHA-256 `90DE50B3D38B1D90E81E8B24DEFCB9B55877BBF1BA0D6754614BFB028162695E`; `facility_room.gd` `1DED4BBE3AA6DB7EDE49B88B7F5415A39BF10584B69EA6D88F90410A2F60DD76`; `facility_host.gd` `B127B6CB72ACCC276D6125EDFC8D15385237C2B4C8A4279E9F46B72D3876086F`. Recheck before applying. No shared production file changed in this packet.

Current M106 functional state is already mounted: `FacilityService.mount_room("tim_hortons")` constructs the `FacilityRoom` counter and four seats; `SocialRoomDecor.build_room("tim_hortons")` constructs replacement furniture and `adopt_restaurant_visuals` hides only exact direct legacy BoxMesh visuals. Static collision bodies and functional station keys remain. Existing food IDs are **coffee $3, tea $2, donut $2**, from `FacilityHost.menu`; all other menu categories mentioned in the design brief are unavailable for sale and must not appear as priced products. The host verifies proximity, venue, profile, balance commit, and held food state. Existing facility panel reads actual menu entries and real prices. Unlimited currency presentation is an existing broader economy feature; no change here.

Candidate `m106_finish.gd` adds M106-only gray tile floor (two MultiMeshes), off-white/blue-gray wall panels, ceiling tiles (two MultiMeshes), six square diffuser surfaces (one MultiMesh), fixed red identity sign, three actual product menu boards, an M106 entrance sign above the door, a supported rear coffee shelf, a framed low-alpha pastry guard and a visible payment terminal. Existing restaurant social profile retains the red upholstered chairs, wood tables, pastry display, cups, planters, framed right wall glazing and customer counter. The terminal is visual only; existing host authority remains the real payment system. The candidate adds no duplicated counter/chair/table body, NPC, new menu item, physics, network or save state.

Furnishing coverage audit: `assets/campus/decor/social_rooms/profiles.json` M106 groups supply the 6.2m wide/1m deep cream countertop at y1.08..1.18, 6m red counter fascia y.06..1.08 with wood vertical ribs, coffee machine at local (1.5,1.18,-2.5), pastry food forms at (-1.5,1.18,-2.5), tray stack at (0,1.18,-2.5), four supported 1.5x1m tables at y.7..8, four red chair buckets at functional local seats, selected table cups/trays/baked forms, planters, recycling and existing right wall insets. Existing furniture replacement retains exact old colliders. `m106_finish.gd` now supplies the pastry guard frame x -2.4..-.6, z -2.785..-2.215, y1.18..1.72, and a payment terminal x2.215..2.685 on the counter at y1.18..1.36. The payment terminal is supported by the existing top and does not move the functional `counter` anchor at (0,0,-1.2). The rear shelf at x3.1..5.3,z-5.66..-5.24, y1.095..1.185 has two floor supports and a backed equipment silhouette. These parts do not protrude into the customer queue local x-8..-2.9,z-.45..+.45 or the west entry. No additional dining islands were added without matching collision.

Surgical main adoption after the existing `social_decor.build_room("tim_hortons",...)` succeeds **and** `adopt_restaurant_visuals` succeeds:

```gdscript
var tim_finish := preload("res://scripts/campus/presentation/decor/social_rooms/m106_finish.gd").new()
tim_finish.name = "M106Finish"
tim_finish.position = Vector3(26,0,33)
game.campus.add_child(tim_finish)
if tim_finish.build(facilities.controller.host.menu):
    if not game.campus.register_content("tim_hortons", tim_finish):
        tim_finish.queue_free()
else:
    tim_finish.queue_free()
```

Copy candidate to the named M106-only production path when main adopts. Keep main's existing M104/Subway paths unchanged. The build reads menu before constructing any geometry, so missing IDs abort without partial content. If legacy visual adoption fails, skip this finish. The existing `FacilityRoom` menu and panel remain the interaction source; the new wall boards are physical presentation driven by the same menu object.

Geometry source check: registry M106 center world (26,0,33), bounds x16..36, z27..39, door world (16,0,33), opening z31.8..34.2. Candidate floor x local -9.992..9.992, z -5.992..5.992, top y.014; ceiling grid y3.925..3.973. West wall finish only occupies local z -5.925..-1.375 and 1.375..5.925, leaving 2.75m at the door. Rear wall sign at z-5.79 and y3.2. Coffee shelf x local3.1..5.3, z-5.66..-5.24, away from the fixed counter x-3.1..3.1,z-3..-2. No free-standing route obstruction. Existing `tools/campus/decor/social_rooms/validate.py` passed after the new M106 candidate was authored; it checks the social profile's full transformed mesh footprints, room bounds, west door and order aisle. This packet's new geometry was checked analytically above but not rendered or imported.

Fixture reference for lighting owner: diffuser centers local x -5/0/5, z -3/3, y3.925 (world x21/26/31, z30/36). Existing social pendant geometry is local x4/7.2,z3.3,y3.05. Use at most two actual local lights if shared rig has no M106 contribution, shadow disabled. No global exposure edit. No runtime/visual/FPS claim; runtime owner must check Godot parser, counter support, readability, seat interactions, money/inventory, multiplayer, navigation and screenshots at safe boundary.
