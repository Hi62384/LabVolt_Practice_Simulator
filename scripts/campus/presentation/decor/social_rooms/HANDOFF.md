# Social rooms — interrupted implementation handoff

Status: incomplete; stopped promptly on coordinator instruction to apply the user's model cap. No engine, CUA, server, render, reload, save action or runtime validation was performed. No shared code was edited. No generated assets exist from this work yet.

Completed atomic write: `tools/campus/decor/social_rooms/build_social_rooms.py` (original authored mesh/profile generator). It has NOT been run or syntax checked. Review it before generation. It proposes rounded pedestal tables, curved-back tubular chairs, ribbed counters, trays/cups/food, sorting bins, closed leaf meshes, pendants, wall-mounted simulated glazing, populated shelves, screened study desks/task lamps and reading armchairs. Some details and clearance checks still need correction; do not treat the generator as accepted output.

Verified source observations:

- Actual IDs/numbers: cafeteria M104; tim_hortons M106; subway M108; library M204; study M205.
- All five are 20 by 12 metres. Centers respectively [26,0,19], [26,0,33], [26,0,47], [26,5,19], [0,5,33].
- `scripts/campus/presentation/decor/campus_decor.gd` exists with `register_streamed`, but inspected `scripts/campus_integration.gd` and `scripts/game.gd` contain no mount of it. Thus the generic JSON alone does not furnish the cafeteria.
- `campus_integration.gd` mounts facility service rooms only gym/tim_hortons/subway. `facility_room.gd` rejects cafeteria/library/study. This explains missing cafeteria furniture at the inspected source composition level; screenshot was unavailable and no visual claim is made.
- Existing restaurant counter local center [0,.55,-2.5], size [6,1.1,.8]; top [0,1.13,-2.5] size [6.2,.1,1]. Functional counter anchor [0,0,-1.2].
- Existing four restaurant tables local x=-4.5+(i%2)*4.2, z=1+(i/2)*2.7. Seat anchors table+[0,0,.9]; meshes have seat center offset z .95, back offset z 1.22. Preserve station IDs, all anchors, menu labels, food sync, collision bodies and host services.
- Streamer stores exactly ONE loader per room. Registering a second provider overwrites the first, so composite loading must be owned by the integrator. `register_content` controls visibility immediately based on active zone. Loader stages return false until complete. New source provider should build hidden staging content, register it atomically, then exclude/remove generic decor only on success.
- No AGENTS.md found in workspace or direct ancestor paths checked. No git repository detected at cwd. Existing shared files were only read, not preimage-copied or hashed yet.

Remaining required work:

1. Review/fix/run generator offline; validate triangle normals and winding (OBJ outward CCW importer expectation), UV/index completeness, nondegenerate surfaces, room bounds, full transformed mesh AABBs, door and protected aisle exclusions, restaurant seat anchor envelopes and overlap. Current intended cafeteria counter and extra seating may need spacing revisions. The coffee machine currently placed at floor level in cafeteria needs a supporting beverage console. Library/study currently share most geometry and could use a stronger differentiated layout.
2. Implement provider under this directory with cached mesh/material resources, incremental loading (one batch per stage), registry-relative coordinates and graceful missing-resource failure. Avoid orphaned hidden staging trees and preserve generic decor on failure. No physics or lights unless explicitly approved by integrator.
3. Optional restaurant visual adapter must hide only the exact preexisting BoxMesh visuals after replacement succeeds, preserving their collision child bodies and dynamic placed_food. Existing menu labels stay visible. Do not mutate authoritative stations. Cafeteria/library/study authored chairs are presentation only unless integrator adds authorized existing seat API hooks; do not claim gameplay seating works.
4. Preserve shared source preimages/hash manifest in the assigned directories. Supply a preimage-bound patch or exact assembly hooks to main, without editing shared composition.
5. Write bounded offline validation script/tests/report and budgets. No runtime acceptance claims. Actual visual/physics/interaction/performance validation awaits safe user boundary.

Ownership remains exclusively assets/campus/decor/social_rooms/, scripts/campus/presentation/decor/social_rooms/, tools/campus/decor/social_rooms/, tests/campus/decor/social_rooms/.
