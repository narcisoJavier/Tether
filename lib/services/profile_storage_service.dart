import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive/hive.dart';

import '../models/connection_profile.dart';
import '../models/quick_command.dart';
import '../utils/constants.dart';

/// Service for persisting connection profiles and quick commands to Hive.
class ProfileStorageService {
  final Box<ConnectionProfile> _profilesBox;
  final Box<QuickCommand> _commandsBox;
  final FlutterSecureStorage _secureStorage;

  ProfileStorageService(
    this._profilesBox,
    this._commandsBox, [
    this._secureStorage = const FlutterSecureStorage(
      aOptions: AndroidOptions(),
    ),
  ]);

  // --- Connection Profiles ---

  /// Get all saved connection profiles.
  List<ConnectionProfile> listProfiles() {
    return _profilesBox.values.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  /// Get a profile by ID.
  ConnectionProfile? getProfile(String id) => _profilesBox.get(id);

  /// Save a new or updated connection profile.
  Future<void> saveProfile(ConnectionProfile profile) async {
    await _profilesBox.put(profile.id, profile);
  }

  /// Delete a connection profile.
  Future<void> deleteProfile(String id) async {
    await _profilesBox.delete(id);
    // Passwords are stored separately in the Android Keystore and must be
    // removed with the profile to avoid orphaned credentials.
    await deletePassword(id);
  }

  /// Update the last connection success flag.
  Future<void> updateConnectionStatus(String id, bool success) async {
    final profile = _profilesBox.get(id);
    if (profile == null) return;
    final updated = profile.copyWith(lastConnectionSuccess: success);
    await _profilesBox.put(id, updated);
  }

  // --- Quick Commands ---

  /// Get all saved quick commands.
  List<QuickCommand> listCommands() {
    return _commandsBox.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  /// Get commands associated with a specific profile.
  List<QuickCommand> listCommandsForProfile(String profileId) {
    return _commandsBox.values.where((c) => c.profileId == profileId).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  /// Get a command by ID.
  QuickCommand? getCommand(String id) => _commandsBox.get(id);

  /// Save a new or updated quick command.
  Future<void> saveCommand(QuickCommand command) async {
    await _commandsBox.put(command.id, command);
  }

  /// Delete a quick command.
  Future<void> deleteCommand(String id) async {
    await _commandsBox.delete(id);
  }

  // --- Secure Password Storage ---

  /// Retrieve a password from secure storage for the given profile ID.
  Future<String?> getPassword(String profileId) async {
    return _secureStorage.read(key: 'ssh_password_$profileId');
  }

  /// Store a password in secure storage for the given profile ID.
  Future<void> savePassword(String profileId, String password) async {
    await _secureStorage.write(key: 'ssh_password_$profileId', value: password);
  }

  /// Delete a password from secure storage.
  Future<void> deletePassword(String profileId) async {
    await _secureStorage.delete(key: 'ssh_password_$profileId');
  }

  /// One-time migration: move passwords from Hive plain-text fields to
  /// secure storage (Android Keystore). Clears the password from Hive
  /// after migration.
  Future<int> migratePasswords() async {
    int migrated = 0;
    for (final profile in _profilesBox.values) {
      if (profile.password != null && profile.password!.isNotEmpty) {
        await _secureStorage.write(
          key: 'ssh_password_${profile.id}',
          value: profile.password!,
        );
        // Clear from Hive (no longer stored in plain text)
        final updated = profile.copyWith();
        // Manually null out the password since copyWith preserves it
        updated.password = null;
        await _profilesBox.put(profile.id, updated);
        migrated++;
        debugPrint('[PWD] Migrated password for profile ${profile.id}');
      }
    }
    return migrated;
  }
}

/// Provider for the profile storage service.
final profileStorageProvider = Provider<ProfileStorageService>((ref) {
  final profilesBox = Hive.box<ConnectionProfile>(AppConstants.profilesBox);
  final commandsBox = Hive.box<QuickCommand>(AppConstants.commandsBox);
  return ProfileStorageService(profilesBox, commandsBox);
});
