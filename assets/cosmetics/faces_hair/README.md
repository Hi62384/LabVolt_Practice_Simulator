# Faces, hair, and facial hair collectibles

This directory contains an original, offline-authored quality slice for the
`avatar_collectibles_v1` contract. `catalog.json` is intentionally separate
from the shared catalog so the integration owner can merge it atomically.

Library: six complete face presets, seven different hairstyle silhouettes,
and six facial-hair choices. Bob, long waves, ponytail, and full beard use
separate baked length variants. The models are not assembled from primitives
at runtime. Every glTF supplies normals, UVs, named PBR material regions, and
128 px albedo/normal/ORM maps. Card artwork is a deterministic catalog image,
not a claim of an engine-rendered preview.

Rig assumptions: scenes use `Body/Head` local coordinates for the existing
`labvolt_toon_v1` head (about 0.24 m half-width, facial surface z 0.14–0.20 m).
The provider attaches beneath the animated head so idle/walk/seated head tracks
are inherited. Assets remain in `Body/Head` local coordinates and inherit the
full core `0.65–1.4` head-size and non-uniform head-shape transforms; there is no
stale fit clamp or inverse scaling. Legacy face/hair nodes are hidden with
reference-counted prior visibility and restored by `detach_from_avatar`.
No facial-animation blend-shape seam exists in the current procedural toon, so
facial hair follows the rigid animated head rather than unavailable mouth
deformation.

Cloud Curls and Braided Bun advertise `hair_volume_high`, matching the actual
headwear conflicts in the accessories catalog. Other hairstyles remain eligible
for hats. Length-capable items select separately baked geometry variants rather
than stretching a complete hairstyle or head.

Regenerate and validate offline:

```text
python tools/cosmetics/faces_hair/build_faces_hair_assets.py
python tools/cosmetics/faces_hair/validate_faces_hair_assets.py
```

Integration requires the shared renderer to call `FacesHairProvider.instantiate`
and `attach_to_avatar` for the `face`, `hair`, and `facial_hair` slots. The
provider hides matching legacy nodes only after a successful attachment. Runtime
acceptance still needs visual inspection at body/head limits once playtesting is
not active.
