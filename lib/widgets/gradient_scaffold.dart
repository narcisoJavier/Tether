import 'dart:ui';
import 'package:flutter/material.dart';
import '../app_theme.dart';
import '../utils/constants.dart';

/// A [Scaffold] wrapper that paints the deep-space gradient background
/// behind all content, with optional ambient orb decorations.
///
/// Usage:
/// ```dart
/// GradientScaffold(
///   appBar: AppBar(...),
///   body: ...,
/// )
/// ```
class GradientScaffold extends StatelessWidget {
  const GradientScaffold({
    super.key,
    this.appBar,
    required this.body,
    this.floatingActionButton,
    this.floatingActionButtonLocation,
    this.bottomNavigationBar,
    this.resizeToAvoidBottomInset = true,
    this.showOrbs = true,
    this.extendBodyBehindAppBar = false,
  });

  final PreferredSizeWidget? appBar;
  final Widget body;
  final Widget? floatingActionButton;
  final FloatingActionButtonLocation? floatingActionButtonLocation;
  final Widget? bottomNavigationBar;
  final bool resizeToAvoidBottomInset;

  /// Whether to draw ambient gradient orbs in the background.
  final bool showOrbs;
  final bool extendBodyBehindAppBar;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: extendBodyBehindAppBar,
      resizeToAvoidBottomInset: resizeToAvoidBottomInset,
      backgroundColor: AppConstants.bgDeep,
      appBar: appBar,
      floatingActionButton: floatingActionButton,
      floatingActionButtonLocation: floatingActionButtonLocation,
      bottomNavigationBar: bottomNavigationBar,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ── Base gradient ────────────────────────────────────────────────
          const DecoratedBox(decoration: BoxDecoration(gradient: AppTheme.scaffoldGradient)),

          // ── Ambient orbs ─────────────────────────────────────────────────
          if (showOrbs) ...[
            // Top-left green orb
            Positioned(
              top: -120,
              left: -80,
              child: _Orb(
                size: 320,
                color: AppConstants.primaryGreen.withValues(alpha: 0.045),
              ),
            ),
            // Top-right blue orb
            Positioned(
              top: 40,
              right: -100,
              child: _Orb(
                size: 280,
                color: AppConstants.accentBlue.withValues(alpha: 0.03),
              ),
            ),
            // Bottom-center purple orb
            Positioned(
              bottom: -100,
              left: 0,
              right: 0,
              child: Center(
                child: _Orb(
                  size: 260,
                  color: AppConstants.accentPurple.withValues(alpha: 0.025),
                ),
              ),
            ),
          ],

          // ── Actual content ───────────────────────────────────────────────
          body,
        ],
      ),
    );
  }
}

/// Blurred ambient light orb.
class _Orb extends StatelessWidget {
  const _Orb({required this.size, required this.color});
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ImageFiltered(
      imageFilter: ImageFilter.blur(sigmaX: 60, sigmaY: 60),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
        ),
      ),
    );
  }
}

/// A frosted-glass AppBar that blurs content behind it.
///
/// Use this instead of [AppBar] for screens with gradient backgrounds to
/// give the illusion that the scrollable content floats beneath a glass bar.
class GlassAppBar extends StatelessWidget implements PreferredSizeWidget {
  const GlassAppBar({
    super.key,
    required this.title,
    this.leading,
    this.actions,
    this.bottom,
    this.toolbarHeight = 58,
    this.blurSigma = 20,
  });

  final Widget title;
  final Widget? leading;
  final List<Widget>? actions;
  final PreferredSizeWidget? bottom;
  final double toolbarHeight;
  final double blurSigma;

  @override
  Size get preferredSize => Size.fromHeight(
        toolbarHeight + (bottom?.preferredSize.height ?? 0),
      );

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.paddingOf(context).top;
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
        child: Container(
          height: preferredSize.height + topPadding,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                AppConstants.surface0.withValues(alpha: 0.85),
                AppConstants.surface0.withValues(alpha: 0.6),
              ],
            ),
            border: Border(
              bottom: BorderSide(
                color: Colors.white.withValues(alpha: 0.06),
              ),
            ),
          ),
          child: SafeArea(
            bottom: false,
            child: Column(
              children: [
                SizedBox(
                  height: toolbarHeight,
                  child: NavigationToolbar(
                    leading: leading != null
                        ? Padding(
                            padding: const EdgeInsets.only(left: 4),
                            child: leading,
                          )
                        : null,
                    middle: title,
                    trailing: actions != null
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: actions!,
                          )
                        : null,
                    centerMiddle: true,
                  ),
                ),
                if (bottom != null) bottom!,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
