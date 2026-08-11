import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:xterm/xterm.dart';

import '../models/connection_profile.dart';
import '../models/terminal_tab.dart';
import '../services/key_service.dart';
import '../services/pending_quick_command_provider.dart';
import '../services/profile_storage_service.dart';
import '../services/ssh_service.dart';
import '../services/tab_manager.dart';
import '../services/tailscale_provider.dart';
import '../services/tailscale_ssh_socket.dart';
import '../services/terminal_tab_request_provider.dart';
import '../utils/constants.dart';
import '../utils/app_version.dart';
import '../utils/terminal_settings_provider.dart';

/// Full-screen multi-tab terminal with persistent SSH sessions.
///
/// Tabs are identified by a unique [tabId] (e.g. `tab_1`, `tab_2`). Each tab
/// wraps its own [Terminal], [TerminalController], and SSH session. The screen
/// stays alive across navigation via [StatefulShellRoute.indexedStack] — going
/// back to the home screen hides it, but tabs and connections survive.
class TabbedTerminalScreen extends ConsumerStatefulWidget {
  const TabbedTerminalScreen({super.key});

  @override
  ConsumerState<TabbedTerminalScreen> createState() =>
      _TabbedTerminalScreenState();
}

// ── Internal per-tab data ─────────────────────────────────────────────────────

/// Runtime state for a single terminal tab — kept in the widget's local state,
/// not serialized (tabs are ephemeral, tied to the SSH session lifecycle).
class _TabData {
  final String tabId;
  final String profileId;
  final String label;
  final Terminal terminal;
  final TerminalController controller;

  String? initialCommand;
  bool isConnected = false;
  bool isConnecting = false;
  bool shellStarted = false;
  String? error;
  double fontSize;
  bool userZoomed = false;
  Size lastTerminalSize = Size.zero;
  StreamSubscription? stdoutSub;
  final BytesBuilder utf8Buffer = BytesBuilder();

  _TabData({
    required this.tabId,
    required this.profileId,
    required this.label,
    required this.terminal,
    required this.controller,
    required this.fontSize,
    this.initialCommand,
  });

  bool get disposed => stdoutSub == null && !isConnecting && !isConnected;
}

// ── Screen state ──────────────────────────────────────────────────────────────

class _TabbedTerminalScreenState extends ConsumerState<TabbedTerminalScreen>
    with WidgetsBindingObserver {
  final Map<String, _TabData> _tabs = {};
  final List<String> _tabOrder = [];
  int _activeTabIndex = 0;
  int _tabCounter = 0;

  /// Cached reference to TabManager notifier — avoids [ref.read] in dispose
  /// where the element may already be unmounted.
  late final TabManager _tabManager;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tabManager = ref.read(tabManagerProvider.notifier);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final tab in _tabs.values) {
      tab.stdoutSub?.cancel();
      if (tab.tabId.isNotEmpty) {
        _tabManager.removeTab(tab.tabId);
      }
    }
    _tabs.clear();
    _tabOrder.clear();
    super.dispose();
  }

  // ── Tab creation ──────────────────────────────────────────────────────────

  /// Creates a new tab and immediately schedules the SSH connection.
  void _createTabNow(String profileId, {String? initialCommand}) {
    final storage = ref.read(profileStorageProvider);
    final profile = storage.getProfile(profileId);
    if (profile == null) return;

    _tabCounter++;
    final tabId = 'tab_$_tabCounter';
    final scrollback = ref.read(terminalScrollbackProvider);
    final fontSize = ref.read(terminalFontSizeProvider);

    final terminal = Terminal(maxLines: scrollback);
    final controller = TerminalController();
    final tabData = _TabData(
      tabId: tabId,
      profileId: profileId,
      label: profile.shortLabel,
      terminal: terminal,
      controller: controller,
      fontSize: fontSize,
      initialCommand: initialCommand,
    );

    // Register with TabManager.
    _tabManager.addTab(TerminalTab(
      tabId: tabId,
      profileId: profileId,
      label: profile.shortLabel,
      isConnecting: true,
    ));

    // Wire resize handler for this tab's terminal.
    terminal.onResize = (width, height, pixelWidth, pixelHeight) {
      if (tabData.shellStarted) {
        if (width > 0 && height > 0) {
          final sshService = ref.read(sshServiceProvider(profileId));
          sshService.resizeShell(
            cols: width,
            rows: height,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
          );
        }
      }
    };

    // Wire output handler.
    terminal.onOutput = (String data) {
      final sshService = ref.read(sshServiceProvider(profileId));
      sshService.writeStdin(Uint8List.fromList(utf8.encode(data)));
    };

    _tabs[tabId] = tabData;
    _tabOrder.add(tabId);
    _activeTabIndex = _tabOrder.length - 1;

    setState(() {});

    // Connect SSH on next frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _connectTab(tabData);
    });
  }

  // ── SSH connection ───────────────────────────────────────────────────────

  Future<void> _connectTab(_TabData tab) async {
    tab.isConnecting = true;
    setState(() {});

    final version = await AppVersion.get();
    tab.terminal.write(
      '\x1b[1;32m⬡ OPA — OpenSSH Pocket Agent v$version\x1b[0m\r\n\r\n'
      '\x1b[33mConnecting...\x1b[0m\r\n',
    );

    try {
      final storage = ref.read(profileStorageProvider);
      final profile = storage.getProfile(tab.profileId);
      if (profile == null) {
        throw StateError('Profile not found: ${tab.profileId}');
      }

      final sshService = ref.read(sshServiceProvider(tab.profileId));

      TailscaleSSHSocket? sock;
      if (profile.connectionMethod == ConnectionMethod.tailscale) {
        final ts = ref.read(tailscaleServiceProvider);
        final conn = await ts.dial(
          profile.host,
          profile.port,
          timeout: const Duration(seconds: 10),
        );
        sock = TailscaleSSHSocket(conn);
      }

      String? privateKey;
      if (profile.keyId != null) {
        privateKey =
            await ref.read(keyServiceProvider).getPrivateKey(profile.keyId!);
      }

      final securePassword =
          await ref.read(profileStorageProvider).getPassword(profile.id);
      final effectivePassword = securePassword ?? profile.password;

      await sshService.connect(
        profile: profile,
        privateKey: privateKey,
        password: effectivePassword,
        keepalive: Duration(seconds: ref.read(terminalKeepaliveProvider)),
        socket: sock,
      );

      tab.terminal
          .write('\x1b[32m✓ Connected to ${profile.displayName}\x1b[0m\r\n\r\n');

      // Auto-start tunnels.
      if (profile.tunnels.isNotEmpty) {
        final tunnelCount =
            await sshService.autoStartTunnels(profile.tunnels);
        if (tunnelCount > 0) {
          tab.terminal.write(
              '\x1b[36m⇌ $tunnelCount tunnel(s) auto-started\x1b[0m\r\n\r\n');
        }
      }

      tab.isConnected = true;
      tab.isConnecting = false;

      _tabManager.updateTab(
        tab.tabId,
        (t) => t.copyWith(isConnected: true, isConnecting: false),
      );

      setState(() {});

      await storage.updateConnectionStatus(tab.profileId, true);
      _maybeStartShell(tab);
    } catch (e) {
      tab.isConnecting = false;
      tab.error = e.toString();
      tab.terminal.write('\r\n\x1b[31m✗ Connection failed:\x1b[0m $e\r\n\r\n');

      _tabManager.updateTab(
        tab.tabId,
        (t) => t.copyWith(isConnecting: false, error: e.toString()),
      );

      final storage = ref.read(profileStorageProvider);
      await storage.updateConnectionStatus(tab.profileId, false);

      setState(() {});
    }
  }

  // ── Shell startup ────────────────────────────────────────────────────────

  void _maybeStartShell(_TabData tab) {
    if (tab.shellStarted || !tab.isConnected) return;

    final cols = tab.terminal.viewWidth;
    final rows = tab.terminal.viewHeight;
    if (cols <= 0 || rows <= 0) return;

    tab.shellStarted = true;
    _startShell(tab, cols, rows);
  }

  Future<void> _startShell(_TabData tab, int cols, int rows) async {
    final sshService = ref.read(sshServiceProvider(tab.profileId));

    final charHeight = tab.fontSize;
    final charWidth = tab.fontSize * AppConstants.charWidthRatio;
    final pixelWidth = (cols * charWidth).round();
    final pixelHeight = (rows * charHeight).round();

    try {
      final session = await sshService.startShell(
        cols: cols,
        rows: rows,
        pixelWidth: pixelWidth,
        pixelHeight: pixelHeight,
      );

      // Send initial command if provided.
      if (tab.initialCommand != null && tab.initialCommand!.isNotEmpty) {
        session.stdinSink
            .add(Uint8List.fromList(utf8.encode(tab.initialCommand!)));
        tab.initialCommand = null;
      }

      tab.stdoutSub = session.stdout.listen(
        (data) {
          if (mounted) _writeBytesToTerminal(tab, data);
        },
        onDone: () {
          if (!mounted) return;
          _flushUtf8Buffer(tab);
          tab.terminal.write('\r\n\x1b[33m⚡ Connection closed\x1b[0m\r\n');
          tab.isConnected = false;
          _tabManager.updateTab(
            tab.tabId,
            (t) => t.copyWith(isConnected: false, shellStarted: false),
          );
          setState(() {});
        },
        onError: (e) {
          if (!mounted) return;
          _flushUtf8Buffer(tab);
          tab.terminal.write('\r\n\x1b[31m✗ Error: $e\x1b[0m\r\n');
          tab.isConnected = false;
          _tabManager.updateTab(
            tab.tabId,
            (t) => t.copyWith(isConnected: false, shellStarted: false),
          );
          setState(() {});
        },
      );

      _tabManager.updateTab(
        tab.tabId,
        (t) => t.copyWith(shellStarted: true),
      );

      setState(() {});
    } catch (e) {
      if (!mounted) return;
      tab.terminal.write('\r\n\x1b[31m✗ Shell error:\x1b[0m $e\r\n');
      tab.isConnected = false;
      _tabManager.updateTab(
        tab.tabId,
        (t) => t.copyWith(isConnected: false),
      );
      setState(() {});
    }
  }

  // ── Output handling ──────────────────────────────────────────────────────

  void _writeBytesToTerminal(_TabData tab, Uint8List data) {
    tab.utf8Buffer.add(data);
    final bytes = tab.utf8Buffer.takeBytes();
    final decoded = utf8.decode(bytes, allowMalformed: true);
    tab.terminal.write(decoded);
  }

  void _flushUtf8Buffer(_TabData tab) {
    if (tab.utf8Buffer.isEmpty) return;
    final bytes = tab.utf8Buffer.takeBytes();
    tab.terminal.write(utf8.decode(bytes, allowMalformed: true));
  }

  // ── Tab management ──────────────────────────────────────────────────────

  _TabData? get activeTab {
    if (_tabOrder.isEmpty) return null;
    if (_activeTabIndex >= _tabOrder.length) {
      _activeTabIndex = _tabOrder.length - 1;
    }
    return _tabs[_tabOrder[_activeTabIndex]];
  }

  void _switchTab(int index) {
    if (index < 0 || index >= _tabOrder.length) return;
    setState(() => _activeTabIndex = index);
  }

  void _closeTab(String tabId) {
    final tab = _tabs[tabId];
    if (tab == null) return;

    // Cancel SSH session.
    tab.stdoutSub?.cancel();
    tab.stdoutSub = null;
    final sshService = ref.read(sshServiceProvider(tab.profileId));
    sshService.disconnect();

    // Remove from tracking.
    _tabManager.removeTab(tabId);
    _tabs.remove(tabId);
    final idx = _tabOrder.indexOf(tabId);
    if (idx >= 0) _tabOrder.removeAt(idx);

    // Adjust active tab index.
    if (_tabOrder.isEmpty) {
      _activeTabIndex = 0;
    } else if (_activeTabIndex >= _tabOrder.length) {
      _activeTabIndex = _tabOrder.length - 1;
    }

    setState(() {});
  }

  // ── Terminal controls ───────────────────────────────────────────────────

  void _sendCtrlC() {
    activeTab?.terminal.textInput(String.fromCharCode(3));
  }

  // ── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Listen for pending tab requests from Home, QCMD, SFTP, etc.
    ref.listen(pendingTerminalTabProvider, (prev, TerminalTabRequest? next) {
      if (next == null || identical(next, prev)) return;
      if (!mounted) return;
      ref.read(pendingTerminalTabProvider.notifier).state = null;
      _createTabNow(next.profileId, initialCommand: next.initialCommand);
    });

    // Listen for pending quick commands targeting existing tabs.
    ref.listen(pendingQuickCommandProvider, (prev, PendingTabCommand? next) {
      if (next == null || identical(next, prev)) return;
      if (!mounted) return;
      final tab = _tabs[next.tabId];
      if (tab == null || tab.disposed) return;
      if (tab.shellStarted) {
        tab.terminal.textInput(next.command);
      } else {
        tab.initialCommand = next.command;
      }
      // Defer clear to next frame — ref is dead during unmount.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ref.read(pendingQuickCommandProvider.notifier).state = null;
        }
      });
    });

    final mq = MediaQuery.of(context);
    final size = mq.size;
    final isLandscape = size.width > size.height;
    final showKeyboardBar = mq.size.shortestSide < 600;

    // Wire terminal resize for the active tab.
    final tab = activeTab;

    // If a tab hasn't started its shell yet and it's connected, try now.
    if (tab != null && tab.isConnected && !tab.shellStarted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _maybeStartShell(tab);
      });
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && mounted) {
          context.go('/');
        }
      },
      child: Scaffold(
        backgroundColor: AppConstants.backgroundDark,
        body: Column(
          children: [
            // ── Unified Single Header Bar (36px, OLED Glass, SafeArea protected) ──
            SafeArea(
              bottom: false,
              child: _buildUnifiedHeader(tab, isLandscape),
            ),

            // ── Terminal area or empty state ──
            Expanded(
              child: _tabOrder.isEmpty
                  ? _buildEmptyState()
                  : _buildTerminalBody(tab, isLandscape, showKeyboardBar),
            ),
          ],
        ),
      ),
    );
  }

  // ── Unified Single Header Bar (Apple TUI 2.0) ───────────────────────────

  Widget _buildUnifiedHeader(_TabData? currentTab, bool isLandscape) {
    if (_tabOrder.isEmpty) return const SizedBox.shrink();
    final h = isLandscape ? 32.0 : 36.0;

    return Container(
      height: h,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: AppConstants.surface0.withValues(alpha: 0.95),
        border: Border(
          bottom: BorderSide(
            color: Colors.white.withValues(alpha: 0.08),
            width: 0.8,
          ),
        ),
      ),
      child: Row(
        children: [
          // Left: Back button to return to home screen
          GestureDetector(
            onTap: () => context.go('/'),
            child: Container(
              width: 28,
              height: 28,
              margin: const EdgeInsets.only(right: 6),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.arrow_back_rounded,
                size: 15,
                color: Colors.white.withValues(alpha: 0.7),
              ),
            ),
          ),

          // Middle: Scrollable list of compact tab chips
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              physics: const ClampingScrollPhysics(),
              itemCount: _tabOrder.length,
              itemBuilder: (context, index) {
                final tabId = _tabOrder[index];
                final tab = _tabs[tabId];
                if (tab == null) return const SizedBox.shrink();
                final isActive = index == _activeTabIndex;
                return _buildTabPill(tab, isActive, index, h - 6);
              },
            ),
          ),

          const SizedBox(width: 4),

          // New Tab (+) button
          _buildNewTabButton(h - 6),

          const SizedBox(width: 6),

          // Terminal Grid Dimensions (e.g. 76x66)
          if (currentTab != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '${currentTab.terminal.viewWidth}×${currentTab.terminal.viewHeight}',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 10,
                  color: Colors.white.withValues(alpha: 0.45),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Compact single-line tab chip
  Widget _buildTabPill(_TabData tab, bool isActive, int index, double h) {
    final stateColor = tab.isConnected
        ? AppConstants.primaryGreen
        : tab.isConnecting
            ? const Color(0xFFFFAB40)
            : Colors.redAccent;

    return GestureDetector(
      onTap: () => _switchTab(index),
      child: Container(
        height: h,
        margin: const EdgeInsets.only(right: 4),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: isActive
              ? AppConstants.surface1
              : AppConstants.surface0.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isActive
                ? AppConstants.accentBlue.withValues(alpha: 0.5)
                : Colors.white.withValues(alpha: 0.05),
            width: isActive ? 1.0 : 0.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Glowing status dot
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: stateColor,
                boxShadow: isActive
                    ? [
                        BoxShadow(
                          color: stateColor.withValues(alpha: 0.6),
                          blurRadius: 3,
                        ),
                      ]
                    : null,
              ),
            ),
            const SizedBox(width: 6),
            // Tab text label
            Text(
              tab.label,
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                color: isActive
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(width: 4),
            // Close (×) button
            GestureDetector(
              onTap: () => _closeTab(tab.tabId),
              child: Icon(
                Icons.close_rounded,
                size: 13,
                color: Colors.white.withValues(alpha: isActive ? 0.6 : 0.3),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// "+" button that hints users to tap a connection on the home screen.
  Widget _buildNewTabButton(double h) {
    return GestureDetector(
      onTap: () {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Tap a connection on Home to open a new tab',
              style: GoogleFonts.inter(fontSize: 13),
            ),
          ),
        );
      },
      child: Container(
        width: 32,
        height: h,
        margin: const EdgeInsets.only(right: 2),
        alignment: Alignment.center,
        child: Icon(
          Icons.add_rounded,
          size: 18,
          color: Colors.white.withValues(alpha: 0.4),
        ),
      ),
    );
  }

  // ── Terminal body ───────────────────────────────────────────────────────

  Widget _buildTerminalBody(
      _TabData? tab, bool isLandscape, bool showKeyboardBar) {
    if (tab == null) return _buildEmptyState();

    final mq = MediaQuery.of(context);
    final size = mq.size;
    final areaWidth = size.width;
    final areaHeight = size.height;

    // Auto-fit font size.
    if (!tab.userZoomed) {
      final sizeChanged =
          (tab.lastTerminalSize.width - areaWidth).abs() > 4 ||
              (tab.lastTerminalSize.height - areaHeight).abs() > 4;
      if (sizeChanged || tab.lastTerminalSize == Size.zero) {
        final targetCols = isLandscape
            ? AppConstants.targetMinColsLandscape
            : AppConstants.targetMinColsPortrait;
        final optimal = _computeOptimalFontSize(areaWidth, targetCols);
        if ((optimal - tab.fontSize).abs() > 0.5) {
          tab.fontSize = optimal;
        }
        tab.lastTerminalSize = Size(areaWidth, areaHeight);
      }
    }

    return Column(
      children: [
        // Terminal view
        Expanded(
          child: GestureDetector(
            onScaleUpdate: (details) {
              if (details.scale != 1.0) {
                setState(() {
                  tab.userZoomed = true;
                  tab.fontSize = (tab.fontSize * details.scale).clamp(
                    AppConstants.minFontSize,
                    AppConstants.maxFontSize,
                  );
                });
              }
            },
            child: TerminalView(
              tab.terminal,
              controller: tab.controller,
              autofocus: true,
              backgroundOpacity: 1.0,
              textStyle: TerminalStyle(
                fontFamily: 'JetBrainsMono',
                fontSize: tab.fontSize,
              ),
              cursorType: TerminalCursorType.block,
              padding: EdgeInsets.symmetric(
                horizontal: 8,
                vertical: isLandscape ? 4 : 8,
              ),
              theme: _terminalTheme,
            ),
          ),
        ),
        if (showKeyboardBar) _buildMobileKeyboardBar(tab, isLandscape),
      ],
    );
  }

  double _computeOptimalFontSize(double areaWidth, int targetCols) {
    final computed =
        areaWidth / (targetCols * AppConstants.charWidthRatio);
    return computed.clamp(AppConstants.minFontSize, AppConstants.maxFontSize);
  }

  // ── Empty state ─────────────────────────────────────────────────────────

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.terminal_rounded,
              size: 64,
              color: AppConstants.primaryGreen.withValues(alpha: 0.15),
            ),
            const SizedBox(height: 20),
            Text(
              'No terminal tabs open',
              style: GoogleFonts.inter(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.white.withValues(alpha: 0.45),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Tap a connection on the home screen to open a new tab',
              style: GoogleFonts.inter(
                fontSize: 14,
                color: Colors.white.withValues(alpha: 0.25),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => context.go('/'),
              icon: const Icon(Icons.arrow_back_rounded, size: 18),
              label: Text('Back to connections',
                  style: GoogleFonts.inter()),
            ),
          ],
        ),
      ),
    );
  }

  // ── Mobile keyboard bar ────────────────────────────────────────────────

  Widget _buildMobileKeyboardBar(_TabData tab, bool isLandscape) {
    final barHeight = isLandscape
        ? AppConstants.keyboardBarHeightLandscape
        : AppConstants.keyboardBarHeightPortrait;

    final keys = isLandscape
        ? [
            _KeyDef('TAB', () => tab.terminal.keyInput(TerminalKey.tab)),
            _KeyDef('ESC', () => tab.terminal.keyInput(TerminalKey.escape)),
            _KeyDef('↑', () => tab.terminal.keyInput(TerminalKey.arrowUp)),
            _KeyDef('↓', () => tab.terminal.keyInput(TerminalKey.arrowDown)),
            _KeyDef('←', () => tab.terminal.keyInput(TerminalKey.arrowLeft)),
            _KeyDef('→', () => tab.terminal.keyInput(TerminalKey.arrowRight)),
            _KeyDef('CTRL', _sendCtrlC, color: const Color(0xFFFF5252)),
          ]
        : [
            _KeyDef('TAB', () => tab.terminal.keyInput(TerminalKey.tab)),
            _KeyDef('ESC', () => tab.terminal.keyInput(TerminalKey.escape)),
            _KeyDef('↑', () => tab.terminal.keyInput(TerminalKey.arrowUp)),
            _KeyDef('↓', () => tab.terminal.keyInput(TerminalKey.arrowDown)),
            _KeyDef('←', () => tab.terminal.keyInput(TerminalKey.arrowLeft)),
            _KeyDef('→', () => tab.terminal.keyInput(TerminalKey.arrowRight)),
            _KeyDef('CTRL', _sendCtrlC, color: const Color(0xFFFF5252)),
            _KeyDef('/', () => tab.terminal.textInput('/')),
            _KeyDef('|', () => tab.terminal.textInput('|')),
            _KeyDef('-', () => tab.terminal.textInput('-')),
          ];

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
        child: Container(
          height: barHeight,
          color: AppConstants.surfaceDark.withValues(alpha: 0.8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: keys
                .map((k) => _SpecialKeyButton(
                      label: k.label,
                      onPressed: k.onPressed,
                      color: k.color,
                    ))
                .toList(),
          ),
        ),
      ),
    );
  }

  // ── Terminal theme ─────────────────────────────────────────────────────

  static const TerminalTheme _terminalTheme = TerminalTheme(
    cursor: AppConstants.primaryGreen,
    selection: Color(0x7F00E676),
    foreground: Colors.white,
    background: AppConstants.backgroundDark,
    black: Color(0xFF000000),
    red: Color(0xFFFF5252),
    green: AppConstants.primaryGreen,
    yellow: Color(0xFFFFAB40),
    blue: Color(0xFF448AFF),
    magenta: Color(0xFFE040FB),
    cyan: Color(0xFF18FFFF),
    white: Color(0xFFFFFFFF),
    brightBlack: Color(0xFF546E7A),
    brightRed: Color(0xFFFF8A80),
    brightGreen: Color(0xFF69F0AE),
    brightYellow: Color(0xFFFFD740),
    brightBlue: Color(0xFF82B1FF),
    brightMagenta: Color(0xFFFF80AB),
    brightCyan: Color(0xFF84FFFF),
    brightWhite: Color(0xFFFFFFFF),
    searchHitBackground: Color(0x7FFFFFFF),
    searchHitBackgroundCurrent: Color(0x7F00E676),
    searchHitForeground: Color(0xFF000000),
  );
}

// ── Helper widgets ────────────────────────────────────────────────────────────

class _KeyDef {
  const _KeyDef(this.label, this.onPressed, {this.color});
  final String label;
  final VoidCallback onPressed;
  final Color? color;
}

class _SpecialKeyButton extends StatelessWidget {
  const _SpecialKeyButton({
    required this.label,
    required this.onPressed,
    this.color,
  });

  final String label;
  final VoidCallback onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            border: Border.all(
              color: (color ?? Colors.white).withValues(alpha: 0.15),
            ),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: color ?? Colors.white.withValues(alpha: 0.7),
            ),
          ),
        ),
      ),
    );
  }
}
