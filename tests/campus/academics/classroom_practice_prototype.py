"""Isolated practice-round contract; not used by the game."""
from dataclasses import dataclass, field
from math import isfinite
from typing import Callable

MAX_PARTICIPANTS = 32
MAX_ANSWER_CHARS = 256


@dataclass
class PracticeRound:
    event_id: str
    class_id: str
    course: str
    week: int
    ends_at: float
    allowed: set[str]
    evaluate: Callable[[str], bool]
    answers: dict[str, bool] = field(default_factory=dict)
    present: set[str] = field(default_factory=set)
    closed: bool = False

    def __post_init__(self):
        if not self.event_id or not self.class_id or not self.course or self.week < 1 or not isfinite(self.ends_at):
            raise ValueError("invalid practice context")
        if not 0 < len(self.allowed) <= MAX_PARTICIPANTS or any(not x for x in self.allowed):
            raise ValueError("invalid participants")
        self.allowed = set(self.allowed)
        self.present = set(self.allowed)

    def submit(self, identity: str, answer: str, now: float, *, host: bool) -> str:
        if not host or self.closed or not isfinite(now) or now >= self.ends_at:
            return "closed"
        if identity not in self.allowed or identity not in self.present:
            return "not_participating"
        if identity in self.answers:
            return "already_submitted"
        if not isinstance(answer, str) or len(answer) > MAX_ANSWER_CHARS:
            return "invalid"
        result = self.evaluate(answer)
        if not isinstance(result, bool):
            raise ValueError("validator must return bool")
        self.answers[identity] = result
        return "accepted"

    def disconnect(self, identity: str, *, host: bool) -> bool:
        if not host or identity not in self.present:
            return False
        self.present.remove(identity)
        return True

    def reconnect(self, identity: str, *, host: bool) -> bool:
        if not host or self.closed or identity not in self.allowed:
            return False
        self.present.add(identity)
        return True

    def close(self, *, host: bool) -> bool:
        if not host or self.closed:
            return False
        self.closed = True
        return True

    def snapshot(self, identity: str, now: float) -> dict:
        # Correctness is withheld until the round ends; other players' answers are private.
        return {"event_id": self.event_id, "class_id": self.class_id,
                "seconds_left": max(0.0, self.ends_at - now),
                "submitted": identity in self.answers,
                "result": self.answers.get(identity) if self.closed else None,
                "can_submit": not self.closed and now < self.ends_at
                              and identity in self.present and identity not in self.answers}
