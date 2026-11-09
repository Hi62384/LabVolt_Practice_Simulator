# HUD and settings source handoff — 2026-11-06

Owned existing files are ready for integration review; no ownership of shared game/front-menu/electronics/network/profile/ledger/session/world source was taken. No shared-file hook is required. The existing front_menu settings-body reparent still works; its empty legacy tab wrapper is removed on reparent, and settings carries its local theme.

## Implemented surfaces

- `scripts/lab_ui.gd`: centered viewport-sized pause/session/clipboard windows; scrollable icon tabs; connection fields, roster cards, host experiment card, seed and modes grouped together; icon actions; personal record summary and recent-submission cards; labeled V RMS/A RMS/W entries; keyboard binding rows retain their original capture callback. Objective, prompt and log labels remain compatible with game.gd's direct text/visibility assignments, with icon readouts and legible shadow. Log feedback is at the right to avoid the bottom-left chat. The crosshair remains a small center dot.
- `scripts/lab_chat.gd`: shared card chrome, team-channel badge, separately sized message region, viewport fitting and labeled input. Plain-text message rendering, 40-message bound, expiry, bubbles, submission and capture behavior remain intact.
- `scripts/campus/ui/campus_hud.gd`: compact icon badges in a wrapping flow within the existing HBox root type. Empty timer/navigation badges disappear. The full `Signage.room_hud_identity(room)` value remains intact and wraps; there is no room-number/name truncation. No polling was added.
- `scripts/campus/ui/profile_inspector.gd`: scrollable public player card, section cards, empty/private state and close actions. The original `safe.FIELDS`/`safe.project` projection remains the only rendering source. No private save or gradebook is read.
- `scripts/campus/ui/profile_visibility.gd`: lock card, accessible-height sharing toggles and saved/error feedback; existing visibility defaults and ConfigFile paths/sections/keys remain intact.
- `scripts/campus/ui/graphics_settings.gd`: presets, image-quality and world-detail groups, labeled selectors with units and retained crowd availability state. All non-build methods, defaults, apply logic, resource behavior and save behavior are byte-for-byte equivalent after newline normalization.
- `scripts/campus/facilities/facility_panel.gd`: context-local service header, counter-item cards, icon actions, scrollable body and immediate pending-action lock/status. All original service operations, station/item payloads, sequence generation and host response/recovery behavior remain intact. Purchase button prefixes remain compatible with the existing facility test helper.
- `scripts/campus/performance/profiling_overlay.gd`: legible shared card styling only; its original hidden guard and half-second sampling cadence remain intact.

`layout.gd` composes the published design-system cards/fields/badges; `readout.gd` is a Label-compatible icon affordance. Neither introduces tokens, icons, a theme or alternate gameplay state.

## Evidence and reversibility

- `manifest.json`: exact SHA-256 before/after for all eight existing files and exact binary preimage locations.
- `offline_validation.json`: bounded source invariants, balanced delimiters/strings and resource existence checks. Run `python tests/ui/hud_settings/audit.py` to repeat against the manifest.
- `python tests/ui/hud_settings/rollback.py` verifies reversible state without writing; `--apply` restores only these eight exact preimages and refuses unknown concurrent edits. It leaves additive helper files alone.
- The migration/refinement scripts are historical preimage-bound authoring evidence, not startup hooks. Do not rerun them on integrated source.

## Pending safe-boundary acceptance

No Godot/editor/server, runtime/render, CUA, reload/restart, input/focus control or active-save mutation occurred. No package was installed. An offline GDScript parser was unavailable, so delimiter/resource checks must not be described as engine parsing.

At the next user-approved safe boundary, run the project parse checks and relevant campus UI/facility/menu tests in isolated user data. Check keyboard focus through scrolled settings, front-menu reparenting, clipboard drafts across close/reopen, all roster and host callbacks, a delayed facility request followed by response, privacy revocation, and direct-IP error feedback. Inspect screenshots at the desktop viewport plus a smaller window for long room names, expanded telemetry, chat/log placement and card overflow. Engine/runtime/visual/multiplayer acceptance remains pending, not passed.

Known integration caution: the settings controls are intentionally the same persistent nodes reparented by front_menu; do not replace them with a second settings build, since that would fork draft/input state and duplicate signal connections. The root themes are local; no project/global theme was changed.

## Parser correction

The isolated parser log reported native-class shadowing of `Skin` in five owned files. All eight owned files now use `HudTheme` for that shared theme alias, including three imports not independently reported because of cascade. The source audit was updated; an engine rerun is still pending the safe boundary.
