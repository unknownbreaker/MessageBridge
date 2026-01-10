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

    -- Get the path to this installer app
    set myPath to POSIX path of (path to me)

    -- Remove trailing slash if present
    if myPath ends with "/" then
        set myPath to text 1 thru -2 of myPath
    end if

    -- Get the folder containing the installer (the DMG volume)
    set installerFolder to do shell script "dirname " & quoted form of myPath
    set sourceApp to installerFolder & "/" & appFileName

    -- Check if source app exists
    set appExists to do shell script "test -d " & quoted form of sourceApp & " && echo 'yes' || echo 'no'"
    if appExists is "no" then
        display alert "Installation Error" message "Could not find " & appFileName & " in the disk image." as critical
        return
    end if

    -- Get the volume name (DMG mount point)
    set volumeName to do shell script "basename " & quoted form of installerFolder

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

    -- Find the DMG file path (the source of the mounted volume)
    set dmgPath to ""
    try
        set dmgInfo to do shell script "hdiutil info | grep -A 20 'image-path' | grep -B 1 " & quoted form of ("/Volumes/" & volumeName) & " | grep 'image-path' | head -1 | sed 's/.*image-path *: *//'"
        if dmgInfo is not "" then
            set dmgPath to dmgInfo
        end if
    end try

    -- Eject the DMG
    try
        do shell script "hdiutil detach " & quoted form of ("/Volumes/" & volumeName) & " -force"
    end try

    -- Move DMG to Trash if we found it
    if dmgPath is not "" then
        try
            do shell script "mv " & quoted form of dmgPath & " ~/.Trash/ 2>/dev/null || true"
        end try
    end if

    -- Show success and offer to launch
    set dialogResult to display dialog appName & " has been installed successfully!" buttons {"Close", "Open " & appName} default button 2 with icon note

    if button returned of dialogResult is ("Open " & appName) then
        do shell script "open " & quoted form of destApp
    end if
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

echo "Created installer: ${INSTALLER_PATH}"
