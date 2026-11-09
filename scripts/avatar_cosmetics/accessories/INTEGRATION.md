# Accessory renderer handoff

The integrator owns shared renderer/catalog files. Load `res://assets/cosmetics/accessories/catalog.json`, append its `items` to the definitions passed to `Catalog.collect`, and preload `res://scripts/avatar_cosmetics/accessories/accessory_provider.gd` in the renderer.

For each equipped accessory slot (`head`, `eyewear`, `ears`, `neck`, `wrist_left`, `wrist_right`, `back`), call `AccessoryProvider.instantiate(definition, Core.sanitize_parameters(definition, entry.parameters), body)` and then `AccessoryProvider.attach_to_avatar(avatar, item, definition)`. Keep the returned item as the reversible equip handle. On failure, queue-free it.

Exact renderer delta: before `Toon.build(legacy)`, suppress legacy duplicates only for occupied collectible slots: set `legacy.hat = "None"` for `head`, `legacy.glasses = "None"` for `eyewear`, `legacy.earrings = false` for `ears`, and `legacy.watch = false` for either wrist slot. Do not clear unrelated legacy fields. After attachments, call `AccessoryProvider.sync_legacy_hair(avatar, head_definition_or_empty_dictionary)`. Passing `{}` on unequip restores `Body/Head/Hair`; repeated calls are safe. This avoids duplicate legacy models across equip/unequip/re-equip without deleting nodes or mutating saved legacy data.

Never alter shared meshes/material resources. The provider duplicates every surface material before parameter coloring. Fit consumes the already-sanitized `.65–1.4` body values without narrowing them: head items inherit the complete `Body/Head` transform, neck/back items account for width/torso dimensions, and the watch follows arm length while retaining its cross-section.

The `physical_backpack_visible` conflict tag must be represented by the gameplay backpack appearance definition/state when one is visible; `AvatarCore.resolve` then rejects the cosmetic conflict without silently evicting either item. If physical packs are not catalog equipment, the gameplay renderer should suppress only the cosmetic back item while the physical pack is active and restore it afterward.
