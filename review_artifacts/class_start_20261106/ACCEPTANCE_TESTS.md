# Focused headless acceptance suites

Run only after the shared runtime owner finishes clean import/parse and its safety gates. These entry points use the existing `extends SceneTree` test convention:

```powershell
godot --headless --path . --script res://scripts/campus/academics/class_start/test_applied_lifecycle.gd
godot --headless --path . --script res://scripts/campus/academics/class_start/test_course_marks.gd
```

Both return exit code 0 on success and 1 on assertion failure. Expected final markers are `CLASS_APPLIED checks=... failures=0` and `CLASS_MARKS checks=... failures=0`. Failure assertions print `FAIL CLASS_APPLIED:` or `FAIL CLASS_MARKS:`. They have no network sockets or input automation, instantiate no Main scene, and write no `user://` data. The lifecycle fixture is an explicitly mocked local host transport with an empty activity so `checkpoint()` returns before saving. Resource needs are expected to be small relative to a full scene load; exact memory/time have not been measured.

`test_applied_lifecycle.gd` uses the production `SchoolSession`, `ClassStartClock`, and `AttendanceLedger`. It checks the 119999/120000 ms boundary, early and late authenticated arrivals, reconnect identity, no deadline reset, restoration of remaining time, automatic host phase transition with zero participants while the menu is open, no instructor click transition, one assigned sheet on lesson completion, repeat advance and reconnect idempotency, Freeplay, class-phase host chooser rules, action rejection, and attendance event idempotency. The mocked peer IDs and roster establish source behavior only; they do not prove actual RPC delivery or network ordering.

`test_course_marks.gd` uses the production `CourseProgression`, `CourseProgressionAdapter`, and `AttendanceLedger` with synthetic records. It checks weighted running and earned-to-date marks, incomplete final status, both final exam slots, exact 50% pass, highest completed retake, repeated assessment ID, lesson exclusion, and the absence of an invented grade penalty from a late flag. It does not depend on live student records.

Runtime correction receipt: the first guarded parse found `multiplayer` was not in `SceneTree` scope in the lifecycle fixture. The assertion now uses `game.get_multiplayer().is_server()` on the explicit fixture node. Updated SHA-256: `97756146E7E9864E9AF478198E17294CCF169DB27BF62AD36112D4C904DA29DF`. No other fixture edits were made in this correction. The runtime owner should repin this exact hash before rerunning.

Second runtime receipt: all 33 lifecycle assertions passed, but Godot reported ObjectDB instances leaked at exit. The fixture created `MockSession` as a Node property without adding it to the tree, and exited with its `MockGame` tree still alive. The fixture now parents `MockSession`, queues `MockGame` for deletion, and waits two frames before exit. Current SHA-256: `7EA737CEF8DA41FD5C8C8718FF98E0038A8108DADE288329791BDE3A93EC1EF9`. This targets only fixture-owned nodes. The runtime owner should repin and rerun; no claim of leak-free execution is made yet.

Still required from the guarded runtime owner: import/parse with warnings-as-errors; the two suites above; real host/client joins before and after cutoff, reconnect delivery and snapshot timing, host menu pause, recovery from an isolated `user://` directory, actual instructor/settings visual checks, stale menu callback across a session transition, and an official submission with late attendance. These synthetic tests must not be described as proving real multiplayer, live persistence, or visual behavior.
