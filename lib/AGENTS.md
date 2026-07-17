# lib/ — Flutter App Source

38 Dart files across 5 subdirectories + 3 root files.

## STRUCTURE

```
lib/
├── main.dart              # App entry: Hive, Tailscale, Riverpod, biometric gate
├── app_router.dart        # GoRouter: 10 routes + onboarding redirect guard
├── app_theme.dart         # Dark glassmorphism Material3 theme
├── models/                # 3 data classes (HiveObject subclasses)
├── screens/               # 10 full-page widgets
├── services/              # 13 business logic services ← see services/AGENTS.md
├── utils/                 # 6 utility files (constants, presets, providers)
└── widgets/               # 3 reusable components
```

## WHERE TO LOOK

| Task | File | Notes |
|------|------|-------|
| Add route | `app_router.dart` | Add to GoRouter routes list + screen import |
| Add screen | `screens/` | ConsumerStatefulWidget, register route |
| Add service | `services/` | ChangeNotifier + Riverpod provider |
| Add model | `models/` | Extend HiveObject, add adapter typeId |
| Add widget | `widgets/` | Stateless or StatefulWidget |
| Add preset | `utils/agent_presets.dart` | Add to AgentPresets.presets list |
| Change theme | `app_theme.dart` | Single source for all styling |
| Change constants | `utils/constants.dart` | Colors, sizes, defaults |

## CONVENTIONS

- Screens use `ConsumerStatefulWidget` (Riverpod + State)
- Models are `HiveObject` subclasses with `copyWith()` methods
- Services extend `ChangeNotifier` and are wrapped in `ChangeNotifierProvider`
- Widgets receive data via constructor, emit events via callbacks
- All imports: Dart SDK → Flutter → third-party → project (blank line between groups)

## ANTI-PATTERNS

- Never use `print()` — use `debugPrint()`
- Never skip `mounted` checks after `await`
- Never hardcode colors — use `AppColors` from `utils/constants.dart`
