# Gym acceptance evidence

The original requirements are in the gym overhaul request, section 22. These
checks describe the coverage actually exercised, not a claim that every visual
combination has been inspected.

- Progression, muscle isolation, recovery, impossible loads and finite failure:
  `test_gym_progress.gd`, `test_all_exercise_failure.gd`.
- All configured station/exercise pairings and target mappings:
  `test_all_exercise_stations.gd`, `test_exercise_definitions.gd`.
- Minigame effort, impossible lifts, trapped bar, helper and solo escape:
  `test_gym_movement_ui.gd`, `test_trapped_bar.gd`, `test_rescue_animation.gd`.
- Equipment, plates, belts, carried load and bench grip tracking:
  `test_barbell_plates.gd`, `test_weight_belt.gd`, `test_carry_load_integration.gd`,
  `test_adjustable_bench.gd`.
- Clothing and body mesh deformation, saved sets and interrupted sessions:
  `test_muscle_visual.gd`, `test_gym_exported_avatar.gd`,
  `test_gym_history_persistence.gd`, `test_gym_session_checkpoint.gd`,
  `test_gym_disconnect_ledger.gd`. `visual_muscle_clothing.gd` was inspected
  for the built-in Tee and Hoodie at maximum growth in the raised curl pose;
  no obvious clothing clipping was visible from its front three-quarter view.
- Room and station construction: `test_source.gd`. `visual_campus_gym.gd`
  entered the assembled campus gym, captured three viewpoints, verified the
  central aisle with a horizontal collision ray, and checked rack collision.
  This is not an exhaustive physical walk of every route. Rendered exercise
  endpoints and exact coverage are in `VISUAL_ENDPOINT_AUDIT.md`.
- `test_lift_network.gd`, `test_spot_network.gd`,
  `test_trapped_rescue_network.gd`, and `test_gear_network.gd` each passed on
  both host and client with isolated data on the current build.
- `visual_exported_gym_avatar.gd` exported a customized fitted tee, applied
  maximum muscle sizes and rendered a raised curl pose from front and rear;
  no obvious clipping was visible in those views.

Gym acceptance is complete within the stated test and visual coverage. Lighting
and performance tuning are deferred per the user's later instruction. The
stylized overhead-extension grip limitation is documented in the endpoint audit.
