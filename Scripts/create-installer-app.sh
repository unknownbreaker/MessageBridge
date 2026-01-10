#!/bin/bash
#
# Creates an "Install" app for DMG installers
#
# Usage: ./create-installer-app.sh <app-name> <output-dir>
# Example: ./create-installer-app.sh "MessageBridge" ./build
#

set -e

APP_NAME="$1"
OUTPUT_DIR="$2"

if [[ -z "$APP_NAME" ]] || [[ -z "$OUTPUT_DIR" ]]; then
    echo "Usage: $0 <app-name> <output-dir>"
    exit 1
fi

INSTALLER_NAME="Install ${APP_NAME}"
INSTALLER_PATH="${OUTPUT_DIR}/${INSTALLER_NAME}.app"

# Remove existing installer
rm -rf "$INSTALLER_PATH"

# Create temporary AppleScript file
TEMP_SCRIPT=$(mktemp /tmp/installer_script.XXXXXX)

cat > "$TEMP_SCRIPT" << 'APPLESCRIPT_END'
-- Installer Script
on run
    set appName to "APP_NAME_PLACEHOLDER"
    set appFileName to appName & ".app"
    set installerName to "Install " & appName & ".app"

    -- Try to find the source app
    -- First, try path to me (works if not translocated)
    set sourceApp to ""
    set volumePath to ""

    try
        set myPath to POSIX path of (path to me)
        if myPath ends with "/" then
            set myPath to text 1 thru -2 of myPath
        end if
        set installerFolder to do shell script "dirname " & quoted form of myPath
        set candidateApp to installerFolder & "/" & appFileName
        set appExists to do shell script "test -d " & quoted form of candidateApp & " && echo 'yes' || echo 'no'"
        if appExists is "yes" then
            set sourceApp to candidateApp
            set volumePath to installerFolder
        end if
    end try

    -- If not found (likely due to App Translocation), search mounted volumes
    if sourceApp is "" then
        try
            -- Find volumes that contain both the app and installer
            set volumeSearch to do shell script "for vol in /Volumes/*/; do if [ -d \"${vol}" & appFileName & "\" ] && [ -d \"${vol}" & installerName & "\" ]; then echo \"${vol%/}\"; break; fi; done"
            if volumeSearch is not "" then
                set sourceApp to volumeSearch & "/" & appFileName
                set volumePath to volumeSearch
            end if
        end try
    end if

    -- Still not found? Show error
    if sourceApp is "" then
        display alert "Installation Error" message "Could not find " & appFileName & " in any mounted disk image. Please make sure the disk image is mounted." as critical
        return
    end if

    -- Destination in Applications
    set destApp to "/Applications/" & appFileName

    -- Check if app already exists in Applications
    set destExists to do shell script "test -d " & quoted form of destApp & " && echo 'yes' || echo 'no'"

    if destExists is "yes" then
        set dialogResult to display dialog appName & " is already installed. Do you want to replace it?" buttons {"Cancel", "Replace"} default button "Replace" with icon caution
        if button returned of dialogResult is "Cancel" then
            return
        end if
        -- Remove existing app
        try
            do shell script "rm -rf " & quoted form of destApp with administrator privileges
        on error errMsg
            display alert "Error" message "Could not remove existing installation: " & errMsg as critical
            return
        end try
    end if

    -- Copy app to Applications
    try
        do shell script "cp -R " & quoted form of sourceApp & " /Applications/" with administrator privileges
    on error errMsg
        display alert "Installation Failed" message "Could not copy " & appName & " to Applications: " & errMsg as critical
        return
    end try

    -- Show success message BEFORE ejecting (installer runs from DMG!)
    display dialog appName & " has been installed successfully!" buttons {"OK"} default button "OK" with icon note

    -- Eject the DMG and optionally move to trash (all errors silenced)
    -- This happens AFTER the dialog so the installer code is still accessible
    try
        -- Find the DMG file path before ejecting
        set dmgPath to do shell script "hdiutil info | awk -v vol=" & quoted form of volumePath & " '
            /^image-path/ { img = $0; sub(/^image-path[[:space:]]*:[[:space:]]*/, \"\", img) }
            $0 ~ vol { if (img != \"\") print img; exit }
        '"

        -- Eject the DMG
        do shell script "hdiutil detach " & quoted form of volumePath & " -force 2>/dev/null || true"

        -- Try to move DMG to trash (completely optional, ignore all errors)
        if dmgPath is not "" then
            try
                do shell script "mv " & quoted form of dmgPath & " ~/.Trash/ 2>/dev/null"
            end try
        end if
    end try
end run
APPLESCRIPT_END

# Replace placeholder with actual app name
sed -i '' "s/APP_NAME_PLACEHOLDER/${APP_NAME}/g" "$TEMP_SCRIPT"

# Compile the AppleScript to an app
osacompile -o "$INSTALLER_PATH" "$TEMP_SCRIPT"

# Clean up temp file
rm -f "$TEMP_SCRIPT"

# Update Info.plist with proper metadata
cat > "${INSTALLER_PATH}/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>applet</string>
    <key>CFBundleIdentifier</key>
    <string>com.messagebridge.installer</string>
    <key>CFBundleName</key>
    <string>${INSTALLER_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>12.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

# Code sign the installer app with hardened runtime (required for notarization)
SIGNING_IDENTITY="${SIGNING_IDENTITY:-Developer ID Application}"
if security find-identity -v -p codesigning | grep -q "$SIGNING_IDENTITY"; then
    echo "Signing installer with: $SIGNING_IDENTITY"
    codesign --force --deep --options runtime --sign "$SIGNING_IDENTITY" "$INSTALLER_PATH"
    echo "Created and signed installer: ${INSTALLER_PATH}"
else
    echo "Warning: No signing identity found. Installer will trigger Gatekeeper warnings."
    echo "Created unsigned installer: ${INSTALLER_PATH}"
fi
