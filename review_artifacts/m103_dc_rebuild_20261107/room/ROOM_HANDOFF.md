# M103 room finish handoff

The private `m103_room_finish.gd` candidate adds tiled floor, blue-gray/off-white wall treatment, ceiling panels and fixture meshes, bench edge trim, three chairs, two storage cabinets and classroom signs. It adds no floor or wall collision, lights, device meshes, port targets, or gameplay state. The existing shell, east doorway, routes, worktop collision, cable obstacles, three bench transforms and save identities remain authoritative. It is mounted as a separate room content root. `campus_integration.gd.patch` stages the only shared integration edit: replace the two existing M103 finish calls with this M103-specific mount. It does not stack another finish over them. Main must check `integration_manifest.json` preimage hash before applying.

## Placement contract for model and binding owners

- Bench centers in world coordinates: `(-6,0,22)`, `(0,0,22)`, `(6,0,22)`. Each existing `dc_lab.gd` origin is yaw `PI` with local top spanning X ±2.4, local Z ±0.8, Y `.76` to `.88` (top `.88`). The world footprint of each is X center ±2.4 and Z `21.2..22.8`.
- Instruments should rest with their base at local Y `.88` and live within local X `[-2.28,2.28]`, Z `[-.68,.68]`, leaving reach to controls and ports. The front student approach is world Z decreasing, equivalent to bench local +Z. A front-port endpoint must be computed from the same device-parent transform as its visible socket and pick target.
- Room candidate trim is only at world Z `21.205` and `22.795`, world Y `.81`; it does not consume tabletop space. Chair centers are at each bench X and world Z `20.35`. Chair occupied bound: X center ±`.32`, Z `20.05..20.65`, Y `0..1.205`. The standing space from chair front to bench edge is `.55 m`. Cabinets occupy X `[-9.48,-8.22]`, Z `[14.69,15.31]` and `[16.79,17.41]`, Y `0..1.435`.
- M103 shell bounds stay X `[-10,10]`, Z `[13,25]`. The east entrance around X `10`, Z `19` remains untouched. The central and east approach aisles are clear. No furniture or collision is placed in the doorway.

## Source checks and deferred acceptance

`stage_integration.py` generated an exact-preimage patch without changing `scripts/campus_integration.gd`. Static coordinate checks find three independent existing bench origins and no overlap between room chairs/cabinets and worktops. Source checks do not establish in-game appearance, legibility, collision comfort, or gameplay. The runtime owner should capture the required M103 wide and close-up views and report any placement adjustment after safe engine access; the room owner can revise this candidate without touching production.
