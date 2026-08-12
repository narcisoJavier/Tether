# Tether — Screen Architecture & Detailed UI/UX Specifications

> **Application**: Tether v0.5.0
> **Design System**: Apple TUI 2.0 (OLED Black, Glassmorphism, System Blue `#0A84FF`, JetBrains Mono)  
> **Routing Framework**: GoRouter with `StatefulShellRoute` persistent terminal branch  

---

## 📱 Screen Registry Overview

| # | Screen Name | Route Path | Primary Role | Key Components |
|---|-------------|------------|--------------|----------------|
| 1 | **Welcome Back Screen** | `/welcome` | Boot & Biometric Gate | Typewriter animation, Keystore init, Biometric prompt |
| 2 | **Home Dashboard Screen** | `/` | Main Server Hub | Tailscale node status card, server RPG stat cards, search chips, FAB menu |
| 3 | **Tabbed Terminal Screen** | `/terminal` | Multi-Session VT100 SSH | 36px OLED glass tab bar, `+` server picker, `⚡` QCMD overlay, touch keyboard |
| 4 | **Profile Editor Screen** | `/profile/new` or `/profile/:id` | Connection Configuration | SSH Host/Port form, Auth method (Pass/Key), Tailscale toggle, Test Connection |
| 5 | **SFTP Remote File Browser** | `/sftp/:id` | Remote File Management | Interactive breadcrumb path bar, file tree, upload/download progress, terminal launch |
| 6 | **Quick Commands Screen** | `/commands` | Shell Automation Hub | Saved command cards, profile binder, preset importer, 1-tap execute |
| 7 | **Preset Library Screen** | `/presets` | CLI Tool Catalog | 20+ built-in developer preset chips (Docker, Nginx, K8s, System) |
| 8 | **SSH Keys Manager Screen** | `/keys` | Keystore & Keygen | Ed25519 / RSA key pair generator, Keystore storage, OpenSSH public key export |
| 9 | **Tunnel Screen** | `/tunnel/:id` | SSH Port Forwarding | Local, remote, and dynamic SOCKS5 tunnel definitions with start/stop controls |
| 10 | **Settings & About Screen** | `/settings` | Configuration & Updates | Biometric lock switch, dark theme options, GitHub release update check (SemVer + ETag) |

---

## 🛠️ Detailed Screen Specifications

### 1. 🚀 Welcome Back Screen (`WelcomeBackScreen`)
* **File**: [`lib/screens/welcome_back_screen.dart`](file:///D:/A-PC%20FILES/Desktop/OPA/lib/screens/welcome_back_screen.dart)
* **Purpose**: Serves as the application boot screen and security checkpoint.
* **UI/UX Breakdown**:
  * **Terminal Boot Header**: Typewriter terminal animation printing system initialization status (`[OK] Hive initialized`, `[OK] Keystore unlocked`).
  * **Biometric Auth Gate**: Triggers Android Biometric Prompt (`local_auth`) if enabled in Settings.
  * **Glass Container**: Dark glass card with neon blue logo glow.
* **State & Navigation**: On authentication success, checks if onboarding is completed and routes to `/` (Home).

---

### 2. 🏠 Home Dashboard Screen (`HomeScreen`)
* **File**: [`lib/screens/home_screen.dart`](file:///D:/A-PC%20FILES/Desktop/OPA/lib/screens/home_screen.dart)
* **Purpose**: The central command center showing saved server connections, active Tailscale status, and quick launch triggers.
* **UI/UX Breakdown**:
  * **Tailscale Node Status Card**: Top banner displaying active Tailscale VPN status (Connected IPv4, MagicDNS suffix, node state).
  * **Environment Filter Chips**: Quick filtering (`All`, `Prod 🔴`, `Staging 🟡`, `HomeLab 🟢`).
  * **Connection Tiles (`ConnectionTile`)**: RPG stat card style with honest `AUTH` / `SHELL` / `TUNNL` bars, host address, SSH port, authentication type badge, 1-tap SSH / 1-tap SFTP actions, and a visible profile action sheet for Telemetry, Tunnels, Quick Commands, and editing.
  * **Expandable FAB Menu**: Floating action button expanding into `New Server` and `Manage Keys`.
* **State & Navigation**: Tapping a server tile writes `TerminalTabRequest` to `pendingTerminalTabProvider` and navigates to `/terminal`.

---

### 3. 🖥️ Tabbed Terminal Screen (`TabbedTerminalScreen`)
* **File**: [`lib/screens/tabbed_terminal_screen.dart`](file:///D:/A-PC%20FILES/Desktop/OPA/lib/screens/tabbed_terminal_screen.dart)
* **Purpose**: Full-screen multi-tab VT100 terminal engine hosting persistent SSH sessions.
* **UI/UX Breakdown**:
  * **Unified Single Header Bar (36px)**: OLED glass bar with back navigation (`←`), scrollable tab chips (`[● server ×]`), server picker (`+`), quick command trigger (`⚡`), and terminal grid dimensions (`76×66`).
  * **Interactive `+` Server Picker Sheet**: Bottom sheet listing saved servers to open a new tab instantly.
  * **`⚡` Quick Command Overlay**: Bottom sheet showing saved CLI presets to execute commands directly into the active shell.
  * **Terminal Canvas (`xterm.dart`)**: Auto-fits font size (80 cols portrait, 120 cols landscape), pinch-to-zoom support, 256-color palette.
  * **Touch Keyboard Bar**: Dark glass bottom bar with `TAB`, `ESC`, `↑`, `↓`, `←`, `→`, `CTRL`, `/`, `|`, `-`, and `⚡` keys.
* **State & Navigation**: Runs inside `StatefulShellRoute` (Branch 1) so SSH connections stay alive when navigating back to Home. Auto-redirects to `/` when all tabs are closed.

---

### 4. 📝 Profile Editor Screen (`ProfileEditorScreen`)
* **File**: [`lib/screens/profile_editor_screen.dart`](file:///D:/A-PC%20FILES/Desktop/OPA/lib/screens/profile_editor_screen.dart)
* **Purpose**: Create or edit SSH connection profiles.
* **UI/UX Breakdown**:
  * **Configuration Form**: Server Label, Host IP/Domain, Port (default 22), Username.
  * **Auth Selector**: Segmented toggle for `Password`, `Public Key`, or `Password + Key`.
  * **Key Picker**: Dropdown to choose from saved SSH Key Pairs in Keystore.
  * **Tailscale WireGuard Switch**: Toggle to route connection via embedded Tailscale Go FFI node.
  * **Palette Picker**: Color selector for server tile color coding.
  * **Test Connection Button**: One-off connection tester verifying SSH handshake without corrupting active sessions.
* **State & Navigation**: Persists profiles to Hive `connection_profiles` box and returns to `/`.

---

### 5. 📁 SFTP Remote File Browser Screen (`SftpScreen`)
* **File**: [`lib/screens/sftp_screen.dart`](file:///D:/A-PC%20FILES/Desktop/OPA/lib/screens/sftp_screen.dart)
* **Purpose**: Remote file management over SSH/SFTP.
* **UI/UX Breakdown**:
  * **Interactive Breadcrumb Path Bar**: Tapable path segments (`/` `var` `log` `nginx`) for quick directory navigation.
  * **File List View**: Displays directories, text files, binary files, permissions (`rwxr-xr-x`), sizes, and timestamps.
  * **File Actions Modal**: Bottom sheet for `Download`, `Delete`, `Rename`, `View/Edit`, and `Permissions`.
  * **"Open in Terminal" App Bar Action**: Button to immediately open an SSH terminal tab at the current remote directory path.

---

### 6. ⚡ Quick Commands Screen (`QuickCommandsScreen`)
* **File**: [`lib/screens/quick_commands_screen.dart`](file:///D:/A-PC%20FILES/Desktop/OPA/lib/screens/quick_commands_screen.dart)
* **Purpose**: Manage saved command snippets and one-tap scripts.
* **UI/UX Breakdown**:
  * **Command Deck**: Searchable preset launcher with uniform AI, development, and system folders; system actions use the same two-column tile layout as the other groups.
  * **Layout Edit Mode**: Long-press any preset or saved-command tile to enter arrangement mode and drag it to reorder it; preset tiles can also move between groups. The arrange button remains pinned in the app bar for an explicit edit session.
  * **Folder Resizing**: Arrange mode exposes persisted `− / row count / +` controls for changing how many preset rows each category folder shows; folder height fits the populated tiles.
  * **Compact Empty State**: A static inline hint replaces the animated empty-state glow so the deck remains the visual focus when no saved commands exist.
  * **Tab Picker Dialog**: When executing a command, prioritizes active terminal tabs, with options to launch a new tab or run once without a persistent terminal.
  * **Runtime Profile Selection**: Commands without a fixed profile prompt for a target server before showing the tab picker.

---

### 7. 📚 Preset Library Screen (`PresetLibraryScreen`)
* **File**: [`lib/screens/preset_editor_screen.dart`](file:///D:/A-PC%20FILES/Desktop/OPA/lib/screens/preset_editor_screen.dart)
* **Purpose**: Catalog of 20+ ready-to-use developer CLI command presets.
* **UI/UX Breakdown**:
  * **Category Tabs**: `Docker`, `Nginx`, `Kubernetes`, `System Monitoring`, `Git`, `Tailscale`.
  * **Preset Cards**: Preset name, command string, description, and "Add to My Commands" button.

---

### 8. 🔑 SSH Keys Manager Screen (`KeyManagerScreen`)
* **File**: [`lib/screens/key_management_screen.dart`](file:///D:/A-PC%20FILES/Desktop/OPA/lib/screens/key_management_screen.dart)
* **Purpose**: Generate, store, and export SSH key pairs securely.
* **UI/UX Breakdown**:
  * **Key Generator Modal**: Supports Ed25519 (recommended) and RSA (2048/4096-bit).
  * **Keystore Protection Badge**: Indicates private keys are locked in Android Keystore (`flutter_secure_storage`).
  * **OpenSSH Public Key Exporter**: 1-tap copy of OpenSSH formatted public key (`ssh-ed25519 AAAAC3...`) to paste into `authorized_keys`.

---

### 9. 🌐 Tailscale Mesh Screen (`TunnelScreen`)
* **File**: [`lib/screens/tunnel_screen.dart`](file:///D:/A-PC%20FILES/Desktop/OPA/lib/screens/tunnel_screen.dart)
* **Purpose**: Configure and control SSH port forwarding for a saved profile.
* **UI/UX Breakdown**:
  * **Tunnel List**: Shows configured local, remote, and dynamic SOCKS5 forwards.
  * **Active State**: Start/stop controls reflect the connected SSH session.
  * **Add Tunnel Sheet**: Validates local/remote ports and uses safe-area-aware input handling.

---

### 10. ⚙️ Settings & About Screen (`SettingsScreen`)
* **File**: [`lib/screens/settings_screen.dart`](file:///D:/A-PC%20FILES/Desktop/OPA/lib/screens/settings_screen.dart)
* **Purpose**: App settings, security preferences, and update checker.
* **UI/UX Breakdown**:
  * **Security Section**: Biometric Lock toggle (`local_auth`).
  * **Terminal Theme Preferences**: Default font size, term environment (`xterm-256color`), scrollback lines.
  * **About Card**: Installed app version (`v0.5.0+3`), GitHub repository link, and manual **"Check Update"** button with SemVer parsing & ETag 304 cache.
