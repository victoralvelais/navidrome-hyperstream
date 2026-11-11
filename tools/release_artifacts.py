"""Package CI builds and validate artifacts. Python standard library only."""

import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import plistlib
import re
import stat
import struct
import zipfile

ROOT = Path(__file__).resolve().parents[1]
PACKAGES = {'ios': 'hyperstream-ios-unsigned.ipa', 'windows': 'hyperstream-windows-x64.zip'}


class ReleaseError(Exception):
    pass


def sha256(path):
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def source_version():
    text = (ROOT / 'apps/client/pubspec.yaml').read_text(encoding='utf-8')
    match = re.search(r'^version:\s*(\d+\.\d+\.\d+)\+\d+\s*$', text, re.MULTILINE)
    if not match:
        raise ReleaseError('Expected version: MAJOR.MINOR.PATCH+BUILD in pubspec.yaml.')
    return match[1]


def checked_members(archive):
    """Reject traversal, symlinks, and Windows filename collisions before extraction."""
    seen = set()
    total = 0
    for member in archive.infolist():
        name = member.orig_filename.rstrip('/')
        path = PurePosixPath(name)
        parts = name.split('/')
        if (not name or path.is_absolute() or any(c in '<>:"\\|?*' or ord(c) < 32 for c in name) or
                any(part in ('', '.', '..') or part.rstrip(' .') != part for part in parts) or
                any(part.split('.')[0].upper() in {'CON', 'PRN', 'AUX', 'NUL',
                    *(f'COM{i}' for i in range(1, 10)), *(f'LPT{i}' for i in range(1, 10))} for part in parts) or
                stat.S_ISLNK(member.external_attr >> 16)):
            raise ReleaseError('Archive contains an unsafe path or link.')
        key = name.casefold()
        if key in seen:
            raise ReleaseError('Archive contains duplicate paths.')
        seen.add(key)
        total += member.file_size
        if total > 1024 ** 3:
            raise ReleaseError('Archive exceeds the 1 GiB expanded-size limit.')
    if archive.testzip() is not None:
        raise ReleaseError('Archive integrity check failed.')
    return archive.infolist()


def verify_ipa(path, version, build):
    with zipfile.ZipFile(path) as archive:
        if archive.testzip() is not None:
            raise ReleaseError('IPA integrity check failed.')
        prefix = 'Payload/Runner.app/'
        info = plistlib.loads(archive.read(prefix + 'Info.plist'))
        if (info.get('CFBundleSupportedPlatforms') != ['iPhoneOS'] or
                info.get('CFBundleShortVersionString') != version or
                info.get('CFBundleVersion') != str(build) or
                'audio' not in info.get('UIBackgroundModes', [])):
            raise ReleaseError('IPA platform, version, or background-audio metadata does not match.')
        executable = info.get('CFBundleExecutable', '')
        if not executable or '/' in executable or '\\' in executable:
            raise ReleaseError('IPA executable name is invalid.')
        entry = archive.getinfo(prefix + executable)
        if entry.file_size == 0 or not (entry.external_attr >> 16) & 0o111:
            raise ReleaseError('IPA app executable is empty or not executable.')


def verify_windows(path):
    with zipfile.ZipFile(path) as archive:
        checked_members(archive)
        required = {'hyperstream_client.exe', 'flutter_windows.dll', 'data/icudtl.dat',
                    'msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll'}
        if not required.issubset(archive.namelist()) or not any(
                n.startswith('data/flutter_assets/') for n in archive.namelist()):
            raise ReleaseError('Windows package is missing the app, data, or runtime DLLs.')
        exe = archive.read('hyperstream_client.exe')
        if len(exe) < 64 or exe[:2] != b'MZ':
            raise ReleaseError('Windows EXE header is invalid.')
        offset = struct.unpack_from('<I', exe, 0x3c)[0]
        if exe[offset:offset + 6] != b'PE\x00\x00\x64\x86':
            raise ReleaseError('Expected a Windows x64 EXE.')


def make_manifest(platform, package):
    return {
        'schema': 1, 'platform': platform, 'version': source_version(),
        'build_number': int(os.environ['GITHUB_RUN_NUMBER']),
        'run_id': int(os.environ['GITHUB_RUN_ID']),
        'run_attempt': int(os.environ['GITHUB_RUN_ATTEMPT']),
        'commit': os.environ['GITHUB_SHA'], 'repository': os.environ['GITHUB_REPOSITORY'],
        'package': package.name, 'sha256': sha256(package),
        'configuration': 'release',
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('platform', choices=PACKAGES)
    parser.add_argument('--source', type=Path)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    package = args.output / PACKAGES[args.platform]
    if args.platform == 'windows':
        if args.source is None or not args.source.is_dir():
            raise ReleaseError('A compiled Windows release directory is required.')
        with zipfile.ZipFile(package, 'x', compression=zipfile.ZIP_DEFLATED) as archive:
            for path in sorted(args.source.rglob('*')):
                if path.is_file():
                    archive.write(path, path.relative_to(args.source).as_posix())
        verify_windows(package)
    manifest = make_manifest(args.platform, package)
    if args.platform == 'ios':
        verify_ipa(package, manifest['version'], manifest['build_number'])
    else:
        file_version = os.environ.get('HYPERSTREAM_WINDOWS_VERSION', '')
        expected = f"{manifest['version']}+{manifest['build_number']}"
        if file_version != expected:
            raise ReleaseError(f'Windows version does not match {expected}.')
        manifest['file_version'] = file_version
    (args.output / 'release-manifest.json').write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
    (args.output / (package.name + '.sha256')).write_text(f"{manifest['sha256']}  {package.name}\n", encoding='ascii')
    print(f"Packaged {args.platform}: {manifest['version']}+{manifest['build_number']}")


if __name__ == '__main__':
    main()
