# Cloudflare Tunnel Setup for MessageBridge

This guide explains how to set up Cloudflare Tunnel to securely expose your MessageBridge server over the internet, without port forwarding or a static IP.

## Why Cloudflare Tunnel?

Cloudflare Tunnel (formerly Argo Tunnel) creates an encrypted tunnel between your home Mac and Cloudflare's edge network. Benefits:

- **No port forwarding required** - Works behind NAT/firewalls
- **No static IP needed** - Works with dynamic home IP
- **Free** - For personal use
- **Encrypted** - All traffic is encrypted via TLS
- **With E2E encryption** - Message content is encrypted before reaching Cloudflare

**Important**: When using Cloudflare Tunnel, enable E2E encryption in MessageBridge settings. This ensures Cloudflare cannot read your message content - they only see encrypted bytes.

## Prerequisites

1. A Cloudflare account (free): https://dash.cloudflare.com/sign-up
2. A domain name added to Cloudflare (or use Cloudflare's free `.trycloudflare.com` subdomain for quick testing)

## Option 1: Quick Testing (No Domain Required)

For quick testing, you can use Cloudflare's temporary URLs without a domain:

```bash
# Install cloudflared
brew install cloudflared

# Run a quick tunnel (creates a temporary URL)
cloudflared tunnel --url http://localhost:8080
```

This will output a URL like `https://random-words.trycloudflare.com`. Use this URL in the MessageBridge client.

**Note**: This URL changes each time you restart cloudflared. For permanent use, set up a named tunnel (Option 2).

## Option 2: Permanent Setup (Recommended)

### Step 1: Install cloudflared

```bash
brew install cloudflared
```

### Step 2: Login to Cloudflare

```bash
cloudflared tunnel login
```

This opens a browser window. Select your domain and authorize.

### Step 3: Create a Named Tunnel

```bash
cloudflared tunnel create messagebridge
```

This creates a tunnel and outputs a UUID like `a1b2c3d4-5678-90ab-cdef-1234567890ab`. Save this ID.

### Step 4: Configure the Tunnel

Create a config file at `~/.cloudflared/config.yml`:

```yaml
tunnel: messagebridge
credentials-file: /Users/YOUR_USERNAME/.cloudflared/a1b2c3d4-5678-90ab-cdef-1234567890ab.json

ingress:
  - hostname: messagebridge.yourdomain.com
    service: http://localhost:8080
  - service: http_status:404
```

Replace:
- `YOUR_USERNAME` with your macOS username
- `a1b2c3d4...` with your tunnel UUID
- `yourdomain.com` with your domain

### Step 5: Create DNS Record

```bash
cloudflared tunnel route dns messagebridge messagebridge.yourdomain.com
```

### Step 6: Run the Tunnel

```bash
cloudflared tunnel run messagebridge
```

### Step 7: Configure MessageBridge Client

In the MessageBridge client settings:
- **Server URL**: `https://messagebridge.yourdomain.com`
- **API Key**: Your API key from the server
- **E2E Encryption**: Enable this!

## Running as a Launch Agent

To run cloudflared automatically on login:

### Step 1: Create Launch Agent

Create `~/Library/LaunchAgents/com.cloudflare.cloudflared.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.cloudflare.cloudflared</string>
    <key>ProgramArguments</key>
    <array>
        <string>/opt/homebrew/bin/cloudflared</string>
        <string>tunnel</string>
        <string>run</string>
        <string>messagebridge</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/usr/local/var/log/cloudflared/output.log</string>
    <key>StandardErrorPath</key>
    <string>/usr/local/var/log/cloudflared/error.log</string>
</dict>
</plist>
```

### Step 2: Create Log Directory

```bash
sudo mkdir -p /usr/local/var/log/cloudflared
sudo chown $(whoami) /usr/local/var/log/cloudflared
```

### Step 3: Load the Launch Agent

```bash
launchctl load ~/Library/LaunchAgents/com.cloudflare.cloudflared.plist
```

### Managing the Service

```bash
# Start
launchctl load ~/Library/LaunchAgents/com.cloudflare.cloudflared.plist

# Stop
launchctl unload ~/Library/LaunchAgents/com.cloudflare.cloudflared.plist

# Restart
launchctl kickstart -k gui/$(id -u)/com.cloudflare.cloudflared

# View logs
tail -f /usr/local/var/log/cloudflared/output.log
```

## Security Considerations

1. **Always enable E2E encryption** when using Cloudflare Tunnel. This ensures:
   - Cloudflare cannot read your message content
   - Only encrypted data passes through their network
   - Your API key is used to derive the encryption key

2. **API key security**: Your API key serves two purposes:
   - Authentication with the server
   - Derivation of the E2E encryption key
   - Never share your API key

3. **Access control**: Consider using Cloudflare Access for additional security (IP restrictions, authentication, etc.)

## Troubleshooting

### Tunnel not connecting

```bash
# Check tunnel status
cloudflared tunnel info messagebridge

# Test local connection
curl http://localhost:8080/health
```

### DNS not resolving

```bash
# Verify DNS record
cloudflared tunnel route dns messagebridge messagebridge.yourdomain.com --force

# Check DNS propagation
dig messagebridge.yourdomain.com
```

### Connection timeout

1. Ensure MessageBridge server is running on port 8080
2. Check if the tunnel is running: `cloudflared tunnel list`
3. Verify the config file hostname matches your DNS record

## Alternative: SSH Tunnel

If you have SSH access to your home Mac from elsewhere, you can use SSH port forwarding instead:

```bash
# On your work Mac
ssh -L 8080:localhost:8080 your-home-mac.local

# Then configure MessageBridge client to use:
# Server URL: http://localhost:8080
```

This requires your home Mac to be reachable via SSH (e.g., through a VPN or with a static IP).
