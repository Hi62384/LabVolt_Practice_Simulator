# M203 station contract (room owner)

M203 registry bounds are x [-10,10], y [5,9], z [13,25]; east door is (10,5,19), width 2.4 m. Front teaching wall is south (z=13). This layout has 20 stations, five columns by four rows, with desk centers x `[-7.2,-3.6,0,3.6,7.2]`, z `[16.2,18.4,20.6,22.8]`. Row 0 faces the south display. IDs are `m203_r{row}_c{column}` with zero based row and column.

All positions below are world coordinates; station scene local origin is the desk center at floor y=5, with local forward `-Z`:

* desk footprint: x ±0.85, z ±0.43, top y=5.77.
* seat anchor: desk center + (0,0,+0.98); seated eye: seat anchor + (0,1.18,0).
* interaction anchor: desk center + (0,0,+1.38); interaction radius 1.45 m.
* screen center: desk center + (0,1.17,-0.17), facing +Z toward seated player; visible display about 0.64 x 0.37 m.
* worksheet area: desk center + (-0.56,0.79,+0.15); clear surface ~0.40 x 0.42 m.

Reusable `computer_station.gd` exposes `station_id`, `seat_anchor`, `interaction_anchor`, `screen_anchor` and `worksheet_anchor` as child nodes. Session logic may claim the ID and seat anchor; it must not depend on visual child mesh names. All world positions are available through each anchor's `global_transform` after mount. `m203_room.gd` exposes `stations` by ID. No scene creates a desktop or starts a session.

Front instructor desk is centered at (0,5,14.7). Teaching display mount is on the south wall at (0,7.2,13.22), facing north (+Z). The existing lesson whiteboard remains authoritative; the integration owner should pass that content through the teaching display adapter. Do not add a static panel over the lesson board.

Clearance: eastmost desk edge x=8.05 leaves 1.95 m to the east wall. East doorway spans z=17.8..20.2, and the east aisle is open. Northmost chair reaches about z=24.2, leaving 0.8 m rear clearance. Desk row pitch is 2.2 m, with 1.34 m between desk footprints. Column gap is 1.9 m between desk footprints. The first desk front is z=15.77, leaving 2.77 m for instructor movement from the south wall. Station chair meshes are visual; the desk has a single simple collider. Existing academic seating should use these anchors if M203 becomes an activity room.
