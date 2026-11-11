# Build iPhone/iPad releases from Windows with GitHub Actions

The workflow is [`.github/workflows/ios-sideload.yml`](../.github/workflows/ios-sideload.yml).
It runs on demand and produces an **unsigned release IPA for physical devices**.
GitHub supplies macOS and Xcode; your Windows PC handles editing and sideloading.
No Apple account, signing certificate, or Navidrome credential goes into Actions.

Status: [hosted run 2](https://github.com/victoralvelais/navidrome-hyperstream/actions/runs/42930047757)
successfully compiled, packaged, and uploaded the unsigned IPA from commit
`cb897fb`. The downloaded IPA passed checksum, archive-integrity, device-platform,
and app executable-permission checks. Installation and playback on an iPhone
remain to be verified.

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
2. Select **Build iOS for sideloading**, then **Run workflow**.
3. Select the branch and start the run. The workflow must first exist on the
   default branch for the manual button to appear.
4. Follow the job's individual steps. The first run also downloads Flutter and
   dependencies; later runs can reuse the SDK/package cache.
5. When successful, download `hyperstream-ios-unsigned-RUN-ATTEMPT` under
   **Artifacts** on the run's summary page.
6. Extract the downloaded ZIP. The installable input is the **`.ipa` inside**;
   the outer GitHub artifact ZIP is not an IPA.

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
