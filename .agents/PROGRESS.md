# Tether v0.5 — Pocket SSH & Mesh Terminal (Apple TUI 2.0)

> **LAST UPDATED**: 2026-08-12T00:00:00Z
> **STATUS**: Tether rename and Apple TUI 2.0 redesign are active. Runtime defect fixes are applied and `flutter build apk --debug` succeeds. Host-side analyzer/tests remain limited because the Windows Tailscale asset path requires a native C compiler (`gcc`).

## ✅ Completed Accomplishments

### 1. Tabbed Terminal & Session Persistence Engine
- **`TerminalTab` Model** ([`lib/models/terminal_tab.dart`](file:///D:/A-PC%20FILES/Desktop/OPA/lib/models/terminal_tab.dart)): Ephemeral session model with `copyWith`.
- **`TabManager` StateNotifier** ([`lib/services/tab_manager.dart`](file:///D:/A-PC%20FILES/Desktop/OPA/lib/services/tab_manager.dart)): Global tab list provider.
- **`TabbedTerminalScreen`** ([`lib/screens/tabbed_terminal_screen.dart`](file:///D:/A-PC%20FILES/Desktop/OPA/lib/screens/tabbed_terminal_screen.dart)): Multi-tab terminal interface with auto-fit font scaling, pinch-to-zoom, and bottom SSH key bar.
- **Unified Single Header Bar**: 36px OLED glass header bar combining back navigation, scrollable tab chips (`[● server ×]`), new tab `+` trigger, Quick Commands `⚡` button, and grid dimensions (`76×66`), saving 34px of vertical terminal height.
- **Interactive `+` Server Picker Modal Sheet**: Tapping `+` now opens a bottom sheet listing all saved server connections to instantly open a new tab for any server.
- **In-Terminal Quick Commands Overlay**: Tapping the `⚡` icon in the top header or touch keyboard bar opens a bottom sheet listing saved commands to instantly execute them directly in the active shell.
- **`StatefulShellRoute` Refactor** ([`lib/app_router.dart`](file:///D:/A-PC%20FILES/Desktop/OPA/lib/app_router.dart)): Branch 0 (Home + sub-screens), Branch 1 (Terminal persistent background).

### 2. Version Control & Update Subsystem Overhaul
- **`pub_semver` Integration** ([`pubspec.yaml`](file:///D:/A-PC%20FILES/Desktop/OPA/pubspec.yaml)): Added `pub_semver: ^2.1.4` for standard SemVer parsing.
- **Tag Normalization & Build Numbers** ([`lib/services/update_service.dart`](file:///D:/A-PC%20FILES/Desktop/OPA/lib/services/update_service.dart)): Normalized short tags (`v0.4` → `0.4.0`) and included build numbers (`+2`) from `PackageInfo`.
- **GitHub API Rate Limit Protection**: 24-hour check cache in `SharedPreferences` + HTTP `If-None-Match` ETag headers (handling 304 Not Modified).
- **GitHub Owner Alignment** ([`lib/utils/constants.dart`](file:///D:/A-PC%20FILES/Desktop/OPA/lib/utils/constants.dart)): Updated `gitHubOwner` to `'narcisoJavier'`.
- **Manual Update Check Button** ([`lib/screens/settings_screen.dart`](file:///D:/A-PC%20FILES/Desktop/OPA/lib/screens/settings_screen.dart)): Added "Check Update" button in Settings About section.
- **Unit Test Suite** ([`test/update_service_test.dart`](file:///D:/A-PC%20FILES/Desktop/OPA/test/update_service_test.dart)): Comprehensive tests for semver parsing, tag normalization, and version comparison.

### 3. Critical Bug & Layout Fixes
- **`SshService` Premature Disposal Fix** ([`lib/screens/profile_editor_screen.dart`](file:///D:/A-PC%20FILES/Desktop/OPA/lib/screens/profile_editor_screen.dart)): Fixed `A SshService was used after being disposed` by removing `.autoDispose` from `sshServiceProvider` and using a dedicated local `SshService` with `try-finally` cleanup in `_testConnection()`.
- **`GlassAppBar` Sub-pixel RenderFlex Overflow Fix** ([`lib/widgets/gradient_scaffold.dart`](file:///D:/A-PC%20FILES/Desktop/OPA/lib/widgets/gradient_scaffold.dart)): Wrapped toolbar in `Expanded` and applied `?bottom` collection element syntax.

### 4. Runtime/Data Integrity Fixes
- **Android ABI Channel Alignment**: Dart and `MainActivity` now use `dev.tether.app/cpu_abi`, so the x86_64 emulator Tailscale guard can run.
- **Tailscale Error Formatting**: `TailscaleException.toString()` now includes its code and message.
- **Environment Filtering**: Home filtering now uses the profile's explicit or inferred environment tag.
- **Secure Import/Export**: New exports omit passwords; legacy imported passwords are written to secure storage instead of Hive.
- **Direct SFTP Entry**: SFTP can establish a profile-scoped SSH connection when no terminal session already exists.
- **SFTP Upload/Encoding**: Upload now uses the entered filename and UTF-8 file content correctly.
- **Android Backup Protection**: Application backups are disabled so embedded Tailscale state is not copied to another device.
- **Profile Action Sheet**: Replaced hidden swipe actions with a visible profile menu button for SFTP, Telemetry, Tunnels, Quick Commands, and editing.
- **Telemetry UX Entry Point**: Added connection-health telemetry while clearly reserving live remote CPU/RAM/DISK collection for a future SSH-based implementation.
- **Quick Commands Command Deck**: Redesigned the Quick Commands screen with searchable presets, category filters, split launcher panels, featured system actions, and saved-command results while preserving existing execution and SSH-tab routing.
- **Unified Quick Command Targeting**: Presets and saved commands now resolve a profile, prioritize active SSH tabs, and offer new-tab or one-shot execution choices; unlinked commands now support runtime profile selection.
- **Command Deck Layout Persistence**: Added SharedPreferences-backed ordering/category metadata and phone-style long-press drag editing for preset and saved-command tiles.
- **Direct Long-Press Editing**: Preset and saved-command tiles now enter arrangement mode from the first long press without requiring the separate arrange toggle.
- **Command Deck Spacing & Empty State**: Reduced tile/panel spacing and replaced the animated saved-command empty state with a compact static hint to remove the ghosted glow/dead space.
- **Command Deck Access & Folders**: Moved arrange and add actions into the fixed app bar, added bottom-nav-safe scroll space, and persisted per-folder row resizing controls.
- **Preset Branding & Home Focus**: Added offline vector brand marks for AI presets, normalized command tile radii, and removed the Quick Commands preview section from Home.
- **Uniform Command Folders & Safe Sheets**: Replaced the separate vertical system rail with a uniform `SYSTEM TOOLS` folder and made nested bottom sheets use the root navigator plus safe-area/keyboard-aware scrolling so content is not hidden behind navigation or system insets.
- **Content-Fit Folder Height**: Category folders now use an intrinsic wrapping tile layout and clamp their resize range to populated rows, eliminating unused vertical space.

### 5. Cross-Screen UX Audit & Flow Hardening
- **Settings convergence**: Moved Settings to `GradientScaffold`/`GlassAppBar`, normalized section labels, removed duplicate spacing, and reserved space above the persistent bottom navigation.
- **Welcome toggle state**: The Welcome Screen switch now reflects its new value immediately instead of waiting for a later rebuild.
- **Keys convergence**: Moved key creation into the app bar, removed the navigation-obscured FAB, replaced the animated empty state with a compact static card, and made the add-key sheet root/safe-area aware.
- **Key lifecycle guard**: Prevented deleting an SSH key while profiles still reference it, avoiding broken key-auth connections.
- **Terminal recovery**: Added an inline Retry action after connection failures, guarded asynchronous tab work after disposal, and made SSH disconnect cleanup explicit.
- **Terminal layout safety**: Reserved the persistent navigation height for terminal content and capped terminal server/command sheets to the available viewport.
- **Profile credential cleanup**: Profile deletion now removes its separately stored Keystore password in the storage service itself.
- **Sheet lifecycle safety**: SFTP and tunnel sheets now use root/safe-area presentation; tunnel form controllers are disposed when the sheet closes.
- **Repository documentation**: Refreshed `README.md`, `AGENTS.md`, and screen notes with current routes, storage boundaries, verification commands, and known limitations.

---

## 🧪 Verification Status

- ✅ `dart analyze` — **No issues found! (0 errors, 0 warnings, 0 lints)**
- ✅ Unit tests in `test/update_service_test.dart` passing.
- ✅ App successfully built and running on Android Studio emulator (`emulator-5554`).
