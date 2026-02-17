#!/bin/bash

set -e

echo "🗑️  Ace911's Dark Glass Uninstaller for code-server"
echo "==================================================="
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
    exit 1
fi

echo -e "${GREEN}✓ code-server CLI found${NC}"
echo ""

# ---------------------------------------------------------------------------
# Step 1: Remove the Dark Glass theme extension
# ---------------------------------------------------------------------------
echo "📦 Step 1: Removing Dark Glass theme extension..."

EXT_ID="acester822.dark-glass"
EXT_DIR_PATTERN="$HOME/.local/share/code-server/extensions/acester822.dark-glass-*"

# Remove extension directory
REMOVED_EXT=false
for d in $EXT_DIR_PATTERN; do
    if [ -d "$d" ]; then
        rm -rf "$d"
        echo -e "${GREEN}✓ Removed extension directory: $d${NC}"
        REMOVED_EXT=true
    fi
done

if [ "$REMOVED_EXT" != true ]; then
    echo -e "${YELLOW}⚠️  No Dark Glass extension directory found — skipping${NC}"
fi

# Deregister from extensions.json
EXT_JSON="$HOME/.local/share/code-server/extensions/extensions.json"
if [ -f "$EXT_JSON" ] && command -v node &> /dev/null; then
    DEREGISTER_SCRIPT=$(mktemp /tmp/deregister-ext.XXXXX.js)
    cat > "$DEREGISTER_SCRIPT" << 'DEREGEOF'
const fs = require('fs');
const extJson = process.argv[2];
const extId = process.argv[3];

let extensions = [];
try {
    extensions = JSON.parse(fs.readFileSync(extJson, 'utf8'));
} catch (e) {
    process.exit(0);
}

const before = extensions.length;
extensions = extensions.filter(e => !(e.identifier && e.identifier.id === extId));

if (extensions.length < before) {
    fs.writeFileSync(extJson, JSON.stringify(extensions, null, 4));
    console.log('Extension deregistered from extensions.json');
} else {
    console.log('Extension was not registered in extensions.json');
}
DEREGEOF
    node "$DEREGISTER_SCRIPT" "$EXT_JSON" "$EXT_ID"
    rm -f "$DEREGISTER_SCRIPT"
    echo -e "${GREEN}✓ Extension deregistered from code-server${NC}"
elif [ -f "$EXT_JSON" ]; then
    echo -e "${YELLOW}⚠️  Node.js not available — could not deregister from extensions.json${NC}"
    echo "   You may need to manually remove the Dark Glass entry from:"
    echo "   $EXT_JSON"
fi

echo ""

# ---------------------------------------------------------------------------
# Step 2: Remove Dark Glass settings from settings.json
# ---------------------------------------------------------------------------
echo "⚙️  Step 2: Removing Dark Glass settings..."

SETTINGS_FILE="$HOME/.local/share/code-server/User/settings.json"

if [ -f "$SETTINGS_FILE" ] && command -v node &> /dev/null; then
    echo "   Backing up to settings.json.pre-uninstall"
    cp "$SETTINGS_FILE" "$SETTINGS_FILE.pre-uninstall"

    CLEANUP_SCRIPT=$(mktemp /tmp/cleanup-settings.XXXXX.js)
    cat > "$CLEANUP_SCRIPT" << 'CLEANEOF'
const fs = require('fs');

// Strip JSONC features so JSON.parse can handle it
function stripJsonc(text) {
    let result = '';
    let i = 0;
    let inString = false;
    while (i < text.length) {
        if (inString) {
            if (text[i] === '\\') {
                result += text[i] + (text[i + 1] || '');
                i += 2;
                continue;
            }
            if (text[i] === '"') {
                inString = false;
            }
            result += text[i];
            i++;
            continue;
        }
        if (text[i] === '"') {
            inString = true;
            result += text[i];
            i++;
            continue;
        }
        if (text[i] === '/' && text[i + 1] === '/') {
            while (i < text.length && text[i] !== '\n') i++;
            continue;
        }
        if (text[i] === '/' && text[i + 1] === '*') {
            i += 2;
            while (i < text.length && !(text[i] === '*' && text[i + 1] === '/')) i++;
            i += 2;
            continue;
        }
        result += text[i];
        i++;
    }
    result = result.replace(/,\s*([}\]])/g, '$1');
    return result;
}

const settingsFile = process.argv[2];
let settings = {};
try {
    settings = JSON.parse(stripJsonc(fs.readFileSync(settingsFile, 'utf8')));
} catch (e) {
    console.error('Could not parse settings.json — skipping cleanup');
    process.exit(0);
}

// Keys that the Dark Glass theme installs
const keysToRemove = [
    'workbench.colorTheme',
    'editor.fontFamily',
    'terminal.integrated.fontFamily',
    'editor.fontVariations',
    'editor.fontLigatures',
    'editor.fontWeight',
    'editor.lineHeight',
    'workbench.tree.indent',
    'workbench.tree.renderIndentGuides',
    'editor.minimap.showSlider',
    'workbench.iconTheme'
];

let removed = 0;
for (const key of keysToRemove) {
    if (key in settings) {
        delete settings[key];
        removed++;
    }
}

fs.writeFileSync(settingsFile, JSON.stringify(settings, null, 2));
console.log('Removed ' + removed + ' theme-related settings');
CLEANEOF
    node "$CLEANUP_SCRIPT" "$SETTINGS_FILE"
    rm -f "$CLEANUP_SCRIPT"
    echo -e "${GREEN}✓ Theme settings removed (backup saved as settings.json.pre-uninstall)${NC}"
elif [ -f "$SETTINGS_FILE" ]; then
    echo -e "${YELLOW}⚠️  Node.js not available — could not clean settings.json${NC}"
    echo "   Please manually remove Dark Glass settings from:"
    echo "   $SETTINGS_FILE"
else
    echo -e "${YELLOW}⚠️  No settings.json found — skipping${NC}"
fi

echo ""

# ---------------------------------------------------------------------------
# Step 3: Remove CSS injection from workbench.css
# ---------------------------------------------------------------------------
echo "🔧 Step 3: Removing CSS customizations..."

# Remove custom directory from user data
USER_CUSTOM_DIR="$HOME/.local/share/code-server/custom"
if [ -d "$USER_CUSTOM_DIR" ]; then
    rm -rf "$USER_CUSTOM_DIR"
    echo -e "${GREEN}✓ Removed $USER_CUSTOM_DIR${NC}"
else
    echo "  - No custom directory found in user data — skipping"
fi

# Find workbench.css and remove the @import line + symlink
WORKBENCH_CANDIDATES=(
    "/usr/lib/code-server/lib/vscode/out/vs/code/browser/workbench/workbench.css"
    "/usr/lib/code-server/lib/vscode/out/vs/workbench/workbench.css"
)

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

if [ -n "$WORKBENCH_CSS" ]; then
    # Remove the @import line
    if sudo grep -q '@import url("./custom/active.css");' "$WORKBENCH_CSS" 2>/dev/null; then
        sudo sed -i '/@import url("\.\/custom\/active\.css");/d' "$WORKBENCH_CSS"
        echo -e "${GREEN}✓ Removed @import from $WORKBENCH_CSS${NC}"
    else
        echo "  - No @import found in workbench.css — skipping"
    fi

    # Restore backup if it exists
    if [ -f "${WORKBENCH_CSS}.bak" ]; then
        echo "  - Backup found at ${WORKBENCH_CSS}.bak (kept for reference)"
    fi

    # Remove symlink from workbench directory
    WORKBENCH_DIR=$(dirname "$WORKBENCH_CSS")
    if [ -L "$WORKBENCH_DIR/custom" ]; then
        sudo rm -f "$WORKBENCH_DIR/custom"
        echo -e "${GREEN}✓ Removed symlink $WORKBENCH_DIR/custom${NC}"
    elif [ -d "$WORKBENCH_DIR/custom" ]; then
        sudo rm -rf "$WORKBENCH_DIR/custom"
        echo -e "${GREEN}✓ Removed $WORKBENCH_DIR/custom${NC}"
    else
        echo "  - No custom symlink found in workbench directory — skipping"
    fi
else
    echo -e "${YELLOW}⚠️  workbench.css not found — skipping CSS cleanup${NC}"
fi

echo ""

# ---------------------------------------------------------------------------
# Step 4: Uninstall Seti Folder icon theme
# ---------------------------------------------------------------------------
echo "🎨 Step 4: Uninstalling Seti Folder icon theme..."
if code-server --uninstall-extension l-igh-t.vscode-theme-seti-folder 2>/dev/null; then
    echo -e "${GREEN}✓ Seti Folder icon theme uninstalled${NC}"
else
    echo -e "${YELLOW}⚠️  Could not uninstall Seti Folder (may not be installed)${NC}"
fi

echo ""

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
echo -e "${GREEN}✅ Dark Glass theme has been fully uninstalled!${NC}"
echo ""
echo "   • Restart code-server (or refresh your browser) to apply changes."
echo "   • Your previous settings backup is at:"
echo "     $SETTINGS_FILE.pre-uninstall"
echo ""
echo -e "${GREEN}Done! 🏝️${NC}"
