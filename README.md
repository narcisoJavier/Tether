<div align="center">

<img src="https://raw.githubusercontent.com/2241812/OPA_Flutter/main/assets/icon.png" alt="OPA Logo" width="120" height="120">

# ⬡ OPA — OpenSSH Pocket Agent

**Your server in your pocket. One tap to connect, swipe to command, everything encrypted.**

[![Flutter](https://img.shields.io/badge/Flutter-3.44-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-3.12-0175C2?logo=dart&logoColor=white)](https://dart.dev)
[![Platform](https://img.shields.io/badge/Platform-Android-3DDC84?logo=android&logoColor=white)](https://github.com/2241812/OPA_Flutter/releases)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

</div>

---

## The Story

It starts the same way every time.

You're away from your desk — couch, commute, cafe — and something breaks on the server. A deploy stalled. A process OOM'd. A log you need to grep. You reach for your phone... and then the dance begins.

Find the SSH client. Type the host. Type the port. Type the username. Pray you remember the password or have a key handy. Wait for it to connect. And then you're staring at a tiny terminal with a keyboard that eats half the screen, fighting autocorrect on every grep flag.

There had to be a better way.

OPA was born from that frustration. Not another terminal emulator — a pocket operations center that makes connecting to any machine feel as natural as opening an app. One tap. Full terminal. Your keys, your commands, your presets — all there, all secure, all offline.

No VPN required. No cloud dependency. No subscription. Just SSH, done right.

---

## What's New — v0.3

### Swipe-to-Reveal Actions
Connection cards are gone. Compact **swipeable tiles** take their place — swipe left on any connection to reveal instant-action buttons: **SFTP**, **Config**, and **QCMD** (Quick Commands). Tap goes straight to terminal — no more extra screens between you and your shell.

### Built-in Tailscale Networking
OPA now embeds Tailscale userspace networking directly — no separate app, no VPN profile. Join your tailnet from inside OPA, discover peers by MagicDNS, and connect over encrypted WireGuard tunnels. Your servers don't need public IPs.

### Embedded Native Engine
The Go-based Tailscale runtime (tsnet) compiles alongside the app — one APK, zero external dependencies.

### Secure by Default
Private keys live in Android Keystore, passwords in local Hive, biometric lock available. Zero telemetry, zero cloud sync.

---

## How It Works

### One-Tap Connections
Add a server once — host, port, username, auth method — and it's saved forever. Your connection list becomes a launchpad. **Tap any tile** and you're in a full SSH session before the thought finishes.

Each connection gets a color-coded accent bar so you can spot production, staging, and dev at a glance.

### Swipe to Command
Swipe left on any connection tile and three buttons slide in:
- **SFTP** — browse remote files
- **Config** — edit connection details
- **QCMD** — launch quick commands against this server

Release and the tile snaps back. No accidental triggers, no friction.

### Terminal, Reimagined for Mobile
The terminal is a first-class mobile experience:
- **Auto-fit font** — 80+ columns in portrait, 120+ in landscape
- **Rotate to immersive** — landscape hides everything but the shell
- **Smart keyboard bar** — TAB, ESC, arrows, Ctrl+C always one tap away
- **VT100/256-color** — full terminal emulation via xterm.dart
- **Scrollback** — never miss output that scrolls off screen

### Your Keys, Your Way
Generate Ed25519 key pairs in the app, or import existing ones. Private keys never leave your device — stored encrypted in Android Keystore.

### Agent Presets — Launch Anything
20+ pre-built quick commands for the tools you actually use:
- **AI Agents:** Claude Code, opencode, aider, Gemini CLI, Codex
- **Dev Tools:** htop, lazygit, tmux, nvim, btop, fastfetch
- **System:** journalctl, docker ps, df -h, free -m, ss -tulpn
- **Network:** iperf3, mtr, nmap, tcpdump, traceroute

---

## Architecture

Architecture section:
Home Screen (ConnectionTile) to Terminal Screen (xterm.dart)

~~~
OPA App
  Home Screen (ConnectionTile) --> Terminal Screen (xterm.dart)
    --> dartssh2 (SSH via password, key, or both)
      --> Tailscale (embedded tsnet: WireGuard, MagicDNS, DERP)
        --> Target server

Persistent storage:
  Hive DB --> profiles, quick commands
  Android Keystore --> private keys (hardware-backed)
  SharedPrefs --> onboarding state
~~~

### Key Decisions

| Decision | Why |
|----------|-----|
| Flutter + Dart | Cross-platform, native perf, mature ecosystem |
| dartssh2 | Pure-Dart SSH -- no native bindings, full control |
| xterm.dart | VT100/256-color terminal widget with scrollback |
| Tailscale (embedded) | Per-process tsnet, no VPN app or root needed |
| ConnectionTile (swipe) | GestureDetector + AnimationController, no extra deps |
| Hive | Fast local NoSQL, no SQLite boilerplate |
| Riverpod | Compile-safe state, context-independent |
| Android Keystore | HW-backed storage, keys never leave secure enclave |

---

## Project Structure

~~~
lib/
+-- main.dart                       # App entry -- Hive init, theme, routing
+-- app_theme.dart                  # Dark glassmorphism theme
+-- app_router.dart                 # GoRouter + onboarding guard
+-- models/
|   +-- connection_profile.dart     # SSH profile (host, port, auth)
|   +-- ssh_key_pair.dart           # Ed25519 key metadata
|   +-- quick_command.dart          # Saved command + presets
+-- services/
|   +-- ssh_service.dart            # dartssh2 wrapper
|   +-- key_service.dart            # Key gen + Keystore CRUD
|   +-- onboarding_service.dart     # First-launch detection
|   +-- update_service.dart         # GitHub Releases update check
|   +-- profile_storage_service.dart # Hive persistence
|   +-- hive_adapters.dart          # Hive type adapters
+-- screens/
|   +-- home_screen.dart            # Connection tiles + commands
|   +-- onboarding_screen.dart      # 4-slide welcome flow
|   +-- terminal_screen.dart        # xterm.dart + auto-fit + keyboard bar
|   +-- profile_editor_screen.dart  # Add/edit connections
|   +-- key_management_screen.dart  # Generate/import/delete keys
|   +-- quick_commands_screen.dart  # Preset browser + custom
+-- widgets/
|   +-- connection_tile.dart        # Swipeable tile -- tap/swipe actions
|   +-- key_card.dart               # Glassmorphism key card
+-- utils/
    +-- constants.dart              # Colors, spacing, constants
    +-- agent_presets.dart          # 20+ agent/tool presets
    +-- ssh_key_encoder.dart        # Ed25519 wire format encoding
~~~

---

## Getting Started

### Install
Download the latest APK from [GitHub Releases](https://github.com/2241812/OPA_Flutter/releases/latest).
Auto-updates are built in -- OPA checks for new versions on launch.

### Build from Source
Prerequisites: Flutter SDK >= 3.0, Go >= 1.26 (for Tailscale native compilation), Android NDK.

~~~bash
git clone https://github.com/2241812/OPA_Flutter.git
cd OPA_Flutter
flutter pub get
flutter run             # Run on connected device
flutter build apk --release  # Release APK
~~~

---

## First-Time Setup

1. Swipe through the 4-slide onboarding or tap Skip.
2. Tap + to add your first server (host, port 22, username, auth method).
3. Set up key-based auth: SSH Keys -> + -> Generate Ed25519 Key -> Copy.
   On your server: echo "ssh-ed25519 AAAAC3... opa" >> ~/.ssh/authorized_keys
4. Tap any connection tile to open the terminal instantly.
5. Swipe left for SFTP, Config, or QCMD quick commands.

---

## Setting Up a Target Server

<details>
<summary><b>Windows (OpenSSH Server)</b></summary>

~~~powershell
# Install (run as Administrator)
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
# Start and enable
Start-Service sshd
Set-Service -Name sshd -StartupType Automatic
# Find your IP
ipconfig
~~~
</details>

<details>
<summary><b>Linux</b></summary>

~~~bash
sudo apt install openssh-server
sudo systemctl enable --now ssh
~~~
</details>

<details>
<summary><b>macOS</b></summary>
System Settings -> General -> Sharing -> toggle Remote Login ON.
</details>

---

## Tailscale Networking

OPA embeds package:tailscale - userspace Tailscale networking powered by upstream Go tsnet. No separate Tailscale app needed.

- **Join your tailnet** from inside OPA - authenticate once, connect forever
- **MagicDNS** - reach servers by .ts.net hostname, no IP wrangling
- **WireGuard encryption** - every byte between you and your server
- **DERP relay fallback** - works through restrictive NATs
- **Per-process** - no system-wide VPN, no root, no VPN profile

### Requirements
1. A Tailscale or Headscale tailnet
2. An auth key from your tailnet admin
3. Enable Tailscale in OPA Settings and enter your auth key

The node identity is persisted in the app support directory (excluded from cloud backups).

---

## Tech Stack

| Package | Purpose |
|---------|---------|
| dartssh2 | Pure-Dart SSH client - auth, shell, exec, SFTP |
| xterm | Terminal emulator - VT100, 256-color, scrollback |
| tailscale | Embedded WireGuard tailnet via Go tsnet FFI |
| pinenacl | Ed25519 key pair generation |
| flutter_secure_storage | Encrypted on-device key storage |
| hive + hive_flutter | Local NoSQL profiles and commands |
| flutter_riverpod | Compile-safe state management |
| go_router | Declarative routing with transitions |
| google_fonts | Inter (UI) + JetBrains Mono (terminal) |
| flutter_animate | Spring/fade/slide animations |
| url_launcher | APK download links |
| package_info_plus | Runtime version for update checks |
| local_auth | Biometric app lock |

---

## Security Model

| Layer | How OPA Protects You |
|-------|----------------------|
| Private keys | Android Keystore - hardware-backed, never exposed as plaintext |
| Passwords | Hive database - local only, never sent externally |
| SSH transport | Direct socket, encrypted by SSH protocol, no MITM |
| Tailscale | WireGuard end-to-end, DERP relayed only when necessary |
| Network | Fully offline - zero telemetry, zero cloud, zero third-party |
| App access | Optional biometric lock (fingerprint or face) |
| Backup | Tailscale state dir excluded from cloud backups |

---

## Roadmap

- [ ] SFTP file browser - upload, download, manage remote files
- [ ] Port forwarding UI - local, remote, dynamic (SOCKS5) tunnels
- [ ] Jump host / bastion - chain through servers
- [ ] SSH agent forwarding - use local keys remotely
- [ ] Session recording and replay
- [ ] Profile import and export
- [ ] Custom preset editor
- [ ] iOS support
- [ ] Split APKs by ABI for smaller downloads
- [ ] Tailscale Taildrop - P2P file transfers over tailnet

---

<div align="center">

## License

[MIT](LICENSE)  Built with love by Renzo Javier

*OPA is not affiliated with OpenSSH, Tailscale, or any referenced tool.*

</div>
