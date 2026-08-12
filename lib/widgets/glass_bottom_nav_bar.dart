import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

/// A frosted-glass bottom navigation bar matching the Apple TUI 2.0 / HTML spec.
///
/// Features 20px blur, dark surface background (`rgba(16, 19, 27, 0.8)`),
/// top cyan hairline border (`rgba(0, 204, 255, 0.2)`), and 5 tab items:
/// Home, Terminal, Commands, Keys, Settings.
class GlassBottomNavBar extends StatelessWidget {
  const GlassBottomNavBar({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  void _onTap(int index) {
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.paddingOf(context).bottom;

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          height: 64 + bottomPadding,
          padding: EdgeInsets.only(bottom: bottomPadding),
          decoration: BoxDecoration(
            color: const Color(0xFF10131B).withValues(alpha: 0.8),
            border: Border(
              top: BorderSide(
                color: const Color(0xFF00CCFF).withValues(alpha: 0.2),
                width: 0.8,
              ),
            ),
          ),
          child: Row(
            children: [
              _NavItem(
                icon: Icons.terminal_rounded,
                label: 'HOME',
                isSelected: navigationShell.currentIndex == 0,
                onTap: () => _onTap(0),
              ),
              _NavItem(
                icon: Icons.code_rounded,
                label: 'TERMINAL',
                isSelected: navigationShell.currentIndex == 1,
                onTap: () => _onTap(1),
              ),
              _NavItem(
                icon: Icons.list_alt_rounded,
                label: 'COMMANDS',
                isSelected: navigationShell.currentIndex == 2,
                onTap: () => _onTap(2),
              ),
              _NavItem(
                icon: Icons.key_rounded,
                label: 'KEYS',
                isSelected: navigationShell.currentIndex == 3,
                onTap: () => _onTap(3),
              ),
              _NavItem(
                icon: Icons.tune_rounded,
                label: 'SETTINGS',
                isSelected: navigationShell.currentIndex == 4,
                onTap: () => _onTap(4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const activeColor = Color(0xFF00CCFF);
    const dimColor = Color(0xFF8E8E93);
    final color = isSelected ? activeColor : dimColor;

    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          splashColor: activeColor.withValues(alpha: 0.1),
          highlightColor: Colors.transparent,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 22, color: color),
              const SizedBox(height: 3),
              Text(
                label,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 10,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: color,
                  letterSpacing: -0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
