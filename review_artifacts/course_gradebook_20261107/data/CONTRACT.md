# Read-only gradebook projection

`GradebookView.build(records, profile, course_id, tracks, weight_config, pending_records)` returns a
dictionary without changing its inputs or writing files. `records` is the saved
gradebook dictionary; only official, numeric records matching both profile and
course participate. Practice and lesson records are excluded. An official zero
is a graded result.

`tracks` maps `lecture` and `lab` to the provider's complete week arrays. The
existing weight configuration maps each track to an array of weekly weights.
An optional `assessments` array contains explicit extra assessment definitions:
`id`, `kind`, `title`, `weight`, and optional `week`. Additional assessments
require unique IDs; no weight is inferred from a sibling or a week. Missing or
invalid weights leave the course policy invalid and the final unavailable.

The result contains `rows`, `tracks`, `current_average`, `earned_final_points`,
`final_mark`, `complete`, `policy_valid`, `policy_errors`, and `unmatched_records`.
Each row gives its own `weight`, `score`, `weighted_points`, `completed`, and
`status` (`graded`, `submitted`, `in_progress`, or `not_available`). The
`submitted` status requires a matching `pending_assessment_version` archive
entry. An unmarked row does not acquire a zero score.
`current_average` divides earned points by completed weight; it is null until
at least one weighted assessment is complete. `earned_final_points` is a sum
out of the full course, including uncompleted work as zero contribution, but
does not label uncompleted work as a graded zero. `final_mark` is present only
when every configured assessment is complete and weights total 100.

`GradebookAdapter.from_school(school, course_id)` is the exact production caller
mapping for the UI owner: it reads `school.gradebook`, `school.local_identity`,
`school.course_bridge`, and `school.archive`, selects the current attempt from
`CourseProgression.summary`, or the highest completed attempt if no current
records exist, then calls `build` with the selected attempt records,
`bridge.weeks(course_id, kind)`, and `Weights.course(course_id)`. It returns
`attempt_number`, `best_completed_attempt`, `best_completed_mark`, and
`retake_status` separately. When versioned `course_attempt > 0` appears, it
uses `AttemptSelector.select` and preserves multiple records for one week.
The current course's mark must not be presented as
the best historical mark. The archive is only used for pending status. Existing
`SchoolSession` producers write an official score only on marking, and pending
archive records deliberately omit `score`.

The existing progression groups one record per weekly slot. Legacy weekly
records continue through that projection. Records omitted by it appear in
`ambiguous_legacy_records`; when mixed with explicit attempts they are never
assigned to one by timestamp. The UI must show `identity_status` and must not
silently blend these records into a displayed mark. Unmatched official records
within a selected attempt appear in `unmatched_records`.

For future configured assessments, add these optional fields to each new
official or pending record at production creation time: `course_attempt`
(positive integer, stable per profile and course retake) and
`gradebook_assessment_id` (stable configured assessment ID, such as
`lecture:1` or the `assessments[].id`). Preserve the existing random
`assessment_id` for class and exactly-once delivery. Copy both optional
fields through `_enrollment_record`, `_give` obligation, `_mark`, and
`_fail_departing` record creation in `school_session.gd`; no historical
records should be rewritten. The course config must declare each added ID and
positive weight; combined course weights still total 100. A weekly legacy
record maps by kind and week only when exactly one configured row occupies
that slot. Missing identity with two same-week rows remains unmatched.

`gradebook_assessment_id` is separate from the class session's random
`assessment_id`; the latter cannot identify a curriculum row. This module
does not infer attendance
or graduation outcomes. A complete mark of at least 50 passes.

Prepared runtime check: run
`godot --headless --path <project> --script res://review_artifacts/course_gradebook_20261107/data/test_gradebook_view.gd`.
This fixture has expected numeric oracles and exits nonzero on assertion failure.
