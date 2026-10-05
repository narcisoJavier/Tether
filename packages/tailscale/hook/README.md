# Native artifact validation

The build hook validates newly built and cached artifacts before registering the native asset. It reads binary metadata without loading or executing target code on the build host.

- ELF requires bounded load, dynamic, section, symbol, string, and hash tables. Required functions must be defined global/weak dynamic symbols, have public visibility, be mapped to executable bytes, and be reachable through the dynamic linker's symbol hash table. Hidden/local/undefined symbols and arbitrary embedded strings do not qualify.
- Mach-O requires a thin 64-bit dylib with bounded load commands, segments, sections, and an export trie. Exported addresses must be executable. The platform command must match macOS, iOS device, or iOS simulator; the hook passes the requested iOS SDK identity. Older version commands are accepted only when their CPU/platform combination identifies the target unambiguously. Fat binaries and binaries with missing platform metadata fail closed.
- PE requires a bounded DLL optional header, section table, and export directory. Named exports must reference valid ordinals and executable addresses. Forwarded exports do not satisfy the bundled Go function requirement.

The ELF validator intentionally requires section metadata produced by the Go build; artifacts stripped of section headers are not accepted. The parser does not emulate an operating system loader or validate dependency availability, relocation execution, or code signing. Passing it does not replace the release packaging checks or native smoke tests on each supported target.

The hook test fixtures populate the metadata used by these checks. They are synthetic parser fixtures, not substitutes for a real Go library load test. Their malformed variants cover missing/decoy exports, truncated data, table bounds, wrong CPU/platform identity, and cache rejection.

Host `CC` is passed through to Go unchanged, so wrappers and compiler arguments supported by Go continue to work. Go's build failure is the compiler diagnostic; the hook does not try to execute a multi-part `CC` value as one executable.

Run the focused tests from this package with `dart test test/hook/native_build_support_test.dart`. This normal entrypoint runs build hooks and therefore requires the Go toolchain from `go/go.mod`. When testing only this pure Dart validator on a host without Go, invoke the resolved `package:test` `bin/test.dart` directly with this package's `.dart_tool/package_config.json`; that bypass is not a native build verification.
