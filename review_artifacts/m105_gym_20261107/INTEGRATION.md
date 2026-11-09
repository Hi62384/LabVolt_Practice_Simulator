# M105 gym assembly and verification

This package owns M105 only. The reference image was described by the coordinator as a simple college gym; its pixels were not inspected here. No Godot process, live game, save, or player session was touched.

## Results ready now

- `generated/profiles.json` and ten original, explicit-normal OBJ material batches: wood plank sports floor, two-tone wall finish, ceiling bays, rectangular unlit fixtures, framed training prints, lockers, perimeter benches, stretching mats, and organized medicine balls. 69 object groups, 5,852 triangles, 10 material batches. The moving barbells and plates are built once by the motion adapter, so they do not overlap static plates. No new sun or local realtime lights.
- `m105_decor.gd` loads all meshes before publishing the M105 root. It adds no colliders or authority state and registers the visual with existing room streaming.
- `gym_equipment_motion.gd` reconstructs bar motion from reliable exercise phase events on each client. It creates no rigid bodies and sends no frame updates. Existing avatar arm/torso cosmetic activity remains the player animation source.
- Four exact-preimage patches add validated weight choices, compact weight/rep feedback, remove static bars and floating gym instructions, and bind M105 presentation to the facility controller. See `patch_manifest.json` for full SHA-256 preimages. Do not apply after a shared file changes without rebasing and review.
- Existing host already enforces one owner per station, clears occupancy on finish/cancel/disconnect, keeps gym profile saves per identity, checks timing and reach, broadcasts phase events, and unlocks existing emotes. These mechanics are retained.
- `validate_m105.py` passed on generated assets. It checks source meshes, normals and winding, triangle/draw-call budgets, bounds, entrance clearance, and existing occupancy/cleanup hooks. This is source admission only.

## Exact integrator assembly

1. Copy `generated/profiles.json` to `assets/campus/decor/m105/profiles.json`; copy `generated/meshes/*.obj` to `assets/campus/decor/m105/meshes/`. The JSON resource paths already point to that destination.
2. Copy `m105_decor.gd` and `gym_equipment_motion.gd` to `scripts/campus/presentation/decor/m105/`.
3. Recheck every preimage hash in `patch_manifest.json`, then apply the four patches in a controlled shared integration. Do not apply `campus_integration.gd.patch` before the asset/code copies.
4. If a generic decor root for `gym` exists, hide it only after `M105Decor.mount()` returns true. Existing `CampusDecor` has no `get_room_root` method, so use `room_roots.get("gym")` after successful mount. Keep the existing `FacilityFurniture` root active; its stations and collision remain authoritative.
5. The old generic `service_room_decor.gd` gym profile must not also mount. Washroom owners may continue using that provider for their rooms. Keep room M105's central registry number, walls, door, shell, and navigation unchanged.

## Binding contract and limits

- `FacilityController.room_event(peer, state)` is the event source. `gym_equipment_motion.on_room_event` consumes `exercise`, `phase`, `reps`, and `station`. The host emits one event per half rep and one start/stop event. Remote peers interpolate the same equipment motion locally.
- `FacilityHost.WEIGHTS` allows bench/squat 10, 20, 40 kg; curl 5, 10, 20 kg; bodyweight exercises 0 kg. Weight is server validated and kept in active state, and XP bonus is bounded. The existing profile schema saves XP and best rep counts; it has no exercise history, set count, weight records, or achievements beyond emote unlocks. Those are not claimed.
- The current first-person avatar presentation rotates named arm nodes when available, but has no skeletal hand targets. Bar and arms follow the same host phase; exact grip contact and no-clipping across all customized avatars require runtime visual correction. Likewise, the current facility panel is compact in content but retains its existing panel chrome/size; final sizing needs visual review.
- Station anchors remain the five existing `FacilityFurniture` positions. Squat bar aligns at local `(-5,1.35,2.8)`, bench bar at `(4,1.25,-2.8)`, curl dumbbell at `(-.5,.82,2.3)`. All geometry profile coordinates are relative to M105 center `(0,0,33)`.
- The existing facility room labels were deliberately removed in a staged patch. Use existing number-only physical room signage and the contextual HUD for room name; do not add free-floating text.

## Safe-boundary runtime acceptance still required

Run the relevant existing `tests/campus/facilities/test_facilities.gd`, `test_network.gd`, `test_persistence.gd`, and `test_visual.gd` after integration. Their occupancy/save assertions remain relevant, but they do not validate the new weight selection or visuals. Add fixtures for invalid weight, simultaneous start at one station, disconnect release, and phase propagation. Then run real M105 first-person and two-client visual/physics/performance checks at a safe boundary, including door access, every station approach, bar support/hand contact, customized avatars, rep save/reload, and screenshots. No runtime or screenshot acceptance is claimed by this package.
