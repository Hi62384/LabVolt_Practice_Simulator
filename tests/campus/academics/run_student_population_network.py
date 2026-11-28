#!/usr/bin/env python3
"""Real ENet host/client processes with isolated local student collections."""
from __future__ import annotations
import argparse
import os
from pathlib import Path
import socket
import subprocess
import tempfile
import time

def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', default='godot')
    args = parser.parse_args()
    repository = Path(__file__).resolve().parents[3]
    output = Path(tempfile.mkdtemp(prefix='labvolt-population-network-'))
    with socket.socket() as sock:
        sock.bind(('127.0.0.1', 0))
        port = sock.getsockname()[1]
    processes = []
    logs = []
    try:
        for role, identity in [('server', 'a' * 48), ('client', 'b' * 48)]:
            data = output / role
            data.mkdir()
            env = os.environ.copy()
            for key in list(env):
                if key in ('OPENAI_API_KEY', 'LABVOLT_OPENAI_BASE_URL'):
                    env.pop(key)
            env.update(XDG_DATA_HOME=str(data), APPDATA=str(data),
                       GODOT_SILENCE_ROOT_WARNING='1', LABVOLT_POP_ROLE=role,
                       LABVOLT_POP_PORT=str(port), LABVOLT_POP_ID=identity)
            log = (output / (role + '.log')).open('w', encoding='utf-8')
            logs.append(log)
            processes.append(subprocess.Popen([args.godot, '--headless', '--path', str(repository),
                '--script', 'res://tests/campus/academics/test_student_population_network_peer.gd'],
                env=env, stdout=log, stderr=subprocess.STDOUT))
            if role == 'server':
                time.sleep(.7)
        codes = [process.wait(timeout=55) for process in processes]
    finally:
        for process in processes:
            if process.poll() is None:
                process.terminate()
                process.wait(timeout=5)
        for log in logs:
            log.close()
    passed = all(code == 0 for code in codes)
    for role in ['server', 'client']:
        text = (output / (role + '.log')).read_text(encoding='utf-8')
        print(role + ': ' + text)
        passed = passed and 'SCRIPT ERROR' not in text and 'FAIL:' not in text
    print('STUDENT_POPULATION_NETWORK ' + ('PASS' if passed else 'FAIL') + ' ' + str(output))
    return 0 if passed else 1

if __name__ == '__main__':
    raise SystemExit(main())
