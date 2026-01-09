#!/bin/bash
set -e

# Generate macOS app icons from SVG
# Requires: rsvg-convert (from librsvg) or Inkscape for SVG to PNG conversion

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
ASSETS_DIR="$PROJECT_DIR/Assets"
SVG_FILE="$ASSETS_DIR/icon.svg"

# Check for SVG conversion tool
if command -v rsvg-convert &> /dev/null; then
    CONVERTER="rsvg-convert"
elif command -v inkscape &> /dev/null; then
    CONVERTER="inkscape"
elif command -v convert &> /dev/null; then
    CONVERTER="convert"
else
    echo "Error: No SVG converter found. Please install one of:"
    echo "  - librsvg: brew install librsvg"
    echo "  - Inkscape: brew install inkscape"
    echo "  - ImageMagick: brew install imagemagick"
    exit 1
fi

echo "Using $CONVERTER for SVG conversion"

# Create iconset directories
SERVER_ICONSET="$ASSETS_DIR/AppIcon-Server.iconset"
CLIENT_ICONSET="$ASSETS_DIR/AppIcon-Client.iconset"

mkdir -p "$SERVER_ICONSET"
mkdir -p "$CLIENT_ICONSET"

# Required sizes for macOS app icons
SIZES=(16 32 64 128 256 512 1024)

convert_svg() {
    local size=$1
    local output=$2

    case $CONVERTER in
        rsvg-convert)
            rsvg-convert -w "$size" -h "$size" "$SVG_FILE" -o "$output"
            ;;
        inkscape)
            inkscape -w "$size" -h "$size" "$SVG_FILE" -o "$output" 2>/dev/null
            ;;
        convert)
            convert -background none -resize "${size}x${size}" "$SVG_FILE" "$output"
            ;;
    esac
}

echo "Generating icon sizes..."

for size in "${SIZES[@]}"; do
    echo "  ${size}x${size}..."

    # Standard resolution
    if [ $size -le 512 ]; then
        convert_svg $size "$SERVER_ICONSET/icon_${size}x${size}.png"
        cp "$SERVER_ICONSET/icon_${size}x${size}.png" "$CLIENT_ICONSET/icon_${size}x${size}.png"
    fi

    # @2x Retina resolution (for sizes up to 512)
    half=$((size / 2))
    if [ $half -ge 16 ] && [ $half -le 512 ]; then
        convert_svg $size "$SERVER_ICONSET/icon_${half}x${half}@2x.png"
        cp "$SERVER_ICONSET/icon_${half}x${half}@2x.png" "$CLIENT_ICONSET/icon_${half}x${half}@2x.png"
    fi
done

echo "Creating .icns files..."

# Create .icns files using iconutil
iconutil -c icns "$SERVER_ICONSET" -o "$ASSETS_DIR/AppIcon-Server.icns"
iconutil -c icns "$CLIENT_ICONSET" -o "$ASSETS_DIR/AppIcon-Client.icns"

echo "Copying icons to app targets..."

# Copy to server app
SERVER_RESOURCES="$PROJECT_DIR/MessageBridgeServer/Sources/MessageBridgeServer/Resources"
mkdir -p "$SERVER_RESOURCES"
cp "$ASSETS_DIR/AppIcon-Server.icns" "$SERVER_RESOURCES/AppIcon.icns"

# Copy to client app
CLIENT_RESOURCES="$PROJECT_DIR/MessageBridgeClient/Sources/MessageBridgeClient/Resources"
mkdir -p "$CLIENT_RESOURCES"
cp "$ASSETS_DIR/AppIcon-Client.icns" "$CLIENT_RESOURCES/AppIcon.icns"

echo ""
echo "================================"
echo "Icon generation complete!"
echo "================================"
echo ""
echo "Generated files:"
echo "  $ASSETS_DIR/AppIcon-Server.icns"
echo "  $ASSETS_DIR/AppIcon-Client.icns"
echo ""
echo "Note: You may need to update your Package.swift or Xcode project"
echo "to include the .icns files in the app bundle."
