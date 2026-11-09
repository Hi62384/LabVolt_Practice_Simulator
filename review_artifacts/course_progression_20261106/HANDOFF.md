# Per-course progression handoff

Applied academic/provider/UI work is additive. `course_progression.gd` derives attempts from immutable records, requires all lecture and lab slots before issuing a final, treats 50% as pass, keeps the highest completed final, excludes lesson/practice/linked-practice records, and keeps course/profile data isolated. `course_progression_adapter.gd` is the narrow shared-session boundary for summary projection and record metadata.

The weights in `assets/campus/courses/grade_weights.json` are deliberately editable and labeled proposed. Each final lecture/lab week is an exam. The example 20% exam weight is used per exam; remaining percentages are visible proposed distribution and total 100% per course. Running mark divides by completed weight. Earned-to-date and final divide by full course weight.

The patch beside this file is for the main integrator because `school_session.gd` owns shared save/network/reward wiring. It must be applied only at a safe boundary after the active play session. It also calls out the existing replay-payment defect: `_receive_grade` currently calls `_apply_reward` even for a known record. The authoritative/persisted ledger remains the correct exactly-once boundary.

Eight-player packet expectation changes (packet intentionally untouched): course summaries must assert `final_mark`, `passed`, completed attempts, and current attempt rather than `overall`; fixtures must include every required slot to expect a final; last lecture and lab weeks must be marked exams; replay must not duplicate payout.

## Stable menu query API

Call `CourseProgressionAdapter.menu_catalog(gradebook, profile, course_bridge, attendance_events)` and consume schema `academic-menu.v1`. It returns exact course IDs, `display_name`, `subject_group`, grouped IDs, authoritative `recent_attendance`, separate timestamp-based `recent_activity`, course `mark` (`running`, `earned_to_date`, best completed `final`, pass/status), and separate lecture/lab tracks. Every week includes exam/type/weight metadata, completion state, attempt count, best score, and an unflattened `marks` array containing attempt number, whether that course attempt is complete, score, stored time, assessment ID and reason.

Attendance is deliberately independent of marks. A supplied authoritative attendance event produces `attended` or explicit `not_attended`; without a matching event the week is `unavailable`. `recent_attendance` never uses grade timestamps. `recent_activity` is the valid fallback for stored marked-work timestamps. Missing/invalid timestamps are not ordered or promoted as recent.

Legacy records without `course_attempt` are deterministically partitioned by valid timestamp and stable record ID into the earliest open attempt missing that slot. New authoritative records may provide a positive `course_attempt` for unambiguous interleaving. Duplicate immutable delivery is deduplicated by `assessment_id` (falling back to record ID). This projection does not mutate grade history.

## Attendance integration

`attendance_ledger.gd` defines immutable schema v1 and the authoritative recorder. Main should persist a separate private `user://student_attendance.json` projection and host archive; it must not place attendance in the gradebook, reward ledger, or public profile. Event IDs are `attendance:<session_id>:<profile>:<course_id>:<kind>:<week>`, so reconnect/replay of the same class join is idempotent. A new session can record a new attendance fact without creating or advancing a course attempt.

At the authoritative point where a selected Class activity admits a profile to its course/track/week, call `Attendance.record_authoritative(attendance_archive, multiplayer.is_server(), assessment_id, profile, course_id, kind, week, Time.get_datetime_string_from_system(), course_ids())`. Save only when `created` is true, then send that profile's event through a reliable authority RPC. The receiving client stores by immutable event ID without rewards. Feed `Attendance.private_for_profile(local_attendance, local_identity)` to `menu_catalog`. Old profiles remain `unavailable`; future real joins populate recent attendance.
