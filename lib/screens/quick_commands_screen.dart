import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:uuid/uuid.dart';

import '../models/connection_profile.dart';
import '../models/quick_command.dart';
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
import '../utils/agent_presets.dart';
import '../utils/constants.dart';
import '../widgets/agent_brand_mark.dart';
import '../widgets/connection_card.dart';

/// Screen for managing and executing quick commands.
class QuickCommandsScreen extends ConsumerStatefulWidget {
  const QuickCommandsScreen({super.key});

  @override
  ConsumerState<QuickCommandsScreen> createState() =>
      _QuickCommandsScreenState();
}

class _QuickCommandsScreenState extends ConsumerState<QuickCommandsScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  PresetCategory? _categoryFilter;
  bool _isEditingLayout = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final storage = ref.watch(profileStorageProvider);
    final commands = storage.listCommands();
    final profiles = storage.listProfiles();
    final query = _searchQuery.trim().toLowerCase();
    final filteredPresets = AgentPresets.all.where((preset) {
      final matchesCategory =
          _categoryFilter == null || preset.category == _categoryFilter;
      final matchesQuery =
          query.isEmpty ||
          preset.label.toLowerCase().contains(query) ||
          preset.command.toLowerCase().contains(query) ||
          preset.description.toLowerCase().contains(query);
      return matchesCategory && matchesQuery;
    }).toList();
    final filteredCommands = commands.where((command) {
      if (query.isEmpty) return true;
      return command.label.toLowerCase().contains(query) ||
          command.command.toLowerCase().contains(query);
    }).toList();
    final orderedCommands = ref
        .read(quickCommandLayoutProvider)
        .orderItems(filteredCommands, _savedCommandKey);

    return Scaffold(
      backgroundColor: AppConstants.backgroundDark,
      appBar: AppBar(
        title: Text(
          'COMMAND DECK',
          style: GoogleFonts.jetBrainsMono(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.1,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(
              _isEditingLayout
                  ? Icons.check_rounded
                  : Icons.dashboard_customize_rounded,
              size: 20,
            ),
            color: _isEditingLayout
                ? AppConstants.primaryGreen
                : AppConstants.accentBlue,
            tooltip: _isEditingLayout ? 'Done rearranging' : 'Arrange commands',
            onPressed: () => setState(() {
              _isEditingLayout = !_isEditingLayout;
            }),
          ),
          IconButton(
            icon: const Icon(Icons.add_rounded, size: 21),
            tooltip: 'Add command',
            onPressed: () => _showCommandEditor(),
          ),
          IconButton(
            icon: const Icon(Icons.tune_rounded, size: 20),
            tooltip: 'Edit Presets',
            onPressed: () => context.push('/presets'),
          ),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(painter: _CommandDeckPainter()),
            ),
          ),
          ListView(
            padding: EdgeInsets.fromLTRB(
              12,
              8,
              12,
              128 + MediaQuery.paddingOf(context).bottom,
            ),
            children: [
              _buildSearchBar(),
              const SizedBox(height: 8),
              _buildCategoryFilters(),
              if (_isEditingLayout) ...[
                const SizedBox(height: 8),
                _buildLayoutHint(),
              ],
              const SizedBox(height: 12),
              if (_searchQuery.trim().isEmpty && _categoryFilter == null)
                _buildCommandDeck(profiles)
              else
                _buildSearchResults(filteredPresets, profiles),
              if (orderedCommands.isNotEmpty) ...[
                const SizedBox(height: 18),
                _buildSavedCommandsHeader(orderedCommands.length),
                ...orderedCommands.map((command) {
                  final profile = command.profileId == null
                      ? null
                      : profiles
                            .where((p) => p.id == command.profileId)
                            .firstOrNull;
                  return _buildManagedSavedCommandCard(command, profile);
                }),
              ],
              if (commands.isEmpty && _searchQuery.trim().isEmpty)
                _buildEmptyState(),
              if (filteredPresets.isEmpty && orderedCommands.isEmpty)
                _buildNoResultsState(),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return TextField(
      controller: _searchController,
      onChanged: (value) => setState(() => _searchQuery = value),
      style: GoogleFonts.inter(fontSize: 13, color: Colors.white),
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: 'Search commands...',
        hintStyle: GoogleFonts.inter(
          fontSize: 13,
          color: Colors.white.withValues(alpha: 0.35),
        ),
        prefixIcon: Icon(
          Icons.search_rounded,
          size: 18,
          color: Colors.white.withValues(alpha: 0.45),
        ),
        suffixIcon: _searchQuery.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.close_rounded, size: 17),
                color: Colors.white.withValues(alpha: 0.5),
                onPressed: () {
                  _searchController.clear();
                  setState(() => _searchQuery = '');
                },
              ),
        filled: true,
        fillColor: const Color(0xFF0B0F16).withValues(alpha: 0.92),
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(
            color: AppConstants.accentBlue,
            width: 1,
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryFilters() {
    final filters = <({String label, PresetCategory? category})>[
      (label: 'ALL', category: null),
      (label: 'AI', category: PresetCategory.agent),
      (label: 'DEV', category: PresetCategory.devtool),
      (label: 'SYSTEM', category: PresetCategory.system),
    ];

    return SizedBox(
      height: 30,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: filters.length,
        separatorBuilder: (_, _) => const SizedBox(width: 7),
        itemBuilder: (context, index) {
          final filter = filters[index];
          final selected = _categoryFilter == filter.category;
          return ChoiceChip(
            label: Text(filter.label),
            selected: selected,
            onSelected: (_) => setState(() {
              _categoryFilter = filter.category;
            }),
            labelStyle: GoogleFonts.jetBrainsMono(
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
              color: selected
                  ? Colors.white
                  : Colors.white.withValues(alpha: 0.45),
            ),
            backgroundColor: const Color(0xFF111722).withValues(alpha: 0.8),
            selectedColor: AppConstants.accentBlue.withValues(alpha: 0.22),
            side: BorderSide(
              color: selected
                  ? AppConstants.accentBlue.withValues(alpha: 0.7)
                  : Colors.white.withValues(alpha: 0.08),
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(9),
            ),
            showCheckmark: false,
            padding: const EdgeInsets.symmetric(horizontal: 4),
          );
        },
      ),
    );
  }

  Widget _buildLayoutHint() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: AppConstants.accentBlue.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: AppConstants.accentBlue.withValues(alpha: 0.22),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.touch_app_rounded,
            size: 16,
            color: AppConstants.accentBlue,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Hold and drag to reorder. Use + / − in a folder header to resize it.',
              style: GoogleFonts.inter(
                fontSize: 11,
                color: Colors.white.withValues(alpha: 0.65),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<AgentPreset> _orderedPresets(PresetCategory category) {
    final layout = ref.read(quickCommandLayoutProvider);
    final categoryName = category.name;
    final presets = AgentPresets.all
        .where(
          (preset) =>
              layout.categoryFor(_presetKey(preset), preset.category.name) ==
              categoryName,
        )
        .toList();
    return layout.orderItems(presets, (preset) => _presetKey(preset));
  }

  String _presetKey(AgentPreset preset) => 'preset:${preset.id}';

  String _savedCommandKey(QuickCommand command) => 'saved:${command.id}';

  Widget _buildPresetIcon(AgentPreset preset, double size) {
    if (preset.category == PresetCategory.agent) {
      return AgentBrandMark(
        presetId: preset.id,
        color: preset.color,
        size: size,
      );
    }
    return Icon(preset.icon, size: size, color: preset.color);
  }

  Widget _buildCommandDeck(List<ConnectionProfile> profiles) {
    final agentPresets = _orderedPresets(PresetCategory.agent);
    final devPresets = _orderedPresets(PresetCategory.devtool);
    final systemPresets = _orderedPresets(PresetCategory.system);

    return Column(
      children: [
        _buildCategoryPanel(
          title: 'AI AGENTS',
          category: PresetCategory.agent,
          presets: agentPresets,
          profiles: profiles,
          color: const Color(0xFF00B8FF),
        ),
        const SizedBox(height: 8),
        _buildCategoryPanel(
          title: 'DEV TOOLS',
          category: PresetCategory.devtool,
          presets: devPresets,
          profiles: profiles,
          color: const Color(0xFF8D7BFF),
        ),
        const SizedBox(height: 8),
        _buildCategoryPanel(
          title: 'SYSTEM TOOLS',
          category: PresetCategory.system,
          presets: systemPresets,
          profiles: profiles,
          color: const Color(0xFF00C7BE),
        ),
      ],
    );
  }

  Widget _buildCategoryPanel({
    required String title,
    required PresetCategory category,
    required List<AgentPreset> presets,
    required List<ConnectionProfile> profiles,
    required Color color,
  }) {
    final layout = ref.read(quickCommandLayoutProvider);
    final requestedRows = layout.folderRows(category.name);
    final availableRows = presets.isEmpty ? 1 : (presets.length + 1) ~/ 2;
    final maxRows = availableRows > 4 ? 4 : availableRows;
    final rows = requestedRows > maxRows ? maxRows : requestedRows;
    final visible = presets.take(rows * 2).toList();
    return Container(
      padding: const EdgeInsets.fromLTRB(9, 9, 9, 8),
      decoration: BoxDecoration(
        color: const Color(0xFF171C25).withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.05),
            blurRadius: 18,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: Colors.white.withValues(alpha: 0.8),
                    letterSpacing: 0.45,
                  ),
                ),
              ),
              if (_isEditingLayout) ...[
                _buildFolderResizeButton(
                  icon: Icons.remove_rounded,
                  enabled: rows > 1,
                  onPressed: () => _resizeFolder(category, rows - 1),
                ),
                Text(
                  '$rows×',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 9,
                    color: Colors.white.withValues(alpha: 0.45),
                  ),
                ),
                _buildFolderResizeButton(
                  icon: Icons.add_rounded,
                  enabled: rows < maxRows,
                  onPressed: () => _resizeFolder(category, rows + 1),
                ),
              ],
              GestureDetector(
                onTap: () => setState(() => _categoryFilter = category),
                child: Icon(
                  Icons.grid_view_rounded,
                  size: 13,
                  color: color.withValues(alpha: 0.65),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, constraints) {
              final tileWidth = (constraints.maxWidth - 7) / 2;
              return Wrap(
                spacing: 7,
                runSpacing: 7,
                children: visible
                    .map(
                      (preset) => SizedBox(
                        width: tileWidth,
                        height: 54,
                        child: _buildPresetTile(preset, profiles, category),
                      ),
                    )
                    .toList(),
              );
            },
          ),
          if (presets.length > visible.length) ...[
            const SizedBox(height: 4),
            _buildDeckMoreButton(
              label: '+${presets.length - visible.length} MORE',
              category: category,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFolderResizeButton({
    required IconData icon,
    required bool enabled,
    required VoidCallback onPressed,
  }) {
    return IconButton(
      onPressed: enabled ? onPressed : null,
      icon: Icon(icon, size: 14),
      color: Colors.white.withValues(alpha: enabled ? 0.65 : 0.18),
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
      tooltip: enabled ? 'Resize folder' : null,
    );
  }

  void _resizeFolder(PresetCategory category, int rows) {
    final layout = ref.read(quickCommandLayoutProvider);
    layout.setFolderRows(category.name, rows);
    unawaited(layout.persist());
    setState(() {});
  }

  Widget _buildPresetTile(
    AgentPreset preset,
    List<ConnectionProfile> profiles,
    PresetCategory category,
  ) {
    final key = _presetKey(preset);
    final tile = Material(
      color: const Color(0xFF0D121B),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: _isEditingLayout ? null : () => _launchPreset(preset, profiles),
        borderRadius: BorderRadius.circular(10),
        splashColor: preset.color.withValues(alpha: 0.18),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 5),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildPresetIcon(preset, 17),
              const SizedBox(height: 3),
              Text(
                preset.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 8,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withValues(alpha: 0.68),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return DragTarget<String>(
      onWillAcceptWithDetails: (details) =>
          details.data.startsWith('preset:') && details.data != key,
      onAcceptWithDetails: (details) =>
          _reorderPreset(details.data, key, category),
      builder: (context, candidateData, rejectedData) {
        return LongPressDraggable<String>(
          data: key,
          onDragStarted: () {
            if (!_isEditingLayout) {
              setState(() => _isEditingLayout = true);
            }
          },
          feedback: Material(
            color: Colors.transparent,
            child: SizedBox(width: 82, height: 54, child: tile),
          ),
          childWhenDragging: Opacity(opacity: 0.22, child: tile),
          child: Transform.rotate(
            angle: _isEditingLayout
                ? (candidateData.isNotEmpty ? 0.025 : 0.012)
                : 0,
            child: tile,
          ),
        );
      },
    );
  }

  void _reorderPreset(
    String sourceKey,
    String targetKey,
    PresetCategory targetCategory,
  ) {
    if (sourceKey == targetKey) return;

    final sourcePreset = AgentPresets.all
        .where((preset) => _presetKey(preset) == sourceKey)
        .firstOrNull;
    if (sourcePreset == null) return;

    final layout = ref.read(quickCommandLayoutProvider);
    final sourceCategoryName = layout.categoryFor(
      sourceKey,
      sourcePreset.category.name,
    );
    final targetKeys = _orderedPresets(
      targetCategory,
    ).map(_presetKey).where((key) => key != sourceKey).toList();
    final targetIndex = targetKeys.indexOf(targetKey);
    if (targetIndex < 0) return;

    targetKeys.insert(targetIndex, sourceKey);
    layout.setCategory(sourceKey, targetCategory.name);
    unawaited(layout.saveCategoryOrder(targetKeys, targetCategory.name));

    if (sourceCategoryName != targetCategory.name) {
      final sourceCategory = PresetCategory.values.firstWhere(
        (value) => value.name == sourceCategoryName,
        orElse: () => sourcePreset.category,
      );
      final sourceKeys = _orderedPresets(
        sourceCategory,
      ).map(_presetKey).where((key) => key != sourceKey).toList();
      unawaited(layout.saveCategoryOrder(sourceKeys, sourceCategoryName));
    }
    setState(() {});
  }

  Widget _buildDeckMoreButton({
    required String label,
    required PresetCategory category,
  }) {
    return OutlinedButton(
      onPressed: () => setState(() => _categoryFilter = category),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(28),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: Text(
        label,
        style: GoogleFonts.jetBrainsMono(
          fontSize: 8,
          fontWeight: FontWeight.w800,
          color: Colors.white.withValues(alpha: 0.45),
        ),
      ),
    );
  }

  Widget _buildSearchResults(
    List<AgentPreset> presets,
    List<ConnectionProfile> profiles,
  ) {
    if (presets.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionLabel('PRESET RESULTS', presets.length),
        const SizedBox(height: 8),
        ...presets.map(
          (preset) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _buildSearchResultTile(preset, profiles),
          ),
        ),
      ],
    );
  }

  Widget _buildSearchResultTile(
    AgentPreset preset,
    List<ConnectionProfile> profiles,
  ) {
    return Material(
      color: const Color(0xFF171C25).withValues(alpha: 0.95),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: () => _launchPreset(preset, profiles),
        borderRadius: BorderRadius.circular(10),
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor: preset.color.withValues(alpha: 0.13),
            child: _buildPresetIcon(preset, 18),
          ),
          title: Text(
            preset.label,
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          subtitle: Text(
            '\$ ${preset.command}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.jetBrainsMono(
              fontSize: 11,
              color: Colors.white.withValues(alpha: 0.45),
            ),
          ),
          trailing: Icon(Icons.play_arrow_rounded, color: preset.color),
        ),
      ),
    );
  }

  Widget _buildSavedCommandsHeader(int count) {
    return _buildSectionLabel('SAVED COMMANDS', count);
  }

  Widget _buildSectionLabel(String label, int count) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          Text(
            label,
            style: GoogleFonts.jetBrainsMono(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
              color: Colors.white.withValues(alpha: 0.75),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: AppConstants.accentAmber.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Text(
              '$count',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 9,
                fontWeight: FontWeight.w800,
                color: AppConstants.accentAmber,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoResultsState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 44, horizontal: 24),
      child: Column(
        children: [
          Icon(
            Icons.search_off_rounded,
            size: 38,
            color: Colors.white.withValues(alpha: 0.2),
          ),
          const SizedBox(height: 10),
          Text(
            'No commands found',
            style: GoogleFonts.inter(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Colors.white.withValues(alpha: 0.55),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            'Try another search or create a custom command.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 12,
              color: Colors.white.withValues(alpha: 0.3),
            ),
          ),
        ],
      ),
    );
  }

  // ── Info banner ──────────────────────────────────────────────────

  // Retained for the legacy layout migration path.
  // ignore: unused_element
  Widget _buildInfoBanner() {
    return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFFFAB40).withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFFFFAB40).withValues(alpha: 0.15),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFAB40).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.flash_on_rounded,
                    size: 18,
                    color: Color(0xFFFFAB40),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Save commands you run often for one-tap execution, '
                    'or tap a preset below to get started.',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.55),
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        )
        .animate()
        .fadeIn(duration: 400.ms, curve: Curves.easeOut)
        .slideY(begin: -0.05, end: 0, duration: 350.ms, curve: Curves.easeOut);
  }

  // ── Presets section ──────────────────────────────────────────────

  // Retained for the legacy layout migration path.
  // ignore: unused_element
  Widget _buildPresetsSection(ProfileStorageService storage) {
    final profiles = storage.listProfiles();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Text(
            'Quick Launch',
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ),
        // Agents
        _buildPresetGroup(
          label: AgentPresets.categoryLabel(PresetCategory.agent),
          presets: AgentPresets.byCategory(PresetCategory.agent),
          profiles: profiles,
        ),
        // Dev Tools
        _buildPresetGroup(
          label: AgentPresets.categoryLabel(PresetCategory.devtool),
          presets: AgentPresets.byCategory(PresetCategory.devtool),
          profiles: profiles,
        ),
        // System
        _buildPresetGroup(
          label: AgentPresets.categoryLabel(PresetCategory.system),
          presets: AgentPresets.byCategory(PresetCategory.system),
          profiles: profiles,
        ),
      ],
    );
  }

  Widget _buildPresetGroup({
    required String label,
    required List<AgentPreset> presets,
    required List<ConnectionProfile> profiles,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
          child: Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.white.withValues(alpha: 0.4),
              letterSpacing: 0.8,
            ),
          ),
        ),
        SizedBox(
          height: 96,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            itemCount: presets.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final preset = presets[index];
              return _buildPresetChip(preset, profiles);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildPresetChip(
    AgentPreset preset,
    List<ConnectionProfile> profiles,
  ) {
    return GestureDetector(
      onTap: () => _launchPreset(preset, profiles),
      child: Container(
        width: 76,
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        decoration: BoxDecoration(
          color: AppConstants.surfaceDark.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: preset.color.withValues(alpha: 0.15)),
          boxShadow: [
            BoxShadow(
              color: preset.color.withValues(alpha: 0.03),
              blurRadius: 10,
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: preset.color.withValues(alpha: 0.12),
                border: Border.all(
                  color: preset.color.withValues(alpha: 0.25),
                  width: 1,
                ),
              ),
              child: _buildPresetIcon(preset, 20),
            ),
            const SizedBox(height: 6),
            Text(
              preset.label,
              style: GoogleFonts.inter(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: Colors.white.withValues(alpha: 0.8),
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _launchPreset(
    AgentPreset preset,
    List<ConnectionProfile> profiles,
  ) async {
    if (profiles.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.info_outline, color: Color(0xFFFFAB40)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Add a connection first to launch "${preset.label}"',
                  style: GoogleFonts.inter(fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      );
      return;
    }
    await _executeCommand(
      QuickCommand(
        id: 'preset:${preset.id}',
        label: preset.label,
        command: preset.command,
        presetId: preset.id,
      ),
      persistPreset: true,
    );
  }

  Future<void> _savePresetAsCommand(
    AgentPreset preset,
    String profileId,
  ) async {
    final storage = ref.read(profileStorageProvider);
    final existing = storage.listCommands().where(
      (c) => c.presetId == preset.id && c.profileId == profileId,
    );

    // Only save if an identical one doesn't already exist.
    if (existing.isEmpty) {
      await storage.saveCommand(
        QuickCommand(
          id: const Uuid().v4(),
          label: preset.label,
          command: preset.command,
          profileId: profileId,
          presetId: preset.id,
        ),
      );
      if (mounted) setState(() {});
    }
  }

  // ── Empty state ──────────────────────────────────────────────────

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 14, 4, 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.025),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
        child: Row(
          children: [
            Icon(
              Icons.bolt_rounded,
              size: 18,
              color: const Color(0xFFFFAB40).withValues(alpha: 0.72),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'No saved commands yet. Use + to create one, or run a preset to save it.',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: Colors.white.withValues(alpha: 0.42),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Command card ─────────────────────────────────────────────────

  Widget _buildManagedSavedCommandCard(
    QuickCommand command,
    ConnectionProfile? profile,
  ) {
    final key = _savedCommandKey(command);
    final card = _buildCommandCard(
      command,
      profile,
      interactive: !_isEditingLayout,
    );

    return DragTarget<String>(
      onWillAcceptWithDetails: (details) =>
          details.data.startsWith('saved:') && details.data != key,
      onAcceptWithDetails: (details) => _reorderSavedCommand(details.data, key),
      builder: (context, candidateData, rejectedData) {
        return LongPressDraggable<String>(
          data: key,
          onDragStarted: () {
            if (!_isEditingLayout) {
              setState(() => _isEditingLayout = true);
            }
          },
          feedback: Material(
            color: Colors.transparent,
            child: SizedBox(width: 340, child: card),
          ),
          childWhenDragging: Opacity(opacity: 0.22, child: card),
          child: Transform.rotate(
            angle: _isEditingLayout
                ? (candidateData.isNotEmpty ? 0.012 : 0.006)
                : 0,
            child: card,
          ),
        );
      },
    );
  }

  void _reorderSavedCommand(String sourceKey, String targetKey) {
    if (sourceKey == targetKey) return;

    final commands = ref.read(profileStorageProvider).listCommands();
    final layout = ref.read(quickCommandLayoutProvider);
    final ordered = layout.orderItems(commands, _savedCommandKey);
    final keys = ordered.map(_savedCommandKey).toList()..remove(sourceKey);
    final targetIndex = keys.indexOf(targetKey);
    if (targetIndex < 0) return;

    keys.insert(targetIndex, sourceKey);
    unawaited(layout.saveCategoryOrder(keys, 'custom'));
    setState(() {});
  }

  Widget _buildCommandCard(
    QuickCommand cmd,
    ConnectionProfile? profile, {
    bool interactive = true,
  }) {
    final preset = cmd.presetId != null
        ? AgentPresets.byId(cmd.presetId!)
        : null;
    final accent = preset?.color ?? const Color(0xFFFFAB40);
    final icon = preset?.icon ?? Icons.play_arrow_rounded;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      child: Container(
        decoration: BoxDecoration(
          color: AppConstants.surfaceDark.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
          boxShadow: [
            BoxShadow(color: accent.withValues(alpha: 0.03), blurRadius: 16),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: interactive ? () => _executeCommand(cmd) : null,
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(11),
                      border: Border.all(
                        color: accent.withValues(alpha: 0.2),
                        width: 1,
                      ),
                    ),
                    child: preset == null
                        ? Icon(icon, color: accent, size: 22)
                        : _buildPresetIcon(preset, 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          cmd.label,
                          style: GoogleFonts.inter(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '\$ ${cmd.command}',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 11,
                            color: Colors.white.withValues(alpha: 0.4),
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 2,
                        ),
                        if (profile != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            '→ ${profile.shortLabel}',
                            style: GoogleFonts.inter(
                              fontSize: 10,
                              color: Colors.white.withValues(alpha: 0.3),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    icon: Icon(
                      Icons.more_vert_rounded,
                      color: Colors.white.withValues(alpha: 0.4),
                    ),
                    onSelected: (action) {
                      if (action == 'edit') {
                        _showCommandEditor(command: cmd);
                      } else if (action == 'delete') {
                        _deleteCommand(cmd);
                      }
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 'edit',
                        child: Row(
                          children: [
                            Icon(
                              Icons.edit_rounded,
                              size: 18,
                              color: Colors.white.withValues(alpha: 0.7),
                            ),
                            const SizedBox(width: 12),
                            const Text('Edit'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(
                              Icons.delete_outline_rounded,
                              size: 18,
                              color: Colors.red,
                            ),
                            SizedBox(width: 12),
                            Text('Delete'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Command execution ────────────────────────────────────────────

  Future<void> _executeCommand(
    QuickCommand cmd, {
    bool persistPreset = false,
  }) async {
    final storage = ref.read(profileStorageProvider);
    final profiles = storage.listProfiles();
    if (profiles.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Add a connection profile before running commands.',
            style: GoogleFonts.inter(fontSize: 13),
          ),
        ),
      );
      return;
    }

    ConnectionProfile? profile;
    if (cmd.profileId == null) {
      profile = await _showProfilePickerDialog(profiles);
    } else {
      profile = storage.getProfile(cmd.profileId!);
      if (profile == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'The linked profile no longer exists. Choose a new profile.',
              style: GoogleFonts.inter(fontSize: 13),
            ),
          ),
        );
        return;
      }
    }
    if (profile == null) return;

    if (persistPreset && cmd.presetId != null) {
      final preset = AgentPresets.byId(cmd.presetId!);
      if (preset != null) {
        await _savePresetAsCommand(preset, profile.id);
      }
    }

    final openTabs = ref
        .read(tabManagerProvider)
        .where((tab) => tab.profileId == profile!.id)
        .toList();
    final choice = await _showTabPickerDialog(cmd, profile, openTabs);
    if (choice == null) return;

    if (choice == 'run_once') {
      await _showCommandOutput(cmd, profile);
      return;
    }

    if (choice == 'new_tab') {
      ref.read(pendingTerminalTabProvider.notifier).state = TerminalTabRequest(
        profileId: profile.id,
        initialCommand: '${cmd.command}\n',
      );
      if (mounted) context.go('/terminal');
      return;
    }

    ref.read(pendingQuickCommandProvider.notifier).state = PendingTabCommand(
      tabId: choice,
      command: '${cmd.command}\n',
    );
    if (mounted) context.go('/terminal');
  }

  Future<ConnectionProfile?> _showProfilePickerDialog(
    List<ConnectionProfile> profiles,
  ) async {
    if (profiles.length == 1) return profiles.first;

    return showDialog<ConnectionProfile>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
        backgroundColor: AppConstants.surfaceDark,
        title: Text(
          'Choose a profile',
          style: GoogleFonts.inter(fontWeight: FontWeight.w600),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: profiles.length,
            itemBuilder: (context, index) {
              final profile = profiles[index];
              return ListTile(
                leading: Icon(
                  Icons.dns_rounded,
                  color: ProfileColors.get(profile.colorIndex),
                ),
                title: Text(profile.shortLabel),
                subtitle: Text(
                  '${profile.username}@${profile.host}',
                  style: GoogleFonts.jetBrainsMono(fontSize: 11),
                ),
                onTap: () => Navigator.pop(ctx, profile),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: GoogleFonts.inter()),
          ),
        ],
      ),
    );
  }

  /// Shows a dialog for selecting an existing tab, opening a new tab, or
  /// explicitly running the command without keeping a terminal session.
  Future<String?> _showTabPickerDialog(
    QuickCommand cmd,
    ConnectionProfile profile,
    List<TerminalTab> openTabs,
  ) async {
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
        backgroundColor: AppConstants.surfaceDark,
        title: Text(
          'Send to ${profile.shortLabel}',
          style: GoogleFonts.inter(fontWeight: FontWeight.w600),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '\$ ${cmd.command}',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 12,
                color: Colors.white.withValues(alpha: 0.6),
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 12),
            if (openTabs.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'No active tabs for this profile yet.',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: Colors.white.withValues(alpha: 0.45),
                  ),
                ),
              )
            else
              ...openTabs.map(
                (tab) => ListTile(
                  dense: true,
                  leading: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: tab.isConnected
                          ? AppConstants.primaryGreen
                          : Colors.white.withValues(alpha: 0.25),
                    ),
                  ),
                  title: Text(
                    tab.label,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      color: Colors.white.withValues(alpha: 0.85),
                    ),
                  ),
                  subtitle: Text(
                    tab.isConnected
                        ? 'Connected — send to this shell'
                        : 'Connecting — queue command',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: Colors.white.withValues(alpha: 0.4),
                    ),
                  ),
                  onTap: () => Navigator.pop(ctx, tab.tabId),
                ),
              ),
            // New tab option
            const Divider(color: Colors.white10),
            ListTile(
              dense: true,
              leading: const Icon(
                Icons.add_rounded,
                size: 20,
                color: AppConstants.primaryGreen,
              ),
              title: Text(
                'Open new tab',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: AppConstants.primaryGreen,
                ),
              ),
              subtitle: Text(
                'Connect and send command to a fresh session',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  color: Colors.white.withValues(alpha: 0.4),
                ),
              ),
              onTap: () => Navigator.pop(ctx, 'new_tab'),
            ),
            ListTile(
              dense: true,
              leading: const Icon(
                Icons.bolt_rounded,
                size: 20,
                color: AppConstants.accentAmber,
              ),
              title: Text(
                'Run once without terminal',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: Colors.white.withValues(alpha: 0.7),
                ),
              ),
              subtitle: Text(
                'Useful for a quick output check',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  color: Colors.white.withValues(alpha: 0.4),
                ),
              ),
              onTap: () => Navigator.pop(ctx, 'run_once'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: GoogleFonts.inter()),
          ),
        ],
      ),
    );
  }

  Future<void> _showCommandOutput(
    QuickCommand cmd,
    ConnectionProfile profile,
  ) async {
    final preset = cmd.presetId != null
        ? AgentPresets.byId(cmd.presetId!)
        : null;
    final accent = preset?.color ?? AppConstants.primaryGreen;

    await showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: SafeArea(
            top: false,
            child: DraggableScrollableSheet(
              initialChildSize: 0.6,
              minChildSize: 0.3,
              maxChildSize: 0.9,
              builder: (context, scrollController) => Container(
                decoration: BoxDecoration(
                  color: AppConstants.backgroundDark.withValues(alpha: 0.95),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(20),
                  ),
                  border: Border(
                    top: BorderSide(
                      color: accent.withValues(alpha: 0.2),
                      width: 1,
                    ),
                  ),
                ),
                child: Column(
                  children: [
                    // Header
                    Container(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                      decoration: BoxDecoration(
                        color: AppConstants.surfaceDark.withValues(alpha: 0.6),
                        border: Border(
                          bottom: BorderSide(
                            color: Colors.white.withValues(alpha: 0.05),
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: accent.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(7),
                            ),
                            child: Icon(
                              preset?.icon ?? Icons.terminal_rounded,
                              size: 16,
                              color: accent,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              '\$ ${cmd.command}',
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 12,
                                color: Colors.white,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            'on ${profile.shortLabel}',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              color: Colors.white.withValues(alpha: 0.4),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Output area
                    Expanded(
                      child: FutureBuilder<String>(
                        future: _runCommand(cmd, profile),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState ==
                              ConnectionState.waiting) {
                            return Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  CircularProgressIndicator(
                                    color: accent,
                                    strokeWidth: 2.5,
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    'Running command...',
                                    style: GoogleFonts.inter(
                                      color: Colors.white.withValues(
                                        alpha: 0.4,
                                      ),
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }

                          final result =
                              snapshot.data ?? snapshot.error.toString();

                          return Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            child: SingleChildScrollView(
                              controller: scrollController,
                              child: SelectableText(
                                result,
                                style: GoogleFonts.jetBrainsMono(
                                  fontSize: 12,
                                  color: Colors.white.withValues(alpha: 0.85),
                                  height: 1.55,
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
        ),
      ),
    );
  }

  Future<String> _runCommand(
    QuickCommand cmd,
    ConnectionProfile profile,
  ) async {
    final sshService = ref.read(sshServiceProvider(profile.id));

    TailscaleSSHSocket? sock;
    String? privateKey;
    if (profile.keyId != null) {
      privateKey = await ref
          .read(keyServiceProvider)
          .getPrivateKey(profile.keyId!);
    }

    try {
      if (profile.connectionMethod == ConnectionMethod.tailscale) {
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
      // Retrieve password from secure storage (falls back to legacy field).
      final securePassword = await ref
          .read(profileStorageProvider)
          .getPassword(profile.id);
      final effectivePassword = securePassword ?? profile.password;

      await sshService.connect(
        profile: profile,
        privateKey: privateKey,
        password: effectivePassword,
        socket: sock,
      );
      final output = await sshService.executeCommand(cmd.command);
      await sshService.disconnect();
      return output;
    } catch (e) {
      try {
        await sshService.disconnect();
      } catch (_) {}
      return 'Error: $e';
    }
  }

  // ── Command editor ───────────────────────────────────────────────

  Future<void> _showCommandEditor({QuickCommand? command}) async {
    final labelController = TextEditingController(text: command?.label ?? '');
    final commandController = TextEditingController(
      text: command?.command ?? '',
    );

    final storage = ref.read(profileStorageProvider);
    final profiles = storage.listProfiles();
    String? selectedProfileId = command?.profileId;

    final result = await showModalBottomSheet<Map<String, String?>>(
      context: context,
      useRootNavigator: true,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: StatefulBuilder(
            builder: (context, setModalState) => Container(
              decoration: BoxDecoration(
                color: AppConstants.surfaceDark.withValues(alpha: 0.95),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20),
                ),
                border: Border(
                  top: BorderSide(
                    color: AppConstants.primaryGreen.withValues(alpha: 0.15),
                  ),
                ),
              ),
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom:
                    MediaQuery.of(context).viewInsets.bottom +
                    MediaQuery.paddingOf(context).bottom +
                    20,
              ),
              child: SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Drag handle
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    Text(
                      command != null ? 'Edit Command' : 'New Quick Command',
                      style: GoogleFonts.inter(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 18),
                    TextField(
                      controller: labelController,
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: 'Label',
                        hintText: 'Start my agent',
                        prefixIcon: Icon(Icons.label_outline_rounded),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: commandController,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Command',
                        hintText: 'python ~/agents/start.py --auto',
                        prefixIcon: Icon(Icons.terminal_rounded),
                      ),
                      style: GoogleFonts.jetBrainsMono(fontSize: 13),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String?>(
                      initialValue: selectedProfileId,
                      decoration: const InputDecoration(
                        labelText: 'Target Profile',
                        prefixIcon: Icon(Icons.router_rounded),
                      ),
                      items: [
                        const DropdownMenuItem(
                          value: null,
                          child: Text('Ask at runtime'),
                        ),
                        ...profiles.map(
                          (p) => DropdownMenuItem(
                            value: p.id,
                            child: Text(p.shortLabel),
                          ),
                        ),
                      ],
                      onChanged: (v) =>
                          setModalState(() => selectedProfileId = v),
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(context, {
                          'label': labelController.text.trim(),
                          'command': commandController.text.trim(),
                          'profileId': selectedProfileId,
                        });
                      },
                      icon: const Icon(Icons.save_rounded),
                      label: Text(command != null ? 'Update' : 'Save'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    if (result == null) return;

    final label = result['label']!;
    final cmdText = result['command']!;
    if (label.isEmpty || cmdText.isEmpty) return;

    final quickCommand = QuickCommand(
      id: command?.id ?? const Uuid().v4(),
      label: label,
      command: cmdText,
      profileId: result['profileId'],
      createdAt: command?.createdAt,
      presetId: command?.presetId,
    );

    await ref.read(profileStorageProvider).saveCommand(quickCommand);

    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            command != null ? 'Command updated' : 'Command saved',
            style: GoogleFonts.inter(),
          ),
        ),
      );
    }
  }

  Future<void> _deleteCommand(QuickCommand cmd) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Command'),
        content: Text('Delete "${cmd.label}"?'),
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

    if (confirm == true) {
      await ref.read(profileStorageProvider).deleteCommand(cmd.id);
      setState(() {});
    }
  }
}

class _CommandDeckPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = const Color(0xFF64748B).withValues(alpha: 0.035)
      ..strokeWidth = 0.6;
    final dotPaint = Paint()
      ..color = const Color(0xFF64748B).withValues(alpha: 0.1);

    for (double x = 0; x <= size.width; x += 24) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (double y = 0; y <= size.height; y += 24) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
    for (double x = 12; x <= size.width; x += 24) {
      for (double y = 12; y <= size.height; y += 24) {
        canvas.drawCircle(Offset(x, y), 0.8, dotPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
