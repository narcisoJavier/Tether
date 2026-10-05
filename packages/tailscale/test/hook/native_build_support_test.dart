import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';

import '../../hook/native_build_support.dart';

part 'native_binary_fixtures.dart';

void main() {
  const androidX64 = NativeBuildTarget(
    operatingSystem: NativeTargetOperatingSystem.android,
    architecture: NativeTargetArchitecture.x64,
  );

  late Directory temporaryDirectory;

  setUp(() {
    temporaryDirectory = Directory.systemTemp.createTempSync(
      'tailscale_native_hook_test_',
    );
  });

  tearDown(() {
    temporaryDirectory.deleteSync(recursive: true);
  });

  group('native artifact validation', () {
    test(
      'a dynamic symbol unreachable through the ELF hash is not exported',
      () {
        final artifact = _writeElfFixture(
          File('${temporaryDirectory.path}/unreachable.so'),
          architecture: NativeTargetArchitecture.x64,
        );
        final bytes = artifact.readAsBytesSync();
        ByteData.sublistView(bytes).setUint32(0x208, 0, Endian.little);
        artifact.writeAsBytesSync(bytes);
        expect(
          () => validateNativeArtifact(artifact: artifact, target: androidX64),
          throwsA(
            isA<NativeBuildException>().having(
              (error) => error.message,
              'message',
              contains('DuneStart'),
            ),
          ),
        );
      },
    );
    test('short 64-bit ELF headers fail cleanly and invalidate the cache', () {
      final artifact = _writeElfFixture(
        File('${temporaryDirectory.path}/short.so'),
        architecture: NativeTargetArchitecture.x64,
      );
      final bytes = artifact.readAsBytesSync();
      for (var length = 52; length < 64; length++) {
        artifact.writeAsBytesSync(bytes.sublist(0, length));
        expect(
          () => validateNativeArtifact(artifact: artifact, target: androidX64),
          throwsA(isA<NativeBuildException>()),
          reason: 'length $length',
        );
        expect(
          isNativeArtifactCacheUsable(
            artifact: artifact,
            inputs: const [],
            target: androidX64,
          ),
          isFalse,
        );
      }
    });

    test(
      'embedded names cannot replace exported ELF, Mach-O, or PE functions',
      () {
        final exports = requiredDuneExports.toSet()..remove('DuneStart');
        final fixtures = <(File, NativeBuildTarget)>[
          (
            _writeElfFixture(
              File('${temporaryDirectory.path}/decoy.so'),
              architecture: NativeTargetArchitecture.x64,
              exports: exports,
            ),
            androidX64,
          ),
          (
            _writeMachOFixture(
              File('${temporaryDirectory.path}/decoy.dylib'),
              exports: exports,
            ),
            const NativeBuildTarget(
              operatingSystem: NativeTargetOperatingSystem.macOS,
              architecture: NativeTargetArchitecture.arm64,
            ),
          ),
          (
            _writePeFixture(
              File('${temporaryDirectory.path}/decoy.dll'),
              exports: exports,
            ),
            const NativeBuildTarget(
              operatingSystem: NativeTargetOperatingSystem.windows,
              architecture: NativeTargetArchitecture.x64,
            ),
          ),
        ];
        for (final (artifact, target) in fixtures) {
          artifact.writeAsBytesSync(
            ascii.encode('\x00DuneStart\x00'),
            mode: FileMode.append,
          );
          expect(
            () => validateNativeArtifact(artifact: artifact, target: target),
            throwsA(
              isA<NativeBuildException>().having(
                (error) => error.message,
                'message',
                contains('DuneStart'),
              ),
            ),
          );
          expect(
            isNativeArtifactCacheUsable(
              artifact: artifact,
              inputs: const [],
              target: target,
            ),
            isFalse,
          );
        }
      },
    );

    test('undefined, local and hidden ELF symbols are not exports', () {
      final artifact = _writeElfFixture(
        File('${temporaryDirectory.path}/visibility.so'),
        architecture: NativeTargetArchitecture.x64,
      );
      final original = artifact.readAsBytesSync();
      for (final (offset, value) in [
        (0x418 + 4, 0x02),
        (0x418 + 5, 2),
        (0x418 + 6, 0),
      ]) {
        final bytes = Uint8List.fromList(original)..[offset] = value;
        artifact.writeAsBytesSync(bytes);
        expect(
          () => validateNativeArtifact(artifact: artifact, target: androidX64),
          throwsA(
            isA<NativeBuildException>().having(
              (error) => error.message,
              'message',
              contains('DuneStart'),
            ),
          ),
        );
      }
    });

    test('rejects segment data beyond EOF for all three formats', () {
      final elf = _writeElfFixture(
        File('${temporaryDirectory.path}/bounds.so'),
        architecture: NativeTargetArchitecture.x64,
      );
      final mach = _writeMachOFixture(
        File('${temporaryDirectory.path}/bounds.dylib'),
      );
      final pe = _writePeFixture(File('${temporaryDirectory.path}/bounds.dll'));
      final fixtures = <(File, NativeBuildTarget, int, bool)>[
        (elf, androidX64, 64 + 32, true),
        (
          mach,
          const NativeBuildTarget(
            operatingSystem: NativeTargetOperatingSystem.macOS,
            architecture: NativeTargetArchitecture.arm64,
          ),
          80,
          true,
        ),
        (
          pe,
          const NativeBuildTarget(
            operatingSystem: NativeTargetOperatingSystem.windows,
            architecture: NativeTargetArchitecture.x64,
          ),
          328 + 16,
          false,
        ),
      ];
      for (final (artifact, target, offset, is64) in fixtures) {
        final bytes = artifact.readAsBytesSync();
        final data = ByteData.sublistView(bytes);
        if (is64) {
          data.setUint64(offset, bytes.length + 1, Endian.little);
        } else {
          data.setUint32(offset, bytes.length + 1, Endian.little);
        }
        artifact.writeAsBytesSync(bytes);
        expect(
          () => validateNativeArtifact(artifact: artifact, target: target),
          throwsA(isA<NativeBuildException>()),
        );
      }
    });

    test('Mach-O enforces macOS, iOS device, and iOS simulator identity', () {
      final file = File('${temporaryDirectory.path}/platform.dylib');
      final targets = <int, NativeBuildTarget>{
        1: const NativeBuildTarget(
          operatingSystem: NativeTargetOperatingSystem.macOS,
          architecture: NativeTargetArchitecture.arm64,
        ),
        2: const NativeBuildTarget(
          operatingSystem: NativeTargetOperatingSystem.iOS,
          architecture: NativeTargetArchitecture.arm64,
        ),
        7: const NativeBuildTarget(
          operatingSystem: NativeTargetOperatingSystem.iOS,
          architecture: NativeTargetArchitecture.arm64,
          isIOSSimulator: true,
        ),
      };
      for (final platform in targets.keys) {
        _writeMachOFixture(file, platform: platform);
        for (final entry in targets.entries) {
          expect(
            () => validateNativeArtifact(artifact: file, target: entry.value),
            entry.key == platform
                ? returnsNormally
                : throwsA(isA<NativeBuildException>()),
          );
        }
      }
    });

    test('rejects invalid Mach-O command and export-trie bounds', () {
      final file = _writeMachOFixture(
        File('${temporaryDirectory.path}/commands.dylib'),
      );
      const target = NativeBuildTarget(
        operatingSystem: NativeTargetOperatingSystem.macOS,
        architecture: NativeTargetArchitecture.arm64,
      );
      final original = file.readAsBytesSync();
      for (final (offset, value) in [
        (36, 0),
        (36, 0xfffffff8),
        (176, original.length),
        (180, original.length),
      ]) {
        final bytes = Uint8List.fromList(original);
        ByteData.sublistView(bytes).setUint32(offset, value, Endian.little);
        file.writeAsBytesSync(bytes);
        expect(
          () => validateNativeArtifact(artifact: file, target: target),
          throwsA(isA<NativeBuildException>()),
        );
      }
    });

    test('rejects PE missing export directory and invalid ordinals', () {
      final file = _writePeFixture(
        File('${temporaryDirectory.path}/exports.dll'),
      );
      const target = NativeBuildTarget(
        operatingSystem: NativeTargetOperatingSystem.windows,
        architecture: NativeTargetArchitecture.x64,
      );
      final original = file.readAsBytesSync();
      for (final (offset, value) in [
        (88 + 112, 0),
        (0x400 + 28, 0xffff0000),
        (0x400 + 40 + requiredDuneExports.length * 8, 0xffff),
      ]) {
        final bytes = Uint8List.fromList(original);
        ByteData.sublistView(bytes).setUint32(offset, value, Endian.little);
        file.writeAsBytesSync(bytes);
        expect(
          () => validateNativeArtifact(artifact: file, target: target),
          throwsA(isA<NativeBuildException>()),
        );
      }
    });

    test('accepts ELF tables for all supported CPU architectures', () {
      for (final architecture in NativeTargetArchitecture.values) {
        final artifact = _writeElfFixture(
          File('${temporaryDirectory.path}/${architecture.name}.so'),
          architecture: architecture,
        );
        expect(
          () => validateNativeArtifact(
            artifact: artifact,
            target: NativeBuildTarget(
              operatingSystem: NativeTargetOperatingSystem.android,
              architecture: architecture,
            ),
          ),
          returnsNormally,
        );
      }
    });
    test('rejects a zero-byte artifact', () {
      final artifact = File('${temporaryDirectory.path}/libtailscale.so')
        ..createSync();

      expect(
        () => validateNativeArtifact(artifact: artifact, target: androidX64),
        throwsA(
          isA<NativeBuildException>().having(
            (error) => error.message,
            'message',
            contains('empty'),
          ),
        ),
      );
    });

    test('rejects truncated and non-ELF artifacts', () {
      final truncated = File('${temporaryDirectory.path}/truncated.so')
        ..writeAsBytesSync(const [0x7f, 0x45, 0x4c, 0x46]);
      final text = File('${temporaryDirectory.path}/text.so')
        ..writeAsStringSync('not a native library');

      for (final artifact in [truncated, text]) {
        expect(
          () => validateNativeArtifact(artifact: artifact, target: androidX64),
          throwsA(isA<NativeBuildException>()),
          reason: artifact.path,
        );
      }
    });

    test('rejects a valid-format artifact for the wrong ABI', () {
      final artifact = _writeElfFixture(
        File('${temporaryDirectory.path}/libtailscale.so'),
        architecture: NativeTargetArchitecture.arm64,
      );

      expect(
        () => validateNativeArtifact(artifact: artifact, target: androidX64),
        throwsA(
          isA<NativeBuildException>().having(
            (error) => error.message,
            'message',
            anyOf(contains('class'), contains('machine')),
          ),
        ),
      );
    });

    test('rejects a binary with a missing required Dune export', () {
      final exports = requiredDuneExports.toSet()..remove('DuneStart');
      final artifact = _writeElfFixture(
        File('${temporaryDirectory.path}/libtailscale.so'),
        architecture: NativeTargetArchitecture.x64,
        exports: exports,
      );

      expect(
        () => validateNativeArtifact(artifact: artifact, target: androidX64),
        throwsA(
          isA<NativeBuildException>().having(
            (error) => error.message,
            'message',
            contains('DuneStart'),
          ),
        ),
      );
    });

    test('accepts a valid ELF artifact with all required exports', () {
      final artifact = _writeElfFixture(
        File('${temporaryDirectory.path}/libtailscale.so'),
        architecture: NativeTargetArchitecture.x64,
      );

      expect(
        () => validateNativeArtifact(artifact: artifact, target: androidX64),
        returnsNormally,
      );
    });

    test('accepts valid Mach-O and PE fixtures for their targets', () {
      final machO = _writeMachOFixture(
        File('${temporaryDirectory.path}/libtailscale.dylib'),
      );
      final pe = _writePeFixture(
        File('${temporaryDirectory.path}/tailscale.dll'),
      );

      expect(
        () => validateNativeArtifact(
          artifact: machO,
          target: const NativeBuildTarget(
            operatingSystem: NativeTargetOperatingSystem.macOS,
            architecture: NativeTargetArchitecture.arm64,
          ),
        ),
        returnsNormally,
      );
      expect(
        () => validateNativeArtifact(
          artifact: pe,
          target: const NativeBuildTarget(
            operatingSystem: NativeTargetOperatingSystem.windows,
            architecture: NativeTargetArchitecture.x64,
          ),
        ),
        returnsNormally,
      );
    });
  });

  group('native cache freshness', () {
    test('accepts a fresh valid fixture without rebuilding', () {
      final input = File('${temporaryDirectory.path}/input.go')
        ..writeAsStringSync('package tailscale');
      final artifact = _writeElfFixture(
        File('${temporaryDirectory.path}/libtailscale.so'),
        architecture: NativeTargetArchitecture.x64,
      );
      input.setLastModifiedSync(DateTime.utc(2025));
      artifact.setLastModifiedSync(DateTime.utc(2025, 1, 2));

      expect(
        isNativeArtifactCacheUsable(
          artifact: artifact,
          inputs: [input],
          target: androidX64,
        ),
        isTrue,
      );
    });

    test('rejects a stale otherwise-valid fixture', () {
      final input = File('${temporaryDirectory.path}/input.go')
        ..writeAsStringSync('package tailscale');
      final artifact = _writeElfFixture(
        File('${temporaryDirectory.path}/libtailscale.so'),
        architecture: NativeTargetArchitecture.x64,
      );
      artifact.setLastModifiedSync(DateTime.utc(2025));
      input.setLastModifiedSync(DateTime.utc(2025, 1, 2));

      expect(
        isNativeArtifactCacheUsable(
          artifact: artifact,
          inputs: [input],
          target: androidX64,
        ),
        isFalse,
      );
    });

    test('rejects a fresh but invalid fixture', () {
      final input = File('${temporaryDirectory.path}/input.go')
        ..writeAsStringSync('package tailscale');
      final artifact = File('${temporaryDirectory.path}/libtailscale.so')
        ..createSync();
      input.setLastModifiedSync(DateTime.utc(2025));
      artifact.setLastModifiedSync(DateTime.utc(2025, 1, 2));

      expect(
        isNativeArtifactCacheUsable(
          artifact: artifact,
          inputs: [input],
          target: androidX64,
        ),
        isFalse,
      );
    });
  });

  group('Go toolchain failures', () {
    test('derives a Windows Go cache when the hook environment is reduced', () {
      final environment = ensureGoCacheEnvironment(const {
        'USERPROFILE': r'C:\Users\test',
        'TEMP': r'C:\Temp',
      }, isWindows: true);

      expect(environment['LOCALAPPDATA'], r'C:\Users\test\AppData\Local');
      expect(environment['GOCACHE'], r'C:\Users\test\AppData\Local\go-build');
    });

    test('preserves explicit Windows cache settings', () {
      final environment = ensureGoCacheEnvironment(const {
        'LOCALAPPDATA': r'C:\Cache',
        'GOCACHE': r'C:\GoCache',
        'USERPROFILE': r'C:\Users\test',
      }, isWindows: true);

      expect(environment['LOCALAPPDATA'], r'C:\Cache');
      expect(environment['GOCACHE'], r'C:\GoCache');
    });

    test('does not alter non-Windows environments', () {
      const environment = {'USERPROFILE': r'C:\Users\test'};
      expect(
        ensureGoCacheEnvironment(environment, isWindows: false),
        environment,
      );
    });

    test('passes multi-part CC commands unchanged to Go', () async {
      const compiler = 'ccache clang --target=x86_64-linux-gnu';
      Future<ProcessResult> runner(
        String executable,
        List<String> arguments, {
        String? workingDirectory,
        Map<String, String>? environment,
      }) async {
        expect(environment?['CC'], compiler);
        return ProcessResult(1, 0, '', '');
      }

      await runGoBuildCommand(
        goExecutable: 'go',
        arguments: const ['build'],
        workingDirectory: temporaryDirectory.path,
        environment: const {'CC': compiler},
        target: androidX64,
        processRunner: runner,
      );
    });
    test('missing Go is fatal', () async {
      await expectLater(
        requireGoExecutable(() async => null),
        throwsA(
          isA<NativeBuildException>().having(
            (error) => error.message,
            'message',
            contains('not found'),
          ),
        ),
      );
    });

    test('failed Go build is fatal', () async {
      Future<ProcessResult> failedRunner(
        String executable,
        List<String> arguments, {
        String? workingDirectory,
        Map<String, String>? environment,
      }) async => ProcessResult(17, 2, 'compile output', 'compile failure');

      await expectLater(
        runGoBuildCommand(
          goExecutable: 'go',
          arguments: const ['build'],
          workingDirectory: temporaryDirectory.path,
          environment: const {},
          target: androidX64,
          processRunner: failedRunner,
        ),
        throwsA(
          isA<NativeBuildException>().having(
            (error) => error.message,
            'message',
            allOf(contains('Go build failed'), contains('compile failure')),
          ),
        ),
      );
    });

    test('enforces the full go.mod version requirement', () async {
      final goMod = File('${temporaryDirectory.path}/go.mod')
        ..writeAsStringSync('module example.invalid/test\n\ngo 1.26.4\n');

      Future<ProcessResult> oldVersionRunner(
        String executable,
        List<String> arguments, {
        String? workingDirectory,
        Map<String, String>? environment,
      }) async => ProcessResult(18, 0, 'go1.26.3\n', '');

      await expectLater(
        enforceGoModuleRequirement(
          goExecutable: 'go',
          moduleDirectory: temporaryDirectory.path,
          goMod: goMod,
          processRunner: oldVersionRunner,
        ),
        throwsA(
          isA<NativeBuildException>().having(
            (error) => error.message,
            'message',
            allOf(contains('1.26.4'), contains('1.26.3')),
          ),
        ),
      );
    });
  });
}
