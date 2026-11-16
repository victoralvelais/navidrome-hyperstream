"""Launch a built simulator app, capture its console, then attach Flutter's driver.

Run from apps/client. Avoids the simulator log-reader race in Flutter 3.47.9;
does not modify the SDK or change physical-device builds.
"""

from pathlib import Path
import plistlib
import re
import subprocess
import sys
import time


def diagnostic(command: list[str], **kwargs) -> None:
    try:
        subprocess.run(command, timeout=30, check=False, **kwargs)
    except (OSError, subprocess.SubprocessError):
        print('Could not collect one simulator diagnostic.', flush=True)


def find_vm_service(device: str, output: str) -> str | None:
    pattern = r'(?:Dart VM service|Dart VM Service).*?(http://127\.0\.0\.1:\d+/[^\s]*)'
    match = re.search(pattern, output)
    if match:
        return match.group(1)
    # log stream can attach after the VM announcement even when started before
    # simctl launch. The simulator's retained log covers that startup race.
    try:
        history = subprocess.run(
            ['xcrun', 'simctl', 'spawn', device, 'log', 'show', '--last', '2m',
             '--predicate', 'process == "Runner" AND eventMessage CONTAINS "Dart VM"',
             '--style', 'compact'],
            capture_output=True, text=True, timeout=10, check=False,
        )
    except (OSError, subprocess.SubprocessError):
        return None
    match = re.search(pattern, history.stdout)
    return match.group(1) if match else None


def main() -> int:
    device = sys.argv[1]
    app = Path('build/ios/iphonesimulator/Runner.app')
    with (app / 'Info.plist').open('rb') as source:
        bundle_id = plistlib.load(source)['CFBundleIdentifier']
    logs = Path('build/ci')
    logs.mkdir(parents=True, exist_ok=True)
    console_path = logs / 'ios-startup-console.log'
    subprocess.run(['xcrun', 'simctl', 'install', device, str(app)], check=True, timeout=90)
    stream_path = logs / 'ios-startup-stream.log'
    with console_path.open('wb') as console, stream_path.open('wb') as stream:
        # Recent simulator runtimes send Flutter output to unified logging even
        # when simctl launch --console is attached. Start both readers first.
        log_process = subprocess.Popen(
            ['xcrun', 'simctl', 'spawn', device, 'log', 'stream', '--level', 'debug',
             '--predicate', 'process == "Runner"', '--style', 'compact'],
            stdout=stream, stderr=subprocess.STDOUT,
        )
        process = subprocess.Popen(
            ['xcrun', 'simctl', 'launch', '--console', device, bundle_id,
             '--enable-dart-profiling', '--enable-checked-mode',
             '--disable-vm-service-publication'],
            stdout=console, stderr=subprocess.STDOUT,
        )
        try:
            deadline = time.monotonic() + 90
            service_uri = None
            while time.monotonic() < deadline:
                output = console_path.read_text(encoding='utf-8', errors='replace')
                output += stream_path.read_text(encoding='utf-8', errors='replace')
                service_uri = find_vm_service(device, output)
                if service_uri:
                    break
                if process.poll() is not None:
                    break
                time.sleep(2)
            if service_uri is None:
                print('No Dart VM service announced. See console and simulator screenshot.', flush=True)
                return 1
            print('Simulator VM service detected. Running the startup driver.', flush=True)
            result = subprocess.run(
                ['flutter', 'drive', '-d', device, '--no-pub',
                 '--driver', 'test_driver/startup_driver.dart',
                 '--use-existing-app=' + service_uri],
                timeout=180,
            )
            return result.returncode
        except subprocess.TimeoutExpired:
            print('Startup driver timed out. See captured simulator diagnostics.', flush=True)
            return 1
        finally:
            log_process.terminate()
            try:
                log_process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                log_process.kill()
                log_process.wait()
            # Capture before terminating, including when launch/attach fails.
            diagnostic(
                ['xcrun', 'simctl', 'io', device, 'screenshot', str(logs / 'ios-startup.png')],
            )
            with (logs / 'ios-startup-system.log').open('wb') as system_log:
                diagnostic(
                    ['xcrun', 'simctl', 'spawn', device, 'log', 'show', '--last', '2m',
                     '--predicate', 'process == "Runner"', '--style', 'compact'],
                    stdout=system_log, stderr=subprocess.STDOUT,
                )
            diagnostic(['xcrun', 'simctl', 'terminate', device, bundle_id])
            if process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()


if __name__ == '__main__':
    raise SystemExit(main())
