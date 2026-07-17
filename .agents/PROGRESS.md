# OPA v0.4 — Implementation Progress

> **PURPOSE**: This file lives in the workspace so ANY new agent session can read it and continue work seamlessly — even if the user switches Google AI accounts due to rate limits.
>
> **LAST UPDATED**: 2026-07-15T17:21:00Z

## Current Goal

Implement OPA v0.4: Architectural refactors + Port Forwarding feature. Six work items in dependency order.

## Execution Order & Status

| # | Item | Status | Notes |
|---|------|--------|-------|
| 1 | TunnelConfig model + Hive adapter | ✅ DONE | New model, Hive adapter typeId 3, ConnectionProfile updated, export service updated, tests added |
| 2 | Per-session SshService | ✅ DONE | Refactored to `.autoDispose.family` keyed by profileId. Updated terminal, sftp, profile_editor, quick_commands screens |
| 3 | Password → Keystore migration | ✅ DONE | ProfileStorageService updated, main.dart wires one-time migration, all screens updated to use secure storage |
| 4 | Biometric guard → GoRouter redirect | ✅ DONE | Moved from widget-level gate to route-based redirect. /lock route added, OpaApp simplified |
| 5 | Tunnel management in SshService | ✅ DONE | forwardLocal/forwardRemote/dynamicSocks5 + ActiveTunnel tracking + SOCKS5 handler |
| 6 | Tunnel screen + UI integration | ✅ DONE | New TunnelScreen, /tunnel/:profileId route, 4th swipe action "FWD" on ConnectionTile |

## Design Decisions (Locked)

- **No build_runner migration**: Switching Hive adapters to code-gen would change the binary format, wiping all existing user data. Keep manual adapters.
- **TunnelConfig is a new model** with typeId: 3, stored as a list inside ConnectionProfile
- **Per-session SshService**: Use `ChangeNotifierProvider.family<SshService, String>` keyed by profileId
- **Password migration**: One-time migration on app start, passwords stored under key `ssh_password_{profileId}` in flutter_secure_storage
- **Tunnel UI**: 4th swipe button "FWD" on ConnectionTile → `/tunnel/:profileId` screen
- **ConnectionTile actions width**: Increase from 156 → 208 to fit 4 buttons

## Files Modified (Completed)

### Item 1 ✅
- `[NEW]` `lib/models/tunnel_config.dart` — TunnelConfig model with TunnelType enum
- `[MOD]` `lib/models/connection_profile.dart` — added `List<TunnelConfig> tunnels` field + copyWith
- `[MOD]` `lib/services/hive_adapters.dart` — TunnelConfigAdapter (typeId 3), ConnectionProfileAdapter updated with backward-compat tunnel read/write
- `[MOD]` `lib/services/export_service.dart` — tunnel JSON serialization/deserialization
- `[MOD]` `test/hive_adapters_test.dart` — TunnelConfigAdapter round-trip tests, profile-with-tunnels tests
- `[MOD]` `test/models_test.dart` — TunnelConfig model tests, ConnectionProfile tunnels tests

### Item 2 ✅
- `[MOD]` `lib/services/ssh_service.dart` — `ChangeNotifierProvider.autoDispose.family<SshService, String>` keyed by profileId
- `[MOD]` `lib/screens/terminal_screen.dart` — all 5 refs updated to `sshServiceProvider(widget.profileId)`
- `[MOD]` `lib/screens/sftp_screen.dart` — ref updated to `sshServiceProvider(widget.profileId)`
- `[MOD]` `lib/screens/profile_editor_screen.dart` — ref updated with temp key `_test_${profile.id}`
- `[MOD]` `lib/screens/quick_commands_screen.dart` — ref updated to `sshServiceProvider(profile.id)`

### Item 3 ✅
- `[MOD]` `lib/services/profile_storage_service.dart` — added FlutterSecureStorage integration, getPassword/savePassword/deletePassword/migratePasswords
- `[MOD]` `lib/main.dart` — one-time password migration on app start
- `[MOD]` `lib/screens/terminal_screen.dart` — password from secure storage with legacy fallback
- `[MOD]` `lib/screens/profile_editor_screen.dart` — save/load/delete password via secure storage
- `[MOD]` `lib/screens/quick_commands_screen.dart` — password from secure storage with legacy fallback

### Item 4 ✅
- `[MOD]` `lib/app_router.dart` — biometric redirect + /lock route + appRouterProvider watches auth state
- `[MOD]` `lib/main.dart` — removed widget-level biometric gate, simplified OpaApp

### Item 5 ✅
- `[MOD]` `lib/services/ssh_service.dart` — forwardLocal, forwardRemote, dynamicSocks5, ActiveTunnel class, SOCKS5 handler, tunnel cleanup on disconnect

### Item 6 ✅
- `[NEW]` `lib/screens/tunnel_screen.dart` — full tunnel management UI with add/start/stop/delete
- `[MOD]` `lib/app_router.dart` — /tunnel/:profileId route
- `[MOD]` `lib/widgets/connection_tile.dart` — 4th swipe action "FWD", widened to 208px
- `[MOD]` `lib/screens/home_screen.dart` — wired onTunnelTap callback

### Bug Fixes
- `[MOD]` `lib/screens/welcome_back_screen.dart` — removed dead _ascii code (compile error fix)
- `[MOD]` `lib/screens/key_management_screen.dart` — added mounted check for BuildContext async gap
- `[MOD]` `lib/app_router.dart` — CRITICAL: fixed GoRouter GlobalKey crash by using refreshListenable instead of ref.watch pattern
- `[MOD]` `lib/services/ssh_service.dart` — fixed SOCKS5 handler to use StreamIterator instead of socket.first (data loss prevention)
- `[DEL]` `lib/screens/welcome_back_screen.dart2` — stale file
- `[DEL]` `lib/screens/welcome_temp.txt` — stale file

## Verification Status

- [x] `flutter analyze` — 0 issues found ✅
- [ ] `flutter test` — Cannot run on Windows (Go native build requires GCC/NDK — expected)
- [x] Code audit — Manual audit completed, bugs found and fixed ✅
- [x] Build test — Static analysis clean ✅

## How to Resume

1. Read this file to understand current state
2. Check the status table above for what's done vs pending
3. For in-progress items, check the "Files Modified" section for what's been written
4. Continue from the next pending item
5. After completing an item, update status to ✅ DONE and add files to "Files Modified (Completed)"
6. Run `dart analyze` and `flutter test` after each item to verify
