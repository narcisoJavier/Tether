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
import 'services/hive_adapters.dart';
import 'services/onboarding_service.dart';
import 'services/profile_storage_service.dart';
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

  // One-time migration: move passwords from Hive plain-text to Keystore.
  if (!(prefs.getBool('password_migration_done') ?? false)) {
    final profilesBox = Hive.box<ConnectionProfile>('connection_profiles');
    final commandsBox = Hive.box<QuickCommand>('quick_commands');
    final storage = ProfileStorageService(profilesBox, commandsBox);
    final migrated = await storage.migratePasswords();
    if (migrated > 0) {
      debugPrint('[PWD] Migrated $migrated passwords to secure storage');
    }
    await prefs.setBool('password_migration_done', true);
  }

  // Init embedded Tailscale node
  //
  // Check CPU architecture first: on x86_64 emulators the Go runtime
  // makes syscalls that seccomp blocks -> SIGSYS kills the process
  // (Dart try-catch cannot catch signal-level crashes).
  TailscaleService? tailscaleService;
  try {
    const platform = MethodChannel('dev.tether.app/cpu_abi');
    final abis =
        (await platform.invokeMethod('getSupportedAbis')) as List<dynamic>?;
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

  // Increment launch counter for welcome-back screen.
  final onboardingService = OnboardingService(prefs);
  await onboardingService.incrementLaunchCount();

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
      child: const TetherApp(),
    ),
  );
}

/// Top-level app widget.
///
/// The biometric gate is now handled by GoRouter redirect (see app_router.dart),
/// so this widget just builds the MaterialApp.router.
class TetherApp extends ConsumerWidget {
  const TetherApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: 'Tether',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.dark,
      routerConfig: router,
    );
  }
}
