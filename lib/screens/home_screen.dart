import 'package:flutter/material.dart';
import 'package:tailscale/tailscale.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/connection_profile.dart';
import '../services/profile_storage_service.dart';
import '../services/key_service.dart';
import '../services/tailscale_provider.dart';
import '../services/terminal_tab_request_provider.dart';
import '../services/update_service.dart';
import '../utils/constants.dart';
import '../widgets/connection_tile.dart';
import '../widgets/gradient_scaffold.dart';

/// Main home screen matching the Apple TUI 2.0 / HTML design spec.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with WidgetsBindingObserver {
  NodeState? _tailscaleNodeState;
  bool _tailscaleListenerRegistered = false;
  TailscaleStatus? _tailscaleStatus;
  String _selectedEnvFilter = 'ALL NODES';

  late final PageController _heroPageCtrl;
  int _heroPageIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _heroPageCtrl = PageController();
    _checkForUpdate();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _heroPageCtrl.dispose();
    super.dispose();
  }

  Future<void> _checkForUpdate() async {
    final info = await UpdateService.checkForUpdate();
    if (!mounted || info == null) return;
    _showUpdateDialog(info);
  }

  Future<void> _showAuthUrl() async {
    try {
      final ts = ref.read(tailscaleServiceProvider);
      final st = await ts.status();
      if (st.authUrl != null && mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
            ),
            backgroundColor: AppConstants.surfaceDark,
            title: const Text('Tailscale Auth Required'),
            content: const Text('Open this URL in a browser to authenticate:'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () {
                  launchUrl(st.authUrl!);
                  Navigator.pop(ctx);
                },
                child: const Text('Open URL'),
              ),
            ],
          ),
        );
      }
    } catch (_) {}
  }

  void _showConnectionTelemetry(ConnectionProfile profile) {
    final authLabel = switch (profile.authType) {
      AuthType.publicKey => 'Public key',
      AuthType.password => 'Password',
      AuthType.passwordAndPublicKey => 'Key + password',
    };
    final methodLabel = profile.connectionMethod == ConnectionMethod.tailscale
        ? 'Tailscale mesh'
        : 'Direct TCP';

    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      useSafeArea: true,
      backgroundColor: AppConstants.surfaceDark,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        Widget row(String label, String value, {Color? valueColor}) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                SizedBox(
                  width: 100,
                  child: Text(
                    label,
                    style: GoogleFonts.jetBrainsMono(
                      color: Colors.white.withValues(alpha: 0.45),
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    value,
                    textAlign: TextAlign.right,
                    style: GoogleFonts.jetBrainsMono(
                      color: valueColor ?? Colors.white.withValues(alpha: 0.85),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'CONNECTION TELEMETRY',
                  style: GoogleFonts.jetBrainsMono(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.0,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${profile.shortLabel} • ${profile.host}:${profile.port}',
                  style: GoogleFonts.jetBrainsMono(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                  child: Column(
                    children: [
                      row(
                        'LAST RESULT',
                        profile.lastConnectionSuccess
                            ? 'Success'
                            : 'Not connected',
                        valueColor: profile.lastConnectionSuccess
                            ? AppConstants.primaryGreen
                            : Colors.white.withValues(alpha: 0.6),
                      ),
                      row('METHOD', methodLabel),
                      row('AUTH', authLabel),
                      row('TUNNELS', '${profile.tunnels.length} configured'),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Live server CPU, RAM, and disk metrics are not collected yet. '
                  'This panel is the entry point for SSH-based telemetry later.',
                  style: GoogleFonts.inter(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.pop(sheetContext),
                    child: const Text('Done'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _autoRetryTailscale();
    }
  }

  Future<void> _autoRetryTailscale() async {
    try {
      final ts = ref.read(tailscaleServiceProvider);
      if (!ts.isInitialized) return;
      final st = await ts.status();
      if ((st.state == NodeState.needsLogin ||
              st.state == NodeState.needsMachineAuth) &&
          st.authUrl != null &&
          mounted) {
        _showAuthUrl();
      } else if (st.state == NodeState.stopped ||
          st.state == NodeState.noState) {
        final key = await ts.readAuthKey();
        if (key != null && key.isNotEmpty) {
          await ts.up(authKey: key);
        }
      }
    } catch (_) {}
  }

  void _showUpdateDialog(UpdateInfo info) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
        backgroundColor: AppConstants.surfaceDark,
        title: Row(
          children: [
            const Icon(
              Icons.system_update_rounded,
              color: AppConstants.primaryGreen,
              size: 24,
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                'Update Available',
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Tether v${info.latestVersion} is ready to install.',
              style: GoogleFonts.inter(
                color: Colors.white.withValues(alpha: 0.8),
                fontSize: 14,
              ),
            ),
            if (info.releaseNotes.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                constraints: const BoxConstraints(maxHeight: 160),
                child: SingleChildScrollView(
                  child: Text(
                    info.releaseNotes,
                    style: GoogleFonts.inter(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF448AFF),
              side: const BorderSide(color: Color(0xFF448AFF), width: 1.2),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: Text(
              'Later',
              style: GoogleFonts.inter(fontWeight: FontWeight.w600),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              launchUrl(
                Uri.parse(info.downloadUrl),
                mode: LaunchMode.externalApplication,
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppConstants.primaryGreen,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: Text(
              'Download APK',
              style: GoogleFonts.inter(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showTailscaleSettings() async {
    if (!mounted) return;
    final ts = ref.read(tailscaleServiceProvider);
    TailscaleStatus? st;
    try {
      st = await ts.status();
    } catch (_) {}
    final hasAuthKey = await ts.readAuthKey();
    if (!mounted) return;
    final nodeState = _tailscaleNodeState;
    Color stateColor;
    String stateLabel;
    if (nodeState == null || nodeState == NodeState.noState) {
      stateColor = Colors.grey;
      stateLabel = 'Not initialized';
    } else if (nodeState == NodeState.running) {
      stateColor = const Color(0xFF32D74B);
      stateLabel = 'Connected';
    } else if (nodeState == NodeState.needsLogin ||
        nodeState == NodeState.needsMachineAuth) {
      stateColor = const Color(0xFFFF9800);
      stateLabel = nodeState == NodeState.needsLogin
          ? 'Login required'
          : 'Machine auth required';
    } else if (nodeState == NodeState.starting) {
      stateColor = const Color(0xFFFFD54F);
      stateLabel = 'Connecting';
    } else {
      stateColor = Colors.grey;
      stateLabel = 'Stopped';
    }
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
          ),
          backgroundColor: AppConstants.surfaceDark,
          title: Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: stateColor,
                  boxShadow: [
                    BoxShadow(
                      color: stateColor.withValues(alpha: 0.4),
                      blurRadius: 6,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              const Text('Tailscale Node'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _tsInfoRow('Status', stateLabel, stateColor),
              if (st != null) ...[
                const SizedBox(height: 6),
                _tsInfoRow('IPv4', st.ipv4 ?? '-', Colors.white70),
                const SizedBox(height: 6),
                _tsInfoRow('DNS', st.magicDNSSuffix ?? '-', Colors.white70),
                const SizedBox(height: 6),
                _tsInfoRow('Node ID', st.stableNodeId ?? '-', Colors.white70),
              ],
              const SizedBox(height: 12),
              _tsInfoRow(
                'Auth Key',
                hasAuthKey != null ? 'Configured' : 'Not set',
                hasAuthKey != null ? AppConstants.primaryGreen : Colors.white38,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () async {
                Navigator.pop(ctx);
                try {
                  await ts.logout();
                  if (mounted) setState(() {});
                } catch (_) {}
              },
              child: const Text('Logout'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(ctx);
                try {
                  await ts.up();
                } catch (_) {}
              },
              child: const Text('Reconnect'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Widget _tsInfoRow(String label, String value, Color valueColor) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white54, fontSize: 13),
        ),
        Text(
          value,
          style: TextStyle(
            color: valueColor,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  /// Fetch live Tailscale status (IP, DNS, node ID) for the hero card.
  Future<void> _fetchTailscaleStatus() async {
    try {
      final ts = ref.read(tailscaleServiceProvider);
      if (!ts.isInitialized) return;
      final st = await ts.status();
      if (!mounted) return;
      setState(() => _tailscaleStatus = st);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (!_tailscaleListenerRegistered) {
      _tailscaleListenerRegistered = true;
      ref.listen<AsyncValue<NodeState?>>(tailscaleStateProvider, (_, next) {
        final state = next.valueOrNull;
        if (!mounted) return;
        setState(() => _tailscaleNodeState = state);
        if (state == NodeState.needsLogin) {
          _showAuthUrl();
        }
        _fetchTailscaleStatus();
      });
    }

    final storage = ref.watch(profileStorageProvider);
    final profiles = storage.listProfiles();
    final isTailscaleConfigured =
        _tailscaleNodeState != null && _tailscaleNodeState != NodeState.noState;

    return GradientScaffold(
      extendBodyBehindAppBar: false,
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
                Icons.home_rounded,
                size: 12,
                color: Color(0xFFC0C6D6),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'HOME',
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
          if (isTailscaleConfigured)
            GestureDetector(
              onTap: _showTailscaleSettings,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF181C23),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: const Color(0xFF00CCFF).withValues(alpha: 0.2),
                    width: 0.8,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _tailscaleNodeState == NodeState.running
                            ? const Color(0xFF32D74B)
                            : const Color(0xFFFFD60A),
                        boxShadow: [
                          BoxShadow(
                            color:
                                (_tailscaleNodeState == NodeState.running
                                        ? const Color(0xFF32D74B)
                                        : const Color(0xFFFFD60A))
                                    .withValues(alpha: 0.6),
                            blurRadius: 6,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _tailscaleNodeState == NodeState.running
                          ? 'TAILSCALE ACTIVE'
                          : 'TAILSCALE IDLE',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: _tailscaleNodeState == NodeState.running
                            ? const Color(0xFF32D74B)
                            : const Color(0xFFFFD60A),
                        letterSpacing: 0.6,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(width: 12),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          setState(() {});
        },
        color: const Color(0xFF00CCFF),
        child: ListView(
          padding: const EdgeInsets.only(top: 12, bottom: 100),
          children: [
            // ── Swipeable Hero Node Cards Carousel ──
            Column(
              children: [
                SizedBox(
                  height: 176,
                  child: PageView(
                    controller: _heroPageCtrl,
                    onPageChanged: (i) => setState(() => _heroPageIndex = i),
                    children: [
                      _buildTailscaleHeroCard(),
                      _buildSshMeshHeroCard(profiles),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: _heroPageIndex == 0 ? 16 : 6,
                      height: 6,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(3),
                        color: _heroPageIndex == 0
                            ? const Color(0xFF00CCFF)
                            : const Color(0xFF414754),
                      ),
                    ),
                    const SizedBox(width: 6),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: _heroPageIndex == 1 ? 16 : 6,
                      height: 6,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(3),
                        color: _heroPageIndex == 1
                            ? const Color(0xFFBF5AF2)
                            : const Color(0xFF414754),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),

            // ── Environment Filter Chips ──
            SizedBox(
              height: 38,
              child: ShaderMask(
                shaderCallback: (Rect bounds) {
                  return const LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [Colors.black, Colors.black, Colors.transparent],
                    stops: [0.0, 0.88, 1.0],
                  ).createShader(bounds);
                },
                blendMode: BlendMode.dstIn,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.only(left: 16, right: 32),
                  children: [
                    _buildEnvFilterChip(
                      'ALL NODES',
                      Colors.white,
                      const Color(0xFF00CCFF),
                    ),
                    const SizedBox(width: 8),
                    _buildEnvFilterChip(
                      'PROD',
                      const Color(0xFF8E8E93),
                      const Color(0xFFFF453A),
                    ),
                    const SizedBox(width: 8),
                    _buildEnvFilterChip(
                      'STAGING',
                      const Color(0xFF8E8E93),
                      const Color(0xFFFFD60A),
                    ),
                    const SizedBox(width: 8),
                    _buildEnvFilterChip(
                      'HOMELAB',
                      const Color(0xFF8E8E93),
                      const Color(0xFF32D74B),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ── Connection profiles list ──
            if (profiles.isEmpty)
              _buildEmptyState(
                icon: Icons.router_outlined,
                title: 'NO CONNECTIONS YET',
                subtitle: 'Tap + to add your first SSH connection',
              )
            else
              ...profiles
                  .where((p) {
                    final filter = _selectedEnvFilter.toUpperCase();
                    if (filter == 'ALL NODES') return true;
                    return p.effectiveEnvironment.toUpperCase() == filter;
                  })
                  .map(
                    (profile) => ConnectionTile(
                      profile: profile,
                      tailscaleState: _tailscaleNodeState,
                      onTap: () => _connectTo(profile),
                      onLongPress: () => _editProfile(profile),
                      onSftpTap: () => context.push('/sftp/${profile.id}'),
                      onTunnelTap: () => context.push('/tunnel/${profile.id}'),
                      onConfigTap: () => context.push('/profile/${profile.id}'),
                      onQuickCommandsTap: () => context.push('/commands'),
                      onTelemetryTap: () => _showConnectionTelemetry(profile),
                    ),
                  ),
          ],
        ),
      ),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 92, right: 8),
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF3E90FF),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF3E90FF).withValues(alpha: 0.45),
                blurRadius: 20,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => context.push('/profile/new'),
              borderRadius: BorderRadius.circular(28),
              child: const Icon(
                Icons.add_rounded,
                color: Colors.white,
                size: 28,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTailscaleHeroCard() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GestureDetector(
        onTap: _showTailscaleSettings,
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1C2027).withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: RadialGradient(
                      center: const Alignment(1.0, -1.0),
                      radius: 1.2,
                      colors: [
                        const Color(0xFF00CCFF).withValues(alpha: 0.22),
                        const Color(0xFF00CCFF).withValues(alpha: 0.05),
                        Colors.transparent,
                      ],
                      stops: const [0.0, 0.45, 0.75],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 16,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'TAILSCALE NODE',
                                style: GoogleFonts.jetBrainsMono(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFF8E8E93),
                                  letterSpacing: 1.2,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                _tailscaleNodeState == NodeState.running
                                    ? (_tailscaleStatus?.ipv4 ?? '—')
                                    : 'Node Inactive',
                                style: GoogleFonts.jetBrainsMono(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                  letterSpacing: -0.4,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _tailscaleNodeState == NodeState.running
                                    ? (_tailscaleStatus?.magicDNSSuffix ??
                                          'Resolving DNS…')
                                    : 'Tap to connect WireGuard mesh',
                                style: GoogleFonts.jetBrainsMono(
                                  fontSize: 11,
                                  color: const Color(0xFFAAC7FF),
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xFF262A32),
                            border: Border.all(
                              color: const Color(
                                0xFF00CCFF,
                              ).withValues(alpha: 0.3),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(
                                  0xFF00CCFF,
                                ).withValues(alpha: 0.15),
                                blurRadius: 15,
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.lan_rounded,
                            color: Color(0xFF00CCFF),
                            size: 20,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'NODE ID',
                                style: GoogleFonts.jetBrainsMono(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: const Color(0xFF8E8E93),
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                _tailscaleNodeState == NodeState.running
                                    ? (_tailscaleStatus?.stableNodeId ??
                                          'Unassigned')
                                    : 'Unassigned',
                                style: GoogleFonts.jetBrainsMono(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color:
                                      _tailscaleNodeState == NodeState.running
                                      ? Colors.white
                                      : const Color(0xFF8E8E93),
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'STATUS',
                                style: GoogleFonts.jetBrainsMono(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: const Color(0xFF8E8E93),
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                _tailscaleNodeState == NodeState.running
                                    ? 'Online now'
                                    : (_tailscaleNodeState == NodeState.starting
                                          ? 'Connecting…'
                                          : 'Offline'),
                                style: GoogleFonts.jetBrainsMono(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color:
                                      _tailscaleNodeState == NodeState.running
                                      ? const Color(0xFF32D74B)
                                      : const Color(0xFF8E8E93),
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSshMeshHeroCard(List<ConnectionProfile> profiles) {
    final profileCount = profiles.length;
    final primaryProfile = profiles.isNotEmpty ? profiles.first : null;
    final keyService = ref.read(keyServiceProvider);
    // Derive auth key types in use across all profiles
    final keyTypes = <String>{};
    for (final p in profiles) {
      if (p.keyId != null) {
        final key = keyService.getKey(p.keyId!);
        if (key != null) keyTypes.add(key.keyTypeLabel);
      }
      if (p.authType == AuthType.password ||
          p.authType == AuthType.passwordAndPublicKey) {
        keyTypes.add('Password');
      }
    }
    final authSummary = keyTypes.isEmpty
        ? 'None configured'
        : keyTypes.join(' / ');
    final primaryPort = primaryProfile?.port ?? 22;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GestureDetector(
        onTap: () => context.push('/profile/new'),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1C2027).withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: RadialGradient(
                      center: const Alignment(1.0, -1.0),
                      radius: 1.2,
                      colors: [
                        const Color(0xFFBF5AF2).withValues(alpha: 0.22),
                        const Color(0xFFBF5AF2).withValues(alpha: 0.05),
                        Colors.transparent,
                      ],
                      stops: const [0.0, 0.45, 0.75],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 16,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'PRIMARY SSH MESH',
                                style: GoogleFonts.jetBrainsMono(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFF8E8E93),
                                  letterSpacing: 1.2,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                primaryProfile?.host ?? 'No servers yet',
                                style: GoogleFonts.jetBrainsMono(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                  letterSpacing: -0.4,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '$profileCount Active Server Node${profileCount == 1 ? '' : 's'}',
                                style: GoogleFonts.jetBrainsMono(
                                  fontSize: 11,
                                  color: const Color(0xFFC2C1FF),
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xFF262A32),
                            border: Border.all(
                              color: const Color(
                                0xFFBF5AF2,
                              ).withValues(alpha: 0.4),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(
                                  0xFFBF5AF2,
                                ).withValues(alpha: 0.2),
                                blurRadius: 15,
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.terminal_rounded,
                            color: Color(0xFFBF5AF2),
                            size: 20,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'AUTH KEY',
                                style: GoogleFonts.jetBrainsMono(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: const Color(0xFF8E8E93),
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                authSummary,
                                style: GoogleFonts.jetBrainsMono(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'SSH PORT',
                                style: GoogleFonts.jetBrainsMono(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: const Color(0xFF8E8E93),
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                '$primaryPort (SSH)',
                                style: GoogleFonts.jetBrainsMono(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEnvFilterChip(String label, Color textColor, Color dotColor) {
    final isSelected = _selectedEnvFilter == label;
    return GestureDetector(
      onTap: () => setState(() => _selectedEnvFilter = label),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF262A32)
              : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF00CCFF).withValues(alpha: 0.4)
                : Colors.white.withValues(alpha: 0.05),
            width: isSelected ? 1.0 : 0.5,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: const Color(0xFF00CCFF).withValues(alpha: 0.15),
                    blurRadius: 10,
                  ),
                ]
              : [],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: dotColor,
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: dotColor.withValues(alpha: 0.6),
                          blurRadius: 6,
                        ),
                      ]
                    : [],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: GoogleFonts.jetBrainsMono(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? Colors.white : textColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 64),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
                icon,
                size: 56,
                color: AppConstants.primaryGreen.withValues(alpha: 0.20),
              )
              .animate(onPlay: (c) => c.repeat())
              .shimmer(
                duration: 2500.ms,
                color: AppConstants.primaryGreen.withValues(alpha: 0.12),
              )
              .scale(
                begin: const Offset(1, 1),
                end: const Offset(1.02, 1.02),
                duration: 2500.ms,
                curve: Curves.easeInOutSine,
              ),
          const SizedBox(height: 20),
          Text(
            title,
            style: GoogleFonts.jetBrainsMono(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: Colors.white.withValues(alpha: 0.55),
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: GoogleFonts.jetBrainsMono(
              fontSize: 12,
              color: Colors.white.withValues(alpha: 0.30),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  void _connectTo(ConnectionProfile profile) {
    // Write the request so the persistent terminal picks it up.
    ref.read(pendingTerminalTabProvider.notifier).state = TerminalTabRequest(
      profileId: profile.id,
    );
    context.go('/terminal');
  }

  void _editProfile(ConnectionProfile profile) {
    context.push('/profile/${profile.id}');
  }
}
