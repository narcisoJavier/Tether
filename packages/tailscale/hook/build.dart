// tailscale native build hook.
//
// Compiles the Go tsnet library into a platform-appropriate native library
// and registers it as a native code asset. Runs automatically during
// `dart run` or `flutter build`.
//
// Requires a Go installation capable of selecting the version in go/go.mod.
//
// How the pieces connect:
//
//   1. This hook compiles Go → shared/static library, registered under the
//      asset name 'src/ffi_bindings.dart'.
//
//   2. In Dart, @ffi.DefaultAsset('package:tailscale/src/ffi_bindings.dart')
//      tells FFI to load the library registered under that same name.
//
//   3. The Dart toolchain matches them — @Native external functions in Dart
//      resolve to the compiled Go/C functions.
//
// Platform-specific handling:
//   - iOS: builds a static archive (c-archive) with Xcode toolchain.
//   - Android: builds a shared library (c-shared) with NDK toolchain.
//   - macOS/Linux/Windows: builds a shared library (c-shared) with host toolchain.

import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:path/path.dart' as p;

import 'native_build_support.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    try {
      await _buildNativeAsset(input, output);
    } on NativeBuildException catch (error, stackTrace) {
      throw BuildError(
        message: error.message,
        wrappedException: error,
        wrappedTrace: stackTrace,
      );
    } catch (error, stackTrace) {
      throw BuildError(
        message: 'Unexpected Tailscale native build failure: $error',
        wrappedException: error,
        wrappedTrace: stackTrace,
      );
    }
  });
}

Future<void> _buildNativeAsset(
  BuildInput input,
  BuildOutputBuilder output,
) async {
  if (!input.config.buildCodeAssets) {
    return;
  }

  final targetOS = input.config.code.targetOS;
  final targetArch = input.config.code.targetArchitecture;
  final target = _toNativeBuildTarget(
    targetOS,
    targetArch,
    isIOSSimulator:
        targetOS == OS.iOS &&
        input.config.code.iOS.targetSdk.type == IOSSdk.iPhoneSimulator.type,
  );
  final packageRoot = input.packageRoot.toFilePath();
  final outDir = input.outputDirectory;

  final goos = target.goOperatingSystem;
  final goarch = target.goArchitecture;
  final isIOS = targetOS == OS.iOS;

  // Output filename
  final libName = targetOS.dylibFileName('tailscale');
  final libPath = outDir.resolve(libName).toFilePath();

  // Go source entry point
  final mainGo = p.join(packageRoot, 'go', 'cmd', 'dylib', 'main.go');
  final goDir = p.join(packageRoot, 'go');
  final goMod = File(p.join(goDir, 'go.mod'));

  // Some hook runners pass only a reduced environment. Go 1.26 requires a
  // writable cache location on Windows even for a dependency-only build.
  final env = ensureGoCacheEnvironment({
    ...Platform.environment,
    'GOOS': goos,
    'GOARCH': goarch,
    'CGO_ENABLED': '1',
    // Disable raw disco to avoid permission errors on Android/Linux.
    'TS_ENABLE_RAW_DISCO': 'false',
  });

  // Resolve and validate Go before considering any cached output. Invoking
  // `go env GOVERSION` from the module makes GOTOOLCHAIN=auto select the
  // exact toolchain required by go.mod.
  final goBin = await requireGoExecutable(_findGo);
  await enforceGoModuleRequirement(
    goExecutable: goBin,
    moduleDirectory: goDir,
    goMod: goMod,
    environment: env,
  );

  // Build flags
  final buildTags = <String>[];

  // Platform-specific toolchain setup
  if (targetOS == OS.android) {
    _configureAndroid(env, buildTags, targetArch);
  } else if (isIOS) {
    await _configureIOS(env, input.config.code.iOS, targetArch);
  } else if (targetOS == OS.macOS) {
    await _configureMacOS(env);
  }

  // iOS doesn't support c-shared. Build c-archive then convert to dylib
  // using clang. All other platforms use c-shared directly.
  final buildMode = isIOS ? 'c-archive' : 'c-shared';
  final goOutput = isIOS
      ? outDir.resolve('libtailscale.a').toFilePath()
      : libPath;

  // Idempotency: if the output library is valid for this target and newer
  // than every native build input, skip running `go build` entirely. This
  // matters beyond pure speed: on
  // Linux, rewriting an mmap'd .so under a process that has it loaded
  // crashes that process with SIGBUS. The Dart hooks framework can
  // re-invoke this hook from a subprocess while the parent test process
  // still has the .so mmap'd; short-circuiting here keeps the file
  // bit-for-bit stable across subprocess invocations.
  final goBuildInputs = _goBuildInputs(goDir);

  if (isNativeArtifactCacheUsable(
    artifact: File(libPath),
    inputs: goBuildInputs,
    target: target,
  )) {
    // Skip the build; just register the asset and dependencies below.
  } else {
    final goArgs = [
      'build',
      '-buildmode=$buildMode',
      if (buildTags.isNotEmpty) '-tags=${buildTags.join(',')}',
      '-o',
      goOutput,
      mainGo,
    ];

    await runGoBuildCommand(
      goExecutable: goBin,
      arguments: goArgs,
      workingDirectory: goDir,
      environment: env,
      target: target,
    );

    // On iOS, convert the static archive to a dynamic library.
    if (isIOS) {
      await _archiveToSharedLib(env, goOutput, libPath);
    }
  }

  final linkMode = DynamicLoadingBundled();

  // This is deliberately the last operation before registration. No failed,
  // empty, truncated, wrong-ABI, or export-incomplete artifact can escape.
  validateNativeArtifact(artifact: File(libPath), target: target);
  output.assets.code.add(
    CodeAsset(
      package: input.packageName,
      name: 'src/ffi_bindings.dart',
      file: Uri.file(libPath),
      linkMode: linkMode,
    ),
  );

  // Register native build inputs as dependencies so the hook re-runs on
  // Go source, cgo header/C, and module version changes.
  for (final source in goBuildInputs) {
    output.dependencies.add(source.uri);
  }
}

List<File> _goBuildInputs(String goDir) {
  const extensions = <String>{
    '.c',
    '.cc',
    '.cpp',
    '.cxx',
    '.go',
    '.h',
    '.hpp',
    '.m',
    '.mm',
    '.mod',
    '.s',
    '.sum',
    '.S',
  };
  return Directory(goDir)
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => extensions.contains(p.extension(f.path)))
      .toList(growable: false);
}

// ---------------------------------------------------------------------------
// Go toolchain
// ---------------------------------------------------------------------------

/// Finds the Go binary, checking PATH and common installation paths.
Future<String?> _findGo() async {
  // Try PATH first (works on all platforms)
  final whichCmd = Platform.isWindows ? 'where' : 'which';
  try {
    final whichResult = await Process.run(whichCmd, ['go']);
    if (whichResult.exitCode == 0) {
      return (whichResult.stdout as String)
          .trim()
          .split(RegExp(r'[\r\n]+'))
          .first;
    }
  } on ProcessException {
    // Continue through explicit installation locations below.
  }

  // Check GOROOT if set
  final goroot = Platform.environment['GOROOT'];
  if (goroot != null) {
    final bin = p.join(goroot, 'bin', Platform.isWindows ? 'go.exe' : 'go');
    if (File(bin).existsSync()) return bin;
  }

  // Common installation paths by platform
  final home =
      Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '';
  final candidates = [
    // Official installer default
    if (!Platform.isWindows) '/usr/local/go/bin/go',
    // Homebrew (Apple Silicon + Intel)
    if (Platform.isMacOS) '/opt/homebrew/bin/go',
    // User GOPATH
    if (home.isNotEmpty) p.join(home, 'go', 'bin', 'go'),
    // Windows defaults
    if (Platform.isWindows) r'C:\Go\bin\go.exe',
    if (Platform.isWindows) r'C:\Program Files\Go\bin\go.exe',
    if (Platform.isWindows) p.join(home, r'go\bin\go.exe'),
  ];

  // Homebrew Cellar (versioned) — only check if directory exists
  if (Platform.isMacOS) {
    final cellar = Directory('/usr/local/Cellar/go');
    if (cellar.existsSync()) {
      for (final d in cellar.listSync().whereType<Directory>()) {
        candidates.add(p.join(d.path, 'libexec', 'bin', 'go'));
      }
    }
  }

  for (final path in candidates) {
    if (File(path).existsSync()) return path;
  }

  return null;
}

// ---------------------------------------------------------------------------
// Platform mapping
// ---------------------------------------------------------------------------

NativeBuildTarget _toNativeBuildTarget(
  OS os,
  Architecture? architecture, {
  bool isIOSSimulator = false,
}) => NativeBuildTarget(
  isIOSSimulator: isIOSSimulator,
  operatingSystem: switch (os) {
    OS.android => NativeTargetOperatingSystem.android,
    OS.iOS => NativeTargetOperatingSystem.iOS,
    OS.linux => NativeTargetOperatingSystem.linux,
    OS.macOS => NativeTargetOperatingSystem.macOS,
    OS.windows => NativeTargetOperatingSystem.windows,
    _ => throw UnsupportedError('Unsupported target OS: $os'),
  },
  architecture: switch (architecture) {
    Architecture.arm64 => NativeTargetArchitecture.arm64,
    Architecture.x64 => NativeTargetArchitecture.x64,
    Architecture.arm => NativeTargetArchitecture.arm,
    Architecture.ia32 => NativeTargetArchitecture.ia32,
    _ => throw UnsupportedError(
      'Unsupported target architecture: $architecture',
    ),
  },
);

// ---------------------------------------------------------------------------
// Android NDK configuration
// ---------------------------------------------------------------------------

void _configureAndroid(
  Map<String, String> env,
  List<String> buildTags,
  Architecture? arch,
) {
  // Omit raw disco on Android to avoid socket permission issues.
  buildTags.add('ts_omit_listenrawdisco');
  // Android apps cannot rely on Linux route-table probes. Port mapping is not
  // required for the embedded userspace node and can trigger denied netlink or
  // /proc route reads on modern Android.
  buildTags.add('ts_omit_portmapper');

  final ndkHome = _findAndroidNDK();
  if (ndkHome == null) {
    throw const NativeBuildException(
      'Android NDK not found. Set ANDROID_NDK_HOME or ANDROID_HOME.\n'
      'Install it with `sdkmanager --install "ndk;<version>"`.',
    );
  }

  // Determine host OS for toolchain path
  final hostOS = Platform.isWindows
      ? 'windows-x86_64'
      : Platform.isMacOS
      ? 'darwin-x86_64'
      : 'linux-x86_64';
  final toolchain = p.join(ndkHome, 'toolchains', 'llvm', 'prebuilt', hostOS);

  const apiLevel = 24;

  // Map Dart architecture to NDK clang target triple
  final ccTarget = switch (arch) {
    Architecture.arm64 => 'aarch64-linux-android',
    Architecture.arm => 'armv7a-linux-androideabi',
    Architecture.x64 => 'x86_64-linux-android',
    Architecture.ia32 => 'i686-linux-android',
    _ => throw UnsupportedError('Unsupported Android arch: $arch'),
  };

  env['CC'] = _requireCompilerFile(
    p.join(toolchain, 'bin', '$ccTarget$apiLevel-clang'),
    'Android NDK C compiler',
  );
  env['CXX'] = _requireCompilerFile(
    p.join(toolchain, 'bin', '$ccTarget$apiLevel-clang++'),
    'Android NDK C++ compiler',
  );

  // Android 15+ devices may use 16 KB pages. Keep every LOAD segment in the
  // embedded shared library compatible with that ABI instead of inheriting the
  // NDK's 4 KB default.
  final linkerFlags = [
    env['CGO_LDFLAGS'],
    '-Wl,-z,max-page-size=16384',
    '-Wl,-z,common-page-size=16384',
  ].whereType<String>().where((flag) => flag.trim().isNotEmpty).join(' ');
  env['CGO_LDFLAGS'] = linkerFlags;
}

String _requireCompilerFile(String pathWithoutWindowsSuffix, String label) {
  final candidates = <String>[
    pathWithoutWindowsSuffix,
    if (Platform.isWindows) '$pathWithoutWindowsSuffix.cmd',
    if (Platform.isWindows) '$pathWithoutWindowsSuffix.exe',
  ];
  for (final candidate in candidates) {
    final file = File(candidate);
    if (FileSystemEntity.typeSync(candidate, followLinks: true) ==
            FileSystemEntityType.file &&
        file.lengthSync() > 0) {
      return candidate;
    }
  }
  throw NativeBuildException(
    '$label not found or empty. Expected one of: ${candidates.join(', ')}. '
    'Reinstall the target Android NDK.',
  );
}

String? _findAndroidNDK() {
  final ndkHome = Platform.environment['ANDROID_NDK_HOME'];
  if (ndkHome != null && Directory(ndkHome).existsSync()) return ndkHome;

  // Check ANDROID_HOME, ANDROID_SDK_ROOT, and common default locations.
  final candidates = [
    Platform.environment['ANDROID_HOME'],
    Platform.environment['ANDROID_SDK_ROOT'],
    if (Platform.isMacOS) '${Platform.environment['HOME']}/Library/Android/sdk',
    if (Platform.isLinux) '${Platform.environment['HOME']}/Android/Sdk',
    if (Platform.isWindows)
      '${Platform.environment['LOCALAPPDATA']}\\Android\\Sdk',
  ];

  for (final sdk in candidates) {
    if (sdk == null) continue;
    final ndkDir = Directory(p.join(sdk, 'ndk'));
    if (!ndkDir.existsSync()) continue;

    final versions =
        ndkDir.listSync().whereType<Directory>().map((d) => d.path).toList()
          ..sort();

    if (versions.isNotEmpty) return versions.last;
  }

  return null;
}

// ---------------------------------------------------------------------------
// iOS configuration
// ---------------------------------------------------------------------------

Future<void> _configureIOS(
  Map<String, String> env,
  IOSCodeConfig iOSConfig,
  Architecture? arch,
) async {
  final sdk = iOSConfig.targetSdk.type;
  final minVersion = iOSConfig.targetVersion.toString();
  final versionFlag = sdk == IOSSdk.iPhoneSimulator.type
      ? '-mios-simulator-version-min=$minVersion'
      : '-miphoneos-version-min=$minVersion';

  final cc = await _runXcrun(['--sdk', sdk, '--find', 'clang'], 'iOS clang');
  final cxx = await _runXcrun([
    '--sdk',
    sdk,
    '--find',
    'clang++',
  ], 'iOS clang++');
  final sdkPath = await _runXcrun([
    '--sdk',
    sdk,
    '--show-sdk-path',
  ], 'iOS SDK path');

  final archFlag = arch == Architecture.arm64 ? 'arm64' : 'x86_64';

  env['CC'] = cc;
  env['CXX'] = cxx;
  env['CGO_CFLAGS'] = '-isysroot $sdkPath -arch $archFlag $versionFlag';
  env['CGO_LDFLAGS'] = '-isysroot $sdkPath -arch $archFlag $versionFlag';
}

Future<void> _configureMacOS(Map<String, String> env) async {
  final cc = await _runXcrun(const ['--find', 'clang'], 'macOS clang');
  final cxx = await _runXcrun(const ['--find', 'clang++'], 'macOS clang++');
  final sdkRoot = Platform.environment['SDKROOT']?.trim().isNotEmpty == true
      ? Platform.environment['SDKROOT']!.trim()
      : await _runXcrun(const ['--show-sdk-path'], 'macOS SDK path');

  env['CC'] = cc;
  env['CXX'] = cxx;
  env['SDKROOT'] = sdkRoot;
  env['CGO_CFLAGS'] = '-isysroot $sdkRoot';
  // Flutter rewrites the dylib install name and needs spare load-command room.
  env['CGO_LDFLAGS'] = '-headerpad_max_install_names';
}

Future<String> _runXcrun(List<String> arguments, String description) async {
  late final ProcessResult result;
  try {
    result = await Process.run('xcrun', arguments);
  } on ProcessException catch (error) {
    throw NativeBuildException(
      'Failed to start xcrun while locating $description: ${error.message}. '
      'Install Xcode and its command-line tools.',
    );
  }
  final value = result.stdout.toString().trim();
  if (result.exitCode != 0 || value.isEmpty) {
    throw NativeBuildException(
      'Failed to locate $description with xcrun (exit ${result.exitCode}).\n'
      'stderr: ${result.stderr}\nstdout: ${result.stdout}',
    );
  }
  return value;
}

/// Converts a Go c-archive (.a) into a shared library (.dylib) using clang.
///
/// Go doesn't support c-shared on ios/arm64, but Flutter's native assets
/// system requires a dynamic library. This bridges the gap.
///
/// iOS-specific note: the resulting dylib must have an `@rpath`-relative
/// `LC_ID_DYLIB` install name so Flutter's iOS bundler can wrap it in
/// `tailscale.framework` and link it against `Runner.app`. Without an
/// explicit `-install_name`, clang stamps the absolute build-time path
/// (somewhere in `.dart_tool/hooks_runner/.../build/<hash>/`), which the
/// Flutter pipeline silently fails to rewrite — the framework never
/// makes it into `build/ios/.../*.framework`, and the final link against
/// `Runner` fails with `Undefined symbol: _Dune*`. Matches the pattern
/// used by `resqlite`'s hook (`-install_name @rpath/libresqlite.dylib`).
Future<void> _archiveToSharedLib(
  Map<String, String> env,
  String archivePath,
  String dylibPath,
) async {
  final cc = env['CC'];
  if (cc == null) {
    throw const NativeBuildException('C compiler not set for iOS build.');
  }

  final cflags = env['CGO_CFLAGS'] ?? '';
  final ldflags = env['CGO_LDFLAGS'] ?? '';

  final dylibName = p.basename(dylibPath);
  final args = [
    ...cflags.split(' ').where((s) => s.isNotEmpty),
    '-fpic',
    '-shared',
    '-Wl,-all_load',
    archivePath,
    '-framework',
    'CoreFoundation',
    '-framework',
    'Security',
    '-o',
    dylibPath,
    '-headerpad_max_install_names',
    '-install_name',
    '@rpath/$dylibName',
    ...ldflags.split(' ').where((s) => s.isNotEmpty),
  ];

  late final ProcessResult result;
  try {
    result = await Process.run(cc, args);
  } on ProcessException catch (error) {
    throw NativeBuildException(
      'Failed to start iOS linker `$cc`: ${error.message}',
    );
  }
  if (result.exitCode != 0) {
    throw NativeBuildException(
      'Failed to convert the iOS archive to a shared library '
      '(exit ${result.exitCode}).\n'
      'Command: $cc ${args.join(' ')}\n'
      'stderr: ${result.stderr}\n'
      'stdout: ${result.stdout}',
    );
  }
}
