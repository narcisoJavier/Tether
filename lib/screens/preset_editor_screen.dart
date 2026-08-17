import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:uuid/uuid.dart';

import '../models/quick_command.dart';
import '../services/profile_storage_service.dart';
import '../utils/constants.dart';
import '../widgets/connection_card.dart';
import '../widgets/gradient_scaffold.dart';

/// Screen for creating, editing, and deleting custom presets.
class PresetEditorScreen extends ConsumerStatefulWidget {
  const PresetEditorScreen({super.key});

  @override
  ConsumerState<PresetEditorScreen> createState() => _PresetEditorScreenState();
}

class _PresetEditorScreenState extends ConsumerState<PresetEditorScreen> {
  @override
  Widget build(BuildContext context) {
    final storage = ref.watch(profileStorageProvider);
    final commands = storage.listCommands();

    // Custom presets = commands with no presetId (user-created).
    final customPresets = commands.where((c) => c.presetId == null).toList();

    return GradientScaffold(
      appBar: GlassAppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.03),
                border: Border.all(color: const Color(0xFF414754), width: 0.8),
              ),
              child: const Icon(
                Icons.extension_rounded,
                size: 12,
                color: Color(0xFFC0C6D6),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'CUSTOM PRESETS',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                letterSpacing: 1.5,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_rounded, color: AppConstants.primaryGreen),
            tooltip: 'Add Custom Preset',
            onPressed: () => _showPresetEditor(),
          ),
        ],
      ),
      body: customPresets.isEmpty
          ? _buildEmptyState()
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
              itemCount: customPresets.length,
              itemBuilder: (context, index) {
                final preset = customPresets[index];
                return _buildPresetCard(preset, index);
              },
            ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          decoration: BoxDecoration(
            color: AppConstants.surface0,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.08),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.04),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.1),
                  ),
                ),
                child: const Icon(
                  Icons.extension_rounded,
                  size: 24,
                  color: AppConstants.accentAmber,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'NO CUSTOM PRESETS',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Create custom shell commands to launch with one tap across any server connection.',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: Colors.white.withValues(alpha: 0.5),
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: () => _showPresetEditor(),
                icon: const Icon(Icons.add_rounded, size: 16),
                label: const Text('CREATE PRESET'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppConstants.primaryGreen,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  textStyle: GoogleFonts.jetBrainsMono(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPresetCard(QuickCommand preset, int index) {
    final accent = ProfileColors.get(preset.colorIndex);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Dismissible(
        key: ValueKey(preset.id),
        direction: DismissDirection.endToStart,
        confirmDismiss: (direction) => _confirmDelete(preset),
        onDismissed: (_) => _deletePreset(preset),
        background: Container(
          decoration: BoxDecoration(
            color: Colors.red.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
          ),
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 20),
          child: const Icon(Icons.delete_rounded, color: Colors.redAccent),
        ),
        child: Container(
          decoration: BoxDecoration(
            color: AppConstants.surface0,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => _showPresetEditor(preset: preset),
              borderRadius: BorderRadius.circular(14),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: accent.withValues(alpha: 0.25),
                          width: 1,
                        ),
                      ),
                      child: Icon(
                        _iconForCommand(preset.command),
                        color: accent,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            preset.label,
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '\$ ${preset.command}',
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 11,
                              color: Colors.white.withValues(alpha: 0.4),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: Colors.white.withValues(alpha: 0.25),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Pick a reasonable icon based on the command text.
  IconData _iconForCommand(String command) {
    final cmd = command.toLowerCase().trim();
    if (cmd.contains('docker')) return Icons.deblur_rounded;
    if (cmd.contains('git')) return Icons.code_rounded;
    if (cmd.contains('ssh') || cmd.contains('telnet')) return Icons.dns_rounded;
    if (cmd.contains('curl') || cmd.contains('wget') || cmd.contains('http')) {
      return Icons.http_rounded;
    }
    if (cmd.contains('pip') || cmd.contains('npm') || cmd.contains('brew')) {
      return Icons.inventory_2_rounded;
    }
    if (cmd.contains('ls') || cmd.contains('find') || cmd.contains('cat')) {
      return Icons.folder_open_rounded;
    }
    if (cmd.contains('top') || cmd.contains('ps ') || cmd.contains('htop')) {
      return Icons.memory_rounded;
    }
    if (cmd.contains('nvim') || cmd.contains('vim') || cmd.contains('nano')) {
      return Icons.edit_rounded;
    }
    return Icons.terminal_rounded;
  }

  Future<bool?> _confirmDelete(QuickCommand preset) {
    return showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
        backgroundColor: AppConstants.surface0,
        title: Text(
          'Delete Preset',
          style: GoogleFonts.jetBrainsMono(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        content: Text(
          'Delete "${preset.label}"? This cannot be undone.',
          style: GoogleFonts.inter(
            fontSize: 13,
            color: Colors.white.withValues(alpha: 0.7),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'CANCEL',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 12,
                color: Colors.white.withValues(alpha: 0.5),
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.withValues(alpha: 0.2),
              foregroundColor: Colors.redAccent,
              elevation: 0,
            ),
            child: Text(
              'DELETE',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _deletePreset(QuickCommand preset) async {
    final storage = ref.read(profileStorageProvider);
    await storage.deleteCommand(preset.id);
    if (mounted) setState(() {});
  }

  Future<void> _showPresetEditor({QuickCommand? preset}) async {
    final labelController = TextEditingController(text: preset?.label ?? '');
    final commandController = TextEditingController(
      text: preset?.command ?? '',
    );
    var selectedColor = preset?.colorIndex ?? 0;

    final result =
        await showDialog<({String label, String command, int color})>(
          context: context,
          useRootNavigator: true,
          builder: (ctx) => StatefulBuilder(
            builder: (context, setDialogState) => AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
              ),
              backgroundColor: AppConstants.surface0,
              title: Text(
                preset != null ? 'EDIT PRESET' : 'NEW PRESET',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: labelController,
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: 'Label',
                        hintText: 'e.g. Deploy App',
                      ),
                      style: GoogleFonts.inter(fontSize: 13),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: commandController,
                      decoration: const InputDecoration(
                        labelText: 'Command',
                        hintText: 'e.g. ./deploy.sh',
                      ),
                      style: GoogleFonts.jetBrainsMono(fontSize: 13),
                      minLines: 2,
                      maxLines: 4,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Text(
                          'ACCENT',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Colors.white.withValues(alpha: 0.5),
                          ),
                        ),
                        const SizedBox(width: 12),
                        ...List.generate(ProfileColors.palette.length, (i) {
                          final c = ProfileColors.palette[i];
                          return GestureDetector(
                            onTap: () =>
                                setDialogState(() => selectedColor = i),
                            child: Container(
                              width: 26,
                              height: 26,
                              margin: const EdgeInsets.only(right: 6),
                              decoration: BoxDecoration(
                                color: c,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: selectedColor == i
                                      ? Colors.white
                                      : Colors.transparent,
                                  width: 2,
                                ),
                              ),
                              child: selectedColor == i
                                  ? const Icon(
                                      Icons.check_rounded,
                                      size: 14,
                                      color: Colors.black87,
                                    )
                                  : null,
                            ),
                          );
                        }),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(
                    'CANCEL',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.5),
                    ),
                  ),
                ),
                ElevatedButton(
                  onPressed: () {
                    final label = labelController.text.trim();
                    final command = commandController.text.trim();
                    if (label.isEmpty || command.isEmpty) return;
                    Navigator.pop(ctx, (
                      label: label,
                      command: command,
                      color: selectedColor,
                    ));
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppConstants.primaryGreen,
                    foregroundColor: Colors.black,
                    elevation: 0,
                  ),
                  child: Text(
                    preset != null ? 'SAVE' : 'CREATE',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );

    if (result == null) return;

    final storage = ref.read(profileStorageProvider);
    final newPreset = QuickCommand(
      id: preset?.id ?? const Uuid().v4(),
      label: result.label,
      command: result.command,
      colorIndex: result.color,
      presetId: null, // custom preset
    );

    await storage.saveCommand(newPreset);
    if (mounted) setState(() {});
  }
}
