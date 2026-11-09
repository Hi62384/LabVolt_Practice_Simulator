# M104 cafeteria isolated redesign candidate

Source pins (2026-11-07 packet): `scripts/campus_integration.gd` SHA-256 `9C37EF2A0AF23FCE67D5396C0928CD8D5CC17923C2405F5084D2B384494D1088`; `scripts/campus/facilities/facility_service.gd` `0B01C6017F837CC4682A56CDBC1C68A3C2134DDB0BB5E92EC1C13E5EE1B1802F`; registry `B77D54AFE7549492476FE5B335F5482DB5D64631577101FD262F911F18485335`. Recheck all before applying. This packet made no shared production edits.

Existing social provider is mounted for five rooms in `campus_integration.gd`. M104 has sixteen chair visuals and `cafeteria_seat_anchors()` merged into `facilities.controller.host.anchors`; `facility_service.nearest` calls `nearest_cafeteria_seat`. Keep these exact calls and anchors. The facility host owns sit/stand, occupancy, reachability, movement lock and save state. No cafeteria vendor or currency API was found; Tim Hortons and Subway remain the functional branded food vendors. The M104 serving island remains a food display, not a purchase terminal. Do not imply a fake payment interaction.

Candidate `m104_finish.gd` supplies local tile floor, suspended ceiling and grid, wall finish/baseboards, six diffusers, fixed wall menu and room sign, and two restrained poster backplates. Its 240 floor tiles, 60 ceiling panels and six diffusers are three shared-material MultiMeshes (five batches with two tile colors). There are 20 narrow grid rails, plus trim and signs. No new physics or global environment change.

Main's surgical production adoption after the M104 `social_decor.build_room` success branch:

```gdscript
var finish := preload("res://scripts/campus/presentation/decor/social_rooms/m104_finish.gd").new()
finish.name = "M104Finish"
finish.position = Vector3(26,0,19)
game.campus.add_child(finish)
finish.build()
game.campus.register_content("cafeteria", finish)
```

Copy the candidate source into that M104-only production path during adoption. If `register_content` fails, remove `finish`; leave existing social profile and seat anchors untouched. No other profile or shared material is changed. Reuse the existing M104 social profile geometry: eight tables, sixteen green chairs, ribbed serving island, trays/cups, sorting station, plants, pendants and simulated window insets. The finish candidate adds no competing furniture. The real west door (world x=16,z=19, 2.4m opening) is left untrimmed in its doorway section. Existing room footprint is world x16..36, z13..25, floor y0, ceiling y4.15.

Fixture reference for lighting owner: square diffuser centers in local coordinates `(-5,-3)`, `(-5,3)`, `(0,-3)`, `(0,3)`, `(5,-3)`, `(5,3)` at y3.925; world x21/26/31, z16/22. Existing social profile pendant centers are local x -5.2/-1.2/3/7, z -3.3/3.3, y3.05. They are geometry only. Prefer **no more than two** actual local lights, shadow disabled, placed behind selected diffusers; coordinate with shared lighting rig to avoid duplicate emitters. Do not alter global exposure.

Seat reference: 16 existing chair positions in `source_profiles.json` `rooms.cafeteria.seat_visuals`, with IDs `cafeteria/seat_00` through `_15`. Do not move any chair unless matching `cafeteria_seat_anchors` are regenerated and route/exit checks rerun. Current `FacilityHost` sit/stand retains the player's standing position instead of teleporting onto the chair; the visible sitting pose needs runtime review.

Offline source checks: prior `python tools/campus/decor/social_rooms/validate.py` passed for full M104 mesh footprints and door lane. Finish geometry floors are y.002..014, below player movement; ceiling is y3.925..3.973, above head clearance; west doorway trim covers only z outside local +/-1.375, leaving the 2.4m opening. Sign at doorway is above y3.1. The finish has no collisions and does not modify seating, food, profile, network, currency or inventory code. Godot parser/import, wall appearance, food and multiplayer interactions, lighting and screenshots remain for runtime owner at a safe boundary. Source counts are not an FPS or visual pass.
