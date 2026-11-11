# Build iPhone/iPad and Windows releases with GitHub Actions

The workflow is [`.github/workflows/ios-sideload.yml`](../.github/workflows/ios-sideload.yml).
It runs on demand and produces an **unsigned release IPA for physical devices**
and a **Windows x64 release bundle** from the same source commit.
GitHub supplies macOS and Xcode; your Windows PC handles editing and sideloading.
No Apple account, signing certificate, or Navidrome credential goes into Actions.

## Build and download automatically

After committing and pushing changes, run this from the repository root:

```powershell
python tools/release.py build
```

The command checks that local HEAD matches the pushed branch, dispatches **Build
app releases**, waits for both jobs, downloads their artifacts, and validates their
commit, versions, checksums, and bundle contents before publishing them locally.
It does not commit or push source for you. Python 3.11+ and Git are enough on the
downloading PC; Flutter, Xcode, and Visual Studio run on the hosted builders.

Windows uses `windows-2022` with Visual Studio 2022. The current audio plugin's
C++17 coroutine implementation fails with the newer Visual Studio 2026 toolchain
on `windows-2025`; update and validate that native dependency before changing the
runner. See the [Windows runner inventory](https://github.com/actions/runner-images/blob/main/images/windows/Windows2022-Readme.md).

Both apps use the version in `apps/client/pubspec.yaml` and the Actions run number
as their build number. For example:

```text
releases/
  latest.json
  v0.1.0+7-r1/
    hyperstream-0.1.0+7-ios-unsigned.ipa
    hyperstream-0.1.0+7-windows-x64.zip
    windows/
      hyperstream_client.exe
      flutter_windows.dll
      ...native plugin and C++ runtime DLLs...
      data/
    release.json
    SHA256SUMS.txt
```

Open the EXE **inside its Windows folder**. The ZIP includes the complete folder
for copying elsewhere, including the redistributable C++ runtime from Visual Studio.
Flutter's [Windows distribution guide](https://docs.flutter.dev/platform-integration/windows/building#building-your-own-zip-file-for-windows)
explains why the EXE needs its DLLs and data alongside it. These are unsigned
personal-use packages, not an installer or an App Store submission.

`latest.json` contains a `directory` relative to `releases/`; its `ipa`,
`windows_exe`, and `windows_zip` paths are relative to that version directory.
Old versions are retained. A failed build or download leaves the previous latest
pointer alone. Re-downloading the same run verifies existing files and refuses to
overwrite changed files. `releases/` is ignored by Git.

To collect existing artifacts, including after closing the build command:

```powershell
python tools/release.py fetch --latest
python tools/release.py fetch --run-id 123456789
```

The run-specific command also waits if that run is still building. Fetch selects
both platforms from the same run attempt. Older iOS-only workflow runs cannot be
collected as pairs. Artifact expiry on GitHub does not remove local copies.

Authentication uses `GH_TOKEN`/`GITHUB_TOKEN` if set, otherwise the cached GitHub
credential from Git's credential helper. Fine-grained tokens need Actions write
to dispatch, Actions read to download, and Contents read to verify the commit.
Tokens remain in memory and are never forwarded to artifact-storage redirects.
The [workflow dispatch API](https://docs.github.com/en/rest/actions/workflows#create-a-workflow-dispatch-event)
returns the new run ID; a unique request identifier handles older empty responses.

This command automates collection while it runs. It does not install a background
service, schedule downloads, build on every push, or publish a GitHub Release.

Status: [hosted run 2](https://github.com/victoralvelais/navidrome-hyperstream/actions/runs/42930047757)
successfully compiled, packaged, and uploaded the unsigned IPA from commit
`cb897fb`. The downloaded IPA passed checksum, archive-integrity, device-platform,
and app executable-permission checks. The user subsequently confirmed that the
sideloaded app works on iPhone. Each new audio feature still needs a device check.

## Startup checks

Hyperstream now renders a named startup screen before making settings/audio
platform calls. It shows the current startup step and a message after 15 seconds
at one step. A settings read that does not finish in three seconds falls back to
temporary preferences without overwriting unread saved data. A Dart timeout cannot
recover a blocked native main thread or a failure before Flutter starts; a wholly
blank screen still requires device logs.

The workflow's optional **check_simulator** input runs
`integration_test/startup_smoke_test.dart` in an available iPhone simulator using
`tools/check_ios_startup.sh`. This launches the real app
and native plugins and checks that sign-in appears. It does not start audio or
connect to Navidrome.
The `ios-build-log` artifact includes the simulator test output, app console,
system log, and screenshot. The simulator check builds a debug test app, launches
it with `simctl --console`, then attaches Flutter's supported integration driver
to the announced VM service. This avoids depending on the SDK's unified-log
reader to capture the initial announcement. The startup check is experimental,
off by default, and has a 22-minute step allowance. Hosted attempts have timed out
during setup/build and have not established a successful simulator test. The
workflow summary explicitly reports skipped, failed, or successful checks. A
successfully packaged IPA is still uploaded if this check fails, with the workflow
failure retained.

## Set up the repository

Create or choose a GitHub repository and push this project to its default branch.
Use a public repository if you want GitHub's free standard hosted runners without
the private-repository compute allowance. A public repository exposes the source
and build artifacts; choosing GitHub Actions alone does not make a project public.
Private repositories have an included allowance and can incur usage charges.
See [GitHub Actions billing](https://docs.github.com/en/billing/concepts/product-billing/github-actions).

Local Git is initialized on `main` with an initial project commit. The remote
and upstream connection are left for you to configure. For a new repository,
leave GitHub's README, .gitignore, and license initialization unchecked so the
remote starts empty. From the project root, replacing `OWNER` and the repository
name with your destination:

```powershell
git remote add origin https://github.com/OWNER/navidrome-hyperstream.git
git push -u origin main
```

If an origin or remote history already exists, use that configuration instead.
The `-u` sets `origin/main` as the local branch's upstream for later pushes and
pulls. Git will request GitHub authentication as needed.

The existing ignore files exclude Flutter build outputs, generated local paths,
the disposable Python library, environment files, and signing credentials. Keep
`apps/client/pubspec.lock` and the iOS Xcode project in version control.

## Run and download

1. Open the repository's **Actions** tab.
2. Select **Build app releases**, then **Run workflow**.
3. Select the branch and start the run. The workflow must first exist on the
   default branch for the manual button to appear.
4. Follow the job's individual steps. The first run also downloads Flutter and
   dependencies; later runs can reuse the SDK/package cache.
5. When successful, download `hyperstream-ios-unsigned-RUN-ATTEMPT` under
   **Artifacts** on the run's summary page.
6. Extract the downloaded ZIP. The installable input is the **`.ipa` inside**;
   the outer GitHub artifact ZIP is not an IPA.

The Windows job uploads `hyperstream-windows-x64-RUN-ATTEMPT`. Its artifact
contains the Windows application ZIP, checksum, and release manifest. The local
release command handles both layers of ZIP packaging automatically.

Artifacts expire after seven days to limit retained storage. Start another run
when needed. Re-running a workflow uses the same source revision; push your fixes
and start a new run to build changed code. A new run on the same branch cancels
an older run that is still active. See [manual workflow runs](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/manually-run-a-workflow).

The artifact also contains a SHA-256 checksum and `build-info.txt` with the source
commit, workflow run, and tool versions. You can compare the downloaded IPA using
`Get-FileHash .\hyperstream-ios-unsigned.ipa -Algorithm SHA256`.

## What each step does

| Step | Purpose |
| --- | --- |
| Checkout | Fetch the selected source revision with read-only repository permissions. |
| Flutter setup | Install/cache Flutter 3.47.9, matching the Windows prototype. |
| Tool check | Select Xcode 26.6 on the standard `macos-26` runner and print versions. |
| Dependencies | Restore the committed Dart lockfile; fail if it needs changes. |
| Format, analyze, test | Run the same Dart checks and unit/widget tests used locally. |
| Native build | Build an unsigned release for physical iPhones and iPads. |
| Package | Check the device platform/arm64 executable, preserve the bundle structure, create `Payload/Runner.app` in an IPA, and check archive integrity. |
| Upload | Save the IPA, checksum, build information, and native compiler log. |

The three actions are pinned to exact commits. The workflow specifies the Flutter
version and Xcode path explicitly; update them deliberately when upgrading tools.
GitHub runner images still receive updates. If the pinned Xcode is removed, select
a supported version from the [macOS runner inventory](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-arm64-Readme.md)
and validate a fresh build. The Flutter version must satisfy the Dart SDK constraint
in `apps/client/pubspec.yaml`.

The project uses Flutter's generated Swift Package Manager integration. Let
`flutter build ios` prepare the native dependencies instead of adding an unrelated
Podfile or regenerating the iOS project. The device build is equivalent to:

```bash
cd apps/client
flutter pub get --enforce-lockfile
flutter build ios --release --no-codesign --no-pub
bash ../../tools/package_ios.sh build/ios/iphoneos/Runner.app build/ci/hyperstream-ios-unsigned.ipa
```

The packaging script runs on macOS and refuses to overwrite an existing IPA.
The ZIP is unsigned even though it has an `.ipa` extension. This workflow does
not publish a GitHub Release, submit to Apple, or install anything on your phone.

## Install with AltStore Classic

Follow the official [AltStore Windows setup](https://faq.altstore.io/altstore-classic/how-to-install-altstore-windows)
to install AltServer and AltStore Classic. Import the extracted IPA through
AltStore Classic while AltServer is reachable. Signing uses your Apple account
on your own devices; no GitHub secret is needed. Enable Developer Mode and trust
the developer profile when prompted by iOS.

With a free Apple account, apps need refreshing every seven days and the standard
three-app limit applies. This signing expiration is independent of GitHub's
artifact-retention period. See [AltStore's distribution comparison](https://developer.altstore.io/).

The iOS app's server field starts empty. Enter an HTTPS address reachable from
the phone, or test the local-network configuration using the PC's LAN address.
`localhost:4664` refers to the phone when entered on the phone. Windows Firewall,
Docker port publishing, and local-network permission must allow the connection.
Do not bake usernames/passwords or private server URLs into the workflow.

## First device checks and failures

Check sign-in, album browsing, playback and seeking, track transitions while the
phone is locked, Control Center controls, headphone removal, and interruptions.
Record the workflow run/commit and iOS version alongside any failure. A successful
build establishes compilation and packaging; it does not establish these behaviors.

If the native build fails, open its step log or download the `ios-build-log`
artifact. Failures before the build step appear in the Actions log without a
native log artifact. If installation fails, distinguish an IPA/signing problem
from a runtime crash after launch. Never attach an Apple password, certificate,
or authenticated Navidrome URL when reporting an issue.

TestFlight and App Store distribution are a future, separate signing workflow.
The current sideload workflow does not require a paid Apple Developer membership.
