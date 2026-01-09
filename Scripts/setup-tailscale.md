# Tailscale Setup for MessageBridge

This guide explains how to set up Tailscale to securely connect your work Mac (client) to your home Mac (server).

## Why Tailscale?

- **Zero-config VPN**: No port forwarding or firewall rules needed
- **End-to-end encrypted**: Uses WireGuard protocol
- **Works through NAT**: Connects devices behind firewalls
- **Free for personal use**: Up to 100 devices
- **Stable IPs**: Each device gets a consistent IP (e.g., `100.x.y.z`)

## Installation

### On Both Macs

1. **Download Tailscale** from the Mac App Store or https://tailscale.com/download

2. **Install and launch** the app

3. **Sign in** with the same account on both Macs (Google, Microsoft, GitHub, etc.)

4. **Verify connection** - Both Macs should appear in your Tailscale admin console at https://login.tailscale.com/admin/machines

## Configuration

### On Home Mac (Server)

1. **Note the Tailscale IP** - Click the Tailscale menu bar icon and note the IP address (e.g., `100.64.0.1`)

2. **Verify the server is accessible**:
   ```bash
   # From the home Mac, check the server is running
   curl http://localhost:8080/health
   ```

3. **The server binds to all interfaces** by default, making it accessible via Tailscale

### On Work Mac (Client)

1. **Configure the client** to connect using the home Mac's Tailscale IP:
   ```
   Server URL: http://100.64.0.1:8080
   API Key: (your-api-key)
   ```

2. **Test connectivity**:
   ```bash
   # From work Mac, ping home Mac
   ping 100.64.0.1

   # Test the API
   curl -H "X-API-Key: YOUR_KEY" http://100.64.0.1:8080/health
   ```

## Security Best Practices

### Enable MagicDNS (Optional)

MagicDNS lets you use hostnames instead of IP addresses:

1. Go to https://login.tailscale.com/admin/dns
2. Enable MagicDNS
3. Use `home-mac.tail-scale-name.ts.net:8080` instead of IP

### Access Control Lists (ACLs)

For additional security, restrict which devices can access the server:

1. Go to https://login.tailscale.com/admin/acls
2. Add rules to limit access:
   ```json
   {
     "acls": [
       {
         "action": "accept",
         "src": ["work-mac"],
         "dst": ["home-mac:8080"]
       }
     ]
   }
   ```

### Key Expiry

By default, Tailscale keys expire after 180 days. For a server that needs to stay connected:

1. Go to https://login.tailscale.com/admin/machines
2. Click on your home Mac
3. Disable key expiry for that machine

## Troubleshooting

### Connection Issues

1. **Check Tailscale status**:
   ```bash
   tailscale status
   ```

2. **Verify both devices are online** in the admin console

3. **Check firewall** - Tailscale should work through most firewalls, but verify it's not blocked

### Server Not Accessible

1. **Verify server is running**:
   ```bash
   curl http://localhost:8080/health
   ```

2. **Check server logs**:
   ```bash
   tail -f /usr/local/var/log/messagebridge/server.log
   ```

3. **Verify Tailscale is connected**:
   ```bash
   tailscale status
   ```

### Slow Connection

1. **Check DERP relay** - If direct connection fails, Tailscale uses relay servers which may add latency

2. **View connection type**:
   ```bash
   tailscale status --peers
   ```
   Look for "direct" vs "relay" connection

## Network Diagram

```
┌─────────────────────┐         Tailscale VPN        ┌─────────────────────┐
│     WORK MAC        │         (WireGuard)          │     HOME MAC        │
│  100.64.0.2         │◄────────────────────────────►│  100.64.0.1         │
│                     │                               │                     │
│  ┌───────────────┐  │    Encrypted Connection      │  ┌───────────────┐  │
│  │ Bridge Client │◄─┼───────────────────────────────┼──│ Bridge Server │  │
│  │  Port: N/A    │  │                               │  │  Port: 8080   │  │
│  └───────────────┘  │                               │  └───────────────┘  │
│                     │                               │                     │
└─────────────────────┘                               └─────────────────────┘
         │                                                      │
         │                                                      │
    Corporate                                              Home
    Firewall                                              Router
    (No ports                                            (No ports
     opened)                                              forwarded)
```

## Quick Reference

| Setting | Value |
|---------|-------|
| Server Port | 8080 |
| Protocol | HTTP (encrypted by Tailscale) |
| Home Mac Tailscale IP | Check menu bar icon |
| Admin Console | https://login.tailscale.com/admin |
