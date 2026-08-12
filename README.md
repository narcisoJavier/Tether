# Tether

Tether is a pocket SSH and mesh terminal for Android. It combines a pure-Dart
SSH client, a VT100 terminal, SFTP, port forwarding, and embedded Tailscale
networking in one mobile app.

Current app version: `0.5.0+3`
Repository: [narcisoJavier/Tether](https://github.com/narcisoJavier/Tether)
Platform: Android (iOS is not supported yet)

## Current experience

- Home dashboard with saved connection profiles, environment tags, connection
  health, telemetry entry points, SSH, SFTP, and tunnel actions.
- Persistent multi-tab SSH terminal with automatic sizing, pinch-to-zoom,
  mobile keyboard controls, and quick commands routed to an existing shell.
- Command Deck with searchable presets, categories, offline brand marks,
  saved commands, phone-style long-press arrangement, and persisted folder
  ordering/row sizing.
- SFTP browser with upload, download, rename, delete, directory creation, and
  direct connection support when no terminal tab is already open.
- SSH key generation/import with Android Keystore-backed private-key storage.
- Local, remote, and dynamic SOCKS5 tunnels, including optional auto-start.
- Biometric lock, onboarding, update checks, and JSON profile/command backup.

## Architecture

```text
Flutter app
  StatefulShellRoute
    Home       -> profiles and profile actions
    Terminal   -> persistent SSH tabs and xterm.dart
    Commands   -> preset/saved command management
    Keys       -> SSH key metadata and lifecycle
    Settings   -> terminal, security, backup, and update preferences

SSH: dartssh2 -> direct socket or embedded Tailscale socket -> target server
Storage:
  Hive                 profiles, tunnel definitions, saved commands
  Android Keystore     private keys and passwords
  SharedPreferences    onboarding, settings, command-deck layout metadata
```

The app is intentionally Android-first. The embedded Tailscale package builds
the native Go runtime through Dart hooks and is skipped on x86_64 emulators
where the platform cannot load the required networking path.

## Getting started

### Prerequisites

- Flutter SDK compatible with the Dart constraint in `pubspec.yaml` (`>=3.10.4`)
- Android SDK and an Android device or emulator
- Go 1.26+ and Android NDK for the embedded Tailscale build

### Run locally

```bash
git clone https://github.com/narcisoJavier/Tether.git
cd Tether
flutter pub get
flutter run
```

### Build and verify

```bash
dart format lib test
dart analyze
flutter test
flutter build apk --debug
flutter build apk --release
```

Host-side analysis and tests may require the native Tailscale toolchain. An
Android debug build is the most representative validation path for changes
that touch the embedded networking package.

## First connection

1. Complete onboarding or choose Skip.
2. Add a profile from Home with the server host, port, username, and auth
   method.
3. For key authentication, open **Keys**, generate or import a key, copy its
   public key to the server's `authorized_keys`, then select the key in the
   profile.
4. Tap **SSH** to open a terminal tab. Use the terminal header's lightning
   button to send a saved command to the active shell, or choose another tab
   when multiple sessions are open.
5. Use the profile action sheet for SFTP, telemetry, tunnels, or profile
   editing.

## Security and data boundaries

- SSH passwords are stored in Android Keystore-backed secure storage, not in
  the Hive profile record.
- Private key material is stored through the key service and is not included
  in exports.
- Export/import is local JSON. Imports do not provide cloud synchronization.
- Tether does not collect product telemetry or silently upload connection data.
- Users are responsible for host verification, server permissions, and the
  security of any command they execute.

## Known limitations and next priorities

- Home telemetry currently reports connection-health signals. It does not yet
  fetch live CPU, RAM, or disk values from the remote server; those should be
  collected through authenticated SSH commands and cached per profile.
- Command-deck layout metadata is stored in SharedPreferences and is not yet
  included in profile/command JSON exports.
- Import collisions currently follow the import service's existing overwrite
  behavior; a preview and conflict-resolution step is planned.
- The visual convergence pass has covered Home, Command Deck, Keys, Settings,
  and the persistent terminal. SFTP and tunnel sub-screens remain candidates
  for the next component-level polish pass.
- There is no CI/CD pipeline or iOS target yet. Release builds are currently
  manual.

## Repository map

| Area | Location |
| --- | --- |
| App entry and theme | `lib/main.dart`, `lib/app_theme.dart` |
| Routing and shell navigation | `lib/app_router.dart`, `lib/widgets/glass_bottom_nav_bar.dart` |
| Home and profiles | `lib/screens/home_screen.dart`, `lib/screens/profile_editor_screen.dart` |
| Terminal | `lib/screens/tabbed_terminal_screen.dart`, `lib/services/ssh_service.dart` |
| Command Deck | `lib/screens/quick_commands_screen.dart`, `lib/services/quick_command_layout_service.dart` |
| SFTP and tunnels | `lib/screens/sftp_screen.dart`, `lib/screens/tunnel_screen.dart` |
| Keys and secure storage | `lib/screens/key_management_screen.dart`, `lib/services/key_service.dart` |
| Local persistence | `lib/services/profile_storage_service.dart`, `lib/services/export_service.dart` |
| Embedded networking | `packages/tailscale/` |
| Tests | `test/` |

## Contributing

Keep UI state in Riverpod, use the shared `GradientScaffold`/`GlassAppBar`
components for shell screens, preserve bottom-navigation safe spacing, and
add mounted checks after asynchronous gaps. Use single quotes, avoid
`print()`, and run formatting plus the relevant tests before committing.

## License

[MIT](LICENSE). Tether is not affiliated with OpenSSH, Tailscale, or any
referenced command-line tool.
