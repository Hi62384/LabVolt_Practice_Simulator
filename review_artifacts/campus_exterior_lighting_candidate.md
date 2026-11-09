# Exterior lighting review candidate

The entrance geometry handoff fixes the portal plane at `z=-11.32` and the
clear opening at `x=10..16`. This adapter mounts two lights just outside the
portal uprights at `(9.72, 4.2, -11.32)` and `(16.28, 4.2, -11.32)`.
It adds no poles, frames, fixtures, signs, or collision. Verify the portal
upright dimensions after integration and confirm no other light already uses
these two mount points. Courtyard lights await actual fixture anchors.
Attach once at the persistent campus root with identity transform. Drive its
`set_time_of_day()` and `brightness_scale` with the existing lighting rig.
Two shadowless OmniLight3D nodes are the maximum; no reflection probes or fog.

Current `campus_world.gd` creates ordinary StandardMaterial3D materials with
roughness 0.9 and no emission assignment. Its paving uses the same shared
material helper. Preserve that nonemissive contract for revised facade and
pavement materials; do not make broad surfaces glow to imitate daylight.

Compare fixed entrance frontal, courtyard oblique, and inside-out entrance
views at 13:30 and 20:00 with the same graphics preset and camera exposure.
Assess pavement and wall clipping, local light pools, sky separation, fixture
alignment, and shadow depth. No visual acceptance is implied by this source.
