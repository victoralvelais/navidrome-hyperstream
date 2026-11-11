import json
from pathlib import Path
import plistlib
import stat
import struct
import tempfile
import unittest
import zipfile

from tools.release import artifacts_for, publish_pair, repository_from_remote
from tools.release_artifacts import PACKAGES, ReleaseError, checked_members, sha256


class ReleaseToolsTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name).resolve()
        # TemporaryDirectory is the exact, dedicated absolute cleanup target.
        self.addCleanup(self.temp.cleanup)
        self.run = {'id': 123, 'run_number': 7, 'run_attempt': 1, 'head_sha': 'a' * 40,
                    'html_url': 'https://github.com/owner/repo/actions/runs/123',
                    'status': 'completed', 'conclusion': 'success',
                    'path': '.github/workflows/ios-sideload.yml'}

    def artifact(self, platform, *, version='0.1.0', commit=None, checksum=None, bad_windows_path=None):
        package = self.root / PACKAGES[platform]
        with zipfile.ZipFile(package, 'w') as archive:
            if platform == 'ios':
                info = {'CFBundleSupportedPlatforms': ['iPhoneOS'], 'CFBundleShortVersionString': version,
                        'CFBundleVersion': '7', 'CFBundleExecutable': 'Runner', 'UIBackgroundModes': ['audio']}
                archive.writestr('Payload/Runner.app/Info.plist', plistlib.dumps(info))
                executable = zipfile.ZipInfo('Payload/Runner.app/Runner')
                executable.external_attr = (stat.S_IFREG | 0o755) << 16
                archive.writestr(executable, b'compiled-app')
            else:
                exe = bytearray(128)
                exe[:2] = b'MZ'
                struct.pack_into('<I', exe, 0x3c, 64)
                exe[64:70] = b'PE\x00\x00\x64\x86'
                archive.writestr('hyperstream_client.exe', exe)
                for name in ['flutter_windows.dll', 'msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll',
                             'data/icudtl.dat', 'data/flutter_assets/AssetManifest.bin']:
                    archive.writestr(name, b'fixture')
                if bad_windows_path:
                    archive.writestr(bad_windows_path, b'unsafe')
        manifest = {'schema': 1, 'platform': platform, 'version': version, 'configuration': 'release',
                    'build_number': 7, 'run_id': 123, 'run_attempt': 1, 'repository': 'owner/repo',
                    'commit': commit or self.run['head_sha'], 'package': package.name,
                    'sha256': checksum or sha256(package)}
        if platform == 'windows':
            manifest['file_version'] = version + '+7'
        destination = self.root / (platform + '-artifact.zip')
        with zipfile.ZipFile(destination, 'w') as archive:
            archive.write(package, package.name)
            archive.writestr('release-manifest.json', json.dumps(manifest))
        return destination

    def publish(self, **windows_options):
        return publish_pair(self.artifact('ios'), self.artifact('windows', **windows_options),
                            self.run, 'owner/repo', self.root / 'releases')

    def test_complete_pair_is_versioned_and_repeat_download_is_idempotent(self):
        destination, metadata = self.publish()
        self.assertEqual(destination.name, 'v0.1.0+7-r1')
        self.assertTrue((destination / metadata['ipa']).is_file())
        self.assertTrue((destination / 'windows/hyperstream_client.exe').is_file())
        self.assertTrue((destination / 'windows/flutter_windows.dll').is_file())
        self.assertTrue((destination / 'windows/data/icudtl.dat').is_file())
        latest = json.loads((self.root / 'releases/latest.json').read_text())
        self.assertEqual(latest['directory'], destination.name)
        self.assertEqual(latest['commit'], self.run['head_sha'])
        # Reuse identical downloaded archives, even if a build would differ.
        repeated, _ = publish_pair(self.root / 'ios-artifact.zip', self.root / 'windows-artifact.zip',
                                   self.run, 'owner/repo', self.root / 'releases')
        self.assertEqual(destination, repeated)

    def test_existing_modified_files_are_not_overwritten(self):
        destination, _ = self.publish()
        exe = destination / 'windows/hyperstream_client.exe'
        exe.write_bytes(b'keep this modification')
        with self.assertRaisesRegex(ReleaseError, 'changed'):
            publish_pair(self.root / 'ios-artifact.zip', self.root / 'windows-artifact.zip',
                         self.run, 'owner/repo', self.root / 'releases')
        self.assertEqual(exe.read_bytes(), b'keep this modification')

    def test_mismatched_version_or_commit_never_promotes_latest(self):
        for options in [{'version': '0.2.0'}, {'commit': 'b' * 40}, {'checksum': '0' * 64}]:
            with self.subTest(options=options), self.assertRaises(ReleaseError):
                self.publish(**options)
            self.assertFalse((self.root / 'releases/latest.json').exists())
            self.assertEqual(list((self.root / 'releases').iterdir()), [])

    def test_failed_run_cannot_replace_a_previous_latest(self):
        self.publish()
        pointer = self.root / 'releases/latest.json'
        previous = pointer.read_bytes()
        self.run['conclusion'] = 'failure'
        with self.assertRaisesRegex(ReleaseError, 'successfully'):
            self.publish()
        self.assertEqual(pointer.read_bytes(), previous)

    def test_older_fetch_does_not_move_latest_backwards(self):
        self.publish()
        pointer = self.root / 'releases/latest.json'
        newer = {'run_number': 8, 'run_attempt': 1, 'directory': 'newer'}
        pointer.write_text(json.dumps(newer))
        publish_pair(self.root / 'ios-artifact.zip', self.root / 'windows-artifact.zip',
                     self.run, 'owner/repo', self.root / 'releases')
        self.assertEqual(json.loads(pointer.read_text()), newer)

    def test_unsafe_zip_members_and_windows_path_collisions_are_rejected(self):
        for names in [['../escape'], ['/absolute'], ['C:/escape'], ['folder\\escape'],
                      ['data/../escape'], ['A.dll', 'a.dll'], ['name.'], ['con.txt']]:
            with self.subTest(names=names):
                path = self.root / 'unsafe.zip'
                with zipfile.ZipFile(path, 'w') as archive:
                    for name in names:
                        entry = zipfile.ZipInfo(name)
                        # Bypass Windows ZipInfo's slash normalization to write
                        # the actual hostile bytes a downloaded ZIP can contain.
                        entry.filename = name
                        archive.writestr(entry, b'data')
                with zipfile.ZipFile(path) as archive, self.assertRaises(ReleaseError):
                    checked_members(archive)
        with self.assertRaises(ReleaseError):
            self.publish(bad_windows_path='../outside.exe')
        self.assertFalse((self.root / 'outside.exe').exists())

    def test_zip_symlinks_are_rejected(self):
        path = self.root / 'link.zip'
        entry = zipfile.ZipInfo('link')
        entry.external_attr = (stat.S_IFLNK | 0o777) << 16
        with zipfile.ZipFile(path, 'w') as archive:
            archive.writestr(entry, '../escape')
        with zipfile.ZipFile(path) as archive, self.assertRaises(ReleaseError):
            checked_members(archive)

    def test_artifacts_from_different_attempts_are_not_mixed(self):
        class API:
            def request(_, path):
                return {'artifacts': [
                    {'name': 'hyperstream-ios-unsigned-7-1', 'expired': False},
                    {'name': 'hyperstream-windows-x64-7-2', 'expired': False},
                ]}
        with self.assertRaisesRegex(ReleaseError, 'Missing windows'):
            artifacts_for(API(), self.run)

    def test_only_plain_github_remotes_supply_credentials(self):
        self.assertEqual(repository_from_remote('https://github.com/owner/repo.git'), 'owner/repo')
        self.assertEqual(repository_from_remote('git@github.com:owner/repo.git'), 'owner/repo')
        for url in ['https://token@github.com/owner/repo', 'https://github.com.evil/owner/repo',
                    'https://elsewhere.example/owner/repo']:
            with self.assertRaises(ReleaseError):
                repository_from_remote(url)


if __name__ == '__main__':
    unittest.main()
