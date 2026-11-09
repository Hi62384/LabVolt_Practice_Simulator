"""Run campus multiplayer regressions with separate ENet peers and isolated saves."""
import argparse
import os
from pathlib import Path
import subprocess
import time
from uuid import uuid4


CASES = [
    ("ac_rack", "tests/electronics/test_ac_rack_network.gd", ("host", "client", "late"), "PASS client power"),
    ("ac_modules", "tests/electronics/test_ac_modules_network.gd", ("host", "client"), ""),
    ("ac_auxiliary", "tests/electronics/test_ac_auxiliary_network.gd", ("host", "client"), ""),
    ("chairs", "tests/room_network.gd", ("host", "client"), ""),
    ("dorms", "tests/campus/dorms/authority/test_dorm_access_network.gd", ("host", "client"), ""),
    ("cosmetics", "tests/avatar_cosmetics/persistence/test_equipment_network.gd", ("host", "actor", "late"), "PASS actor rejected"),
    ("assignment", "tests/campus/academics/test_room_assignment_rejoin.gd", ("host", "client"), ""),
]


def run(project, godot, output, case):
    name, script, roles, late_marker = case
    folder = output / name
    folder.mkdir()
    peers = []
    deadline = time.monotonic() + 75
    try:
        for role in roles:
            if role == "late":
                _, operator, operator_log = peers[-1]
                while late_marker not in operator_log.read_text(encoding="utf-8", errors="replace"):
                    if operator.poll() is not None or time.monotonic() >= deadline:
                        raise RuntimeError(f"{name}: operator did not reach late-join milestone. See {operator_log}")
                    time.sleep(0.1)
            profile = folder / (role + "-profile")
            profile.mkdir()
            log = folder / (role + ".log")
            env = os.environ | {"APPDATA": str(profile), "XDG_DATA_HOME": str(profile)}
            command = [str(godot), "--headless", "--path", str(project), "--script", "res://" + script, "--", role]
            with log.open("w", encoding="utf-8") as handle:
                peer = subprocess.Popen(command, env=env, stdout=handle, stderr=subprocess.STDOUT)
            peers.append((role, peer, log))
            if role == "host":
                time.sleep(3)
        for role, peer, log in peers:
            status = peer.wait(timeout=max(0.1, deadline - time.monotonic()))
            lines = log.read_text(encoding="utf-8", errors="replace").splitlines()
            errors = [line for line in lines if "ERROR:" in line and "Failed to read the root certificate store." not in line]
            if status or errors or not any(line.startswith("PASS ") for line in lines):
                raise RuntimeError(f"{name}/{role}: exit {status}, errors {errors}. See {log}")
            for line in lines:
                if line.startswith("PASS "):
                    print(f"{name} | {line}", flush=True)
    finally:
        for _, peer, _ in peers:
            if peer.poll() is None:
                peer.kill()
                peer.wait(timeout=5)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True, type=Path)
    parser.add_argument("--project", type=Path, default=Path.cwd())
    parser.add_argument("--case", action="append", choices=[case[0] for case in CASES])
    args = parser.parse_args()
    project = args.project.resolve()
    output = project / ".godot" / ("campus-enet-" + uuid4().hex[:8])
    output.mkdir(parents=True)
    print(output, flush=True)
    for case in CASES:
        if not args.case or case[0] in args.case:
            run(project, args.godot.resolve(), output, case)


if __name__ == "__main__":
    main()
