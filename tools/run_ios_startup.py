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


def main() -> int:
    device = sys.argv[1]
    app = Path('build/ios/iphonesimulator/Runner.app')
    with (app / 'Info.plist').open('rb') as source:
        bundle_id = plistlib.load(source)['CFBundleIdentifier']
    logs = Path('build/ci')
    logs.mkdir(parents=True, exist_ok=True)
    console_path = logs / 'ios-startup-console.log'
    subprocess.run(['xcrun', 'simctl', 'install', device, str(app)], check=True, timeout=90)
    with console_path.open('wb') as console:
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
                match = re.search(r'(?:Dart VM service|Dart VM Service).*?(http://127\.0\.0\.1:\d+/[^\s]*)', output)
                if match:
                    service_uri = match.group(1)
                    break
                if process.poll() is not None:
                    break
                time.sleep(1)
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
