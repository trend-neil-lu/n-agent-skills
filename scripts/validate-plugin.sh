#!/usr/bin/env bash
# Validate a plugin's structure and required files
# Usage: ./scripts/validate-plugin.sh <plugin-name|plugin-path>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
PLUGINS_DIR="$ROOT_DIR/plugins"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

usage() {
    echo "Usage: $0 <plugin-name|plugin-path>"
    echo ""
    echo "Validates the structure and required files of a Claude Code plugin."
    echo ""
    echo "Examples:"
    echo "  $0 example-skills"
    echo "  $0 ./plugins/my-plugin"
    exit 1
}

if [[ $# -lt 1 ]]; then
    usage
fi

PLUGIN_INPUT="$1"
ERRORS=0
WARNINGS=0

# Determine plugin path
if [[ -d "$PLUGIN_INPUT" ]]; then
    PLUGIN_PATH="$PLUGIN_INPUT"
elif [[ -d "$PLUGINS_DIR/$PLUGIN_INPUT" ]]; then
    PLUGIN_PATH="$PLUGINS_DIR/$PLUGIN_INPUT"
else
    echo -e "${RED}Error: Plugin not found: $PLUGIN_INPUT${NC}"
    exit 1
fi

PLUGIN_NAME=$(basename "$PLUGIN_PATH")
echo -e "${YELLOW}Validating plugin: $PLUGIN_NAME${NC}"
echo "Path: $PLUGIN_PATH"
echo ""

# Check function
check_required() {
    local path="$1"
    local desc="$2"
    if [[ -e "$path" ]]; then
        echo -e "${GREEN}✓${NC} $desc"
        return 0
    else
        echo -e "${RED}✗${NC} $desc (missing)"
        ((ERRORS++))
        return 1
    fi
}

check_optional() {
    local path="$1"
    local desc="$2"
    if [[ -e "$path" ]]; then
        echo -e "${GREEN}✓${NC} $desc"
    else
        echo -e "${YELLOW}○${NC} $desc (optional, not present)"
    fi
}

warn() {
    echo -e "${YELLOW}⚠${NC} $1"
    ((WARNINGS++))
}

# Required files
echo "=== Required Files ==="
check_required "$PLUGIN_PATH/.claude-plugin/plugin.json" ".claude-plugin/plugin.json"

# Validate plugin.json content
if [[ -f "$PLUGIN_PATH/.claude-plugin/plugin.json" ]]; then
    # Check if it's valid JSON
    if ! jq empty "$PLUGIN_PATH/.claude-plugin/plugin.json" 2>/dev/null; then
        echo -e "${RED}✗${NC} plugin.json is not valid JSON"
        ((ERRORS++))
    else
        # Check required fields
        NAME=$(jq -r '.name // empty' "$PLUGIN_PATH/.claude-plugin/plugin.json")
        if [[ -z "$NAME" ]]; then
            echo -e "${RED}✗${NC} plugin.json missing 'name' field"
            ((ERRORS++))
        elif [[ ! "$NAME" =~ ^[a-z][a-z0-9-]*$ ]]; then
            warn "plugin.json 'name' should be kebab-case: $NAME"
        fi

        VERSION=$(jq -r '.version // empty' "$PLUGIN_PATH/.claude-plugin/plugin.json")
        if [[ -z "$VERSION" ]]; then
            warn "plugin.json missing 'version' field"
        elif [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            warn "plugin.json 'version' should be semver format: $VERSION"
        fi

        DESC=$(jq -r '.description // empty' "$PLUGIN_PATH/.claude-plugin/plugin.json")
        if [[ -z "$DESC" ]]; then
            warn "plugin.json missing 'description' field"
        fi
    fi
fi
echo ""

# Optional directories
echo "=== Optional Directories ==="
check_optional "$PLUGIN_PATH/skills" "skills/ directory"
check_optional "$PLUGIN_PATH/commands" "commands/ directory"
check_optional "$PLUGIN_PATH/agents" "agents/ directory"
check_optional "$PLUGIN_PATH/hooks" "hooks/ directory"
check_optional "$PLUGIN_PATH/scripts" "scripts/ directory"
echo ""

# Validate skills
if [[ -d "$PLUGIN_PATH/skills" ]]; then
    echo "=== Skills Validation ==="
    for skill_dir in "$PLUGIN_PATH/skills"/*/; do
        if [[ -d "$skill_dir" ]]; then
            skill_name=$(basename "$skill_dir")
            if [[ -f "$skill_dir/SKILL.md" ]]; then
                echo -e "${GREEN}✓${NC} Skill: $skill_name"

                # Check frontmatter
                if ! head -1 "$skill_dir/SKILL.md" | grep -q "^---$"; then
                    warn "  $skill_name/SKILL.md missing YAML frontmatter"
                else
                    # Check required frontmatter fields
                    if ! grep -q "^name:" "$skill_dir/SKILL.md"; then
                        warn "  $skill_name/SKILL.md missing 'name' in frontmatter"
                    fi
                    if ! grep -q "^description:" "$skill_dir/SKILL.md"; then
                        warn "  $skill_name/SKILL.md missing 'description' in frontmatter"
                    fi
                fi
            else
                echo -e "${RED}✗${NC} Skill: $skill_name (missing SKILL.md)"
                ((ERRORS++))
            fi
        fi
    done
    echo ""
fi

# Validate commands
if [[ -d "$PLUGIN_PATH/commands" ]]; then
    echo "=== Commands Validation ==="
    for cmd_file in "$PLUGIN_PATH/commands"/*.md; do
        if [[ -f "$cmd_file" ]]; then
            cmd_name=$(basename "$cmd_file" .md)
            echo -e "${GREEN}✓${NC} Command: $cmd_name"

            # Check frontmatter
            if ! head -1 "$cmd_file" | grep -q "^---$"; then
                warn "  $cmd_name.md missing YAML frontmatter"
            elif ! grep -q "^description:" "$cmd_file"; then
                warn "  $cmd_name.md missing 'description' in frontmatter"
            fi
        fi
    done
    echo ""
fi

# Summary
echo "=== Summary ==="
if [[ $ERRORS -eq 0 ]] && [[ $WARNINGS -eq 0 ]]; then
    echo -e "${GREEN}✓ Plugin validation passed with no issues${NC}"
    exit 0
elif [[ $ERRORS -eq 0 ]]; then
    echo -e "${YELLOW}Plugin validation passed with $WARNINGS warning(s)${NC}"
    exit 0
else
    echo -e "${RED}Plugin validation failed with $ERRORS error(s) and $WARNINGS warning(s)${NC}"
    exit 1
fi
