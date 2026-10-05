import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

part 'native_binary_validation.dart';

/// Adds Windows Go cache locations when the host strips standard environment
/// variables before launching the native build hook.
Map<String, String> ensureGoCacheEnvironment(
  Map<String, String> environment, {
  bool? isWindows,
}) {
  final result = <String, String>{...environment};
  if (!(isWindows ?? Platform.isWindows)) return result;

  final localAppData = result['LOCALAPPDATA']?.trim();
  if (localAppData == null || localAppData.isEmpty) {
    final userProfile = result['USERPROFILE']?.trim();
    if (userProfile != null && userProfile.isNotEmpty) {
      result['LOCALAPPDATA'] = p.join(userProfile, 'AppData', 'Local');
    }
  }

  final goCache = result['GOCACHE']?.trim();
  if (goCache == null || goCache.isEmpty) {
    final cacheRoot = result['LOCALAPPDATA']?.trim();
    if (cacheRoot != null && cacheRoot.isNotEmpty) {
      result['GOCACHE'] = p.join(cacheRoot, 'go-build');
    } else {
      final temp = result['TEMP']?.trim();
      if (temp != null && temp.isNotEmpty) {
        result['GOCACHE'] = p.join(temp, 'go-build');
      }
    }
  }
  return result;
}

/// Operating systems supported by the Tailscale native build hook.
enum NativeTargetOperatingSystem { android, iOS, linux, macOS, windows }

/// Architectures supported by the Tailscale native build hook.
enum NativeTargetArchitecture { arm64, x64, arm, ia32 }

/// The native platform and architecture expected for one build artifact.
class NativeBuildTarget {
  /// Creates a native build target.
  const NativeBuildTarget({
    required this.operatingSystem,
    required this.architecture,
    this.isIOSSimulator = false,
  });

  /// Target operating system.
  final NativeTargetOperatingSystem operatingSystem;

  /// Target CPU architecture.
  final NativeTargetArchitecture architecture;

  /// Whether an iOS artifact must target the simulator SDK.
  final bool isIOSSimulator;

  /// Go's operating-system identifier for this target.
  String get goOperatingSystem => switch (operatingSystem) {
    NativeTargetOperatingSystem.android => 'android',
    NativeTargetOperatingSystem.iOS => 'ios',
    NativeTargetOperatingSystem.linux => 'linux',
    NativeTargetOperatingSystem.macOS => 'darwin',
    NativeTargetOperatingSystem.windows => 'windows',
  };

  /// Go's architecture identifier for this target.
  String get goArchitecture => switch (architecture) {
    NativeTargetArchitecture.arm64 => 'arm64',
    NativeTargetArchitecture.x64 => 'amd64',
    NativeTargetArchitecture.arm => 'arm',
    NativeTargetArchitecture.ia32 => '386',
  };

  @override
  String toString() => '$goOperatingSystem/$goArchitecture';
}

/// Every C symbol consumed by `lib/src/ffi_bindings.dart`.
const requiredDuneExports = <String>{
  'DuneStart',
  'DuneSetNetworkInterfaces',
  'DuneHttpStart',
  'DuneHttpBind',
  'DuneHttpAccept',
  'DuneHttpCloseBinding',
  'DuneTcpDialFd',
  'DuneTcpListenFd',
  'DuneTlsListenFd',
  'DuneTcpAcceptFd',
  'DuneTcpCloseFdListener',
  'DuneUdpBindFd',
  'DuneReactorCreate',
  'DuneReactorClose',
  'DuneReactorWake',
  'DuneReactorRegister',
  'DuneReactorUpdate',
  'DuneReactorUnregister',
  'DuneReactorWait',
  'DuneWhoIs',
  'DuneTlsDomains',
  'DuneDiagPing',
  'DuneDiagMetrics',
  'DuneDiagDERPMap',
  'DuneDiagCheckUpdate',
  'DuneHasState',
  'DuneLogout',
  'DuneStop',
  'DuneStatus',
  'DunePeers',
  'DunePrefsGet',
  'DunePrefsUpdate',
  'DuneExitNodeSuggest',
  'DuneExitNodeUseAuto',
  'DuneServeForward',
  'DuneServeClear',
  'DuneFree',
  'DuneSetLogLevel',
  'DuneInitDartAPI',
  'DuneSetDartPort',
  'DuneStartWatch',
  'DuneStopWatch',
};

/// A fatal native build or artifact validation failure.
class NativeBuildException implements Exception {
  /// Creates a native build exception with an actionable [message].
  const NativeBuildException(this.message);

  /// Description of the failed build invariant.
  final String message;

  @override
  String toString() => 'NativeBuildException: $message';
}

/// A semantic Go toolchain version.
class GoToolchainVersion implements Comparable<GoToolchainVersion> {
  /// Creates a Go toolchain version.
  const GoToolchainVersion(this.major, this.minor, this.patch);

  /// Major component.
  final int major;

  /// Minor component.
  final int minor;

  /// Patch component.
  final int patch;

  @override
  int compareTo(GoToolchainVersion other) {
    final majorResult = major.compareTo(other.major);
    if (majorResult != 0) return majorResult;
    final minorResult = minor.compareTo(other.minor);
    if (minorResult != 0) return minorResult;
    return patch.compareTo(other.patch);
  }

  @override
  String toString() => '$major.$minor.$patch';
}

/// Signature used to replace process execution in hook unit tests.
typedef NativeProcessRunner =
    Future<ProcessResult> Function(
      String executable,
      List<String> arguments, {
      String? workingDirectory,
      Map<String, String>? environment,
    });

/// Runs a process using [Process.run].
Future<ProcessResult> runNativeProcess(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  Map<String, String>? environment,
}) => Process.run(
  executable,
  arguments,
  workingDirectory: workingDirectory,
  environment: environment,
);

/// Returns the located Go executable or fails instead of creating a stub.
Future<String> requireGoExecutable(Future<String?> Function() locateGo) async {
  final executable = await locateGo();
  if (executable == null || executable.trim().isEmpty) {
    throw const NativeBuildException(
      'Go toolchain not found. Install the version required by go/go.mod '
      'from https://go.dev/dl/ and ensure `go` is on PATH.',
    );
  }
  return executable;
}

/// Reads the Go version required by a module's `go.mod` directive.
GoToolchainVersion readGoModuleRequirement(File goMod) {
  if (!goMod.existsSync()) {
    throw NativeBuildException('Go module file not found: ${goMod.path}');
  }
  final match = RegExp(
    r'^\s*go\s+(\d+)\.(\d+)(?:\.(\d+))?\s*(?://.*)?$',
    multiLine: true,
  ).firstMatch(goMod.readAsStringSync());
  if (match == null) {
    throw NativeBuildException(
      'Could not read the Go version requirement from ${goMod.path}.',
    );
  }
  return GoToolchainVersion(
    int.parse(match.group(1)!),
    int.parse(match.group(2)!),
    int.parse(match.group(3) ?? '0'),
  );
}

/// Parses output such as `go1.26.4` or `go version go1.26.4 ...`.
GoToolchainVersion parseGoToolchainVersion(String output) {
  final match = RegExp(r'go(\d+)\.(\d+)(?:\.(\d+))?').firstMatch(output.trim());
  if (match == null) {
    throw NativeBuildException(
      'Could not parse the selected Go toolchain version from: $output',
    );
  }
  return GoToolchainVersion(
    int.parse(match.group(1)!),
    int.parse(match.group(2)!),
    int.parse(match.group(3) ?? '0'),
  );
}

/// Makes Go select the module toolchain and enforces the `go.mod` requirement.
Future<GoToolchainVersion> enforceGoModuleRequirement({
  required String goExecutable,
  required String moduleDirectory,
  required File goMod,
  Map<String, String>? environment,
  NativeProcessRunner processRunner = runNativeProcess,
}) async {
  final requiredVersion = readGoModuleRequirement(goMod);
  late final ProcessResult result;
  try {
    result = await processRunner(
      goExecutable,
      const ['env', 'GOVERSION'],
      workingDirectory: moduleDirectory,
      environment: environment,
    );
  } on ProcessException catch (error) {
    throw NativeBuildException(
      'Failed to start Go at `$goExecutable`: ${error.message}',
    );
  }
  if (result.exitCode != 0) {
    throw NativeBuildException(
      'Go cannot select the toolchain required by ${goMod.path} '
      '(go $requiredVersion).\n'
      'Enable GOTOOLCHAIN=auto or install Go $requiredVersion or newer.\n'
      'stderr: ${result.stderr}\nstdout: ${result.stdout}',
    );
  }
  final selectedVersion = parseGoToolchainVersion(result.stdout.toString());
  if (selectedVersion.compareTo(requiredVersion) < 0) {
    throw NativeBuildException(
      'Go $requiredVersion or newer is required by ${goMod.path}, but '
      '`$goExecutable` selected Go $selectedVersion. Enable '
      'GOTOOLCHAIN=auto or install a compatible toolchain.',
    );
  }
  return selectedVersion;
}

/// Runs `go build` and turns start or compile failures into fatal errors.
Future<void> runGoBuildCommand({
  required String goExecutable,
  required List<String> arguments,
  required String workingDirectory,
  required Map<String, String> environment,
  required NativeBuildTarget target,
  NativeProcessRunner processRunner = runNativeProcess,
}) async {
  late final ProcessResult result;
  try {
    result = await processRunner(
      goExecutable,
      arguments,
      workingDirectory: workingDirectory,
      environment: environment,
    );
  } on ProcessException catch (error) {
    throw NativeBuildException(
      'Failed to start Go build with `$goExecutable`: ${error.message}',
    );
  }
  if (result.exitCode != 0) {
    throw NativeBuildException(
      'Go build failed (exit ${result.exitCode}).\n'
      'Command: $goExecutable ${arguments.join(' ')}\n'
      'Target: $target\n'
      'stderr: ${result.stderr}\nstdout: ${result.stdout}',
    );
  }
}

/// Validates binary structure and exported function tables for [target].
///
/// The check rejects non-regular and empty files, malformed or truncated
/// headers, wrong CPU ABIs, non-library binaries, and missing required FFI
/// exports. It throws [NativeBuildException] on the first violated invariant.
void validateNativeArtifact({
  required File artifact,
  required NativeBuildTarget target,
  Set<String> requiredExports = requiredDuneExports,
}) {
  final entityType = FileSystemEntity.typeSync(
    artifact.path,
    followLinks: false,
  );
  if (entityType != FileSystemEntityType.file) {
    throw NativeBuildException(
      'Native artifact is not a regular file: ${artifact.path}',
    );
  }
  final stat = artifact.statSync();
  if (stat.size == 0) {
    throw NativeBuildException('Native artifact is empty: ${artifact.path}');
  }

  final randomAccessFile = artifact.openSync();
  try {
    final reader = _BinaryReader(randomAccessFile, stat.size, artifact.path);
    final exports = switch (target.operatingSystem) {
      NativeTargetOperatingSystem.android ||
      NativeTargetOperatingSystem.linux => _elfExports(reader, target),
      NativeTargetOperatingSystem.iOS ||
      NativeTargetOperatingSystem.macOS => _machOExports(reader, target),
      NativeTargetOperatingSystem.windows => _peExports(reader, target),
    };
    final missing = requiredExports.difference(exports).toList()..sort();
    if (missing.isNotEmpty) {
      throw NativeBuildException(
        'Native artifact is missing required Dune exports: '
        '${missing.join(', ')}. Artifact: ${artifact.path}',
      );
    }
  } finally {
    randomAccessFile.closeSync();
  }
}

/// Returns whether a cache is both structurally valid and newer than inputs.
///
/// Timestamp freshness is never sufficient on its own: the full binary and
/// export validation in [validateNativeArtifact] must also succeed.
bool isNativeArtifactCacheUsable({
  required File artifact,
  required Iterable<File> inputs,
  required NativeBuildTarget target,
  Set<String> requiredExports = requiredDuneExports,
}) {
  try {
    validateNativeArtifact(
      artifact: artifact,
      target: target,
      requiredExports: requiredExports,
    );
    final outputModified = artifact.statSync().modified;
    for (final input in inputs) {
      if (!input.existsSync() ||
          input.statSync().modified.isAfter(outputModified)) {
        return false;
      }
    }
    return true;
  } on FileSystemException {
    return false;
  } on NativeBuildException {
    return false;
  }
}
