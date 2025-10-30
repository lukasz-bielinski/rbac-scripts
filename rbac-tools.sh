#!/usr/bin/env bash
#
# RBAC Tools - Quick CLI for ClusterRole Management
# Wrapper for split and compare scripts with common workflows

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Color output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

show_help() {
    cat << EOF
🔐 RBAC Tools - ClusterRole Management Suite

Usage: $0 <command> [options]

Commands:
  split <file>              Split large ClusterRole into aggregated components
  compare <dir>             Compare ClusterRoles across environments
  extract <namespace>       Extract ClusterRole from running cluster
  validate <dir>            Validate ClusterRole syntax
  help                      Show this help

Examples:

  # Split a large role into manageable pieces
  $0 split engineer-role.json

  # Split with custom grouping
  $0 split engineer-role.yaml --group-by category --format yaml

  # Compare TEST vs PROD
  $0 compare ./roles --baseline PROD --output comparison.html

  # Extract from cluster
  $0 extract my-role --output my-role-PROD.yaml

  # Validate all roles in directory
  $0 validate ./roles

Quick Workflows:

  # 1. Extract from multiple clusters
  KUBECONFIG=~/.kube/test   $0 extract engineer-role --output roles/engineer-role-TEST.yaml
  KUBECONFIG=~/.kube/prod   $0 extract engineer-role --output roles/engineer-role-PROD.yaml
  
  # 2. Compare
  $0 compare ./roles --baseline PROD
  
  # 3. Split PROD version for easier maintenance
  $0 split roles/engineer-role-PROD.yaml --group-by category

For detailed help on each command:
  $0 split --help
  $0 compare --help

EOF
}

# Command: split
cmd_split() {
    if [[ ! -f "$SCRIPT_DIR/split-clusterrole-advanced.sh" ]]; then
        echo "Error: split-clusterrole-advanced.sh not found"
        exit 1
    fi
    
    exec "$SCRIPT_DIR/split-clusterrole-advanced.sh" "$@"
}

# Command: compare
cmd_compare() {
    if [[ ! -f "$SCRIPT_DIR/compare-clusterroles.sh" ]]; then
        echo "Error: compare-clusterroles.sh not found"
        exit 1
    fi
    
    exec "$SCRIPT_DIR/compare-clusterroles.sh" "$@"
}

# Command: extract
cmd_extract() {
    if [[ $# -lt 1 ]]; then
        echo "Usage: $0 extract <clusterrole-name> [--output file] [--format yaml|json]"
        exit 1
    fi
    
    ROLE_NAME="$1"
    shift
    
    OUTPUT_FILE="${ROLE_NAME}.yaml"
    OUTPUT_FORMAT="yaml"
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --output)
                OUTPUT_FILE="$2"
                shift 2
                ;;
            --format)
                OUTPUT_FORMAT="$2"
                shift 2
                ;;
            *)
                echo "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    echo -e "${BLUE}ℹ${NC}  Extracting ClusterRole: $ROLE_NAME"
    
    if ! kubectl get clusterrole "$ROLE_NAME" &> /dev/null; then
        echo -e "${YELLOW}⚠️${NC}  ClusterRole '$ROLE_NAME' not found in cluster"
        exit 1
    fi
    
    if [[ "$OUTPUT_FORMAT" == "json" ]]; then
        kubectl get clusterrole "$ROLE_NAME" -o json | \
            jq 'del(.metadata.uid, .metadata.resourceVersion, .metadata.creationTimestamp, .metadata.managedFields)' \
            > "$OUTPUT_FILE"
    else
        kubectl get clusterrole "$ROLE_NAME" -o yaml | \
            yq eval 'del(.metadata.uid, .metadata.resourceVersion, .metadata.creationTimestamp, .metadata.managedFields)' - \
            > "$OUTPUT_FILE"
    fi
    
    echo -e "${GREEN}✅${NC} Extracted to: $OUTPUT_FILE"
}

# Command: validate
cmd_validate() {
    if [[ $# -lt 1 ]]; then
        echo "Usage: $0 validate <directory>"
        exit 1
    fi
    
    DIR="$1"
    
    if [[ ! -d "$DIR" ]]; then
        echo "Error: Directory not found: $DIR"
        exit 1
    fi
    
    echo -e "${BLUE}ℹ${NC}  Validating ClusterRoles in: $DIR"
    
    ERROR_COUNT=0
    SUCCESS_COUNT=0
    
    shopt -s nullglob
    for file in "$DIR"/*.{yaml,yml,json}; do
        echo -n "Checking $(basename "$file")... "
        
        if [[ "$file" =~ \.ya?ml$ ]]; then
            if yq eval '.' "$file" > /dev/null 2>&1; then
                # Check if it's a valid ClusterRole
                KIND=$(yq eval '.kind' "$file")
                if [[ "$KIND" != "ClusterRole" ]]; then
                    echo -e "${YELLOW}⚠️${NC}  Not a ClusterRole (kind: $KIND)"
                    ((ERROR_COUNT++))
                    continue
                fi
                echo -e "${GREEN}✅${NC}"
                ((SUCCESS_COUNT++))
            else
                echo -e "${YELLOW}❌${NC} Invalid YAML"
                ((ERROR_COUNT++))
            fi
        else
            if jq '.' "$file" > /dev/null 2>&1; then
                KIND=$(jq -r '.kind' "$file")
                if [[ "$KIND" != "ClusterRole" ]]; then
                    echo -e "${YELLOW}⚠️${NC}  Not a ClusterRole (kind: $KIND)"
                    ((ERROR_COUNT++))
                    continue
                fi
                echo -e "${GREEN}✅${NC}"
                ((SUCCESS_COUNT++))
            else
                echo -e "${YELLOW}❌${NC} Invalid JSON"
                ((ERROR_COUNT++))
            fi
        fi
    done
    shopt -u nullglob
    
    echo ""
    echo "Summary:"
    echo -e "  ${GREEN}✅${NC} Valid: $SUCCESS_COUNT"
    echo -e "  ${YELLOW}❌${NC} Errors: $ERROR_COUNT"
    
    [[ $ERROR_COUNT -eq 0 ]] && exit 0 || exit 1
}

# Main
if [[ $# -lt 1 ]]; then
    show_help
    exit 1
fi

COMMAND="$1"
shift

case "$COMMAND" in
    split)
        cmd_split "$@"
        ;;
    compare)
        cmd_compare "$@"
        ;;
    extract)
        cmd_extract "$@"
        ;;
    validate)
        cmd_validate "$@"
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        echo "Unknown command: $COMMAND"
        echo "Run '$0 help' for usage"
        exit 1
        ;;
esac



