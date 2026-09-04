import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:xterm/xterm.dart';

import '../services/biometric_provider.dart';
import '../services/export_service.dart';
import '../services/key_service.dart';
import '../services/onboarding_service.dart';
import '../services/profile_storage_service.dart';
import '../services/tailscale_provider.dart';
import '../services/update_service.dart';
import '../utils/app_version.dart';
import '../utils/constants.dart';
import '../utils/terminal_settings_provider.dart';
import '../utils/terminal_themes.dart';
import '../widgets/gradient_scaffold.dart';
import '../widgets/settings_group.dart';

/// Redesigned Settings screen featuring Apple TUI 2.0 Inset Grouped Sections,
/// Live VT100 Terminal Preview, and deep terminal customization.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bottomInset = 88 + MediaQuery.paddingOf(context).bottom;

    return GradientScaffold(
      appBar: GlassAppBar(
        title: Text(
          'SETTINGS',
          style: GoogleFonts.jetBrainsMono(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
            color: Colors.white,
          ),
        ),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, 12, 16, bottomInset.toDouble()),
        children: [
          // ── 0. Mesh Node & System Identity Card ──
          const _MeshNodeIdentityCard(),
          const SizedBox(height: 20),

          // ── 1. Live Terminal Preview ──
          const _LiveTerminalPreviewCard(),
          const SizedBox(height: 20),

          // ── 2. Terminal Appearance & Style ──
          _buildTerminalAppearanceGroup(context, ref),

          // ── 3. Keyboard & Interaction ──
          _buildKeyboardInteractionGroup(context, ref),

          // ── 4. Security & Authentication ──
          _buildSecurityGroup(context, ref),

          // ── 5. Data & Storage Enclave ──
          _buildDataStorageGroup(context, ref),

          // ── 6. About & Ecosystem ──
          _buildAboutGroup(context, ref),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ── Terminal Appearance Group ──────────────────────────────────────────────
  Widget _buildTerminalAppearanceGroup(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(terminalThemeProvider);
    final fontSize = ref.watch(terminalFontSizeProvider);
    final cursorType = ref.watch(terminalCursorTypeProvider);
    final cursorBlink = ref.watch(terminalCursorBlinkProvider);
    final fontFamily = ref.watch(terminalFontFamilyProvider);

    return SettingsGroup(
      title: 'Terminal Appearance',
      subtitle: 'Color themes, monospace typefaces, and VT100 cursor styling.',
      children: [
        // Color Theme Tile
        SettingsTile(
          icon: Icons.palette_outlined,
          iconColor: theme.previewColor,
          title: 'Color Theme',
          subtitle: theme.name,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: theme.previewColor,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: theme.previewColor.withValues(alpha: 0.5),
                      blurRadius: 6,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: Colors.white.withValues(alpha: 0.25),
              ),
            ],
          ),
          onTap: () => _showThemePickerModalSheet(context, ref),
        ),

        // Font Family Tile
        SettingsTile(
          icon: Icons.font_download_outlined,
          iconColor: const Color(0xFF448AFF),
          title: 'Monospace Font',
          subtitle: _fontDisplayName(fontFamily),
          trailing: SettingsValuePill(
            text: _fontDisplayName(fontFamily),
            color: const Color(0xFF448AFF),
            onTap: () => _showFontPickerModalSheet(context, ref),
          ),
          onTap: () => _showFontPickerModalSheet(context, ref),
        ),

        // Font Size Stepper & Slider
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: AppConstants.primaryGreen.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: const Icon(
                      Icons.format_size_rounded,
                      size: 18,
                      color: AppConstants.primaryGreen,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Font Size',
                      style: GoogleFonts.inter(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  // Decrement
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline_rounded),
                    iconSize: 20,
                    color: Colors.white.withValues(alpha: 0.6),
                    onPressed: fontSize > AppConstants.minFontSize
                        ? () => ref
                            .read(terminalFontSizeProvider.notifier)
                            .setSize(fontSize - 1)
                        : null,
                  ),
                  SettingsValuePill(
                    text: '${fontSize.toStringAsFixed(0)} pt',
                    color: AppConstants.primaryGreen,
                  ),
                  // Increment
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline_rounded),
                    iconSize: 20,
                    color: Colors.white.withValues(alpha: 0.6),
                    onPressed: fontSize < AppConstants.maxFontSize
                        ? () => ref
                            .read(terminalFontSizeProvider.notifier)
                            .setSize(fontSize + 1)
                        : null,
                  ),
                ],
              ),
              Slider(
                value: fontSize,
                min: AppConstants.minFontSize,
                max: AppConstants.maxFontSize,
                divisions: 52,
                activeColor: AppConstants.primaryGreen,
                inactiveColor: Colors.white.withValues(alpha: 0.08),
                onChanged: (v) =>
                    ref.read(terminalFontSizeProvider.notifier).setSize(v),
              ),
            ],
          ),
        ),

        // Cursor Style Selector
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFD60A).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Icon(
                  Icons.terminal_rounded,
                  size: 18,
                  color: Color(0xFFFFD60A),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Cursor Style',
                  style: GoogleFonts.inter(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
              SegmentedButton<TerminalCursorType>(
                segments: const [
                  ButtonSegment(
                    value: TerminalCursorType.block,
                    label: Text('█'),
                  ),
                  ButtonSegment(
                    value: TerminalCursorType.verticalBar,
                    label: Text('▎'),
                  ),
                  ButtonSegment(
                    value: TerminalCursorType.underline,
                    label: Text(' '),
                  ),
                ],
                selected: {cursorType},
                onSelectionChanged: (s) => ref
                    .read(terminalCursorTypeProvider.notifier)
                    .setType(s.first),
                style: const ButtonStyle(
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
        ),

        // Cursor Blink Switch
        SettingsTile(
          icon: Icons.animation_rounded,
          iconColor: const Color(0xFF18FFFF),
          title: 'Cursor Blinking',
          subtitle: 'Animate terminal cursor pulse',
          trailing: Switch(
            value: cursorBlink,
            onChanged: (_) =>
                ref.read(terminalCursorBlinkProvider.notifier).toggle(),
            activeThumbColor: const Color(0xFF18FFFF),
            inactiveTrackColor: Colors.white.withValues(alpha: 0.1),
          ),
        ),
      ],
    );
  }

  // ── Keyboard & Interaction Group ───────────────────────────────────────────
  Widget _buildKeyboardInteractionGroup(BuildContext context, WidgetRef ref) {
    final haptic = ref.watch(terminalHapticFeedbackProvider);
    final scrollback = ref.watch(terminalScrollbackProvider);
    final keepalive = ref.watch(terminalKeepaliveProvider);

    final scrollbackLabel = scrollback >= 1000
        ? '${(scrollback ~/ 1000)}K lines'
        : '$scrollback lines';

    return SettingsGroup(
      title: 'Keyboard & Terminal Buffer',
      subtitle: 'Haptics, terminal scrollback ceiling, and SSH keepalive pings.',
      children: [
        // Haptic Feedback
        SettingsTile(
          icon: Icons.vibration_rounded,
          iconColor: const Color(0xFFFF2D55),
          title: 'Haptic Feedback',
          subtitle: 'Tactile tick on virtual keyboard keys',
          trailing: Switch(
            value: haptic,
            onChanged: (_) {
              HapticFeedback.selectionClick();
              ref.read(terminalHapticFeedbackProvider.notifier).toggle();
            },
            activeThumbColor: const Color(0xFFFF2D55),
            inactiveTrackColor: Colors.white.withValues(alpha: 0.1),
          ),
        ),

        // Scrollback Lines
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFAB40).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: const Icon(
                      Icons.format_list_numbered_rounded,
                      size: 18,
                      color: Color(0xFFFFAB40),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Scrollback Buffer',
                      style: GoogleFonts.inter(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  SettingsValuePill(
                    text: scrollbackLabel,
                    color: const Color(0xFFFFAB40),
                  ),
                ],
              ),
              Slider(
                value: scrollback.toDouble(),
                min: 500,
                max: 50000,
                divisions: 99,
                activeColor: const Color(0xFFFFAB40),
                inactiveColor: Colors.white.withValues(alpha: 0.08),
                onChanged: (v) => ref
                    .read(terminalScrollbackProvider.notifier)
                    .setLines(v.round()),
              ),
            ],
          ),
        ),

        // Keepalive Interval
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: const Color(0xFF64D2FF).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: const Icon(
                      Icons.timer_outlined,
                      size: 18,
                      color: Color(0xFF64D2FF),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'SSH Keepalive Ping',
                      style: GoogleFonts.inter(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  SettingsValuePill(
                    text: '${keepalive}s',
                    color: const Color(0xFF64D2FF),
                  ),
                ],
              ),
              Slider(
                value: keepalive.toDouble(),
                min: 5,
                max: 300,
                divisions: 59,
                activeColor: const Color(0xFF64D2FF),
                inactiveColor: Colors.white.withValues(alpha: 0.08),
                onChanged: (v) => ref
                    .read(terminalKeepaliveProvider.notifier)
                    .setInterval(v.round()),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Security & Enclave Group ───────────────────────────────────────────────
  Widget _buildSecurityGroup(BuildContext context, WidgetRef ref) {
    final lockEnabled = ref.watch(biometricLockEnabledProvider);
    final onboardingService = ref.watch(onboardingServiceProvider);
    final welcomeEnabled = onboardingService.isWelcomeScreenEnabled();

    return SettingsGroup(
      title: 'Security & Enclave',
      subtitle: 'Biometric gate and startup verification.',
      children: [
        // Biometric Lock
        SettingsTile(
          icon: Icons.fingerprint_rounded,
          iconColor: AppConstants.primaryGreen,
          title: 'Biometric Lock',
          subtitle: 'Require fingerprint or face to open app',
          trailing: Switch(
            value: lockEnabled,
            onChanged: (_) =>
                ref.read(biometricLockEnabledProvider.notifier).toggle(),
            activeThumbColor: AppConstants.primaryGreen,
            inactiveTrackColor: Colors.white.withValues(alpha: 0.1),
          ),
        ),

        // Welcome Tour on Launch
        SettingsTile(
          icon: Icons.waving_hand_rounded,
          iconColor: const Color(0xFFFF9500),
          title: 'Welcome Screen',
          subtitle: 'Show animated welcome card on cold boot',
          trailing: Switch(
            value: welcomeEnabled,
            onChanged: (val) async {
              await onboardingService.setWelcomeScreenEnabled(val);
              (context as Element).markNeedsBuild();
            },
            activeThumbColor: const Color(0xFFFF9500),
            inactiveTrackColor: Colors.white.withValues(alpha: 0.1),
          ),
        ),
      ],
    );
  }

  // ── Data & Storage Group ───────────────────────────────────────────────────
  Widget _buildDataStorageGroup(BuildContext context, WidgetRef ref) {
    return SettingsGroup(
      title: 'Data & Backup',
      subtitle: 'Encrypted backup export and JSON restoration.',
      children: [
        // Export Backup
        SettingsTile(
          icon: Icons.file_upload_outlined,
          iconColor: AppConstants.primaryGreen,
          title: 'Export Backup',
          subtitle: 'Copy profiles & quick commands to clipboard',
          onTap: () async {
            await ExportService.exportToClipboard();
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  backgroundColor: AppConstants.surfaceDark,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: BorderSide(
                      color: AppConstants.primaryGreen.withValues(alpha: 0.3),
                    ),
                  ),
                  content: Row(
                    children: [
                      const Icon(
                        Icons.check_circle_rounded,
                        color: AppConstants.primaryGreen,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Configuration exported to clipboard',
                        style: GoogleFonts.inter(fontSize: 13),
                      ),
                    ],
                  ),
                  duration: const Duration(seconds: 2),
                ),
              );
            }
          },
        ),

        // Import Backup
        SettingsTile(
          icon: Icons.file_download_outlined,
          iconColor: const Color(0xFF007AFF),
          title: 'Import Backup',
          subtitle: 'Restore profiles & commands from JSON',
          onTap: () => _showImportDialog(context, ref),
        ),
      ],
    );
  }

  // ── About & Ecosystem Group ────────────────────────────────────────────────
  Widget _buildAboutGroup(BuildContext context, WidgetRef ref) {
    return SettingsGroup(
      title: 'About Tether',
      children: [
        // Version & Update Check
        FutureBuilder<String>(
          future: AppVersion.get(),
          builder: (context, snapshot) {
            final version = snapshot.data ?? AppVersion.current;
            return SettingsTile(
              icon: Icons.bolt_rounded,
              iconColor: AppConstants.primaryGreen,
              title: AppConstants.appFullTitle,
              subtitle: 'Android • v$version',
              trailing: ElevatedButton(
                onPressed: () => _checkForUpdate(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      AppConstants.primaryGreen.withValues(alpha: 0.15),
                  foregroundColor: AppConstants.primaryGreen,
                  elevation: 0,
                  side: BorderSide(
                    color: AppConstants.primaryGreen.withValues(alpha: 0.3),
                    width: 0.8,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                child: Text(
                  'Check Update',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            );
          },
        ),

        // Replay Onboarding
        SettingsTile(
          icon: Icons.school_outlined,
          iconColor: const Color(0xFFBF5AF2),
          title: 'Replay Tour',
          subtitle: 'Launch autonomous onboarding cards',
          onTap: () => context.push('/onboarding'),
        ),

        // GitHub Repository
        SettingsTile(
          icon: Icons.code_rounded,
          iconColor: Colors.white.withValues(alpha: 0.8),
          title: 'GitHub Repository',
          subtitle: '${AppConstants.gitHubOwner}/${AppConstants.gitHubRepo}',
          onTap: () => launchUrl(
            Uri.parse(
              'https://github.com/${AppConstants.gitHubOwner}/${AppConstants.gitHubRepo}',
            ),
            mode: LaunchMode.externalApplication,
          ),
        ),
      ],
    );
  }

  // ── Modals & Dialogs ───────────────────────────────────────────────────────

  void _showThemePickerModalSheet(BuildContext context, WidgetRef ref) {
    final currentId = ref.read(terminalThemeIdProvider);

    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      useSafeArea: true,
      backgroundColor: AppConstants.surfaceDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Terminal Color Theme',
              style: GoogleFonts.inter(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Select an ANSI palette optimized for OLED displays',
              style: GoogleFonts.inter(
                fontSize: 12,
                color: Colors.white.withValues(alpha: 0.45),
              ),
            ),
            const SizedBox(height: 16),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: TerminalThemePreset.presets.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (ctx, index) {
                  final preset = TerminalThemePreset.presets[index];
                  final isSelected = preset.id == currentId;

                  return Container(
                    decoration: BoxDecoration(
                      color: isSelected
                          ? preset.previewColor.withValues(alpha: 0.12)
                          : Colors.white.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected
                            ? preset.previewColor.withValues(alpha: 0.5)
                            : Colors.white.withValues(alpha: 0.06),
                        width: 1,
                      ),
                    ),
                    child: ListTile(
                      onTap: () {
                        ref
                            .read(terminalThemeIdProvider.notifier)
                            .setTheme(preset.id);
                        Navigator.pop(ctx);
                      },
                      leading: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: preset.previewBackground,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: preset.previewColor.withValues(alpha: 0.4),
                            width: 1.2,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            '>_',
                            style: GoogleFonts.jetBrainsMono(
                              color: preset.previewColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                      title: Text(
                        preset.name,
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w600,
                          fontSize: 14.5,
                          color: Colors.white,
                        ),
                      ),
                      subtitle: Text(
                        preset.description,
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          color: Colors.white.withValues(alpha: 0.4),
                        ),
                      ),
                      trailing: isSelected
                          ? Icon(
                              Icons.check_circle_rounded,
                              color: preset.previewColor,
                              size: 20,
                            )
                          : null,
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showFontPickerModalSheet(BuildContext context, WidgetRef ref) {
    const fonts = [
      ('JetBrainsMono', 'JetBrains Mono', 'Engineered for developer readability'),
      ('FiraCode', 'Fira Code', 'Modern typeface with programming ligatures'),
      ('SpaceMono', 'Space Mono', 'Geometric monospace with retro feel'),
      ('Courier', 'Courier Prime', 'Classic monospace typewriter standard'),
    ];

    final currentFont = ref.read(terminalFontFamilyProvider);

    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      useSafeArea: true,
      backgroundColor: AppConstants.surfaceDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Terminal Font Family',
              style: GoogleFonts.inter(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 16),
            for (final f in fonts) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: f.$1 == currentFont
                      ? AppConstants.primaryGreen.withValues(alpha: 0.1)
                      : Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: f.$1 == currentFont
                        ? AppConstants.primaryGreen.withValues(alpha: 0.4)
                        : Colors.white.withValues(alpha: 0.06),
                  ),
                ),
                child: ListTile(
                  onTap: () {
                    ref.read(terminalFontFamilyProvider.notifier).setFont(f.$1);
                    Navigator.pop(ctx);
                  },
                  title: Text(
                    f.$2,
                    style: GoogleFonts.getFont(
                      f.$1 == 'JetBrainsMono'
                          ? 'JetBrains Mono'
                          : (f.$1 == 'FiraCode'
                              ? 'Fira Code'
                              : (f.$1 == 'SpaceMono'
                                  ? 'Space Mono'
                                  : 'Courier Prime')),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  subtitle: Text(
                    f.$3,
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: Colors.white.withValues(alpha: 0.4),
                    ),
                  ),
                  trailing: f.$1 == currentFont
                      ? const Icon(
                          Icons.check_circle_rounded,
                          color: AppConstants.primaryGreen,
                          size: 20,
                        )
                      : null,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showImportDialog(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
        backgroundColor: AppConstants.surfaceDark,
        title: Text(
          'Import Configuration',
          style: GoogleFonts.inter(fontWeight: FontWeight.w600),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Paste exported JSON to restore profiles and quick commands.',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: Colors.white.withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                maxLines: 8,
                decoration: const InputDecoration(
                  hintText:
                      '{\n  "version": 1,\n  "profiles": [...],\n  "commands": [...]\n}',
                  hintMaxLines: 5,
                ),
                style: GoogleFonts.jetBrainsMono(fontSize: 11),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: GoogleFonts.inter()),
          ),
          ElevatedButton.icon(
            onPressed: () async {
              final json = controller.text.trim();
              if (json.isEmpty) return;
              final result = await ExportService.importFromJson(json);
              if (ctx.mounted) {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Row(
                      children: [
                        Icon(
                          result.success
                              ? Icons.check_circle_rounded
                              : Icons.error_rounded,
                          color: result.success
                              ? AppConstants.primaryGreen
                              : Colors.red,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            result.message,
                            style: GoogleFonts.inter(fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                    duration: const Duration(seconds: 3),
                  ),
                );
              }
            },
            icon: const Icon(Icons.file_download_outlined),
            label: Text('Import', style: GoogleFonts.inter()),
          ),
        ],
      ),
    ).whenComplete(controller.dispose);
  }

  Future<void> _checkForUpdate(BuildContext context) async {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Checking for updates...',
          style: GoogleFonts.inter(fontSize: 13),
        ),
        duration: const Duration(seconds: 2),
      ),
    );
    final update = await UpdateService.checkForUpdate(force: true);
    if (!context.mounted) return;
    if (update != null) {
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppConstants.surfaceDark,
          title: Text(
            'Update Available (${update.latestVersion})',
            style: GoogleFonts.inter(fontWeight: FontWeight.w600),
          ),
          content: Text(
            update.releaseNotes.isNotEmpty
                ? update.releaseNotes
                : 'A new update is ready for download.',
            style: GoogleFonts.inter(
              fontSize: 13,
              color: Colors.white.withValues(alpha: 0.8),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Later', style: GoogleFonts.inter()),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                launchUrl(
                  Uri.parse(update.downloadUrl),
                  mode: LaunchMode.externalApplication,
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppConstants.primaryGreen,
              ),
              child: Text(
                'Download',
                style: GoogleFonts.inter(
                  color: Colors.black,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Tether is up to date!',
            style: GoogleFonts.inter(fontSize: 13),
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  static String _fontDisplayName(String font) {
    switch (font) {
      case 'JetBrainsMono':
        return 'JetBrains Mono';
      case 'FiraCode':
        return 'Fira Code';
      case 'SpaceMono':
        return 'Space Mono';
      case 'Courier':
        return 'Courier Prime';
      default:
        return font;
    }
  }
}

// ── Mesh Node & System Identity Card ─────────────────────────────────────────

class _MeshNodeIdentityCard extends ConsumerWidget {
  const _MeshNodeIdentityCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profiles = ref.watch(profileStorageProvider).listProfiles();
    final keys = ref.watch(keyServiceProvider).listKeys();
    final commands = ref.watch(profileStorageProvider).listCommands();

    final ts = ref.watch(tailscaleServiceProvider);
    final tsState = ref.watch(tailscaleStateProvider).valueOrNull;
    final isMeshConnected = ts.isInitialized && tsState != null;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF14181F),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppConstants.primaryGreen.withValues(alpha: 0.2),
          width: 0.8,
        ),
        boxShadow: [
          BoxShadow(
            color: AppConstants.primaryGreen.withValues(alpha: 0.05),
            blurRadius: 16,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppConstants.primaryGreen.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: AppConstants.primaryGreen.withValues(alpha: 0.3),
                    width: 1,
                  ),
                ),
                child: const Icon(
                  Icons.hub_rounded,
                  size: 20,
                  color: AppConstants.primaryGreen,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'TETHER MESH ENCLAVE',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: AppConstants.primaryGreen,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isMeshConnected
                          ? 'Tailnet Mesh Active'
                          : 'Local Enclave • Direct SSH',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isMeshConnected
                      ? AppConstants.primaryGreen.withValues(alpha: 0.15)
                      : Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isMeshConnected
                            ? AppConstants.primaryGreen
                            : Colors.white.withValues(alpha: 0.4),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      isMeshConnected ? 'MESH' : 'LOCAL',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        color: isMeshConnected
                            ? AppConstants.primaryGreen
                            : Colors.white.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(
            height: 1,
            thickness: 0.6,
            color: Colors.white10,
          ),
          const SizedBox(height: 12),
          // Stats Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStatChip('${profiles.length}', 'Profiles', Icons.dns_outlined),
              _buildStatChip('${keys.length}', 'SSH Keys', Icons.key_outlined),
              _buildStatChip('${commands.length}', 'Commands', Icons.bolt_rounded),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatChip(String count, String label, IconData icon) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: Colors.white.withValues(alpha: 0.4)),
        const SizedBox(width: 6),
        Text(
          count,
          style: GoogleFonts.jetBrainsMono(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 11,
            color: Colors.white.withValues(alpha: 0.45),
          ),
        ),
      ],
    );
  }
}

// ── Live Interactive Terminal Preview Card ───────────────────────────────────

class _LiveTerminalPreviewCard extends ConsumerWidget {
  const _LiveTerminalPreviewCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(terminalThemeProvider);
    final fontSize = ref.watch(terminalFontSizeProvider);
    final cursorType = ref.watch(terminalCursorTypeProvider);
    final cursorBlink = ref.watch(terminalCursorBlinkProvider);
    final fontFamily = ref.watch(terminalFontFamilyProvider);

    final fontName = SettingsScreen._fontDisplayName(fontFamily);

    String cursorGlyph;
    switch (cursorType) {
      case TerminalCursorType.underline:
        cursorGlyph = ' ';
        break;
      case TerminalCursorType.verticalBar:
        cursorGlyph = '▎';
        break;
      case TerminalCursorType.block:
        cursorGlyph = '█';
        break;
    }

    return Container(
      decoration: BoxDecoration(
        color: theme.previewBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.previewColor.withValues(alpha: 0.25),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: theme.previewColor.withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Simulated Window Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.35),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(15)),
              border: Border(
                bottom: BorderSide(
                  color: Colors.white.withValues(alpha: 0.06),
                  width: 0.8,
                ),
              ),
            ),
            child: Row(
              children: [
                // 3 Window Dots
                Container(
                  width: 9,
                  height: 9,
                  decoration: const BoxDecoration(
                    color: Color(0xFFFF5F56),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 5),
                Container(
                  width: 9,
                  height: 9,
                  decoration: const BoxDecoration(
                    color: Color(0xFFFFBD2E),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 5),
                Container(
                  width: 9,
                  height: 9,
                  decoration: const BoxDecoration(
                    color: Color(0xFF27C93F),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'tether@mesh: ~ (Live Preview)',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: Colors.white.withValues(alpha: 0.55),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: theme.previewColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    theme.name,
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      color: theme.previewColor,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Simulated Terminal Output
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RichText(
                  text: TextSpan(
                    style: GoogleFonts.getFont(
                      fontName,
                      fontSize: fontSize.clamp(11.0, 16.0),
                      height: 1.35,
                    ),
                    children: [
                      TextSpan(
                        text: 'tether@phone',
                        style: TextStyle(
                          color: theme.theme.green,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      TextSpan(
                        text: ':',
                        style: TextStyle(color: theme.theme.foreground),
                      ),
                      TextSpan(
                        text: '~',
                        style: TextStyle(
                          color: theme.theme.blue,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      TextSpan(
                        text: '\$ ping -c 1 100.64.0.1\n',
                        style: TextStyle(color: theme.theme.foreground),
                      ),
                      TextSpan(
                        text:
                            '64 bytes from 100.64.0.1: seq=1 ttl=64 time=12.4 ms\n',
                        style: TextStyle(
                          color: theme.theme.foreground.withValues(alpha: 0.8),
                        ),
                      ),
                      TextSpan(
                        text: 'tether@phone',
                        style: TextStyle(
                          color: theme.theme.green,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      TextSpan(
                        text: ':\$ uptime',
                        style: TextStyle(color: theme.theme.foreground),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'up 14 days, 3 users, load avg: 0.12 ',
                      style: GoogleFonts.getFont(
                        fontName,
                        fontSize: fontSize.clamp(11.0, 16.0),
                        color: theme.theme.foreground.withValues(alpha: 0.8),
                      ),
                    ),
                    _BlinkingCursor(
                      glyph: cursorGlyph,
                      color: theme.theme.cursor,
                      fontSize: fontSize.clamp(11.0, 16.0),
                      blink: cursorBlink,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BlinkingCursor extends StatefulWidget {
  final String glyph;
  final Color color;
  final double fontSize;
  final bool blink;

  const _BlinkingCursor({
    required this.glyph,
    required this.color,
    required this.fontSize,
    required this.blink,
  });

  @override
  State<_BlinkingCursor> createState() => _BlinkingCursorState();
}

class _BlinkingCursorState extends State<_BlinkingCursor>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.blink) {
      return Text(
        widget.glyph,
        style: TextStyle(
          color: widget.color,
          fontSize: widget.fontSize,
          fontWeight: FontWeight.bold,
        ),
      );
    }
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) => Opacity(
        opacity: _ctrl.value > 0.5 ? 1.0 : 0.0,
        child: Text(
          widget.glyph,
          style: TextStyle(
            color: widget.color,
            fontSize: widget.fontSize,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
