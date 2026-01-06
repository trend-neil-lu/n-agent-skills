#!/usr/bin/env bash
# Register a plugin in the marketplace
# Usage: ./scripts/register-plugin.sh <plugin-name> [category]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
PLUGINS_DIR="$ROOT_DIR/plugins"
MARKETPLACE_FILE="$ROOT_DIR/.claude-plugin/marketplace.json"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

usage() {
    echo "Usage: $0 <plugin-name> [category]"
    echo ""
    echo "Registers a plugin in the marketplace.json file."
    echo ""
    echo "Arguments:"
    echo "  plugin-name    Name of the plugin to register"
    echo "  category       Optional category (default: utilities)"
    echo ""
    echo "Available categories:"
    echo "  utilities, development, documentation, security, testing, devops"
    echo ""
    echo "Example:"
    echo "  $0 my-plugin security"
    exit 1
}

if [[ $# -lt 1 ]]; then
    usage
fi

PLUGIN_NAME="$1"
CATEGORY="${2:-utilities}"
PLUGIN_PATH="$PLUGINS_DIR/$PLUGIN_NAME"

# Validate plugin exists
if [[ ! -d "$PLUGIN_PATH" ]]; then
    echo -e "${RED}Error: Plugin not found at $PLUGIN_PATH${NC}"
    exit 1
fi

# Validate plugin.json exists
PLUGIN_JSON="$PLUGIN_PATH/.claude-plugin/plugin.json"
if [[ ! -f "$PLUGIN_JSON" ]]; then
    echo -e "${RED}Error: plugin.json not found at $PLUGIN_JSON${NC}"
    exit 1
fi

# Validate marketplace.json exists
if [[ ! -f "$MARKETPLACE_FILE" ]]; then
    echo -e "${RED}Error: marketplace.json not found at $MARKETPLACE_FILE${NC}"
    exit 1
fi

# Extract info from plugin.json
VERSION=$(jq -r '.version // "1.0.0"' "$PLUGIN_JSON")
DESCRIPTION=$(jq -r '.description // "No description"' "$PLUGIN_JSON")
AUTHOR_NAME=$(jq -r '.author.name // "Unknown"' "$PLUGIN_JSON")
AUTHOR_EMAIL=$(jq -r '.author.email // empty' "$PLUGIN_JSON")
KEYWORDS=$(jq -r '.keywords // []' "$PLUGIN_JSON")

# Check if plugin already registered
EXISTING_ENTRY=$(jq -e ".plugins[] | select(.name == \"$PLUGIN_NAME\")" "$MARKETPLACE_FILE" 2>/dev/null || echo "")

if [[ -n "$EXISTING_ENTRY" ]]; then
    EXISTING_VERSION=$(echo "$EXISTING_ENTRY" | jq -r '.version // "unknown"')

    echo -e "${CYAN}Plugin '$PLUGIN_NAME' is already registered in marketplace${NC}"
    echo -e "  Marketplace version: ${YELLOW}$EXISTING_VERSION${NC}"
    echo -e "  Plugin.json version: ${YELLOW}$VERSION${NC}"

    if [[ "$EXISTING_VERSION" == "$VERSION" ]]; then
        echo -e "${YELLOW}Warning: Same version already registered. Consider updating the version.${NC}"
    fi

    read -p "Do you want to update the entry? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 0
    fi
    # Remove existing entry
    jq "del(.plugins[] | select(.name == \"$PLUGIN_NAME\"))" "$MARKETPLACE_FILE" > "$MARKETPLACE_FILE.tmp"
    mv "$MARKETPLACE_FILE.tmp" "$MARKETPLACE_FILE"
fi

# Build author object
if [[ -n "$AUTHOR_EMAIL" ]]; then
    AUTHOR_OBJ=$(jq -n --arg name "$AUTHOR_NAME" --arg email "$AUTHOR_EMAIL" '{name: $name, email: $email}')
else
    AUTHOR_OBJ=$(jq -n --arg name "$AUTHOR_NAME" '{name: $name}')
fi

# Create new plugin entry
NEW_PLUGIN=$(jq -n \
    --arg name "$PLUGIN_NAME" \
    --arg source "./plugins/$PLUGIN_NAME" \
    --arg desc "$DESCRIPTION" \
    --arg version "$VERSION" \
    --argjson author "$AUTHOR_OBJ" \
    --argjson keywords "$KEYWORDS" \
    --arg category "$CATEGORY" \
    '{
        name: $name,
        source: $source,
        description: $desc,
        version: $version,
        author: $author,
        keywords: $keywords,
        category: $category,
        featured: false,
        status: "stable"
    }')

# Add to marketplace
jq ".plugins += [$NEW_PLUGIN]" "$MARKETPLACE_FILE" > "$MARKETPLACE_FILE.tmp"
mv "$MARKETPLACE_FILE.tmp" "$MARKETPLACE_FILE"

echo -e "${GREEN}✓ Plugin '$PLUGIN_NAME' registered in marketplace${NC}"
echo ""
echo "Entry added:"
echo "$NEW_PLUGIN" | jq .
echo ""
echo -e "${CYAN}Next steps:${NC}"
echo "  1. Review the changes: git diff .claude-plugin/marketplace.json"
echo "  2. Commit: git add .claude-plugin/marketplace.json && git commit -m 'Register $PLUGIN_NAME plugin'"
