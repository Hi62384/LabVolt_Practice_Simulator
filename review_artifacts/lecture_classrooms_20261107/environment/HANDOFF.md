# Reusable lecture-room furniture packet

The current registry has two lecture rooms, M201 and M202, each 20 × 4 × 12 m
with eight desk and eight seat anchors. ELM253, MTH147 and MTH255 share M201;
ETY155 uses M202. MTH courses are not new rooms. `SchoolWorld` already creates
the eight collidable desks and eight interactive rolling chairs per room.

`classroom_furniture_skin.gd` visually replaces each existing desk top/frame
after creation. The existing `StaticBody3D`, collision shape, role, worksheet
surface y=0.8, seat index, multiplayer chair and paper authority are unchanged.
The old legs bottom at y=-0.045, penetrating the floor; the new legs end at
y=0.010. `MOUNT.patch` adds one call in the shared builder for both lecture
rooms, with a guard on the exact desk collision size. Main should adopt only
after checking the current `school_world.gd` preimage from `check_layout.py`.

The mounted TeachingRoomFinish and ReferenceStyleFinish already supply lower
wall finish, trim and ceiling features. This packet deliberately does not
stack a second ceiling, signs, whiteboard, instructor desk or light over them.
The separate board owner controls the functional lesson surface. The existing
instructor anchor and 120-second countdown stay in their current systems.

`classroom_chair_skin.gd` changes only MeshInstance3D children under the
existing rolling chair swivel; the base, wheel animation, collision, yaw,
occupant, sit and stand logic remain unchanged. `instructor_area.gd` mounts a
small lectern outside the live board width, a computer-shaped terminal, clock
and perimeter cabinet using the campus zone visibility API. Adopt
`INSTRUCTOR_MOUNT.patch` once after campus services build. No second board,
room sign, ceiling or light is added. Instructor circulation, board readability,
lighting and player seated pose require later camera and multiplayer validation; source
geometry alone cannot establish those outcomes. No engine or live game was run.
