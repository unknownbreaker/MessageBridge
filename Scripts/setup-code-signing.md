# Code Signing Setup Guide

This guide explains how to set up code signing and notarization for MessageBridge releases.

## Prerequisites

- **Apple Developer Program membership** ($99/year)
  - Enroll at: https://developer.apple.com/programs/

## Step 1: Create a Developer ID Certificate

1. Open **Keychain Access** on your Mac
2. Go to **Keychain Access > Certificate Assistant > Request a Certificate From a Certificate Authority**
3. Enter your email and name, select "Saved to disk", click Continue
4. Save the certificate signing request (CSR) file

5. Go to https://developer.apple.com/account/resources/certificates/list
6. Click the **+** button to create a new certificate
7. Select **Developer ID Application** and click Continue
8. Upload your CSR file and click Continue
9. Download the certificate and double-click to install it in Keychain Access

## Step 2: Export the Certificate as .p12

1. Open **Keychain Access**
2. Find your "Developer ID Application" certificate (under "My Certificates")
3. Right-click and select **Export**
4. Save as `.p12` format
5. Set a strong password (you'll need this later)

## Step 3: Create an App-Specific Password

1. Go to https://appleid.apple.com/account/manage
2. Sign in with your Apple ID
3. In the Security section, click **App-Specific Passwords**
4. Click **Generate an app-specific password**
5. Name it "MessageBridge Notarization"
6. Save the generated password

## Step 4: Find Your Team ID

1. Go to https://developer.apple.com/account
2. Your Team ID is shown in the Membership section
3. It's a 10-character alphanumeric string (e.g., `ABC123XYZ9`)

## Step 5: Configure GitHub Secrets

Go to your GitHub repository: **Settings > Secrets and variables > Actions**

Add these secrets:

| Secret Name | Value |
|-------------|-------|
| `APPLE_DEVELOPER_CERTIFICATE_P12_BASE64` | Base64-encoded .p12 file (see below) |
| `APPLE_DEVELOPER_CERTIFICATE_PASSWORD` | Password you set when exporting .p12 |
| `DEVELOPER_ID_APPLICATION` | Full certificate name, e.g., `Developer ID Application: Your Name (TEAMID)` |
| `APPLE_ID` | Your Apple ID email |
| `APPLE_ID_PASSWORD` | The app-specific password from Step 3 |
| `APPLE_TEAM_ID` | Your 10-character Team ID |

### How to Base64 Encode Your Certificate

Run this command in Terminal:

```bash
base64 -i /path/to/your/certificate.p12 | pbcopy
```

This copies the base64-encoded certificate to your clipboard. Paste it as the `APPLE_DEVELOPER_CERTIFICATE_P12_BASE64` secret.

### Finding Your Full Certificate Name

Run this command to list your signing identities:

```bash
security find-identity -v -p codesigning
```

Look for the line with "Developer ID Application" - copy the full name including the Team ID in parentheses.

## Step 6: Test a Release

1. Bump the version:
   ```bash
   echo "0.3.4" > MessageBridgeClient/VERSION
   git add -A && git commit -m "chore: bump client version to 0.3.4"
   ```

2. Create and push a tag:
   ```bash
   git tag client-v0.3.4
   git push origin client-v0.3.4
   ```

3. Check the Actions tab on GitHub to monitor the build

4. Once complete, download the DMG and verify it opens without Gatekeeper warnings

## Local Signing (Optional)

To sign apps locally for testing:

```bash
export DEVELOPER_ID_APPLICATION="Developer ID Application: Your Name (TEAMID)"
export APPLE_ID="your@email.com"
export APPLE_ID_PASSWORD="xxxx-xxxx-xxxx-xxxx"  # App-specific password
export APPLE_TEAM_ID="ABC123XYZ9"

./Scripts/build-release.sh client
./Scripts/codesign-notarize.sh "build/MessageBridge.app"
./Scripts/create-dmgs.sh client
```

## Troubleshooting

### "No identity found"
- Make sure the certificate is installed in your Keychain
- Check that the certificate name matches exactly

### "Unable to notarize"
- Verify your Apple ID and app-specific password are correct
- Check that your Team ID is correct
- Make sure your Developer Program membership is active

### "The signature is invalid"
- Re-export the .p12 certificate and update the GitHub secret
- Make sure you included the private key when exporting

## Cost Summary

| Item | Cost |
|------|------|
| Apple Developer Program | $99/year |
| GitHub Actions | Free for public repos |
| **Total** | **$99/year** |
