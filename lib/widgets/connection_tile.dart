import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:tailscale/tailscale.dart';

import '../models/connection_profile.dart';
import '../utils/constants.dart';

/// A premium connection profile tile matching the Apple TUI 2.0 design system.
///
/// Features direct `> SSH` and `📂 SFTP` action buttons, status indicator dot,
/// environment tag pill (`PROD`, `STAGING`, `HOMELAB`), 3-stat horizontal
/// progress bars (`AUTH`, `SHELL`, `TUNNL`), and a profile action sheet.
class ConnectionTile extends StatefulWidget {
  const ConnectionTile({
    super.key,
    required this.profile,
    this.tailscaleState,
    required this.onTap,
    this.onSftpTap,
    this.onTunnelTap,
    this.onConfigTap,
    this.onQuickCommandsTap,
    this.onTelemetryTap,
    this.onLongPress,
  });

  final ConnectionProfile profile;
  final NodeState? tailscaleState;
  final VoidCallback onTap;
  final VoidCallback? onSftpTap;
  final VoidCallback? onTunnelTap;
  final VoidCallback? onConfigTap;
  final VoidCallback? onQuickCommandsTap;
  final VoidCallback? onTelemetryTap;
  final VoidCallback? onLongPress;

  @override
  State<ConnectionTile> createState() => _ConnectionTileState();
}

class _ConnectionTileState extends State<ConnectionTile>
    with TickerProviderStateMixin {
  late final AnimationController _statAnimCtrl;
  late final Animation<double> _authAnim;
  late final Animation<double> _shellAnim;
  late final Animation<double> _tunlAnim;

  @override
  void initState() {
    super.initState();
    _statAnimCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1050),
    );
    _authAnim = CurvedAnimation(
      parent: _statAnimCtrl,
      curve: const Interval(0.0, 0.50, curve: Curves.easeOutCubic),
    );
    _shellAnim = CurvedAnimation(
      parent: _statAnimCtrl,
      curve: const Interval(0.15, 0.65, curve: Curves.easeOutCubic),
    );
    _tunlAnim = CurvedAnimation(
      parent: _statAnimCtrl,
      curve: const Interval(0.30, 0.80, curve: Curves.easeOutCubic),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _statAnimCtrl.forward();
    });
  }

  @override
  void dispose() {
    _statAnimCtrl.dispose();
    super.dispose();
  }

  void _showActionSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppConstants.surfaceDark,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                  title: Text(
                    widget.profile.shortLabel,
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  subtitle: Text(
                    '${widget.profile.host}:${widget.profile.port}',
                    style: GoogleFonts.jetBrainsMono(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 11,
                    ),
                  ),
                ),
                const Divider(height: 12),
                _buildSheetAction(
                  sheetContext,
                  icon: Icons.folder_open_rounded,
                  label: 'SFTP',
                  color: AppConstants.accentBlue,
                  onTap: widget.onSftpTap,
                ),
                _buildSheetAction(
                  sheetContext,
                  icon: Icons.monitor_heart_rounded,
                  label: 'Telemetry',
                  color: AppConstants.primaryGreen,
                  onTap: widget.onTelemetryTap,
                ),
                _buildSheetAction(
                  sheetContext,
                  icon: Icons.swap_horiz_rounded,
                  label: 'Tunnels',
                  color: const Color(0xFF00BCD4),
                  onTap: widget.onTunnelTap,
                ),
                _buildSheetAction(
                  sheetContext,
                  icon: Icons.bolt_rounded,
                  label: 'Quick Commands',
                  color: AppConstants.accentPurple,
                  onTap: widget.onQuickCommandsTap,
                ),
                _buildSheetAction(
                  sheetContext,
                  icon: Icons.tune_rounded,
                  label: 'Edit Profile',
                  color: AppConstants.accentAmber,
                  onTap: widget.onConfigTap,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSheetAction(
    BuildContext sheetContext, {
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback? onTap,
  }) {
    return ListTile(
      enabled: onTap != null,
      leading: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(11),
        ),
        child: Icon(icon, color: color, size: 20),
      ),
      title: Text(
        label,
        style: GoogleFonts.inter(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
      trailing: Icon(
        Icons.chevron_right_rounded,
        color: Colors.white.withValues(alpha: 0.35),
      ),
      onTap: onTap == null
          ? null
          : () {
              Navigator.of(sheetContext).pop();
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) onTap();
              });
            },
    );
  }

  Color get _indicatorColor {
    final p = widget.profile;
    if (p.connectionMethod == ConnectionMethod.tailscale) {
      return switch (widget.tailscaleState) {
        NodeState.running => AppConstants.primaryGreen,
        NodeState.starting => AppConstants.accentAmber,
        NodeState.needsLogin || NodeState.noState => Colors.orange,
        _ => Colors.white.withValues(alpha: 0.2),
      };
    }
    return p.lastConnectionSuccess
        ? AppConstants.primaryGreen
        : Colors.white.withValues(alpha: 0.2);
  }

  bool get _isOnline => _indicatorColor == AppConstants.primaryGreen;

  double get _authPercent {
    switch (widget.profile.authType) {
      case AuthType.publicKey:
        return 0.90;
      case AuthType.password:
        return 0.40;
      case AuthType.passwordAndPublicKey:
        return 0.95;
    }
  }

  double get _tunnelPercent {
    final count = widget.profile.tunnels.length;
    if (count >= 3) return 1.0;
    if (count == 2) return 0.65;
    if (count == 1) return 0.35;
    return 0.0;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: SizedBox(height: 172, child: _buildTile()),
    );
  }

  Widget _buildTile() {
    final profile = widget.profile;
    final env = profile.effectiveEnvironment.toUpperCase();
    final envColor = env == 'PROD'
        ? const Color(0xFFFF453A)
        : (env == 'STAGING'
              ? const Color(0xFFFFD60A)
              : const Color(0xFF32D74B));

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF181C23),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
          width: 0.8,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          onLongPress: widget.onLongPress,
          borderRadius: BorderRadius.circular(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // ── Top Header Row ─────────────────────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Text(
                        profile.shortLabel,
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: envColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: envColor.withValues(alpha: 0.3),
                            width: 0.5,
                          ),
                        ),
                        child: Text(
                          env,
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            color: envColor,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ),
                    ],
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.more_horiz_rounded),
                        iconSize: 20,
                        color: Colors.white.withValues(alpha: 0.65),
                        tooltip: 'Profile actions',
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 32,
                          minHeight: 32,
                        ),
                        onPressed: _showActionSheet,
                      ),
                      const SizedBox(width: 8),
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _indicatorColor,
                          boxShadow: [
                            BoxShadow(
                              color: _indicatorColor.withValues(alpha: 0.6),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              // ── Host Subtitle Line ──────────────────────────────────────
              Text(
                '${profile.host}:${profile.port} • ${profile.authType == AuthType.publicKey ? 'Ed25519' : 'Password'}',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 11,
                  color: const Color(0xFF8E8E93),
                ),
              ),
              const SizedBox(height: 6),

              // ── RPG 3-Stat Progress Bars ───────────────────────────────
              AnimatedBuilder(
                animation: _statAnimCtrl,
                builder: (context, _) {
                  return Row(
                    children: [
                      Expanded(
                        child: _buildHorizontalStatBar(
                          'AUTH',
                          const Color(0xFF32D74B),
                          _authAnim.value * _authPercent,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildHorizontalStatBar(
                          'SHELL',
                          const Color(0xFFFFD60A),
                          _shellAnim.value * (_isOnline ? 0.65 : 0.20),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildHorizontalStatBar(
                          'TUNNL',
                          const Color(0xFF32D74B),
                          _tunlAnim.value *
                              (_tunnelPercent > 0 ? _tunnelPercent : 0.40),
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 10),

              // ── Direct Action Buttons Row ──────────────────────────────
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: widget.onTap,
                      child: Container(
                        height: 36,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              '>',
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFF00CCFF),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'SSH',
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF00CCFF),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        widget.onSftpTap?.call();
                      },
                      child: Container(
                        height: 36,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: const Color(
                              0xFF00CCFF,
                            ).withValues(alpha: 0.4),
                            width: 0.8,
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.folder_open_rounded,
                              size: 15,
                              color: Color(0xFF00CCFF),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'SFTP',
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF00CCFF),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHorizontalStatBar(String label, Color color, double percent) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.jetBrainsMono(
            fontSize: 9,
            fontWeight: FontWeight.w800,
            color: const Color(0xFF8E8E93),
          ),
        ),
        const SizedBox(height: 3),
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: Container(
            height: 4,
            width: double.infinity,
            color: const Color(0xFF363941),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: percent.clamp(0.05, 1.0),
              child: Container(color: color),
            ),
          ),
        ),
      ],
    );
  }
}

class ProfileColors {
  ProfileColors._();

  static const List<Color> palette = [
    Color(0xFF0A84FF),
    Color(0xFFFF9F0A),
    Color(0xFFFF453A),
    Color(0xFF30D158),
    Color(0xFFBF5AF2),
    Color(0xFFFFD60A),
    Color(0xFF5E5CE6),
    Color(0xFF64D2FF),
  ];

  static Color get(int index) => palette[index % palette.length];
}
