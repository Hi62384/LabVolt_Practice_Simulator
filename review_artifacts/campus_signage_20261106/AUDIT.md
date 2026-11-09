# Sign transform audit

| Producer | Purpose | Existing transform behavior | Required behavior |
|---|---|---|---|
| `campus_world.gd:sign_text` | Campus room, corridor, directory, entrance, stairs, lift | Yaw is explicit; back-face policy omitted | Keep authored yaw; disable back face |
| `campus_world.gd:_room` | Door identity | Two opposing offsets, but each `+Z` front yaw points back toward the wall; corridor face also includes title/function | Reverse both yaws, disable back faces, use room number only |
| `campus_hud.gd:update_state` | Top-left room identity | Number/title only for registry-shaped dictionaries | Number plus title/function for registry and room-slip shapes |
| `facility_room.gd:label` | Menus and activity instructions | No explicit yaw/back-face policy | Preserve functional content; one-sided authored front |
| `campus_decor.gd:_label` | Decor-owned campus labels | Explicit data yaw; back-face policy omitted | Preserve intended fronts; disable back face; number-only only when role is room identity |
| `school_world.gd` / `room_finish.gd` | Course boards and directions | Explicit `PI` for the opposite wall | Preserve content and intentional rotation |

No negative-scale text repair was found in the audited campus sign constructors. Door-sign yaws point their readable `+Z` fronts toward the wall, so the visible side is the default-enabled back face and therefore mirrored. Other sign producers need their own front checked; this is why the repair is not a global rotation or mirror.
