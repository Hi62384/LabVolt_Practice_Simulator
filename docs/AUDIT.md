# Inspection and architecture

All eight supplied archive files were inspected before implementation: README, manual test cases, project configuration, entry scene, both scripts, and both reference photographs. The input ZIP was left unchanged. The reference photographs' cables were treated as examples, never initial wiring.

## Baseline findings

The base had a procedural rack with recognizable module positions, reusable geometry helpers, switch/terminal metadata, analog needle geometry, ideal-wire unions, complex nodal stamping, and useful RLC component values. These were retained where appropriate.

Its first-person player was a Node3D moved directly through geometry. Ray reach was 15 m. A two-click operation created an entire lead, with no inventory or end ownership. There was no multiplayer transport or authority. Meter voltage coils were infinite impedance. Tiny conductance to ground masked floating islands and singular behavior. Current shunts lost useful precision when their small voltage differences were represented at full supply common mode. Motor speed was an arbitrary formula independent of electrical torque. All verification was manual and explicitly unrun. Demo shortcuts automatically wired and energized circuits. Exam state and meaningful measurement grading were absent.

## Resulting modules

| File | Responsibility |
|---|---|
| equipment_builder.gd | Retained procedural equipment builder, reduced from the original monolith; data-driven load labels |
| equipment_catalog.gd | Common-variant load values and explicit assumed meter/protection parameters |
| ac_network.gd | Standalone linear RMS AC MNA, double-precision matrix, floating references, singular detection |
| circuit_solver.gd | Physical terminals/leads to equipment netlist, meter outputs, power and protection |
| induction_motor.gd | Documented approximate equivalent and steady torque equilibrium |
| lab_state.gd | Server-owned equipment, end locks, reach, edits, safety, seeded assignments and grading |
| session.gd | ENet lobby, authority RPCs, validated requests, snapshots, disconnect handling, poses and chat |
| first_person.gd | CharacterBody3D movement, capsule, camera, persistent control settings |
| cable_mesh.gd | Bounded analytic sag mesh |
| game.gd | Scene composition, physical interaction, audio, visual state, avatars and local records |
| lab_ui.gd | Menu/lobby/settings, compact HUD, clipboard and progression record |

The original monolith's unused menu/preset/gameplay methods were removed during extraction. Example shortcuts cannot reveal wiring in exams. All ordinary equipment changes flow through LabState, including local play. Only the authority runs the electrical solver in network play. Reliable snapshots are sent on equipment changes, rather than once per rendered frame. Player poses use a separate unreliable ordered channel at 20 Hz; avatar rendering interpolates them.

Network movement is bounded by elapsed time and room extents; interaction reach is checked against the last accepted pose. This is basic game validation, not a complete anti-cheat or collision-authoritative movement server. The host remains trusted. Actions are rate-limited; numeric inputs are finite and bounded. Switches carry their expected previous state. Cable endpoints have exclusive owners. Reset/experiment assignment are host-only. Snapshots and meter readings use authority-only RPCs.

## Deliberately unfinished

Exact photographed instrument tap mappings and impedances; full machine calibration; live DAQ/transformers; multiple functional stations; furniture-aware cable collision; transient/protective-earth behavior; voice/NAT traversal/discovery; separate troubleshooting campaign; advanced environment art, hand animation, cosmetic rewards and large multiplayer/performance soak testing. These are documented limitations, not hidden placeholder readings.
