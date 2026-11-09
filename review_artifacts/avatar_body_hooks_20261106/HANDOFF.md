# Body hooks — source gate complete, engine acceptance deferred

The four adapter sources and four review-only patches are ready for the main
integrator's source review. No shared/provider file was edited. Applying patches
is exclusively the corresponding owner's job. All four patches are required:
mixing the new rig with the old clothing fit double-scales garment lengths.
Verify `PREIMAGES.json` SHA-256 values before applying; source drift invalidates
the relevant patch. `stage.py` generates artifacts only, never applies them.

## Behavior

Neck length/thickness deform the neck and translate the head; torso length
anchors at the hip; torso width and hips deform distinct ring envelopes; hip
width moves leg pivots; arm/leg thickness change meshes without altering parent
length scales. A conditional pants bridge joins displaced leg roots to the hem.
Head-local face/hair/hat fit and the existing footwear Y cancellation survive.
Legacy body depth remains in a private provider-context copy, never saved.
Shoulder clearance uses actual deformed mesh triangle projections, with an exact
convex envelope of the arm endpoints (conservative across concavities and Z).
It retains the torso's concave waist. The joint overlap allowance derives from
actual sleeve thickness, rather than an assumed radius. Final fitted sleeves
trigger rest-quaternion rebasing of the existing animation tracks.

Named build multipliers (chest, hips, arm thickness, leg thickness, depth):

| Build | Chest | Hips | Arms | Legs | Depth |
|---|---:|---:|---:|---:|---:|
| average | 1 | 1 | 1 | 1 | 1 |
| slim | .88 | .92 | .86 | .90 | .92 |
| heavy | 1.16 | 1.18 | 1.14 | 1.18 | 1.18 |
| muscular | 1.20 | 1.04 | 1.24 | 1.14 | 1.10 |

Multipliers combine with legitimate .65..1.4 saved sliders. Products are not
clamped back to that range. Direct legacy Toon.build(raw) bypasses the adapter.
Modern average with all seven new numeric fields at 1 preserves the existing
legacy geometry and pivots, including old head behavior. Equipped garments can
still require improved rest splay. Once new proportions are used, head placement
anchors its lower tip to the extended neck. No movement/collider/network/save
code is changed. The renderer patch adds save_glb(state,catalog,path) using the
same render_avatar function as preview, including equipped items. Its actual
GLTF conversion and caller adoption remain engine/integration acceptance.

## Checks performed

- `python tests/avatar_cosmetics/body_deformation/test_source.py`: four tests.
- `python tests/avatar_cosmetics/body_deformation/test_math.py`: four tests.
- Math tests translate a restricted subset of the actual adapter functions into
  Python; this is deliberately not presented as GDScript execution or parsing.
- 8,192 mixed extrema/build cases: monotone torso rows, exact shoulder ring/pivot
  match, neck/head anchor math, positive limb factors, wrist length cancellation.
- 4,800 sampled authored garment vertices across actual glTF buffers: finite
  mapped coordinates and conservative radial clearance at the smallest fit.
  This is vertex sampling, not proof that every garment triangle clears skin.
- 64 sleeve-envelope rest solves, 844 clearance queries; the sampled lab-coat
  sleeve projected hull has four edges. Latest offline solver fixture took
  about .25 seconds total on this machine. This is not a GDScript performance
  measurement and excludes resource import/mesh warping.
- Source checks confirm legacy bypass, unchanged parent length semantics,
  apply-before-animation ordering, quaternion rest rebase, shared render/export
  entry, no per-frame adapter callbacks, and unchanged shared preimage hashes.

Envelope collection runs only during avatar construction/final equipment fit,
never each animation frame. Arm hull reduction is performed once per arm solve;
angle search is bounded to one initial test, seven trials, ten bisections.

## Corrections made during offline review

Removed unused clearance work; reduced arm triangle-edge comparisons to its
conservative convex envelope; fixed lab-coat lower ring interpolation; anchored
below-hip garment coordinates; prevented negative garment ease pulling sampled
torso vertices inside the body; fixed thick/short-arm shoulder allowance; added
neutral bypass for legacy parity and shared renderer export entry.

## Still required after user ends play

Godot parser/import acceptance for all source and staged hooks; execute the
provided deferred runtime smoke test; visual acceptance of all controls alone
and mixed extremes, including pants bridge, skirt seams, coat hems, sleeves,
neck/back/wrist accessories, face/hair/footwear, walk/run/seated/crouch; actual
export round trip and preview agreement; existing network/save/movement tests.
Near-horizontal arms may occur at extreme width/length mixes and require visual
judgment. Offline bounds do not establish attractive visuals or animation fit.
No engine/server/CUA/focus/reload/save mutation was used in this lane.

Source gate: READY FOR OWNER REVIEW. Runtime/visual/export/network acceptance:
UNREADY until those deferred checks pass. IN_PROGRESS.md is historical and is
superseded by this handoff.
