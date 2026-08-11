---
name: OPA "Apple TUI"
colors:
  primary: "#0A84FF"
  secondary: "#FF9F0A"
  surface-0: "#1C1C1E"
  surface-1: "#2C2C2E"
  surface-2: "#3A3A3C"
  on-surface: "#FFFFFF"
  error: "#FF5370"
  accent-purple: "#BF5AF2"
typography:
  body-md:
    fontFamily: Inter
    fontSize: 14px
    fontWeight: 400
  display-code:
    fontFamily: JetBrains Mono
    fontSize: 14px
    fontWeight: 400
rounded:
  sm: 8px
  md: 12px
  lg: 16px
  xl: 20px
  sheet: 24px
---

# Design System — OPA (Apple TUI 2.0)

## Overview

OPA (OpenSSH Pocket Agent) is a premium OLED-dark mobile SSH client and Tailscale node. 
The design language — **Apple TUI** — bridges the elegance of modern iOS glassmorphism with the dense, high-contrast utility of retro terminal dashboards. Every pixel is optimized for one-handed mobile terminal use: zero-light OLED black canvas, subtle frosted glass elevation layers, 10-segment pip stat indicators, and crisp JetBrains Mono + Inter typography.

---

## 🎨 Color Palette & Elevation

### 1. Canvas Layers
| Token | Hex | Role |
|-------|-----|------|
| `bg-base` | `#000000` | Pure OLED black scaffold background. Zero backlight drain on OLED displays. |
| `bg-deep` | `#000000` | Persistent navigation bar & status bar background. |

### 2. Surface Elevation Tokens
| Token | Hex | Blur / Fill | Usage |
|-------|-----|-------------|-------|
| `surface-0` | `#1C1C1E` | Inset fill (100%) | Form input fields, search bars, inset list items |
| `surface-1` | `#2C2C2E` | Card surface (70-95%) | Connection tiles, quick command items, key cards |
| `surface-2` | `#3A3A3C` | Modal surface (90-100%) | Bottom sheets, dialogs, floating action menus, snackbars |

### 3. Borders & Divider Strokes
| Token | Alpha | Spec | Usage |
|-------|-------|------|-------|
| `border-0` | `6% white` | `0x0FFFFFFF` | Standard card outlines, list dividers |
| `border-1` | `12% white` | `0x1FFFFFFF` | Hover, selected, or active state outlines |

### 4. Accent Tokens
- **Primary / System Blue** (`#0A84FF`): Active tabs, primary CTAs, switches, focus rings, status indicators.
  > *Code Mapping Note:* `AppConstants.primaryGreen` maps to `#0A84FF` for historical reasons; all UI uses it as Apple System Blue.
- **Accent Amber** (`#FF9F0A`): Warnings, active SSH session stats, scrollback slider, config actions.
- **Accent Purple** (`#BF5AF2`): Power features, Ed25519 key management indicators.
- **Error / Destructive** (`#FF5370`): Validation failures, disconnect actions, error state borders.

---

## 🔤 Typography Hierarchy

### 1. Inter — UI & Controls
| Role | Weight | Size | Usage |
|------|--------|------|-------|
| Headline Large | 800 | 28–32px | Primary screen titles |
| Title Large | 700 | 17px | Centered AppBar title (0.6 letterSpacing) |
| Title Medium | 600 | 15–16px | Connection profile names, card titles |
| Body Medium | 400 | 14px | Modal text, body paragraphs, form labels |
| Body Small | 400 | 12–13px | Muted subtitles (55% white) |
| Label Large | 600 | 14px | Action buttons, sheet submit triggers |
| Label Small | 600 | 12px | Uppercase section headers (`DISPLAY`, `SECURITY`) |

### 2. JetBrains Mono — Code & Terminal Data
| Role | Weight | Size | Usage |
|------|--------|------|-------|
| Code Display | 400 | 13–15px | Live terminal emulator output (xterm.dart) |
| Code Badge | 600 | 11–12px | RPG stat indicators, version badges, SSH ports |

---

## 📱 Components & Signature Controls

### 1. RPG Stat Connection Cards (`ConnectionTile`)
- **Container:** `GlassDecoration` with top-left `surface-1` (95%) to bottom-right `surface-0` (90%) gradient.
- **Accent Strip:** 4px vertical color strip on the left edge denoting server environment color.
- **10-Segment Pip Bars:**
  - **`AUTH`**: Password/Key status (10 filled pips = authenticated).
  - **`SHELL`**: Active PTY session indicator (green/blue animated pips).
  - **`TUNNL`**: WireGuard/Tailscale mesh tunnel state.
- **Footer:** Host IP, port, and quick-connect action trigger.

### 2. Tabbed Terminal Screen (`TabbedTerminalScreen`)
- **Top Tab Bar:** Horizontal scrollable tab strip with 12px radius pill tabs. Active tab highlighted with `surface-2` + System Blue top indicator.
- **Session Bar:** Micro status strip showing active connection state (`Connecting 🟡`, `Connected 🟢`, `Disconnected 🔴`).
- **Touch Keyboard Bar:** Fixed bottom bar providing quick access to `ESC`, `CTRL`, `TAB`, `|`, `/`, `~`, `SHIFT`, and directional arrows.

### 3. Glass App Bar (`GlassAppBar`)
- **Height:** 54px toolbar height + `MediaQuery.paddingOf(context).top`.
- **Blur:** `BackdropFilter` with `sigmaX: 20`, `sigmaY: 20`.
- **Title:** Centered `Inter` Title Large (17px, 600 weight).

### 4. Quick Command Sheets (`QuickCommandsScreen`)
- **Sheet Radius:** 24px top rounded corners with 40×4px pill drag handle.
- **Category Filter Chips:** Horizontal scrolling tag chips (`All`, `Docker`, `System`, `Git`).
- **Tab Picker Dialog:** Interactive modal prompting user to select an existing terminal tab or spawn a new tab for command execution.

---

## 📐 Layout & Spacing Rules

- **Horizontal Margin:** 16px page padding on mobile.
- **Card Spacing:** 8px vertical gap between profile cards.
- **Section Headers:** Uppercase 12px, 600 weight, 40% white, 4px left padding.
- **Touch Target Minimum:** 44×44px for all interactive buttons and chips.

---

## 🛠️ Implementation Mapping

| Token / Asset | File Path |
|---------------|-----------|
| Color Tokens | [`lib/utils/constants.dart`](file:///D:/A-PC%20FILES/Desktop/OPA/lib/utils/constants.dart) |
| Theme Definition | [`lib/app_theme.dart`](file:///D:/A-PC%20FILES/Desktop/OPA/lib/app_theme.dart) |
| Glass Decoration | `GlassDecoration` in [`lib/app_theme.dart`](file:///D:/A-PC%20FILES/Desktop/OPA/lib/app_theme.dart#L150) |
| App Bar Widget | `GlassAppBar` in [`lib/widgets/gradient_scaffold.dart`](file:///D:/A-PC%20FILES/Desktop/OPA/lib/widgets/gradient_scaffold.dart#L50) |
| Connection Cards | `ConnectionTile` in [`lib/widgets/connection_tile.dart`](file:///D:/A-PC%20FILES/Desktop/OPA/lib/widgets/connection_tile.dart) |
