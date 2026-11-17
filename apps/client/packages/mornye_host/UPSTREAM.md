# Mornye host adapter

Hyperstream embeds Mornye's Rust extension runtime at
[`45df9860661e9c4e731ef26a60c44b2b5d8cf125`](https://github.com/mornyeapp/Mornye/tree/45df9860661e9c4e731ef26a60c44b2b5d8cf125),
whose compatibility version is 5.3.1. This is independent of Hyperstream's app
version. Runtime feature and minimum-version checks remain enabled.

The three supported JavaScript packages are pinned in `assets/catalog.json` to
Mornye-Extension revision `e9d2499688f77d8cbc224c1c1a1fe2ccfdb94555`. Installation
checks both the archive SHA-256 and manifest identity. The source archives are
not modified. `rust/src/adapter.js` adds explicit streaming/download entry points
when loading these particular package versions. Updates require reviewing their
contracts and updating the pinned registry together with adapter tests.

The host uses Mornye's network permissions, QuickJS limits, encrypted storage,
signed sessions, file grants, cancellation and FFmpeg command registry. File
grants cover a single private staging directory, never an SMB share. Hyperstream
provides the FFmpegKit command pump, native player and final MP3/SMB delivery.
The only manifest adjustment is a `hyperstream://session-grant` callback; signed
provider scope, app-version identifiers and other authentication fields stay
unchanged. A pending callback state must belong to the requesting provider.

The runtime's Cargo workspace patches concern Android and Windows UNC paths.
This adapter currently targets iOS/Windows and gives the runtime only local app
storage; it does not access UNC paths. SMB remains in Hyperstream's existing
client. All resolved Cargo dependencies are pinned in `rust/Cargo.lock`.

## Build and replace

Install Rust 1.99.0 (`rustup toolchain install 1.99.0 --profile minimal`). On macOS,
also run `rustup target add --toolchain 1.99.0 aarch64-apple-ios
aarch64-apple-ios-sim x86_64-apple-ios`. Flutter's native asset hook builds the dynamic library
with `cargo +1.99.0 build --release --locked --target <target>` and bundles it into
the Windows distribution or iOS app framework. Native tests use `cargo +1.99.0
test --locked` inside `rust/`. Windows requires the Visual Studio C++ toolchain;
Apple builds require Xcode's SDK and libclang.
The hook supplies target-specific SDK and Clang arguments for QuickJS binding
generation, following Mornye's iOS build script. This keeps the header parser on
the iPhone or simulator SDK instead of the build host's macOS SDK.

To replace the runtime, change its Cargo dependency and rebuild this package and
the open-source app. The release workflow documents the complete build process,
including unsigned iOS packaging. No account data is needed to build or test.
Mornye and its linked libraries retain their licenses; the Hyperstream adapter
source is Apache-2.0. The combined dynamic library includes LGPL-3.0-only Mornye
code. Full notices are bundled in the app's open-source licenses screen and in
`apps/client/assets/licenses/MORNYE-NOTICES.txt`.

Generate notices from the locked graph with `tools/generate_mornye_notices.py`.
Package versions, source references, build configuration and the lockfile are
public; device keys, verification grants, provider settings and resolved audio
URLs are not repository configuration.
