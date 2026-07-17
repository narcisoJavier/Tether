import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/stored_key_pair.dart';
import '../services/key_service.dart';
import '../utils/constants.dart';
import '../widgets/key_card.dart';

/// Screen for managing SSH key pairs — generate, import, and delete.
class KeyManagementScreen extends ConsumerStatefulWidget {
  const KeyManagementScreen({super.key});

  @override
  ConsumerState<KeyManagementScreen> createState() =>
      _KeyManagementScreenState();
}

class _KeyManagementScreenState extends ConsumerState<KeyManagementScreen> {
  @override
  Widget build(BuildContext context) {
    final keys = ref.watch(keyServiceProvider).listKeys();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'SSH Keys',
          style: GoogleFonts.inter(fontWeight: FontWeight.w600),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.only(top: 4, bottom: 100),
        children: [
          // ── Info banner ──
          _buildInfoBanner(),

          if (keys.isEmpty)
            _buildEmptyState()
          else ...[
            // ── Header ──
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  Text(
                    'Your Keys',
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
                      color: AppConstants.primaryGreen.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color:
                            AppConstants.primaryGreen.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Text(
                      '${keys.length}',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: AppConstants.primaryGreen,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            ...keys.map(
              (key) => KeyCard(
                keyPair: key,
                onCopy: () => _copyPublicKey(key),
                onDelete: () => _deleteKey(key),
              ),
            ),
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
          onPressed: _showAddKeyMenu,
          tooltip: 'Add Key',
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
              color: AppConstants.primaryGreen.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppConstants.primaryGreen.withValues(alpha: 0.15),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: AppConstants.primaryGreen.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.shield_rounded,
                    size: 18,
                    color: AppConstants.primaryGreen,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Private keys are encrypted in your device keystore. '
                    'Copy the public key to your server\'s authorized_keys.',
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

  // ── Empty state ──────────────────────────────────────────────────

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.all(48),
      child: Column(
        children: [
          Icon(
            Icons.vpn_key_rounded,
            size: 64,
            color: Colors.white.withValues(alpha: 0.1),
          )
              .animate(onPlay: (c) => c.repeat())
              .shimmer(
                  duration: 2500.ms,
                  color: AppConstants.primaryGreen.withValues(alpha: 0.08))
              .scale(
                begin: const Offset(1, 1),
                end: const Offset(1.02, 1.02),
                duration: 2500.ms,
                curve: Curves.easeInOutSine,
              ),
          const SizedBox(height: 20),
          Text(
            'No SSH keys yet',
            style: GoogleFonts.inter(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.white.withValues(alpha: 0.45),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Generate or import a key to get started',
            style: GoogleFonts.inter(
              fontSize: 14,
              color: Colors.white.withValues(alpha: 0.25),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // ── Key actions ──────────────────────────────────────────────────

  Future<void> _generateEd25519() async {
    final label = await showDialog<String>(
      context: context,
      builder: (context) => _LabelInputDialog(
        title: 'Generate Ed25519 Key',
        hintText: 'My Key',
        defaultValue: 'Ed25519 Key ${DateTime.now().year}',
      ),
    );

    if (label == null || label.trim().isEmpty) return;

    try {
      await ref.read(keyServiceProvider).generateEd25519(label: label.trim());

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded,
                    color: AppConstants.primaryGreen),
                const SizedBox(width: 8),
                Text(
                  'Ed25519 key generated',
                  style: GoogleFonts.inter(),
                ),
              ],
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to generate key: $e',
              style: GoogleFonts.inter(),
            ),
          ),
        );
      }
    }
  }

  Future<void> _importKey() async {
    final controller = TextEditingController();
    final label = await showDialog<String>(
      context: context,
      builder: (context) => _LabelInputDialog(
        title: 'Import SSH Key',
        hintText: 'Imported Key',
        defaultValue: 'Imported Key ${DateTime.now().year}',
      ),
    );

    if (label == null || label.trim().isEmpty) return;

    if (!mounted) return;
    final pemContent = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Paste Private Key'),
        content: TextField(
          controller: controller,
          maxLines: 10,
          decoration: const InputDecoration(
            hintText:
                '-----BEGIN OPENSSH PRIVATE KEY-----\n...\n-----END OPENSSH PRIVATE KEY-----',
            hintMaxLines: 3,
          ),
          style: GoogleFonts.jetBrainsMono(fontSize: 12),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Import'),
          ),
        ],
      ),
    );

    if (pemContent == null || pemContent.trim().isEmpty) return;

    try {
      await ref.read(keyServiceProvider).importKey(
            label: label.trim(),
            privateKeyPem: pemContent.trim(),
          );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded,
                    color: AppConstants.primaryGreen),
                const SizedBox(width: 8),
                Text(
                  'Key imported successfully',
                  style: GoogleFonts.inter(),
                ),
              ],
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to import key: $e',
              style: GoogleFonts.inter(),
            ),
          ),
        );
      }
    }
  }

  Future<void> _copyPublicKey(StoredKeyPair key) async {
    await Clipboard.setData(ClipboardData(text: key.publicKey));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.copy_rounded, color: AppConstants.primaryGreen),
              const SizedBox(width: 8),
              Text(
                'Public key copied to clipboard',
                style: GoogleFonts.inter(),
              ),
            ],
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _deleteKey(StoredKeyPair key) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Key'),
        content: Text('Delete "${key.label}"? This cannot be undone.'),
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
      await ref.read(keyServiceProvider).deleteKey(key.id);
    }
  }

  void _showAddKeyMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            decoration: BoxDecoration(
              color: AppConstants.surfaceDark.withValues(alpha: 0.9),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(20)),
              border: Border(
                top: BorderSide(
                  color: AppConstants.primaryGreen.withValues(alpha: 0.15),
                ),
              ),
            ),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 36,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    ListTile(
                      leading: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color:
                              AppConstants.primaryGreen.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.add_circle_outline_rounded,
                          color: AppConstants.primaryGreen,
                          size: 20,
                        ),
                      ),
                      title: Text(
                        'Generate Ed25519 Key',
                        style: GoogleFonts.inter(fontWeight: FontWeight.w500),
                      ),
                      subtitle: Text(
                        'Recommended',
                        style: GoogleFonts.inter(
                            fontSize: 11,
                            color: AppConstants.primaryGreen.withValues(alpha: 0.7)),
                      ),
                      onTap: () {
                        Navigator.pop(context);
                        _generateEd25519();
                      },
                    ),
                    ListTile(
                      leading: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: const Color(0xFF448AFF).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.upload_file_rounded,
                          color: Color(0xFF448AFF),
                          size: 20,
                        ),
                      ),
                      title: Text(
                        'Import Existing Key',
                        style: GoogleFonts.inter(fontWeight: FontWeight.w500),
                      ),
                      onTap: () {
                        Navigator.pop(context);
                        _importKey();
                      },
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
}

/// Simple dialog for entering a label.
class _LabelInputDialog extends StatefulWidget {
  const _LabelInputDialog({
    required this.title,
    required this.hintText,
    this.defaultValue,
  });

  final String title;
  final String hintText;
  final String? defaultValue;

  @override
  State<_LabelInputDialog> createState() => _LabelInputDialogState();
}

class _LabelInputDialogState extends State<_LabelInputDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.defaultValue ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(hintText: widget.hintText),
        onSubmitted: (value) => Navigator.pop(context, value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: const Text('OK'),
        ),
      ],
    );
  }
}
