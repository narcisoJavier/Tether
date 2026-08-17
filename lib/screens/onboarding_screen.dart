import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/onboarding_service.dart';
import '../utils/constants.dart';

/// Dribbble/Muzli-inspired onboarding with autonomous live component animations.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen>
    with TickerProviderStateMixin {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  static const _totalPages = 4;

  // ── Animation Controllers ─────────────────────────────────────────────
  late final AnimationController _floatCtrl;
  late final AnimationController _scanCtrl;
  late final AnimationController _pulseCtrl;

  // ── Autonomous State Timers ───────────────────────────────────────────
  Timer? _terminalLineTimer;
  int _terminalLineCount = 1;

  Timer? _meshNodeTimer;
  int _activeMeshNode = 0;

  Timer? _securityScanTimer;
  bool _securityUnlocked = false;

  Timer? _commandCycleTimer;
  int _activeCommandIndex = 0;

  bool _cursorBlink = true;
  Timer? _cursorTimer;

  @override
  void initState() {
    super.initState();

    // Floating breathing animation for cards
    _floatCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);

    // Scanning radar / pulse for security and network
    _scanCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();

    // Subtle glow pulse
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    // Blinking cursor
    _cursorTimer = Timer.periodic(const Duration(milliseconds: 450), (_) {
      if (mounted) setState(() => _cursorBlink = !_cursorBlink);
    });

    // Autonomous Slide 1: Terminal streaming lines
    _terminalLineTimer = Timer.periodic(const Duration(milliseconds: 900), (_) {
      if (mounted) {
        setState(() {
          _terminalLineCount = (_terminalLineCount % 5) + 1;
        });
      }
    });

    // Autonomous Slide 2: Mesh node rotation
    _meshNodeTimer = Timer.periodic(const Duration(milliseconds: 1800), (_) {
      if (mounted) {
        setState(() {
          _activeMeshNode = (_activeMeshNode + 1) % 3;
        });
      }
    });

    // Autonomous Slide 3: Security scan sequence
    _securityScanTimer = Timer.periodic(const Duration(milliseconds: 2400), (_) {
      if (mounted) {
        setState(() {
          _securityUnlocked = !_securityUnlocked;
        });
      }
    });

    // Autonomous Slide 4: Command deck cycling
    _commandCycleTimer = Timer.periodic(const Duration(milliseconds: 1600), (_) {
      if (mounted) {
        setState(() {
          _activeCommandIndex = (_activeCommandIndex + 1) % 4;
        });
      }
    });
  }

  @override
  void dispose() {
    _floatCtrl.dispose();
    _scanCtrl.dispose();
    _pulseCtrl.dispose();
    _cursorTimer?.cancel();
    _terminalLineTimer?.cancel();
    _meshNodeTimer?.cancel();
    _securityScanTimer?.cancel();
    _commandCycleTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _completeOnboarding() async {
    await ref.read(onboardingServiceProvider).completeOnboarding();
    if (mounted) context.go('/');
  }

  void _skip() => _completeOnboarding();

  void _nextPage() {
    if (_currentPage < _totalPages - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    } else {
      _completeOnboarding();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.backgroundDark,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            Expanded(
              child: PageView(
                controller: _pageController,
                onPageChanged: (index) => setState(() => _currentPage = index),
                children: [
                  _buildSlide(
                    badge: 'CORE ENGINE',
                    badgeColor: AppConstants.primaryGreen,
                    title: 'Pocket SSH & Mesh Terminal',
                    subtitle:
                        'Hardware-accelerated VT100 terminal with embedded Tailscale WireGuard mesh networking in a pure Dart/Go client.',
                    tags: ['⚡ Pure Dart/Go', '🌐 Tailscale FFI', '🔒 Zero Cloud'],
                    card: _buildAnimatedTerminalCard(),
                  ),
                  _buildSlide(
                    badge: 'NETWORK TOPOLOGY',
                    badgeColor: AppConstants.accentBlue,
                    title: 'Direct SSH & Tailnet Mesh',
                    subtitle:
                        'Connect directly over IPv4/IPv6 or route seamlessly through your private WireGuard tailnet with SFTP and port tunnels.',
                    tags: ['🌐 WireGuard Mesh', '📁 SFTP Browser', '🔀 TCP Tunnels'],
                    card: _buildAnimatedMeshCard(),
                  ),
                  _buildSlide(
                    badge: 'HARDWARE SECURITY',
                    badgeColor: AppConstants.primaryGreen,
                    title: 'Hardware-Encrypted Enclave',
                    subtitle:
                        'Ed25519 and RSA keys are generated on-device and sealed in Android Hardware Keystore with biometric authentication.',
                    tags: ['🔑 Ed25519 Keys', '🛡️ Hardware Vault', '👆 Biometric Gate'],
                    card: _buildAnimatedSecurityCard(),
                  ),
                  _buildSlide(
                    badge: 'WORKFLOW DECK',
                    badgeColor: AppConstants.accentAmber,
                    title: 'Command Deck Automation',
                    subtitle:
                        'Save reusable scripts, agent harnesses, and DevOps snippets. Execute with one tap directly into active terminal tabs.',
                    tags: ['⚡ 1-Tap Run', '📑 Multi-Tab Sync', '⌨️ Touch Bar'],
                    card: _buildAnimatedCommandCard(),
                  ),
                ],
              ),
            ),
            _buildBottomControls(),
          ],
        ),
      ),
    );
  }

  // ── Top Bar ───────────────────────────────────────────────────────────

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  color: Colors.black,
                  border: Border.all(
                    color: AppConstants.primaryGreen.withValues(alpha: 0.5),
                    width: 0.8,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(5),
                  child: Image.asset(
                    'assets/logo.png',
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const Icon(
                      Icons.terminal_rounded,
                      size: 14,
                      color: AppConstants.primaryGreen,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Tether',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: 1.0,
                ),
              ),
            ],
          ),
          if (_currentPage < _totalPages - 1)
            TextButton(
              onPressed: _skip,
              style: TextButton.styleFrom(
                foregroundColor: Colors.white.withValues(alpha: 0.5),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                'Skip',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── Universal Slide Layout (Floating Animated Card Top, Content Bottom) ─

  Widget _buildSlide({
    required String badge,
    required Color badgeColor,
    required String title,
    required String subtitle,
    required List<String> tags,
    required Widget card,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          const SizedBox(height: 6),
          // Upper Visual Showcase with Smooth Vertical Float (Takes ~55% of height)
          Expanded(
            flex: 11,
            child: AnimatedBuilder(
              animation: _floatCtrl,
              builder: (context, child) {
                final offsetY = (_floatCtrl.value - 0.5) * 6.0;
                return Transform.translate(
                  offset: Offset(0, offsetY),
                  child: child,
                );
              },
              child: Center(
                child: card,
              ),
            ),
          ),
          const SizedBox(height: 14),
          // Lower Typography Section (Takes ~45% of height)
          Expanded(
            flex: 8,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: badgeColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: badgeColor.withValues(alpha: 0.3),
                      width: 0.8,
                    ),
                  ),
                  child: Text(
                    badge,
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      color: badgeColor,
                      letterSpacing: 1.0,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  title,
                  style: GoogleFonts.inter(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: -0.4,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  subtitle,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: Colors.white.withValues(alpha: 0.58),
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: tags.map((tag) {
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
                      ),
                      child: Text(
                        tag,
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: Colors.white.withValues(alpha: 0.65),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Card 1: Autonomous Live Terminal Stream ───────────────────────────

  Widget _buildAnimatedTerminalCard() {
    final terminalLines = [
      ('SSH Client', 'dartssh2 pure-Dart (v2.8.0)'),
      ('Mesh Core', 'Tailscale Go FFI (WireGuard)'),
      ('VT100 Matrix', 'xterm.dart 60 FPS Accelerated'),
      ('Session Sync', 'Stateful persistent background tabs'),
      ('Telemetry', '100% Offline & Local Hive DB'),
    ];

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF070B0A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppConstants.primaryGreen.withValues(
            alpha: 0.25 + (_pulseCtrl.value * 0.2),
          ),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: AppConstants.primaryGreen.withValues(
              alpha: 0.06 + (_pulseCtrl.value * 0.08),
            ),
            blurRadius: 28,
            spreadRadius: 2,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Titlebar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
              border: Border(
                bottom: BorderSide(color: Colors.white.withValues(alpha: 0.07)),
              ),
            ),
            child: Row(
              children: [
                Container(width: 9, height: 9, decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFFFF5F56))),
                const SizedBox(width: 6),
                Container(width: 9, height: 9, decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFFFFBD2E))),
                const SizedBox(width: 6),
                Container(width: 9, height: 9, decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF27C93F))),
                const SizedBox(width: 12),
                Text(
                  'tether@cluster: ~ (pty0)',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.white.withValues(alpha: 0.6),
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppConstants.primaryGreen.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 5,
                        height: 5,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppConstants.primaryGreen,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'ONLINE',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 8,
                          fontWeight: FontWeight.w800,
                          color: AppConstants.primaryGreen,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Terminal lines
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      '> tether status --mesh',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppConstants.primaryGreen,
                      ),
                    ),
                    if (_cursorBlink)
                      Container(
                        width: 7,
                        height: 13,
                        margin: const EdgeInsets.only(left: 4),
                        color: AppConstants.primaryGreen,
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                ...List.generate(terminalLines.length, (i) {
                  final line = terminalLines[i];
                  final isVisible = i < _terminalLineCount;
                  return AnimatedOpacity(
                    duration: const Duration(milliseconds: 300),
                    opacity: isVisible ? 1.0 : 0.08,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: [
                          Text(
                            '• ${line.$1}: ',
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 10,
                              color: isVisible ? Colors.white.withValues(alpha: 0.45) : Colors.white10,
                            ),
                          ),
                          Expanded(
                            child: Text(
                              line.$2,
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: isVisible ? Colors.white.withValues(alpha: 0.9) : Colors.white12,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Card 2: Autonomous Mesh Node Topology Rotation ────────────────────

  Widget _buildAnimatedMeshCard() {
    final nodes = [
      (
        title: 'PROD_CLUSTER',
        sub: 'Direct SSH (IPv4) • 159.89.24.110',
        badge: '14ms',
        color: AppConstants.primaryGreen,
        icon: Icons.dns_rounded,
      ),
      (
        title: 'HOMELAB_TAILNET',
        sub: 'WireGuard Mesh • 100.84.12.90',
        badge: '26ms',
        color: AppConstants.accentBlue,
        icon: Icons.hub_rounded,
      ),
      (
        title: 'DEV_TCP_TUNNEL',
        sub: 'Port Forward • L:8080 → R:3000',
        badge: 'ACTIVE',
        color: AppConstants.accentAmber,
        icon: Icons.compare_arrows_rounded,
      ),
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppConstants.surface0,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(nodes.length, (i) {
          final n = nodes[i];
          final isActive = _activeMeshNode == i;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOutCubic,
            margin: EdgeInsets.only(bottom: i == nodes.length - 1 ? 0 : 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isActive ? n.color.withValues(alpha: 0.12) : Colors.white.withValues(alpha: 0.02),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isActive ? n.color.withValues(alpha: 0.6) : Colors.white.withValues(alpha: 0.05),
                width: isActive ? 1.4 : 1.0,
              ),
              boxShadow: isActive
                  ? [
                      BoxShadow(
                        color: n.color.withValues(alpha: 0.15),
                        blurRadius: 12,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
            ),
            child: Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 350),
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: isActive ? n.color.withValues(alpha: 0.25) : n.color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(n.icon, size: 18, color: n.color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            n.title,
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: n.color.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              n.badge,
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 8,
                                fontWeight: FontWeight.w800,
                                color: n.color,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        n.sub,
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 10,
                          color: Colors.white.withValues(alpha: 0.45),
                        ),
                      ),
                    ],
                  ),
                ),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isActive ? n.color : Colors.transparent,
                    border: Border.all(
                      color: isActive ? n.color : Colors.white.withValues(alpha: 0.25),
                      width: 1.5,
                    ),
                  ),
                  child: isActive
                      ? const Icon(
                          Icons.check_rounded,
                          size: 12,
                          color: Colors.black,
                        )
                      : null,
                ),
              ],
            ),
          );
        }),
      ),
    );
  }

  // ── Card 3: Autonomous Keystore Enclave Scan Animation ────────────────

  Widget _buildAnimatedSecurityCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppConstants.surface0,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _securityUnlocked
              ? AppConstants.primaryGreen.withValues(alpha: 0.4)
              : Colors.white.withValues(alpha: 0.08),
        ),
        boxShadow: [
          BoxShadow(
            color: _securityUnlocked
                ? AppConstants.primaryGreen.withValues(alpha: 0.1)
                : Colors.black.withValues(alpha: 0.4),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 400),
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppConstants.primaryGreen.withValues(
                    alpha: _securityUnlocked ? 0.25 : 0.1,
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.vpn_key_rounded,
                  size: 20,
                  color: AppConstants.primaryGreen,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'id_ed25519_primary',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      'Ed25519 • Curve25519 (256-bit)',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 10,
                        color: AppConstants.primaryGreen,
                      ),
                    ),
                  ],
                ),
              ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 350),
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: _securityUnlocked
                      ? AppConstants.primaryGreen.withValues(alpha: 0.2)
                      : Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: _securityUnlocked
                        ? AppConstants.primaryGreen.withValues(alpha: 0.5)
                        : Colors.transparent,
                  ),
                ),
                child: Text(
                  _securityUnlocked ? 'AUTHENTICATED' : 'SEALED',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 8,
                    fontWeight: FontWeight.w800,
                    color: _securityUnlocked ? AppConstants.primaryGreen : Colors.white.withValues(alpha: 0.8),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white.withValues(alpha: 0.04)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'SHA256:7b4e91f0c2a8d3e64f8a91b2c7e034df...',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 9,
                    color: Colors.white.withValues(alpha: 0.4),
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      'VAULT: Android Hardware Keystore',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: AppConstants.primaryGreen.withValues(alpha: 0.85),
                      ),
                    ),
                    const Spacer(),
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppConstants.primaryGreen,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const Divider(color: Colors.white10, height: 1),
          const SizedBox(height: 8),
          Row(
            children: [
              AnimatedRotation(
                duration: const Duration(milliseconds: 500),
                turns: _securityUnlocked ? 0 : 0.05,
                child: const Icon(
                  Icons.fingerprint_rounded,
                  size: 22,
                  color: AppConstants.primaryGreen,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _securityUnlocked ? 'Biometric verification active' : 'Scanning biometric gate...',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _securityUnlocked ? Colors.white : Colors.white.withValues(alpha: 0.6),
                  ),
                ),
              ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _securityUnlocked
                      ? AppConstants.primaryGreen.withValues(alpha: 0.2)
                      : Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _securityUnlocked ? 'ENCLAVE READY' : 'SCANNING',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    color: _securityUnlocked ? AppConstants.primaryGreen : Colors.white.withValues(alpha: 0.5),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Card 4: Autonomous Command Deck Execution Stream ──────────────────

  Widget _buildAnimatedCommandCard() {
    final commands = [
      (
        tag: 'SYSTEM',
        command: 'htop --tree',
        desc: 'CPU: 2.1% • RAM: 184MB',
        color: AppConstants.accentBlue,
      ),
      (
        tag: 'DOCKER',
        command: 'docker compose up -d',
        desc: '4/4 containers healthy',
        color: AppConstants.primaryGreen,
      ),
      (
        tag: 'MESH',
        command: 'tailscale status',
        desc: '12 mesh peers online',
        color: AppConstants.accentAmber,
      ),
      (
        tag: 'AGENTS',
        command: 'python -m harness',
        desc: 'Autonomous runner active',
        color: const Color(0xFFFF5F56),
      ),
    ];

    final activeCmd = commands[_activeCommandIndex];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppConstants.surface0,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: commands.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 1.7,
            ),
            itemBuilder: (context, i) {
              final cmd = commands[i];
              final isCurrent = _activeCommandIndex == i;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isCurrent ? cmd.color.withValues(alpha: 0.15) : Colors.white.withValues(alpha: 0.02),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isCurrent ? cmd.color.withValues(alpha: 0.6) : Colors.white.withValues(alpha: 0.06),
                    width: isCurrent ? 1.4 : 1.0,
                  ),
                  boxShadow: isCurrent
                      ? [
                          BoxShadow(
                            color: cmd.color.withValues(alpha: 0.2),
                            blurRadius: 8,
                          ),
                        ]
                      : null,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          cmd.tag,
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            color: cmd.color,
                          ),
                        ),
                        Icon(
                          Icons.bolt_rounded,
                          size: 14,
                          color: isCurrent ? cmd.color : Colors.white.withValues(alpha: 0.2),
                        ),
                      ],
                    ),
                    Text(
                      cmd.command,
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      cmd.desc,
                      style: GoogleFonts.inter(
                        fontSize: 9,
                        color: Colors.white.withValues(alpha: 0.45),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 10),
          // Live Command Output Simulator
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: activeCmd.color.withValues(alpha: 0.25),
              ),
            ),
            child: Row(
              children: [
                Text(
                  '> ${activeCmd.command}: ',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 9,
                    color: Colors.white.withValues(alpha: 0.5),
                  ),
                ),
                Expanded(
                  child: Text(
                    activeCmd.desc,
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: activeCmd.color,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: activeCmd.color.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    'OK',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 7,
                      fontWeight: FontWeight.w900,
                      color: activeCmd.color,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Bottom Controls (Matching Dribbble References) ────────────────────

  Widget _buildBottomControls() {
    final isLast = _currentPage == _totalPages - 1;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
      child: isLast
          // Slide 4: Full-width Pill CTA "Start Tether"
          ? SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _completeOnboarding,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppConstants.primaryGreen,
                  foregroundColor: Colors.black,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'START TETHER',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.0,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.arrow_forward_rounded, size: 16),
                  ],
                ),
              ),
            )
          // Slides 1-3: Dot Indicators on Left + Next Arrow Button on Right
          : Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Animated Pill Dots
                Row(
                  children: List.generate(_totalPages, (i) {
                    final isActive = i == _currentPage;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOut,
                      margin: const EdgeInsets.only(right: 6),
                      width: isActive ? 22 : 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: isActive ? AppConstants.primaryGreen : Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(3),
                        boxShadow: isActive
                            ? [
                                BoxShadow(
                                  color: AppConstants.primaryGreen.withValues(alpha: 0.4),
                                  blurRadius: 6,
                                ),
                              ]
                            : null,
                      ),
                    );
                  }),
                ),
                // Circular Next Arrow Button
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppConstants.primaryGreen,
                    boxShadow: [
                      BoxShadow(
                        color: AppConstants.primaryGreen.withValues(alpha: 0.3),
                        blurRadius: 14,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: _nextPage,
                      customBorder: const CircleBorder(),
                      child: const Center(
                        child: Icon(
                          Icons.arrow_forward_rounded,
                          color: Colors.black,
                          size: 22,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
