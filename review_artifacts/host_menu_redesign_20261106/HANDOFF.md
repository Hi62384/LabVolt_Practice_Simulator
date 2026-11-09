# Host menu redesign handoff

## Shared design integration update

Current `scripts/front_menu.gd` SHA-256: `5F3CE5924F1091DEF9EE842AF6CDC2AAA96D5A218F69519768B0A22259800790`.

Consumes the published `scripts/ui/design_system/theme.gd:create()`, `tokens.gd:surface()`, and `widgets.gd:action()/text()/icon()` APIs. Main, host, join, pause, settings and course-browser menus inherit the shared theme, with icon actions, primary/danger emphasis, focus styles, 52px actions and wrapping labels. The original settings control is reused with its values and callbacks intact.

The menu panel follows viewport dimensions, all menu content scrolls, and course/track/difficulty rows stack below 760px panel width. Course results use separate lecture/lab cards and View Courses displays per-attempt marks with completion states. Host name/solo/port values persist across selector rebuilds; solo disables port editing. A single shared week ButtonGroup now covers both lecture and laboratory choices. Recent-list slicing includes up to four entries. Course grouping uses the query's actual subjects rather than a fixed two-group allowlist.

Static source review confirmed shared theme/action usage, one View Courses entry, the read-only guard, one authoritative Course launch intent, and one cross-track week selection group. Existing Join/Host/Resume callbacks remain. No engine, reload, CUA, or active save operation was performed; appearance, actual viewport behavior and engine parsing remain unverified. Earlier hashes below describe historical checkpoints.

## Scope

- Changed only `scripts/front_menu.gd`.
- Preserved the earlier top-level `Host Game` merge.
- Did not edit academic, session/network, avatar, profile, inventory, or character-customizer sources.

## Source identity

- Baseline SHA-256: `F1952AC4FC006429C98D50E280EA1462DBCFD3902F6CB8F23045315AB553562E`
- Hosting redesign checkpoint SHA-256: `26A9C895A5A2CF846B1A2B52DA5A98A10FBE6607306A60B3FAA3EF3E4BD103F8`
- Final hosting + View Courses SHA-256: `E30F57F667E2A0875C9D30A6575066ECE4E0473ED5F05BAE0EC3C02B93527492`

## Routing

- `Host Game` -> `network_page(false)` -> `_build_host_page()`.
- Freeplay -> existing solo/network setup -> `school.start("Freeplay", difficulty)` -> capture.
- Class -> campus adapter catalog/progression/week queries -> selected course/kind/week/difficulty -> existing solo/network setup -> `request_activity({mode:"Course", ...})` -> capture on success.
- `Courses & Map` still routes to `campus_page()`.
- `Back` routes to `home()`.
- `View Courses` -> `view_courses_page()` -> the same grouped/recent selector used by Class hosting, with hosting controls and launch callbacks suppressed.

## Academic boundary

The menu consumes the academic owner's `course_progression_adapter.menu_catalog()` projection for subject groups, recent attendance, course marks, weekly lecture/lab marks, and attendance state. It does not calculate grades or infer attendance. Activity launch continues through `campus_adapter.request_activity()`.

## Static checks

- One mutually exclusive `Freeplay`/`Class` pair.
- No top-level `Open Lab` mode.
- Class Start is disabled until course, lecture/lab kind, and week are selected.
- Separate lecture/laboratory panels are generated when laboratory weeks exist.
- Empty recent-course state is explicit.
- All interactive controls retain keyboard focus; selection controls use `ButtonGroup`.
- Hosting and Join Game networking calls remain present.
- One main-menu `View Courses` route exists; its read-only guard returns before difficulty, hosting, or Start controls are built.
- Weekly rows show the projected best mark or `Not completed`, plus authoritative attendance or `Attendance unavailable`.

## Verification limits

The supplied Library screenshot identifiers were not exposed through a readable Library tool on this executor. No screenshot details were inferred. Per instruction, Godot was not launched or reloaded, the running game was not touched, and no visual/runtime pass is claimed.
