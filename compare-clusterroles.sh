#!/usr/bin/env bash
#
# ClusterRole Environment Comparison Tool
# Compares ClusterRoles across different environments (TEST, PROD, DEV, etc.)
#
# Features:
# - Identifies differences in permissions between environments
# - Generates HTML/Markdown reports
# - Highlights security implications
# - Detects missing/extra permissions per environment

set -euo pipefail

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${BLUE}ℹ${NC}  $*"; }
log_success() { echo -e "${GREEN}✅${NC} $*"; }
log_warning() { echo -e "${YELLOW}⚠️${NC}  $*"; }
log_error() { echo -e "${RED}❌${NC} $*" >&2; }
log_diff() { echo -e "${CYAN}🔍${NC} $*"; }

# Check dependencies
for cmd in jq yq diff; do
    if ! command -v $cmd &> /dev/null; then
        log_error "$cmd is required but not installed"
        exit 1
    fi
done

# Usage
if [[ $# -lt 1 ]]; then
    cat << EOF
Usage: $0 <directory> [options]

Compares ClusterRoles with environment suffixes (e.g., role-TEST.yaml, role-PROD.yaml)

Arguments:
  directory          Directory containing ClusterRole files with env suffixes

Options:
  --output <file>    Output report file (default: role-comparison-report.md)
  --format <fmt>     Report format: markdown|html|json (default: markdown)
  --baseline <env>   Baseline environment (default: PROD)
  --verbose          Show detailed diff output

Environment suffixes:
  Files should be named: <role-name>-<ENV>.yaml
  Examples: engineer-role-TEST.yaml, engineer-role-PROD.yaml

Example:
  $0 ./roles --output comparison.md --baseline PROD
EOF
    exit 1
fi

INPUT_DIR="$1"
shift

# Parse options
OUTPUT_FILE="role-comparison-report.md"
OUTPUT_FORMAT="markdown"
BASELINE_ENV="PROD"
VERBOSE=false

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
        --baseline)
            BASELINE_ENV="$2"
            shift 2
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Validate input
if [[ ! -d "$INPUT_DIR" ]]; then
    log_error "Directory not found: $INPUT_DIR"
    exit 1
fi

log_info "Analyzing ClusterRoles in: $INPUT_DIR"
log_info "Baseline environment: $BASELINE_ENV"
log_info "Output report: $OUTPUT_FILE"

# Find all ClusterRole files
shopt -s nullglob
ROLE_FILES=("$INPUT_DIR"/*-*.{yaml,yml,json})
shopt -u nullglob

if [[ ${#ROLE_FILES[@]} -eq 0 ]]; then
    log_error "No ClusterRole files found with environment suffixes"
    log_info "Expected pattern: <role-name>-<ENV>.{yaml,yml,json}"
    exit 1
fi

log_info "Found ${#ROLE_FILES[@]} ClusterRole files"

# Extract role names and environments
declare -A ROLES
declare -A ENVS

for file in "${ROLE_FILES[@]}"; do
    basename=$(basename "$file")
    # Extract: role-name-ENV.ext -> role-name and ENV
    if [[ "$basename" =~ ^(.+)-([A-Z]+)\.(yaml|yml|json)$ ]]; then
        ROLE_NAME="${BASH_REMATCH[1]}"
        ENV="${BASH_REMATCH[2]}"
        
        ROLES["$ROLE_NAME"]=1
        ENVS["$ENV"]=1
        
        log_diff "Found: $ROLE_NAME in $ENV environment"
    fi
done

# Convert to arrays
ROLE_NAMES=($(for role in "${!ROLES[@]}"; do echo "$role"; done | sort))
ENV_NAMES=($(for env in "${!ENVS[@]}"; do echo "$env"; done | sort))

log_info "Unique roles: ${#ROLE_NAMES[@]}"
log_info "Environments: ${ENV_NAMES[*]}"

# Check if baseline exists
if [[ ! " ${ENV_NAMES[*]} " =~ " ${BASELINE_ENV} " ]]; then
    log_warning "Baseline environment '$BASELINE_ENV' not found"
    log_info "Available: ${ENV_NAMES[*]}"
    BASELINE_ENV="${ENV_NAMES[0]}"
    log_info "Using first environment as baseline: $BASELINE_ENV"
fi

# Function to extract rules from a file
extract_rules() {
    local file="$1"
    local temp_json="/tmp/role-$$.json"
    
    if [[ "$file" =~ \.ya?ml$ ]]; then
        yq eval -o=json "$file" > "$temp_json"
    else
        cp "$file" "$temp_json"
    fi
    
    jq -c '.rules[]?' "$temp_json" | sort | jq -s '.'
    rm -f "$temp_json"
}

# Function to extract API groups from rules
extract_api_groups() {
    local rules="$1"
    echo "$rules" | jq -r '.[].apiGroups[]?' | sort -u
}

# Function to extract resources from rules
extract_resources() {
    local rules="$1"
    local api_group="$2"
    echo "$rules" | jq -r --arg group "$api_group" \
        '.[] | select(.apiGroups[]? == $group) | .resources[]?' | sort -u
}

# Function to extract verbs for resource
extract_verbs() {
    local rules="$1"
    local api_group="$2"
    local resource="$3"
    echo "$rules" | jq -r --arg group "$api_group" --arg res "$resource" \
        '.[] | select(.apiGroups[]? == $group and .resources[]? == $res) | .verbs[]?' | sort -u
}

# Initialize report
REPORT_CONTENT=""
JSON_REPORT='{"generated": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'", "baseline": "'$BASELINE_ENV'", "environments": [], "roles": []}'

# Function to add to report
add_to_report() {
    REPORT_CONTENT+="$1"$'\n'
}

# Start report
case "$OUTPUT_FORMAT" in
    html)
        add_to_report "<html><head><title>ClusterRole Comparison Report</title>"
        add_to_report "<style>"
        add_to_report "body { font-family: Arial, sans-serif; margin: 20px; }"
        add_to_report "table { border-collapse: collapse; width: 100%; margin: 20px 0; }"
        add_to_report "th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }"
        add_to_report "th { background-color: #4CAF50; color: white; }"
        add_to_report ".added { background-color: #d4edda; }"
        add_to_report ".removed { background-color: #f8d7da; }"
        add_to_report ".warning { background-color: #fff3cd; }"
        add_to_report "</style></head><body>"
        add_to_report "<h1>🔐 ClusterRole Comparison Report</h1>"
        add_to_report "<p>Generated: $(date)</p>"
        add_to_report "<p>Baseline: <strong>$BASELINE_ENV</strong></p>"
        ;;
    markdown)
        add_to_report "# 🔐 ClusterRole Comparison Report"
        add_to_report ""
        add_to_report "**Generated**: $(date)"
        add_to_report "**Baseline Environment**: $BASELINE_ENV"
        add_to_report "**Environments**: ${ENV_NAMES[*]}"
        add_to_report ""
        add_to_report "---"
        add_to_report ""
        ;;
esac

# Compare each role
for ROLE in "${ROLE_NAMES[@]}"; do
    log_info "Comparing role: $ROLE"
    
    # Find all env files for this role
    declare -A ROLE_FILES_BY_ENV
    for env in "${ENV_NAMES[@]}"; do
        for ext in yaml yml json; do
            file="$INPUT_DIR/${ROLE}-${env}.${ext}"
            if [[ -f "$file" ]]; then
                ROLE_FILES_BY_ENV["$env"]="$file"
                break
            fi
        done
    done
    
    # Check if role exists in all environments
    MISSING_ENVS=()
    for env in "${ENV_NAMES[@]}"; do
        if [[ -z "${ROLE_FILES_BY_ENV[$env]:-}" ]]; then
            MISSING_ENVS+=("$env")
            log_warning "Role '$ROLE' missing in $env"
        fi
    done
    
    # Skip if baseline doesn't exist
    if [[ -z "${ROLE_FILES_BY_ENV[$BASELINE_ENV]:-}" ]]; then
        log_error "Baseline file not found for role: $ROLE"
        continue
    fi
    
    # Extract baseline rules
    BASELINE_FILE="${ROLE_FILES_BY_ENV[$BASELINE_ENV]}"
    BASELINE_RULES=$(extract_rules "$BASELINE_FILE")
    
    # Report header for this role
    case "$OUTPUT_FORMAT" in
        html)
            add_to_report "<h2>Role: $ROLE</h2>"
            [[ ${#MISSING_ENVS[@]} -gt 0 ]] && add_to_report "<p class='warning'>⚠️ Missing in: ${MISSING_ENVS[*]}</p>"
            add_to_report "<table><tr><th>Environment</th><th>API Group</th><th>Resources</th><th>Verbs</th><th>Difference</th></tr>"
            ;;
        markdown)
            add_to_report "## 📋 Role: \`$ROLE\`"
            add_to_report ""
            [[ ${#MISSING_ENVS[@]} -gt 0 ]] && add_to_report "⚠️ **Missing in**: ${MISSING_ENVS[*]}"
            add_to_report ""
            ;;
    esac
    
    # Extract API groups from baseline
    BASELINE_API_GROUPS=$(extract_api_groups "$BASELINE_RULES")
    
    # Compare with each environment
    for env in "${ENV_NAMES[@]}"; do
        [[ "$env" == "$BASELINE_ENV" ]] && continue
        [[ -z "${ROLE_FILES_BY_ENV[$env]:-}" ]] && continue
        
        ENV_FILE="${ROLE_FILES_BY_ENV[$env]}"
        ENV_RULES=$(extract_rules "$ENV_FILE")
        ENV_API_GROUPS=$(extract_api_groups "$ENV_RULES")
        
        log_diff "Comparing $BASELINE_ENV vs $env"
        
        case "$OUTPUT_FORMAT" in
            markdown)
                add_to_report "### Comparison: $BASELINE_ENV → $env"
                add_to_report ""
                add_to_report "| API Group | Resource | $BASELINE_ENV Verbs | $env Verbs | Difference |"
                add_to_report "|-----------|----------|-------------|---------|------------|"
                ;;
        esac
        
        # Find added/removed API groups
        ADDED_API_GROUPS=$(comm -13 <(echo "$BASELINE_API_GROUPS") <(echo "$ENV_API_GROUPS"))
        REMOVED_API_GROUPS=$(comm -23 <(echo "$BASELINE_API_GROUPS") <(echo "$ENV_API_GROUPS"))
        COMMON_API_GROUPS=$(comm -12 <(echo "$BASELINE_API_GROUPS") <(echo "$ENV_API_GROUPS"))
        
        if [[ -n "$ADDED_API_GROUPS" ]]; then
            log_success "Added API groups in $env: $(echo $ADDED_API_GROUPS | tr '\n' ' ')"
            for api_group in $ADDED_API_GROUPS; do
                RESOURCES=$(extract_resources "$ENV_RULES" "$api_group")
                for resource in $RESOURCES; do
                    VERBS=$(extract_verbs "$ENV_RULES" "$api_group" "$resource")
                    case "$OUTPUT_FORMAT" in
                        markdown)
                            add_to_report "| \`${api_group:-core}\` | \`$resource\` | - | \`$(echo $VERBS | tr '\n' ', ')\` | ➕ **ADDED** |"
                            ;;
                        html)
                            add_to_report "<tr class='added'><td>$env</td><td>${api_group:-core}</td><td>$resource</td><td>$(echo $VERBS | tr '\n' ', ')</td><td>➕ ADDED</td></tr>"
                            ;;
                    esac
                done
            done
        fi
        
        if [[ -n "$REMOVED_API_GROUPS" ]]; then
            log_warning "Removed API groups in $env: $(echo $REMOVED_API_GROUPS | tr '\n' ' ')"
            for api_group in $REMOVED_API_GROUPS; do
                RESOURCES=$(extract_resources "$BASELINE_RULES" "$api_group")
                for resource in $RESOURCES; do
                    VERBS=$(extract_verbs "$BASELINE_RULES" "$api_group" "$resource")
                    case "$OUTPUT_FORMAT" in
                        markdown)
                            add_to_report "| \`${api_group:-core}\` | \`$resource\` | \`$(echo $VERBS | tr '\n' ', ')\` | - | ➖ **REMOVED** |"
                            ;;
                        html)
                            add_to_report "<tr class='removed'><td>$env</td><td>${api_group:-core}</td><td>$resource</td><td>-</td><td>➖ REMOVED</td></tr>"
                            ;;
                    esac
                done
            done
        fi
        
        # Compare common API groups
        for api_group in $COMMON_API_GROUPS; do
            BASELINE_RESOURCES=$(extract_resources "$BASELINE_RULES" "$api_group")
            ENV_RESOURCES=$(extract_resources "$ENV_RULES" "$api_group")
            
            COMMON_RESOURCES=$(comm -12 <(echo "$BASELINE_RESOURCES") <(echo "$ENV_RESOURCES"))
            
            for resource in $COMMON_RESOURCES; do
                BASELINE_VERBS=$(extract_verbs "$BASELINE_RULES" "$api_group" "$resource")
                ENV_VERBS=$(extract_verbs "$ENV_RULES" "$api_group" "$resource")
                
                if [[ "$BASELINE_VERBS" != "$ENV_VERBS" ]]; then
                    ADDED_VERBS=$(comm -13 <(echo "$BASELINE_VERBS") <(echo "$ENV_VERBS"))
                    REMOVED_VERBS=$(comm -23 <(echo "$BASELINE_VERBS") <(echo "$ENV_VERBS"))
                    
                    DIFF=""
                    [[ -n "$ADDED_VERBS" ]] && DIFF+="➕ $(echo $ADDED_VERBS | tr '\n' ',')"
                    [[ -n "$REMOVED_VERBS" ]] && DIFF+=" ➖ $(echo $REMOVED_VERBS | tr '\n' ',')"
                    
                    case "$OUTPUT_FORMAT" in
                        markdown)
                            add_to_report "| \`${api_group:-core}\` | \`$resource\` | \`$(echo $BASELINE_VERBS | tr '\n' ', ')\` | \`$(echo $ENV_VERBS | tr '\n' ', ')\` | $DIFF |"
                            ;;
                        html)
                            add_to_report "<tr class='warning'><td>$env</td><td>${api_group:-core}</td><td>$resource</td><td>$(echo $ENV_VERBS | tr '\n' ', ')</td><td>$DIFF</td></tr>"
                            ;;
                    esac
                    
                    log_diff "$api_group/$resource: $DIFF"
                fi
            done
        done
        
        add_to_report ""
    done
    
    case "$OUTPUT_FORMAT" in
        html)
            add_to_report "</table>"
            ;;
        markdown)
            add_to_report "---"
            add_to_report ""
            ;;
    esac
    
    unset ROLE_FILES_BY_ENV
done

# Close report
case "$OUTPUT_FORMAT" in
    html)
        add_to_report "</body></html>"
        ;;
    markdown)
        add_to_report "## 📊 Summary"
        add_to_report ""
        add_to_report "- Total roles compared: ${#ROLE_NAMES[@]}"
        add_to_report "- Environments: ${ENV_NAMES[*]}"
        add_to_report "- Baseline: $BASELINE_ENV"
        add_to_report ""
        add_to_report "---"
        add_to_report "*Generated by compare-clusterroles.sh*"
        ;;
esac

# Write report
echo "$REPORT_CONTENT" > "$OUTPUT_FILE"

log_success "Report saved to: $OUTPUT_FILE"
log_info "Open with:"
case "$OUTPUT_FORMAT" in
    html)
        log_info "  xdg-open $OUTPUT_FILE"
        ;;
    markdown)
        log_info "  cat $OUTPUT_FILE | less"
        log_info "  or open in your markdown viewer"
        ;;
esac

