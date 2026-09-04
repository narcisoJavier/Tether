import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:uuid/uuid.dart';

import '../models/connection_profile.dart';
import '../models/tunnel_config.dart';
import '../services/profile_storage_service.dart';
import '../services/ssh_service.dart';
import '../utils/constants.dart';

/// Screen for managing SSH port-forwarding tunnels on a connection profile.
///
/// Shows configured tunnels with start/stop controls and allows adding
/// new tunnels (local, remote, dynamic SOCKS5).
class TunnelScreen extends ConsumerStatefulWidget {
  const TunnelScreen({super.key, required this.profileId});

  /// ID of the connection profile to manage tunnels for.
  final String profileId;

  @override
  ConsumerState<TunnelScreen> createState() => _TunnelScreenState();
}

class _TunnelScreenState extends ConsumerState<TunnelScreen> {
  ConnectionProfile? _profile;
  final Map<String, bool> _startingTunnels = {};

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  void _loadProfile() {
    final storage = ref.read(profileStorageProvider);
    setState(() {
      _profile = storage.getProfile(widget.profileId);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_profile == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final sshService = ref.watch(sshServiceProvider(widget.profileId));
    final activeTunnels = sshService.activeTunnels;

    return Scaffold(
      backgroundColor: AppConstants.backgroundDark,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Port Forwarding',
              style: GoogleFonts.inter(
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              _profile!.shortLabel,
              style: GoogleFonts.inter(
                fontSize: 12,
                color: Colors.white.withValues(alpha: 0.4),
              ),
            ),
          ],
        ),
        actions: [
          if (activeTunnels.isNotEmpty)
            IconButton(
              icon: const Icon(
                Icons.stop_circle_outlined,
                color: Colors.redAccent,
              ),
              tooltip: 'Stop All',
              onPressed: () => _stopAllTunnels(sshService),
            ),
        ],
      ),
      body: _profile!.tunnels.isEmpty
          ? _buildEmptyState()
          : _buildTunnelList(activeTunnels, sshService),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddTunnelSheet,
        icon: const Icon(Icons.add_rounded),
        label: Text(
          'Add Tunnel',
          style: GoogleFonts.inter(fontWeight: FontWeight.w600),
        ),
        backgroundColor: AppConstants.primaryGreen,
        foregroundColor: Colors.black,
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: const Icon(
              Icons.swap_horiz_rounded,
              size: 36,
              color: Colors.white24,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'No tunnels configured',
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.white.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Add a port forward to tunnel traffic\nthrough this SSH connection.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 13,
              color: Colors.white.withValues(alpha: 0.3),
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTunnelList(
    Map<String, ActiveTunnel> activeTunnels,
    SshService sshService,
  ) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      itemCount: _profile!.tunnels.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final tunnel = _profile!.tunnels[index];
        final isActive = activeTunnels.containsKey(tunnel.id);
        final isStarting = _startingTunnels[tunnel.id] ?? false;

        return _buildTunnelCard(tunnel, isActive, isStarting, sshService);
      },
    );
  }

  Widget _buildTunnelCard(
    TunnelConfig tunnel,
    bool isActive,
    bool isStarting,
    SshService sshService,
  ) {
    final statusColor = isActive
        ? AppConstants.primaryGreen
        : Colors.white.withValues(alpha: 0.3);
    final typeColor = _typeColor(tunnel.type);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: isActive ? 0.06 : 0.03),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isActive
              ? AppConstants.primaryGreen.withValues(alpha: 0.3)
              : Colors.white.withValues(alpha: 0.06),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 4,
          ),
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: typeColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(_typeIcon(tunnel.type), size: 20, color: typeColor),
          ),
          title: Text(
            tunnel.label.isNotEmpty ? tunnel.label : tunnel.displayString,
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.white.withValues(alpha: 0.9),
            ),
          ),
          subtitle: GestureDetector(
            onTap: () => _toggleAutoStart(tunnel),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    tunnel.displayString,
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.4),
                    ),
                  ),
                ),
                Icon(
                  tunnel.enabled
                      ? Icons.autorenew_rounded
                      : Icons.block_rounded,
                  size: 14,
                  color: tunnel.enabled
                      ? AppConstants.primaryGreen.withValues(alpha: 0.6)
                      : Colors.white.withValues(alpha: 0.2),
                ),
                const SizedBox(width: 4),
                Text(
                  tunnel.enabled ? 'Auto' : 'Manual',
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: tunnel.enabled
                        ? AppConstants.primaryGreen.withValues(alpha: 0.6)
                        : Colors.white.withValues(alpha: 0.2),
                  ),
                ),
              ],
            ),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Status indicator
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: statusColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 12),
              // Start/stop button
              if (isStarting)
                const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else if (isActive)
                IconButton(
                  icon: const Icon(Icons.stop_rounded, color: Colors.redAccent),
                  onPressed: () => _stopTunnel(tunnel.id, sshService),
                  tooltip: 'Stop',
                )
              else
                IconButton(
                  icon: const Icon(
                    Icons.play_arrow_rounded,
                    color: AppConstants.primaryGreen,
                  ),
                  onPressed: sshService.isConnected
                      ? () => _startTunnel(tunnel, sshService)
                      : null,
                  tooltip: sshService.isConnected ? 'Start' : 'Not connected',
                ),
              // Delete button
              IconButton(
                icon: Icon(
                  Icons.delete_outline_rounded,
                  color: Colors.white.withValues(alpha: 0.3),
                  size: 20,
                ),
                onPressed: () => _deleteTunnel(tunnel.id),
                tooltip: 'Delete',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _typeColor(TunnelType type) {
    switch (type) {
      case TunnelType.local:
        return const Color(0xFF4FC3F7); // cyan
      case TunnelType.remote:
        return const Color(0xFFFFB74D); // amber
      case TunnelType.dynamicSocks5:
        return const Color(0xFFBA68C8); // purple
    }
  }

  IconData _typeIcon(TunnelType type) {
    switch (type) {
      case TunnelType.local:
        return Icons.arrow_forward_rounded;
      case TunnelType.remote:
        return Icons.arrow_back_rounded;
      case TunnelType.dynamicSocks5:
        return Icons.public_rounded;
    }
  }

  Future<void> _startTunnel(TunnelConfig tunnel, SshService sshService) async {
    setState(() => _startingTunnels[tunnel.id] = true);

    try {
      switch (tunnel.type) {
        case TunnelType.local:
          await sshService.forwardLocal(
            tunnelId: tunnel.id,
            localPort: tunnel.localPort,
            remoteHost: tunnel.remoteHost,
            remotePort: tunnel.remotePort,
          );
          break;
        case TunnelType.remote:
          await sshService.forwardRemote(
            tunnelId: tunnel.id,
            remotePort: tunnel.remotePort,
            localHost: tunnel.remoteHost,
            localPort: tunnel.localPort,
          );
          break;
        case TunnelType.dynamicSocks5:
          await sshService.dynamicSocks5(
            tunnelId: tunnel.id,
            localPort: tunnel.localPort,
          );
          break;
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Tunnel failed: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _startingTunnels.remove(tunnel.id));
      }
    }
  }

  Future<void> _stopTunnel(String tunnelId, SshService sshService) async {
    await sshService.stopTunnel(tunnelId);
  }

  Future<void> _stopAllTunnels(SshService sshService) async {
    await sshService.stopAllTunnels();
  }

  Future<void> _toggleAutoStart(TunnelConfig tunnel) async {
    if (_profile == null) return;
    final updatedTunnels = _profile!.tunnels.map((t) {
      if (t.id == tunnel.id) {
        return t.copyWith(enabled: !t.enabled);
      }
      return t;
    }).toList();
    final updated = _profile!.copyWith(tunnels: updatedTunnels);
    await ref.read(profileStorageProvider).saveProfile(updated);
    _loadProfile();
  }

  Future<void> _deleteTunnel(String tunnelId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Tunnel'),
        content: const Text('Remove this tunnel configuration?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && _profile != null) {
      // Stop the tunnel if it's active
      final sshService = ref.read(sshServiceProvider(widget.profileId));
      if (sshService.activeTunnels.containsKey(tunnelId)) {
        await sshService.stopTunnel(tunnelId);
      }

      final updatedTunnels = _profile!.tunnels
          .where((t) => t.id != tunnelId)
          .toList();
      final updated = _profile!.copyWith(tunnels: updatedTunnels);
      await ref.read(profileStorageProvider).saveProfile(updated);
      _loadProfile();
    }
  }

  void _showAddTunnelSheet() {
    final labelCtrl = TextEditingController();
    final localPortCtrl = TextEditingController();
    final remoteHostCtrl = TextEditingController(text: 'localhost');
    final remotePortCtrl = TextEditingController();
    var selectedType = TunnelType.local;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      useSafeArea: true,
      backgroundColor: AppConstants.surfaceDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => SingleChildScrollView(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              24,
              24,
              24,
              MediaQuery.of(context).viewInsets.bottom + 24,
            ),
            child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'New Tunnel',
                style: GoogleFonts.inter(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 20),

              // Type selector
              Text(
                'TYPE',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Colors.white.withValues(alpha: 0.4),
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 8),
              SegmentedButton<TunnelType>(
                segments: const [
                  ButtonSegment(
                    value: TunnelType.local,
                    label: Text('Local'),
                    icon: Icon(Icons.arrow_forward_rounded, size: 16),
                  ),
                  ButtonSegment(
                    value: TunnelType.remote,
                    label: Text('Remote'),
                    icon: Icon(Icons.arrow_back_rounded, size: 16),
                  ),
                  ButtonSegment(
                    value: TunnelType.dynamicSocks5,
                    label: Text('SOCKS5'),
                    icon: Icon(Icons.public_rounded, size: 16),
                  ),
                ],
                selected: {selectedType},
                onSelectionChanged: (s) =>
                    setSheetState(() => selectedType = s.first),
              ),
              const SizedBox(height: 16),

              // Label
              TextField(
                controller: labelCtrl,
                decoration: const InputDecoration(
                  labelText: 'Label (optional)',
                  hintText: 'e.g. MySQL, Web Server',
                ),
              ),
              const SizedBox(height: 12),

              // Local port
              TextField(
                controller: localPortCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: selectedType == TunnelType.dynamicSocks5
                      ? 'SOCKS5 Port'
                      : 'Local Port',
                  hintText: 'e.g. 8080',
                ),
              ),

              // Remote host + port (not for SOCKS5)
              if (selectedType != TunnelType.dynamicSocks5) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: remoteHostCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Remote Host',
                    hintText: 'e.g. localhost, db.internal',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: remotePortCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Remote Port',
                    hintText: 'e.g. 3306, 5432',
                  ),
                ),
              ],
              const SizedBox(height: 24),

              // Save button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _saveTunnel(
                    context,
                    labelCtrl.text,
                    selectedType,
                    localPortCtrl.text,
                    remoteHostCtrl.text,
                    remotePortCtrl.text,
                  ),
                  icon: const Icon(Icons.add_rounded),
                  label: Text(
                    'Add Tunnel',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                  ),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  ).whenComplete(() {
      labelCtrl.dispose();
      localPortCtrl.dispose();
      remoteHostCtrl.dispose();
      remotePortCtrl.dispose();
    });
  }

  Future<void> _saveTunnel(
    BuildContext sheetContext,
    String label,
    TunnelType type,
    String localPortStr,
    String remoteHost,
    String remotePortStr,
  ) async {
    final localPort = int.tryParse(localPortStr);
    if (localPort == null || localPort <= 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Invalid local port')));
      return;
    }

    int remotePort = 0;
    if (type != TunnelType.dynamicSocks5) {
      remotePort = int.tryParse(remotePortStr) ?? 0;
      if (remotePort <= 0) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Invalid remote port')));
        return;
      }
    }

    final tunnel = TunnelConfig(
      id: const Uuid().v4(),
      label: label.trim(),
      type: type,
      localPort: localPort,
      remoteHost: type == TunnelType.dynamicSocks5
          ? 'localhost'
          : remoteHost.trim(),
      remotePort: remotePort,
    );

    if (_profile != null) {
      final updated = _profile!.copyWith(
        tunnels: [..._profile!.tunnels, tunnel],
      );
      await ref.read(profileStorageProvider).saveProfile(updated);
      _loadProfile();
    }

    if (sheetContext.mounted) {
      Navigator.pop(sheetContext);
    }
  }
}
