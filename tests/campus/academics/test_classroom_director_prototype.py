"""Contract tests for an isolated prototype, not integration acceptance."""
import unittest
from classroom_director_prototype import CORE_RESERVE_SECONDS, Definition, Director

QUESTION = Definition("question", 20, "board", frozenset({"ETY155"}), 2)
QUIZ = Definition("quiz", 45, "projector", frozenset({"ETY155"}), 1)


class DirectorContract(unittest.TestCase):
    def propose(self, director, **overrides):
        args = dict(host=True, phase="lesson", seconds_left=120, course="ETY155",
                    definitions=[QUESTION, QUIZ], students=["one", "two"], random_index=0)
        args.update(overrides)
        return director.propose(**args)

    def test_host_lecture_course_and_budget_gate(self):
        for changes in ({"host": False}, {"phase": "assignment"}, {"course": "MTH147"},
                        {"seconds_left": CORE_RESERVE_SECONDS}, {"students": []}):
            self.assertIsNone(self.propose(Director("class"), **changes))

    def test_weighted_selection_and_repetition(self):
        director = Director("class")
        event = self.propose(director, random_index=2)
        self.assertEqual(event["definition"], "quiz")
        self.assertFalse(director.advance(event["id"], "active", host=True))
        self.assertFalse(director.advance(event["id"], "preparing", host=False))
        for state in ("preparing", "announcing", "active", "resolving", "complete"):
            self.assertTrue(director.advance(event["id"], state, host=True))
        self.assertEqual(self.propose(director)["definition"], "question")

    def test_disconnect_and_late_snapshot(self):
        director = Director("class")
        event = self.propose(director)
        view = director.snapshot()
        view["participants"].clear()
        self.assertEqual(len(director.snapshot()["participants"]), 2)
        self.assertTrue(director.disconnect("one", host=True))
        self.assertEqual(director.snapshot()["participants"], ["two"])
        self.assertTrue(director.disconnect("two", host=True))
        self.assertIsNone(director.snapshot())
        self.assertFalse(director.advance(event["id"], "preparing", host=True))

    def test_assessment_cancels_without_touching_grade_data(self):
        director = Director("class")
        event = self.propose(director)
        official = {"grade": 87, "assessment_id": "official"}
        self.assertFalse(director.assessment_started(host=False))
        self.assertIsNotNone(director.snapshot())
        self.assertTrue(director.assessment_started(host=True))
        self.assertIsNone(director.snapshot())
        self.assertEqual(official, {"grade": 87, "assessment_id": "official"})
        self.assertFalse(director.advance(event["id"], "preparing", host=True))

    def test_interruption_stale_requests_and_limits(self):
        director = Director("class")
        self.assertIsNone(self.propose(director, students=["one", "one"]))
        self.assertIsNone(self.propose(director, students=[str(i) for i in range(33)]))
        event = self.propose(director)
        self.assertIsNone(self.propose(director))
        for state in ("preparing", "announcing", "active", "interrupted", "active", "timed_out"):
            self.assertTrue(director.advance(event["id"], state, host=True))
        next_event = self.propose(director)
        self.assertNotEqual(event["id"], next_event["id"])
        self.assertFalse(director.advance(event["id"], "cancelled", host=True))
        self.assertFalse(director.disconnect("two", host=False))


if __name__ == "__main__":
    unittest.main()
