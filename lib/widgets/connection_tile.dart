import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:tailscale/tailscale.dart';

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
    with TickerProviderStateMixin {
  static const double _actionsWidth = 216.0;
  static const double _revealThreshold = 0.35;

  late final AnimationController _slideCtrl;
  late final Animation<double> _offsetAnim;

  // ── RPG stat bar animations (3 staggered bars) ─────────────────────────
  late final AnimationController _statAnimCtrl;
  late final Animation<double> _authAnim;
  late final Animation<double> _shellAnim;
  late final Animation<double> _tunlAnim;

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

    // Three staggered RPG stat bars: AUTH → SHELL → TUNNL cascade.
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

    // Start the staggered animation after the first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _statAnimCtrl.forward();
    });
  }

  @override
  void dispose() {
    _slideCtrl.dispose();
    _statAnimCtrl.dispose();
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: SizedBox(
        height: 118,
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

  // ── RPG card with 3 animated stat bars ─────────────────────────────────

  /// Terminal-styled card with left accent strip, subtle shadow, and three
  /// staggered stat bars: AUTH (security), SHELL (connection), TUNNL (load).
  Widget _buildTile(Color accent) {
    final profile = widget.profile;
    final isTailscale =
        profile.connectionMethod == ConnectionMethod.tailscale;

    return GestureDetector(
      onHorizontalDragUpdate: _onDragUpdate,
      onHorizontalDragEnd: _onDragEnd,
      child: Container(
        decoration: BoxDecoration(
          color: AppConstants.bgBase,
          // ── Left accent strip via gradient ──────────────────────────
          border: Border(
            left: BorderSide(color: accent, width: 2.5),
            right: BorderSide(
                color: accent.withValues(alpha: 0.15), width: 0.5),
            top: BorderSide(
                color: accent.withValues(alpha: 0.20), width: 0.5),
            bottom: BorderSide(
                color: accent.withValues(alpha: 0.35), width: 1.5),
          ),
          // ── Subtle card shadow ──────────────────────────────────────
          boxShadow: [
            BoxShadow(
              color: accent.withValues(alpha: 0.06),
              blurRadius: 6,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _onTap,
            onLongPress: widget.onLongPress,
            splashColor: accent.withValues(alpha: 0.06),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Title bar ──────────────────────────────────────────
                _buildTitleBar(profile.shortLabel, accent, isTailscale),
                Container(height: 1, color: accent.withValues(alpha: 0.15)),

                // ── Stat rows ──────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(9, 4, 9, 5),
                  child: Column(
                    children: [
                      _buildHostLine(
                          '${profile.username}@${profile.host}:${profile.port}'),
                      const SizedBox(height: 3),
                      _buildStatBar('AUTH', accent, _authAnim,
                          percent: _authPercent),
                      const SizedBox(height: 2),
                      _buildStatBar('SHELL', accent, _shellAnim,
                          percent: _isOnline ? 0.85 : 0.15),
                      const SizedBox(height: 2),
                      _buildStatBar('TUNNL', accent, _tunlAnim,
                          percent: _tunnelPercent),
                      const SizedBox(height: 2),
                      _buildCardFooter(accent),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Auth strength: pubkey=90%, password=40%, both=95%.
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

  /// Tunnel load: 0→0%, 1→35%, 2→65%, 3+→100%.
  double get _tunnelPercent {
    final count = widget.profile.tunnels.length;
    if (count >= 3) return 1.0;
    if (count == 2) return 0.65;
    if (count == 1) return 0.35;
    return 0.0;
  }

  /// Title bar: server name left, method badge right.
  Widget _buildTitleBar(String label, Color accent, bool isTailscale) {
    return Container(
      height: 20,
      padding: const EdgeInsets.symmetric(horizontal: 7),
      color: accent.withValues(alpha: 0.10),
      child: Row(
        children: [
          Text(
            label,
            style: GoogleFonts.jetBrainsMono(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: accent.withValues(alpha: 0.85),
            ),
            overflow: TextOverflow.ellipsis,
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              border: Border.all(
                  color: accent.withValues(alpha: 0.25), width: 0.5),
            ),
            child: Text(
              isTailscale ? 'TS' : 'SSH',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 7,
                fontWeight: FontWeight.w800,
                color: accent,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Host line with terminal prompt prefix.
  Widget _buildHostLine(String host) {
    return Row(
      children: [
        Text(
          '> ',
          style: GoogleFonts.jetBrainsMono(
            fontSize: 10,
            color: Colors.white.withValues(alpha: 0.15),
          ),
        ),
        Expanded(
          child: Text(
            host,
            style: GoogleFonts.jetBrainsMono(
              fontSize: 10,
              color: Colors.white.withValues(alpha: 0.50),
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  /// One animated pip bar: label + 10 discrete segments + percentage.
  ///
  /// Renders like a classic RPG health bar: filled pips are the accent color,
  /// empty pips are a dim background. Each pip has a hairline gap for the
  /// segmented look (Tick Bar / Pip Bar style).
  Widget _buildStatBar(
      String label, Color color, Animation<double> anim,
      {required double percent}) {
    const totalPips = 10;
    const pipGap = 1.5;
    const pipHeight = 7.0;

    return AnimatedBuilder(
      animation: anim,
      builder: (context, _) {
        final pipsFilled =
            (anim.value * percent * totalPips).round().clamp(0, totalPips);
        return Row(
          children: [
            // ── Label ──────────────────────────────────────────────────
            SizedBox(
              width: 34,
              child: Text(
                label,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 8,
                  fontWeight: FontWeight.w700,
                  color: Colors.white.withValues(alpha: 0.25),
                  letterSpacing: 0.4,
                ),
              ),
            ),
            // ── Pip row ────────────────────────────────────────────────
            Expanded(
              child: SizedBox(
                height: pipHeight,
                child: Row(
                  children: List.generate(totalPips, (i) {
                    final isFilled = i < pipsFilled;
                    return Expanded(
                      child: Container(
                        margin: EdgeInsets.only(
                            right: i < totalPips - 1 ? pipGap : 0),
                        decoration: BoxDecoration(
                          color: isFilled
                              ? color.withValues(alpha: 0.70)
                              : Colors.white.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(1.2),
                        ),
                      ),
                    );
                  }),
                ),
              ),
            ),
            const SizedBox(width: 5),
            // ── Percentage ─────────────────────────────────────────────
            SizedBox(
              width: 24,
              child: Text(
                '${(pipsFilled / totalPips * 100).round()}%',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 8,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withValues(alpha: 0.25),
                ),
                textAlign: TextAlign.right,
              ),
            ),
          ],
        );
      },
    );
  }

  /// Card footer: status dot + ONLINE/IDLE + tunnel count + session tag.
  Widget _buildCardFooter(Color accent) {
    final tunnelCount = widget.profile.tunnels.length;
    return Row(
      children: [
        Container(
          width: 4,
          height: 4,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _indicatorColor,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          _isOnline ? 'ONLINE' : 'IDLE',
          style: GoogleFonts.jetBrainsMono(
            fontSize: 7,
            fontWeight: FontWeight.w700,
            color: _isOnline
                ? accent.withValues(alpha: 0.65)
                : Colors.white.withValues(alpha: 0.15),
            letterSpacing: 0.5,
          ),
        ),
        if (tunnelCount > 0) ...[
          const SizedBox(width: 8),
          Icon(Icons.alt_route_rounded,
              size: 7, color: Colors.white.withValues(alpha: 0.12)),
          const SizedBox(width: 2),
          Text(
            '$tunnelCount',
            style: GoogleFonts.jetBrainsMono(
              fontSize: 7,
              color: Colors.white.withValues(alpha: 0.12),
            ),
          ),
        ],
        if (_isOnline) ...[
          const SizedBox(width: 8),
          Text(
            'session active',
            style: GoogleFonts.jetBrainsMono(
              fontSize: 7,
              color: Colors.white.withValues(alpha: 0.12),
            ),
          ),
        ],
      ],
    );
  }
}

// ── ProfileColors ────────────────────────────────────────────────────────────

/// Color palette for connection profile accent bars.
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
