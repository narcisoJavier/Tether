# packages/tailscale/ — Embedded Go FFI Sub-package

Fork of [danReynolds/tailscale_dart](https://github.com/danReynolds/tailscale_dart) v0.5.0. Provides userspace Tailscale networking via Go tsnet compiled to a shared library loaded through Dart FFI.

## STRUCTURE

```
packages/tailscale/
├── lib/
│   ├── tailscale.dart              # Public API barrel (Tailscale singleton)
│   └── src/
│       ├── ffi_bindings.dart       # Dart FFI bindings to Go exports
│       ├── worker/
│       │   ├── entrypoint.dart     # Isolate entry: _workerEntrypoint()
│       │   ├── worker.dart         # Worker orchestrator
│       │   └── messages.dart       # Command/response message types
│       ├── api/                    # 13 API namespace implementations
│       │   ├── tcp.dart, tls.dart, udp.dart, http.dart
│       │   ├── identity.dart, status.dart, errors.dart
│       │   ├── prefs.dart, serve.dart, funnel.dart
│       │   ├── exit_node.dart, taildrop.dart, profiles.dart
│       │   └── connection.dart     # TCP/TLS/UDP connection abstractions
│       ├── fd_transport.dart       # POSIX fd transport layer
│       ├── posix_reactor.dart      # kqueue/epoll async I/O reactor
│       ├── http_fd_client.dart     # HTTP client over fd transport
│       └── runtime_connection.dart # Connection/listener abstractions
├── go/
│   ├── cmd/dylib/main.go           # CGo entry: 30+ Dune* exports
│   ├── lib.go                      # Core tsnet wrapper
│   ├── reactor_linux.go            # epoll reactor
│   ├── reactor_darwin.go           # kqueue reactor
│   ├── reactor_unsupported.go      # No-op fallback
│   └── tcp_fd_posix.go, http_fd_posix.go, udp_fd_posix.go
├── hook/
│   └── build.dart                  # Dart build hook: Go → .so/.dylib
├── test/                           # Multi-tier tests
│   ├── unit/                       # Pure Dart tests
│   ├── integration/                # FFI + fd transport tests
│   ├── e2e/                        # Headscale Docker E2E
│   └── live_tailscale/             # Tailscale SaaS validation
└── doc/                            # API roadmap, testing guide
```

## WHERE TO LOOK

| Task | File | Notes |
|------|------|-------|
| Add new API method | `lib/src/api/<namespace>.dart` | Follow existing pattern |
| Modify Go exports | `go/cmd/dylib/main.go` | Add CGo export function |
| Modify Go core | `go/lib.go` | Wraps upstream tsnet |
| Change build process | `hook/build.dart` | Go compilation logic |
| Add platform support | `go/reactor_<platform>.go` | Implement reactor interface |
| Debug FFI | `lib/src/worker/entrypoint.dart` | Isolate message handling |
| Run tests | `test/unit/`, `test/integration/` | `dart test` from package root |

## CONVENTIONS

- All Go exports use `Dune` prefix (C-ABI compatible)
- Dart FFI uses `Pointer<Utf8>` for strings with manual `calloc.free()`
- Worker isolate handles all native ops (never blocks UI thread)
- Platform split: `_posix.go` / `_unsupported.go` files
- Test tiers: unit → integration → e2e → live (strict ordering)

## ANTI-PATTERNS

- Never call FFI from main isolate → blocks UI
- Never skip `DuneFree()` on returned pointers → memory leak
- Never use `print()` → use `debugPrint()`
- Empty `else` blocks forbidden (lint: `avoid_empty_else`)
- Un-awaited futures forbidden (lint: `unawaited_futures`)
