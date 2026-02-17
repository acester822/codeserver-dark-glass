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

# Get the directory where this script is located. When the script is fetched via
# curl | bash it runs from a temporary location — in that case clone the repo to
# a temp dir so we can access the repo files (package.json, themes, custom, etc.).
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# If package.json isn't next to the script assume we're running from a remote
# one-liner; clone the repository into a temp dir and continue from there.
if [ ! -f "$SCRIPT_DIR/package.json" ]; then
    echo "⚙️  installer running from remote - cloning repository to a temporary folder..."
    REPO_URL="https://github.com/acester822/codeserver-dark-glass.git"
    CLONE_DIR="$(mktemp -d /tmp/codeserver-dark-glass.XXXX)"
    # attempt a shallow clone
    if git clone --depth 1 "$REPO_URL" "$CLONE_DIR" >/dev/null 2>&1; then
        echo "  ✓ cloned $REPO_URL -> $CLONE_DIR"
        SCRIPT_DIR="$CLONE_DIR"
        # cleanup on exit
        trap 'rm -rf "$CLONE_DIR"' EXIT
    else
        echo -e "${RED}❌ Failed to download repository ($REPO_URL).${NC}"
        echo "Please clone the repo and run the installer from the repo directory." 
        exit 1
    fi
fi

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

// Strip JSONC features (comments and trailing commas) for JSON.parse
function stripJsonc(text) {
    // Remove single-line comments (but not // inside strings)
    text = text.replace(/\/\/(?=(?:[^"\\]|\\.)*$)/gm, '');
    // Remove multi-line comments
    text = text.replace(/\/\*[\s\S]*?\*\//g, '');
    // Remove trailing commas before } or ]
    text = text.replace(/,\s*([}\]])/g, '$1');
    return text;
}

const scriptDir = process.cwd();
const newSettings = JSON.parse(stripJsonc(fs.readFileSync(path.join(scriptDir, 'settings.json'), 'utf8')));

const home = process.env.HOME;
// Use code-server user settings exclusively
const settingsDir = path.join(home, '.local/share/code-server/User');
const settingsFile = path.join(settingsDir, 'settings.json');
const existingText = fs.existsSync(settingsFile) ? fs.readFileSync(settingsFile, 'utf8') : '{}';
const existingSettings = JSON.parse(stripJsonc(existingText));

// Merge settings - Islands Dark settings take precedence
const mergedSettings = { ...existingSettings, ...newSettings };

// Deep merge custom-ui-style.stylesheet
const stylesheetKey = 'custom-ui-style.stylesheet';
if (existingSettings[stylesheetKey] && newSettings[stylesheetKey]) {
    mergedSettings[stylesheetKey] = {
        ...existingSettings[stylesheetKey],
        ...newSettings[stylesheetKey]
    };
}

fs.mkdirSync(settingsDir, { recursive: true });
fs.writeFileSync(settingsFile, JSON.stringify(mergedSettings, null, 2));
console.log('Settings merged successfully');
NODE_SCRIPT
        else
                echo -e "${YELLOW}   Node.js not found. Please manually merge settings.json from this repo into your code-server settings.${NC}"
                echo "   Your original settings have been backed up to settings.json.backup"
        fi
else
    # No existing settings, just copy
    cp "$SCRIPT_DIR/settings.json" "$SETTINGS_FILE"
    echo -e "${GREEN}✓ Settings applied${NC}"
fi

echo ""
echo -e "${GREEN}Done! 🏝️${NC}"

echo ""
echo "🔧 Step 3: (optional) Install CSS directly into code-server (no Custom UI Style)"
echo "    — will copy 'custom/' into your code-server user data, inject an @import into workbench.css,
            create a symlink from the workbench folder to the user 'custom' folder, and install Seti Folder icon theme."

# Direct-theming steps provided by user (idempotent where possible)
CUSTOM_SRC="$SCRIPT_DIR/custom"
USER_CUSTOM_DIR="$HOME/.local/share/code-server/custom"
WORKBENCH_CANDIDATES=(
    "/usr/lib/code-server/lib/vscode/out/vs/code/browser/workbench/workbench.css"
    "/usr/lib/code-server/lib/vscode/out/vs/workbench/workbench.css"
)

echo "\n• Adjusting ownership so code-server can load user customizations (sudo may be required)"
for d in "$HOME/.config/code-server" "$HOME/.local/share/code-server" "/usr/lib/code-server"; do
    if [ -d "$d" ]; then
        echo "  - chown $d -> $(whoami)"
        sudo chown -R "$(whoami)" "$d" || echo "    ⚠️  failed to chown $d (check permissions)"
    else
        echo "  - skipping $d (not found)"
    fi
done

# locate workbench.css
WORKBENCH_CSS=""
for p in "${WORKBENCH_CANDIDATES[@]}"; do
    if [ -f "$p" ]; then
        WORKBENCH_CSS="$p"
        break
    fi
done
if [ -z "$WORKBENCH_CSS" ]; then
    WORKBENCH_CSS=$(sudo find /usr/lib/code-server -type f -name 'workbench.css' 2>/dev/null | head -n 1 || true)
fi

if [ -z "$WORKBENCH_CSS" ]; then
    echo -e "${YELLOW}⚠️  workbench.css not found under /usr/lib/code-server — skipping CSS injection step${NC}"
else
    echo "\n• workbench.css -> $WORKBENCH_CSS"

    # backup and inject import if missing
    if sudo grep -q '@import url("./custom/active.css");' "$WORKBENCH_CSS" 2>/dev/null; then
        echo "  - import already present in workbench.css"
    else
        echo "  - backing up workbench.css -> ${WORKBENCH_CSS}.bak"
        sudo cp "$WORKBENCH_CSS" "${WORKBENCH_CSS}.bak" || true
        echo "  - inserting @import at top of workbench.css"
        sudo sed -i '1i @import url("./custom/active.css");' "$WORKBENCH_CSS" || echo "    ⚠️  failed to inject — try running script with sudo"
    fi

    # copy custom/ to user data
    if [ -d "$CUSTOM_SRC" ]; then
        echo "  - copying custom/ -> $USER_CUSTOM_DIR"
        mkdir -p "$USER_CUSTOM_DIR"
        rsync -a --delete "$CUSTOM_SRC/" "$USER_CUSTOM_DIR/"
        sudo chown -R "$(whoami)" "$USER_CUSTOM_DIR" || true
    else
        echo "  - no local 'custom/' folder found in the repo — skipping copy"
    fi

    # create symlink from workbench folder to user custom folder
    WORKBENCH_DIR=$(dirname "$WORKBENCH_CSS")
    if [ -L "$WORKBENCH_DIR/custom" ] || [ -d "$WORKBENCH_DIR/custom" ]; then
        echo "  - removing existing $WORKBENCH_DIR/custom"
        sudo rm -rf "$WORKBENCH_DIR/custom" || true
    fi
    echo "  - creating symlink: $WORKBENCH_DIR/custom -> $USER_CUSTOM_DIR"
    sudo ln -sfn "$USER_CUSTOM_DIR" "$WORKBENCH_DIR/custom" || echo "    ⚠️  failed to create symlink (permission denied)"
fi

# install recommended icon theme for best results
echo "\n• Installing recommended icon theme: l-igh-t.vscode-theme-seti-folder"
if code-server --install-extension l-igh-t.vscode-theme-seti-folder --force 2>/dev/null; then
    echo -e "${GREEN}✓ Seti Folder icon theme installed${NC}"
else
    echo -e "${YELLOW}⚠️  Could not install Seti Folder automatically. Run: code-server --install-extension l-igh-t.vscode-theme-seti-folder${NC}"
fi

echo "\n✅ Built-in custom theming steps complete. Restart code-server (or refresh browser) to see changes."
    echo "\n• workbench.css -> $WORKBENCH_CSS"
