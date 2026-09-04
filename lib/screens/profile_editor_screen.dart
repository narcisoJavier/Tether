import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:uuid/uuid.dart';

import '../models/connection_profile.dart';
import '../services/key_service.dart';
import '../services/profile_storage_service.dart';
import '../services/ssh_service.dart';
import '../services/tailscale_provider.dart';
import '../services/tailscale_ssh_socket.dart';
import '../utils/constants.dart';
import '../widgets/gradient_scaffold.dart';

/// Screen for creating or editing a connection profile matching the HTML design spec.
class ProfileEditorScreen extends ConsumerStatefulWidget {
  const ProfileEditorScreen({super.key, this.profileId});

  /// If null, this is a new profile; otherwise editing an existing one.
  final String? profileId;

  @override
  ConsumerState<ProfileEditorScreen> createState() =>
      _ProfileEditorScreenState();
}

class _ProfileEditorScreenState extends ConsumerState<ProfileEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  final _labelController = TextEditingController();
  final _hostController = TextEditingController();
  final _portController = TextEditingController(text: '22');
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  AuthType _authType = AuthType.password;
  String? _selectedKeyId;
  int _colorIndex = 0;
  bool _isTesting = false;
  bool _obscurePassword = true;
  final _authKeyController = TextEditingController();
  ConnectionMethod _connectionMethod = ConnectionMethod.direct;
  String _environment = 'PROD';

  bool get _isEditing => widget.profileId != null;
  ConnectionProfile? _existingProfile;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_isEditing) _loadExistingProfile();
      _loadAuthKey();
    });
  }

  Future<void> _loadExistingProfile() async {
    final storage = ref.read(profileStorageProvider);
    _existingProfile = storage.getProfile(widget.profileId!);
    if (_existingProfile == null) {
      context.pop();
      return;
    }

    setState(() {
      _labelController.text = _existingProfile!.label;
      _hostController.text = _existingProfile!.host;
      _portController.text = _existingProfile!.port.toString();
      _usernameController.text = _existingProfile!.username;
      _authType = _existingProfile!.authType;
      _selectedKeyId = _existingProfile!.keyId;
      _colorIndex = _existingProfile!.colorIndex;
      _connectionMethod = _existingProfile!.connectionMethod;
      _environment = _existingProfile!.effectiveEnvironment.toUpperCase();
    });

    final stored = await ref
        .read(profileStorageProvider)
        .getPassword(_existingProfile!.id);
    final legacyPassword = _existingProfile!.password;
    final effectivePassword = stored ?? legacyPassword;
    if (effectivePassword != null && effectivePassword.isNotEmpty && mounted) {
      setState(() => _passwordController.text = effectivePassword);
    }
  }

  Future<void> _loadAuthKey() async {
    final ts = ref.read(tailscaleServiceProvider);
    final key = await ts.readAuthKey();
    if (key != null && key.isNotEmpty && mounted) {
      setState(() => _authKeyController.text = key);
    }
  }

  @override
  void dispose() {
    _labelController.dispose();
    _hostController.dispose();
    _portController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _authKeyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final keys = ref.watch(keyServiceProvider).listKeys();

    return GradientScaffold(
      appBar: GlassAppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          onPressed: () => context.pop(),
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFF1C2027),
                shape: BoxShape.circle,
                border: Border.all(
                  color: const Color(0xFF00CCFF).withValues(alpha: 0.3),
                ),
              ),
              child: const Icon(
                Icons.terminal_rounded,
                size: 16,
                color: Color(0xFF00CCFF),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'PROFILE',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                letterSpacing: 1.5,
              ),
            ),
          ],
        ),
        actions: [
          if (_isEditing)
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded, color: Colors.red),
              tooltip: 'Delete',
              onPressed: _deleteProfile,
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
          children: [
            // ── Page Header ──
            Text(
              _isEditing ? 'Edit Node' : 'New Node',
              style: GoogleFonts.hankenGrotesk(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Configure connection parameters for a new SSH target.',
              style: GoogleFonts.inter(
                fontSize: 14,
                color: const Color(0xFF8E8E93),
              ),
            ),
            const SizedBox(height: 20),

            // ── Card 1: Connection Parameters ──
            _buildCardContainer(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSectionHeader(Icons.dns_rounded, 'CONNECTION'),
                  const SizedBox(height: 16),

                  // Profile Label
                  _buildInputLabel('Profile Label'),
                  const SizedBox(height: 6),
                  _buildTextField(
                    controller: _labelController,
                    hintText: 'e.g., Production DB',
                    validator: (v) =>
                        v?.trim().isEmpty ?? true ? 'Required' : null,
                  ),
                  const SizedBox(height: 14),

                  // Host / IP & Port Row
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 3,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildInputLabel('Host / IP'),
                            const SizedBox(height: 6),
                            _buildTextField(
                              controller: _hostController,
                              hintText: '192.168.1.100',
                              validator: (v) =>
                                  v?.trim().isEmpty ?? true ? 'Required' : null,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 1,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildInputLabel('Port'),
                            const SizedBox(height: 6),
                            _buildTextField(
                              controller: _portController,
                              hintText: '22',
                              textAlign: TextAlign.center,
                              keyboardType: TextInputType.number,
                              validator: (v) {
                                final p = int.tryParse(v ?? '');
                                if (p == null || p < 1 || p > 65535) {
                                  return 'Invalid';
                                }
                                return null;
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Username
                  _buildInputLabel('Username'),
                  const SizedBox(height: 6),
                  _buildTextField(
                    controller: _usernameController,
                    hintText: 'root',
                    validator: (v) =>
                        v?.trim().isEmpty ?? true ? 'Required' : null,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ── Card 2: Authentication Method ──
            _buildCardContainer(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildSectionHeader(Icons.vpn_key_rounded, 'AUTH METHOD'),
                      // Segmented Control
                      Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10131B),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildAuthSegment(
                              label: 'PASSWORD',
                              isSelected: _authType == AuthType.password,
                              onTap: () =>
                                  setState(() => _authType = AuthType.password),
                            ),
                            _buildAuthSegment(
                              label: 'KEY PAIR',
                              isSelected: _authType == AuthType.publicKey,
                              onTap: () => setState(
                                () => _authType = AuthType.publicKey,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  if (_authType == AuthType.password) ...[
                    _buildInputLabel('Password'),
                    const SizedBox(height: 6),
                    _buildTextField(
                      controller: _passwordController,
                      hintText: '••••••••••••',
                      obscureText: _obscurePassword,
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_rounded
                              : Icons.visibility_off_rounded,
                          color: const Color(0xFF8E8E93),
                          size: 20,
                        ),
                        onPressed: () => setState(
                          () => _obscurePassword = !_obscurePassword,
                        ),
                      ),
                    ),
                  ] else ...[
                    _buildInputLabel('SSH Key'),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10131B),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.05),
                        ),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _selectedKeyId,
                          hint: Text(
                            keys.isEmpty
                                ? 'No keys — generate one first'
                                : 'Select SSH Key',
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 12,
                              color: const Color(0xFF8E8E93),
                            ),
                          ),
                          dropdownColor: const Color(0xFF181C23),
                          isExpanded: true,
                          icon: const Icon(
                            Icons.keyboard_arrow_down_rounded,
                            color: Color(0xFF8E8E93),
                          ),
                          items: keys
                              .map(
                                (k) => DropdownMenuItem(
                                  value: k.id,
                                  child: Text(
                                    k.fingerprint,
                                    style: GoogleFonts.jetBrainsMono(
                                      fontSize: 12,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (val) =>
                              setState(() => _selectedKeyId = val),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ── Row 3: Environment Tag & Accent Color (2-Column Grid) ──
            Row(
              children: [
                // Left Card: ENV TAG
                Expanded(
                  child: _buildCardContainer(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'ENV TAG',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 6,
                          runSpacing: 8,
                          children: ['PROD', 'STG', 'DEV'].map((env) {
                            final isSel = _environment == env;
                            return GestureDetector(
                              onTap: () => setState(() => _environment = env),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: isSel
                                      ? const Color(
                                          0xFF32D74B,
                                        ).withValues(alpha: 0.12)
                                      : const Color(0xFF10131B),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: isSel
                                        ? const Color(
                                            0xFF32D74B,
                                          ).withValues(alpha: 0.5)
                                        : const Color(0xFF414754),
                                    width: isSel ? 1.0 : 0.8,
                                  ),
                                ),
                                child: Text(
                                  env,
                                  style: GoogleFonts.jetBrainsMono(
                                    fontSize: 11,
                                    fontWeight: isSel
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                    color: isSel
                                        ? const Color(0xFF32D74B)
                                        : const Color(0xFF8E8E93),
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),

                // Right Card: ACCENT
                Expanded(
                  child: _buildCardContainer(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'ACCENT',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: List.generate(ProfileColors.palette.length, (idx) {
                            final c = ProfileColors.palette[idx];
                            final isSel = _colorIndex == idx;
                            return GestureDetector(
                              onTap: () => setState(() => _colorIndex = idx),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 180),
                                width: 24,
                                height: 24,
                                decoration: BoxDecoration(
                                  color: c,
                                  shape: BoxShape.circle,
                                  boxShadow: isSel
                                      ? [
                                          BoxShadow(
                                            color: c.withValues(alpha: 0.5),
                                            blurRadius: 8,
                                            spreadRadius: 2,
                                          ),
                                        ]
                                      : [],
                                  border: isSel
                                      ? Border.all(
                                          color: Colors.white,
                                          width: 2,
                                        )
                                      : null,
                                ),
                              ),
                            );
                          }),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // ── Card 4: Network Routing ──
            _buildCardContainer(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Route via Tailscale',
                        style: GoogleFonts.inter(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Use mesh network overlay',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 12,
                          color: const Color(0xFF8E8E93),
                        ),
                      ),
                    ],
                  ),
                  Switch(
                    value: _connectionMethod == ConnectionMethod.tailscale,
                    activeThumbColor: const Color(0xFF00CCFF),
                    activeTrackColor: const Color(
                      0xFF00CCFF,
                    ).withValues(alpha: 0.25),
                    inactiveThumbColor: const Color(0xFF8E8E93),
                    inactiveTrackColor: const Color(0xFF10131B),
                    onChanged: (val) {
                      setState(() {
                        _connectionMethod = val
                            ? ConnectionMethod.tailscale
                            : ConnectionMethod.direct;
                      });
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // ── Action Buttons ──
            // Primary Save Button
            GestureDetector(
              onTap: _save,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFF00CCFF),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF00CCFF).withValues(alpha: 0.35),
                      blurRadius: 15,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.save_rounded,
                      size: 20,
                      color: Color(0xFF001B3E),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _isEditing ? 'Update Profile' : 'Save Profile',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF001B3E),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Secondary Test Connection Button
            GestureDetector(
              onTap: _isTesting ? null : _testConnection,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: const Color(0xFF00CCFF).withValues(alpha: 0.4),
                    width: 1.0,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _isTesting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Color(0xFF00CCFF),
                            ),
                          )
                        : const Icon(
                            Icons.cable_rounded,
                            size: 20,
                            color: Color(0xFF00CCFF),
                          ),
                    const SizedBox(width: 8),
                    Text(
                      _isTesting ? 'Testing Connection…' : 'Test Connection',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF00CCFF),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCardContainer({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1C2027),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
          width: 0.8,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _buildSectionHeader(IconData icon, String title) {
    return Row(
      children: [
        Icon(icon, size: 16, color: const Color(0xFF00CCFF)),
        const SizedBox(width: 8),
        Text(
          title,
          style: GoogleFonts.jetBrainsMono(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: const Color(0xFF00CCFF),
            letterSpacing: 1.5,
          ),
        ),
      ],
    );
  }

  Widget _buildInputLabel(String label) {
    return Text(
      label,
      style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFFC0C6D6)),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hintText,
    bool obscureText = false,
    TextAlign textAlign = TextAlign.start,
    TextInputType? keyboardType,
    Widget? suffixIcon,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      textAlign: textAlign,
      keyboardType: keyboardType,
      style: GoogleFonts.jetBrainsMono(fontSize: 13, color: Colors.white),
      validator: validator,
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: GoogleFonts.jetBrainsMono(
          fontSize: 12,
          color: const Color(0xFF8E8E93),
        ),
        filled: true,
        fillColor: const Color(0xFF10131B),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: const Color(0xFF00CCFF).withValues(alpha: 0.5),
            width: 1.0,
          ),
        ),
        suffixIcon: suffixIcon,
      ),
    );
  }

  Widget _buildAuthSegment({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF262A32) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: GoogleFonts.jetBrainsMono(
            fontSize: 10,
            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
            color: isSelected ? Colors.white : const Color(0xFF8E8E93),
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }

  Future<void> _testConnection() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isTesting = true);
    final testService = SshService();

    try {
      final profile = _buildProfile();

      TailscaleSSHSocket? sock;
      if (_connectionMethod == ConnectionMethod.tailscale) {
        var ts = ref.read(tailscaleServiceProvider);
        var conn = await ts.dial(
          profile.host,
          profile.port,
          timeout: const Duration(seconds: 10),
        );
        sock = TailscaleSSHSocket(conn);
      } else {
        sock = null;
      }

      String? passwordToUse = _passwordController.text;
      if (passwordToUse.isEmpty && _existingProfile != null) {
        passwordToUse = await ref
            .read(profileStorageProvider)
            .getPassword(_existingProfile!.id);
      }

      String? privateKey;
      if (_authType != AuthType.password && _selectedKeyId != null) {
        privateKey = await ref
            .read(keyServiceProvider)
            .getPrivateKey(_selectedKeyId!);
      }

      await testService.testConnection(
        profile: profile,
        privateKey: privateKey,
        password: (passwordToUse != null && passwordToUse.isNotEmpty)
            ? passwordToUse
            : null,
        socket: sock,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF181C23),
            content: Row(
              children: [
                const Icon(
                  Icons.check_circle_rounded,
                  color: AppConstants.primaryGreen,
                ),
                const SizedBox(width: 8),
                Text(
                  'Connection successful!',
                  style: GoogleFonts.jetBrainsMono(color: Colors.white),
                ),
              ],
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF181C23),
            content: Row(
              children: [
                const Icon(Icons.error_outline_rounded, color: Colors.red),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    e.toString(),
                    style: GoogleFonts.jetBrainsMono(color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        );
      }
    } finally {
      await testService.disconnect();
      testService.dispose();
      if (mounted) {
        setState(() => _isTesting = false);
      }
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final profile = _buildProfile();
    final storage = ref.read(profileStorageProvider);
    await storage.saveProfile(profile);

    if (_passwordController.text.isNotEmpty) {
      await storage.savePassword(profile.id, _passwordController.text);
    } else {
      await storage.deletePassword(profile.id);
    }

    if (profile.connectionMethod == ConnectionMethod.tailscale &&
        _authKeyController.text.trim().isNotEmpty) {
      final ts = ref.read(tailscaleServiceProvider);
      await ts.storeAuthKey(_authKeyController.text.trim());
      unawaited(ts.up(authKey: _authKeyController.text.trim()));
    }

    if (mounted) {
      context.pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF181C23),
          content: Text(
            _isEditing ? 'Connection updated' : 'Connection saved',
            style: GoogleFonts.jetBrainsMono(color: Colors.white),
          ),
        ),
      );
    }
  }

  ConnectionProfile _buildProfile() {
    return ConnectionProfile(
      id: _existingProfile?.id ?? const Uuid().v4(),
      label: _labelController.text.trim(),
      host: _hostController.text.trim(),
      port: int.parse(_portController.text.trim()),
      username: _usernameController.text.trim(),
      authType: _authType,
      password: null,
      keyId: _selectedKeyId,
      colorIndex: _colorIndex,
      connectionMethod: _connectionMethod,
      environment: _environment,
      createdAt: _existingProfile?.createdAt,
      lastConnectionSuccess: _existingProfile?.lastConnectionSuccess ?? false,
      tunnels: _existingProfile?.tunnels,
    );
  }

  Future<void> _deleteProfile() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF181C23),
        title: Text(
          'Delete Connection',
          style: GoogleFonts.jetBrainsMono(color: Colors.white),
        ),
        content: Text(
          'Delete "${_labelController.text.trim()}"? This cannot be undone.',
          style: GoogleFonts.jetBrainsMono(color: const Color(0xFF8E8E93)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'Cancel',
              style: GoogleFonts.jetBrainsMono(color: Colors.white70),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text('Delete', style: GoogleFonts.jetBrainsMono()),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final storage = ref.read(profileStorageProvider);
      await storage.deleteProfile(widget.profileId!);
      if (mounted) context.pop();
    }
  }
}
