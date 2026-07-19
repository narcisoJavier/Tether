import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'services/biometric_provider.dart';
import 'services/onboarding_service.dart';
import 'screens/home_screen.dart';
import 'screens/lock_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/tabbed_terminal_screen.dart';
import 'screens/profile_editor_screen.dart';
import 'screens/key_management_screen.dart';
import 'screens/quick_commands_screen.dart';
import 'screens/sftp_screen.dart';
import 'screens/preset_editor_screen.dart';
import 'screens/tunnel_screen.dart';
import 'screens/welcome_back_screen.dart';

/// Top-level navigator key.
final _rootNavigatorKey = GlobalKey<NavigatorState>();

/// Custom page transition — slide from right with fade.
CustomTransitionPage<void> _buildTransitionPage({
  required Widget child,
  required GoRouterState state,
}) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 300),
    reverseTransitionDuration: const Duration(milliseconds: 250),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return FadeTransition(
        opacity: CurvedAnimation(
          parent: animation,
          curve: Curves.easeOut,
        ),
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.06, 0),
            end: Offset.zero,
          ).animate(CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          )),
          child: child,
        ),
      );
    },
  );
}

/// Listenable that fires when any of the auth-related Riverpod providers change.
///
/// GoRouter watches this to re-run its redirect without recreating the router
/// (which would crash due to GlobalKey reuse).
class _AuthRefreshListenable extends ChangeNotifier {
  _AuthRefreshListenable(Ref ref) {
    ref.listen(biometricLockEnabledProvider, (_, _) => notifyListeners());
    ref.listen(authSessionProvider, (_, _) => notifyListeners());
  }
}

/// GoRouter configuration for OPA.
///
/// Uses [StatefulShellRoute.indexedStack] to keep the terminal tab screen alive
/// across navigation. The [TabbedTerminalScreen] lives in its own branch so its
/// SSH sessions and terminal state are preserved when the user goes back home.
final appRouterProvider = Provider<GoRouter>((ref) {
  final refreshListenable = _AuthRefreshListenable(ref);

  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/',
    refreshListenable: refreshListenable,
    redirect: (context, state) {
      final container = ProviderScope.containerOf(context);
      final onboardingService = container.read(onboardingServiceProvider);
      final lockEnabled = container.read(biometricLockEnabledProvider);
      final isAuthenticated = container.read(authSessionProvider);
      final isComplete = onboardingService.isOnboardingComplete();
      final isOnboardingRoute = state.matchedLocation == '/onboarding';
      final isWelcomeRoute = state.matchedLocation == '/welcome';
      final isLockRoute = state.matchedLocation == '/lock';

      // First-time onboarding
      if (!isComplete && !isOnboardingRoute) {
        return '/onboarding';
      }
      if (isComplete && isOnboardingRoute) {
        return '/';
      }

      // Biometric lock gate (route-based instead of widget-level)
      if (lockEnabled && !isAuthenticated && !isLockRoute && !isOnboardingRoute) {
        return '/lock';
      }
      if (isLockRoute && (!lockEnabled || isAuthenticated)) {
        return '/';
      }

      // Welcome-back screen (second+ launch, if enabled)
      if (isComplete && !isWelcomeRoute && !isLockRoute && onboardingService.shouldShowWelcomeBack()) {
        return '/welcome';
      }
      if (isWelcomeRoute && !onboardingService.shouldShowWelcomeBack()) {
        return '/';
      }

      return null;
    },
    routes: [
      // ── Full-screen routes (outside shell: lock, onboarding, welcome-back) ──
      GoRoute(
        path: '/lock',
        pageBuilder: (context, state) => _buildTransitionPage(
          child: const LockScreen(),
          state: state,
        ),
      ),
      GoRoute(
        path: '/onboarding',
        pageBuilder: (context, state) => _buildTransitionPage(
          child: const OnboardingScreen(),
          state: state,
        ),
      ),
      GoRoute(
        path: '/welcome',
        pageBuilder: (context, state) => _buildTransitionPage(
          child: const WelcomeBackScreen(),
          state: state,
        ),
      ),

      // ── Shell: tabbed terminal stays alive across navigation ──
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) => navigationShell,
        branches: [
          // Branch 0 — Home + sub-screens
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/',
                pageBuilder: (context, state) => _buildTransitionPage(
                  child: const HomeScreen(),
                  state: state,
                ),
                routes: [
                  GoRoute(
                    path: 'sftp/:profileId',
                    pageBuilder: (context, state) {
                      final profileId = state.pathParameters['profileId']!;
                      return _buildTransitionPage(
                        child: SftpScreen(profileId: profileId),
                        state: state,
                      );
                    },
                  ),
                  GoRoute(
                    path: 'profile/new',
                    pageBuilder: (context, state) => _buildTransitionPage(
                      child: const ProfileEditorScreen(),
                      state: state,
                    ),
                  ),
                  GoRoute(
                    path: 'profile/:profileId',
                    pageBuilder: (context, state) {
                      final profileId = state.pathParameters['profileId']!;
                      return _buildTransitionPage(
                        child: ProfileEditorScreen(profileId: profileId),
                        state: state,
                      );
                    },
                  ),
                  GoRoute(
                    path: 'tunnel/:profileId',
                    pageBuilder: (context, state) {
                      final profileId = state.pathParameters['profileId']!;
                      return _buildTransitionPage(
                        child: TunnelScreen(profileId: profileId),
                        state: state,
                      );
                    },
                  ),
                  GoRoute(
                    path: 'keys',
                    pageBuilder: (context, state) => _buildTransitionPage(
                      child: const KeyManagementScreen(),
                      state: state,
                    ),
                  ),
                  GoRoute(
                    path: 'commands',
                    pageBuilder: (context, state) => _buildTransitionPage(
                      child: const QuickCommandsScreen(),
                      state: state,
                    ),
                  ),
                  GoRoute(
                    path: 'presets',
                    pageBuilder: (context, state) => _buildTransitionPage(
                      child: const PresetEditorScreen(),
                      state: state,
                    ),
                  ),
                  GoRoute(
                    path: 'settings',
                    pageBuilder: (context, state) => _buildTransitionPage(
                      child: const SettingsScreen(),
                      state: state,
                    ),
                  ),
                ],
              ),
            ],
          ),

          // Branch 1 — Terminal (persistent across navigation)
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/terminal',
                pageBuilder: (context, state) => _buildTransitionPage(
                  child: const TabbedTerminalScreen(),
                  state: state,
                ),
              ),
            ],
          ),
        ],
      ),
    ],
  );
});
