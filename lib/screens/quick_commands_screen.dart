import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:uuid/uuid.dart';

import '../models/connection_profile.dart';
import '../models/quick_command.dart';
import '../services/key_service.dart';
import '../services/profile_storage_service.dart';
import '../services/ssh_service.dart';
import '../services/tailscale_provider.dart';
import '../services/tailscale_ssh_socket.dart';
import '../utils/agent_presets.dart';
import '../utils/constants.dart';
import '../widgets/connection_card.dart';

/// Screen for managing and executing quick commands.
class QuickCommandsScreen extends ConsumerStatefulWidget {
  const QuickCommandsScreen({super.key});

  @override
  ConsumerState<QuickCommandsScreen> createState() =>
      _QuickCommandsScreenState();
}

class _QuickCommandsScreenState extends ConsumerState<QuickCommandsScreen> {
  @override
  Widget build(BuildContext context) {
    final storage = ref.watch(profileStorageProvider);
    final commands = storage.listCommands();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Quick Commands',
          style: GoogleFonts.inter(fontWeight: FontWeight.w600),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.tune_rounded, size: 20),
            tooltip: 'Edit Presets',
            onPressed: () => context.push('/presets'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(top: 4, bottom: 100),
        children: [
          // ── Info banner ──
          _buildInfoBanner(),

          // ── Quick-launch presets (always visible, one-tap to add+run) ──
          if (commands.isEmpty) _buildPresetsSection(storage),

          // ── Saved commands ──
          if (commands.isEmpty)
            _buildEmptyState()
          else ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  Text(
                    'Saved Commands',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFAB40).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: const Color(0xFFFFAB40).withValues(alpha: 0.2),
                      ),
                    ),
                    child: Text(
                      '${commands.length}',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: const Color(0xFFFFAB40),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            ...() {
              final profiles = storage.listProfiles();
              return commands.map((cmd) {
                final profile = cmd.profileId != null
                    ? profiles.where((p) => p.id == cmd.profileId).firstOrNull
                    : null;
                return _buildCommandCard(cmd, profile);
              });
            }(),
          ],
        ],
      ),
      floatingActionButton: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: AppConstants.primaryGreen.withValues(alpha: 0.25),
              blurRadius: 16,
              spreadRadius: 2,
            ),
          ],
        ),
        child: FloatingActionButton(
          onPressed: () => _showCommandEditor(),
          tooltip: 'Add Command',
          child: const Icon(Icons.add_rounded),
        ),
      ),
    );
  }

  // ── Info banner ──────────────────────────────────────────────────

  Widget _buildInfoBanner() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFFFAB40).withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFFFFAB40).withValues(alpha: 0.15),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFAB40).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.flash_on_rounded,
                    size: 18,
                    color: Color(0xFFFFAB40),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Save commands you run often for one-tap execution, '
                    'or tap a preset below to get started.',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.55),
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
    )
        .animate()
        .fadeIn(duration: 400.ms, curve: Curves.easeOut)
        .slideY(begin: -0.05, end: 0, duration: 350.ms, curve: Curves.easeOut);
  }

  // ── Presets section ──────────────────────────────────────────────

  Widget _buildPresetsSection(ProfileStorageService storage) {
    final profiles = storage.listProfiles();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Text(
            'Quick Launch',
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ),
        // Agents
        _buildPresetGroup(
          label: AgentPresets.categoryLabel(PresetCategory.agent),
          presets: AgentPresets.byCategory(PresetCategory.agent),
          profiles: profiles,
        ),
        // Dev Tools
        _buildPresetGroup(
          label: AgentPresets.categoryLabel(PresetCategory.devtool),
          presets: AgentPresets.byCategory(PresetCategory.devtool),
          profiles: profiles,
        ),
        // System
        _buildPresetGroup(
          label: AgentPresets.categoryLabel(PresetCategory.system),
          presets: AgentPresets.byCategory(PresetCategory.system),
          profiles: profiles,
        ),
      ],
    );
  }

  Widget _buildPresetGroup({
    required String label,
    required List<AgentPreset> presets,
    required List<ConnectionProfile> profiles,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
          child: Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.white.withValues(alpha: 0.4),
              letterSpacing: 0.8,
            ),
          ),
        ),
        SizedBox(
          height: 96,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            itemCount: presets.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final preset = presets[index];
              return _buildPresetChip(preset, profiles);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildPresetChip(
      AgentPreset preset, List<ConnectionProfile> profiles) {
    return GestureDetector(
      onTap: () => _launchPreset(preset, profiles),
      child: Container(
        width: 76,
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        decoration: BoxDecoration(
          color: AppConstants.surfaceDark.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: preset.color.withValues(alpha: 0.15),
          ),
          boxShadow: [
            BoxShadow(
              color: preset.color.withValues(alpha: 0.03),
              blurRadius: 10,
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: preset.color.withValues(alpha: 0.12),
                border: Border.all(
                  color: preset.color.withValues(alpha: 0.25),
                  width: 1,
                ),
              ),
              child: Icon(preset.icon, size: 20, color: preset.color),
            ),
            const SizedBox(height: 6),
            Text(
              preset.label,
              style: GoogleFonts.inter(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: Colors.white.withValues(alpha: 0.8),
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _launchPreset(
      AgentPreset preset, List<ConnectionProfile> profiles) async {
    if (profiles.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.info_outline, color: Color(0xFFFFAB40)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Add a connection first to launch "${preset.label}"',
                  style: GoogleFonts.inter(fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      );
      return;
    }

    // If only one profile, use it directly.
    if (profiles.length == 1) {
      _savePresetAsCommand(preset, profiles.first.id);
      _showCommandOutput(
        QuickCommand(
          id: 'temp',
          label: preset.label,
          command: preset.command,
          profileId: profiles.first.id,
          presetId: preset.id,
        ),
        profiles.first,
      );
      return;
    }

    // Multiple profiles — ask which one.
    final selectedProfile = await showDialog<ConnectionProfile>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Run on which server?',
          style: GoogleFonts.inter(fontWeight: FontWeight.w600),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: profiles.length,
            itemBuilder: (context, index) {
              final p = profiles[index];
              return ListTile(
                leading: Icon(Icons.dns_rounded,
                    color: ProfileColors.get(p.colorIndex)),
                title: Text(p.shortLabel),
                subtitle: Text(
                  '${p.username}@${p.host}',
                  style: GoogleFonts.jetBrainsMono(fontSize: 11),
                ),
                onTap: () => Navigator.pop(context, p),
              );
            },
          ),
        ),
      ),
    );

    if (selectedProfile == null) return;

    _savePresetAsCommand(preset, selectedProfile.id);
    _showCommandOutput(
      QuickCommand(
        id: 'temp',
        label: preset.label,
        command: preset.command,
        profileId: selectedProfile.id,
        presetId: preset.id,
      ),
      selectedProfile,
    );
  }

  Future<void> _savePresetAsCommand(
      AgentPreset preset, String profileId) async {
    final storage = ref.read(profileStorageProvider);
    final existing = storage.listCommands().where(
      (c) => c.presetId == preset.id && c.profileId == profileId,
    );

    // Only save if an identical one doesn't already exist.
    if (existing.isEmpty) {
      await storage.saveCommand(QuickCommand(
        id: const Uuid().v4(),
        label: preset.label,
        command: preset.command,
        profileId: profileId,
        presetId: preset.id,
      ));
      if (mounted) setState(() {});
    }
  }

  // ── Empty state ──────────────────────────────────────────────────

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(48, 16, 48, 24),
      child: Column(
        children: [
          Icon(
            Icons.flash_on_rounded,
            size: 56,
            color: Colors.white.withValues(alpha: 0.1),
          )
              .animate(onPlay: (c) => c.repeat())
              .shimmer(
                  duration: 2500.ms,
                  color: const Color(0xFFFFAB40).withValues(alpha: 0.08))
              .scale(
                begin: const Offset(1, 1),
                end: const Offset(1.02, 1.02),
                duration: 2500.ms,
                curve: Curves.easeInOutSine,
              ),
          const SizedBox(height: 16),
          Text(
            'No saved commands yet',
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.white.withValues(alpha: 0.4),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Tap a preset above to launch, or + to create a custom command',
            style: GoogleFonts.inter(
              fontSize: 13,
              color: Colors.white.withValues(alpha: 0.25),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // ── Command card ─────────────────────────────────────────────────

  Widget _buildCommandCard(QuickCommand cmd, ConnectionProfile? profile) {
    final preset = cmd.presetId != null ? AgentPresets.byId(cmd.presetId!) : null;
    final accent = preset?.color ?? const Color(0xFFFFAB40);
    final icon = preset?.icon ?? Icons.play_arrow_rounded;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      child: Container(
            decoration: BoxDecoration(
              color: AppConstants.surfaceDark.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
              boxShadow: [
                BoxShadow(
                  color: accent.withValues(alpha: 0.03),
                  blurRadius: 16,
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => _executeCommand(cmd),
                borderRadius: BorderRadius.circular(14),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(11),
                          border: Border.all(
                            color: accent.withValues(alpha: 0.2),
                            width: 1,
                          ),
                        ),
                        child: Icon(icon, color: accent, size: 22),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              cmd.label,
                              style: GoogleFonts.inter(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '\$ ${cmd.command}',
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 11,
                                color: Colors.white.withValues(alpha: 0.4),
                              ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 2,
                            ),
                            if (profile != null) ...[
                              const SizedBox(height: 2),
                              Text(
                                '→ ${profile.shortLabel}',
                                style: GoogleFonts.inter(
                                  fontSize: 10,
                                  color: Colors.white.withValues(alpha: 0.3),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      PopupMenuButton<String>(
                        icon: Icon(Icons.more_vert_rounded,
                            color: Colors.white.withValues(alpha: 0.4)),
                        onSelected: (action) {
                          if (action == 'edit') {
                            _showCommandEditor(command: cmd);
                          } else if (action == 'delete') {
                            _deleteCommand(cmd);
                          }
                        },
                        itemBuilder: (context) => [
                          PopupMenuItem(
                            value: 'edit',
                            child: Row(
                              children: [
                                Icon(Icons.edit_rounded,
                                    size: 18,
                                    color: Colors.white.withValues(alpha: 0.7)),
                                const SizedBox(width: 12),
                                const Text('Edit'),
                              ],
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'delete',
                            child: Row(
                              children: [
                                Icon(Icons.delete_outline_rounded,
                                    size: 18, color: Colors.red),
                                SizedBox(width: 12),
                                Text('Delete'),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
    );
  }

  // ── Command execution ────────────────────────────────────────────

  Future<void> _executeCommand(QuickCommand cmd) async {
    if (cmd.profileId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'This command is not linked to a profile. Edit to link it.',
            style: GoogleFonts.inter(fontSize: 13),
          ),
        ),
      );
      return;
    }

    final storage = ref.read(profileStorageProvider);
    final profile = storage.getProfile(cmd.profileId!);
    if (profile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Linked profile not found.',
            style: GoogleFonts.inter(fontSize: 13),
          ),
        ),
      );
      return;
    }

    _showCommandOutput(cmd, profile);
  }

  Future<void> _showCommandOutput(
    QuickCommand cmd,
    ConnectionProfile profile,
  ) async {
    final preset = cmd.presetId != null ? AgentPresets.byId(cmd.presetId!) : null;
    final accent = preset?.color ?? AppConstants.primaryGreen;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: DraggableScrollableSheet(
            initialChildSize: 0.6,
            minChildSize: 0.3,
            maxChildSize: 0.9,
            builder: (context, scrollController) => Container(
              decoration: BoxDecoration(
                color: AppConstants.backgroundDark.withValues(alpha: 0.95),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(20)),
                border: Border(
                  top: BorderSide(
                    color: accent.withValues(alpha: 0.2),
                    width: 1,
                  ),
                ),
              ),
              child: Column(
                children: [
                  // Header
                  Container(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                    decoration: BoxDecoration(
                      color: AppConstants.surfaceDark.withValues(alpha: 0.6),
                      border: Border(
                        bottom: BorderSide(
                          color: Colors.white.withValues(alpha: 0.05),
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(7),
                          ),
                          child: Icon(
                            preset?.icon ?? Icons.terminal_rounded,
                            size: 16,
                            color: accent,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '\$ ${cmd.command}',
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 12,
                              color: Colors.white,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          'on ${profile.shortLabel}',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            color: Colors.white.withValues(alpha: 0.4),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Output area
                  Expanded(
                    child: FutureBuilder<String>(
                      future: _runCommand(cmd, profile),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                CircularProgressIndicator(
                                  color: accent,
                                  strokeWidth: 2.5,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'Running command...',
                                  style: GoogleFonts.inter(
                                    color: Colors.white.withValues(alpha: 0.4),
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }

                        final result =
                            snapshot.data ?? snapshot.error.toString();

                        return Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          child: SingleChildScrollView(
                            controller: scrollController,
                            child: SelectableText(
                              result,
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 12,
                                color: Colors.white.withValues(alpha: 0.85),
                                height: 1.55,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<String> _runCommand(
    QuickCommand cmd,
    ConnectionProfile profile,
  ) async {
    final sshService = ref.read(sshServiceProvider);

    TailscaleSSHSocket? sock;
    String? privateKey;
    if (profile.keyId != null) {
      privateKey =
          await ref.read(keyServiceProvider).getPrivateKey(profile.keyId!);
    }

    try {
      if (profile.connectionMethod == ConnectionMethod.tailscale) {
        var ts = ref.read(tailscaleServiceProvider);
        var conn = await ts.dial(profile.host, profile.port, timeout: const Duration(seconds: 10));
        sock = TailscaleSSHSocket(conn);
      } else {
        sock = null;
      }
      await sshService.connect(
        profile: profile,
        privateKey: privateKey,
        password: profile.password,
        socket: sock,
      );
      final output = await sshService.executeCommand(cmd.command);
      await sshService.disconnect();
      return output;
    } catch (e) {
      try {
        await sshService.disconnect();
      } catch (_) {}
      return 'Error: $e';
    }
  }

  // ── Command editor ───────────────────────────────────────────────

  Future<void> _showCommandEditor({QuickCommand? command}) async {
    final labelController =
        TextEditingController(text: command?.label ?? '');
    final commandController =
        TextEditingController(text: command?.command ?? '');

    final storage = ref.read(profileStorageProvider);
    final profiles = storage.listProfiles();
    String? selectedProfileId = command?.profileId;

    final result = await showModalBottomSheet<Map<String, String?>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: StatefulBuilder(
            builder: (context, setModalState) => Container(
              decoration: BoxDecoration(
                color: AppConstants.surfaceDark.withValues(alpha: 0.95),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(20)),
                border: Border(
                  top: BorderSide(
                    color: AppConstants.primaryGreen.withValues(alpha: 0.15),
                  ),
                ),
              ),
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Drag handle
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Text(
                    command != null ? 'Edit Command' : 'New Quick Command',
                    style: GoogleFonts.inter(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 18),
                  TextField(
                    controller: labelController,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'Label',
                      hintText: 'Start my agent',
                      prefixIcon: Icon(Icons.label_outline_rounded),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: commandController,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Command',
                      hintText: 'python ~/agents/start.py --auto',
                      prefixIcon: Icon(Icons.terminal_rounded),
                    ),
                    style: GoogleFonts.jetBrainsMono(fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String?>(
                    initialValue: selectedProfileId,
                    decoration: const InputDecoration(
                      labelText: 'Target Profile',
                      prefixIcon: Icon(Icons.router_rounded),
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text('Ask at runtime'),
                      ),
                      ...profiles.map(
                        (p) => DropdownMenuItem(
                          value: p.id,
                          child: Text(p.shortLabel),
                        ),
                      ),
                    ],
                    onChanged: (v) =>
                        setModalState(() => selectedProfileId = v),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(context, {
                        'label': labelController.text.trim(),
                        'command': commandController.text.trim(),
                        'profileId': selectedProfileId,
                      });
                    },
                    icon: const Icon(Icons.save_rounded),
                    label: Text(command != null ? 'Update' : 'Save'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    if (result == null) return;

    final label = result['label']!;
    final cmdText = result['command']!;
    if (label.isEmpty || cmdText.isEmpty) return;

    final quickCommand = QuickCommand(
      id: command?.id ?? const Uuid().v4(),
      label: label,
      command: cmdText,
      profileId: result['profileId'],
      createdAt: command?.createdAt,
      presetId: command?.presetId,
    );

    await ref.read(profileStorageProvider).saveCommand(quickCommand);

    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            command != null ? 'Command updated' : 'Command saved',
            style: GoogleFonts.inter(),
          ),
        ),
      );
    }
  }

  Future<void> _deleteCommand(QuickCommand cmd) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Command'),
        content: Text('Delete "${cmd.label}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await ref.read(profileStorageProvider).deleteCommand(cmd.id);
      setState(() {});
    }
  }
}
