import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/biometric_provider.dart';
import '../services/export_service.dart';
import '../services/onboarding_service.dart';
import '../services/update_service.dart';
import '../utils/app_version.dart';
import '../utils/constants.dart';
import '../utils/terminal_settings_provider.dart';
import '../widgets/gradient_scaffold.dart';

/// Settings screen with display preferences and app info.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bottomInset = 128 + MediaQuery.paddingOf(context).bottom;

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
        padding: EdgeInsets.fromLTRB(16, 8, 16, bottomInset.toDouble()),
        children: [
          _sectionHeader('Display'),
          const SizedBox(height: 8),
          _BiometricTile(),
          const SizedBox(height: 8),
          const _WelcomeScreenTile(),
          const SizedBox(height: 24),
          _sectionHeader('Terminal'),
          const SizedBox(height: 8),
          _FontSizeTile(),
          const SizedBox(height: 8),
          _ScrollbackTile(),
          const SizedBox(height: 8),
          _KeepaliveTile(),
          const SizedBox(height: 24),
          _sectionHeader('Data'),
          const SizedBox(height: 8),
          _ExportTile(),
          const SizedBox(height: 8),
          _ImportTile(),
          const SizedBox(height: 24),
          _sectionHeader('About'),
          const SizedBox(height: 8),
          _AboutCard(),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _sectionHeader(String label) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, top: 4),
      child: Text(
        label.toUpperCase(),
        style: GoogleFonts.jetBrainsMono(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: Colors.white.withValues(alpha: 0.5),
          letterSpacing: 1.0,
        ),
      ),
    );
  }
}

class _BiometricTile extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lockEnabled = ref.watch(biometricLockEnabledProvider);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppConstants.surfaceDark.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.fingerprint_rounded,
              size: 20,
              color: AppConstants.primaryGreen,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Biometric Lock',
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Require fingerprint or face to open the app',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: Colors.white.withValues(alpha: 0.45),
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: lockEnabled,
            onChanged: (_) =>
                ref.read(biometricLockEnabledProvider.notifier).toggle(),
            activeThumbColor: AppConstants.primaryGreen,
            inactiveTrackColor: Colors.white.withValues(alpha: 0.1),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 350.ms, curve: Curves.easeOut);
  }
}

class _WelcomeScreenTile extends ConsumerStatefulWidget {
  const _WelcomeScreenTile();

  @override
  ConsumerState<_WelcomeScreenTile> createState() => _WelcomeScreenTileState();
}

class _WelcomeScreenTileState extends ConsumerState<_WelcomeScreenTile> {
  late bool _enabled;

  @override
  void initState() {
    super.initState();
    _enabled = ref.read(onboardingServiceProvider).isWelcomeScreenEnabled();
  }

  @override
  Widget build(BuildContext context) {
    final onboardingService = ref.watch(onboardingServiceProvider);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppConstants.surfaceDark.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.waving_hand_rounded,
              size: 20,
              color: Color(0xFFFFAB40),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Welcome Screen',
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Show animated screen on launch',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: Colors.white.withValues(alpha: 0.45),
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: _enabled,
            onChanged: (value) async {
              setState(() => _enabled = value);
              await onboardingService.setWelcomeScreenEnabled(value);
            },
            activeThumbColor: const Color(0xFFFFAB40),
            inactiveTrackColor: Colors.white.withValues(alpha: 0.1),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 350.ms, curve: Curves.easeOut);
  }
}

// --- Terminal Settings Tiles ---

class _FontSizeTile extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fontSize = ref.watch(terminalFontSizeProvider);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppConstants.surfaceDark.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.text_fields_rounded,
                  size: 20,
                  color: Color(0xFF448AFF),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Font Size',
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$fontSize pt',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 12,
                        color: AppConstants.primaryGreen,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Slider(
            value: fontSize,
            min: AppConstants.minFontSize,
            max: AppConstants.maxFontSize,
            divisions: 52,
            activeColor: AppConstants.primaryGreen,
            inactiveColor: Colors.white.withValues(alpha: 0.1),
            onChanged: (v) =>
                ref.read(terminalFontSizeProvider.notifier).setSize(v),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 350.ms, curve: Curves.easeOut);
  }
}

class _ScrollbackTile extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scrollback = ref.watch(terminalScrollbackProvider);
    final label = scrollback >= 1000
        ? '${(scrollback ~/ 1000)}K lines'
        : '$scrollback lines';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppConstants.surfaceDark.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.list_rounded,
                  size: 20,
                  color: Color(0xFFFFAB40),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Scrollback Lines',
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      label,
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 12,
                        color: const Color(0xFFFFAB40),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Slider(
            value: scrollback.toDouble(),
            min: 500,
            max: 50000,
            divisions: 99,
            activeColor: const Color(0xFFFFAB40),
            inactiveColor: Colors.white.withValues(alpha: 0.1),
            onChanged: (v) => ref
                .read(terminalScrollbackProvider.notifier)
                .setLines(v.round()),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 350.ms, curve: Curves.easeOut);
  }
}

class _KeepaliveTile extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final keepalive = ref.watch(terminalKeepaliveProvider);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppConstants.surfaceDark.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.timer_outlined,
                  size: 20,
                  color: Color(0xFF18FFFF),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Keepalive Interval',
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${keepalive}s',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 12,
                        color: const Color(0xFF18FFFF),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Slider(
            value: keepalive.toDouble(),
            min: 5,
            max: 300,
            divisions: 59,
            activeColor: const Color(0xFF18FFFF),
            inactiveColor: Colors.white.withValues(alpha: 0.1),
            onChanged: (v) => ref
                .read(terminalKeepaliveProvider.notifier)
                .setInterval(v.round()),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 350.ms, curve: Curves.easeOut);
  }
}

// --- Data Section Tiles ---

class _ExportTile extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppConstants.surfaceDark.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () async {
            await ExportService.exportToClipboard();
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Row(
                    children: [
                      const Icon(
                        Icons.check_circle_rounded,
                        color: AppConstants.primaryGreen,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Exported to clipboard',
                          style: GoogleFonts.inter(fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                  duration: const Duration(seconds: 2),
                ),
              );
            }
          },
          borderRadius: BorderRadius.circular(10),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppConstants.primaryGreen.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.file_upload_outlined,
                  size: 20,
                  color: AppConstants.primaryGreen,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Export',
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Copy profiles and commands to clipboard',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.45),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: Colors.white.withValues(alpha: 0.2),
              ),
            ],
          ),
        ),
      ),
    ).animate().fadeIn(duration: 350.ms, curve: Curves.easeOut);
  }
}

class _ImportTile extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppConstants.surfaceDark.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _showImportDialog(context, ref),
          borderRadius: BorderRadius.circular(10),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFF448AFF).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.file_download_outlined,
                  size: 20,
                  color: Color(0xFF448AFF),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Import',
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Paste exported JSON to restore data',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.45),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: Colors.white.withValues(alpha: 0.2),
              ),
            ],
          ),
        ),
      ),
    ).animate().fadeIn(duration: 350.ms, curve: Curves.easeOut);
  }

  void _showImportDialog(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
        backgroundColor: AppConstants.surfaceDark,
        title: Text(
          'Import Data',
          style: GoogleFonts.inter(fontWeight: FontWeight.w600),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Paste the JSON you exported earlier.',
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
}

class _AboutCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppConstants.surfaceDark.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppConstants.primaryGreen.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: AppConstants.primaryGreen.withValues(alpha: 0.2),
                  ),
                ),
                child: const Icon(
                  Icons.terminal_rounded,
                  size: 20,
                  color: AppConstants.primaryGreen,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppConstants.appFullTitle,
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    _VersionBadge(),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => launchUrl(
                    Uri.parse(
                      'https://github.com/${AppConstants.gitHubOwner}/${AppConstants.gitHubRepo}',
                    ),
                    mode: LaunchMode.externalApplication,
                  ),
                  icon: const Icon(Icons.code_rounded, size: 16),
                  label: Text(
                    'GitHub',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white.withValues(alpha: 0.7),
                    side: BorderSide(
                      color: Colors.white.withValues(alpha: 0.12),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () async {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Checking for updates...',
                          style: GoogleFonts.inter(fontSize: 13),
                        ),
                        duration: const Duration(seconds: 2),
                      ),
                    );
                    final update = await UpdateService.checkForUpdate(
                      force: true,
                    );
                    if (!context.mounted) return;
                    if (update != null) {
                      showDialog(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          backgroundColor: AppConstants.surfaceDark,
                          title: Text(
                            'Update Available (${update.latestVersion})',
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.w600,
                            ),
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
                  },
                  icon: const Icon(Icons.system_update_rounded, size: 16),
                  label: Text(
                    'Check Update',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppConstants.primaryGreen.withValues(
                      alpha: 0.15,
                    ),
                    foregroundColor: AppConstants.primaryGreen,
                    elevation: 0,
                    side: BorderSide(
                      color: AppConstants.primaryGreen.withValues(alpha: 0.3),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => context.push('/onboarding'),
              icon: const Icon(Icons.school_outlined, size: 16),
              label: Text(
                'Replay Onboarding Tour',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white.withValues(alpha: 0.8),
                side: BorderSide(
                  color: Colors.white.withValues(alpha: 0.12),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms, delay: 100.ms, curve: Curves.easeOut);
  }
}

class _VersionBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: AppVersion.get(),
      builder: (context, snapshot) {
        final version = snapshot.data ?? AppVersion.current;
        return Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppConstants.primaryGreen.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: AppConstants.primaryGreen.withValues(alpha: 0.2),
                ),
              ),
              child: Text(
                'v$version',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppConstants.primaryGreen,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'Android',
              style: GoogleFonts.inter(
                fontSize: 12,
                color: Colors.white.withValues(alpha: 0.35),
              ),
            ),
          ],
        );
      },
    );
  }
}
