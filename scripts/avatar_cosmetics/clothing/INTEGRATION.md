# Clothing integration handoff

Merge `assets/cosmetics/clothing/catalog.json` items into the shared catalog. In the renderer, preload `clothing_provider.gd`; for resolved `top_inner`, `top_outer`, and `bottom` entries call `ClothingProvider.instantiate(definition, sanitized_parameters, body)` then `attach_to_avatar(avatar, garment)`. Keep both top slots so an inner tee can coexist with an outer open jacket/coat. Core conflict resolution already rejects symmetric tag conflicts.

After a successful top attachment, hide the legacy `Body/TailoredTop` and each legacy arm `Sleeve`; after a successful bottom attachment, hide each legacy leg `Trouser`. Do not hide skin forearms/hands. The provider duplicates every imported surface material before applying player colors.

The current shared renderer has only a footwear adapter. Runtime import, visual fit at body-slider extremes, motion/seat/crouch acceptance, and thumbnail replacement with renderer captures remain integration gates for the main owner once the user is no longer playing. No shared file was edited in this lane.

The provider consumes `AvatarCore.sanitize_body()` and preserves the authoritative 0.65–1.40 range. Torso vertices are deformed per row with the same `.87` waist to `1.24` shoulder smoothstep used by the toon rather than applying one averaged shell scale. The skirt waistband similarly interpolates its lower hip and upper waist envelopes. Sleeves use `arm_width`/`arm_length`; trouser panels use `leg_width`/`leg_length`; their baked positive joint overlap remains attached on the animated limb side of each joint. The legacy-only `body_depth` is not present in the v1 body dictionary, so this provider does not invent a replacement or silently alter it.
