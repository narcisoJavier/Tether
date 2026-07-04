import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:tailscale/tailscale.dart';
import '../models/connection_profile.dart';
import '../utils/constants.dart';


/// A compact list tile for a connection profile with swipe-to-reveal actions.
///
/// Swipe left reveals: SFTP, Config, Quick Commands.
/// Tap navigates to terminal. Long-press triggers edit/delete.
class ConnectionTile extends StatefulWidget {
  const ConnectionTile({
    super.key,
    required this.profile,
    this.tailscaleState,
    required this.onTap,
    this.onSftpTap,
    this.onConfigTap,
    this.onQuickCommandsTap,
    this.onLongPress,
  });

  final ConnectionProfile profile;
  final NodeState? tailscaleState;
  final VoidCallback onTap;
  final VoidCallback? onSftpTap;
  final VoidCallback? onConfigTap;
  final VoidCallback? onQuickCommandsTap;
  final VoidCallback? onLongPress;

  @override
  State<ConnectionTile> createState() => _ConnectionTileState();
}

class _ConnectionTileState extends State<ConnectionTile>
    with SingleTickerProviderStateMixin {
  static const double _actionsWidth = 156.0;
  static const double _revealThreshold = 0.35;

  late final AnimationController _slideCtrl;
  late final Animation<double> _offsetAnim;

  @override
  void initState() {
    super.initState();
    _slideCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
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

  void _snapBack() {
    _slideCtrl.reverse();
  }

  bool get _isRevealed => _slideCtrl.isCompleted;

  void _onDragUpdate(DragUpdateDetails d) {
    _slideCtrl.value = (_slideCtrl.value - d.delta.dx / _actionsWidth)
        .clamp(0.0, 1.0);
  }

  void _onDragEnd(DragEndDetails d) {
    if (_slideCtrl.value > _revealThreshold) {
      _slideCtrl.forward();
    } else {
      _slideCtrl.reverse();
    }
  }

  void _onTap() {
    if (_isRevealed) {
      _snapBack();
      return;
    }
    widget.onTap();
  }

  Color get _indicatorColor {
    final profile = widget.profile;
    if (profile.connectionMethod == ConnectionMethod.tailscale) {
      final state = widget.tailscaleState;
      if (state == NodeState.running) return AppConstants.primaryGreen;
      if (state == NodeState.needsLogin || state == NodeState.noState) {
        return Colors.orange;
      }
      if (state == NodeState.starting) return Colors.amber;
      return Colors.white.withValues(alpha: 0.3);
    }
    return profile.lastConnectionSuccess
        ? AppConstants.primaryGreen
        : Colors.white.withValues(alpha: 0.3);
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.profile;
    final accent = ProfileColors.get(profile.colorIndex);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
      child: SizedBox(
        height: 56,
        child: AnimatedBuilder(
          animation: _offsetAnim,
          builder: (context, child) {
            return ClipRect(
              child: Stack(
                children: [
                  // Background: action buttons, right-aligned
                  if (_slideCtrl.value > 0)
                    Positioned(
                      right: 8,
                      top: 0,
                      bottom: 0,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _ActionButton(
                            icon: Icons.folder_outlined,
                            label: 'SFTP',
                            color: const Color(0xFF448AFF),
                            onTap: () {
                              _snapBack();
                              widget.onSftpTap?.call();
                            },
                          ),
                          _ActionButton(
                            icon: Icons.settings_outlined,
                            label: 'Config',
                            color: const Color(0xFFFFAB40),
                            onTap: () {
                              _snapBack();
                              widget.onConfigTap?.call();
                            },
                          ),
                          _ActionButton(
                            icon: Icons.bolt_outlined,
                            label: 'QCMD',
                            color: const Color(0xFF7C4DFF),
                            onTap: () {
                              _snapBack();
                              widget.onQuickCommandsTap?.call();
                            },
                          ),
                        ],
                      ),
                    ),

                  // Foreground: the tile itself, slides left
                  Transform.translate(
                    offset: Offset(_offsetAnim.value, 0),
                    child: child,
                  ),
                ],
              ),
            );
          },
          child: _buildTileContent(accent),
        ),
      ),
    );
  }

  Widget _buildTileContent(Color accent) {
    final profile = widget.profile;

    return GestureDetector(
      onHorizontalDragUpdate: _onDragUpdate,
      onHorizontalDragEnd: _onDragEnd,
      child: Container(
      decoration: BoxDecoration(
        color: AppConstants.surfaceDark.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _onTap,
          onLongPress: widget.onLongPress,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                // Status dot
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
                const SizedBox(width: 12),

                // Accent bar
                Container(
                  width: 3,
                  height: 32,
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.circular(1.5),
                    boxShadow: [
                      BoxShadow(
                        color: accent.withValues(alpha: 0.3),
                        blurRadius: 6,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),

                // Name + host
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        profile.shortLabel,
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${profile.username}@${profile.host}:${profile.port}',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 11,
                          color: Colors.white.withValues(alpha: 0.4),
                        ),
                      ),
                    ],
                  ),
                ),

                // Method badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: profile.connectionMethod == ConnectionMethod.tailscale
                        ? Colors.blue.withValues(alpha: 0.15)
                        : Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    profile.connectionMethod == ConnectionMethod.tailscale
                        ? 'TS'
                        : 'DIRECT',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      color: profile.connectionMethod == ConnectionMethod.tailscale
                          ? Colors.blue.withValues(alpha: 0.8)
                          : Colors.white.withValues(alpha: 0.4),
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // Chevron
                Icon(
                  Icons.chevron_right,
                  size: 18,
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
}

/// Color palette for connection profile cards.
class ProfileColors {
  ProfileColors._();

  static const List<Color> palette = [
    Color(0xFF00E676), // green
    Color(0xFF448AFF), // blue
    Color(0xFFFF5252), // red
    Color(0xFFFFAB40), // amber
    Color(0xFFE040FB), // purple
    Color(0xFF18FFFF), // cyan
    Color(0xFFFF6E40), // deep orange
    Color(0xFF69F0AE), // light green
  ];

  static Color get(int index) => palette[index % palette.length];
}

/// A single action icon button shown on swipe reveal.
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
      width: 52,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(height: 2),
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                  color: Colors.white.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
