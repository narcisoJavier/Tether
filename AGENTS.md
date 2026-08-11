# PROJECT KNOWLEDGE BASE

**Generated:** 2026-07-08
**Commit:** 0249149
**Branch:** main

## OVERVIEW

Tether — Pocket SSH & Mesh Terminal. Flutter/Dart Android app (v0.5.0+3) for mobile SSH with embedded Tailscale networking. Pure-Dart SSH client (dartssh2) + VT100 terminal (xterm.dart) + Go FFI bridge for WireGuard tunnels.

## STRUCTURE

```
Tether/
├── lib/                    # Flutter app source (38 files)
│   ├── main.dart           # Entry: Hive init, Tailscale init, Riverpod scope
│   ├── app_router.dart     # GoRouter: 10 routes + onboarding guard
│   ├── app_theme.dart      # Dark glassmorphism Material3 theme
│   ├── models/             # Data classes (ConnectionProfile, StoredKeyPair, QuickCommand)
│   ├── screens/            # Full-page widgets (10 screens)
│   ├── services/           # Business logic (13 services) ← see lib/services/AGENTS.md
│   ├── utils/              # Constants, presets, encoders
│   └── widgets/            # Reusable components (3 widgets)
├── packages/tailscale/     # Embedded Go FFI sub-package ← see packages/tailscale/AGENTS.md
├── test/                   # 5 unit test files
├── android/                # Android platform (Kotlin MainActivity, Gradle)
├── assets/                 # Logo assets (SVG, PNG, generation script)
└── pubspec.yaml            # Flutter manifest
```

## WHERE TO LOOK

| Task | Location | Notes |
|------|----------|-------|
| Add new screen | `lib/screens/` + `lib/app_router.dart` | Register route in GoRouter |
| Add new service | `lib/services/` | Wrap in Riverpod provider, register in main.dart overrides |
| Add new model | `lib/models/` | Extend HiveObject, register adapter in hive_adapters.dart |
| Modify SSH connection | `lib/services/ssh_service.dart` | dartssh2 wrapper |
| Modify Tailscale | `lib/services/tailscale_service.dart` | Wraps package:tailscale |
| Modify terminal | `lib/screens/terminal_screen.dart` | xterm.dart + auto-fit + keyboard bar |
| Modify theme | `lib/app_theme.dart` | Single source for all Material3 styling |
| Add quick command preset | `lib/utils/agent_presets.dart` | 253-line data file |
| Build native Go | `packages/tailscale/hook/build.dart` | Auto-runs on flutter build |
| Modify key storage | `lib/services/key_service.dart` | Android Keystore via flutter_secure_storage |

## CODE MAP

| Symbol | Type | Location | Role |
|--------|------|----------|------|
| `main()` | function | `lib/main.dart` | App entry: Hive + SharedPreferences + Tailscale + Riverpod |
| `OpaApp` | class | `lib/main.dart` | Biometric gate → MaterialApp.router |
| `appRouterProvider` | provider | `lib/app_router.dart` | GoRouter with 10 routes |
| `AppTheme.dark()` | method | `lib/app_theme.dart` | Dark glassmorphism theme |
| `SshService` | class | `lib/services/ssh_service.dart` | dartssh2 wrapper: connect/shell/exec |
| `TailscaleService` | class | `lib/services/tailscale_service.dart` | Embedded WireGuard tailnet |
| `KeyService` | class | `lib/services/key_service.dart` | Ed25519 generation + Keystore CRUD |
| `ProfileStorageService` | class | `lib/services/profile_storage_service.dart` | Hive CRUD for profiles/commands |
| `ConnectionProfile` | model | `lib/models/connection_profile.dart` | SSH connection profile |
| `StoredKeyPair` | model | `lib/models/stored_key_pair.dart` | SSH key metadata |
| `QuickCommand` | model | `lib/models/quick_command.dart` | Saved command preset |
| `ConnectionTile` | widget | `lib/widgets/connection_tile.dart` | Swipeable connection tile |
| `AgentPresets` | class | `lib/utils/agent_presets.dart` | 20+ agent/tool presets |
| `Tailscale` | class | `packages/tailscale/lib/tailscale.dart` | Go FFI bridge singleton |

## CONVENTIONS

- **Single quotes** everywhere (lint: `prefer_single_quotes`)
- **No `print()`** — use `debugPrint()` (lint: `avoid_print`)
- **`const` constructors** on all widgets/models where possible
- **Named parameters** with `required` keyword
- **Riverpod** for state management (Provider, ChangeNotifierProvider, StreamProvider)
- **GoRouter** for routing with slide+fade transitions
- **Manual Hive adapters** (no build_runner code-gen despite being in dev_dependencies)
- **Private members** prefixed with `_`
- **Doc comments** (`///`) on all public classes/methods
- **`mounted` checks** after async gaps in StatefulWidgets

## ANTI-PATTERNS (THIS PROJECT)

| Pattern | Enforcement | Location |
|---------|-------------|----------|
| `print()` calls | Lint rule (`avoid_print`) | `analysis_options.yaml` |
| Empty `else` blocks | Lint rule (`avoid_empty_else`) | `packages/tailscale/analysis_options.yaml` |
| Un-cancelled subscriptions | Lint rule (`cancel_subscriptions`) | `packages/tailscale/analysis_options.yaml` |
| Un-awaited futures | Lint rule (`unawaited_futures`) | `packages/tailscale/analysis_options.yaml` |
| Type name collision with dartssh2 | Convention (`NOTE:`) | `lib/models/stored_key_pair.dart:17` |
| Windows target | Explicitly unsupported | `packages/tailscale/doc/api-roadmap.md` |

## UNIQUE STYLES

- **Dark-only theme** — no light mode, `ThemeMode.dark` hardcoded
- **Glassmorphism** — `BackdropFilter` + blur + semi-transparent surfaces
- **Accent colors** — 8-color palette for connection differentiation
- **Typography** — Inter (UI) + JetBrains Mono (terminal)
- **Biometric gate** — Widget-level conditional rendering (not route-based)
- **Tailscale FFI** — Go compiled to shared library via Dart hooks

## COMMANDS

```bash
flutter pub get                    # Resolve dependencies + trigger Go build
flutter run                        # Debug on connected device
flutter build apk --release        # Release APK
flutter test                       # Run 5 unit tests
dart analyze                       # Static analysis
flutter clean && flutter pub get   # Full clean rebuild
```

## NOTES

- **Go 1.26+ required** for Tailscale native compilation (auto-detected by hook)
- **Android NDK required** for Go cross-compilation
- **`key.properties`** must be created for release signing (gitignored)
- **`package.json`** in root is stale — ignore it (project is pure Dart/Flutter)
- **No CI/CD** — builds and releases are manual
- **No iOS support yet** — Android only (iOS on roadmap)
- **Tailscale state** excluded from cloud backups
- **x86_64 emulators** — Tailscale skipped on emulator (seccomp SIGSYS)

## ACTIVE DEVELOPMENT

> **⚠️ BEFORE STARTING ANY WORK**: Read `.agents/PROGRESS.md` for the current implementation state. This project has an active multi-session development effort (OPA v0.4) that may span multiple agent sessions/accounts. The progress file tracks what's done, what's in progress, and what's next. Always check it first to avoid redoing completed work.
