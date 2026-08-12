import 'package:flutter/material.dart';

import '../utils/constants.dart';

/// A preset agent harness or developer tool that can be launched quickly.
///
/// These presets let users one-tap launch popular AI coding agents and dev
/// tools with a single tap, instead of manually typing the command each time.
class AgentPreset {
  const AgentPreset({
    required this.id,
    required this.label,
    required this.command,
    required this.description,
    required this.icon,
    required this.color,
    this.category = PresetCategory.agent,
  });

  final String id;
  final String label;
  final String command;
  final String description;
  final IconData icon;
  final Color color;
  final PresetCategory category;
}

/// Categories for grouping presets.
enum PresetCategory { agent, devtool, system }

/// Catalog of built-in agent harness and dev-tool presets.
class AgentPresets {
  AgentPresets._();

  static const List<AgentPreset> all = [
    // ── AI Coding Agents ──
    AgentPreset(
      id: 'claude-code',
      label: 'Claude Code',
      command: 'claude',
      description: 'Anthropic\'s AI coding agent',
      icon: Icons.smart_toy_rounded,
      color: Color(0xFFD97757),
      category: PresetCategory.agent,
    ),
    AgentPreset(
      id: 'opencode',
      label: 'opencode',
      command: 'opencode',
      description: 'Open-source AI coding agent TUI',
      icon: Icons.code_rounded,
      color: Color(0xFF00E676),
      category: PresetCategory.agent,
    ),
    AgentPreset(
      id: 'aider',
      label: 'Aider',
      command: 'aider',
      description: 'AI pair programming in the terminal',
      icon: Icons.handshake_rounded,
      color: Color(0xFF448AFF),
      category: PresetCategory.agent,
    ),
    AgentPreset(
      id: 'cursor-agent',
      label: 'Cursor Agent',
      command: 'cursor-agent',
      description: 'Cursor\'s autonomous coding agent',
      icon: Icons.ads_click_rounded,
      color: Color(0xFFE040FB),
      category: PresetCategory.agent,
    ),
    AgentPreset(
      id: 'gemini-cli',
      label: 'Gemini CLI',
      command: 'gemini',
      description: 'Google\'s Gemini command-line agent',
      icon: Icons.auto_awesome_rounded,
      color: Color(0xFF18FFFF),
      category: PresetCategory.agent,
    ),
    AgentPreset(
      id: 'qwen-code',
      label: 'Qwen Code',
      command: 'qwen-code',
      description: 'Alibaba\'s Qwen coding agent',
      icon: Icons.memory_rounded,
      color: Color(0xFFFF6E40),
      category: PresetCategory.agent,
    ),
    AgentPreset(
      id: 'codex',
      label: 'Codex',
      command: 'codex',
      description: 'OpenAI\'s Codex CLI agent',
      icon: Icons.bolt_rounded,
      color: Color(0xFF69F0AE),
      category: PresetCategory.agent,
    ),
    AgentPreset(
      id: 'goose',
      label: 'Goose',
      command: 'goose session',
      description: 'Block\'s open-source AI agent',
      icon: Icons.flutter_dash_rounded,
      color: Color(0xFFFFAB40),
      category: PresetCategory.agent,
    ),

    // ── Dev Tools ──
    AgentPreset(
      id: 'htop',
      label: 'htop',
      command: 'htop',
      description: 'Interactive process viewer',
      icon: Icons.bar_chart_rounded,
      color: Color(0xFF448AFF),
      category: PresetCategory.devtool,
    ),
    AgentPreset(
      id: 'btop',
      label: 'btop',
      command: 'btop',
      description: 'Resource monitor (modern htop)',
      icon: Icons.monitor_heart_rounded,
      color: AppConstants.primaryGreen,
      category: PresetCategory.devtool,
    ),
    AgentPreset(
      id: 'lazygit',
      label: 'lazygit',
      command: 'lazygit',
      description: 'Terminal UI for git',
      icon: Icons.commit_rounded,
      color: Color(0xFFFF5252),
      category: PresetCategory.devtool,
    ),
    AgentPreset(
      id: 'lazydocker',
      label: 'lazydocker',
      command: 'lazydocker',
      description: 'Terminal UI for Docker',
      icon: Icons.inventory_2_rounded,
      color: Color(0xFF18FFFF),
      category: PresetCategory.devtool,
    ),
    AgentPreset(
      id: 'tmux',
      label: 'tmux',
      command: 'tmux attach || tmux new',
      description: 'Terminal multiplexer (attach or new)',
      icon: Icons.view_quilt_rounded,
      color: Color(0xFF69F0AE),
      category: PresetCategory.devtool,
    ),
    AgentPreset(
      id: 'nvim',
      label: 'Neovim',
      command: 'nvim',
      description: 'Vim-fork text editor',
      icon: Icons.edit_note_rounded,
      color: Color(0xFF00E676),
      category: PresetCategory.devtool,
    ),
    AgentPreset(
      id: 'yazi',
      label: 'yazi',
      command: 'yazi',
      description: 'Blazing-fast terminal file manager',
      icon: Icons.folder_open_rounded,
      color: Color(0xFFFFAB40),
      category: PresetCategory.devtool,
    ),

    // ── System ──
    AgentPreset(
      id: 'neofetch',
      label: 'neofetch',
      command: 'neofetch',
      description: 'System information with logo',
      icon: Icons.computer_rounded,
      color: Color(0xFFE040FB),
      category: PresetCategory.system,
    ),
    AgentPreset(
      id: 'systemctl-status',
      label: 'Services Status',
      command: 'systemctl --type=service --state=running',
      description: 'List running services',
      icon: Icons.settings_suggest_rounded,
      color: Color(0xFF448AFF),
      category: PresetCategory.system,
    ),
    AgentPreset(
      id: 'disk-usage',
      label: 'Disk Usage',
      command: 'df -h',
      description: 'Show disk space usage',
      icon: Icons.storage_rounded,
      color: Color(0xFFFF6E40),
      category: PresetCategory.system,
    ),
    AgentPreset(
      id: 'logs',
      label: 'Recent Logs',
      command: 'journalctl -n 50 --no-pager',
      description: 'Show last 50 system log lines',
      icon: Icons.description_rounded,
      color: Color(0xFFFFAB40),
      category: PresetCategory.system,
    ),
    AgentPreset(
      id: 'uptime',
      label: 'Uptime',
      command: 'uptime -p',
      description: 'Show system uptime',
      icon: Icons.schedule_rounded,
      color: Color(0xFF69F0AE),
      category: PresetCategory.system,
    ),
  ];

  /// Get presets filtered by category.
  static List<AgentPreset> byCategory(PresetCategory category) {
    return all.where((p) => p.category == category).toList();
  }

  /// Find a preset by its id.
  static AgentPreset? byId(String id) {
    try {
      return all.firstWhere((p) => p.id == id);
    } catch (_) {
      return null;
    }
  }

  /// Human-readable label for a category.
  static String categoryLabel(PresetCategory category) {
    switch (category) {
      case PresetCategory.agent:
        return 'AI Agents';
      case PresetCategory.devtool:
        return 'Dev Tools';
      case PresetCategory.system:
        return 'System';
    }
  }
}
