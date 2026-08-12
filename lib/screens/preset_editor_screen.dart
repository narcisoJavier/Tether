import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:uuid/uuid.dart';

import '../models/quick_command.dart';
import '../services/profile_storage_service.dart';
import '../utils/constants.dart';
import '../widgets/connection_card.dart';

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

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Edit Presets',
          style: GoogleFonts.inter(fontWeight: FontWeight.w600),
        ),
      ),
      body: customPresets.isEmpty
          ? _buildEmptyState()
          : ListView.builder(
              padding: const EdgeInsets.only(top: 8, bottom: 100),
              itemCount: customPresets.length,
              itemBuilder: (context, index) {
                final preset = customPresets[index];
                return _buildPresetCard(preset, index);
              },
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
          onPressed: () => _showPresetEditor(),
          tooltip: 'Add Custom Preset',
          child: const Icon(Icons.add_rounded),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
                  Icons.extension_rounded,
                  size: 56,
                  color: Colors.white.withValues(alpha: 0.1),
                )
                .animate(onPlay: (c) => c.repeat())
                .shimmer(
                  duration: 2500.ms,
                  color: const Color(0xFFFFAB40).withValues(alpha: 0.08),
                )
                .scale(
                  begin: const Offset(1, 1),
                  end: const Offset(1.02, 1.02),
                  duration: 2500.ms,
                  curve: Curves.easeInOutSine,
                ),
            const SizedBox(height: 16),
            Text(
              'No custom presets yet',
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.white.withValues(alpha: 0.4),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Create custom commands to launch on any server.\n'
              'Tap + to get started.',
              style: GoogleFonts.inter(
                fontSize: 13,
                color: Colors.white.withValues(alpha: 0.25),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPresetCard(QuickCommand preset, int index) {
    final accent = ProfileColors.get(preset.colorIndex);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      child: Dismissible(
        key: ValueKey(preset.id),
        direction: DismissDirection.endToStart,
        confirmDismiss: (direction) => _confirmDelete(preset),
        onDismissed: (_) => _deletePreset(preset),
        background: Container(
          decoration: BoxDecoration(
            color: Colors.red.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(14),
          ),
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 20),
          child: const Icon(Icons.delete_rounded, color: Colors.red),
        ),
        child: Container(
          decoration: BoxDecoration(
            color: AppConstants.surfaceDark.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
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
                      child: Icon(
                        _iconForCommand(preset.command),
                        color: accent,
                        size: 22,
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
                              color: Colors.white.withValues(alpha: 0.9),
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '\$ ${preset.command}',
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 11,
                              color: Colors.white.withValues(alpha: 0.35),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: accent.withValues(alpha: 0.4),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: Colors.white.withValues(alpha: 0.2),
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
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
        backgroundColor: AppConstants.surfaceDark,
        title: Text(
          'Delete Preset',
          style: GoogleFonts.inter(fontWeight: FontWeight.w600),
        ),
        content: Text(
          'Delete "${preset.label}"? This cannot be undone.',
          style: GoogleFonts.inter(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.withValues(alpha: 0.2),
            ),
            child: const Text('Delete'),
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
          builder: (ctx) => StatefulBuilder(
            builder: (context, setDialogState) => AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
              ),
              backgroundColor: AppConstants.surfaceDark,
              title: Text(
                preset != null ? 'Edit Preset' : 'New Preset',
                style: GoogleFonts.inter(fontWeight: FontWeight.w600),
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
                          'Accent',
                          style: GoogleFonts.inter(
                            fontSize: 12,
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
                              width: 28,
                              height: 28,
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
                                      size: 16,
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
                  child: const Text('Cancel'),
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
                  child: Text(preset != null ? 'Save' : 'Create'),
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
