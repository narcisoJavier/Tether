# Tether privacy and data handling

This document describes the data handling implemented by the Android app. It is an engineering reference for release review, not a legal privacy policy or a store declaration.

## Data stored on the device

- SSH connection profiles and quick commands are stored locally in Hive. Profiles contain connection settings, environment tags, and tunnel configuration; quick commands contain their command text and metadata.
- SSH passwords are stored separately through Android secure storage and are not part of normal Hive profile data. SSH private keys are stored through Android secure storage; their public metadata is kept locally in Hive.
- SSH host-key trust records are stored locally in Hive. They are used to detect changed host keys and are not uploaded by Tether.
- App preferences such as onboarding, terminal presentation, and command-deck layout are stored locally through `SharedPreferences`.
- The embedded Tailscale node keeps its local identity/state in the app's private storage. Android application backup is disabled (`android:allowBackup="false"`) so that state is not copied to another device.

## Network activity and telemetry

Tether connects to SSH servers and, when configured, routes connections through the embedded Tailscale mesh. The Home telemetry surface currently reports local connection-health signals. It does not collect remote CPU, RAM, or disk metrics; those remain a future SSH-backed feature.

Tether has no cloud synchronization service. It does not send profiles, commands, passwords, private keys, host-key records, or Tailscale identity to a Tether backend.

## Encrypted backups

The backup flow exports profiles, environment tags, tunnels, and quick commands into a password-protected encrypted envelope. It excludes SSH passwords, private keys, trusted host keys, Tailscale identity, and app preferences. A restored profile therefore requires credentials to be entered again on the destination device.

Plaintext clipboard export is disabled. The current convenience flow copies only the encrypted envelope to the device clipboard after the user supplies a backup password. Treat copied backup text as sensitive and clear it when it is no longer needed.

## Release review notes

This document records current implementation behavior. Before release, verify the packaged Android artifact, Android backup configuration, encrypted backup behavior, and the applicable store disclosures against the exact build being shipped. See the [Android release checklist](RELEASE_CHECKLIST.md).
