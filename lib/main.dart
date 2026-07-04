import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tailscale/tailscale.dart';

import 'app_theme.dart';
import 'app_router.dart';
import 'models/connection_profile.dart';
import 'models/stored_key_pair.dart';
import 'models/quick_command.dart';
import 'screens/lock_screen.dart';
import 'services/biometric_provider.dart';
import 'services/hive_adapters.dart';
import 'services/onboarding_service.dart';
import 'services/tailscale_provider.dart';
import 'services/tailscale_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize SharedPreferences early for onboarding detection.
  final prefs = await SharedPreferences.getInstance();

  // Initialize Hive FIRST, then register adapters (adapters require Hive to
  // be initialized so the registry can store them).
  await Hive.initFlutter();
  registerHiveAdapters();

  // Open typed boxes for profiles, keys, and commands.
  await Hive.openBox<ConnectionProfile>('connection_profiles');
  await Hive.openBox<StoredKeyPair>('ssh_keys');
  await Hive.openBox<QuickCommand>('quick_commands');

  // Init embedded Tailscale node
  //
  // Check CPU architecture first: on x86_64 emulators the Go runtime
  // makes syscalls that seccomp blocks -> SIGSYS kills the process
  // (Dart try-catch cannot catch signal-level crashes).
  TailscaleService? tailscaleService;
  try {
    const platform = MethodChannel('com.opa.app/cpu_abi');
    final abis = (await platform.invokeMethod('getSupportedAbis'))
        as List<dynamic>?;
    final isX86_64 = abis?.any((a) => a == 'x86_64') ?? false;

    if (isX86_64) {
      debugPrint('[TS] Skipping Tailscale init: x86_64 emulator detected');
    } else {
      final d = await getApplicationSupportDirectory();
      Tailscale.init(stateDir: d.path, logLevel: TailscaleLogLevel.silent);
      tailscaleService = TailscaleService();
      tailscaleService.initialize(d.path);
    }
  } catch (e) {
    debugPrint('[TS] Tailscale init skipped/errored: $e');
  }

  runApp(
    ProviderScope(
      overrides: [
        // Inject the already-initialized SharedPreferences so the
        // onboarding provider doesn't need to await again.
        sharedPrefsProvider.overrideWithValue(prefs),
        // Inject the pre-initialized TailscaleService so providers
        // don't create a fresh uninitialized instance.
        if (tailscaleService != null)
          tailscaleServiceProvider.overrideWithValue(tailscaleService),
      ],
      child: const OpaApp(),
    ),
  );
}

/// Top-level app widget.
///
/// Wraps the main app with a biometric gate: if the user has enabled
/// biometric lock and hasn't authenticated yet this session, show the
/// [LockScreen] instead of the main app.
class OpaApp extends ConsumerWidget {
  const OpaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lockEnabled = ref.watch(biometricLockEnabledProvider);
    final isAuthenticated = ref.watch(authSessionProvider);

    // When biometric lock is on and the user hasn't authenticated this
    // session, show the lock screen instead of the main app.
    if (lockEnabled && !isAuthenticated) {
      return _buildLockGate();
    }

    return _buildApp(context, ref);
  }

  Widget _buildLockGate() {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'OPA',
      theme: AppTheme.dark(),
      home: const LockScreen(),
    );
  }

  Widget _buildApp(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: 'OPA',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.dark,
      routerConfig: router,
    );
  }
}
