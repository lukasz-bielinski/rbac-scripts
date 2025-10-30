#!/usr/bin/env bash
#
# Advanced ClusterRole Splitter
# Splits large ClusterRoles into maintainable, aggregated components
#
# Features:
# - Groups by apiGroup with intelligent categorization
# - Separates read-only vs write permissions
# - Creates sensible logical groupings (core, apps, networking, storage, etc.)
# - Generates clean, git-friendly YAML
# - Adds helpful comments and metadata

set -euo pipefail

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() { echo -e "${BLUE}ℹ${NC}  $*"; }
log_success() { echo -e "${GREEN}✅${NC} $*"; }
log_warning() { echo -e "${YELLOW}⚠️${NC}  $*"; }
log_error() { echo -e "${RED}❌${NC} $*" >&2; }

# Check dependencies
for cmd in jq yq; do
    if ! command -v $cmd &> /dev/null; then
        log_error "$cmd is required but not installed"
        exit 1
    fi
done

# Usage
if [[ $# -lt 1 ]]; then
    cat << EOF
Usage: $0 <input_clusterrole.json|yaml> [options]

Options:
  --output-dir <dir>     Output directory (default: <role-name>_aggregated)
  --format <yaml|json>   Output format (default: yaml)
  --group-by <strategy>  Grouping strategy: apigroup|category|verb (default: category)
  --prefix <string>      Prefix for generated roles (default: original name)

Grouping strategies:
  apigroup  - One file per API group (kafka.strimzi.io, apps, etc.)
  category  - Logical categories (core, apps, networking, storage, monitoring, etc.)
  verb      - Separate read-only from read-write permissions

Example:
  $0 engineer-role.json --group-by category --format yaml
EOF
    exit 1
fi

INPUT_FILE="$1"
shift

# Parse options
OUTPUT_DIR=""
OUTPUT_FORMAT="yaml"
GROUPING_STRATEGY="category"
ROLE_PREFIX=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --output-dir)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --format)
            OUTPUT_FORMAT="$2"
            shift 2
            ;;
        --group-by)
            GROUPING_STRATEGY="$2"
            shift 2
            ;;
        --prefix)
            ROLE_PREFIX="$2"
            shift 2
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Validate input
if [[ ! -f "$INPUT_FILE" ]]; then
    log_error "Input file not found: $INPUT_FILE"
    exit 1
fi

# Convert input to JSON if YAML
TEMP_JSON="/tmp/clusterrole-$$.json"
if [[ "$INPUT_FILE" =~ \.ya?ml$ ]]; then
    log_info "Converting YAML to JSON..."
    yq eval -o=json "$INPUT_FILE" > "$TEMP_JSON"
    INPUT_JSON="$TEMP_JSON"
else
    INPUT_JSON="$INPUT_FILE"
fi

# Extract role name
ORIGINAL_ROLE_NAME=$(jq -r '.metadata.name' "$INPUT_JSON")
if [[ -z "$ORIGINAL_ROLE_NAME" || "$ORIGINAL_ROLE_NAME" == "null" ]]; then
    log_error "Could not read .metadata.name from input file"
    exit 1
fi

[[ -z "$ROLE_PREFIX" ]] && ROLE_PREFIX="$ORIGINAL_ROLE_NAME"
[[ -z "$OUTPUT_DIR" ]] && OUTPUT_DIR="${ORIGINAL_ROLE_NAME}_aggregated"

log_info "Splitting ClusterRole: $ORIGINAL_ROLE_NAME"
log_info "Output directory: $OUTPUT_DIR"
log_info "Grouping strategy: $GROUPING_STRATEGY"
log_info "Output format: $OUTPUT_FORMAT"

# Prepare output directory
rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

# Define aggregation label
AGGREGATION_LABEL="rbac.management.k8s.io/aggregate-to-${ORIGINAL_ROLE_NAME}"

# Category mapping for intelligent grouping
declare -A CATEGORY_MAP=(
    # Core Kubernetes
    ["core"]="01-core"
    ["apps"]="02-apps"
    ["batch"]="02-apps"
    ["extensions"]="02-apps"
    
    # Networking
    ["networking.k8s.io"]="03-networking"
    ["network.openshift.io"]="03-networking"
    ["route.openshift.io"]="03-networking"
    
    # Storage
    ["storage.k8s.io"]="04-storage"
    ["snapshot.storage.k8s.io"]="04-storage"
    ["objectbucket.io"]="04-storage"
    
    # Monitoring & Observability
    ["monitoring.coreos.com"]="05-monitoring"
    ["logging.openshift.io"]="05-monitoring"
    ["loki.grafana.com"]="05-monitoring"
    ["grafana.integreatly.org"]="05-monitoring"
    ["metrics.k8s.io"]="05-monitoring"
    
    # Security & Policy
    ["policy"]="06-security"
    ["compliance.openshift.io"]="06-security"
    ["quota.openshift.io"]="06-security"
    
    # Operators
    ["operators.coreos.com"]="07-operators"
    ["packages.operators.coreos.com"]="07-operators"
    
    # Build & Deploy
    ["build.openshift.io"]="08-build"
    ["image.openshift.io"]="08-build"
    ["template.openshift.io"]="08-build"
    
    # Project Management
    ["project.openshift.io"]="09-project"
    
    # Autoscaling
    ["autoscaling"]="10-autoscaling"
    
    # API Extensions
    ["apiextensions.k8s.io"]="11-apiextensions"
    
    # Third-party
    ["kafka.strimzi.io"]="20-kafka"
    ["enterprise.splunk.com"]="20-splunk"
)

# Function to categorize API group
categorize_api_group() {
    local api_group="$1"
    
    # Check exact match
    if [[ -n "${CATEGORY_MAP[$api_group]:-}" ]]; then
        echo "${CATEGORY_MAP[$api_group]}"
        return
    fi
    
    # Check prefix match for *.openshift.io, *.k8s.io, etc.
    for key in "${!CATEGORY_MAP[@]}"; do
        if [[ "$api_group" == *"$key"* ]]; then
            echo "${CATEGORY_MAP[$key]}"
            return
        fi
    done
    
    # Default: third-party
    echo "99-other"
}

# Function to sanitize names for files/resources
sanitize_name() {
    echo "$1" | tr '.' '-' | tr '[:upper:]' '[:lower:]'
}

# Function to determine if verbs are read-only
is_readonly() {
    local verbs="$1"
    [[ "$verbs" =~ ^(get|list|watch)$ ]] && return 0
    return 1
}

# Create main aggregator role
log_info "Creating main aggregator role..."

AGGREGATOR_CONTENT=$(cat <<EOF
---
# Main Aggregator Role for $ORIGINAL_ROLE_NAME
# This role automatically aggregates all component roles with the label:
#   $AGGREGATION_LABEL: "true"
#
# DO NOT EDIT THIS FILE MANUALLY - it is auto-generated
# Edit the component roles in subdirectories instead

apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: $ORIGINAL_ROLE_NAME
  annotations:
    description: "Aggregated role for $ORIGINAL_ROLE_NAME"
    generated-by: "split-clusterrole-advanced.sh"
    generated-at: "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
aggregationRule:
  clusterRoleSelectors:
    - matchLabels:
        $AGGREGATION_LABEL: "true"
EOF
)

AGGREGATOR_FILE="${OUTPUT_DIR}/00-AGGREGATOR.${OUTPUT_FORMAT}"
echo "$AGGREGATOR_CONTENT" > "$AGGREGATOR_FILE"
log_success "Created aggregator: $AGGREGATOR_FILE"

# Extract all API groups
API_GROUPS=$(jq -r '.rules[]?.apiGroups[]? | select(. != null)' "$INPUT_JSON" | sort -u)

if [[ -z "$API_GROUPS" ]]; then
    log_warning "No API groups found in rules"
    exit 0
fi

# Process based on grouping strategy
log_info "Processing rules with strategy: $GROUPING_STRATEGY"

case "$GROUPING_STRATEGY" in
    apigroup)
        # One file per API group
        for api_group in $API_GROUPS; do
            if [[ -z "$api_group" ]]; then
                SAFE_NAME="core"
            else
                SAFE_NAME=$(sanitize_name "$api_group")
            fi
            
            COMPONENT_NAME="${ROLE_PREFIX}-${SAFE_NAME}"
            OUTPUT_FILE="${OUTPUT_DIR}/${SAFE_NAME}.${OUTPUT_FORMAT}"
            
            # Extract rules for this API group
            RULES=$(jq --arg group "$api_group" \
                '[.rules[]? | select(.apiGroups[]? == $group)]' "$INPUT_JSON")
            
            # Create component role
            COMPONENT=$(jq -n \
                --arg name "$COMPONENT_NAME" \
                --arg label "$AGGREGATION_LABEL" \
                --arg apigroup "$api_group" \
                --argjson rules "$RULES" \
                '{
                    apiVersion: "rbac.authorization.k8s.io/v1",
                    kind: "ClusterRole",
                    metadata: {
                        name: $name,
                        labels: { ($label): "true" },
                        annotations: {
                            "api-group": $apigroup,
                            "generated-by": "split-clusterrole-advanced.sh"
                        }
                    },
                    rules: $rules
                }')
            
            if [[ "$OUTPUT_FORMAT" == "yaml" ]]; then
                echo "$COMPONENT" | yq eval -P - > "$OUTPUT_FILE"
            else
                echo "$COMPONENT" > "$OUTPUT_FILE"
            fi
            
            log_success "Created: $OUTPUT_FILE"
        done
        ;;
        
    category)
        # Group by logical category
        declare -A CATEGORY_RULES
        
        for api_group in $API_GROUPS; do
            CATEGORY=$(categorize_api_group "$api_group")
            
            # Extract rules for this API group
            RULES=$(jq -c --arg group "$api_group" \
                '[.rules[]? | select(.apiGroups[]? == $group)]' "$INPUT_JSON")
            
            # Accumulate rules by category
            if [[ -z "${CATEGORY_RULES[$CATEGORY]:-}" ]]; then
                CATEGORY_RULES[$CATEGORY]="$RULES"
            else
                # Merge rules
                CATEGORY_RULES[$CATEGORY]=$(jq -n \
                    --argjson existing "${CATEGORY_RULES[$CATEGORY]}" \
                    --argjson new "$RULES" \
                    '$existing + $new')
            fi
        done
        
        # Create category files
        for category in "${!CATEGORY_RULES[@]}"; do
            COMPONENT_NAME="${ROLE_PREFIX}-${category#*-}" # Remove number prefix
            OUTPUT_FILE="${OUTPUT_DIR}/${category}.${OUTPUT_FORMAT}"
            
            RULES="${CATEGORY_RULES[$category]}"
            
            COMPONENT=$(jq -n \
                --arg name "$COMPONENT_NAME" \
                --arg label "$AGGREGATION_LABEL" \
                --arg cat "$category" \
                --argjson rules "$RULES" \
                '{
                    apiVersion: "rbac.authorization.k8s.io/v1",
                    kind: "ClusterRole",
                    metadata: {
                        name: $name,
                        labels: { ($label): "true" },
                        annotations: {
                            "category": $cat,
                            "generated-by": "split-clusterrole-advanced.sh"
                        }
                    },
                    rules: $rules
                }')
            
            if [[ "$OUTPUT_FORMAT" == "yaml" ]]; then
                echo "$COMPONENT" | yq eval -P - > "$OUTPUT_FILE"
            else
                echo "$COMPONENT" > "$OUTPUT_FILE"
            fi
            
            log_success "Created: $OUTPUT_FILE ($category)"
        done
        ;;
        
    verb)
        # Separate read-only vs read-write
        READONLY_RULES=$(jq '[.rules[]? | select(.verbs | all(. == "get" or . == "list" or . == "watch"))]' "$INPUT_JSON")
        READWRITE_RULES=$(jq '[.rules[]? | select(.verbs | any(. != "get" and . != "list" and . != "watch"))]' "$INPUT_JSON")
        
        # Create read-only role
        if [[ "$READONLY_RULES" != "[]" ]]; then
            READONLY_NAME="${ROLE_PREFIX}-readonly"
            OUTPUT_FILE="${OUTPUT_DIR}/readonly.${OUTPUT_FORMAT}"
            
            COMPONENT=$(jq -n \
                --arg name "$READONLY_NAME" \
                --arg label "$AGGREGATION_LABEL" \
                --argjson rules "$READONLY_RULES" \
                '{
                    apiVersion: "rbac.authorization.k8s.io/v1",
                    kind: "ClusterRole",
                    metadata: {
                        name: $name,
                        labels: { ($label): "true" },
                        annotations: {
                            "permission-type": "read-only",
                            "generated-by": "split-clusterrole-advanced.sh"
                        }
                    },
                    rules: $rules
                }')
            
            if [[ "$OUTPUT_FORMAT" == "yaml" ]]; then
                echo "$COMPONENT" | yq eval -P - > "$OUTPUT_FILE"
            else
                echo "$COMPONENT" > "$OUTPUT_FILE"
            fi
            
            log_success "Created: $OUTPUT_FILE (read-only)"
        fi
        
        # Create read-write role
        if [[ "$READWRITE_RULES" != "[]" ]]; then
            READWRITE_NAME="${ROLE_PREFIX}-readwrite"
            OUTPUT_FILE="${OUTPUT_DIR}/readwrite.${OUTPUT_FORMAT}"
            
            COMPONENT=$(jq -n \
                --arg name "$READWRITE_NAME" \
                --arg label "$AGGREGATION_LABEL" \
                --argjson rules "$READWRITE_RULES" \
                '{
                    apiVersion: "rbac.authorization.k8s.io/v1",
                    kind: "ClusterRole",
                    metadata: {
                        name: $name,
                        labels: { ($label): "true" },
                        annotations: {
                            "permission-type": "read-write",
                            "generated-by": "split-clusterrole-advanced.sh"
                        }
                    },
                    rules: $rules
                }')
            
            if [[ "$OUTPUT_FORMAT" == "yaml" ]]; then
                echo "$COMPONENT" | yq eval -P - > "$OUTPUT_FILE"
            else
                echo "$COMPONENT" > "$OUTPUT_FILE"
            fi
            
            log_success "Created: $OUTPUT_FILE (read-write)"
        fi
        ;;
esac

# Create README
README_FILE="${OUTPUT_DIR}/README.md"
cat > "$README_FILE" << EOF
# Aggregated ClusterRole: $ORIGINAL_ROLE_NAME

Generated on: $(date)
Source file: $INPUT_FILE
Grouping strategy: $GROUPING_STRATEGY

## Structure

This directory contains an aggregated ClusterRole split into manageable components:

- \`00-AGGREGATOR.$OUTPUT_FORMAT\` - Main aggregator role (apply this first)
- Component roles with label: \`$AGGREGATION_LABEL: "true"\`

## Usage

### Apply all roles:
\`\`\`bash
kubectl apply -f $OUTPUT_DIR/
\`\`\`

### Apply in order (recommended):
\`\`\`bash
# 1. Apply aggregator first
kubectl apply -f $OUTPUT_DIR/00-AGGREGATOR.$OUTPUT_FORMAT

# 2. Apply all components
kubectl apply -f $OUTPUT_DIR/ --recursive
\`\`\`

### Verify aggregation:
\`\`\`bash
kubectl get clusterrole $ORIGINAL_ROLE_NAME -o yaml
\`\`\`

## Maintenance

- Edit component roles individually for easier git diffs
- Aggregator automatically combines all components
- Add new components by creating files with the aggregation label

## Components

EOF

# List all components
for file in "$OUTPUT_DIR"/*."$OUTPUT_FORMAT"; do
    [[ "$file" == *"00-AGGREGATOR"* ]] && continue
    COMP_NAME=$(basename "$file" ".$OUTPUT_FORMAT")
    echo "- \`$COMP_NAME\` - $(jq -r '.metadata.annotations.description // .metadata.annotations.category // .metadata.annotations."api-group" // "Component role"' <(yq eval -o=json "$file" 2>/dev/null || echo '{}'))" >> "$README_FILE"
done

log_success "Created README: $README_FILE"

# Cleanup
[[ -f "$TEMP_JSON" ]] && rm "$TEMP_JSON"

log_success "Split complete! Output in: $OUTPUT_DIR"
log_info "Files created: $(ls -1 "$OUTPUT_DIR" | wc -l)"

