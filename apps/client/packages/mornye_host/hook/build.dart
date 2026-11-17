import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;
    final code = input.config.code;
    final (target, artifact, bundled) = switch (code.targetOS) {
      OS.windows => (
        'x86_64-pc-windows-msvc',
        'hyperstream_mornye.dll',
        'hyperstream_mornye.dll',
      ),
      OS.iOS => (
        code.iOS.targetSdk == IOSSdk.iPhoneSimulator
            ? code.targetArchitecture == Architecture.arm64
                  ? 'aarch64-apple-ios-sim'
                  : 'x86_64-apple-ios'
            : 'aarch64-apple-ios',
        'libhyperstream_mornye.dylib',
        'libhyperstream_mornye.dylib',
      ),
      OS.macOS => (
        code.targetArchitecture == Architecture.arm64
            ? 'aarch64-apple-darwin'
            : 'x86_64-apple-darwin',
        'libhyperstream_mornye.dylib',
        'libhyperstream_mornye.dylib',
      ),
      _ => throw UnsupportedError('Mornye host supports iOS and Windows.'),
    };
    if (code.targetOS == OS.windows &&
        code.targetArchitecture != Architecture.x64) {
      throw UnsupportedError('Windows ARM builds are not available yet.');
    }
    final rust = Directory.fromUri(input.packageRoot.resolve('rust/'));
    final environment = <String, String>{
      if (code.targetOS == OS.iOS) 'IPHONEOS_DEPLOYMENT_TARGET': '15.0',
    };
    if (code.targetOS == OS.iOS) {
      // QuickJS generates bindings with libclang. Its header parser needs the
      // target SDK explicitly; Cargo's target alone still finds macOS headers.
      // This mirrors Mornye's scripts/build_rust_backend.sh for Apple targets.
      final simulator = code.iOS.targetSdk == IOSSdk.iPhoneSimulator;
      final sdk = await Process.run('xcrun', [
        '--sdk',
        simulator ? 'iphonesimulator' : 'iphoneos',
        '--show-sdk-path',
      ]);
      if (sdk.exitCode != 0) {
        throw StateError('The Apple target SDK could not be located.');
      }
      final sdkPath = (sdk.stdout as String).trim();
      final arch = code.targetArchitecture == Architecture.arm64
          ? 'arm64'
          : 'x86_64';
      final clangTarget = '$arch-apple-ios15.0${simulator ? '-simulator' : ''}';
      environment['BINDGEN_EXTRA_CLANG_ARGS_${target.replaceAll('-', '_')}'] =
          '-isysroot "$sdkPath" --target=$clangTarget';
    }
    final result = await Process.run(
      'cargo',
      ['+1.99.0', 'build', '--release', '--locked', '--target', target],
      workingDirectory: rust.path,
      environment: environment,
    );
    if (result.exitCode != 0) {
      throw StateError('Mornye host build failed: ${result.stderr}');
    }
    final file = await File('${rust.path}/target/$target/release/$artifact')
        .copy(File.fromUri(input.outputDirectory.resolve(bundled)).path);
    output.dependencies.addAll([
      for (final file in rust.listSync(recursive: false).whereType<File>())
        file.uri,
      for (final file in Directory(
        '${rust.path}/src',
      ).listSync(recursive: true).whereType<File>())
        file.uri,
      input.packageRoot.resolve('assets/catalog.json'),
    ]);
    output.assets.code.add(
      CodeAsset(
        package: input.packageName,
        name: 'mornye_host',
        linkMode: DynamicLoadingBundled(),
        file: file.uri,
      ),
    );
  });
}
