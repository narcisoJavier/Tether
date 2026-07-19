import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/connection_profile.dart';
import 'package:tailscale/tailscale.dart';
import '../utils/constants.dart';

/// Color palette for connection profile cards.
class ProfileColors {
  ProfileColors._();

  static const List<Color> palette = [
    Color(0xFF0A84FF), // Apple System Blue
    Color(0xFFFF9F0A), // Apple System Orange
    Color(0xFFFF453A), // Apple System Red
    Color(0xFF30D158), // Apple System Green
    Color(0xFFBF5AF2), // Apple System Purple
    Color(0xFFFFD60A), // Apple System Yellow
    Color(0xFF5E5CE6), // Apple System Indigo
    Color(0xFF64D2FF), // Apple System Cyan
  ];

  static Color get(int index) => palette[index % palette.length];
}

/// A card widget representing a saved SSH connection profile.
class ConnectionCard extends StatelessWidget {
  const ConnectionCard({
    super.key,
    required this.profile,
    this.onTap,
    this.onLongPress,
    this.tailscaleState,
  });

  final ConnectionProfile profile;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final NodeState? tailscaleState;

  @override
  Widget build(BuildContext context) {
    final accent = ProfileColors.get(profile.colorIndex);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Container(
            decoration: BoxDecoration(
              color: AppConstants.surfaceDark.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.06),
              ),
              boxShadow: [
                BoxShadow(
                  color: accent.withValues(alpha: 0.04),
                  blurRadius: 20,
                  spreadRadius: 2,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onTap,
                onLongPress: onLongPress,
                borderRadius: BorderRadius.circular(14),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      // Accent bar with glow
                      Container(
                        width: 4,
                        height: 48,
                        decoration: BoxDecoration(
                          color: accent,
                          borderRadius: BorderRadius.circular(2),
                          boxShadow: [
                            BoxShadow(
                              color: accent.withValues(alpha: 0.4),
                              blurRadius: 8,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      // Profile info
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                // Connection status indicator
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: _indicatorColor,
                                    boxShadow: _indicatorColor == AppConstants.primaryGreen
                                        ? [
                                            BoxShadow(
                                              color: AppConstants.primaryGreen
                                                  .withValues(alpha: 0.4),
                                              blurRadius: 6,
                                            ),
                                          ]
                                        : null,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    profile.shortLabel,
                                    style: GoogleFonts.inter(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${profile.username}@${profile.host}:${profile.port}',
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 12,
                                color: Colors.white.withValues(alpha: 0.5),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                Text(
                                  _authTypeLabel(profile.authType),
                                  style: GoogleFonts.inter(
                                    fontSize: 11,
                                    color: accent.withValues(alpha: 0.8),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                // Connection method badge
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: profile.connectionMethod == ConnectionMethod.tailscale
                                        ? Colors.blue.withValues(alpha: 0.15)
                                        : Colors.white.withValues(alpha: 0.06),
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                  child: Text(
                                    profile.connectionMethod == ConnectionMethod.tailscale ? 'TS' : 'DIRECT',
                                    style: GoogleFonts.jetBrainsMono(
                                      fontSize: 8,
                                      fontWeight: FontWeight.w600,
                                      color: profile.connectionMethod == ConnectionMethod.tailscale
                                          ? Colors.blue.withValues(alpha: 0.8)
                                          : Colors.white.withValues(alpha: 0.4),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      // Tap to connect arrow
                      Icon(
                        Icons.chevron_right,
                        color: Colors.white.withValues(alpha: 0.2),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
    );
  }

  Color get _indicatorColor {
    if (profile.connectionMethod == ConnectionMethod.tailscale) {
      if (tailscaleState == NodeState.running) return AppConstants.primaryGreen;
      if (tailscaleState == NodeState.needsLogin || tailscaleState == NodeState.noState) return Colors.orange;
      if (tailscaleState == NodeState.starting) return Colors.amber;
      return Colors.white.withValues(alpha: 0.3);
    }
    return profile.lastConnectionSuccess
        ? AppConstants.primaryGreen
        : Colors.white.withValues(alpha: 0.3);
  }

  String _authTypeLabel(AuthType type) {
    switch (type) {
      case AuthType.password:
        return 'Password';
      case AuthType.publicKey:
        return 'Public Key';
      case AuthType.passwordAndPublicKey:
        return 'Password + Key';
    }
  }
}
