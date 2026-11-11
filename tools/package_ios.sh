#!/usr/bin/env bash
# Run on macOS after `flutter build ios --release --no-codesign`.
set -euo pipefail

app="${1:?Usage: package_ios.sh /path/to/Runner.app /path/to/output.ipa}"
archive="${2:?Usage: package_ios.sh /path/to/Runner.app /path/to/output.ipa}"

if [[ "$(uname -s)" != Darwin ]]; then
  echo 'IPA packaging requires macOS to preserve the app bundle.' >&2
  exit 1
fi
if [[ ! -d "$app" || ! -f "$app/Info.plist" ]]; then
  echo 'Expected a compiled iPhone .app bundle with Info.plist.' >&2
  exit 1
fi
if [[ "$archive" != *.ipa || -e "$archive" || -e "$archive.sha256" ]]; then
  echo 'Choose a new .ipa output path; existing packages are not overwritten.' >&2
  exit 1
fi

platform=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleSupportedPlatforms:0' "$app/Info.plist")
executable=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$app/Info.plist")
if [[ "$platform" != iPhoneOS ]]; then
  echo 'Expected an iPhoneOS build; simulator builds cannot be sideloaded.' >&2
  exit 1
fi
if [[ "$executable" == */* || "$executable" == .* || ! -s "$app/$executable" ]]; then
  echo 'App bundle executable is missing or invalid.' >&2
  exit 1
fi
# -verify_arch treats every following argument as an architecture name.
xcrun lipo "$app/$executable" -verify_arch arm64

mkdir -p "$(dirname "$archive")"
archive="$(cd "$(dirname "$archive")" && pwd)/$(basename "$archive")"
stage=$(mktemp -d "${TMPDIR:-/tmp}/hyperstream-ipa.XXXXXX")
trap 'rm -rf -- "$stage"' EXIT
mkdir "$stage/Payload"

# ditto preserves framework symlinks and executable modes. The resulting ZIP
# must contain Payload/Runner.app, not a bare .app or a simulator bundle.
ditto "$app" "$stage/Payload/Runner.app"
ditto -c -k --norsrc --noextattr --noqtn --keepParent "$stage/Payload" "$archive"
unzip -tq "$archive"
(
  cd "$(dirname "$archive")"
  shasum -a 256 "$(basename "$archive")" > "$(basename "$archive").sha256"
)
printf 'Packaged unsigned iOS app: %s\n' "$archive"
