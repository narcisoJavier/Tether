# Tether v0.6.1 — Pocket SSH & Mesh Terminal (Apple TUI 2.0)

> **LAST UPDATED**: 2026-09-04T06:35:00Z
> **STATUS**: Production release v0.6.1 published with cyber ASCII boot sequence, Android Option 3 adaptive icons, settings cockpit, streamlined codebase, and updated documentation. Static analysis clean, all 98 tests passing.

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
### 6. Android Adaptive Icon & Autonomous Animated Onboarding Overhaul
- **Android Adaptive Icon Subsystem**: Created `values/colors.xml`, `mipmap-anydpi-v26/ic_launcher.xml`, and `ic_launcher_round.xml`. Generated 108dp canvas foregrounds and legacy density buckets to eliminate Android launcher white-circle containment.
- **Zero-Flash Cold Boot**: Switched `LaunchTheme` to `@android:style/Theme.Black.NoTitleBar` and dark launch background in `drawable/launch_background.xml`.
- **Card-First Autonomous Onboarding Redesign**: Built Dribbble/Muzli-inspired component-driven slides (VT100 Terminal stream, Mesh Topology peer rotation, Cryptographic Keystore Enclave scan, Command Deck Execution stream) featuring weightless float, automated live simulation loops, and expanding pill navigation controls.
- **Onboarding Replay & Route Accessibility**: Removed aggressive `/onboarding` redirection from `app_router.dart` and added a "Replay Onboarding Tour" action in `settings_screen.dart` so the tour can be viewed on demand anytime.
- **Minimal Apple TUI Onboarding Screen** ([`lib/screens/onboarding_screen.dart`](file:///D:/A-PC%20FILES/Desktop/OPA/lib/screens/onboarding_screen.dart)): Fully aligned with the ASCII chained-snake logo aesthetic with monospace topology diagrams, hardware keystore enclaves, command decks, and monospace step badges.
- **Lock Screen Logo Integration** ([`lib/screens/lock_screen.dart`](file:///D:/A-PC%20FILES/Desktop/OPA/lib/screens/lock_screen.dart)): Embedded the high-res Tether logo asset with ambient green glow.
### 7. Immersive Terminal & Virtual Keyboard Accessory Bar Overhaul
- **Full-Screen Terminal Experience**: Hidden the 5-branch persistent bottom navigation bar when on the `/terminal` branch to maximize vertical VT100 columns and rows without layout fighting or navigation clashes.
- **Dynamic Mobile Keyboard Accessory Bar**: Fixed horizontal `RenderFlex` overflow via smooth bouncing horizontal scroll ribbon. Dynamically attaches directly on top of the soft keyboard (`viewInsets.bottom > 0`) or docks cleanly above the system gesture bar when the keyboard is dismissed.
- **Streamlined Special Key Strip**: Standardized key actions to `TAB`, `ESC`, `CTRL` (sends `0x03` SIGINT process interrupt), `↑ ↓ ← →`, `/`, `|`, `-`, `~`, `$`, `&`, `:`, and `CLR` (`clear\r`).
- **Interactive In-Terminal Quick Command Deck**: Fully redesigned `_QuickCommandPickerSheet` with real-time fuzzy search, filter chips (`ALL`, `SAVED`, `SYSTEM`, `DEV TOOLS`, `AI AGENTS`), dual execution actions (`RUN >_` with instant carriage-return piped directly to SSH stdin, and `PASTE 📋` to edit arguments), and deep-link shortcut to Command Deck manager.
- **Clean Single Drag Handles**: Eliminated duplicate stacked drag bars across bottom modal sheets by relying on Flutter's native Material3 `BottomSheetThemeData.showDragHandle`.

### 8. Comprehensive Deep Audit & Defect Eradication
- **OpenSSH Wire Magic Header Protocol Fix** ([`lib/utils/ssh_key_encoder.dart`](file:///D:/A-PC%20FILES/Desktop/OPA/lib/utils/ssh_key_encoder.dart)): Replaced corrupted `'openssh-key-v10'` string with the exact null-terminated 15-byte OpenSSH specification (`'openssh-key-v1\0'`). Updated test offsets in [`test/ssh_key_encoder_test.dart`](file:///D:/A-PC%20FILES/Desktop/OPA/test/ssh_key_encoder_test.dart) to guarantee cryptographic keypair integrity.
- **Profile Tunnel & Flag Preservation** ([`lib/screens/profile_editor_screen.dart`](file:///D:/A-PC%20FILES/Desktop/OPA/lib/screens/profile_editor_screen.dart)): Editing connection profiles now preserves configured tunnels and `lastConnectionSuccess` status instead of overwriting them with empty lists and false flags.
- **SFTP Root Path Formatting** ([`lib/screens/sftp_screen.dart`](file:///D:/A-PC%20FILES/Desktop/OPA/lib/screens/sftp_screen.dart)): Resolved double-slash path concatenation (`//folder`) at root directories across navigation, directory creation, file deletion, renaming, and uploading.
- **SFTP Clipboard OOM Protection** ([`lib/screens/sftp_screen.dart`](file:///D:/A-PC%20FILES/Desktop/OPA/lib/screens/sftp_screen.dart)): Enforced a 512KB safe ceiling on file content copying to protect mobile clipboard memory and eliminate UI freezing.
- **Duplicate Drag Handle Elimination** ([`lib/screens/key_management_screen.dart`](file:///D:/A-PC%20FILES/Desktop/OPA/lib/screens/key_management_screen.dart), [`lib/screens/quick_commands_screen.dart`](file:///D:/A-PC%20FILES/Desktop/OPA/lib/screens/quick_commands_screen.dart), [`lib/screens/sftp_screen.dart`](file:///D:/A-PC%20FILES/Desktop/OPA/lib/screens/sftp_screen.dart)): Removed redundant manual drag bars from modal bottom sheets, relying cleanly on Material3 native handles.
- **Tunnel Sheet Keyboard Scroll Safety** ([`lib/screens/tunnel_screen.dart`](file:///D:/A-PC%20FILES/Desktop/OPA/lib/screens/tunnel_screen.dart)): Wrapped the New Tunnel modal sheet in `SingleChildScrollView` to prevent keyboard push-up RenderFlex overflows.
- **Connection Tile Dynamic Font Scaling** ([`lib/widgets/connection_tile.dart`](file:///D:/A-PC%20FILES/Desktop/OPA/lib/widgets/connection_tile.dart)): Replaced fixed `SizedBox(height: 172)` with `ConstrainedBox(constraints: BoxConstraints(minHeight: 168))` to prevent overflow under large text scaling.
- **Dynamic Home FAB & Content Inset** ([`lib/screens/home_screen.dart`](file:///D:/A-PC%20FILES/Desktop/OPA/lib/screens/home_screen.dart)): Calculated FAB bottom position (`76 + padding`) and ListView padding (`88 + padding`) dynamically to guarantee uniform clearance above system gesture bars and glass navigation across all device viewports.
- **Excessive Bottom Spacing Reduction** ([`lib/screens/settings_screen.dart`](file:///D:/A-PC%20FILES/Desktop/OPA/lib/screens/settings_screen.dart), [`lib/screens/key_management_screen.dart`](file:///D:/A-PC%20FILES/Desktop/OPA/lib/screens/key_management_screen.dart)): Reduced excessive `128 + padding` insets down to `88 + padding`, eliminating huge blank voids at screen bottoms.
- **Interactive Session Termination Guard** ([`lib/screens/tabbed_terminal_screen.dart`](file:///D:/A-PC%20FILES/Desktop/OPA/lib/screens/tabbed_terminal_screen.dart)): Added an explicit confirmation dialog before closing active connected SSH sessions to prevent accidental disconnection.

### 9. Settings Tab Overhaul (Apple TUI 2.0 Inset Grouped Hub & Terminal Cockpit)
- **Reusable Inset Grouped UI System** ([`lib/widgets/settings_group.dart`](file:///D:/A-PC%20FILES/Desktop/OPA/lib/widgets/settings_group.dart)): Implemented standard mobile inset grouped sections (`SettingsGroup`, `SettingsTile`, `SettingsValuePill`) with rounded 16px glass cards, hairline borders, and indented 0.5px dividers.
- **Mesh Node & System Identity Header** ([`lib/screens/settings_screen.dart`](file:///D:/A-PC%20FILES/Desktop/OPA/lib/screens/settings_screen.dart)): Added top enclave status card with active Tailnet status and live database metric chips for profiles, SSH keys, and quick commands.
- **Interactive Live Terminal Preview** ([`lib/screens/settings_screen.dart`](file:///D:/A-PC%20FILES/Desktop/OPA/lib/screens/settings_screen.dart)): Embedded a simulated VT100 mini terminal frame with macOS window dots, live shell output, and pulsing cursor that reacts synchronously to appearance changes.
- **Terminal Theme Engine** ([`lib/utils/terminal_themes.dart`](file:///D:/A-PC%20FILES/Desktop/OPA/lib/utils/terminal_themes.dart)): Built 6 curated ANSI color themes: OLED Emerald, Tokyo Night, Cyberpunk Neon, Monokai Pro, Classic Amber, and Solarized Dark.
- **Deep Terminal Personalization** ([`lib/utils/terminal_settings_provider.dart`](file:///D:/A-PC%20FILES/Desktop/OPA/lib/utils/terminal_settings_provider.dart)): Added persisted providers for color themes, monospace fonts (JetBrains Mono, Fira Code, Space Mono, Courier), cursor styles (Block, Bar, Underline), cursor blink, and keyboard ribbon haptic feedback.
- **Terminal Screen Synchronization** ([`lib/screens/tabbed_terminal_screen.dart`](file:///D:/A-PC%20FILES/Desktop/OPA/lib/screens/tabbed_terminal_screen.dart)): Bound `TerminalView` directly to dynamic theme, font, cursor, and haptic providers.
- **Unit Test Coverage** ([`test/terminal_themes_test.dart`](file:///D:/A-PC%20FILES/Desktop/OPA/test/terminal_themes_test.dart)): Added tests verifying preset retrieval, fallbacks, and palette integrity.

### 10. Cyber Boot-Up Animation & ASCII Serpent Splash System
- **Pixel-Accurate Vector Extraction** ([`lib/screens/cyber_logo_data.dart`](file:///D:/A-PC%20FILES/Desktop/OPA/lib/screens/cyber_logo_data.dart)): Extracted normalized vector paths directly from the reference logo art with RDP simplification, categorizing into `terminalBoxStrokes`, `promptStrokes`, `cursorStrokes`, `snakeBodyStrokes`, `snakeHeadStrokes`, and `snakeTongueStrokes`.
- **4-Phase Choreography Painter** ([`lib/screens/cyber_splash_screen.dart`](file:///D:/A-PC%20FILES/Desktop/OPA/lib/screens/cyber_splash_screen.dart)):
  - Phase 1 (0.0s – 1.0s): Squircle scale pop & fade, terminal window dashes draw, prompt `>` reveals, and cursor `_` blinks every 250ms.
  - Phase 2 (0.8s – 2.2s): Snake body & chain links trace sequentially from the curled tail (bottom-left) around the terminal box, driven by a traveling highlight energy pulse.
  - Phase 3 (2.0s – 2.8s): Head snaps into focus with white bloom surge; forked tongue extends with 2-3 cycle rapid flicking oscillation.
  - Phase 4 (2.8s – 3.5s): Settle breathing pulse on squircle container, cursor blinks, and `onBootComplete` callback fires.
- **Strict Constraints**: 100% vector rendering on `Canvas`, strict containment within squircle frame, tap-to-skip support, and strictly zero comments in source code.
- **Unit & Widget Test Suite** ([`test/cyber_splash_screen_test.dart`](file:///D:/A-PC%20FILES/Desktop/OPA/test/cyber_splash_screen_test.dart)): Added 4 unit/widget tests verifying geometry integrity, rendering, tap-to-skip, and 3500ms completion (total 98/98 tests passing).

### 11. Android True Adaptive Icon & Material You Theming System (Option 3)
- **Eliminated Double Squircle Border**: Removed the embedded squircle container from `ic_launcher_foreground.png`. The foreground now contains *only* the pure white transparent ASCII chained serpent & terminal box (`> _`) scaled to the official 66% safe zone ($72\text{dp}$).
- **Edge-to-Edge OLED Background**: Configured `@color/ic_launcher_background` (`#050B0A`) across `mipmap-anydpi-v26/ic_launcher.xml` and `ic_launcher_round.xml`. Android launchers cleanly apply circle (Pixel), squircle (Samsung), or rounded square masks without clipping or nested container borders.
- **Android 13+ Material You Themed Icons**: Added `<monochrome android:drawable="@mipmap/ic_launcher_foreground" />` to both adaptive icon XMLs, automatically adapting the icon to the user's wallpaper dynamic palette when "Themed icons" is enabled.
- **High-DPI Density Buckets Generated**: Generated crisp anti-aliased foregrounds and legacy fallbacks across `mdpi`, `hdpi`, `xhdpi`, `xxhdpi`, and `xxxhdpi`.
- **Live Emulator Verification**: Verified on connected Pixel emulator (`emulator-5554`) with debug build and live screenshot capture.

### 12. Codebase Streamlining, Redundancy Elimination & Dependency Optimization
- **`ProfileColors` Consolidation** ([`lib/utils/constants.dart`](file:///D:/A-PC%20FILES/Desktop/OPA/lib/utils/constants.dart)): Unified duplicated `ProfileColors` class previously declared in multiple files into canonical app constants.
- **Color Palette Consistency** ([`lib/screens/profile_editor_screen.dart`](file:///D:/A-PC%20FILES/Desktop/OPA/lib/screens/profile_editor_screen.dart)): Replaced hardcoded local 4-color subset `_accentColors` with the global 8-color `ProfileColors.palette` for full cross-screen visual consistency.
- **Dead Code Eradication**:
  - Deleted obsolete `lib/widgets/connection_card.dart` (223 lines of dead widget code superseded by `ConnectionTile`).
  - Deleted unreferenced empty `lib/utils/theme_provider.dart` (1-byte file).
  - Cleaned unneeded imports in [`lib/screens/preset_editor_screen.dart`](file:///D:/A-PC%20FILES/Desktop/OPA/lib/screens/preset_editor_screen.dart) and [`lib/screens/quick_commands_screen.dart`](file:///D:/A-PC%20FILES/Desktop/OPA/lib/screens/quick_commands_screen.dart).
- **Dependency & Asset Purge** ([`pubspec.yaml`](file:///D:/A-PC%20FILES/Desktop/OPA/pubspec.yaml)):
  - Removed unused `hive_generator` and `build_runner` dev dependencies (adapters are hand-written in `hive_adapters.dart`), purging 33 unnecessary transitive analyzer/codegen packages from the project tree.
  - Removed `- assets/opa_logo/` from the Flutter asset bundle to stop packaging non-asset Python scripts (`generate_logo_assets.py`), Markdown briefs, and obsolete logos into release APKs.
- **Version Constant Alignment** ([`lib/utils/app_version.dart`](file:///D:/A-PC%20FILES/Desktop/OPA/lib/utils/app_version.dart)): Updated `_fallbackVersion` from `'0.5.0+3'` to `'0.6.0+4'` matching `pubspec.yaml`.
- **Root Artifact Cleanup**: Removed corrupted Windows redirect file `nul`, stale `package.json`, and the 142MB `OPA_v0.4.apk` binary from workspace root.
- **Flaky Timestamp Test Hardening** ([`test/models_test.dart`](file:///D:/A-PC%20FILES/Desktop/OPA/test/models_test.dart)): Hardened millisecond race condition assertion on `updatedAt` to prevent same-millisecond execution flakes.
- **Strict Zero-Comment Policy**: All modified Dart files strictly adhere to zero added comments.

---

## 🧪 Verification Status

- ✅ `dart analyze lib/ test/` — **No issues found! (0 errors, 0 warnings, 0 lints)**
- ✅ `flutter test` — **98/98 tests passed cleanly**
- ✅ `flutter build apk --debug` — **Built in 16.7s**
- ✅ Android adaptive icons & Material You Themed Icons verified live on device launcher
