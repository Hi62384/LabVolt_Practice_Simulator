"""Repeatable Godot numerical, gameplay and real-process ENet checks."""
import argparse
import os
from pathlib import Path
import subprocess
import tempfile
import time


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--godot', required=True, help='Godot 4.5.1 executable (console variant on Windows)')
    parser.add_argument('--visual', action='store_true', help='Render gameplay and save preview PNGs')
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    executable = str(Path(args.godot).resolve())
    logs = root / 'docs' / 'validation_logs'
    logs.mkdir(exist_ok=True)
    failed = False
    with tempfile.TemporaryDirectory(prefix='labvolt-tests-') as temp:
        env = os.environ.copy()
        env['APPDATA'] = str(Path(temp) / 'Roaming')
        env['LOCALAPPDATA'] = str(Path(temp) / 'Local')
        Path(env['APPDATA']).mkdir()
        Path(env['LOCALAPPDATA']).mkdir()

        def command(script, headless=True, extra=()):
            return [executable] + (['--headless'] if headless else []) + [
                '--path', str(root), '--script', 'res://tests/' + script
            ] + (['--'] + list(extra) if extra else [])

        def valid(code, text):
            # This Windows sandbox reports a certificate-store initialization
            # error even without TLS requests. Never suppress project errors.
            filtered = text.replace('ERROR: Failed to read the root certificate store.', '')
            return code == 0 and 'ERROR:' not in filtered and 'FAIL' not in filtered

        for script in ['electrical_tests.gd', 'gameplay_tests.gd', 'extended_tests.gd', 'menu_tests.gd', 'school_tests.gd', 'instrument_tests.gd', 'new_features.gd']:
            visual = script in ['menu_tests.gd', 'gameplay_tests.gd']
            completed = subprocess.run(command(script, not visual, ('--visual',) if visual else ()),
                                       env=env, text=True, stdout=subprocess.PIPE,
                                       stderr=subprocess.STDOUT, timeout=60)
            text = completed.stdout
            (logs / (script + '.log')).write_text(text, encoding='utf-8')
            print(text)
            failed = failed or not valid(completed.returncode, text)

        jobs = []

        def start(role):
            path = logs / ('network_' + role + '.log')
            output = path.open('w', encoding='utf-8')
            process = subprocess.Popen(command('network_peer.gd', extra=(role,)),
                                       env=env, stdout=output, stderr=subprocess.STDOUT)
            jobs.append((role, process, output, path))

        try:
            start('host')
            time.sleep(.6)
            start('client')
            deadline = time.monotonic() + 18
            while time.monotonic() < deadline:
                if 'SYNC_PASS' in (logs / 'network_client.log').read_text(encoding='utf-8'):
                    break
                time.sleep(.1)
            start('late')
            for role, process, output, path in jobs:
                try:
                    code = process.wait(timeout=38)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()
                    code = -1
                output.close()
                text = path.read_text(encoding='utf-8')
                print(role, 'exit', code, '\n', text)
                failed = failed or not valid(code, text)
        finally:
            for _, process, output, _ in jobs:
                if process.poll() is None:
                    process.kill()
                    process.wait()
                if not output.closed:
                    output.close()
    room_jobs = []
    for role in ['host', 'client']:
        path = logs / ('room_' + role + '.log')
        output = path.open('w', encoding='utf-8')
        proc = subprocess.Popen([executable, '--headless', '--path', str(root),
                                 '--script', 'res://tests/room_network.gd', '--', role],
                                stdout=output, stderr=subprocess.STDOUT)
        room_jobs.append((proc, output, path))
        time.sleep(.7)
    for proc, output, path in room_jobs:
        try:
            code = proc.wait(timeout=40)
        except subprocess.TimeoutExpired:
            proc.kill()
            code = proc.wait()
        output.close()
        text = path.read_text(encoding='utf-8')
        print(text)
        failed = failed or not valid(code, text)
    print('RESULT:',  'FAILED' if failed else 'ALL SUITES PASSED')
    return 1 if failed else 0


if __name__ == '__main__':
    raise SystemExit(main())
