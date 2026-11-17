import unittest
from classroom_practice_prototype import PracticeRound


def make_round():
    # Deliberately injected, already validated exercise; production must use CourseBridge.
    return PracticeRound("event-1", "class-1", "ETY155", 1, 30.0,
                         {"alice", "bob"}, lambda answer: answer.strip() == "200")


class PracticeContract(unittest.TestCase):
    def test_authority_deadline_and_private_results(self):
        round_ = make_round()
        self.assertEqual(round_.submit("alice", "200", 1, host=False), "closed")
        self.assertEqual(round_.submit("alice", "200", 1, host=True), "accepted")
        self.assertEqual(round_.submit("alice", "0", 2, host=True), "already_submitted")
        self.assertEqual(round_.submit("bob", "200", 30, host=True), "closed")
        self.assertIsNone(round_.snapshot("alice", 2)["result"])
        self.assertIsNone(round_.snapshot("bob", 2)["result"])
        self.assertTrue(round_.close(host=True))
        self.assertTrue(round_.snapshot("alice", 31)["result"])
        self.assertIsNone(round_.snapshot("bob", 31)["result"])

    def test_disconnect_rejoin_and_observer(self):
        round_ = make_round()
        self.assertTrue(round_.disconnect("alice", host=True))
        self.assertEqual(round_.submit("alice", "200", 3, host=True), "not_participating")
        self.assertFalse(round_.reconnect("observer", host=True))
        self.assertTrue(round_.reconnect("alice", host=True))
        self.assertEqual(round_.submit("alice", "200", 4, host=True), "accepted")
        self.assertFalse(round_.snapshot("observer", 4)["can_submit"])

    def test_practice_does_not_mutate_official_records(self):
        official = {"assessment_id": "official", "score": 91}
        round_ = make_round()
        self.assertEqual(round_.submit("bob", "0", 3, host=True), "accepted")
        round_.close(host=True)
        self.assertEqual(official, {"assessment_id": "official", "score": 91})
        self.assertFalse(round_.snapshot("bob", 4)["result"])

    def test_bounded_inputs_and_validator(self):
        round_ = make_round()
        self.assertEqual(round_.submit("alice", "x" * 257, 3, host=True), "invalid")
        self.assertEqual(round_.submit("alice", "200", float("nan"), host=True), "closed")
        round_.evaluate = lambda _: "yes"
        with self.assertRaises(ValueError):
            round_.submit("alice", "x", 3, host=True)
        self.assertFalse(round_.answers)


if __name__ == "__main__":
    unittest.main()
