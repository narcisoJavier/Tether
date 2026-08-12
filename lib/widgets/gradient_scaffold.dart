import 'dart:ui';
import 'package:flutter/material.dart';
import '../utils/constants.dart';

/// A [Scaffold] wrapper with OLED black background.
///
/// Stripped of gradient and ambient orbs for a clean Apple TUI aesthetic.
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

  /// Kept for API compatibility — orbs are always off in TUI mode.
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
      body: body,
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
    this.toolbarHeight = 54,
    this.blurSigma = 20,
  });

  final Widget title;
  final Widget? leading;
  final List<Widget>? actions;
  final PreferredSizeWidget? bottom;
  final double toolbarHeight;
  final double blurSigma;

  @override
  Size get preferredSize =>
      Size.fromHeight(toolbarHeight + (bottom?.preferredSize.height ?? 0));

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
              bottom: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
            ),
          ),
          child: SafeArea(
            bottom: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Center(child: title),
                      if (leading != null)
                        Positioned(
                          left: 8,
                          top: 0,
                          bottom: 0,
                          child: Center(child: leading!),
                        ),
                      if (actions != null)
                        Positioned(
                          right: 8,
                          top: 0,
                          bottom: 0,
                          child: Center(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: actions!,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                ?bottom,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
