# Footwear quality slice

This additive slice contains six original, baked glTF footwear assets for the
`labvolt_toon_v1` rig. Toe direction is local +Z. Each model's origin matches a
single foot, and the provider places it at `(0, -0.74, 0.045)` beneath `LegL`
and `LegR`. The assets inherit all leg animation without skinning or rig edits.
The provider consumes `AvatarCore.BODY_MIN/BODY_MAX` (currently 0.65–1.40),
supports that complete range, and rejects out-of-contract values explicitly.
It compensates for the parent leg's Y scale so leg length changes placement but
do not vertically stretch shoe construction. Per-item `fit` scale/offset data
retains the small authored adjustments needed by different silhouettes.

The shared catalog is `catalog.json`. Models use named material regions and
reusable 128 px PBR textures (albedo, normal, glTF metallic-roughness; Ionstep
also has emission). Recoloring duplicates each imported surface material and
sets per-instance overrides, so equipped players never mutate shared assets.

Integration seam:

1. Merge the catalog's `items` through the shared AvatarCore catalog loader.
2. Call `FootwearProvider.instantiate(definition, parameters, body)`.
3. Call `FootwearProvider.attach_to_avatar(toon_root, pair)` after the toon is
   built; hide/remove the legacy children named `Sneaker` and `Sole` only when
   a v1 footwear item is successfully attached.
4. Preserve the empty returned pair as an equip handle or free it after attach.

This is an initial six-item quality slice, not the full footwear catalog.
Regenerate its authored source assets with
`python tools/cosmetics/footwear/build_footwear_assets.py`.
