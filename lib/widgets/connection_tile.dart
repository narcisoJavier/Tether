import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:tailscale/tailscale.dart';
import '../app_theme.dart';
import '../models/connection_profile.dart';
import '../utils/constants.dart';


/// A premium connection profile tile with swipe-to-reveal actions.
///
/// Design: layered glass card, neon status dot with bloom glow, colored
/// left-edge accent bar, and a smooth slide animation for action buttons.
///
/// Swipe left reveals: SFTP, FWD (tunnels), Config, Quick Commands.
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
    this.onLongPress,
  });

  final ConnectionProfile profile;
  final NodeState? tailscaleState;
  final VoidCallback onTap;
  final VoidCallback? onSftpTap;
  final VoidCallback? onTunnelTap;
  final VoidCallback? onConfigTap;
  final VoidCallback? onQuickCommandsTap;
  final VoidCallback? onLongPress;

  @override
  State<ConnectionTile> createState() => _ConnectionTileState();
}

class _ConnectionTileState extends State<ConnectionTile>
    with SingleTickerProviderStateMixin {
  static const double _actionsWidth = 216.0;
  static const double _revealThreshold = 0.35;

  late final AnimationController _slideCtrl;
  late final Animation<double> _offsetAnim;

  @override
  void initState() {
    super.initState();
    _slideCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
    _offsetAnim = Tween<double>(begin: 0, end: -_actionsWidth).animate(
      CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOutCubic),
    );
  }

  @override
  void dispose() {
    _slideCtrl.dispose();
    super.dispose();
  }

  void _snapBack() => _slideCtrl.reverse();
  bool get _isRevealed => _slideCtrl.isCompleted;

  void _onDragUpdate(DragUpdateDetails d) {
    _slideCtrl.value =
        (_slideCtrl.value - d.delta.dx / _actionsWidth).clamp(0.0, 1.0);
  }

  void _onDragEnd(DragEndDetails d) {
    _slideCtrl.value > _revealThreshold
        ? _slideCtrl.forward()
        : _slideCtrl.reverse();
  }

  void _onTap() {
    if (_isRevealed) {
      _snapBack();
      return;
    }
    widget.onTap();
  }

  /// Status indicator color based on connection state.
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

  bool get _isOnline =>
      _indicatorColor == AppConstants.primaryGreen;

  @override
  Widget build(BuildContext context) {
    final accent = ProfileColors.get(widget.profile.colorIndex);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      child: SizedBox(
        height: 72,
        child: AnimatedBuilder(
          animation: _offsetAnim,
          builder: (context, child) {
            return ClipRect(
              child: Stack(
                children: [
                  // ── Action buttons ───────────────────────────────────────
                  if (_slideCtrl.value > 0)
                    Positioned(
                      right: 0,
                      top: 0,
                      bottom: 0,
                      child: _buildActions(),
                    ),

                  // ── Tile foreground ──────────────────────────────────────
                  Transform.translate(
                    offset: Offset(_offsetAnim.value, 0),
                    child: child,
                  ),
                ],
              ),
            );
          },
          child: _buildTile(accent),
        ),
      ),
    );
  }

  Widget _buildActions() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ActionButton(
          icon: Icons.folder_open_rounded,
          label: 'SFTP',
          color: AppConstants.accentBlue,
          onTap: () {
            _snapBack();
            widget.onSftpTap?.call();
          },
        ),
        _ActionButton(
          icon: Icons.swap_horiz_rounded,
          label: 'Tunnels',
          color: const Color(0xFF00BCD4),
          onTap: () {
            _snapBack();
            widget.onTunnelTap?.call();
          },
        ),
        _ActionButton(
          icon: Icons.tune_rounded,
          label: 'Config',
          color: AppConstants.accentAmber,
          onTap: () {
            _snapBack();
            widget.onConfigTap?.call();
          },
        ),
        _ActionButton(
          icon: Icons.bolt_rounded,
          label: 'Cmds',
          color: AppConstants.accentPurple,
          onTap: () {
            _snapBack();
            widget.onQuickCommandsTap?.call();
          },
        ),
      ],
    );
  }

  Widget _buildTile(Color accent) {
    final profile = widget.profile;
    final isTailscale =
        profile.connectionMethod == ConnectionMethod.tailscale;

    return GestureDetector(
      onHorizontalDragUpdate: _onDragUpdate,
      onHorizontalDragEnd: _onDragEnd,
      child: Container(
        decoration: GlassDecoration.card(
          accentColor: accent,
          borderRadius: 14,
          highlighted: _isOnline,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _onTap,
            onLongPress: widget.onLongPress,
            borderRadius: BorderRadius.circular(14),
            splashColor: accent.withValues(alpha: 0.06),
            highlightColor: accent.withValues(alpha: 0.04),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                children: [
                  // ── Left accent bar ──────────────────────────────────
                  Container(
                    width: 3,
                    height: 40,
                    decoration: BoxDecoration(
                      color: accent,
                      borderRadius: BorderRadius.circular(2),
                      boxShadow: NeonGlow.of(accent, intensity: 0.7),
                    ),
                  ),
                  const SizedBox(width: 14),

                  // ── Label column ─────────────────────────────────────
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Name
                        Text(
                          profile.shortLabel,
                          style: GoogleFonts.inter(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Colors.white.withValues(alpha: 0.95),
                            letterSpacing: 0.1,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 3),
                        // Host:port
                        Text(
                          '${profile.username}@${profile.host}:${profile.port}',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 11.5,
                            color: Colors.white.withValues(alpha: 0.38),
                            letterSpacing: 0.0,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // ── Status + method badge ─────────────────────────────
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      // Method badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: isTailscale
                              ? AppConstants.accentBlue.withValues(alpha: 0.12)
                              : Colors.white.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(5),
                          border: Border.all(
                            color: isTailscale
                                ? AppConstants.accentBlue.withValues(alpha: 0.25)
                                : AppConstants.border0,
                            width: 0.8,
                          ),
                        ),
                        child: Text(
                          isTailscale ? 'TS' : 'SSH',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: isTailscale
                                ? AppConstants.accentBlue.withValues(alpha: 0.9)
                                : Colors.white.withValues(alpha: 0.35),
                            letterSpacing: 0.8,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      // Status dot
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _indicatorColor,
                              boxShadow: _isOnline
                                  ? NeonGlow.dot(AppConstants.primaryGreen)
                                  : null,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            _isOnline ? 'ready' : 'idle',
                            style: GoogleFonts.inter(
                              fontSize: 10,
                              color: _isOnline
                                  ? AppConstants.primaryGreen
                                      .withValues(alpha: 0.8)
                                  : Colors.white.withValues(alpha: 0.25),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(width: 4),

                  // Chevron
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: Colors.white.withValues(alpha: 0.18),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── ProfileColors ────────────────────────────────────────────────────────────

/// Color palette for connection profile accent bars.
class ProfileColors {
  ProfileColors._();

  static const List<Color> palette = [
    Color(0xFF00E5A0), // teal-green (matches primary)
    Color(0xFF2979FF), // electric blue
    Color(0xFFFF5370), // coral red
    Color(0xFFFFAB40), // amber
    Color(0xFF9C6FFF), // soft purple
    Color(0xFF00BCD4), // cyan
    Color(0xFFFF6B6B), // salmon
    Color(0xFF69F0AE), // mint green
  ];

  static Color get(int index) => palette[index % palette.length];
}

// ── Action Button ─────────────────────────────────────────────────────────────

/// A compact swipe-action icon + label button.
class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 54,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          splashColor: color.withValues(alpha: 0.12),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: color.withValues(alpha: 0.2),
                      width: 0.8,
                    ),
                  ),
                  child: Icon(icon, color: color, size: 18),
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: GoogleFonts.inter(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w600,
                    color: Colors.white.withValues(alpha: 0.65),
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
