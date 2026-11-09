# Persistence integration handoff

The adapter consumes the shared v1 catalog dictionary, core resolver
(`AvatarCore.resolve`) and body sanitizer (`AvatarCore.sanitize_body`). Construct
it as `Persistence.new(catalog, AvatarCore.resolve, AvatarCore.sanitize_body)`.
Configure `is_authority` from the actual host or
offline owner context; never from a request field.

## Exact authoritative hook

In `scripts/inventory_authority/ledger.gd`, extend `transact()` at the existing
`match op` block after it creates transaction-local `p` from `a.profile`.
Instantiate this adapter with the authoritative catalog and `AvatarCore.resolve`,
set `is_authority` to a callable that returns true in that host-only method, then
call:

```gdscript
var cosmetic_result := adapter.apply_authoritative(p.data, intent)
if not cosmetic_result.ok:
	return failure(cosmetic_result.error)
p.data = cosmetic_result.profile
```

Use the already authenticated request ID, receipt lookup, `next` account copy,
revision increment, and final `persist(next)` directly below that block. Do not
call `commit_local()` from the ledger and do not create a second store: that
would split currency from ownership and bypass receipt replay protection.

Add the cosmetic operation to the ledger's success-required operation list.
Forward `equip`, `unequip`, `body`, and atomic `edit` intents through the same
authenticated operation. `edit.changes` may contain only body/equip/unequip
changes and is all-or-nothing. If product policy requires a slot to remain
populated, provide its name in the adapter constructor's `required` array;
catalog v1 itself does not currently declare required slots.

The ledger's existing request receipt is the replay authority. Do not add a
second replay journal to the profile adapter. Repeated permanent purchases are
also rejected before any debit.

For reconnect/local reconciliation, add `avatar_cosmetics` to the existing
metadata whitelist only if client equipment edits are intentionally allowed;
owned IDs and dollars must always remain host-owned. Fresh/loaded profiles
should pass through `migrate()` before their first authoritative snapshot so
starter grants become persistent. Supply the selected legacy `character.json`
dictionary once to retain it under `legacy_character`.

Offline code may call `commit_local()` with the authoritative
`ElectronicsProfile`; it snapshots the full dictionary and restores it if the
existing atomic `save()` fails.
