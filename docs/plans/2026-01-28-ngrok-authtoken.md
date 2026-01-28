# ngrok Authtoken Support (M2.3)

**Date:** 2026-01-28
**Status:** Approved

## Context

NgrokManager (530 lines) already handles binary management, process lifecycle, tunnel detection, and URL parsing. The missing piece is authtoken configuration — required for free-tier ngrok to create tunnels.

## Scope

- Authtoken detection from ngrok config files
- Authtoken storage in Keychain
- Settings UI for token input with onboarding guidance
- Guard tunnel start on token presence
- Tests for all new functionality

**Out of scope:** Custom domain support (paid feature).

## Design

### 1. Authtoken Detection (NgrokManager)

New methods:
- `detectAuthToken() async -> String?` — checks `~/.config/ngrok/ngrok.yml` then `~/.ngrok2/ngrok.yml` for `authtoken:` line, falls back to Keychain
- `saveAuthToken(_:) async throws` — saves to Keychain, runs `ngrok config add-authtoken`
- `removeAuthToken() async` — removes from Keychain
- `hasAuthToken: Bool` — computed property

Detection order:
1. ngrok config file (modern path, then legacy path)
2. Keychain (`com.messagebridge.ngrok-authtoken`)

### 2. AppState Integration

- Add `ngrokAuthTokenConfigured: Bool` @Published property
- Call `detectAuthToken()` during `checkTunnelInstallations()`
- Add `saveNgrokAuthToken(_:)` and `removeNgrokAuthToken()` methods

### 3. Settings UI (TunnelSettingsView)

When ngrok selected, show authtoken section between install status and tunnel controls:

- **No token:** Yellow info box with signup link, SecureField, Save button
- **Token configured:** Green checkmark, Change/Remove buttons
- **Auto-detected:** Green checkmark noting detection source

Start tunnel button disabled without token.

### 4. Connect Guard

`startNgrokTunnel()` checks for authtoken before launching process. Surfaces clear error if missing.

### 5. Tests

- Config file parsing (valid YAML, missing file, legacy path)
- Keychain save/remove round-trip
- Connect-without-token error

## Implementation Steps

1. NgrokManager authtoken methods
2. AppState integration
3. TunnelSettingsView authtoken section
4. Connect guard
5. Tests
6. Update spec.md M2.3 status
