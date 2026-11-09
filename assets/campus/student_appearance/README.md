# Student appearance data contract

NPC appearances reuse the existing `labvolt_toon_v1` cosmetic catalogs. No NPC-only
copies of meshes or textures are stored here. `StudentAppearanceProvider` produces a
compact `{v, appearance_id}` network packet and reconstructs body, face, hair,
clothing, accessory, and color choices deterministically on every peer.

The crowd lifecycle owner should request an appearance once when a student identity is
spawned, pass the returned state and `provider.catalog()` to the shared avatar renderer,
and retain that rendered node across visibility changes. It must not request a new
identity on hall enter/exit. Legacy renderers can consume `legacy_character` from the
same state. NPC catalog choices are render data only and never grant player ownership.
