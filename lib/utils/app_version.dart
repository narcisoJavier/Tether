import 'package:package_info_plus/package_info_plus.dart';

/// Resolves the installed app version at runtime from the platform (Android
/// package info), instead of a hardcoded constant.
///
/// The version is read once and cached for the lifetime of the session — it
/// never changes while the app is running. This keeps the update checker and
/// UI in sync with whatever version the APK was actually built as
/// (pubspec.yaml `version`), so they never drift.
class AppVersion {
  AppVersion._();

  /// Compile-time fallback matching pubspec.yaml version.
  static const String _fallbackVersion = '0.6.0+4';

  static String? _cached;

  /// Returns the installed version in "major.minor.patch+build" form (e.g. "0.4.0+2"),
  /// or the compile-time fallback if the platform lookup fails.
  static Future<String> get() async {
    if (_cached != null) return _cached!;
    try {
      final info = await PackageInfo.fromPlatform();
      final buildSuffix = info.buildNumber.isNotEmpty
          ? '+${info.buildNumber}'
          : '';
      _cached = '${info.version}$buildSuffix';
      return _cached!;
    } catch (_) {
      _cached = _fallbackVersion;
      return _cached!;
    }
  }

  /// Synchronous access to the last-resolved version, or the compile-time
  /// fallback if [get] hasn't been awaited yet.
  static String get current => _cached ?? _fallbackVersion;
}
