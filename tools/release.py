"""Build or fetch matching iOS/Windows releases into this project's releases/ folder."""

import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid
import zipfile

if __package__ in (None, ''):
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from tools.release_artifacts import (
    ROOT, PACKAGES, ReleaseError, checked_members, sha256, verify_ipa, verify_windows,
)

WORKFLOW = 'ios-sideload.yml'
PREFIXES = {'ios': 'hyperstream-ios-unsigned', 'windows': 'hyperstream-windows-x64'}


def git(*args):
    result = subprocess.run(['git', *args], cwd=ROOT, capture_output=True, text=True)
    if result.returncode:
        raise ReleaseError('Git command failed. Check the repository and branch.')
    return result.stdout.strip()


def repository_from_remote(remote):
    match = re.fullmatch(r'(?:https://github\.com/|git@github\.com:)([\w.-]+/[\w.-]+?)(?:\.git)?/?', remote)
    if not match:
        raise ReleaseError('origin must be a github.com repository without embedded credentials.')
    return match[1]


def github_token(repository):
    token = os.environ.get('GH_TOKEN') or os.environ.get('GITHUB_TOKEN')
    if token:
        return token
    result = subprocess.run(
        ['git', 'credential', 'fill'], cwd=ROOT, text=True, capture_output=True,
        input=f'protocol=https\nhost=github.com\npath={repository}.git\n\n',
        env=dict(os.environ, GIT_TERMINAL_PROMPT='0', GCM_INTERACTIVE='never'),
    )
    credential = dict(line.split('=', 1) for line in result.stdout.splitlines() if '=' in line)
    if result.returncode or not credential.get('password'):
        raise ReleaseError('Sign into GitHub through Git, or set GH_TOKEN with Actions read/write permission. Never put the token in a file or command argument.')
    return credential['password']


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


class GitHub:
    def __init__(self, repository, token):
        self.base = f'https://api.github.com/repos/{repository}'
        self.opener = urllib.request.build_opener(NoRedirect)
        self.headers = {'Authorization': 'Bearer ' + token, 'Accept': 'application/vnd.github+json',
                        'X-GitHub-Api-Version': '2022-11-28', 'User-Agent': 'hyperstream-release'}

    def request(self, path, body=None):
        request = urllib.request.Request(self.base + path, headers=self.headers,
            data=None if body is None else json.dumps(body).encode('utf-8'))
        if body is not None:
            request.add_header('Content-Type', 'application/json')
        try:
            with self.opener.open(request, timeout=45) as response:
                data = response.read()
                return json.loads(data) if data else {}
        except urllib.error.HTTPError as error:
            raise ReleaseError(f'GitHub returned HTTP {error.code}. Check Actions access and the run in GitHub.') from None
        except (urllib.error.URLError, TimeoutError):
            # A dispatch might have succeeded even if its response was lost.
            raise ReleaseError('GitHub did not respond. Check Actions before repeating a build; use fetch to resume a completed run.') from None

    def download(self, artifact, destination):
        url = self.base + f"/actions/artifacts/{artifact['id']}/zip"
        headers = self.headers
        for _ in range(5):
            if urllib.parse.urlsplit(url).scheme != 'https':
                raise ReleaseError('Refusing an insecure artifact redirect.')
            try:
                request = urllib.request.Request(url, headers=headers)
                with self.opener.open(request, timeout=60) as response, destination.open('xb') as output:
                    total = 0
                    while chunk := response.read(1024 * 1024):
                        total += len(chunk)
                        if total > 1024 ** 3:
                            raise ReleaseError('Artifact exceeds the 1 GiB download limit.')
                        output.write(chunk)
                expected = artifact.get('digest')
                if expected and expected != 'sha256:' + sha256(destination):
                    raise ReleaseError('GitHub artifact digest does not match.')
                return
            except urllib.error.HTTPError as error:
                if error.code not in (301, 302, 303, 307, 308):
                    raise ReleaseError(f'Artifact download returned HTTP {error.code}.') from None
                url = urllib.parse.urljoin(url, error.headers.get('Location', ''))
                # Presigned storage URLs get no GitHub credentials, even on a
                # subsequent redirect. Neither tokens nor those URLs are logged.
                headers = {'User-Agent': 'hyperstream-release'}
            except (urllib.error.URLError, TimeoutError):
                raise ReleaseError('Artifact download failed. Run fetch again to retry.') from None
        raise ReleaseError('Too many artifact redirects.')


def artifacts_for(api, run):
    artifacts = api.request(f"/actions/runs/{run['id']}/artifacts?per_page=100")['artifacts']
    result = {}
    for platform, prefix in PREFIXES.items():
        name = f"{prefix}-{run['run_number']}-{run['run_attempt']}"
        matches = [a for a in artifacts if a['name'] == name and not a['expired']]
        if len(matches) != 1:
            raise ReleaseError(f'Missing {platform} artifact for this run attempt. Build both platforms again if artifacts expired.')
        result[platform] = matches[0]
    return result


def validate_run(run):
    if run.get('path') != '.github/workflows/' + WORKFLOW:
        raise ReleaseError('This run belongs to a different workflow.')
    if run.get('status') != 'completed' or run.get('conclusion') != 'success':
        raise ReleaseError('Both platform jobs must finish successfully before collecting a release.')


def unpack_artifact(archive_path, platform, run, repository, destination):
    with zipfile.ZipFile(archive_path) as archive:
        checked_members(archive)
        if archive.getinfo('release-manifest.json').file_size > 65536:
            raise ReleaseError('Release manifest is too large.')
        manifest = json.loads(archive.read('release-manifest.json'))
        expected = {'schema': 1, 'platform': platform, 'repository': repository,
                    'run_id': run['id'], 'run_attempt': run['run_attempt'],
                    'build_number': run['run_number'], 'commit': run['head_sha'],
                    'package': PACKAGES[platform], 'configuration': 'release'}
        if any(manifest.get(k) != v for k, v in expected.items()):
            raise ReleaseError('Artifact metadata does not match the selected run and commit.')
        if not re.fullmatch(r'\d+\.\d+\.\d+', manifest.get('version', '')):
            raise ReleaseError('Artifact version is invalid.')
        destination.mkdir(parents=True, exist_ok=True)
        package = destination / PACKAGES[platform]
        with archive.open(PACKAGES[platform]) as source, package.open('xb') as output:
            shutil.copyfileobj(source, output)
    if sha256(package) != manifest.get('sha256'):
        raise ReleaseError('Package checksum does not match its manifest.')
    if platform == 'ios':
        verify_ipa(package, manifest['version'], manifest['build_number'])
    else:
        expected_version = f"{manifest['version']}+{manifest['build_number']}"
        if manifest.get('file_version') != expected_version:
            raise ReleaseError('Windows version does not match the release.')
        verify_windows(package)
        # The destination is a new staging directory and every ZIP path was
        # validated before writing. Keep the EXE beside its DLLs and data.
        with zipfile.ZipFile(package) as archive:
            archive.extractall(destination / 'windows')
    return manifest, package


def atomic_json(path, data):
    temporary = path.with_name(path.name + '.' + uuid.uuid4().hex + '.tmp')
    temporary.write_text(json.dumps(data, indent=2) + '\n', encoding='utf-8')
    os.replace(temporary, path)


def publish_pair(ios_archive, windows_archive, run, repository, release_root):
    """Publish only a verified pair. Never replace an existing version directory."""
    validate_run(run)
    release_root = release_root.resolve()
    release_root.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='.package-', dir=release_root) as temporary:
        # Verify the absolute cleanup target before TemporaryDirectory removes it.
        stage = Path(temporary).resolve()
        if stage.parent != release_root:
            raise ReleaseError('Staging path is outside the release directory.')
        result = stage / 'release'
        result.mkdir()
        ios, ipa = unpack_artifact(ios_archive, 'ios', run, repository, result)
        windows, windows_zip = unpack_artifact(windows_archive, 'windows', run, repository, result)
        if ios['version'] != windows['version']:
            raise ReleaseError('iOS and Windows have different app versions.')
        version = f"{ios['version']}+{run['run_number']}"
        tag = f"v{version}-r{run['run_attempt']}"
        ipa.rename(result / f'hyperstream-{version}-ios-unsigned.ipa')
        windows_zip.rename(result / f'hyperstream-{version}-windows-x64.zip')
        files = {p.relative_to(result).as_posix(): sha256(p) for p in sorted(result.rglob('*')) if p.is_file()}
        metadata = {'schema': 1, 'version': version, 'commit': run['head_sha'], 'repository': repository,
                    'run_id': run['id'], 'run_number': run['run_number'], 'run_attempt': run['run_attempt'],
                    'workflow_url': run['html_url'], 'files': files,
                    'ipa': f'hyperstream-{version}-ios-unsigned.ipa',
                    'windows_exe': 'windows/hyperstream_client.exe',
                    'windows_zip': f'hyperstream-{version}-windows-x64.zip'}
        atomic_json(result / 'release.json', metadata)
        (result / 'SHA256SUMS.txt').write_text(''.join(f'{digest}  {name}\n' for name, digest in files.items()), encoding='utf-8')
        destination = release_root / tag
        if destination.exists():
            if json.loads((destination / 'release.json').read_text(encoding='utf-8')) != metadata:
                raise ReleaseError('An existing release directory has different metadata; it was not overwritten.')
            for name, digest in files.items():
                if sha256(destination / name) != digest:
                    raise ReleaseError('An existing release file has changed; it was not overwritten.')
        else:
            result.rename(destination)
        latest = release_root / 'latest.json'
        previous = json.loads(latest.read_text(encoding='utf-8')) if latest.exists() else {}
        if (run['run_number'], run['run_attempt']) >= (previous.get('run_number', 0), previous.get('run_attempt', 0)):
            atomic_json(latest, {**metadata, 'directory': tag})
        return destination, metadata


def wait_for_run(api, run_id, timeout):
    deadline = time.monotonic() + timeout * 60
    last = None
    while time.monotonic() < deadline:
        run = api.request(f'/actions/runs/{run_id}')
        status = f"Run {run['run_number']}: {run['status']} ({run.get('conclusion') or 'waiting'})"
        if status != last:
            print(status, flush=True)
            last = status
        if run['status'] == 'completed':
            validate_run(run)
            return run
        time.sleep(20)
    raise ReleaseError(f'Timed out waiting. Resume with: python tools/release.py fetch --run-id {run_id}')


def build(api, ref, timeout):
    if git('status', '--porcelain'):
        raise ReleaseError('Commit and push your changes before building a versioned release.')
    ref = ref or git('symbolic-ref', '--short', 'HEAD')
    commit = git('rev-parse', 'HEAD')
    remote = api.request('/commits/' + urllib.parse.quote(ref, safe=''))
    if remote['sha'] != commit:
        raise ReleaseError('The selected GitHub ref does not match local HEAD. Push your commit first.')
    request_id = uuid.uuid4().hex[:12]
    details = api.request(f'/actions/workflows/{WORKFLOW}/dispatches', {
        'ref': ref, 'return_run_details': True,
        'inputs': {'check_simulator': False, 'request_id': request_id},
    })
    run_id = details.get('workflow_run_id')
    # Older API responses can still be empty. Correlate by our unique run title,
    # never by whichever unrelated workflow happens to be newest.
    for _ in range(18):
        if run_id:
            break
        time.sleep(5)
        runs = api.request(f'/actions/workflows/{WORKFLOW}/runs?event=workflow_dispatch&per_page=30')['workflow_runs']
        matches = [r for r in runs if r['display_title'].endswith(request_id) and r['head_sha'] == commit]
        if len(matches) == 1:
            run_id = matches[0]['id']
    if not run_id:
        raise ReleaseError('Build was requested but its run could not be identified. Check Actions; do not immediately dispatch another build.')
    print(f'{api.base.replace("api.github.com/repos", "github.com")}/actions/runs/{run_id}', flush=True)
    print(f'Resume downloads with: python tools/release.py fetch --run-id {run_id}', flush=True)
    run = wait_for_run(api, run_id, timeout)
    if run['head_sha'] != commit:
        raise ReleaseError('The branch changed during dispatch. This run is not the requested commit.')
    return run


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='command', required=True)
    build_parser = sub.add_parser('build', help='Build both platforms in Actions, wait, and download.')
    build_parser.add_argument('--ref', help='Pushed branch/tag matching local HEAD; defaults to current branch.')
    build_parser.add_argument('--timeout', type=int, default=50, help='Maximum wait in minutes.')
    fetch_parser = sub.add_parser('fetch', help='Download an existing successful release without rebuilding.')
    selection = fetch_parser.add_mutually_exclusive_group(required=True)
    selection.add_argument('--latest', action='store_true')
    selection.add_argument('--run-id', type=int)
    args = parser.parse_args()
    repository = repository_from_remote(git('remote', 'get-url', 'origin'))
    api = GitHub(repository, github_token(repository))
    if args.command == 'build':
        run = build(api, args.ref, args.timeout)
    elif args.run_id:
        run = wait_for_run(api, args.run_id, 50)
    else:
        runs = api.request(f'/actions/workflows/{WORKFLOW}/runs?status=success&per_page=30')['workflow_runs']
        run = None
        for candidate in runs:
            try:
                artifacts_for(api, candidate)
            except ReleaseError:
                continue
            run = candidate
            break
        if run is None:
            raise ReleaseError('No completed release pair is available. Run the build command first.')
    validate_run(run)
    artifacts = artifacts_for(api, run)
    release_root = ROOT / 'releases'
    release_root.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='.download-', dir=release_root) as temporary:
        stage = Path(temporary).resolve()
        if stage.parent != release_root.resolve():
            raise ReleaseError('Download staging path is outside the release directory.')
        for platform, artifact in artifacts.items():
            print(f'Downloading {platform} release...', flush=True)
            api.download(artifact, stage / f'{platform}.zip')
        destination, metadata = publish_pair(stage / 'ios.zip', stage / 'windows.zip', run, repository, release_root)
    print(f"Release {metadata['version']} from {metadata['commit'][:8]}")
    print(f"IPA: {destination / metadata['ipa']}")
    print(f"Windows: {destination / metadata['windows_exe']}")
    print(f"ZIP: {destination / metadata['windows_zip']}")


if __name__ == '__main__':
    try:
        main()
    except KeyboardInterrupt:
        print('Stopped waiting. The GitHub build continues; use fetch to resume.', file=sys.stderr)
        sys.exit(130)
    except (ReleaseError, OSError, ValueError, KeyError, zipfile.BadZipFile) as error:
        # urllib errors are handled above without printing credential-bearing URLs.
        print(f'Release failed: {error}', file=sys.stderr)
        sys.exit(1)
