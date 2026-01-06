#!/usr/bin/env bash
# Create a new plugin from template
# Usage: ./scripts/create-plugin.sh <plugin-name> [description]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
TEMPLATE_DIR="$ROOT_DIR/plugins/_template"
PLUGINS_DIR="$ROOT_DIR/plugins"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

usage() {
    echo "Usage: $0 <plugin-name> [description]"
    echo ""
    echo "Arguments:"
    echo "  plugin-name    Name of the plugin (kebab-case, e.g., my-plugin)"
    echo "  description    Optional description of the plugin"
    echo ""
    echo "Example:"
    echo "  $0 my-awesome-plugin \"A collection of awesome skills\""
    exit 1
}

# Cross-platform sed in-place
sed_inplace() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i '' "$@"
    else
        sed -i "$@"
    fi
}

# Check arguments
if [[ $# -lt 1 ]]; then
    usage
fi

PLUGIN_NAME="$1"
PLUGIN_DESCRIPTION="${2:-A Claude Code plugin}"

# Validate plugin name (kebab-case)
if [[ ! "$PLUGIN_NAME" =~ ^[a-z][a-z0-9-]*$ ]]; then
    echo -e "${RED}Error: Plugin name must be kebab-case (lowercase letters, numbers, hyphens)${NC}"
    echo "Example: my-plugin, code-tools, security-scanner"
    exit 1
fi

# Check if plugin already exists
if [[ -d "$PLUGINS_DIR/$PLUGIN_NAME" ]]; then
    echo -e "${RED}Error: Plugin '$PLUGIN_NAME' already exists at $PLUGINS_DIR/$PLUGIN_NAME${NC}"
    exit 1
fi

# Check if template exists
if [[ ! -d "$TEMPLATE_DIR" ]]; then
    echo -e "${RED}Error: Template directory not found at $TEMPLATE_DIR${NC}"
    exit 1
fi

echo -e "${YELLOW}Creating plugin: $PLUGIN_NAME${NC}"

# Copy template
cp -r "$TEMPLATE_DIR" "$PLUGINS_DIR/$PLUGIN_NAME"

# Get git user info if available
AUTHOR_NAME=$(git config user.name 2>/dev/null || echo "Your Name")

# Try to get GitHub user from remote URL first
GITHUB_USER=""
REMOTE_URL=$(git config --get remote.origin.url 2>/dev/null || echo "")
if [[ -n "$REMOTE_URL" ]]; then
    # Extract user from various URL formats:
    # git@github.com:user/repo.git
    # https://github.com/user/repo.git
    # https://github.trendmicro.com/user/repo
    GITHUB_USER=$(echo "$REMOTE_URL" | sed -n 's/.*[:/]\([^/]*\)\/[^/]*$/\1/p')
fi
if [[ -z "$GITHUB_USER" ]]; then
    GITHUB_USER=$(git config user.name 2>/dev/null | tr ' ' '-' | tr '[:upper:]' '[:lower:]' || echo "user")
fi

# Try to get repo name from remote URL
REPO_NAME=""
if [[ -n "$REMOTE_URL" ]]; then
    REPO_NAME=$(basename -s .git "$REMOTE_URL" 2>/dev/null || echo "")
fi
if [[ -z "$REPO_NAME" ]]; then
    REPO_NAME="n-agent-skills"
fi

# Replace placeholders in all files
find "$PLUGINS_DIR/$PLUGIN_NAME" -type f \( -name "*.json" -o -name "*.md" \) -print0 | while IFS= read -r -d '' file; do
    sed_inplace \
        -e "s/{{PLUGIN_NAME}}/$PLUGIN_NAME/g" \
        -e "s/{{PLUGIN_DESCRIPTION}}/$PLUGIN_DESCRIPTION/g" \
        -e "s/{{AUTHOR_NAME}}/$AUTHOR_NAME/g" \
        -e "s/{{GITHUB_USER}}/$GITHUB_USER/g" \
        -e "s/{{REPO_NAME}}/$REPO_NAME/g" \
        "$file"
done

# Make scripts executable
chmod +x "$PLUGINS_DIR/$PLUGIN_NAME/scripts/"*.sh 2>/dev/null || true

echo -e "${GREEN}✓ Plugin created successfully at: $PLUGINS_DIR/$PLUGIN_NAME${NC}"
echo ""
echo "Next steps:"
echo "  1. Edit the plugin.json with your details"
echo "  2. Add your skills in the skills/ directory"
echo "  3. Test locally: claude --plugin-dir $PLUGINS_DIR/$PLUGIN_NAME"
echo "  4. Register in marketplace: ./scripts/register-plugin.sh $PLUGIN_NAME"
