import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/connection_profile.dart';
import '../services/key_service.dart';
import '../services/profile_storage_service.dart';
import '../services/sftp_service.dart';
import '../services/ssh_service.dart';
import '../services/terminal_tab_request_provider.dart';
import '../services/tailscale_provider.dart';
import '../services/tailscale_ssh_socket.dart';
import '../utils/constants.dart';
import '../utils/terminal_settings_provider.dart';

/// Screen for browsing remote files via SFTP.
class SftpScreen extends ConsumerStatefulWidget {
  const SftpScreen({super.key, required this.profileId});

  final String profileId;

  @override
  ConsumerState<SftpScreen> createState() => _SftpScreenState();
}

class _SftpScreenState extends ConsumerState<SftpScreen> {
  final SftpService _sftpService = SftpService();
  final List<String> _pathStack = ['/'];
  List<SftpEntry> _entries = [];
  bool _isLoading = true;
  String? _error;
  bool _isConnected = false;
  bool _ownsSshConnection = false;

  late final SshService _sshService;

  String get _currentPath => _pathStack.last;

  @override
  void initState() {
    super.initState();
    _sshService = ref.read(sshServiceProvider(widget.profileId));
    _connect();
  }

  Future<void> _connect() async {
    try {
      var client = _sshService.client;

      // SFTP can be opened directly from a connection tile. Reuse an
      // existing terminal client when available; otherwise establish a
      // profile-scoped SSH connection that this screen owns.
      if (client == null) {
        final profile = ref
            .read(profileStorageProvider)
            .getProfile(widget.profileId);
        if (profile == null) {
          throw StateError('Connection profile not found.');
        }

        TailscaleSSHSocket? socket;
        if (profile.connectionMethod == ConnectionMethod.tailscale) {
          final ts = ref.read(tailscaleServiceProvider);
          final connection = await ts.dial(
            profile.host,
            profile.port,
            timeout: const Duration(seconds: 10),
          );
          socket = TailscaleSSHSocket(connection);
        }

        final privateKey = profile.keyId == null
            ? null
            : await ref.read(keyServiceProvider).getPrivateKey(profile.keyId!);
        final securePassword = await ref
            .read(profileStorageProvider)
            .getPassword(profile.id);

        await _sshService.connect(
          profile: profile,
          privateKey: privateKey,
          password: securePassword ?? profile.password,
          keepalive: Duration(seconds: ref.read(terminalKeepaliveProvider)),
          socket: socket,
        );
        _ownsSshConnection = true;
        client = _sshService.client;
      }

      if (client == null) {
        throw StateError('SSH connection was not established.');
      }

      await _sftpService.connect(client);
      if (!mounted) return;
      setState(() => _isConnected = true);
      await _listDirectory();
    } catch (e) {
      if (_ownsSshConnection) {
        await _sshService.disconnect();
        _ownsSshConnection = false;
      }
      if (!mounted) return;
      setState(() {
        _error = 'SFTP failed: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _listDirectory() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final entries = await _sftpService.listDirectory(_currentPath);
      entries.sort((a, b) {
        if (a.isDirectory && !b.isDirectory) return -1;
        if (!a.isDirectory && b.isDirectory) return 1;
        return a.filename.compareTo(b.filename);
      });
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _isLoading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to list directory: $e';
        _isLoading = false;
      });
    }
  }

  String _joinPath(String name) {
    return _currentPath == '/' ? '/$name' : '$_currentPath/$name';
  }

  void _navigateToDir(String dirName) {
    final newPath = _joinPath(dirName);
    _pathStack.add(newPath);
    _listDirectory();
  }

  void _navigateToPath(String path) {
    final idx = _pathStack.indexOf(path);
    if (idx >= 0) {
      _pathStack.removeRange(idx + 1, _pathStack.length);
      _listDirectory();
    }
  }

  Future<void> _createDirectory() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
        backgroundColor: AppConstants.surfaceDark,
        title: Text(
          'New Directory',
          style: GoogleFonts.inter(fontWeight: FontWeight.w600),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'folder_name',
            prefixIcon: Icon(Icons.create_new_folder_rounded),
          ),
          style: GoogleFonts.jetBrainsMono(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) {
      try {
        await _sftpService.createDirectory(_joinPath(name));
        await _listDirectory();
      } catch (e) {
        if (mounted) _showError('Failed to create directory: $e');
      }
    }
  }

  Future<void> _deleteEntry(SftpEntry entry) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
        backgroundColor: AppConstants.surfaceDark,
        title: Text(
          'Delete ${entry.isDirectory ? 'Directory' : 'File'}',
          style: GoogleFonts.inter(fontWeight: FontWeight.w600),
        ),
        content: Text(
          'Delete "${entry.filename}"? This cannot be undone.',
          style: GoogleFonts.inter(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      try {
        if (entry.isDirectory) {
          await _sftpService.deleteDirectory(_joinPath(entry.filename));
        } else {
          await _sftpService.deleteFile(_joinPath(entry.filename));
        }
        await _listDirectory();
      } catch (e) {
        if (mounted) _showError('Delete failed: $e');
      }
    }
  }

  Future<void> _renameEntry(SftpEntry entry) async {
    final controller = TextEditingController(text: entry.filename);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
        backgroundColor: AppConstants.surfaceDark,
        title: Text(
          'Rename',
          style: GoogleFonts.inter(fontWeight: FontWeight.w600),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.edit_rounded),
          ),
          style: GoogleFonts.jetBrainsMono(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Rename'),
          ),
        ],
      ),
    );
    if (newName != null && newName.isNotEmpty && newName != entry.filename) {
      try {
        await _sftpService.rename(
          _joinPath(entry.filename),
          _joinPath(newName),
        );
        await _listDirectory();
      } catch (e) {
        if (mounted) _showError('Rename failed: $e');
      }
    }
  }

  Future<void> _downloadEntry(SftpEntry entry) async {
    try {
      if (entry.size > 512 * 1024) {
        if (mounted) {
          _showError(
            'File exceeds 512KB clipboard preview limit (${_formatSize(entry.size)}).',
          );
        }
        return;
      }
      final bytes = await _sftpService.readFile(
        _joinPath(entry.filename),
      );
      final text = utf8.decode(bytes, allowMalformed: true);
      await Clipboard.setData(ClipboardData(text: text));
      if (mounted) {
        _showSuccess('Downloaded to clipboard');
      }
    } catch (e) {
      if (mounted) _showError('Download failed: $e');
    }
  }

  Future<void> _uploadFile() async {
    final filenameController = TextEditingController();
    final contentController = TextEditingController();
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
        backgroundColor: AppConstants.surfaceDark,
        title: Text(
          'Upload File',
          style: GoogleFonts.inter(fontWeight: FontWeight.w600),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: filenameController,
              decoration: const InputDecoration(
                hintText: 'filename.txt',
                prefixIcon: Icon(Icons.insert_drive_file_rounded),
              ),
              style: GoogleFonts.jetBrainsMono(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: contentController,
              maxLines: 6,
              decoration: const InputDecoration(
                hintText: 'Paste file content here...',
                hintMaxLines: 3,
              ),
              style: GoogleFonts.jetBrainsMono(fontSize: 11),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, {
              'filename': filenameController.text.trim(),
              'content': contentController.text,
            }),
            child: const Text('Upload'),
          ),
        ],
      ),
    );
    filenameController.dispose();
    contentController.dispose();

    final filename = result?['filename'];
    final content = result?['content'] ?? '';
    if (filename != null && filename.isNotEmpty) {
      try {
        await _sftpService.writeFile(
          _joinPath(filename),
          Uint8List.fromList(utf8.encode(content)),
        );
        await _listDirectory();
        if (mounted) _showSuccess('Uploaded');
      } catch (e) {
        if (mounted) _showError('Upload failed: $e');
      }
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_rounded, color: Colors.red),
            const SizedBox(width: 8),
            Expanded(child: Text(msg, style: GoogleFonts.inter(fontSize: 13))),
          ],
        ),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showSuccess(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(
              Icons.check_circle_rounded,
              color: AppConstants.primaryGreen,
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(msg, style: GoogleFonts.inter(fontSize: 13))),
          ],
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _openInTerminal() async {
    // This screen may have created a temporary SSH client for direct SFTP
    // entry. Release it before the terminal branch creates its own session.
    if (_ownsSshConnection) {
      await _sftpService.disconnect();
      await _sshService.disconnect();
      _ownsSshConnection = false;
    }
    if (!mounted) return;
    ref.read(pendingTerminalTabProvider.notifier).state = TerminalTabRequest(
      profileId: widget.profileId,
    );
    context.go('/terminal');
  }

  @override
  void dispose() {
    unawaited(_sftpService.disconnect());
    if (_ownsSshConnection) {
      unawaited(_sshService.disconnect());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'SFTP Browser',
          style: GoogleFonts.inter(fontWeight: FontWeight.w600),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.terminal_rounded),
            tooltip: 'Open in Terminal',
            onPressed: _openInTerminal,
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
            onPressed: _listDirectory,
          ),
          if (_isConnected) ...[
            IconButton(
              icon: const Icon(Icons.create_new_folder_rounded),
              tooltip: 'New Directory',
              onPressed: _createDirectory,
            ),
            IconButton(
              icon: const Icon(Icons.file_upload_rounded),
              tooltip: 'Upload File',
              onPressed: _uploadFile,
            ),
          ],
        ],
      ),
      body: Column(
        children: [
          _buildBreadcrumb(),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBreadcrumb() {
    final parts = _currentPath.split('/').where((p) => p.isNotEmpty).toList();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppConstants.surfaceDark.withValues(alpha: 0.5),
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _breadcrumbItem(
              '/',
              _pathStack.length == 1,
              () => _navigateToPath('/'),
            ),
            for (int i = 0; i < parts.length; i++) ...[
              Icon(
                Icons.chevron_right,
                size: 14,
                color: Colors.white.withValues(alpha: 0.3),
              ),
              _breadcrumbItem(
                parts[i],
                i == parts.length - 1,
                () => _navigateToPath('/${parts.take(i + 1).join('/')}'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _breadcrumbItem(String label, bool isActive, VoidCallback onTap) {
    return GestureDetector(
      onTap: isActive ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isActive
              ? AppConstants.primaryGreen.withValues(alpha: 0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: GoogleFonts.jetBrainsMono(
            fontSize: 12,
            fontWeight: isActive ? FontWeight.w700 : FontWeight.w400,
            color: isActive
                ? AppConstants.primaryGreen
                : Colors.white.withValues(alpha: 0.5),
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_error != null && !_isConnected) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.cloud_off_rounded,
                size: 64,
                color: Colors.white.withValues(alpha: 0.1),
              ),
              const SizedBox(height: 16),
              Text(
                _error!,
                style: GoogleFonts.inter(
                  color: Colors.white.withValues(alpha: 0.5),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => context.pop(),
                icon: const Icon(Icons.arrow_back_rounded),
                label: Text('Go Back', style: GoogleFonts.inter()),
              ),
            ],
          ),
        ),
      );
    }

    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppConstants.primaryGreen),
      );
    }

    if (_entries.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.folder_open_rounded,
              size: 64,
              color: Colors.white.withValues(alpha: 0.1),
            ),
            const SizedBox(height: 16),
            Text(
              'Empty directory',
              style: GoogleFonts.inter(
                fontSize: 16,
                color: Colors.white.withValues(alpha: 0.4),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _listDirectory,
      color: AppConstants.primaryGreen,
      child: ListView.builder(
        padding: const EdgeInsets.only(top: 4, bottom: 80),
        itemCount: _entries.length,
        itemBuilder: (context, index) {
          final entry = _entries[index];
          final isDir = entry.isDirectory;
          return _buildEntryTile(entry, isDir);
        },
      ),
    );
  }

  Widget _buildEntryTile(SftpEntry entry, bool isDir) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Container(
        decoration: BoxDecoration(
          color: AppConstants.surfaceDark.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white.withValues(alpha: 0.04)),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: isDir ? () => _navigateToDir(entry.filename) : null,
            onLongPress: () => _showEntryMenu(entry),
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: isDir
                          ? const Color(0xFF448AFF).withValues(alpha: 0.1)
                          : Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      isDir
                          ? Icons.folder_rounded
                          : Icons.insert_drive_file_rounded,
                      size: 18,
                      color: isDir
                          ? const Color(0xFF448AFF)
                          : Colors.white.withValues(alpha: 0.4),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.filename,
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 13,
                            color: Colors.white.withValues(alpha: 0.85),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (entry.size > 0) ...[
                          const SizedBox(height: 2),
                          Text(
                            _formatSize(entry.size),
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              color: Colors.white.withValues(alpha: 0.35),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (!isDir)
                    Icon(
                      Icons.chevron_right,
                      size: 16,
                      color: Colors.white.withValues(alpha: 0.15),
                    ),
                ],
              ),
            ),
          ),
        ),
      ).animate().fadeIn(duration: 200.ms, curve: Curves.easeOut),
    );
  }

  void _showEntryMenu(SftpEntry entry) {
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            decoration: BoxDecoration(
              color: AppConstants.surfaceDark.withValues(alpha: 0.9),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20),
              ),
              border: Border(
                top: BorderSide(
                  color: AppConstants.primaryGreen.withValues(alpha: 0.15),
                ),
              ),
            ),
            child: SafeArea(
              child: Material(
                color: Colors.transparent,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 8,
                      ),
                      child: Text(
                        entry.filename,
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const Divider(color: Colors.white10),
                    if (!entry.isDirectory)
                      ListTile(
                        leading: const Icon(
                          Icons.download_rounded,
                          color: AppConstants.primaryGreen,
                        ),
                        title: Text(
                          'Download to Clipboard',
                          style: GoogleFonts.inter(),
                        ),
                        onTap: () {
                          Navigator.pop(context);
                          _downloadEntry(entry);
                        },
                      ),
                    ListTile(
                      leading: const Icon(
                        Icons.edit_rounded,
                        color: Color(0xFF448AFF),
                      ),
                      title: Text('Rename', style: GoogleFonts.inter()),
                      onTap: () {
                        Navigator.pop(context);
                        _renameEntry(entry);
                      },
                    ),
                    ListTile(
                      leading: const Icon(
                        Icons.delete_outline_rounded,
                        color: Colors.red,
                      ),
                      title: Text('Delete', style: GoogleFonts.inter()),
                      onTap: () {
                        Navigator.pop(context);
                        _deleteEntry(entry);
                      },
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}
