# Persistent dorm authority implementation

Actual implementation: `integration.patch`, 17 candidate source/test files in
`candidate/`, exact current production preimages in `preimages/`, and SHA-256
preimage/candidate hashes plus individual patches in `PATCHES.json`.
`stage.py` regenerates this packet from current source and the room/customization
packets without writing production. `DEPENDENCIES.json` pins those packet inputs
and the adopted rest API. Check all hashes before integration; stop on drift.

The sole production integrator applies the source patch and the separate rest
packet's five shared-file hooks. This packet does not include those hooks or
change the other owners' files. The coordinator installs the rest controller
through the actual `game.install_dorm_rest(self)` hook, registers the transformed
bed anchor, binds rest requests, and keeps occupied resting rooms mounted.

## Implemented behavior

- Both valid existing profile load and first profile creation migrate through
  the existing profile-key-to-school-identity config. An absent identity is
  generated in that same config before migration. The existing profile save
  method commits the whole profile; a failure restores in-memory preimage.
  Malformed dorm data is retained and reported instead of silently reset.
- Host `ledger.bind` migrates before it publishes a successful binding/snapshot.
  The enrollment network emits `profile_ready` only after successful bind.
  The coordinator uses credential-bound ledger identities, checks current roster,
  and handles delayed offline readiness. Peer numbers and display names never
  become persistent ownership. Rejoin metadata cannot overwrite saved dorms.
- Logical room IDs are `dorm_` plus the full 48-hex stable identity. The visible
  persisted number is `D-` plus that identity, avoiding truncation collisions.
  Disconnect clears transient presence only. Existing host accounts retain rooms
  and contents across restart, mode change, and reconnect.
- Physical hallway bays are reusable leases. Empty bays are used first; only an
  unoccupied bay may be remapped. The directory mounts any selected authorized
  historical owner's room in an available bay. At most eight peers means at most
  eight simultaneously occupied logical rooms; historical owners are unlimited
  by entrance count. Full occupancy refuses remapping without changing ownership.
  Door use enters/exits through the existing physical bay anchor. The host checks
  sender binding, epoch, monotonic sequence, distance, policy and current lease.
  Host pose checks remove unauthorized tailgaters and revoked visitors.
- The directory shows the local profile's room number, hallway mapping, access
  policy controls, and explicit persistent-ID invitations. Private, Invited and
  Open are the only policies. There is no invented friends service. Per-peer
  directory pages contain 32 historical rooms plus the owner's room; previous/
  next requests are authenticated and range checked at the physical directory.
- `ledger.transact(...,"dorm",[intent])` uses the existing durable receipt archive
  and full-profile atomic store commit. Receipt lookup precedes room revision
  validation, so a successful retry cannot duplicate a transfer. Changed payload
  under the same ID fails. Save failure publishes neither new allocation nor a
  receipt. Storage is a reservation of master stock, never another inventory.
  Deployment, crafting, trading, specific mutable instances, and offline DC
  deployment all honor storage allocations. Instance bytes stay in the existing
  registry, and explicitly selected stored instances cannot be materialized or
  transferred elsewhere. Storage operations reject unresolved legacy trades.
- Offline transactions use the existing profile save, rollback, and a bounded
  256-operation receipt map; a full map refuses new operations without dropping
  receipts or contents. Online transactions use the existing archive lifecycle.
- Saved customization uses the packet's actual `DormRoomEdits.apply` and
  `DormPlacementRules.validate`, plus starter catalog ownership, style entitlement,
  surface support, and whole-layout validation. Starter footprints match the
  supplied furniture. Canonical west-room coordinates mirror into east bays.
  The renderer moves/rotates/hides starter groups and builds simple collisions;
  only selected lightweight project representations render, capped at three.
  Removing a support while its laptop/lamp/display remains is rejected.
- The contextual decorate panel uses the supplied thumbnails/controls, a local
  translucent preview, real host result delivery, saved revisions and rollback.
  The panel closes on room loss. Wardrobe uses the existing clothing/customization
  panel and collection. Storage has generic and unique-instance actions.
- Room adapters stream furnished interiors while occupied and release empty
  rooms. The original primitive furnishing calls are removed from the hall,
  while hallway shell, doors and anchors remain. Existing kit/loadout/notes router
  calls are corrected to its actual object.
- Personal computers register real existing game chairs with M203's adopted
  session service. Private station owner checks run on entry and every operation.
  Session identity and workspace identity are bound independently of peer number;
  peer reuse clears old workspaces. Private profiles/files never broadcast.
  Saved chair/laptop positions update station anchors and hidden/picked-up laptops
  lose their lease. The shared desktop and local document persistence remain in
  use; unsupported browser/execution behavior is unchanged.

## Verification and limits

Ran `python stage.py`, `python test_source.py` (11 passing checks), and
`git apply --check --ignore-space-change integration.patch` (pass). These verify
exact source/candidate hashes, patch applicability, resource paths, source gates,
adapter APIs, and source-derived starter bounds/overlap/entry geometry. They do
not parse or execute GDScript and are not gameplay verification.

`test_authority_memory.gd`, staged as
`tests/campus/dorms/authority/test_persistent_memory.gd`, exercises actual candidate
ledger/helper methods with synthetic profiles, in-memory persistence and a fake
hot receipt lookup: migration preservation/idempotence, enrollment before binding,
stale-peer rejoin, restart from persisted state, 25 historical owners, adversarial
policies/metadata, storage/retrieve conservation and replay, unique instances,
overflow, failed saves and doorway rejection. It never calls profile.open or
uses live profile paths. It has NOT been parsed or run. Real receipt archive and
disk fault injection remain covered by the existing authority test suite and
must be rerun in the integrator's separately authorized isolated engine context.

Still required under those safe resources: Godot parse/type checks, executing
the synthetic fixture and existing inventory regressions, isolated new/legacy
profile disk reload, multiplayer late join/reconnect, pose/range/visitor checks,
moving furniture while seated/resting, visual collision QA, UI input/scrolling,
directory capacity/message behavior, and screenshots. The long untruncated room
number needs UI scale review. Directory packets are paginated and bounded to
262144 bytes. Unsupported catalog/style entitlements fail closed;
this packet does not invent paid dorm merchandise or duplicate cosmetic stock.

No production source, game/cache, live profile, engine, CUA, AC device or resource
was changed or invoked. No action was denied. A redundant connector returned
HTTP 429; trusted follow-up confirmed this matching local project, so filesystem
source work continued. This packet is complete source work for integrator review,
with runtime acceptance explicitly outstanding.
