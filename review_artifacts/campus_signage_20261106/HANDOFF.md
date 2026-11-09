# Campus signage handoff

Status: source implementation and bounded fixtures complete; shared integration is staged, not applied. Live render acceptance remains pending because the user is actively playing and engine/window control was prohibited.

## Stable convention

- `Label3D` readable local front is treated as `+Z` after yaw. The old door yaws pointed each face back toward its wall; the helper reverses those yaws so each `+Z` front points away from the wall.
- Every authored wall sign sets `double_sided = false`; its back is deliberately blank, never mirrored text.
- A sign that must be readable from both directions uses two labels with opposing yaws and small opposing wall-normal offsets.
- Physical room identity signs contain the room number only (`M103`).
- The top-left HUD contains number plus room name/function (`M103 · DC Lab`).
- Directory, navigation, course-board, equipment, menu and other functional text remains intact.
- Do not use negative scale to repair text. Negative scale changes winding/handedness and can break signs that already have the right yaw.

Canonical implementation: `res://scripts/campus/presentation/signage/campus_signage.gd`.

## Shared-owner adoption

Apply `shared_integration.patch` only if these SHA-256 preimages still match:

- `scripts/campus/world/campus_world.gd`: `7DADA66F0D8F30EB0DE950A6366476B45CD039FED8850198DD693717C9ABA37E`
- `scripts/campus/ui/campus_hud.gd`: `764C3D5ECBD1E0C762CC808885B487E0B2BD6241314180FD916193E835811509`

The world hook intentionally routes all campus shell labels through the one-sided factory, but changes content only for the paired physical room signs. The HUD hook accepts both registry (`number`, `title`) and room-slip (`room_number`, `name`) dictionaries.

## Other producer audit

- `scripts/campus/facilities/facility_room.gd` produces restaurant/menu/gym functional labels. Preserve their content. Its owner should set `node.double_sided=false` and confirm each authored front yaw; do not rewrite them as room identity signs.
- `scripts/campus/presentation/decor/campus_decor.gd` appeared during this task and is owned by the decor task. Its label constructor must adopt `double_sided=false`; data yaws must describe the intended readable front. Room-identity entries must contain number only, while decorative/functional entries retain their current semantics.
- `scripts/room_finish.gd` and `scripts/school_world.gd` are legacy/local course and instructional boards. Their content is functional and should remain. Their explicit `PI` rotations are intentional fronts, not evidence that all signs need a mirror.
- Billboarded name tags/chat/equipment readouts are not physical wall signs and are out of this content policy.

## Validation

`tests/campus/signage/signage_tests.gd` checks number-only physical faces, full HUD identity, both east/west opposing yaws, wall offsets, and disabled back faces. `orientation_fixture.json` publishes the same values for bounded source/data validation.

The supplied Library image IDs could not be materialized through a supported Library image flow available in this delegated task. No visual claim was inferred from captions or invented URLs; diagnosis is grounded in the actual `Label3D` construction, opposing transforms and default double-sided behavior. Final local-pixel/readability acceptance is therefore explicitly pending a later non-live render or the user's playtest.
