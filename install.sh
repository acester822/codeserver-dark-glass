#!/bin/bash

set -e

echo "🏝️  Ace911's Dark Glass Installer for code-server"
echo "================================================"
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check for code-server CLI
if ! command -v code-server &> /dev/null; then
    echo -e "${RED}❌ code-server CLI not found${NC}"
    echo "This script is designed exclusively for code-server."
    echo "Please install code-server and ensure it's in your PATH."
    exit 1
fi

echo -e "${GREEN}✓ code-server CLI found${NC}"

# Get the directory where this script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

echo ""
echo "📦 Step 1: Installing Ace911's Dark Glass Theme extension..."

# Read extension identity from package.json so we don't hard-code the publisher/name/version
EXT_PUBLISHER=$(sed -n 's/.*"publisher"\s*:\s*"\([^"]*\)".*/\1/p' "$SCRIPT_DIR/package.json" || true)
EXT_NAME=$(sed -n 's/.*"name"\s*:\s*"\([^"]*\)".*/\1/p' "$SCRIPT_DIR/package.json" || true)
EXT_VERSION=$(sed -n 's/.*"version"\s*:\s*"\([^"]*\)".*/\1/p' "$SCRIPT_DIR/package.json" || true)

if [ -z "$EXT_PUBLISHER" ] || [ -z "$EXT_NAME" ] || [ -z "$EXT_VERSION" ]; then
    echo -e "${RED}❌ Could not read package.json metadata (publisher/name/version)${NC}"
    exit 1
fi

# Use code-server extension directory exclusively
EXT_DIR="$HOME/.local/share/code-server/extensions/${EXT_PUBLISHER}.${EXT_NAME}-${EXT_VERSION}"

rm -rf "$EXT_DIR" 2>/dev/null || true
mkdir -p "$EXT_DIR"
cp "$SCRIPT_DIR/package.json" "$EXT_DIR/"
cp -r "$SCRIPT_DIR/themes" "$EXT_DIR/" || true

if [ -d "$EXT_DIR/themes" ]; then
    echo -e "${GREEN}✓ Theme extension installed to $EXT_DIR${NC}"
else
    echo -e "${RED}❌ Failed to install theme extension${NC}"
    exit 1
fi

echo ""
echo "⚙️  Step 2: Applying VS Code settings..."
# Use code-server user settings directory exclusively
SETTINGS_DIR="$HOME/.local/share/code-server/User"

mkdir -p "$SETTINGS_DIR"
SETTINGS_FILE="$SETTINGS_DIR/settings.json"

# Check if settings.json exists
if [ -f "$SETTINGS_FILE" ]; then
    echo -e "${YELLOW}⚠️  Existing settings.json found${NC}"
    echo "   Backing up to settings.json.backup"
    cp "$SETTINGS_FILE" "$SETTINGS_FILE.backup"

    # Read the existing settings and merge
    echo "   Merging Islands Dark settings with your existing settings..."

        # Create a temporary file with the merge logic using node.js if available
        if command -v node &> /dev/null; then
                node << 'NODE_SCRIPT'
const fs = require('fs');
const path = require('path');

function stripJsonc(text) {
    // Remove single-line comments (but not // inside strings)
    text = text.replace(/\/\/(?=(?:[^"\\]|\\.)*$)/gm, '');
    text = text.replace(/\/\*[\s\S]*?\*\//g, '');
    text = text.replace(/,\s*([}\]])/g, '$1');
    return text;
}

const scriptDir = process.cwd();
const newSettings = JSON.parse(stripJsonc(fs.readFileSync(path.join(scriptDir, 'settings.json'), 'utf8')));

const home = process.env.HOME;
// Use code-server user settings exclusively
const settingsDir = path.join(home, '.local/share/code-server/User');
const settingsFile = path.join(settingsDir, 'settings.json');

let existingSettings = {};
try {
    if (fs.existsSync(settingsFile)) {
        existingSettings = JSON.parse(stripJsonc(fs.readFileSync(settingsFile, 'utf8')));
    }
} catch (e) {
    console.error('Could not read existing settings.json — aborting merge.');
    process.exit(1);
}

// Merge settings - Islands Dark settings take precedence
const mergedSettings = { ...existingSettings, ...newSettings };

// Deep merge custom-ui-style.stylesheet if both exist
const stylesheetKey = 'custom-ui-style.stylesheet';
if (existingSettings[stylesheetKey] && newSettings[stylesheetKey]) {
    mergedSettings[stylesheetKey] = { ...existingSettings[stylesheetKey], ...newSettings[stylesheetKey] };
}

fs.writeFileSync(settingsFile, JSON.stringify(mergedSettings, null, 2));
console.log('Settings merged successfully ->', settingsFile);
NODE_SCRIPT
        else
                echo -e "${RED}❌ Node.js not found. Cannot merge settings.${NC}"
                exit 1
        fi
else
    # No existing settings, just copy
    cp "$SCRIPT_DIR/settings.json" "$SETTINGS_FILE"
    echo -e "${GREEN}✓ Settings applied${NC}"
fi

echo ""
echo -e "${GREEN}Done! 🏝️${NC}"
