import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

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
import '../services/quick_command_layout_service.dart';
import '../services/ssh_service.dart';
import '../services/tab_manager.dart';
import '../services/tailscale_provider.dart';
import '../services/tailscale_ssh_socket.dart';
import '../services/terminal_tab_request_provider.dart';
import '../utils/constants.dart';
import '../utils/agent_presets.dart';
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
    _tabManager.addTab(
      TerminalTab(
        tabId: tabId,
        profileId: profileId,
        label: profile.shortLabel,
        isConnecting: true,
      ),
    );

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
    if (!mounted || !_tabs.containsKey(tab.tabId)) return;
    tab.isConnecting = true;
    tab.error = null;
    setState(() {});

    final version = await AppVersion.get();
    if (!mounted || !_tabs.containsKey(tab.tabId)) return;
    tab.terminal.write(
      '\x1b[1;32m⬡ Tether — Pocket SSH & Mesh Terminal v$version\x1b[0m\r\n\r\n'
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
        privateKey = await ref
            .read(keyServiceProvider)
            .getPrivateKey(profile.keyId!);
      }

      final securePassword = await ref
          .read(profileStorageProvider)
          .getPassword(profile.id);
      final effectivePassword = securePassword ?? profile.password;

      await sshService.connect(
        profile: profile,
        privateKey: privateKey,
        password: effectivePassword,
        keepalive: Duration(seconds: ref.read(terminalKeepaliveProvider)),
        socket: sock,
      );
      if (!mounted || !_tabs.containsKey(tab.tabId)) return;

      tab.terminal.write(
        '\x1b[32m✓ Connected to ${profile.displayName}\x1b[0m\r\n\r\n',
      );

      // Auto-start tunnels.
      if (profile.tunnels.isNotEmpty) {
        final tunnelCount = await sshService.autoStartTunnels(profile.tunnels);
        if (!mounted || !_tabs.containsKey(tab.tabId)) return;
        if (tunnelCount > 0) {
          tab.terminal.write(
            '\x1b[36m⇌ $tunnelCount tunnel(s) auto-started\x1b[0m\r\n\r\n',
          );
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
      if (!mounted || !_tabs.containsKey(tab.tabId)) return;
      _maybeStartShell(tab);
    } catch (e) {
      if (!mounted || !_tabs.containsKey(tab.tabId)) return;
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
        session.stdinSink.add(
          Uint8List.fromList(utf8.encode(tab.initialCommand!)),
        );
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

      _tabManager.updateTab(tab.tabId, (t) => t.copyWith(shellStarted: true));

      setState(() {});
    } catch (e) {
      if (!mounted) return;
      tab.terminal.write('\r\n\x1b[31m✗ Shell error:\x1b[0m $e\r\n');
      tab.isConnected = false;
      _tabManager.updateTab(tab.tabId, (t) => t.copyWith(isConnected: false));
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
    unawaited(sshService.disconnect());

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

  /// Retries a failed connection without forcing the user to close the tab.
  Future<void> _retryTab(_TabData tab) async {
    if (!mounted || !_tabs.containsKey(tab.tabId) || tab.isConnecting) return;

    tab.stdoutSub?.cancel();
    tab.stdoutSub = null;
    tab.isConnected = false;
    tab.shellStarted = false;
    tab.error = null;
    tab.terminal.write('\r\n\x1b[33mRetrying connection...\x1b[0m\r\n');
    setState(() {});

    try {
      await ref.read(sshServiceProvider(tab.profileId)).disconnect();
    } catch (_) {
      // A failed session may already be disconnected; continue with retry.
    }
    await _connectTab(tab);
  }

  // ── Terminal controls ───────────────────────────────────────────────────

  void _sendCtrlC() {
    activeTab?.terminal.textInput(String.fromCharCode(3));
  }

  // ── Build ───────────────────────────────────────────────────────────────

  void _showSessionInfo(_TabData tab) {
    final profile = ref.read(profileStorageProvider).getProfile(tab.profileId);
    if (profile == null) return;

    final status = tab.isConnected
        ? 'Connected'
        : tab.isConnecting
        ? 'Connecting'
        : 'Offline';
    final statusColor = tab.isConnected
        ? AppConstants.primaryGreen
        : tab.isConnecting
        ? AppConstants.accentAmber
        : Colors.redAccent;

    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      useSafeArea: true,
      backgroundColor: AppConstants.surface2,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'SESSION DETAILS',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.0,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${profile.shortLabel}  •  ${profile.username}@${profile.host}:${profile.port}',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 10,
                  color: Colors.white.withValues(alpha: 0.45),
                ),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.07),
                  ),
                ),
                child: Column(
                  children: [
                    _sessionDetailRow('STATUS', status, statusColor),
                    _sessionDetailRow(
                      'AUTH',
                      profile.authType == AuthType.publicKey
                          ? 'PUBLIC KEY'
                          : 'PASSWORD',
                      Colors.white.withValues(alpha: 0.75),
                    ),
                    _sessionDetailRow(
                      'SHELL',
                      tab.shellStarted
                          ? '${tab.terminal.viewWidth} x ${tab.terminal.viewHeight} PTY'
                          : 'NOT STARTED',
                      Colors.white.withValues(alpha: 0.75),
                    ),
                    _sessionDetailRow(
                      'TUNNELS',
                      '${profile.tunnels.length} CONFIGURED',
                      Colors.white.withValues(alpha: 0.75),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(sheetContext);
                        context.go('/sftp/${profile.id}');
                      },
                      icon: const Icon(Icons.folder_open_rounded, size: 16),
                      label: const Text('SFTP'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(sheetContext);
                        context.go('/tunnel/${profile.id}');
                      },
                      icon: const Icon(Icons.swap_horiz_rounded, size: 16),
                      label: const Text('TUNNELS'),
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

  Widget _sessionDetailRow(String label, String value, Color valueColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Text(
            label,
            style: GoogleFonts.jetBrainsMono(
              fontSize: 9,
              fontWeight: FontWeight.w800,
              color: Colors.white.withValues(alpha: 0.35),
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: GoogleFonts.jetBrainsMono(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Listen for pending tab requests from Home, QCMD, SFTP, etc.
    ref.listen(pendingTerminalTabProvider, (prev, TerminalTabRequest? next) {
      if (next == null || identical(next, prev)) return;
      if (!mounted) return;
      ref.read(pendingTerminalTabProvider.notifier).state = null;
      _createTabNow(next.profileId, initialCommand: next.initialCommand);
    });

    // Check for pending tab request created before ref.listen was mounted (e.g. fresh launch)
    final initialPendingTab = ref.read(pendingTerminalTabProvider);
    if (initialPendingTab != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            ref.read(pendingTerminalTabProvider) == initialPendingTab) {
          ref.read(pendingTerminalTabProvider.notifier).state = null;
          _createTabNow(
            initialPendingTab.profileId,
            initialCommand: initialPendingTab.initialCommand,
          );
        }
      });
    }

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

    // Check for pending quick command created before ref.listen was mounted
    final initialPendingCmd = ref.read(pendingQuickCommandProvider);
    if (initialPendingCmd != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            ref.read(pendingQuickCommandProvider) == initialPendingCmd) {
          ref.read(pendingQuickCommandProvider.notifier).state = null;
          final tab = _tabs[initialPendingCmd.tabId];
          if (tab != null && !tab.disposed) {
            if (tab.shellStarted) {
              tab.terminal.textInput(initialPendingCmd.command);
            } else {
              tab.initialCommand = initialPendingCmd.command;
            }
          }
        }
      });
    }

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

            if (tab != null) _buildSessionInfoBar(tab),

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
    final h = isLandscape ? 32.0 : 36.0;

    if (_tabOrder.isEmpty) {
      return Container(
        height: h + 8,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
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
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppConstants.accentBlue.withValues(alpha: 0.45),
                ),
              ),
              child: const Icon(
                Icons.code_rounded,
                size: 12,
                color: AppConstants.accentBlue,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'TERMINAL',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.4,
                color: Colors.white,
              ),
            ),
            const Spacer(),
            _buildNewTabButton(h),
          ],
        ),
      );
    }

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

          // Quick Commands (⚡) button
          if (currentTab != null)
            GestureDetector(
              onTap: () => _showQuickCommandModalSheet(currentTab),
              child: Container(
                width: 28,
                height: h - 6,
                margin: const EdgeInsets.only(right: 4),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppConstants.accentAmber.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AppConstants.accentAmber.withValues(alpha: 0.25),
                  ),
                ),
                child: const Icon(
                  Icons.bolt_rounded,
                  size: 16,
                  color: AppConstants.accentAmber,
                ),
              ),
            ),

          // New Tab (+) button
          _buildNewTabButton(h - 6),

          const SizedBox(width: 4),

          // Active-session switcher. This keeps session selection available
          // without leaving the terminal or confusing it with profile setup.
          GestureDetector(
            onTap: _showActiveSessionSheet,
            child: Container(
              width: 28,
              height: h - 6,
              margin: const EdgeInsets.only(right: 4),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: Icon(
                Icons.view_agenda_outlined,
                size: 15,
                color: Colors.white.withValues(alpha: 0.6),
              ),
            ),
          ),

          // Terminal Grid Dimensions (e.g. 76x66)
          if (currentTab != null)
            GestureDetector(
              onTap: () => _showSessionInfo(currentTab),
              child: Container(
                width: 28,
                height: h - 6,
                margin: const EdgeInsets.only(right: 4),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
                child: Icon(
                  Icons.info_outline_rounded,
                  size: 15,
                  color: Colors.white.withValues(alpha: 0.6),
                ),
              ),
            ),

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

  Widget _buildSessionInfoBar(_TabData tab) {
    final profile = ref.read(profileStorageProvider).getProfile(tab.profileId);
    if (profile == null) return const SizedBox.shrink();

    final statusColor = tab.isConnected
        ? AppConstants.primaryGreen
        : tab.isConnecting
        ? AppConstants.accentAmber
        : Colors.redAccent;
    final status = tab.isConnected
        ? 'CONNECTED'
        : tab.isConnecting
        ? 'CONNECTING'
        : 'OFFLINE';

    return GestureDetector(
      onTap: () => _showSessionInfo(tab),
      child: Container(
        margin: const EdgeInsets.fromLTRB(8, 6, 8, 2),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: AppConstants.surface0.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
        child: Row(
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: statusColor,
                boxShadow: [
                  BoxShadow(
                    color: statusColor.withValues(alpha: 0.55),
                    blurRadius: 5,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 7),
            Flexible(
              child: Text(
                profile.shortLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              status,
              style: GoogleFonts.jetBrainsMono(
                fontSize: 9,
                fontWeight: FontWeight.w800,
                color: statusColor,
                letterSpacing: 0.5,
              ),
            ),
            const Spacer(),
            _buildSessionMetric('PORT', '${profile.port}'),
            const SizedBox(width: 10),
            _buildSessionMetric('SHELL', tab.shellStarted ? 'PTY' : '--'),
            const SizedBox(width: 10),
            _buildSessionMetric('TUNN', '${profile.tunnels.length}'),
          ],
        ),
      ),
    );
  }

  Widget _buildSessionMetric(String label, String value) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          label,
          style: GoogleFonts.jetBrainsMono(
            fontSize: 7,
            fontWeight: FontWeight.w800,
            color: Colors.white.withValues(alpha: 0.3),
          ),
        ),
        Text(
          value,
          style: GoogleFonts.jetBrainsMono(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            color: Colors.white.withValues(alpha: 0.68),
          ),
        ),
      ],
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

  /// "+" button that opens a server selection sheet to add a new tab.
  Widget _buildNewTabButton(double h) {
    return GestureDetector(
      onTap: _showServerPickerModalSheet,
      child: Container(
        width: 28,
        height: h,
        margin: const EdgeInsets.only(right: 2),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          Icons.add_rounded,
          size: 16,
          color: Colors.white.withValues(alpha: 0.7),
        ),
      ),
    );
  }

  /// Shows all live terminal tabs and lets the user switch without returning
  /// to Home or reopening a profile.
  void _showActiveSessionSheet() {
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      useSafeArea: true,
      backgroundColor: AppConstants.surface2,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.7,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ACTIVE TERMINAL SESSIONS',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.9,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Select a tab to make it active.',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: Colors.white.withValues(alpha: 0.45),
                  ),
                ),
                const SizedBox(height: 14),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: _tabOrder.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final tab = _tabs[_tabOrder[index]];
                      if (tab == null) return const SizedBox.shrink();
                      final profile = ref
                          .read(profileStorageProvider)
                          .getProfile(tab.profileId);
                      final isActive = index == _activeTabIndex;
                      final statusColor = tab.isConnected
                          ? AppConstants.primaryGreen
                          : tab.isConnecting
                          ? AppConstants.accentAmber
                          : Colors.redAccent;
                      final status = tab.isConnected
                          ? 'CONNECTED'
                          : tab.isConnecting
                          ? 'CONNECTING'
                          : 'OFFLINE';

                      return Material(
                        color: isActive
                            ? AppConstants.accentBlue.withValues(alpha: 0.1)
                            : AppConstants.surface1,
                        borderRadius: BorderRadius.circular(14),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: () {
                            _switchTab(index);
                            Navigator.pop(sheetContext);
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Row(
                              children: [
                                Container(
                                  width: 9,
                                  height: 9,
                                  decoration: BoxDecoration(
                                    color: statusColor,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        tab.label,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: GoogleFonts.jetBrainsMono(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w800,
                                          color: Colors.white,
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        profile == null
                                            ? 'Connection removed'
                                            : '${profile.username}@${profile.host}:${profile.port}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: GoogleFonts.jetBrainsMono(
                                          fontSize: 10,
                                          color: Colors.white.withValues(
                                            alpha: 0.42,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Text(
                                  status,
                                  style: GoogleFonts.jetBrainsMono(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w800,
                                    color: statusColor,
                                  ),
                                ),
                                if (isActive) ...[
                                  const SizedBox(width: 8),
                                  const Icon(
                                    Icons.check_circle_rounded,
                                    size: 16,
                                    color: AppConstants.accentBlue,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Opens an Apple TUI 2.0 bottom sheet showing saved servers to connect in a new tab.
  void _showServerPickerModalSheet() {
    final profiles = ref.read(profileStorageProvider).listProfiles();

    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: AppConstants.surface2,
      barrierColor: Colors.black.withValues(alpha: 0.75),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _ServerPickerSheet(
        profiles: profiles,
        onSelectProfile: (profileId) {
          Navigator.pop(ctx);
          _createTabNow(profileId);
        },
        onAddProfile: () {
          Navigator.pop(ctx);
          context.go('/profile/new');
        },
      ),
    );
  }

  /// Opens an interactive Apple TUI 2.0 bottom sheet showing quick commands and presets.
  void _showQuickCommandModalSheet(_TabData tab) {
    final storage = ref.read(profileStorageProvider);
    final layout = ref.read(quickCommandLayoutProvider);
    final profileCommands = storage.listCommandsForProfile(tab.profileId);
    final allSavedCommands = storage.listCommands();
    final savedCommands = layout.orderItems(
      profileCommands.isNotEmpty ? profileCommands : allSavedCommands,
      (command) => 'saved:${command.id}',
    );

    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: AppConstants.surface2,
      barrierColor: Colors.black.withValues(alpha: 0.75),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _QuickCommandPickerSheet(
        savedCommands: savedCommands,
        onRunCommand: (cmd) {
          Navigator.pop(ctx);
          HapticFeedback.mediumImpact();
          final sshService = ref.read(sshServiceProvider(tab.profileId));
          final normalized = cmd.trim();
          sshService.writeStdin(Uint8List.fromList(utf8.encode('$normalized\r')));
        },
        onPasteCommand: (cmd) {
          Navigator.pop(ctx);
          HapticFeedback.lightImpact();
          final normalized = cmd.trim();
          final sshService = ref.read(sshServiceProvider(tab.profileId));
          sshService.writeStdin(Uint8List.fromList(utf8.encode(normalized)));
        },
        onManageCommands: () {
          Navigator.pop(ctx);
          context.go('/commands');
        },
      ),
    );
  }

  // ── Terminal body ───────────────────────────────────────────────────────

  Widget _buildTerminalBody(
    _TabData? tab,
    bool isLandscape,
    bool showKeyboardBar,
  ) {
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
        if (tab.error != null && !tab.isConnected)
          _buildConnectionErrorBanner(tab),
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

  Widget _buildConnectionErrorBanner(_TabData tab) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.redAccent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.redAccent.withValues(alpha: 0.28)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.cloud_off_rounded,
            size: 17,
            color: Colors.redAccent,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Connection failed. Check the profile and try again.',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: 12,
                color: Colors.white.withValues(alpha: 0.7),
              ),
            ),
          ),
          TextButton(
            onPressed: () => unawaited(_retryTab(tab)),
            style: TextButton.styleFrom(
              foregroundColor: Colors.redAccent,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  double _computeOptimalFontSize(double areaWidth, int targetCols) {
    final computed = areaWidth / (targetCols * AppConstants.charWidthRatio);
    return computed.clamp(AppConstants.minFontSize, AppConstants.maxFontSize);
  }

  Widget _buildEmptyState() {
    final profiles = ref.read(profileStorageProvider).listProfiles();

    if (profiles.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
                child: const Icon(
                  Icons.terminal_rounded,
                  size: 28,
                  color: AppConstants.primaryGreen,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'No Active Sessions',
                style: GoogleFonts.inter(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Add an SSH server or homelab node to start an interactive terminal tab.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: Colors.white.withValues(alpha: 0.45),
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 22),
              ElevatedButton.icon(
                onPressed: () => context.go('/profile/new'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppConstants.primaryGreen,
                  foregroundColor: Colors.black,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 12,
                  ),
                ),
                icon: const Icon(Icons.add_rounded, size: 16),
                label: Text(
                  'Add Server Connection',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'SAVED HOSTS',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.0,
                  color: Colors.white.withValues(alpha: 0.5),
                ),
              ),
              InkWell(
                onTap: () => context.go('/profile/new'),
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.add_rounded,
                        size: 14,
                        color: AppConstants.primaryGreen,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'NEW HOST',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: AppConstants.primaryGreen,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...profiles.map((p) => _buildInlineServerCard(p)),
        ],
      ),
    );
  }

  Widget _buildInlineServerCard(ConnectionProfile profile) {
    final isTailscale = profile.connectionMethod == ConnectionMethod.tailscale;
    final env = profile.effectiveEnvironment.toUpperCase();
    final envColor = env == 'PROD'
        ? const Color(0xFFFF453A)
        : env == 'TAILSCALE'
            ? AppConstants.accentBlue
            : const Color(0xFF30D158);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppConstants.surface0,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _createTabNow(profile.id),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                // Icon
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: (isTailscale ? AppConstants.accentBlue : AppConstants.primaryGreen)
                        .withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    isTailscale ? Icons.hub_rounded : Icons.dns_rounded,
                    size: 18,
                    color: isTailscale ? AppConstants.accentBlue : AppConstants.primaryGreen,
                  ),
                ),
                const SizedBox(width: 12),
                // Host info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            profile.label,
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: envColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: envColor.withValues(alpha: 0.3),
                                width: 0.6,
                              ),
                            ),
                            child: Text(
                              env,
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 8,
                                fontWeight: FontWeight.w800,
                                color: envColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${profile.username}@${profile.host}:${profile.port}  •  ${profile.authType == AuthType.publicKey ? 'Ed25519' : 'Password'}',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 10,
                          color: Colors.white.withValues(alpha: 0.45),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                // Connect Action Capsule
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppConstants.primaryGreen.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: AppConstants.primaryGreen.withValues(alpha: 0.35),
                      width: 0.8,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'CONNECT',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: AppConstants.primaryGreen,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.arrow_forward_rounded,
                        size: 12,
                        color: AppConstants.primaryGreen,
                      ),
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



  // ── Mobile keyboard bar ────────────────────────────────────────────────

  Widget _buildMobileKeyboardBar(_TabData tab, bool isLandscape) {
    final barHeight = isLandscape
        ? AppConstants.keyboardBarHeightLandscape
        : AppConstants.keyboardBarHeightPortrait;

    final mq = MediaQuery.of(context);
    final isKeyboardOpen = mq.viewInsets.bottom > 0;

    final keys = [
      _KeyDef('TAB', () => tab.terminal.keyInput(TerminalKey.tab)),
      _KeyDef('ESC', () => tab.terminal.keyInput(TerminalKey.escape)),
      _KeyDef('CTRL', _sendCtrlC, color: const Color(0xFFFF5252)),
      _KeyDef('↑', () => tab.terminal.keyInput(TerminalKey.arrowUp)),
      _KeyDef('↓', () => tab.terminal.keyInput(TerminalKey.arrowDown)),
      _KeyDef('←', () => tab.terminal.keyInput(TerminalKey.arrowLeft)),
      _KeyDef('→', () => tab.terminal.keyInput(TerminalKey.arrowRight)),
      _KeyDef('/', () => tab.terminal.textInput('/')),
      _KeyDef('|', () => tab.terminal.textInput('|')),
      _KeyDef('-', () => tab.terminal.textInput('-')),
      _KeyDef('~', () => tab.terminal.textInput('~')),
      _KeyDef('\$', () => tab.terminal.textInput('\$')),
      _KeyDef('&', () => tab.terminal.textInput('&')),
      _KeyDef(':', () => tab.terminal.textInput(':')),
      _KeyDef(
        'CLR',
        () {
          final sshService = ref.read(sshServiceProvider(tab.profileId));
          sshService.writeStdin(Uint8List.fromList(utf8.encode('clear\r')));
        },
        color: AppConstants.accentBlue,
      ),
    ];

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0C0F17).withValues(alpha: 0.95),
        border: Border(
          top: BorderSide(
            color: Colors.white.withValues(alpha: 0.08),
            width: 0.8,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        bottom: !isKeyboardOpen,
        child: SizedBox(
          height: barHeight,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: keys.map((k) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: _SpecialKeyButton(
                    label: k.label,
                    onPressed: k.onPressed,
                    color: k.color,
                  ),
                );
              }).toList(),
            ),
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
    final effectiveColor = color ?? Colors.white.withValues(alpha: 0.75);

    return Material(
      color: Colors.white.withValues(alpha: 0.04),
      borderRadius: BorderRadius.circular(7),
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onPressed();
        },
        borderRadius: BorderRadius.circular(7),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 4,
          ),
          decoration: BoxDecoration(
            border: Border.all(
              color: (color != null)
                  ? color!.withValues(alpha: 0.45)
                  : Colors.white.withValues(alpha: 0.12),
              width: 0.8,
            ),
            borderRadius: BorderRadius.circular(7),
          ),
          child: Center(
            child: Text(
              label,
              style: GoogleFonts.jetBrainsMono(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: effectiveColor,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Apple TUI 2.0 Server Picker Modal Sheet ─────────────────────────────────

class _ServerPickerSheet extends StatefulWidget {
  const _ServerPickerSheet({
    required this.profiles,
    required this.onSelectProfile,
    required this.onAddProfile,
  });

  final List<ConnectionProfile> profiles;
  final ValueChanged<String> onSelectProfile;
  final VoidCallback onAddProfile;

  @override
  State<_ServerPickerSheet> createState() => _ServerPickerSheetState();
}

class _ServerPickerSheetState extends State<_ServerPickerSheet> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _selectedEnv = 'ALL';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchCtrl.text.trim().toLowerCase();
    final filtered = widget.profiles.where((p) {
      if (_selectedEnv != 'ALL') {
        if (p.effectiveEnvironment.toUpperCase() != _selectedEnv) return false;
      }
      if (query.isEmpty) return true;
      return p.label.toLowerCase().contains(query) ||
          p.host.toLowerCase().contains(query) ||
          p.username.toLowerCase().contains(query) ||
          p.effectiveEnvironment.toLowerCase().contains(query);
    }).toList();

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with Icon, Title, and "+ NEW HOST" action
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: AppConstants.accentBlue.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: AppConstants.accentBlue.withValues(alpha: 0.4),
                        width: 0.8,
                      ),
                    ),
                    child: const Icon(
                      Icons.code_rounded,
                      size: 16,
                      color: AppConstants.accentBlue,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'NEW TERMINAL TAB',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.0,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        'Select host to mount interactive shell',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          color: Colors.white.withValues(alpha: 0.45),
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  OutlinedButton.icon(
                    onPressed: widget.onAddProfile,
                    icon: const Icon(Icons.add_rounded, size: 14),
                    label: Text(
                      'NEW HOST',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppConstants.primaryGreen,
                      side: BorderSide(
                        color: AppConstants.primaryGreen.withValues(alpha: 0.4),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ],
              ),
            ),
            // Search Input Bar
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
              child: Container(
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: (_) => setState(() {}),
                  style: GoogleFonts.inter(fontSize: 13, color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Search hosts by name, IP, or tag...',
                    hintStyle: GoogleFonts.inter(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.35),
                    ),
                    prefixIcon: Icon(
                      Icons.search_rounded,
                      size: 18,
                      color: Colors.white.withValues(alpha: 0.4),
                    ),
                    suffixIcon: _searchCtrl.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, size: 16),
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() {});
                            },
                          )
                        : null,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
            ),
            // Filter Pills (ALL, PROD, TAILSCALE, DEV)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: ['ALL', 'PROD', 'TAILSCALE', 'DEV'].map((env) {
                  final isSelected = _selectedEnv == env;
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: InkWell(
                      onTap: () => setState(() => _selectedEnv = env),
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AppConstants.accentBlue.withValues(alpha: 0.2)
                              : Colors.white.withValues(alpha: 0.03),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: isSelected
                                ? AppConstants.accentBlue.withValues(alpha: 0.6)
                                : Colors.white.withValues(alpha: 0.06),
                            width: 0.8,
                          ),
                        ),
                        child: Text(
                          env,
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            color: isSelected
                                ? AppConstants.accentBlue
                                : Colors.white.withValues(alpha: 0.5),
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 6),
            // Server List
            if (filtered.isEmpty)
              Padding(
                padding: const EdgeInsets.all(28),
                child: Center(
                  child: Column(
                    children: [
                      Icon(
                        Icons.dns_rounded,
                        size: 32,
                        color: Colors.white.withValues(alpha: 0.2),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        widget.profiles.isEmpty
                            ? 'No saved server connections yet'
                            : 'No matching hosts found',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.white.withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final p = filtered[index];
                    final isTailscale = p.connectionMethod == ConnectionMethod.tailscale;
                    final env = p.effectiveEnvironment.toUpperCase();
                    final envColor = env == 'PROD'
                        ? const Color(0xFFFF453A)
                        : env == 'TAILSCALE'
                            ? AppConstants.accentBlue
                            : const Color(0xFF30D158);

                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: AppConstants.surface1.withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.07),
                        ),
                      ),
                      child: Material(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(14),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: () => widget.onSelectProfile(p.id),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              children: [
                                // Host Icon
                                Container(
                                  width: 38,
                                  height: 38,
                                  decoration: BoxDecoration(
                                    color: (isTailscale ? AppConstants.accentBlue : AppConstants.primaryGreen)
                                        .withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(
                                    isTailscale ? Icons.hub_rounded : Icons.dns_rounded,
                                    size: 18,
                                    color: isTailscale ? AppConstants.accentBlue : AppConstants.primaryGreen,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                // Host info
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Text(
                                            p.label,
                                            style: GoogleFonts.inter(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w700,
                                              color: Colors.white,
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                            decoration: BoxDecoration(
                                              color: envColor.withValues(alpha: 0.12),
                                              borderRadius: BorderRadius.circular(4),
                                              border: Border.all(
                                                color: envColor.withValues(alpha: 0.3),
                                                width: 0.6,
                                              ),
                                            ),
                                            child: Text(
                                              env,
                                              style: GoogleFonts.jetBrainsMono(
                                                fontSize: 8,
                                                fontWeight: FontWeight.w800,
                                                color: envColor,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        '${p.username}@${p.host}:${p.port}',
                                        style: GoogleFonts.jetBrainsMono(
                                          fontSize: 11,
                                          color: Colors.white.withValues(alpha: 0.5),
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                                // Connect Button
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: AppConstants.primaryGreen.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: AppConstants.primaryGreen.withValues(alpha: 0.35),
                                      width: 0.8,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        'CONNECT',
                                        style: GoogleFonts.jetBrainsMono(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w800,
                                          color: AppConstants.primaryGreen,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      const Icon(
                                        Icons.arrow_forward_rounded,
                                        size: 12,
                                        color: AppConstants.primaryGreen,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Apple TUI 2.0 Quick Command Picker Modal Sheet ──────────────────────────

class _QuickCommandPickerSheet extends StatefulWidget {
  const _QuickCommandPickerSheet({
    required this.savedCommands,
    required this.onRunCommand,
    required this.onPasteCommand,
    required this.onManageCommands,
  });

  final List<dynamic> savedCommands;
  final ValueChanged<String> onRunCommand;
  final ValueChanged<String> onPasteCommand;
  final VoidCallback onManageCommands;

  @override
  State<_QuickCommandPickerSheet> createState() =>
      _QuickCommandPickerSheetState();
}

class _QuickCommandPickerSheetState extends State<_QuickCommandPickerSheet> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _selectedCategory = 'ALL';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchCtrl.text.trim().toLowerCase();

    // Map saved commands into uniform view model
    final savedItems = widget.savedCommands.map((c) {
      return _CommandItem(
        id: c.id as String,
        label: c.label as String,
        command: c.command as String,
        description: 'Saved custom command',
        icon: Icons.bolt_rounded,
        color: AppConstants.accentAmber,
        category: 'SAVED',
      );
    }).toList();

    // Map presets into uniform view model
    final presetItems = AgentPresets.all.map((p) => _CommandItem(
      id: p.id,
      label: p.label,
      command: p.command,
      description: p.description,
      icon: p.icon,
      color: p.color,
      category: p.category == PresetCategory.system
          ? 'SYSTEM'
          : p.category == PresetCategory.devtool
              ? 'DEV TOOLS'
              : 'AI AGENTS',
    )).toList();

    final allItems = [...savedItems, ...presetItems];

    final filtered = allItems.where((item) {
      if (_selectedCategory != 'ALL') {
        if (item.category.toUpperCase() != _selectedCategory) return false;
      }
      if (query.isEmpty) return true;
      return item.label.toLowerCase().contains(query) ||
          item.command.toLowerCase().contains(query) ||
          item.description.toLowerCase().contains(query) ||
          item.category.toLowerCase().contains(query);
    }).toList();

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with Icon, Title, and Manage action
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: AppConstants.accentAmber.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: AppConstants.accentAmber.withValues(alpha: 0.4),
                        width: 0.8,
                      ),
                    ),
                    child: const Icon(
                      Icons.bolt_rounded,
                      size: 18,
                      color: AppConstants.accentAmber,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'QUICK COMMANDS',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.0,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        'Tap RUN to execute directly, or PASTE to edit',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          color: Colors.white.withValues(alpha: 0.45),
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  OutlinedButton.icon(
                    onPressed: widget.onManageCommands,
                    icon: const Icon(Icons.tune_rounded, size: 14),
                    label: Text(
                      'MANAGE',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppConstants.accentAmber,
                      side: BorderSide(
                        color: AppConstants.accentAmber.withValues(alpha: 0.4),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ],
              ),
            ),
            // Search Input Bar
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
              child: Container(
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: (_) => setState(() {}),
                  style: GoogleFonts.inter(fontSize: 13, color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Search commands or presets (e.g. htop, docker)...',
                    hintStyle: GoogleFonts.inter(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.35),
                    ),
                    prefixIcon: Icon(
                      Icons.search_rounded,
                      size: 18,
                      color: Colors.white.withValues(alpha: 0.4),
                    ),
                    suffixIcon: _searchCtrl.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, size: 16),
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() {});
                            },
                          )
                        : null,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
            ),
            // Filter Pills
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: ['ALL', 'SAVED', 'SYSTEM', 'DEV TOOLS', 'AI AGENTS'].map((cat) {
                  final isSelected = _selectedCategory == cat;
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: InkWell(
                      onTap: () => setState(() => _selectedCategory = cat),
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AppConstants.accentAmber.withValues(alpha: 0.2)
                              : Colors.white.withValues(alpha: 0.03),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: isSelected
                                ? AppConstants.accentAmber.withValues(alpha: 0.6)
                                : Colors.white.withValues(alpha: 0.06),
                            width: 0.8,
                          ),
                        ),
                        child: Text(
                          cat,
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            color: isSelected
                                ? AppConstants.accentAmber
                                : Colors.white.withValues(alpha: 0.5),
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 6),
            // Command List
            if (filtered.isEmpty)
              Padding(
                padding: const EdgeInsets.all(28),
                child: Center(
                  child: Column(
                    children: [
                      Icon(
                        Icons.search_off_rounded,
                        size: 32,
                        color: Colors.white.withValues(alpha: 0.2),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'No matching commands found',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.white.withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final item = filtered[index];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: AppConstants.surface1.withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.07),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            // Icon
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: item.color.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                item.icon,
                                size: 18,
                                color: item.color,
                              ),
                            ),
                            const SizedBox(width: 12),
                            // Details
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          item.label,
                                          style: GoogleFonts.inter(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w700,
                                            color: Colors.white,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 4,
                                          vertical: 1,
                                        ),
                                        decoration: BoxDecoration(
                                          color: item.color.withValues(alpha: 0.12),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          item.category,
                                          style: GoogleFonts.jetBrainsMono(
                                            fontSize: 8,
                                            fontWeight: FontWeight.w800,
                                            color: item.color,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    item.command,
                                    style: GoogleFonts.jetBrainsMono(
                                      fontSize: 11,
                                      color: Colors.white.withValues(alpha: 0.5),
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            // Paste action
                            IconButton(
                              tooltip: 'Paste into terminal',
                              icon: const Icon(Icons.content_paste_rounded, size: 16),
                              color: AppConstants.accentBlue,
                              style: IconButton.styleFrom(
                                backgroundColor: AppConstants.accentBlue.withValues(alpha: 0.12),
                                padding: const EdgeInsets.all(8),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              onPressed: () => widget.onPasteCommand(item.command),
                            ),
                            const SizedBox(width: 6),
                            // Run action
                            ElevatedButton.icon(
                              onPressed: () => widget.onRunCommand(item.command),
                              icon: const Icon(Icons.play_arrow_rounded, size: 14),
                              label: Text(
                                'RUN',
                                style: GoogleFonts.jetBrainsMono(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppConstants.primaryGreen,
                                foregroundColor: Colors.black,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CommandItem {
  const _CommandItem({
    required this.id,
    required this.label,
    required this.command,
    required this.description,
    required this.icon,
    required this.color,
    required this.category,
  });

  final String id;
  final String label;
  final String command;
  final String description;
  final IconData icon;
  final Color color;
  final String category;
}

