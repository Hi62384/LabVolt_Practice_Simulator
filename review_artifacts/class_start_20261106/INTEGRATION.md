# Automatic class start: shared-file integration

Source delivered: `res://scripts/campus/academics/class_start/class_start_clock.gd` and its boundary test. This helper is host state only. No live shared file was edited while the game was running.

Preimage SHA-256 (recheck before applying):

| File | SHA-256 |
| --- | --- |
| `scripts/school_session.gd` | `064ABA93CEE14F121912D1CB25C7E104438638F743679E129E31614A757CBE51` |
| `scripts/paper_ui.gd` | `9AEB9F9E2973522BBF74614B3A305654E90205BB7B54E8B0EB8A0C82EC67874C` |
| `scripts/school_world.gd` | `73FB12041BBA8AE3951540B45499016E022AC7D9ABBA3370F74BA66B972CE3CB` |
| `scripts/campus/academics/attendance_ledger.gd` | `F502EFAB925F30DBD4CC8116D679AD12C692A936CBA5083785F9527058EC7F3E` |
| `scripts/front_menu.gd` | `5F3CE5924F1091DEF9EE842AF6CDC2AAA96D5A218F69519768B0A22259800790` |
| `scripts/campus/ui/campus_adapter.gd` | `75A130710A3C36574CFA85716E6978849D0392BF3EB00FC5D18ADD8CC60DE1BF` |

## `school_session.gd` call-site changes for main integrator

1. Preload `ClassStartClock` next to `Attendance`; add `var class_start = ClassStartClock.new()`. In `_reset_session()` and `start()` call `class_start.cancel()`. In `start_activity`, cancel any prior countdown only after validation and capability checks have succeeded, before changing the round. For `selected == "Course"`, after `assessment_id` and `class_students` are established, arm with `class_start.arm(assessment_id, Time.get_ticks_usec())`, then call `class_start.arrive(token, Time.get_ticks_usec())` for each authenticated participant already present. Do this immediately before `activity_started.emit(...)` so spawning latency consumes the two-minute window. Keep Freeplay and Open Lab unarmed.

2. In `_identify`, after a new authenticated token enters `class_students` in the `travel`/`lesson` branch, call `class_start.arrive(token, Time.get_ticks_usec())`. For a returning token already in `class_students`, call the same method; its stored first arrival stays unchanged. Avoid using peer ID as the attendance key. A new arrival at exactly the deadline is late even if `_process` has not advanced yet. A join during `lesson` remains a class participant; a join during `assignment` retains its existing ungraded practice behavior.

3. In the host `_process`, before `advance(delta)`, when `phase == "travel"`, set `remaining = class_start.remaining(Time.get_ticks_usec())`; when `class_start.begin_if_due(Time.get_ticks_usec())`, set `phase = "lesson"`, `remaining = teaching_seconds`, record attendance for every enrolled authenticated profile (including disconnected profiles), broadcast and checkpoint once. Do not impose room, seat, or participant-count gates. The clock must be checked only by the server. The existing `advance` lesson/assessment transitions stay intact. Paused menus must not pause the host deadline; if `_process` is gated by `game.front.in_game`, put this deadline check ahead of that gate or in a separate host callback that continues while the menu is open. Handle `advance(0)` or equivalent on the first frame after returning.

4. Remove the `begin_lesson` request branch from `apply`. Retain instructor interaction for assignment, help, replacement, and activity selection. Remove or repurpose `begin_lesson()` so no click can start early. Do not call its current room/seated check. The instruction in `_give_slip` should say teaching begins automatically after two minutes.

5. Keep the authoritative `class_start` object off RPC payloads. In `_public_state` include `class_start.remaining(Time.get_ticks_usec())` as `start_remaining` and `class_start.started` as `start_started` for the current `assessment_id`, or use the existing `remaining` field while in travel. `_snapshot` and `_motion` only display host-supplied remaining time; clients never calculate or transition from a local timer. Snapshots sent to late joiners show `phase == "lesson"` and lesson time already elapsed, and must not reset the countdown.

6. `checkpoint` should persist the travel countdown's remaining seconds and an absolute wall-clock recovery cap (`_academic_now() + class_start.remaining(Time.get_ticks_usec())`), not the monotonic ticks which do not survive process restart. On recovery, clamp saved remaining by wall-clock elapsed time, arm a fresh monotonic clock with that *remaining* duration (add a `restore(id, remaining_seconds, now_usec)` helper if necessary), then immediately start the lesson when the cap is expired. Never grant another 120 seconds. For a recovered class, restore first arrivals by authenticated identity and their late flags from the journal. Do not infer late from a reconnect after host downtime. An intentional new class uses a fresh `assessment_id`, which resets the clock and arrivals.

7. `attendance_ledger.gd` is owned by the academic agent. Coordinate a `late` or `arrival_status` field on the event created for this session. At lesson start, pass the clock's stored status by authenticated token. Preserve the existing event ID and idempotency, and return the historical event unchanged on duplicate recording. A student who arrived before the deadline stays on time after reconnect. A student who first arrives after it is late. Do not alter grade scores, rewards, or pass thresholds. The course progression adapter must preserve unknown historical attendance as `unavailable`.

8. `paper_ui.gd`: remove the host-only `Begin teaching when everyone is ready` button at line 138. Keep the teacher menu. `school_world.gd`: replace line 89 text with `Find your assigned room. Teaching begins automatically when the two-minute countdown ends; arrivals afterward are late.` Keep the visible timer in travel. These files are main/other-owner shared files; no edits are made here.

## Instructor menu correction (added after user review)

The current `paper_ui.gd:teacher()` always builds a course `OptionButton`, week `OptionButton`, difficulty `OptionButton`, then `Take assignment`, `Random assignment`, and `Take lesson` buttons *before* checking `school.mode == "Class"`. This is the crowded, misleading scheduled-class UI. `school_session.gd:apply()` also accepts `op == "new"` in Class, so simply hiding buttons is insufficient.

Main's exact call-site changes:

- In `teacher()`, make a first branch for `school.mode == "Class"`. Display a compact header with `school.activity.course_id`, `school.activity.week`, `school.activity.kind`, current `school.phase`, and the host-supplied `school.remaining`. During travel show the automatic countdown and room from `school.activity.room`; during lesson show the current teaching stage and time; during assignment show the assigned paper and assessment time. Show `Replace missing Class sheet` only when the phase is `assignment` and the player has no assigned copy. Keep `Equipment guide` as help if useful, and retain held-paper Read/Submit plus Back. Remove the host `Choose next campus activity` button from this menu entirely. Do not build the selector row or any `Take assignment`, `Random assignment`, or `Take lesson` buttons in this branch.
- Put the existing selector row and practice buttons in an `else` branch for Freeplay/Creative Freeplay/Open Lab. Preserve those practice flows. This avoids changing the host's separate campus activity setup, where the host initially chooses a class.
- In `school_session.gd:apply`, start the `op == "new"` branch with `if mode == "Class" and not activity.is_empty(): return` (optionally `_notice(peer,"Your class work is assigned automatically.")`). Apply this before generating, allocating, or giving any paper. Class copies must continue to come only from the lifecycle transition in `advance()` and the existing reconnect/replacement paths. This protects against hand-crafted client requests as well as the UI.
- The `begin_lesson` RPC branch must also be removed or ignored as described above. During the travel phase, no instructor interaction can advance the class ahead of the deadline.

Suggested source-level acceptance: inspect `teacher()` in Class mode for zero selector widgets and zero `op:"new"` callbacks; send a forged `new` request as an enrolled client and confirm paper count and grade state do not change; verify Freeplay practice still generates a worksheet; verify assignment transition supplies exactly the existing class copy for each enrolled authenticated identity. Run with Godot only after the user finishes playing.

## Host settings ownership of the activity chooser

Current sources: `paper_ui.gd:teacher()` line 144 exposes `Choose next campus activity` from the instructor; `paper_ui.gd:activity_menu()` lines 481–516 builds the chooser; `front_menu.gd:settings_page()` lines 428–432 only hosts general settings. `school_session.gd:apply()` lines 250–254 accepts `op == "activity"` from peer 1; `start_activity()` line 689 currently checks `formal_active()`, which can be false in an empty travel state and does not encode the requested completed-class rule. `front_menu.gd:_start_host_selection()` is the initial pre-game host setup and must continue working.

Main's exact shared integration:

1. Delete `Choose next campus activity` from `paper_ui.gd:teacher()`. Remove `paper_ui.gd:activity_menu()` after moving its chooser controls to a host-only settings subpage in `front_menu.gd`. At `settings_page()` add a `Choose next campus activity` button only when `in_game`, `multiplayer.is_server()`, and the authoritative session says activity changes are allowed. Callback rechecks immediately before showing the chooser; the Start callback rechecks before `school.start_activity(config)`. Keep the ordinary `Settings` button and all other settings available to clients.
2. In `school_session.gd`, add an authoritative predicate equivalent to `func can_choose_next_activity() -> bool: return multiplayer.is_server() and ((mode in ["Freeplay","Creative Freeplay"] and phase == "freeplay") or (mode == "Class" and phase == "complete"))`. If the codebase has a distinct completed/cancelled state, accept a truly completed cancellation only after that state transition has committed; never infer completion from `class_students.is_empty()`, a menu flag, or a client payload. For Open Lab, decide explicitly whether its ended state should count as freeplay; do not allow an active practice activity to satisfy the predicate accidentally.
3. At receipt of `op == "activity"`, require `peer == 1` **and** `can_choose_next_activity()` before using `a.config`; reject otherwise. Also call the predicate in `start_activity()` itself, because the settings chooser and `campus_adapter.request_activity()` invoke it directly. Initial pre-game `front_menu.gd:_start_host_selection()` calls `start_activity()` from host setup: retain this path by checking a trusted `not game.front.in_game` initial setup condition separately. Do not take an `is_host`, `completed`, `phase`, or session identifier from request payload as proof. Recheck after every await/deferred callback because a menu opened in Freeplay could remain stale after a class starts.
4. Show the settings button in Freeplay or after the current class reaches `complete`. Hide or disable it throughout `travel`, `lesson`, `assignment`, and any unfinished break; the server-side guard enforces the same rule. A delayed request from an old session must fail if the current session is active, even if its payload was created when the chooser was available. If the target session has already ended and a newer eligible session exists, bind the chooser callback to the captured `assessment_id` or round and require it still matches before submission, so stale UI cannot change that newer session.

Acceptance: host settings in Freeplay exposes the chooser; client settings never does; host settings during countdown, lesson, and assessment does not; host settings after actual completion does. Instructor UI never exposes it. Forged client, stale host request, and direct adapter call during an active class all fail without changing mode, phase, assessment identity, papers, or grades. The host's initial class selection from the main menu still succeeds.

## Acceptance checks after integration, outside active play

- Start Class: one 120-second host deadline starts at successful activity creation. At 119.999999 seconds, travel; at 120.000000, lesson; repeated start cannot extend it.
- Host and client before cutoff are on time. First arrival at or after cutoff is late and sees an already-running lesson. Reconnect preserves original status and paper/session identity.
- Zero participants still begins. Menu pause does not defer it. Freeplay and Open Lab have no countdown.
- Cancel/new class and host recovery do not reuse stale ticks or duplicate attendance. The existing lesson-to-assignment deadline and grade progression remain unchanged.

The isolated helper boundary test is `res://scripts/campus/academics/class_start/test_class_start_clock.gd`; defer its Godot run until the user stops playing.
