# Android Release Checklist

Review [privacy and data handling](PRIVACY_DATA_SAFETY.md) against the exact release build before completing any store or distribution disclosures. It documents the implemented local storage, encrypted backup scope, Android backup setting, and current telemetry boundaries; it is not a legal policy or a substitute for store declarations.

This checklist is a blocking release gate for the packaged Tailscale native library. A successful Flutter or Go build, an installed NDK version, and the presence of a file named `libtailscale.so` are not evidence that the shipped artifact is valid.

## Required local tools

- PowerShell (`pwsh` is recommended).
- Android NDK with `llvm-readelf`.
- Android SDK Build Tools with a `zipalign` version that supports `-P 16`.
- Java and a bundletool JAR when releasing an Android App Bundle.
- Flutter and the Go toolchain required by `packages/tailscale/go/go.mod` for the build itself.

The verifier searches explicit arguments first, then `PATH`, Android environment variables, SDK/NDK version directories, and `android/local.properties`. Use these overrides when discovery is ambiguous:

```powershell
pwsh -File .\tool\verify_android_native_artifacts.ps1 `
  -ArtifactPath .\build\app\outputs\flutter-apk\app-release.apk `
  -AndroidSdkPath 'D:\Android\Sdk' `
  -AndroidNdkPath 'D:\Android\Sdk\ndk\28.2.13676358'
```

`-LlvmReadElfPath` and `-ZipAlignPath` can point directly to the executables. A missing verification tool is a gate failure, not a warning.

## APK release gate

1. Build the release APK using the normal release-signing setup. Do not put keystore passwords or private keys in source control or command output.

   ```powershell
   flutter clean
   flutter pub get
   flutter build apk --release
   ```

2. Inspect the produced APK itself.

   ```powershell
   pwsh -File .\tool\verify_android_native_artifacts.ps1 `
     -ArtifactPath .\build\app\outputs\flutter-apk\app-release.apk
   if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
   ```

The default expected ABI set is `armeabi-v7a`, `arm64-v8a`, and `x86_64`, matching this app's documented Android targets. For an intentionally ABI-specific APK, provide the exact set, for example:

```powershell
pwsh -File .\tool\verify_android_native_artifacts.ps1 `
  -ArtifactPath .\build\app\outputs\flutter-apk\app-arm64-v8a-release.apk `
  -ExpectedAbi arm64-v8a
```

Do not narrow `-ExpectedAbi` merely to make an unexpected package pass. The release artifact and its declared ABI scope must agree.

## AAB release gate

An AAB is not directly installable, so checking only its ZIP entries cannot prove the alignment of the APK delivered to a device. The verifier therefore requires both the AAB and a universal APK set generated from that exact bundle.

1. Build the release bundle.

   ```powershell
   flutter build appbundle --release
   ```

2. Generate a universal APK set with bundletool. Keep signing material and password files outside the repository. The placeholders below are not project credentials.

   ```powershell
   java -jar 'C:\tools\bundletool-all.jar' build-apks `
     --bundle='.\build\app\outputs\bundle\release\app-release.aab' `
     --output='.\build\app\outputs\bundle\release\app-release.apks' `
     --mode=universal `
     --ks='C:\secure\release-keystore.jks' `
     --ks-key-alias='YOUR_ALIAS' `
     --ks-pass='file:C:\secure\keystore-password.txt' `
     --key-pass='file:C:\secure\key-password.txt' `
     --overwrite
   if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
   ```

3. Verify the AAB, the bundletool-generated universal APK, and their relationship.

   ```powershell
   pwsh -File .\tool\verify_android_native_artifacts.ps1 `
     -ArtifactPath .\build\app\outputs\bundle\release\app-release.aab `
     -ApkSetPath .\build\app\outputs\bundle\release\app-release.apks
   if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
   ```

The command fails if the APK set was not generated in universal mode or if any `libtailscale.so` differs byte-for-byte between the AAB and universal APK. Passing an AAB without `-ApkSetPath` intentionally exits nonzero after bundle inspection and explains the missing invocation.

An APK set can also be checked on its own:

```powershell
pwsh -File .\tool\verify_android_native_artifacts.ps1 `
  -ArtifactPath .\build\app\outputs\bundle\release\app-release.apks
```

## What the gate proves

For every expected ABI, the verifier checks the artifact rather than build intermediates:

- The ABI is actually packaged and has exactly one library at `lib/<abi>/libtailscale.so` in an APK or `base/lib/<abi>/libtailscale.so` in an AAB.
- The entry is non-empty and extracts without truncation.
- The payload has a complete little-endian ELF shared-object header with the class and machine matching its Android ABI directory.
- Android NDK `llvm-readelf` can parse its program headers and every `LOAD` segment has a power-of-two alignment of at least `0x4000`.
- Android NDK `llvm-readelf` reports every `Dune*` symbol consumed by the Dart FFI bindings as a defined dynamic export.
- Every installable APK passes `zipalign -c -P 16 -v 4`.
- A companion universal APK contains the same native bytes as its AAB.

Any missing, empty, malformed, wrong-ABI, duplicate, export-incomplete, 4 KB-aligned, or ZIP-misaligned payload exits nonzero.

## Verifier self-test

Run the deterministic negative fixtures before relying on verifier changes:

```powershell
pwsh -File .\tool\test_verify_android_native_artifacts.ps1
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
```

Run the Android release-configuration preflight as well:

```powershell
pwsh -File .\tool\test_verify_android_release_config.ps1
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
```

This checks backup policy, biometric permission, cold-boot themes, adaptive icons,
release signing configuration, minification, resource shrinking, and ignored signing files.

The self-test covers missing, zero-byte, non-ELF, truncated ELF, wrong-machine, 4 KB `LOAD` alignment, and missing-export artifacts. If the checked-in `release/Tether-v0.6.1.apk` is present, it also proves that the seeded zero-byte Tailscale payload is rejected.

## External release checks

The local artifact gate does not replace runtime validation or store processing:

- Install the verified APK on a 16 KB page-size Android test device or emulator.
- Confirm `adb shell getconf PAGE_SIZE` reports `16384` for that test run.
- Launch Tether, exercise Tailscale initialization, and complete an SSH-over-tailnet smoke test without exposing authentication material in logs.
- Retain the exact verified artifact and its checksum for the release record.
- Treat Google Play's generated-APK and pre-launch results as an additional gate after an authorized upload. This checklist does not authorize or perform an upload.

Do not publish when any local or external gate is incomplete.

## Latest local evidence

The current workspace has passed the following local gates:

- Signed release APK build and native verification for `armeabi-v7a`, `arm64-v8a`, and `x86_64`.
- Signed release AAB build.
- Bundletool 1.18.3 universal APK generation and byte-for-byte AAB/native payload verification.
- 16 KB ELF LOAD alignment, required Dune exports, and `zipalign -P 16` checks.
- Release APK install/launch smoke on the `Pixel_6a` 16 KB emulator (`PAGE_SIZE=16384`) with no fatal app crash.

The generated artifacts remain under `build/` and are not a substitute for the external device and Play checks above.
