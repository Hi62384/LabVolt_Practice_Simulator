# Incomplete body deformation lane — 2026-11-06

Historical checkpoint: superseded by HANDOFF.md and the completed offline tests.

Paused at an atomic-write boundary in response to the coordinator's forwarded
latest user model-cap instruction. This is NOT a completion or acceptance report.

## Written (only exclusive lane)

- `scripts/avatar_cosmetics/body_deformation/body_fit.gd`
- `scripts/avatar_cosmetics/body_deformation/mesh_warp.gd`
- `scripts/avatar_cosmetics/body_deformation/mesh_envelope.gd`
- `scripts/avatar_cosmetics/body_deformation/rig_adapter.gd`

No shared source changed. No engine, server, CUA, reload, active save, network,
or game control operations performed. Python was used only for a bounded read
of baked clothing glTF node/accessor bounds. Repository has no `.git` here.
No applicable AGENTS.md found in workspace or checked ancestors.

## Actual inspected contract and gap

`core/avatar_core.gd` keeps all numeric body fields at 0.65..1.4 and build as
slim/average/heavy/muscular. `core/avatar_renderer.gd` maps only the older subset
to Toon.build(legacy), dropping neck_length/width, torso_length/width, hips,
arm_width, leg_width, and named build. `toon_character.gd` is a segmented rig
with animated Body/Head, Body/ArmL/R, LegL/R, and AnimationPlayer quaternion
tracks. Arm and leg parents already scale Y for length. Current clothing
provider ALSO scales child sleeves/pants Y by length (double application).
Current accessory provider guesses torso and neck fitting separately.
Footwear cancels Leg Y and must retain that behavior. Faces/hair inherit Head.

## Intended seam (NOT YET PATCHED)

1. Toon preloads RigAdapter; build(raw, modern_body:Dictionary={}) calls
   RigAdapter.apply(root,modern_body,c) after _glasses and before _animations.
   Empty dictionary deliberately retains historical direct Toon builds.
2. Renderer calls Toon.build(legacy,body), then passes a copied
   BodyFit.provider_context(body,Toon.sanitize(legacy)) to providers (private
   legacy depth/outfit context, never persisted). Renderer calls
   RigAdapter.finish(avatar) after equipment so actual visible mesh envelopes
   govern rest splay; rotation keys are rebased from their old rest quaternion.
3. Clothing owner replaces _apply_fit body with BodyFit.fit_clothing(...).
   Accessory owner replaces _apply_fit body with BodyFit.fit_accessory(...).
   Existing provider interfaces remain. No provider edits performed yet.
4. Toon.save_glb should accept an optional modern_body arg and build with the
   same adapter. Renderer preview and modern export need explicit acceptance.

## Design currently in draft source

Torso length anchors at hip Y .86. Hip factor moves leg pivots, new per-instance
mesh deformation applies thickness, head translation follows neck/torso length.
Named builds multiply chest/hips/arm/leg/depth with documented constants in
body_fit.gd, average all 1. Arm/Leg scale semantics and node paths unchanged.
Actual mesh projected triangle edges drive conservative XY shoulder clearance,
including visible attached sleeves. No previous guessed torso-radius query.
Warp preserves UVs, surface materials/overrides, uses inverse transpose normals
and regenerates tangents. New pants bridge only for changed hip/leg envelope.

## Required before claiming functional implementation

- Review GDScript syntax/types; NO parser or GDScript execution occurred.
- Exact-envelope algorithm is unbenchmarked and potentially expensive: pairwise
  projected-edge clearance repeated for angle search. Optimize/bound offline.
  Remove unused `ys` accumulation in mesh_envelope.clears.
- Review shoulder connection zone (.115*arm_length), all mixed extremes, and
  visual suitability of potentially near-horizontal arms. These are unproven.
- Review conditional pelvis bridge shape/material and exact torso/hip/leg joins.
- Review clothing Waist/skirt mapping with torso_length: mapping currently uses
  torso_y below hip and can move waistband lower edge away from leg panels.
- Review garment fit <1.0: current multiplier can shrink .263/.255 shell below
  skin at fit .94. Need actual envelope clearance floor, not range narrowing.
- Review neck/back accessory maps against actual authored geometry, including
  user scale and unchanged head inheritance; hands slot provider support is a
  pre-existing separate seam, not addressed here.
- Stage minimal exact preimage-bound shared hooks and category-owner patches;
  capture hashes and snapshots before producing patches, fail on source drift.
- Add source/data offline tests under tests/avatar_cosmetics/body_deformation/:
  defaults/legacy parity, each control, named builds, mixed extrema, rest and
  animation origins, garment joins, preview/export adapter consistency.
- Add a Godot runtime acceptance script for later, but DO NOT RUN while playing.
- Produce accurate test report and completed handoff. No tests written/run yet.

Do not treat offline math/bounds as visual, parser, animation, export, or network
acceptance. Do not apply shared/provider patches concurrently with their owners.
