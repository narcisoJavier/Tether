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
import '../services/key_service.dart';
import '../services/tailscale_provider.dart';
import '../services/tailscale_ssh_socket.dart';
import '../services/profile_storage_service.dart';
import '../services/ssh_service.dart';
import '../utils/constants.dart';
import '../utils/app_version.dart';
import '../utils/terminal_settings_provider.dart';

/// Full-screen terminal screen connected to an SSH session.
///
/// Auto-optimizes the font size to fit at least 80 columns in portrait and
/// 120 columns in landscape, so TUI apps (opencode, aider, etc.) render fully.
/// In landscape, system chrome is hidden for maximum terminal area.
class TerminalScreen extends ConsumerStatefulWidget {
  const TerminalScreen({super.key, required this.profileId});

  /// ID of the connection profile to use.
  final String profileId;

  @override
  ConsumerState<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends ConsumerState<TerminalScreen>
    with WidgetsBindingObserver {
  late final Terminal _terminal;
  late final TerminalController _terminalController;

  StreamSubscription? _stdoutSub;
  bool _isConnected = false;
  bool _isConnecting = false;
  String? _error;
  double _fontSize = AppConstants.defaultFontSize;

  // True if the user has manually pinched to zoom (disables auto-fit).
  bool _userZoomed = false;
  // Last calculated available size (to detect orientation changes).
  Size _lastTerminalSize = Size.zero;

  // True once the shell has been opened; prevents opening it before the
  // TerminalView has been laid out (which would send wrong cols/rows).
  bool _shellStarted = false;

  // Accumulates raw bytes from the remote until a complete UTF-8 sequence is
  // available, so multi-byte characters split across packets aren't mangled.
  final BytesBuilder _utf8Buffer = BytesBuilder();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _fontSize = ref.read(terminalFontSizeProvider);
    final scrollbackLines = ref.read(terminalScrollbackProvider);

    _terminal = Terminal(maxLines: scrollbackLines);
    _terminalController = TerminalController();

    // TerminalView (autoResize) calls terminal.resize() once laid out, which
    // fires onResize with the real cols/rows. We use that to open the PTY
    // shell with correct dimensions instead of a stale 80×24 default.
    _terminal.onResize = (width, height, pixelWidth, pixelHeight) {
      // If the shell isn't open yet, this is the post-layout signal we wait
      // for. Otherwise, propagate live resizes to the remote PTY.
      if (_shellStarted) {
        if (width > 0 && height > 0) {
          ref
              .read(sshServiceProvider(widget.profileId))
              .resizeShell(
                cols: width,
                rows: height,
                pixelWidth: pixelWidth,
                pixelHeight: pixelHeight,
              );
        }
      } else {
        _maybeStartShell();
      }
    };

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _connect();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _restoreSystemUI();
    _stdoutSub?.cancel();
    ref.read(sshServiceProvider(widget.profileId)).disconnect();
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    // Re-evaluate orientation and system UI after rotation.
    if (mounted) {
      _handleOrientation();
    }
  }

  /// Compute the optimal font size to fit [targetCols] columns within the
  /// given terminal area width. Returns a value clamped to font bounds.
  double _computeOptimalFontSize(double areaWidth, int targetCols) {
    // Each monospace char is approximately fontSize * charWidthRatio wide.
    // Solve: fontSize = areaWidth / (targetCols * ratio)
    final computed =
        areaWidth / (targetCols * AppConstants.charWidthRatio);
    return computed.clamp(AppConstants.minFontSize, AppConstants.maxFontSize);
  }

  /// Detect landscape and apply immersive mode + slim UI accordingly.
  void _handleOrientation() {
    final size = MediaQuery.of(context).size;
    final isLandscape = size.width > size.height;

    if (isLandscape) {
      // Hide system chrome in landscape for maximum terminal area.
      SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.immersiveSticky,
        overlays: [],
      );
    } else {
      _restoreSystemUI();
    }
  }

  void _restoreSystemUI() {
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.edgeToEdge,
      overlays: SystemUiOverlay.values,
    );
  }

  Future<void> _connect() async {
    setState(() {
      _isConnecting = true;
      _error = null;
    });

    final version = await AppVersion.get();
    _terminal.write(
      '\x1b[1;32m⬡ OPA — OpenSSH Pocket Agent v$version\x1b[0m\r\n\r\n'
      '\x1b[33mConnecting...\x1b[0m\r\n',
    );

    try {
      final storage = ref.read(profileStorageProvider);
      final profile = storage.getProfile(widget.profileId);
      if (profile == null) {
        throw StateError('Profile not found: ${widget.profileId}');
      }

      final sshService = ref.read(sshServiceProvider(widget.profileId));

      TailscaleSSHSocket? sock;
      if (profile.connectionMethod == ConnectionMethod.tailscale) {
        var ts = ref.read(tailscaleServiceProvider);
        var conn = await ts.dial(profile.host, profile.port, timeout: const Duration(seconds: 10));
        sock = TailscaleSSHSocket(conn);
      } else {
        sock = null;
      }

      String? privateKey;
      if (profile.keyId != null) {
        privateKey =
            await ref.read(keyServiceProvider).getPrivateKey(profile.keyId!);
      }

      // Retrieve password from secure storage (migrated from Hive).
      // Falls back to profile.password for profiles not yet migrated.
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

      _terminal.write(
          '\x1b[32m✓ Connected to ${profile.displayName}\x1b[0m\r\n\r\n');

      // Auto-start enabled tunnels (if any configured on this profile).
      if (profile.tunnels.isNotEmpty) {
        final tunnelCount = await sshService.autoStartTunnels(profile.tunnels);
        if (tunnelCount > 0) {
          _terminal.write(
              '\x1b[36m⇌ $tunnelCount tunnel(s) auto-started\x1b[0m\r\n\r\n');
        }
      }

      setState(() {
        _isConnected = true;
        _isConnecting = false;
      });

      await storage.updateConnectionStatus(profile.id, true);

      // Defer opening the PTY shell until the TerminalView has been laid out,
      // so we send the real cols/rows instead of a wrong 80×24 default. This
      // prevents TUI apps (opencode/agy) from drawing to stale dimensions and
      // leaving a blank/frozen screen.
      _maybeStartShell();
    } catch (e) {
      if (mounted) {
        _terminal.write('\r\n\x1b[31m✗ Connection failed:\x1b[0m $e\r\n\r\n');

        final storage = ref.read(profileStorageProvider);
        await storage.updateConnectionStatus(widget.profileId, false);

        setState(() {
          _isConnecting = false;
          _error = e.toString();
        });
      }
    }
  }

  /// Opens the SSH shell once the terminal has real dimensions. Called both
  /// after a successful connect and from the TerminalView's onSize callback.
  void _maybeStartShell() {
    if (_shellStarted || !_isConnected) return;

    final cols = _terminal.viewWidth;
    final rows = _terminal.viewHeight;
    // Wait until the view reports non-zero dimensions (post-layout).
    if (cols <= 0 || rows <= 0) {
      return;
    }

    _shellStarted = true;
    _startShell(cols, rows);
  }

  Future<void> _startShell(int cols, int rows) async {
    final sshService = ref.read(sshServiceProvider(widget.profileId));

    // Estimate pixel dimensions from the font size so TUIs that rely on
    // pixel-based layout get reasonable values.
    final charHeight = _fontSize;
    final charWidth = _fontSize * AppConstants.charWidthRatio;
    final pixelWidth = (cols * charWidth).round();
    final pixelHeight = (rows * charHeight).round();

    try {
      final session = await sshService.startShell(
        cols: cols,
        rows: rows,
        pixelWidth: pixelWidth,
        pixelHeight: pixelHeight,
      );

      _stdoutSub = session.stdout.listen(
        (data) {
          if (mounted) {
            _writeBytesToTerminal(data);
          }
        },
        onDone: () {
          if (mounted) {
            // Flush any buffered bytes before showing the closed message.
            _flushUtf8Buffer();
            _terminal.write('\r\n\x1b[33m⚡ Connection closed\x1b[0m\r\n');
            setState(() => _isConnected = false);
          }
        },
        onError: (e) {
          if (mounted) {
            _flushUtf8Buffer();
            _terminal.write('\r\n\x1b[31m✗ Error: $e\x1b[0m\r\n');
            setState(() => _isConnected = false);
          }
        },
      );

      _terminal.onOutput = (String data) {
        session.stdinSink.add(Uint8List.fromList(utf8.encode(data)));
      };

      // NOTE: _terminal.onResize is wired in initState() and handles both the
      // initial shell-open trigger and live resizes. Not reassigned here.
    } catch (e) {
      if (mounted) {
        _terminal.write('\r\n\x1b[31m✗ Shell error:\x1b[0m $e\r\n');
        setState(() => _isConnected = false);
      }
    }
  }

  /// Decodes raw SSH stdout bytes as UTF-8 and writes them to the terminal.
  ///
  /// Bytes are accumulated in [_utf8Buffer] because a multi-byte UTF-8
  /// sequence (e.g. a box-drawing char used by opencode/agy) can be split
  /// across two packets. Decoding only the complete prefix avoids the
  /// garbled-text bug that `String.fromCharCodes(data)` caused.
  void _writeBytesToTerminal(Uint8List data) {
    _utf8Buffer.add(data);
    final bytes = _utf8Buffer.takeBytes();
    final decoded = utf8.decode(bytes, allowMalformed: true);
    _terminal.write(decoded);
  }

  /// Writes any remaining buffered bytes to the terminal (call on close).
  void _flushUtf8Buffer() {
    if (_utf8Buffer.isEmpty) return;
    final bytes = _utf8Buffer.takeBytes();
    _terminal.write(utf8.decode(bytes, allowMalformed: true));
  }

  void _disconnect() async {
    await ref.read(sshServiceProvider(widget.profileId)).disconnect();
    _stdoutSub?.cancel();
    _stdoutSub = null;
    _shellStarted = false;
    _utf8Buffer.takeBytes(); // discard any buffered bytes
    setState(() => _isConnected = false);
  }

  void _sendCtrlC() {
    _terminal.textInput(String.fromCharCode(3));
  }

  void _sendCtrlD() {
    _terminal.textInput(String.fromCharCode(4));
  }

  void _copySelection() {
    final selection = _terminalController.selection;
    if (selection != null) {
      final text = _terminal.buffer.getText(selection);
      if (text.isNotEmpty) {
        Clipboard.setData(ClipboardData(text: text));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Copied to clipboard', style: GoogleFonts.inter()),
            duration: const Duration(seconds: 1),
          ),
        );
        return;
      }
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Select text to copy', style: GoogleFonts.inter()),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  void _zoomIn() {
    setState(() {
      _userZoomed = true;
      _fontSize = (_fontSize + 1).clamp(
        AppConstants.minFontSize,
        AppConstants.maxFontSize,
      );
    });
  }

  void _zoomOut() {
    setState(() {
      _userZoomed = true;
      _fontSize = (_fontSize - 1).clamp(
        AppConstants.minFontSize,
        AppConstants.maxFontSize,
      );
    });
  }

  void _resetAutoFit() {
    setState(() {
      _userZoomed = false;
      _lastTerminalSize = Size.zero; // force recompute
    });
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final size = mq.size;
    final isLandscape = size.width > size.height;
    // The keyboard bar shows only on narrow (phone) screens.
    final showKeyboardBar = mq.size.shortestSide < 600;

    return Scaffold(
      // No AppBar in landscape → maximize vertical space.
      appBar: isLandscape ? null : _buildAppBar(),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final areaWidth = constraints.maxWidth;
          final areaHeight = constraints.maxHeight;

          // ── Auto-fit font size ──
          // Only recompute when the available size changes significantly AND
          // the user hasn't manually zoomed.
          if (!_userZoomed) {
            final sizeChanged =
                (_lastTerminalSize.width - areaWidth).abs() > 4 ||
                    (_lastTerminalSize.height - areaHeight).abs() > 4;
            if (sizeChanged || _lastTerminalSize == Size.zero) {
              final targetCols = isLandscape
                  ? AppConstants.targetMinColsLandscape
                  : AppConstants.targetMinColsPortrait;
              final optimal = _computeOptimalFontSize(areaWidth, targetCols);
              if ((optimal - _fontSize).abs() > 0.5) {
                _fontSize = optimal;
              }
              _lastTerminalSize = Size(areaWidth, areaHeight);
            }
          }

          return Column(
            children: [
              _buildStatusBar(isLandscape),
              Expanded(
                child: GestureDetector(
                  onScaleUpdate: (details) {
                    if (details.scale != 1.0) {
                      setState(() {
                        _userZoomed = true;
                        _fontSize = (_fontSize * details.scale).clamp(
                          AppConstants.minFontSize,
                          AppConstants.maxFontSize,
                        );
                      });
                    }
                  },
                  child: TerminalView(
                    _terminal,
                    controller: _terminalController,
                    autofocus: true,
                    backgroundOpacity: 1.0,
                    textStyle: TerminalStyle(
                      fontFamily: 'JetBrainsMono',
                      fontSize: _fontSize,
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
              if (showKeyboardBar)
                _buildMobileKeyboardBar(isLandscape),
            ],
          );
        },
      ),
    );
  }

  // ── Terminal color theme ──────────────────────────────────────────

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

  // ── AppBar ───────────────────────────────────────────────────────

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      toolbarHeight: 48,
      title: Text(
        ref
                .read(profileStorageProvider)
                .getProfile(widget.profileId)
                ?.shortLabel ??
            'Terminal',
        style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.folder_open_rounded, size: 20),
          tooltip: 'SFTP Browser',
          onPressed: () => context.push('/sftp/${widget.profileId}'),
        ),
        IconButton(
          icon: const Icon(Icons.zoom_out_rounded, size: 20),
          tooltip: 'Zoom out',
          onPressed: _zoomOut,
        ),
        Padding(
          padding: const EdgeInsets.only(top: 14),
          child: Text(
            '${_fontSize.toInt()}',
            style: GoogleFonts.jetBrainsMono(
              fontSize: 12,
              color: Colors.white.withValues(alpha: 0.4),
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.zoom_in_rounded, size: 20),
          tooltip: 'Zoom in',
          onPressed: _zoomIn,
        ),
        IconButton(
          icon: Icon(
            _userZoomed
                ? Icons.fit_screen_outlined
                : Icons.fit_screen_rounded,
            size: 18,
            color: _userZoomed
                ? AppConstants.primaryGreen
                : Colors.white.withValues(alpha: 0.4),
          ),
          tooltip: 'Auto-fit',
          onPressed: _resetAutoFit,
        ),
        const SizedBox(width: 4),
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert_rounded),
          onSelected: (action) {
            switch (action) {
              case 'ctrl_c':
                _sendCtrlC();
                break;
              case 'ctrl_d':
                _sendCtrlD();
                break;
              case 'copy':
                _copySelection();
                break;
              case 'autofit':
                _resetAutoFit();
                break;
              case 'disconnect':
                _disconnect();
                break;
              case 'reconnect':
                _disconnect();
                _connect();
                break;
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'ctrl_c',
              child: Row(children: [
                Icon(Icons.stop_circle_outlined, size: 18),
                SizedBox(width: 12),
                Text('Ctrl+C'),
              ]),
            ),
            const PopupMenuItem(
              value: 'ctrl_d',
              child: Row(children: [
                Icon(Icons.door_front_door_outlined, size: 18),
                SizedBox(width: 12),
                Text('Ctrl+D (EOF)'),
              ]),
            ),
            const PopupMenuItem(
              value: 'copy',
              child: Row(children: [
                Icon(Icons.copy_rounded, size: 18),
                SizedBox(width: 12),
                Text('Copy selection'),
              ]),
            ),
            const PopupMenuItem(
              value: 'autofit',
              child: Row(children: [
                Icon(Icons.fit_screen_rounded, size: 18),
                SizedBox(width: 12),
                Text('Auto-fit to screen'),
              ]),
            ),
            const PopupMenuDivider(),
            if (_isConnected)
              const PopupMenuItem(
                value: 'disconnect',
                child: Row(children: [
                  Icon(Icons.link_off_rounded, size: 18, color: Colors.red),
                  SizedBox(width: 12),
                  Text('Disconnect'),
                ]),
              ),
            if (!_isConnected)
              const PopupMenuItem(
                value: 'reconnect',
                child: Row(children: [
                  Icon(Icons.refresh_rounded,
                      size: 18, color: AppConstants.primaryGreen),
                  SizedBox(width: 12),
                  Text('Reconnect'),
                ]),
              ),
          ],
        ),
      ],
    );
  }

  // ── Status bar ───────────────────────────────────────────────────

  Widget _buildStatusBar(bool isLandscape) {
    Color statusColor;
    String statusText;

    if (_isConnecting) {
      statusColor = const Color(0xFFFFAB40);
      statusText = '⏳ Connecting...';
    } else if (_isConnected) {
      statusColor = AppConstants.primaryGreen;
      statusText = '● Connected';
    } else if (_error != null) {
      statusColor = Colors.red;
      statusText = '✗ Disconnected';
    } else {
      statusColor = Colors.white.withValues(alpha: 0.3);
      statusText = '○ Disconnected';
    }

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
        child: Container(
          height: isLandscape
              ? AppConstants.statusBarHeightLandscape
              : AppConstants.statusBarHeightPortrait,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          color: AppConstants.surfaceDark.withValues(alpha: 0.7),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: statusColor,
                  boxShadow: [
                    BoxShadow(
                      color: statusColor.withValues(alpha: 0.5),
                      blurRadius: 4,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                statusText,
                style: GoogleFonts.inter(
                  fontSize: 11,
                  color: statusColor,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              Text(
                '${_terminal.viewWidth}×${_terminal.viewHeight}',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 11,
                  color: Colors.white.withValues(alpha: 0.3),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Mobile keyboard bar ──────────────────────────────────────────

  Widget _buildMobileKeyboardBar(bool isLandscape) {
    final barHeight = isLandscape
        ? AppConstants.keyboardBarHeightLandscape
        : AppConstants.keyboardBarHeightPortrait;

    // Compact layout in landscape — only essential keys.
    final keys = isLandscape
        ? [
            _KeyDef('TAB', () => _terminal.keyInput(TerminalKey.tab)),
            _KeyDef('ESC', () => _terminal.keyInput(TerminalKey.escape)),
            _KeyDef('↑', () => _terminal.keyInput(TerminalKey.arrowUp)),
            _KeyDef('↓', () => _terminal.keyInput(TerminalKey.arrowDown)),
            _KeyDef('←', () => _terminal.keyInput(TerminalKey.arrowLeft)),
            _KeyDef('→', () => _terminal.keyInput(TerminalKey.arrowRight)),
            _KeyDef('CTRL', _sendCtrlC, color: const Color(0xFFFF5252)),
          ]
        : [
            _KeyDef('TAB', () => _terminal.keyInput(TerminalKey.tab)),
            _KeyDef('ESC', () => _terminal.keyInput(TerminalKey.escape)),
            _KeyDef('↑', () => _terminal.keyInput(TerminalKey.arrowUp)),
            _KeyDef('↓', () => _terminal.keyInput(TerminalKey.arrowDown)),
            _KeyDef('←', () => _terminal.keyInput(TerminalKey.arrowLeft)),
            _KeyDef('→', () => _terminal.keyInput(TerminalKey.arrowRight)),
            _KeyDef('CTRL', _sendCtrlC, color: const Color(0xFFFF5252)),
            _KeyDef('/', () => _terminal.textInput('/')),
            _KeyDef('|', () => _terminal.textInput('|')),
            _KeyDef('-', () => _terminal.textInput('-')),
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
}

/// Internal helper holding a keyboard key definition.
class _KeyDef {
  const _KeyDef(this.label, this.onPressed, {this.color});
  final String label;
  final VoidCallback onPressed;
  final Color? color;
}

/// Special key button for the mobile keyboard bar.
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
