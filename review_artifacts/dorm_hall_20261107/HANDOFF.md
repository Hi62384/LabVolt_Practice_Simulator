# Dorm hallway visual handoff

Production source inspected: `scripts/campus/dorms/world/dorm_hall.gd`, SHA-256
`2aafa8a9bb6c7452459a3c7f1b19b637954f454b314c5c96f1263750b0d24d1c`.
The coordinator currently rotates `DoorPivot` by `PI/2` for an open door.
Keep `DormHall/<dorm_id>/DoorPivot/Door/CollisionShape3D` under that pivot so
the visual and collision move together. Do not change room IDs or door centers.

## Staged visual changes

In `_build_corridor`, retain HallFloor's original solid and NorthEndWall's
original solid. Change their surface colors to clean gray and off-white. Add
thin noncolliding floor tile seams across the six-metre width at regular 1.5 m
intervals, blue-gray wall panels only on closed entry-wall spans, wood baseboards
and ceiling trim. The current instanced CeilingPanels may be retained and given
simple rectangular bezels. Use no per-room dynamic lights. At the north wall,
add a shallow noticeboard or seating detail within the existing walkable bounds;
do not create an exterior window without a verified exterior view.

In `_build_room`, preserve EntryWall and DoorLintel collision. Add visible dark
wood frame jambs at z = center.z ± `Layout.DOOR_WIDTH / 2`, with a thin lintel.
Place the actual `contract.dorm_id` on a small wall plaque beside each door,
facing the hall. Reserve a separate optional nameplate node with no private
identity rendered until the authority layer supplies an authorized public name.

In `_build_door`, retain the existing `AnimatableBody3D`, pivot and collision.
Add recessed panel relief, hinge barrels on the pivot's negative-z edge, and a
handle and lock escutcheon on both faces. Keep all moving detail under `Door`
or `DoorPivot`; stationary frame and plaque belong directly under the room root.
The coordinator's `PI/2` rotation must be checked for both sides against player
exit clearance before changing swing direction.

Decoration should occupy the wall edge, never the central x=11..15 circulation
lane or either door's 1.3 m opening. A noticeboard must use existing notice data
only; a blank board with an optional content hook is acceptable.

No production patch is applied here. The current active game cannot be used for
visual, collider, multiplayer, or screenshot acceptance. This handoff is a
reviewable design boundary, not a completed redesign.
