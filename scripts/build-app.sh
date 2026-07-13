#!/bin/bash
# ---------------------------------------------------------
# build-app.sh — Build UsageMonitor.app from source
#
# This script:
#   1. Compiles the Swift code in release mode
#   2. Creates a proper macOS .app bundle directory structure
#   3. Copies the binary and Info.plist into the bundle
#   4. Optionally code-signs the app (for distribution)
#
# Usage:
#   ./scripts/build-app.sh
#   BUILD_ARCH=arm64 ./scripts/build-app.sh
#
# Output:
#   build/UsageMonitor.app
# ---------------------------------------------------------

set -euo pipefail  # Exit on any error

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'  # No Color

echo -e "${GREEN}=== Building 用量监控 ===${NC}"

# ── Step 1: Compile ──────────────────────────────────────
if [ "${DEBUG:-}" = "1" ]; then
    BUILD_CONFIG="debug"
else
    BUILD_CONFIG="release"
fi

BUILD_ARGS=(-c "$BUILD_CONFIG")
if [ -n "${BUILD_ARCH:-}" ]; then
    BUILD_ARGS+=(--arch "$BUILD_ARCH")
fi

echo -e "${YELLOW}Compiling Swift code ($BUILD_CONFIG, ${BUILD_ARCH:-native} architecture)...${NC}"
swift build "${BUILD_ARGS[@]}"

# Ask SwiftPM for the architecture-specific output directory.
BIN_DIR="$(swift build "${BUILD_ARGS[@]}" --show-bin-path)"
BINARY_PATH="$BIN_DIR/UsageMonitor"
if [ ! -f "$BINARY_PATH" ]; then
    echo -e "${RED}Error: Binary not found at $BINARY_PATH${NC}"
    echo "Make sure the Swift build completed successfully."
    exit 1
fi

echo -e "${GREEN}Compilation successful!${NC}"

# ── Step 2: Create .app bundle structure ─────────────────
# macOS .app bundles are just directories with a specific structure:
#
#   UsageMonitor.app/
#     Contents/
#       Info.plist          ← App metadata
#       MacOS/
#         UsageMonitor      ← The actual binary
#       Resources/          ← Icons, assets (optional)

APP_DIR="build/UsageMonitor.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

echo -e "${YELLOW}Creating .app bundle...${NC}"

# Clean previous build
rm -rf "$APP_DIR"

# Create directory structure
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# ── Step 3: Copy files into bundle ───────────────────────
echo -e "${YELLOW}Copying binary and resources...${NC}"

# Copy the compiled binary
cp "$BINARY_PATH" "$MACOS_DIR/UsageMonitor"

# Make it executable
chmod +x "$MACOS_DIR/UsageMonitor"

# Copy Info.plist (tells macOS about our app)
cp "Resources/Info.plist" "$CONTENTS_DIR/Info.plist"

# Copy app icon
if [ -f "Resources/AppIcon.icns" ]; then
    cp "Resources/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
    echo -e "${GREEN}App icon bundled!${NC}"
fi

# ── Step 4: Optional code signing ────────────────────────
# Code signing is required for:
#   - App Store distribution
#   - Gatekeeper (macOS security) approval
#   - Notarization
#
# For local development, you can skip this.
# For distribution, you need an Apple Developer account.

if [ -n "${CODESIGN_IDENTITY:-}" ]; then
    IDENTITY="$CODESIGN_IDENTITY"
    SIGNING_SOURCE="CODESIGN_IDENTITY"
else
    IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | awk -F '"' '/"Apple Development:/{ print $2; exit }')"
    if [ -n "$IDENTITY" ]; then
        SIGNING_SOURCE="auto-detected Apple Development"
    else
        IDENTITY="-"  # "-" means ad-hoc signing
        SIGNING_SOURCE="ad-hoc fallback"
    fi
fi

echo -e "${YELLOW}Code signing with identity: $IDENTITY ($SIGNING_SOURCE)${NC}"
codesign --force --deep --sign "$IDENTITY" "$APP_DIR"
echo -e "${GREEN}Code signing complete!${NC}"

# ── Done! ────────────────────────────────────────────────
echo ""
echo -e "${GREEN}=== Build complete! ===${NC}"
echo -e "App bundle: ${GREEN}$APP_DIR${NC}"
echo ""
echo "To run the app:"
echo "  open $APP_DIR"
echo ""
echo "To code sign for distribution:"
echo "  CODESIGN=1 CODESIGN_IDENTITY=\"Developer ID Application: Your Name\" ./scripts/build-app.sh"
