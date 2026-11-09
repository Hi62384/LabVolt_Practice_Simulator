"""Run isolated firmware tests; optional externally compiled Arduino HEX argument.
python run_tests.py --godot GODOT_EXE --node NODE_EXE --logs LOG_DIRECTORY [--arduino-hex HEX]
"""
import argparse
import os
import pathlib
import subprocess
import sys
import uuid

parser = argparse.ArgumentParser()
parser.add_argument('--godot', required=True)
parser.add_argument('--node', required=True)
parser.add_argument('--logs', required=True)
parser.add_argument('--arduino-hex')
args = parser.parse_args()
project = pathlib.Path(__file__).resolve().parents[3]
logs = pathlib.Path(args.logs).resolve() / ('firmware-' + uuid.uuid4().hex[:12])
logs.mkdir(parents=True)
env = dict(os.environ, LABVOLT_TEST_NODE=str(pathlib.Path(args.node).resolve()))
tests = [('machine', [args.node, str(project / 'tests/workers/firmware/test_machine.cjs')])]
for name, script in [('worker', 'tests/workers/firmware/test_worker.gd'),
                     ('ide-project', 'tests/workers/firmware/test_ide_project.gd'),
                     ('legacy-firmware', 'tests/electronics/test_firmware.gd'),
                     ('nested-firmware', 'tests/electronics/test_nested_firmware.gd')]:
    tests.append((name, [args.godot, '--headless', '--path', str(project), '--script', 'res://' + script,
                         '--log-file', str(logs / (name + '-godot.log'))]))
if args.arduino_hex:
    tests.append(('compiled-arduino', [args.node, str(project / 'tests/workers/firmware/test_compiled_arduino.cjs'),
                                      str(pathlib.Path(args.arduino_hex).resolve())]))
failed = 0
for name, command in tests:
    env['APPDATA'] = str(logs / ('appdata-' + name))
    pathlib.Path(env['APPDATA']).mkdir()
    try:
        run = subprocess.run(command, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                             timeout=30, text=True, encoding='utf-8', errors='replace')
        text = run.stdout
        bad = run.returncode != 0 or any(marker in text for marker in ['SCRIPT ERROR', 'Parse Error', 'FAIL '])
        # The environment's certificate-store error is recorded, not hidden.
        errors = [line for line in text.splitlines() if line.startswith('ERROR:') and
                  line != 'ERROR: Failed to read the root certificate store.']
        bad = bad or bool(errors)
    except subprocess.TimeoutExpired as exc:
        text = 'TEST TIMEOUT: ' + str(exc)
        bad = True
    (logs / (name + '.log')).write_text(text, encoding='utf-8')
    (logs / (name + '-command.txt')).write_text(subprocess.list2cmdline(command), encoding='utf-8')
    print(('FAIL ' if bad else 'PASS ') + name)
    failed += bool(bad)
print('LOGS:', logs)
print('FAILED SUITES:', failed)
sys.exit(int(bool(failed)))
