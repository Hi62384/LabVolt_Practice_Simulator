"""Isolated reference model; not connected to the game or production saves."""
from dataclasses import dataclass, field

MAX_STUDENTS = 32
MAX_RECENT = 6
MAX_EVENTS = 3
CORE_RESERVE_SECONDS = 45
TRANSITIONS = {
    "proposed": {"preparing", "cancelled"},
    "preparing": {"announcing", "cancelled"},
    "announcing": {"active", "cancelled"},
    "active": {"resolving", "interrupted", "timed_out", "cancelled"},
    "interrupted": {"active", "cancelled", "timed_out"},
    "resolving": {"complete", "cancelled"},
}
TERMINAL = frozenset(("complete", "cancelled", "timed_out"))


@dataclass(frozen=True)
class Definition:
    id: str
    seconds: int
    resource: str
    courses: frozenset[str]
    weight: int


@dataclass
class Director:
    class_id: str
    recent: list[str] = field(default_factory=list)
    completed: int = 0
    event: dict | None = None
    sequence: int = 0

    def propose(self, *, host: bool, phase: str, seconds_left: int,
                course: str, definitions: list[Definition], students: list[str],
                random_index: int) -> dict | None:
        if not host or phase != "lesson" or self.event is not None or self.completed >= MAX_EVENTS:
            return None
        if len(students) > MAX_STUDENTS or not students or len(set(students)) != len(students):
            return None
        choices = [d for d in definitions if d.id and d.weight > 0 and d.seconds > 0
                   and course in d.courses and d.id not in self.recent
                   and d.seconds + CORE_RESERVE_SECONDS <= seconds_left]
        if not choices:
            return None
        weight = sum(d.weight for d in choices)
        pick = random_index % weight
        chosen = choices[-1]
        for definition in choices:
            if pick < definition.weight:
                chosen = definition
                break
            pick -= definition.weight
        self.sequence += 1
        self.event = {"id": f"{self.class_id}:{self.sequence}", "definition": chosen.id,
                      "state": "proposed", "resource": chosen.resource,
                      "participants": list(students), "seconds": chosen.seconds}
        return self.snapshot()

    def advance(self, event_id: str, target: str, *, host: bool) -> bool:
        event = self.event
        if not host or event is None or event_id != event["id"]:
            return False
        if target not in TRANSITIONS.get(event["state"], set()):
            return False
        event["state"] = target
        if target in TERMINAL:
            self.recent = (self.recent + [event["definition"]])[-MAX_RECENT:]
            if target == "complete":
                self.completed += 1
            self.event = None
        return True

    def assessment_started(self, *, host: bool) -> bool:
        if not host:
            return False
        if self.event is not None:
            self.recent = (self.recent + [self.event["definition"]])[-MAX_RECENT:]
            self.event = None
        return True

    def disconnect(self, identity: str, *, host: bool) -> bool:
        if not host or self.event is None or identity not in self.event["participants"]:
            return False
        self.event["participants"].remove(identity)
        if not self.event["participants"]:
            self.advance(self.event["id"], "cancelled", host=True)
        return True

    def snapshot(self) -> dict | None:
        if self.event is None:
            return None
        return {**self.event, "participants": list(self.event["participants"])}
