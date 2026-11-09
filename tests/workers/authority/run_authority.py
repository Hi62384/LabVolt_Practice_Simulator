"""Bounded, isolated Godot tests. Only kills processes started by this runner."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import time
import uuid

parser = argparse.ArgumentParser()
parser.add_argument('--godot', required=True)
parser.add_argument('--project', required=True)
parser.add_argument('--work', required=True)
parser.add_argument('--port', type=int, default=25350)
parser.add_argument('--core-hooks', action='store_true', help='Require integrator-owned proposed DC hooks')
args = parser.parse_args()
assert 25350 <= args.port <= 25399
project = Path(args.project).resolve()
base = Path(args.work).resolve() / ('authority-' + uuid.uuid4().hex[:10])
base.mkdir(parents=True)
owned = []
logs = []

def launch(name, script, extra=(), profile=None):
    env = os.environ.copy()
    profile_dir = base / (profile or name)
    for key in ('APPDATA', 'LOCALAPPDATA'):
        folder = profile_dir / key
        folder.mkdir(parents=True, exist_ok=True)
        env[key] = str(folder)
    temp_dir = profile_dir / 'temp'
    temp_dir.mkdir(parents=True, exist_ok=True)
    env['TEMP'] = env['TMP'] = str(temp_dir)
    log = base / (name + '.log')
    stream = open(base / (name + '.stdout'), 'w', encoding='utf-8')
    cmd = [args.godot, '--headless', '--path', str(project), '--script', script,
           '--log-file', str(log)]
    if extra:
        cmd += ['--', *map(str, extra)]
    proc = subprocess.Popen(cmd, env=env, stdout=stream, stderr=subprocess.STDOUT)
    owned.append((proc, stream))
    logs.append(log)
    return proc

def wait_file(file, proc, timeout=40):
    end = time.monotonic() + timeout
    while not file.exists():
        if proc.poll() is not None:
            raise RuntimeError(f'process {proc.pid} exited {proc.returncode} waiting for {file.name}')
        if time.monotonic() > end:
            raise TimeoutError(file)
        time.sleep(.1)

def complete(proc, timeout=50):
    if proc.wait(timeout=timeout) != 0:
        raise RuntimeError(f'process {proc.pid} returned {proc.returncode}')

try:
    complete(launch('unit', 'res://tests/workers/authority/test_ledger.gd'))
    complete(launch('component-persistence', 'res://tests/workers/authority/test_component_persistence.gd'))
    complete(launch('firmware-storage', 'res://tests/workers/authority/test_firmware_storage.gd'))
    # Existing offline APIs and save formats continue to work with isolated saves.
    for name in ('trade', 'assortments', 'analyzer', 'custom', 'nested_firmware', 'notebook'):
        complete(launch('regression-' + name, f'res://tests/electronics/test_{name}.gd'))
    network_script = 'res://tests/workers/authority/network_case.gd'
    for phase in ('cancel', 'trade', 'recover'):
        control = base / phase
        control.mkdir()
        host = launch('host-' + phase, network_script, ('host', phase, args.port, control), 'host')
        wait_file(control / ('listening-' + phase), host)
        client = launch('client-' + phase, network_script, ('client', phase, args.port, control), 'client')
        complete(client)
        if phase == 'trade':
            wait_file(control / 'host-crash-ready', host)
            host.kill()
            host.wait(timeout=5)
            # Rewind the client's ordinary JSON to its pre-commit backup. Host ledger
            # must repair this stale local save on rebind rather than duplicate stock.
            for profile in (base / 'client' / 'APPDATA').rglob('electronics_*.json'):
                backup = profile.with_name(profile.name + '.bak')
                if backup.exists():
                    prior = json.loads(backup.read_text(encoding='utf-8'))
                    prior['inventory']['r1000'] = 8
                    prior['inventory']['r220'] = 4
                    prior['applied_trades'] = {}
                    profile.write_text(json.dumps(prior), encoding='utf-8')
        else:
            complete(host)
    if args.core_hooks:
        assert args.port < 25399
        control = base / 'core-hooks'
        control.mkdir()
        script = 'res://tests/workers/authority/test_core_hooks.gd'
        host = launch('core-host', script, ('host', args.port + 1, control), 'core-host')
        wait_file(control / 'listening', host)
        client = launch('core-client', script, ('client', args.port + 1, control), 'core-client')
        complete(client)
        complete(host)
    for log in logs:
        content = log.read_text(encoding='utf-8', errors='replace')
        errors = [line for line in content.splitlines() if 'SCRIPT ERROR' in line or
                  ('ERROR:' in line and 'root certificate store' not in line)]
        if errors:
            raise RuntimeError(f'{log}: {errors}')
    print('PASS: authority unit and component/IO persistence, six offline regressions, adversarial ENet cancellation, trade, killed host restart and stale-client recovery')
    print(base)
finally:
    for proc, stream in owned:
        if proc.poll() is None:
            proc.kill()
            proc.wait(timeout=5)
        stream.close()
