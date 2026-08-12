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
import '../services/quick_command_layout_service.dart';
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
      if (mounted) {
        context.go('/');
      }
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

    // Auto-bounce to Home when zero tabs exist and no tab request is pending
    if (_tabOrder.isEmpty && initialPendingTab == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            _tabOrder.isEmpty &&
            ref.read(pendingTerminalTabProvider) == null) {
          context.go('/');
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
        body: Padding(
          padding: EdgeInsets.only(
            bottom: 64 + MediaQuery.paddingOf(context).bottom,
          ),
          child: Column(
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

  /// Opens a bottom sheet showing saved servers to connect in a new tab.
  void _showServerPickerModalSheet() {
    final storage = ref.read(profileStorageProvider);
    final profiles = storage.listProfiles();

    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      useSafeArea: true,
      backgroundColor: AppConstants.surface2,
      barrierColor: Colors.black.withValues(alpha: 0.7),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(ctx).height * 0.78,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drag handle
              Center(
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 12),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 4,
                ),
                child: Text(
                  'Open New Terminal Tab',
                  style: GoogleFonts.inter(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (profiles.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                    child: Column(
                      children: [
                        Text(
                          'No saved server connections yet.',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            color: Colors.white.withValues(alpha: 0.5),
                          ),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: () {
                            Navigator.pop(ctx);
                            context.go('/profile/new');
                          },
                          icon: const Icon(Icons.add_rounded, size: 18),
                          label: Text(
                            'Add Connection',
                            style: GoogleFonts.inter(),
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
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: profiles.length,
                    itemBuilder: (context, index) {
                      final p = profiles[index];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: AppConstants.surface1,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.06),
                          ),
                        ),
                        child: ListTile(
                          title: Text(
                            p.label,
                            style: GoogleFonts.inter(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                          subtitle: Text(
                            '${p.username}@${p.host}:${p.port}',
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 12,
                              color: Colors.white.withValues(alpha: 0.45),
                            ),
                          ),
                          trailing: const Icon(
                            Icons.add_circle_outline_rounded,
                            color: AppConstants.primaryGreen,
                            size: 22,
                          ),
                          onTap: () {
                            Navigator.pop(ctx);
                            _createTabNow(p.id);
                          },
                        ),
                      );
                    },
                  ),
                ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  /// Opens a bottom sheet showing quick commands for the current profile.
  void _showQuickCommandModalSheet(_TabData tab) {
    final storage = ref.read(profileStorageProvider);
    final layout = ref.read(quickCommandLayoutProvider);
    final commands = layout.orderItems(
      storage.listCommandsForProfile(tab.profileId),
      (command) => 'saved:${command.id}',
    );
    final allCommands = storage.listCommands();
    final displayCommands = commands.isNotEmpty
        ? commands
        : layout.orderItems(allCommands, (command) => 'saved:${command.id}');

    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      useSafeArea: true,
      backgroundColor: AppConstants.surface2,
      barrierColor: Colors.black.withValues(alpha: 0.7),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(ctx).height * 0.78,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drag handle
              Center(
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 12),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 4,
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.bolt_rounded,
                      color: AppConstants.accentAmber,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Execute Quick Command',
                      style: GoogleFonts.inter(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              if (displayCommands.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                    child: Column(
                      children: [
                        Text(
                          'No saved quick commands.',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            color: Colors.white.withValues(alpha: 0.5),
                          ),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: () {
                            Navigator.pop(ctx);
                            context.go('/commands');
                          },
                          icon: const Icon(Icons.add_rounded, size: 18),
                          label: Text(
                            'Manage Commands',
                            style: GoogleFonts.inter(),
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
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: displayCommands.length,
                    itemBuilder: (context, index) {
                      final cmd = displayCommands[index];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: AppConstants.surface1,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.06),
                          ),
                        ),
                        child: ListTile(
                          leading: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppConstants.accentAmber.withValues(
                                alpha: 0.1,
                              ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.terminal_rounded,
                              size: 18,
                              color: AppConstants.accentAmber,
                            ),
                          ),
                          title: Text(
                            cmd.label,
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                          subtitle: Text(
                            cmd.command,
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 12,
                              color: Colors.white.withValues(alpha: 0.5),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: const Icon(
                            Icons.play_arrow_rounded,
                            color: AppConstants.primaryGreen,
                            size: 22,
                          ),
                          onTap: () {
                            Navigator.pop(ctx);
                            final execStr = cmd.command.endsWith('\n')
                                ? cmd.command
                                : '${cmd.command}\n';
                            tab.terminal.textInput(execStr);
                          },
                        ),
                      );
                    },
                  ),
                ),
              const SizedBox(height: 16),
            ],
          ),
        ),
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
    final storage = ref.read(profileStorageProvider);
    final profiles = storage.listProfiles();

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
      child: Column(
        children: [
          const SizedBox(height: 20),
          // Glow terminal icon
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppConstants.accentBlue.withValues(alpha: 0.08),
              shape: BoxShape.circle,
              border: Border.all(
                color: AppConstants.accentBlue.withValues(alpha: 0.2),
              ),
            ),
            child: const Icon(
              Icons.terminal_rounded,
              size: 48,
              color: AppConstants.accentBlue,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'No Active Terminal Sessions',
            style: GoogleFonts.inter(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Select a server below to launch an SSH terminal tab:',
            style: GoogleFonts.inter(
              fontSize: 14,
              color: Colors.white.withValues(alpha: 0.45),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),

          // Primary "Open New Tab" Button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _showServerPickerModalSheet,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppConstants.accentBlue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 0,
              ),
              icon: const Icon(Icons.add_rounded, size: 20),
              label: Text(
                'Open Terminal Session',
                style: GoogleFonts.inter(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),

          const SizedBox(height: 28),

          // Saved Connections List header
          if (profiles.isNotEmpty) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'SAVED CONNECTIONS',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                  color: Colors.white.withValues(alpha: 0.4),
                ),
              ),
            ),
            const SizedBox(height: 12),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: profiles.length,
              itemBuilder: (context, index) {
                final p = profiles[index];
                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: AppConstants.surface0,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.06),
                    ),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    leading: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppConstants.surface1,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.dns_rounded,
                        size: 20,
                        color: AppConstants.accentBlue,
                      ),
                    ),
                    title: Text(
                      p.label,
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    subtitle: Text(
                      '${p.username}@${p.host}:${p.port}',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.45),
                      ),
                    ),
                    trailing: const Icon(
                      Icons.play_arrow_rounded,
                      color: AppConstants.primaryGreen,
                      size: 24,
                    ),
                    onTap: () => _createTabNow(p.id),
                  ),
                );
              },
            ),
          ],

          const SizedBox(height: 16),

          // Return Home link
          TextButton.icon(
            onPressed: () => context.go('/'),
            icon: const Icon(Icons.arrow_back_rounded, size: 16),
            label: Text(
              'Back to Home Dashboard',
              style: GoogleFonts.inter(
                fontSize: 13,
                color: Colors.white.withValues(alpha: 0.4),
              ),
            ),
          ),
        ],
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
            _KeyDef(
              '⚡',
              () => _showQuickCommandModalSheet(tab),
              color: AppConstants.accentAmber,
            ),
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
                .map(
                  (k) => _SpecialKeyButton(
                    label: k.label,
                    onPressed: k.onPressed,
                    color: k.color,
                  ),
                )
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
