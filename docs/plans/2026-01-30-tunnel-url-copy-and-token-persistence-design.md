# Tunnel URL Copy & ngrok Token Persistence

## Problem

1. **Copying the tunnel URL requires navigating to Settings** — too many clicks for a frequent action.
2. **ngrok auth token lost on each Xcode rebuild** — likely because rebuilding changes the code signing identity, invalidating Keychain access.

## Design

### 1. Copy Tunnel URL from Menu Bar

Add a "Copy Tunnel URL" button as a top-level item in the `ServerMenuView` popover:

- Visible only when a tunnel is actively running
- One click copies URL to clipboard via `appState.copyTunnelURL()`
- Shows "Copied!" confirmation for ~2 seconds, then reverts

**File:** `ServerMenuView.swift`

### 2. Fix ngrok Auth Token Persistence

**Root cause:** `saveAuthToken` relies on the ngrok CLI binary (`ngrok config add-authtoken`) to write the config file. If the binary isn't found, only Keychain is written — and Keychain entries are tied to the app's code signing identity, which changes on rebuild.

**Fix:**

- **`saveAuthToken`**: Write directly to `~/.config/ngrok/ngrok.yml` as a fallback when the ngrok binary isn't available. Keep Keychain as secondary store.
- **`detectAuthToken`**: Add self-healing — if config file has the token but Keychain read fails, re-save to Keychain silently.

**File:** `NgrokManager.swift`

## Files Changed

| File | Change |
|------|--------|
| `ServerMenuView.swift` | Add "Copy Tunnel URL" button to menu popover |
| `NgrokManager.swift` | Direct config file write fallback + Keychain self-healing |
