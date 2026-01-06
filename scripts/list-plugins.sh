#!/usr/bin/env bash
# List all plugins in the marketplace
# Usage: ./scripts/list-plugins.sh [--json] [--verbose]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
PLUGINS_DIR="$ROOT_DIR/plugins"
MARKETPLACE_FILE="$ROOT_DIR/.claude-plugin/marketplace.json"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# Parse arguments
JSON_OUTPUT=false
VERBOSE=false

for arg in "$@"; do
    case "$arg" in
        --json) JSON_OUTPUT=true ;;
        --verbose|-v) VERBOSE=true ;;
        --help|-h)
            echo "Usage: $0 [--json] [--verbose]"
            echo ""
            echo "Options:"
            echo "  --json      Output in JSON format"
            echo "  --verbose   Show additional details (skills, commands)"
            echo "  --help      Show this help message"
            exit 0
            ;;
    esac
done

if [[ ! -f "$MARKETPLACE_FILE" ]]; then
    echo "Error: marketplace.json not found"
    exit 1
fi

# JSON output mode
if [[ "$JSON_OUTPUT" == true ]]; then
    jq '.plugins' "$MARKETPLACE_FILE"
    exit 0
fi

# Get marketplace info
MARKETPLACE_NAME=$(jq -r '.name' "$MARKETPLACE_FILE")
MARKETPLACE_VERSION=$(jq -r '.version // "unknown"' "$MARKETPLACE_FILE")
PLUGIN_COUNT=$(jq '.plugins | length' "$MARKETPLACE_FILE")

echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${CYAN}  $MARKETPLACE_NAME v$MARKETPLACE_VERSION${NC}"
echo -e "${CYAN}  $PLUGIN_COUNT plugin(s) available${NC}"
echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
echo ""

# List plugins
jq -r '.plugins[] | "\(.name)|\(.version // "1.0.0")|\(.category // "utilities")|\(.status // "stable")|\(.featured // false)|\(.description // "")"' "$MARKETPLACE_FILE" | \
while IFS='|' read -r name version category status featured description; do
    # Status indicator
    case "$status" in
        stable) indicator="${GREEN}●${NC}" ;;
        beta) indicator="${YELLOW}●${NC}" ;;
        alpha) indicator="${YELLOW}○${NC}" ;;
        deprecated) indicator="○" ;;
        *) indicator="●" ;;
    esac

    # Featured badge
    featured_badge=""
    if [[ "$featured" == "true" ]]; then
        featured_badge=" ${MAGENTA}★${NC}"
    fi

    # Count skills and commands
    skill_count=0
    command_count=0
    agent_count=0

    plugin_path="$PLUGINS_DIR/$name"
    if [[ -d "$plugin_path/skills" ]]; then
        skill_count=$(find "$plugin_path/skills" -name "SKILL.md" 2>/dev/null | wc -l | tr -d ' ')
    fi
    if [[ -d "$plugin_path/commands" ]]; then
        command_count=$(find "$plugin_path/commands" -name "*.md" 2>/dev/null | wc -l | tr -d ' ')
    fi
    if [[ -d "$plugin_path/agents" ]]; then
        agent_count=$(find "$plugin_path/agents" -name "*.md" 2>/dev/null | wc -l | tr -d ' ')
    fi

    # Build stats string
    stats=""
    if [[ $skill_count -gt 0 ]]; then
        stats="${stats}${skill_count} skill(s)"
    fi
    if [[ $command_count -gt 0 ]]; then
        [[ -n "$stats" ]] && stats="${stats}, "
        stats="${stats}${command_count} cmd(s)"
    fi
    if [[ $agent_count -gt 0 ]]; then
        [[ -n "$stats" ]] && stats="${stats}, "
        stats="${stats}${agent_count} agent(s)"
    fi
    [[ -z "$stats" ]] && stats="empty"

    echo -e "$indicator ${GREEN}$name${NC} v$version [$category]$featured_badge"
    echo -e "    ${stats}"
    echo "    $description"

    # Verbose mode: show skills
    if [[ "$VERBOSE" == true ]] && [[ -d "$plugin_path/skills" ]]; then
        for skill_md in "$plugin_path/skills"/*/SKILL.md; do
            if [[ -f "$skill_md" ]]; then
                skill_name=$(basename "$(dirname "$skill_md")")
                skill_desc=$(grep -m1 "^description:" "$skill_md" 2>/dev/null | sed 's/^description: *//' | head -c 60)
                echo -e "      └─ ${CYAN}$skill_name${NC}: $skill_desc..."
            fi
        done
    fi

    echo ""
done

echo -e "${CYAN}───────────────────────────────────────────────────────────────${NC}"
echo ""
echo "Commands:"
echo "  ./scripts/validate-plugin.sh <name>   Validate a plugin"
echo "  ./scripts/create-plugin.sh <name>     Create a new plugin"
echo "  ./scripts/register-plugin.sh <name>   Register in marketplace"
echo ""
echo "Test locally:"
echo "  claude --plugin-dir ./plugins/<name>"
