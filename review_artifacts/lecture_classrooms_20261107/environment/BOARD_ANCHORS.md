# Current lecture board and instructor anchor contract

The production `RoomBridge.room()` uses `RoomRegistry.activity_room()` for the
current registry, so the fallback `ClassroomLayout.teacher()` is not the active
anchor formula. For lectures, `activity_room()` sets `teacher_position` to
`center + (0,0,-size.z/2+2)`. Both lecture rooms have 12m depth, making the
instructor z = center.z - 4. The live `SchoolWorld` sets the board 1.4m further
toward the south wall (direction=-1), and its backing panel 1.47m further.

| Room | Courses currently routed here | Center | Instructor anchor | Live board label | Live board backing | South wall |
|---|---|---|---|---|---|---|
| M201 `elm253_lecture` | ELM253, MTH147, MTH255 | (0,5,3) | (0,5,-1) | (0,7,-2.4) | (0,7,-2.47) | z=-3 |
| M202 `ety155_lecture` | ETY155 | (26,5,3) | (26,5,-1) | (26,7,-2.4) | (26,7,-2.47) | z=-3 |

The backing panel is 5.7 × 2.5 × .08m, spanning y5.75..8.25 and
z-2.51..-2.43. This is 0.41m in front of the inner face of the south shell
wall at z=-2.92. The teacher approaches from z≈-1; student desk rows center
at z1 and z5. The board owner should bind the existing progressive content
surface or replace it with an equally positioned functional surface, not put
an opaque decorative panel in front of it. M203 is excluded and owned by the
computer-classroom provider.

Source evidence: `room_registry.gd` `activity_room`, `room_bridge.gd` `room`,
`school_world.gd` `update` and `build_campus_furniture`.
