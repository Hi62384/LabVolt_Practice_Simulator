# Dorm rest source packet

Implemented private host occupancy/authentication state, reliable request and
snapshot controller, instance-local lying pose, floor/capsule checked standing,
disconnect cleanup, blocked-exit retention, and review patches for player,
avatar, game, session and facility visual pose. No production changes or saves.

Main must check PREIMAGES.json before applying the five patches. Keep private
source paths when applying, or consistently relocate preloads. Install with
`game.install_dorm_rest(persistent_dorm_coordinator)` after authority setup on
every peer; node name DormRest must match across peers for RPC dispatch.

Room owner integration: host registers each streamed logical room once via
`game.dorm_rest.state.register_bed(logical_room_id, foot_anchor)`. Resolve logical
room identity through the persistent authority lease, never a client ID or
physical bay. The current bed target is centred at mattress Y .65; a suitable
foot anchor is its global position plus Vector3(0,.16,.85), basis matching the
bed. Register from host-owned room geometry only. Bind the room adapter's rest
callable to `func(_ignored_transform): game.dorm_rest.request(logical_room_id)`.
The transform payload is deliberately ignored. The room adapter already gates
owner interactions; the host repeats owner, entry policy and range validation.
Visitors may enter permitted rooms but cannot occupy the owner's bed.

The controller canonicalizes resting after ordinary pose validation, locks the
root at the host anchor and overrides client seated/crouch claims. Chair claims
are rejected for occupied resting peers. Existing facility translation guard
rejects begin while gym/facility movement is locked. E, Space and Escape request
exit; normal activation is suppressed while resting. No sleep timer or meter.
The lying pose pauses an idle sample and rotates the existing complete visual
rig by a quarter turn, preserving all customized geometry and attachments. Its
original transform and animation selection are restored on exit. Facility visual
updates skip the resting visual to avoid overwriting that transform.

Safe standing uses 65 bounded candidate points, floor slope checks and a full
standing capsule against world/player layers. It excludes the local actor only
for local exits; remote exits do not exclude the host body. Blocked exits keep
the bed occupied and permit immediate retry. Session reset tries safe standing;
if every candidate is blocked it retains the locked state for an exit retry.
Disconnect releases host occupancy. Room unload must wait until no rest occupant
remains, and main must call state.disconnect(peer) before removing a room whose
occupants disconnect. Persistent ownership/storage is untouched.

Validation: stage_hooks.py ran successfully; test_source.py passed three checks
covering exact shared preimages, authority/pose gates, pose reversal and collision
query presence. These are source checks, not synthetic execution of GDScript.
test_rest_deferred.gd supplies an actual synthetic authority/occupancy transition
fixture for the later guarded engine run. It has NOT been parsed or executed.
Physics floor/capsule behavior, multiplayer delivery, reset with blocked exits,
late join, head/camera mode, and visual bounds across custom avatar extremes
remain runtime gates. Long avatars can overhang the single bed; no avatar scale
is silently changed. No engine, CUA, reload, active save or denied operation.

Ready: private implementation and exact shared hooks for main review. Unready:
room-owner mounting and guarded parser/runtime/visual/multiplayer acceptance.
