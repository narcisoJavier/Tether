import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/stored_key_pair.dart';
import '../utils/constants.dart';

/// A card widget representing a stored SSH key pair.
class KeyCard extends StatelessWidget {
  const KeyCard({
    super.key,
    required this.keyPair,
    this.onTap,
    this.onCopy,
    this.onDelete,
  });

  final StoredKeyPair keyPair;
  final VoidCallback? onTap;
  final VoidCallback? onCopy;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final isEd25519 = keyPair.keyType == KeyType.ed25519;
    final accent = isEd25519
        ? AppConstants.primaryGreen
        : const Color(0xFF448AFF);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Container(
        decoration: BoxDecoration(
          color: AppConstants.surfaceDark.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
          boxShadow: [
            BoxShadow(
              color: accent.withValues(alpha: 0.03),
              blurRadius: 16,
              spreadRadius: 2,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  // Key type icon with glow
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: accent.withValues(alpha: 0.2),
                        width: 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: accent.withValues(alpha: 0.15),
                          blurRadius: 8,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    child: Icon(
                      isEd25519 ? Icons.vpn_key_rounded : Icons.key_rounded,
                      color: accent,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 16),
                  // Key info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          keyPair.label,
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          keyPair.keyTypeLabel,
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: Colors.white.withValues(alpha: 0.4),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _truncatedPublicKey(keyPair.publicKey),
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 10,
                            color: Colors.white.withValues(alpha: 0.25),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  // Copy public key button
                  IconButton(
                    icon: Icon(
                      Icons.copy_rounded,
                      size: 18,
                      color: Colors.white.withValues(alpha: 0.4),
                    ),
                    tooltip: 'Copy public key',
                    onPressed: onCopy,
                  ),
                  // Delete button
                  IconButton(
                    icon: Icon(
                      Icons.delete_outline_rounded,
                      size: 18,
                      color: Colors.red.withValues(alpha: 0.5),
                    ),
                    tooltip: 'Delete key',
                    onPressed: onDelete,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _truncatedPublicKey(String key) {
    if (key.length > 40) {
      return '${key.substring(0, 37)}...';
    }
    return key;
  }
}
