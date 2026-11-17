# Gym source review and deferred checks

The M105 gym overhaul request covers exercise progress, equipment, spotting, rescue, multiplayer, and visual quality. The current source maps those requirements as follows:

| Requested behavior | Current production path | Status |
| --- | --- | --- |
| Muscle fatigue, delayed growth, recovery and persistent history | `gym_progress.gd`, `facility_host.gd`, `ledger_adapter.gd`, `profile_adapter.gd` | Implemented in source; focused fixtures passed |
| Adjustable benches, dumbbells, plates, bars, cables, belts, mats and room presentation | `gym_bench.gd`, `gym_weights.gd`, `gym_barbells.gd`, `gym_cable_machine.gd`, `facility_room.gd`, M105 presentation | Implemented in source; visual and interaction checks pending |
| Exercise rhythm, gradual fatigue and failure | `gym_lift_control.gd`, `facility_panel.gd`, `facility_host.gd` | Local exercise, failure and movement fixtures plus paired lift host/client passed; interactive feel still pending |
| Proactive spotting, strength-based rescue and nearby helper checks | `facility_host.gd` `spot`, `beat`, `assist`; `gym_barbells.gd` | Source guards strengthened; focused fixtures passed |
| Mouse escape, synchronized trapped bar and timed fallback | `facility_panel.gd` slider, `facility_host.gd` `wiggle` and `tick`, `gym_equipment_motion.gd` | Trapped bar, rescue animation, paired host/client rescue passed; interactive visual check pending |
| Disconnect and save failure | `facility_controller.gd`, `facility_host.gd` `clear_activity`, `pending_sets`, `_flush_pending` | Host releases the player and queues unsaved records per identity for ordered retry while the host is running. An unbound student must reconnect before the ledger adapter can save. A host process exiting while the profile store still refuses writes cannot durably retain that in-memory queue; the host warns on session finish. |

`test_gym_rescue_guards.gd` covers failed cancel commit and retry, weak prepared spotter, invalid helper position, ungrounded helper, replay, and two disconnected workout checkpoints retried under the same stable identity. It and the disconnect ledger, session checkpoint, history persistence, recovery display, proactive spotting, all-exercise failure and station, movement, rescue animation, trapped bar, animation handoff, and single-process network fixtures passed with isolated Godot user data on 2026-11-13. `test_lift_network.gd`, `test_spot_network.gd`, and `test_trapped_rescue_network.gd` passed in separate host and client processes with isolated user data. This verifies network state paths, not manual visual quality or real interactive two-player play. Pending sets remain in host memory if profile storage fails; host exit before recovery can lose them.
