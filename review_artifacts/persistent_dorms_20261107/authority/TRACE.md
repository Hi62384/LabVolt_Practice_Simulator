# Assignment trace and completed private implementation

Confirmed source cause: profile.open returned existing valid profiles without a
dorm migration; school identity acceptance preceded inventory credential binding;
the dorm coordinator reconciled roster entries before that binding, synthesized
peer-based ownership, and neither saved/restored room identity nor displayed it.
Source inspection establishes these defects, not the precise original gameplay
symptom's runtime trigger.

The replacement is actual source, not a proposed contract: see HANDOFF.md,
integration.patch, candidate/, PATCHES.json and DEPENDENCIES.json. Seventeen
candidate files include profile migration/save rollback, pre-binding durable
ledger migration, enrollment-ready signal, receipt-backed transactions, master
stock and instance reservations, offline deployment/trade checks, stable room
ownership, leased entrances, paginated directory, visitor checks, streamed room
and customization adapters, transformed furnishings/collisions, rest registration,
existing wardrobe/stations, and M203 private identity/workspace leases.

The room owner's corrected request_personal_computer(room_id) implementation is
the pinned assembly input. Adapter transformations bind its actual router object
and saved renderer. The rest owner's hooks remain separate and unchanged.
Customization uses the actual packet's host edit and placement validators; it
does not accept arbitrary replacement dictionaries. Public projections contain
only bounded room metadata and allowlisted decorative state.

Ran: stage.py, 11 test_source.py checks, and git apply --check. All passed.
Prepared but did not parse/run: actual GDScript in-memory ledger/profile fixture.
No engine, gameplay, CUA, live save/cache, production, or immutable AC resource
operation occurred. No denial occurred. Runtime/visual/physics/multiplayer and
isolated disk persistence acceptance remain for the sole production integrator.
