# OPA — Screen Architecture & Detailed UI/UX Specifications

> **Application**: OpenSSH Pocket Agent (OPA) v0.5.0  
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
| 9 | **Tailscale Mesh Screen** | `/tunnel/:id` | WireGuard Tailnet | Node status card, peer IP list, MagicDNS info, reconnect & auth actions |
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
  * **Connection Tiles (`ConnectionTile`)**: RPG stat card style with pip status bars, host address, SSH port, authentication type badge, and 1-tap SSH / 1-tap SFTP action buttons.
  * **Expandable FAB Menu**: Floating action button expanding into `New Server`, `Manage Keys`, and `Quick Commands`.
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
  * **Command Cards**: Monospace code preview, label, target server profile badge, and execute button.
  * **Tab Picker Dialog**: When executing a command, prompts the user to pick an active terminal tab or launch a new tab.
  * **Preset Library Trigger**: Quick link to import pre-configured developer tools.

---

### 7. 📚 Preset Library Screen (`PresetLibraryScreen`)
* **File**: [`lib/screens/preset_library_screen.dart`](file:///D:/A-PC%20FILES/Desktop/OPA/lib/screens/preset_library_screen.dart)
* **Purpose**: Catalog of 20+ ready-to-use developer CLI command presets.
* **UI/UX Breakdown**:
  * **Category Tabs**: `Docker`, `Nginx`, `Kubernetes`, `System Monitoring`, `Git`, `Tailscale`.
  * **Preset Cards**: Preset name, command string, description, and "Add to My Commands" button.

---

### 8. 🔑 SSH Keys Manager Screen (`KeyManagerScreen`)
* **File**: [`lib/screens/key_manager_screen.dart`](file:///D:/A-PC%20FILES/Desktop/OPA/lib/screens/key_manager_screen.dart)
* **Purpose**: Generate, store, and export SSH key pairs securely.
* **UI/UX Breakdown**:
  * **Key Generator Modal**: Supports Ed25519 (recommended) and RSA (2048/4096-bit).
  * **Keystore Protection Badge**: Indicates private keys are locked in Android Keystore (`flutter_secure_storage`).
  * **OpenSSH Public Key Exporter**: 1-tap copy of OpenSSH formatted public key (`ssh-ed25519 AAAAC3...`) to paste into `authorized_keys`.

---

### 9. 🌐 Tailscale Mesh Screen (`TunnelScreen`)
* **File**: [`lib/screens/tunnel_screen.dart`](file:///D:/A-PC%20FILES/Desktop/OPA/lib/screens/tunnel_screen.dart)
* **Purpose**: Inspect embedded Tailscale WireGuard network status.
* **UI/UX Breakdown**:
  * **Node Info Card**: Self IP (IPv4/IPv6), MagicDNS domain suffix, Node ID.
  * **Peer Devices List**: Shows online/offline Tailnet peer devices with ping round-trip latency.
  * **Re-auth / Key Input**: Re-authenticate node or update Tailscale auth key.

---

### 10. ⚙️ Settings & About Screen (`SettingsScreen`)
* **File**: [`lib/screens/settings_screen.dart`](file:///D:/A-PC%20FILES/Desktop/OPA/lib/screens/settings_screen.dart)
* **Purpose**: App settings, security preferences, and update checker.
* **UI/UX Breakdown**:
  * **Security Section**: Biometric Lock toggle (`local_auth`).
  * **Terminal Theme Preferences**: Default font size, term environment (`xterm-256color`), scrollback lines.
  * **About Card**: Installed app version (`v0.5.0+3`), GitHub repository link, and manual **"Check Update"** button with SemVer parsing & ETag 304 cache.
