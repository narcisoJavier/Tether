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
import 'widgets/glass_bottom_nav_bar.dart';

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
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
        child: SlideTransition(
          position:
              Tween<Offset>(
                begin: const Offset(0.06, 0),
                end: Offset.zero,
              ).animate(
                CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
              ),
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
    ref.listen(appLockProvider, (_, _) => notifyListeners());
  }
}

/// Preserves mounted sessions on relock and defers new destinations until unlock.
class AppLockRouteGuard {
  String? _lastAccessibleLocation;
  String? _pendingLocation;

  /// Gates cold starts before protected screens are constructed.
  String? redirect({required Uri uri, required bool locked}) {
    final location = uri.toString();
    if (locked) {
      final previous = _lastAccessibleLocation;
      if (previous != null) {
        if (location != previous && uri.path != '/lock') {
          _pendingLocation = location;
        }
        return location == previous ? null : previous;
      }
      if (uri.path == '/lock') return null;
      return Uri(path: '/lock', queryParameters: {'from': location}).toString();
    }
    if (uri.path == '/lock') {
      final destination = Uri.tryParse(uri.queryParameters['from'] ?? '/');
      if (destination == null ||
          destination.hasScheme ||
          destination.hasAuthority ||
          !destination.path.startsWith('/') ||
          destination.path.startsWith('//') ||
          destination.path == '/lock') {
        return '/';
      }
      return destination.toString();
    }
    final pending = _pendingLocation;
    _pendingLocation = null;
    if (pending != null && pending != location) return pending;
    _lastAccessibleLocation = location;
    return null;
  }
}

/// GoRouter configuration for Tether.
///
/// Uses [StatefulShellRoute.indexedStack] with 5 branches to preserve state across
/// Home, Terminal, Commands, Keys, and Settings screens.
final appRouterProvider = Provider<GoRouter>((ref) {
  final refreshListenable = _AuthRefreshListenable(ref);
  final lockGuard = AppLockRouteGuard();

  final router = GoRouter(
    initialLocation: '/',
    refreshListenable: refreshListenable,
    redirect: (context, state) {
      final container = ProviderScope.containerOf(context);
      final onboardingService = container.read(onboardingServiceProvider);
      final appLock = container.read(appLockProvider);
      final isComplete = onboardingService.isOnboardingComplete();
      final isOnboardingRoute = state.matchedLocation == '/onboarding';
      final isWelcomeRoute = state.matchedLocation == '/welcome';
      final isLockRoute = state.matchedLocation == '/lock';

      final lockRedirect = lockGuard.redirect(
        uri: state.uri,
        locked: appLock.requiresAuthentication,
      );
      if (lockRedirect != null) return lockRedirect;
      if (appLock.requiresAuthentication) return null;

      // First-time onboarding redirect
      if (!isComplete && !isOnboardingRoute) {
        return '/onboarding';
      }

      // Welcome-back screen (second+ launch, if enabled)
      if (isComplete &&
          state.uri.path == '/' &&
          !isWelcomeRoute &&
          !isLockRoute &&
          onboardingService.shouldShowWelcomeBack()) {
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
        pageBuilder: (context, state) =>
            NoTransitionPage(key: state.pageKey, child: const LockScreen()),
      ),
      GoRoute(
        path: '/onboarding',
        pageBuilder: (context, state) =>
            _buildTransitionPage(child: const OnboardingScreen(), state: state),
      ),
      GoRoute(
        path: '/welcome',
        pageBuilder: (context, state) => _buildTransitionPage(
          child: const WelcomeBackScreen(),
          state: state,
        ),
      ),

      // ── Shell: persistent glass bottom navigation bar across 5 branches ──
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          final isTerminal = navigationShell.currentIndex == 1;
          return Scaffold(
            body: navigationShell,
            extendBody: !isTerminal,
            bottomNavigationBar: isTerminal
                ? null
                : GlassBottomNavBar(navigationShell: navigationShell),
          );
        },
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
                    path: 'presets',
                    pageBuilder: (context, state) => _buildTransitionPage(
                      child: const PresetEditorScreen(),
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

          // Branch 2 — Commands
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/commands',
                pageBuilder: (context, state) => _buildTransitionPage(
                  child: const QuickCommandsScreen(),
                  state: state,
                ),
              ),
            ],
          ),

          // Branch 3 — Keys
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/keys',
                pageBuilder: (context, state) => _buildTransitionPage(
                  child: const KeyManagementScreen(),
                  state: state,
                ),
              ),
            ],
          ),

          // Branch 4 — Settings
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/settings',
                pageBuilder: (context, state) => _buildTransitionPage(
                  child: const SettingsScreen(),
                  state: state,
                ),
              ),
            ],
          ),
        ],
      ),
    ],
  );
  ref.onDispose(() {
    router.dispose();
    refreshListenable.dispose();
  });
  return router;
});
