# Implemented persistent dorm authority contract

Authoritative online identity is ledger.bindings[peer], filtered by current
roster, after credential verification and durable migration. Offline identity
uses the same school profile config. Full 48-hex identities form logical room
IDs; temporary peer/display identities never own rooms. Disconnect never deletes
profiles, room ownership, saved customization or stored possessions.

Durable schema: dorm = {schema:1, owner, room_id, number, policy, invited,
customization:{items,styles}, storage:{type:count}, instances:[registry_id],
revision}. Storage is master-inventory allocation, not copied inventory. Specific
mutable bytes remain solely in component_instances. Deployment, trade and craft
reservations include dorm allocations. Host ledger receipts supply idempotence;
offline saves use bounded dorm_receipts and fail closed at their limit.

Transaction API: ledger.transact(peer, operation_id, "dorm", [intent]). The host
derives peer from its existing inventory RPC sender. intent has integer revision
and op policy(value), invite(value array), storage(item,delta,instances array),
or edit(edit intent). Receipt lookup precedes revision checking. Full account,
new room state and receipt commit together through existing ledger persistence.
Save failure publishes no changed state. Reusing an ID with different content
fails. Metadata cannot replace dorm fields.

Coordinator APIs used by room/rest/router: authenticated_identity(peer),
owner_identity(room), room_for_peer(peer), is_owner(identity,room),
can_enter(identity,room), assignment_revision(), locate_room(peer),
storage_transfer(identity,room,operation_id,item,quantity,into_storage,instances=[]),
request_personal_computer(room). Local mutation adapters submit through the
authenticated ledger; identity arguments are never accepted in an RPC payload.

Private permits owner; Invited permits owner and explicit stable invitations;
Open permits authenticated visitors. All storage, editing, wardrobe, files and
personal stations remain owner-only. Access is rechecked on requests and against
host presence. Public room projections exclude inventory/storage, unique bytes,
private documents, profiles and credentials.

Physical bays are leases, independent of unlimited historical logical owners.
Directory selection reuses an empty bay; no occupied bay is remapped. Room
interiors load while occupied and unload when empty, retaining active bed rest.
At most MAX_PLAYERS occupied logical rooms can exist, so existing MAX_PLAYERS
bays suffice. Historical rooms remain selectable through authenticated paginated
directory requests. Logical coordinates are canonical west, mirrored into east
physical bays. Door requests bind epoch/sequence/range/current lease/policy.

Custom edits invoke the actual DormRoomEdits and DormPlacementRules plus concrete
starter furnishing ownership, surface support, style entitlement, complete-room
geometry and selected lightweight display eligibility. The renderer adopts that
saved state. M203 uses real chairs/anchors and private owner leases rechecked
on every operation; workspace identity is independent of peer-number reuse.
Wardrobe opens the existing clothing panel/collection. Rest uses the separately
owned install_dorm_rest/register_bed/request APIs without editing pose files.

HANDOFF.md records exact application order, hashes, successful source checks,
prepared synthetic fixtures and outstanding isolated engine/runtime acceptance.
