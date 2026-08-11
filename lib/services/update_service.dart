import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:pub_semver/pub_semver.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/app_version.dart';
import '../utils/constants.dart';

/// Holds information about a pending app update from GitHub Releases.
class UpdateInfo {
  final String latestVersion;
  final String downloadUrl;
  final String releaseNotes;

  const UpdateInfo({
    required this.latestVersion,
    required this.downloadUrl,
    required this.releaseNotes,
  });

  Map<String, dynamic> toJson() => {
        'latestVersion': latestVersion,
        'downloadUrl': downloadUrl,
        'releaseNotes': releaseNotes,
      };

  factory UpdateInfo.fromJson(Map<String, dynamic> json) => UpdateInfo(
        latestVersion: json['latestVersion'] as String? ?? '',
        downloadUrl: json['downloadUrl'] as String? ?? '',
        releaseNotes: json['releaseNotes'] as String? ?? '',
      );
}

/// Checks the GitHub Releases API for newer versions of the app.
class UpdateService {
  UpdateService._();

  /// Timeout for the GitHub API call.
  static const Duration _timeout = Duration(seconds: 10);

  /// 24-hour cache duration to prevent exceeding GitHub API rate limits.
  static const Duration _cacheDuration = Duration(hours: 24);

  /// Returns [UpdateInfo] when a newer release is available, or `null` if the
  /// app is up-to-date, the API fails, or the user is offline.
  ///
  /// Set [force] to `true` to bypass the 24-hour cache check (e.g. manual check).
  static Future<UpdateInfo?> checkForUpdate({bool force = false}) async {
    SharedPreferences? prefs;
    try {
      prefs = await SharedPreferences.getInstance();
    } catch (e) {
      debugPrint('[UpdateService] Failed to load SharedPreferences: $e');
    }

    // Check 24-hour cache if force is false
    if (!force && prefs != null) {
      final lastCheckMillis = prefs.getInt(AppConstants.lastUpdateCheckKey) ?? 0;
      final elapsed = DateTime.now().millisecondsSinceEpoch - lastCheckMillis;
      if (elapsed < _cacheDuration.inMilliseconds) {
        final cachedJsonStr = prefs.getString(AppConstants.cachedUpdateInfoKey);
        if (cachedJsonStr != null && cachedJsonStr.isNotEmpty) {
          try {
            final jsonMap = json.decode(cachedJsonStr) as Map<String, dynamic>;
            final cachedInfo = UpdateInfo.fromJson(jsonMap);
            final installedVersion = await AppVersion.get();
            if (isNewer(cachedInfo.latestVersion, installedVersion)) {
              return cachedInfo;
            }
          } catch (_) {
            // Ignore cache parse error
          }
        }
        return null; // Checked recently and no update was cached
      }
    }

    try {
      final uri = Uri.parse(
        'https://api.github.com/repos/'
        '${AppConstants.gitHubOwner}/${AppConstants.gitHubRepo}'
        '/releases/latest',
      );

      final headers = <String, String>{
        'Accept': 'application/vnd.github.v3+json',
      };

      final etag = prefs?.getString(AppConstants.updateEtagKey);
      if (etag != null && etag.isNotEmpty) {
        headers['If-None-Match'] = etag;
      }

      final response = await http.get(uri, headers: headers).timeout(_timeout);

      // Save check timestamp
      await prefs?.setInt(
        AppConstants.lastUpdateCheckKey,
        DateTime.now().millisecondsSinceEpoch,
      );

      // Handle 304 Not Modified (cached ETag still valid)
      if (response.statusCode == 304 && prefs != null) {
        final cachedJsonStr = prefs.getString(AppConstants.cachedUpdateInfoKey);
        if (cachedJsonStr != null && cachedJsonStr.isNotEmpty) {
          final jsonMap = json.decode(cachedJsonStr) as Map<String, dynamic>;
          final cachedInfo = UpdateInfo.fromJson(jsonMap);
          final installedVersion = await AppVersion.get();
          if (isNewer(cachedInfo.latestVersion, installedVersion)) {
            return cachedInfo;
          }
        }
        return null;
      }

      if (response.statusCode != 200) return null;

      // Save new ETag if present
      final newEtag = response.headers['etag'];
      if (newEtag != null && newEtag.isNotEmpty) {
        await prefs?.setString(AppConstants.updateEtagKey, newEtag);
      }

      final body = json.decode(response.body) as Map<String, dynamic>;
      final tagName = body['tag_name'] as String? ?? '';
      final releaseBody = body['body'] as String? ?? '';

      // Strip leading 'v' if present (e.g. "v0.4.0" → "0.4.0").
      final remoteVersion = tagName.replaceFirst(RegExp(r'^v'), '');
      final installedVersion = await AppVersion.get();

      if (!isNewer(remoteVersion, installedVersion)) {
        await prefs?.remove(AppConstants.cachedUpdateInfoKey);
        return null;
      }

      // Find the first APK asset in the release.
      final assets = body['assets'] as List<dynamic>?;
      String downloadUrl = '';
      if (assets != null) {
        for (final asset in assets) {
          final name = (asset['name'] as String? ?? '').toLowerCase();
          if (name.endsWith('.apk')) {
            downloadUrl = asset['browser_download_url'] as String? ?? '';
            break;
          }
        }
      }

      // Fall back to html_url if no APK asset is found.
      if (downloadUrl.isEmpty) {
        downloadUrl = body['html_url'] as String? ?? '';
      }

      final updateInfo = UpdateInfo(
        latestVersion: remoteVersion,
        downloadUrl: downloadUrl,
        releaseNotes: releaseBody.trim(),
      );

      // Cache pending update info
      await prefs?.setString(
        AppConstants.cachedUpdateInfoKey,
        json.encode(updateInfo.toJson()),
      );

      return updateInfo;
    } catch (e) {
      debugPrint('[UpdateService] Update check failed: $e');
      return null;
    }
  }

  /// Parses a version tag into a [Version] object using [pub_semver].
  ///
  /// Normalizes short tags like `0.4` or `v0.4` into `0.4.0`.
  /// Returns `null` if parsing fails.
  static Version? parseVersion(String versionString) {
    if (versionString.trim().isEmpty) return null;
    var cleaned = versionString.trim().replaceFirst(RegExp(r'^v'), '');

    // Extract build metadata (+N) or pre-release (-...) if present
    String mainPart = cleaned;
    String extraPart = '';

    final plusIdx = cleaned.indexOf('+');
    final dashIdx = cleaned.indexOf('-');

    int splitIdx = -1;
    if (plusIdx != -1 && dashIdx != -1) {
      splitIdx = plusIdx < dashIdx ? plusIdx : dashIdx;
    } else if (plusIdx != -1) {
      splitIdx = plusIdx;
    } else if (dashIdx != -1) {
      splitIdx = dashIdx;
    }

    if (splitIdx != -1) {
      mainPart = cleaned.substring(0, splitIdx);
      extraPart = cleaned.substring(splitIdx);
    }

    // Normalize 1 or 2 part versions (e.g. "0.4" -> "0.4.0", "1" -> "1.0.0")
    final parts = mainPart.split('.');
    if (parts.length == 1) {
      mainPart = '${parts[0]}.0.0';
    } else if (parts.length == 2) {
      mainPart = '${parts[0]}.${parts[1]}.0';
    }

    final normalized = '$mainPart$extraPart';

    try {
      return Version.parse(normalized);
    } catch (_) {
      return null;
    }
  }

  /// Returns `true` if [remote] is strictly newer than [current].
  static bool isNewer(String remote, String current) {
    final r = parseVersion(remote);
    final c = parseVersion(current);
    if (r == null || c == null) return false;
    return r > c;
  }
}
