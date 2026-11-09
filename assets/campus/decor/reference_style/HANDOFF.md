# Reference style candidate

The verified second reference image is a clean, restrained low-poly workshop:
pale grey walls, muted blue lower walls and floor, matte navy furniture, warm
wood worktops, organized parts/tool storage and simple rectangular ceiling
fixtures. `reference_style_finish.gd` applies only wall-fixed finish and fixture
meshes to M102, M103, M201, M202 and M203. It creates no lights, collision, text,
physics or saves. M101 is excluded to preserve its liked decoration.

Mount after `TeachingRoomFinish.mount_approved`, once per approved ID, through
`campus.register_content`. Do not mount the older generic `CampusDecor` for
those IDs. This is an optional private revision; main should choose it only
after inspecting it alongside the lighting owner's ceiling rig, avoiding
duplicate fixture meshes. M102 is the pictured room, but its shop and trading
functions remain allocated there; workshop/loadout/notes stay in dorms and
IC/PCB stays in the studio. The finish does not change those interactions,
avatars or UI.

The palette is a shared visual vocabulary for future providers, not an
automatic whole-game style change. Camera-angle visual acceptance remains
required after the active playtest ends.
