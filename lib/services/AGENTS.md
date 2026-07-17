# lib/services/ — Business Logic Layer

13 Dart files. Core services for SSH, Tailscale, keys, storage, and biometrics.

## STRUCTURE

```
services/
├── ssh_service.dart              # dartssh2 wrapper: connect/shell/exec/resize
├── tailscale_service.dart        # Embedded WireGuard tailnet lifecycle
├── tailscale_provider.dart       # Riverpod providers for Tailscale state
├── tailscale_ssh_socket.dart     # Bridge: TailscaleConnection → dartssh2.SSHSocket
├── key_service.dart              # Ed25519 generation + Android Keystore CRUD
├── profile_storage_service.dart  # Hive CRUD for ConnectionProfile + QuickCommand
├── hive_adapters.dart            # Manual Hive TypeAdapters (typeId 0-2)
├── sftp_service.dart             # SFTP file operations via dartssh2
├── biometric_service.dart        # local_auth wrapper for fingerprint/face
├── biometric_provider.dart       # Riverpod providers for biometric lock state
├── onboarding_service.dart       # SharedPreferences first-launch detection
├── update_service.dart           # GitHub Releases API update checker
└── export_service.dart           # Import/Export profiles+commands to JSON
```

## KEY PATTERNS

### SSH Connection Flow
```
SshService.connect(host, port, user, auth)
  → [optional] TailscaleService.dial(host, port) → TailscaleSshSocket
  → dartssh2.SSHClient(socket, identities, onPasswordRequest)
  → client.shell() → PTY session → stdout stream → terminal widget
```

### Tailscale Integration
```
TailscaleService.initialize(authKey)
  → package:tailscale (Go FFI) → WireGuard tunnel
  → TailscaleService.dial(host, port) → TailscaleConnection
  → TailscaleSshSocket wraps connection as SSHSocket
```

### Hive Persistence
| Box | Type | typeId | Adapter |
|-----|------|--------|---------|
| `connection_profiles` | `ConnectionProfile` | 0 | `ConnectionProfileAdapter` |
| `ssh_keys` | `StoredKeyPair` | 1 | `StoredKeyPairAdapter` |
| `quick_commands` | `QuickCommand` | 2 | `QuickCommandAdapter` |

### Provider Registration (main.dart)
All pre-initialized services are injected via `ProviderScope(overrides: [...])`:
- `sharedPrefsProvider` → SharedPreferences
- `tailscaleServiceProvider` → TailscaleService (after init)

## CONVENTIONS

- Services that hold state extend `ChangeNotifier`
- Provider names: `camelCase + Provider` (e.g., `sshServiceProvider`)
- Secure storage keys: `opa_` prefix (e.g., `opa_key_<id>`)
- Stream subscriptions must be cancelled in `dispose()`
- Use `debugPrint()` not `print()`

## ANTI-PATTERNS

- Never leave stream subscriptions uncanceled → leak
- Never use `print()` → lint violation
- Never skip `mounted` check after async in screens using these services
