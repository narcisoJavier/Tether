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

## ✨ Features

### 🚇 Port Forwarding & Tunnels
Fully integrated SSH tunneling support! Set up **Local**, **Remote**, and **Dynamic (SOCKS5)** port forwarding directly from the **Tunnels** screen. Tunnels can be set to auto-start when the connection opens, allowing for seamless background networking.

### 🌌 Premium "Deep Space" Redesign
The entire app features a premium aesthetic with layered midnight navy surfaces, glowing neon accents, and frosted glass components. The `ConnectionTile` is highly legible and features a smooth swipe-to-reveal action menu.

### 🚀 Built-in Tailscale Networking
OPA embeds Tailscale userspace networking directly — no separate app, no VPN profile. Join your tailnet from inside OPA, discover peers by MagicDNS, and connect over encrypted WireGuard tunnels. Your servers don't even need public IPs. The Go-based Tailscale runtime (tsnet) compiles alongside the app — one APK, zero external dependencies.

### ⚡ Swipe-to-Reveal Actions
Compact **swipeable tiles** — swipe left on any connection to reveal instant-action buttons: **SFTP**, **Config**, **Tunnels**, and **QCMD** (Quick Commands). Tap the tile to go straight to the terminal — no more extra screens between you and your shell.

### 🔒 Secure by Default
Private keys and passwords live exclusively in the hardware-backed **Android Keystore**, never in plaintext local storage. Features a robust biometric lock enforced at the routing layer for instant, secure authentication. Zero telemetry, zero cloud sync.

---

## 📱 How It Works

### One-Tap Connections
Add a server once — host, port, username, auth method — and it's saved forever. Your connection list becomes a launchpad. **Tap any tile** and you're in a full SSH session instantly. Each connection gets a color-coded accent bar so you can spot production, staging, and dev at a glance.

### Terminal, Reimagined for Mobile
The terminal is a first-class mobile experience:
- **Auto-fit font** — 80+ columns in portrait, 120+ in landscape
- **Rotate to immersive** — landscape hides everything but the shell
- **Smart keyboard bar** — TAB, ESC, arrows, Ctrl+C always one tap away
- **VT100/256-color** — full terminal emulation via xterm.dart
- **Scrollback** — never miss output that scrolls off screen

### Agent Presets — Launch Anything
20+ pre-built quick commands for the tools you actually use:
- **AI Agents:** Claude Code, opencode, aider, Gemini CLI, Codex
- **Dev Tools:** htop, lazygit, tmux, nvim, btop, fastfetch
- **System:** journalctl, docker ps, df -h, free -m, ss -tulpn
- **Network:** iperf3, mtr, nmap, tcpdump, traceroute

---

## 🏗 Architecture

<details>
<summary><b>Click to expand Architecture Details</b></summary>

~~~
OPA App
  Home Screen (ConnectionTile) --> Terminal Screen (xterm.dart)
    --> dartssh2 (SSH via password, key, or both)
      --> Tailscale (embedded tsnet: WireGuard, MagicDNS, DERP)
        --> Target server

Persistent storage:
  Hive DB --> profiles, quick commands
  Android Keystore --> private keys, passwords (hardware-backed)
  SharedPrefs --> onboarding state
~~~

### Key Decisions

| Decision | Why |
|----------|-----|
| **Flutter + Dart** | Cross-platform, native perf, mature ecosystem |
| **dartssh2** | Pure-Dart SSH — no native bindings, full control |
| **xterm.dart** | VT100/256-color terminal widget with scrollback |
| **Tailscale (embedded)** | Per-process tsnet, no VPN app or root needed |
| **ConnectionTile (swipe)** | GestureDetector + AnimationController, no extra deps |
| **Hive** | Fast local NoSQL, no SQLite boilerplate |
| **Riverpod** | Compile-safe state, context-independent |
| **Android Keystore** | HW-backed storage, keys never leave secure enclave |
</details>

---

## 🚀 Getting Started

### Install
Download the latest APK from [GitHub Releases](https://github.com/2241812/OPA_Flutter/releases/latest).

### Build from Source
Prerequisites: Flutter SDK >= 3.0, Go >= 1.26 (for Tailscale native compilation), Android NDK.

~~~bash
git clone https://github.com/2241812/OPA_Flutter.git
cd OPA_Flutter
flutter pub get
flutter run             # Run on connected device
flutter build apk --release  # Release APK
~~~

### First-Time Setup
1. Swipe through the 4-slide onboarding or tap Skip.
2. Tap `+` to add your first server (host, port 22, username, auth method).
3. Set up key-based auth: `SSH Keys` -> `+` -> `Generate Ed25519 Key` -> `Copy`.
   *On your server:* `echo "ssh-ed25519 AAAAC3... opa" >> ~/.ssh/authorized_keys`
4. Tap any connection tile to open the terminal instantly.
5. Swipe left for SFTP, Config, Tunnels, or QCMD quick commands.

---

## 🌐 Setting Up a Target Server

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

## 🔒 Security Model

| Layer | How OPA Protects You |
|-------|----------------------|
| **Private Keys & Passwords** | Android Keystore — hardware-backed, never exposed as plaintext |
| **SSH Transport** | Direct socket, encrypted by SSH protocol, no MITM |
| **Tailscale** | WireGuard end-to-end, DERP relayed only when necessary |
| **Network** | Fully offline — zero telemetry, zero cloud, zero third-party |
| **App Access** | Biometric lock (fingerprint or face) handled securely at the routing layer |

---

## 🗺 Roadmap

- [x] Port forwarding UI - local, remote, dynamic (SOCKS5) tunnels
- [x] Android Keystore hardware-backed password security
- [ ] SFTP file browser — upload, download, manage remote files
- [ ] Jump host / bastion — chain through servers
- [ ] SSH agent forwarding — use local keys remotely
- [ ] Session recording and replay
- [ ] Profile import and export
- [ ] Custom preset editor
- [ ] iOS support
- [ ] Split APKs by ABI for smaller downloads
- [ ] Tailscale Taildrop — P2P file transfers over tailnet

---

<div align="center">

## 📄 License

[MIT](LICENSE) | Built with love by Renzo Javier

*OPA is not affiliated with OpenSSH, Tailscale, or any referenced tool.*

</div>
