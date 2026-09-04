import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../services/onboarding_service.dart';
import 'cyber_splash_screen.dart';

class WelcomeBackScreen extends ConsumerWidget {
  const WelcomeBackScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return CyberSplashScreen(
      onBootComplete: () {
        ref.read(onboardingServiceProvider).markWelcomeShown();
        context.go('/');
      },
    );
  }
}
