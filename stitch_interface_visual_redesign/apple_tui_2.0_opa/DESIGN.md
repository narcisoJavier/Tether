---
name: Apple TUI 2.0 / Tether
colors:
  surface: '#10131b'
  surface-dim: '#10131b'
  surface-bright: '#363941'
  surface-container-lowest: '#0b0e15'
  surface-container-low: '#181c23'
  surface-container: '#1c2027'
  surface-container-high: '#262a32'
  surface-container-highest: '#31353d'
  on-surface: '#e0e2ed'
  on-surface-variant: '#c0c6d6'
  inverse-surface: '#e0e2ed'
  inverse-on-surface: '#2d3038'
  outline: '#8b91a0'
  outline-variant: '#414754'
  surface-tint: '#aac7ff'
  primary: '#aac7ff'
  on-primary: '#003064'
  primary-container: '#3e90ff'
  on-primary-container: '#002957'
  inverse-primary: '#005db8'
  secondary: '#c2c1ff'
  on-secondary: '#1800a7'
  secondary-container: '#3630bf'
  on-secondary-container: '#b1b1ff'
  tertiary: '#ffb691'
  on-tertiary: '#552000'
  tertiary-container: '#eb6a12'
  on-tertiary-container: '#4a1b00'
  error: '#ffb4ab'
  on-error: '#690005'
  error-container: '#93000a'
  on-error-container: '#ffdad6'
  primary-fixed: '#d6e3ff'
  primary-fixed-dim: '#aac7ff'
  on-primary-fixed: '#001b3e'
  on-primary-fixed-variant: '#00468d'
  secondary-fixed: '#e2dfff'
  secondary-fixed-dim: '#c2c1ff'
  on-secondary-fixed: '#0c006b'
  on-secondary-fixed-variant: '#332dbc'
  tertiary-fixed: '#ffdbcb'
  tertiary-fixed-dim: '#ffb691'
  on-tertiary-fixed: '#341100'
  on-tertiary-fixed-variant: '#793100'
  background: '#10131b'
  on-background: '#e0e2ed'
  surface-variant: '#31353d'
  oled-black: '#000000'
  glass-surface: rgba(28, 28, 30, 0.7)
  neon-blue-glow: '#00CCFF'
  pip-critical: '#FF453A'
  pip-warning: '#FFD60A'
  pip-success: '#32D74B'
  terminal-dim: '#8E8E93'
typography:
  headline-lg:
    fontFamily: Hanken Grotesk
    fontSize: 32px
    fontWeight: '700'
    lineHeight: 40px
    letterSpacing: -0.02em
  headline-md:
    fontFamily: Hanken Grotesk
    fontSize: 24px
    fontWeight: '600'
    lineHeight: 32px
  body-lg:
    fontFamily: Hanken Grotesk
    fontSize: 16px
    fontWeight: '400'
    lineHeight: 24px
  code-display:
    fontFamily: JetBrains Mono
    fontSize: 15px
    fontWeight: '500'
    lineHeight: 22px
  code-sm:
    fontFamily: JetBrains Mono
    fontSize: 12px
    fontWeight: '400'
    lineHeight: 16px
  label-caps:
    fontFamily: JetBrains Mono
    fontSize: 11px
    fontWeight: '700'
    lineHeight: 14px
    letterSpacing: 0.08em
  pip-label:
    fontFamily: JetBrains Mono
    fontSize: 10px
    fontWeight: '800'
    lineHeight: 12px
rounded:
  sm: 0.25rem
  DEFAULT: 0.5rem
  md: 0.75rem
  lg: 1rem
  xl: 1.5rem
  full: 9999px
spacing:
  terminal-gutter: 1rem
  card-padding: 1.25rem
  chip-gap: 0.5rem
  header-height: 36px
  stack-tight: 0.25rem
---

## Brand & Style

The design system embodies a futuristic, developer-centric aesthetic dubbed **Apple TUI 2.0**. It balances the clinical precision of a high-end terminal interface with the depth and elegance of modern glassmorphism. Designed for advanced users, the UI should feel exceptionally responsive, secure, and performant.

The visual narrative is built on **OLED Blacks** and **Glassmorphism**, creating a sense of infinite depth. It draws inspiration from tactical military interfaces and premium creative software, utilizing high-contrast typography and glowing neon accents to guide the user's eye toward critical system states. The atmosphere is quiet but powerful—a "silent operator" tool for high-stakes server management.

## Colors

The palette is optimized for OLED displays, utilizing absolute black (`#000000`) as the foundation to minimize power consumption and maximize contrast. 

- **Primary & Secondary**: "System Blue" and vibrant indigo create the "Apple TUI" signature. Use these for active states and primary actions.
- **Neon Accents**: A secondary "Glow Blue" is reserved for status indicators, logo iconography, and active terminal cursors to evoke a futuristic feel.
- **Pip Status**: A strict traffic-light system (Red, Yellow, Green) provides instant visual telemetry for server health and connection status.
- **Neutral/Surface**: Surfaces use semi-transparent dark grays with backdrop blurring to create the glassmorphism effect.

## Typography

This design system uses a dual-font approach to distinguish between "Interface" and "Data."

1.  **Hanken Grotesk**: Used for the UI shell, headings, and primary navigation. It provides a clean, modern, and readable sans-serif experience that feels premium.
2.  **JetBrains Mono**: The workhorse for terminal output, command chips, and "RPG-style" stat cards. It reinforces the technical nature of the application and ensures perfect alignment for tabular data.

All code-based typography should utilize slightly increased line height to improve legibility during long debugging sessions. Labels for status bars and technical specs should be in uppercase to mimic industrial hardware labeling.

## Layout & Spacing

The layout follows a **Fixed Grid** philosophy within high-level containers (cards/sheets) but shifts to a **Fluid Grid** for the terminal canvas. 

- **Density**: High density is preferred. Developers need to see maximum information with minimal scrolling.
- **Rhythm**: A 4px baseline grid governs all spacing.
- **Mobile Adjustments**: On mobile, side margins are reduced to 16px to maximize terminal width. The 36px header remains constant across all views to preserve vertical screen real estate for the CLI.
- **Breakpoints**: 
    - **Phone**: Single column, full-width cards.
    - **Tablet**: 12-column grid allowing for a persistent sidebar for server lists alongside the terminal.

## Elevation & Depth

Hierarchy is established through **Backdrop Blurs** and **Inner Glows** rather than traditional drop shadows.

1.  **Level 0 (Base)**: Absolute OLED Black.
2.  **Level 1 (Cards)**: `glass-surface` with a 20px blur and a 0.5px "stroke" border in a low-opacity white (10%).
3.  **Level 2 (Overlays/Modals)**: Increased blur (40px) and a subtle inner-glow using the `primary_color_hex` at 5% opacity to indicate interaction readiness.
4.  **Indicators**: Use "Ambient Glow" for active status. An active server tile should have a soft, diffused outer glow of the `neon-blue-glow` to differentiate it from disconnected nodes.

## Shapes

The design system uses "Rounded" geometry to soften the technical edge of the terminal. 

- **Primary Containers**: 0.5rem (8px) corner radius.
- **Command Chips**: Fully rounded (Pill-shaped) to distinguish them from interactive buttons.
- **Terminal Canvas**: Sharp 0px corners to maximize the character grid, but housed within a 0.5rem rounded glass container.
- **Buttons**: 0.5rem radius, ensuring a consistent look with the cards they inhabit.

## Components

### Terminal-Style Stat Cards (RPG Style)
Cards should display server stats as a vertical list of monospace attributes. Each attribute (CPU, RAM, DISK) is paired with a **Pip Status Bar**. Use `code-sm` for the labels and a "filled segment" bar style where the background is a dim gray and the progress is highlighted in System Blue.

### Pip Status Bars
Horizontal progress bars divided into 10 discrete segments. 
- **Green**: 0-60% (Healthy)
- **Yellow**: 61-85% (Warning)
- **Red**: 86-100% (Critical)

### Command Chips
Small, pill-shaped elements with a background of `rgba(255, 255, 255, 0.1)`. They feature a leading `$` or `> ` prefix in `neon-blue-glow`.

### Buttons
- **Primary**: Solid `primary_color_hex` with white text.
- **Secondary (Glass)**: Transparent background, 1px border of System Blue, with blue text. Use for secondary actions like "Test Connection."

### Input Fields
Darker than the card background with a 1px bottom-border only. On focus, the bottom border glows with the primary color and a typewriter-style block cursor should blink in the field.

### SFTP Breadcrumbs
Chevron-separated monospace strings. Active segments are white; parent segments are `terminal-dim`. Tapping a segment triggers a "glitch" transition to the new directory.