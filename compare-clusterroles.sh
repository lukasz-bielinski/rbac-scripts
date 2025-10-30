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

# Check jq version
JQ_VERSION=$(jq --version 2>&1 | grep -oP '\d+\.\d+\.\d+' | head -1)
REQUIRED_JQ_VERSION="1.8.1"

if [[ -n "$JQ_VERSION" ]]; then
    if ! printf '%s\n' "$REQUIRED_JQ_VERSION" "$JQ_VERSION" | sort -V -C; then
        log_error "jq version $REQUIRED_JQ_VERSION or higher is required (found: $JQ_VERSION)"
        log_info "Install latest jq: https://github.com/jqlang/jq/releases"
        exit 1
    fi
else
    log_warning "Could not determine jq version"
fi

# Usage
if [[ $# -lt 1 ]]; then
    cat << EOF
Usage: $0 <directory> [options]

Compares ClusterRoles across environments OR between different roles

Arguments:
  directory          Directory containing ClusterRole files

Options:
  --output <file>    Output report file (default: auto-generated based on mode)
  --format <fmt>     Report format: markdown|html|json (default: markdown)
  --mode <mode>      Comparison mode: env|roles (default: env)
  --baseline <env>   Baseline environment (default: PROD) - for env mode
  --baseline-role <name>  Baseline role name (required for roles mode)
  --environment <env>     Environment to compare (required for roles mode)
  --verbose          Show detailed diff output

Comparison modes:
  env    - Compare same role across environments (TEST, PROD, DEV)
           Files: role-name-TEST.yaml, role-name-PROD.yaml
           Output: env-comparison-<timestamp>.md
  
  roles  - Compare different roles in same environment
           Files: debug-TEST.yaml, developer-TEST.yaml
           Output: roles-comparison-<env>-<timestamp>.md

Examples:
  # Compare across environments (default mode)
  $0 ./roles --baseline PROD
  
  # Compare different roles in same environment
  $0 ./roles --mode roles --environment TEST --baseline-role debug
EOF
    exit 1
fi

INPUT_DIR="$1"
shift

# Parse options
OUTPUT_FILE=""
OUTPUT_FORMAT="markdown"
COMPARISON_MODE="env"
BASELINE_ENV="PROD"
BASELINE_ROLE=""
TARGET_ENVIRONMENT=""
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
        --mode)
            COMPARISON_MODE="$2"
            shift 2
            ;;
        --baseline)
            BASELINE_ENV="$2"
            shift 2
            ;;
        --baseline-role)
            BASELINE_ROLE="$2"
            shift 2
            ;;
        --environment)
            TARGET_ENVIRONMENT="$2"
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

# Generate default output file name based on mode
if [[ -z "$OUTPUT_FILE" ]]; then
    TIMESTAMP=$(date +%Y%m%d-%H%M%S)
    case "$COMPARISON_MODE" in
        env)
            OUTPUT_FILE="env-comparison-${TIMESTAMP}.md"
            ;;
        roles)
            if [[ -n "$TARGET_ENVIRONMENT" ]]; then
                OUTPUT_FILE="roles-comparison-${TARGET_ENVIRONMENT}-${TIMESTAMP}.md"
            else
                OUTPUT_FILE="roles-comparison-${TIMESTAMP}.md"
            fi
            ;;
    esac
fi

# Validate mode-specific requirements
if [[ "$COMPARISON_MODE" == "roles" ]]; then
    if [[ -z "$BASELINE_ROLE" ]]; then
        log_error "roles mode requires --baseline-role option"
        exit 1
    fi
    if [[ -z "$TARGET_ENVIRONMENT" ]]; then
        log_error "roles mode requires --environment option"
        exit 1
    fi
fi

# Validate input
if [[ ! -d "$INPUT_DIR" ]]; then
    log_error "Directory not found: $INPUT_DIR"
    exit 1
fi

log_info "Analyzing ClusterRoles in: $INPUT_DIR"
log_info "Comparison mode: $COMPARISON_MODE"
if [[ "$COMPARISON_MODE" == "env" ]]; then
    log_info "Baseline environment: $BASELINE_ENV"
else
    log_info "Target environment: $TARGET_ENVIRONMENT"
    log_info "Baseline role: $BASELINE_ROLE"
fi
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

# ============================================================================
# MODE: ROLES - Compare different roles in same environment
# ============================================================================
if [[ "$COMPARISON_MODE" == "roles" ]]; then
    log_info "=== ROLES COMPARISON MODE ==="
    
    # Find all roles in target environment
    AVAILABLE_ROLES=()
    for role in "${ROLE_NAMES[@]}"; do
        for ext in yaml yml json; do
            file="$INPUT_DIR/${role}-${TARGET_ENVIRONMENT}.${ext}"
            if [[ -f "$file" ]]; then
                AVAILABLE_ROLES+=("$role")
                break
            fi
        done
    done
    
    log_info "Available roles in $TARGET_ENVIRONMENT: ${AVAILABLE_ROLES[*]}"
    
    # Check if baseline role exists
    if [[ ! " ${AVAILABLE_ROLES[*]} " =~ " ${BASELINE_ROLE} " ]]; then
        log_error "Baseline role '$BASELINE_ROLE' not found in environment $TARGET_ENVIRONMENT"
        log_info "Available roles: ${AVAILABLE_ROLES[*]}"
        exit 1
    fi
    
    # Find baseline role file
    BASELINE_ROLE_FILE=""
    for ext in yaml yml json; do
        file="$INPUT_DIR/${BASELINE_ROLE}-${TARGET_ENVIRONMENT}.${ext}"
        if [[ -f "$file" ]]; then
            BASELINE_ROLE_FILE="$file"
            break
        fi
    done
    
    # Extract baseline rules
    BASELINE_RULES=$(extract_rules "$BASELINE_ROLE_FILE")
    BASELINE_API_GROUPS=$(extract_api_groups "$BASELINE_RULES")
    
    # Update report header for roles mode
    case "$OUTPUT_FORMAT" in
        html)
            add_to_report "<html><head><title>ClusterRole Comparison Report - Roles</title>"
            add_to_report "<style>"
            add_to_report "body { font-family: Arial, sans-serif; margin: 20px; }"
            add_to_report "table { border-collapse: collapse; width: 100%; margin: 20px 0; }"
            add_to_report "th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }"
            add_to_report "th { background-color: #4CAF50; color: white; }"
            add_to_report ".added { background-color: #d4edda; }"
            add_to_report ".removed { background-color: #f8d7da; }"
            add_to_report ".warning { background-color: #fff3cd; }"
            add_to_report "</style></head><body>"
            add_to_report "<h1>🔐 ClusterRole Comparison Report - Roles</h1>"
            add_to_report "<p>Generated: $(date)</p>"
            add_to_report "<p>Environment: <strong>$TARGET_ENVIRONMENT</strong></p>"
            add_to_report "<p>Baseline Role: <strong>$BASELINE_ROLE</strong></p>"
            ;;
        markdown)
            add_to_report "# 🔐 ClusterRole Comparison Report - Roles"
            add_to_report ""
            add_to_report "**Generated**: $(date)"
            add_to_report "**Environment**: $TARGET_ENVIRONMENT"
            add_to_report "**Baseline Role**: $BASELINE_ROLE"
            add_to_report "**Compared Roles**: ${AVAILABLE_ROLES[*]}"
            add_to_report ""
            add_to_report "---"
            add_to_report ""
            ;;
    esac
    
    # Compare baseline role with each other role
    for TARGET_ROLE in "${AVAILABLE_ROLES[@]}"; do
        [[ "$TARGET_ROLE" == "$BASELINE_ROLE" ]] && continue
        
        log_info "Comparing: $BASELINE_ROLE vs $TARGET_ROLE"
        
        # Find target role file
        TARGET_ROLE_FILE=""
        for ext in yaml yml json; do
            file="$INPUT_DIR/${TARGET_ROLE}-${TARGET_ENVIRONMENT}.${ext}"
            if [[ -f "$file" ]]; then
                TARGET_ROLE_FILE="$file"
                break
            fi
        done
        
        # Extract target rules
        TARGET_RULES=$(extract_rules "$TARGET_ROLE_FILE")
        TARGET_API_GROUPS=$(extract_api_groups "$TARGET_RULES")
        
        # Report header for this comparison
        case "$OUTPUT_FORMAT" in
            html)
                add_to_report "<h2>Comparison: $BASELINE_ROLE → $TARGET_ROLE</h2>"
                add_to_report "<table><tr><th>API Group</th><th>Resource</th><th>$BASELINE_ROLE Verbs</th><th>$TARGET_ROLE Verbs</th><th>Difference</th></tr>"
                ;;
            markdown)
                add_to_report "## 📋 Comparison: \`$BASELINE_ROLE\` → \`$TARGET_ROLE\`"
                add_to_report ""
                add_to_report "| API Group | Resource | $BASELINE_ROLE Verbs | $TARGET_ROLE Verbs | Difference |"
                add_to_report "|-----------|----------|-------------|---------|------------|"
                ;;
        esac
        
        # Find added/removed API groups
        ADDED_API_GROUPS=$(comm -13 <(echo "$BASELINE_API_GROUPS") <(echo "$TARGET_API_GROUPS"))
        REMOVED_API_GROUPS=$(comm -23 <(echo "$BASELINE_API_GROUPS") <(echo "$TARGET_API_GROUPS"))
        COMMON_API_GROUPS=$(comm -12 <(echo "$BASELINE_API_GROUPS") <(echo "$TARGET_API_GROUPS"))
        
        if [[ -n "$ADDED_API_GROUPS" ]]; then
            log_success "Added API groups in $TARGET_ROLE: $(echo $ADDED_API_GROUPS | tr '\n' ' ')"
            for api_group in $ADDED_API_GROUPS; do
                RESOURCES=$(extract_resources "$TARGET_RULES" "$api_group")
                for resource in $RESOURCES; do
                    VERBS=$(extract_verbs "$TARGET_RULES" "$api_group" "$resource")
                    case "$OUTPUT_FORMAT" in
                        markdown)
                            add_to_report "| \`${api_group:-core}\` | \`$resource\` | - | \`$(echo $VERBS | tr '\n' ', ')\` | ➕ **ADDED** |"
                            ;;
                        html)
                            add_to_report "<tr class='added'><td>${api_group:-core}</td><td>$resource</td><td>-</td><td>$(echo $VERBS | tr '\n' ', ')</td><td>➕ ADDED</td></tr>"
                            ;;
                    esac
                done
            done
        fi
        
        if [[ -n "$REMOVED_API_GROUPS" ]]; then
            log_warning "Removed API groups in $TARGET_ROLE: $(echo $REMOVED_API_GROUPS | tr '\n' ' ')"
            for api_group in $REMOVED_API_GROUPS; do
                RESOURCES=$(extract_resources "$BASELINE_RULES" "$api_group")
                for resource in $RESOURCES; do
                    VERBS=$(extract_verbs "$BASELINE_RULES" "$api_group" "$resource")
                    case "$OUTPUT_FORMAT" in
                        markdown)
                            add_to_report "| \`${api_group:-core}\` | \`$resource\` | \`$(echo $VERBS | tr '\n' ', ')\` | - | ➖ **REMOVED** |"
                            ;;
                        html)
                            add_to_report "<tr class='removed'><td>${api_group:-core}</td><td>$resource</td><td>$(echo $VERBS | tr '\n' ', ')</td><td>-</td><td>➖ REMOVED</td></tr>"
                            ;;
                    esac
                done
            done
        fi
        
        # Compare common API groups
        for api_group in $COMMON_API_GROUPS; do
            BASELINE_RESOURCES=$(extract_resources "$BASELINE_RULES" "$api_group")
            TARGET_RESOURCES=$(extract_resources "$TARGET_RULES" "$api_group")
            
            COMMON_RESOURCES=$(comm -12 <(echo "$BASELINE_RESOURCES") <(echo "$TARGET_RESOURCES"))
            
            for resource in $COMMON_RESOURCES; do
                BASELINE_VERBS=$(extract_verbs "$BASELINE_RULES" "$api_group" "$resource")
                TARGET_VERBS=$(extract_verbs "$TARGET_RULES" "$api_group" "$resource")
                
                if [[ "$BASELINE_VERBS" != "$TARGET_VERBS" ]]; then
                    ADDED_VERBS=$(comm -13 <(echo "$BASELINE_VERBS") <(echo "$TARGET_VERBS"))
                    REMOVED_VERBS=$(comm -23 <(echo "$BASELINE_VERBS") <(echo "$TARGET_VERBS"))
                    
                    DIFF=""
                    [[ -n "$ADDED_VERBS" ]] && DIFF+="➕ $(echo $ADDED_VERBS | tr '\n' ',')"
                    [[ -n "$REMOVED_VERBS" ]] && DIFF+=" ➖ $(echo $REMOVED_VERBS | tr '\n' ',')"
                    
                    case "$OUTPUT_FORMAT" in
                        markdown)
                            add_to_report "| \`${api_group:-core}\` | \`$resource\` | \`$(echo $BASELINE_VERBS | tr '\n' ', ')\` | \`$(echo $TARGET_VERBS | tr '\n' ', ')\` | $DIFF |"
                            ;;
                        html)
                            add_to_report "<tr class='warning'><td>${api_group:-core}</td><td>$resource</td><td>$(echo $BASELINE_VERBS | tr '\n' ', ')</td><td>$(echo $TARGET_VERBS | tr '\n' ', ')</td><td>$DIFF</td></tr>"
                            ;;
                    esac
                    
                    log_diff "$api_group/$resource: $DIFF"
                fi
            done
        done
        
        case "$OUTPUT_FORMAT" in
            html)
                add_to_report "</table>"
                ;;
            markdown)
                add_to_report ""
                add_to_report "---"
                add_to_report ""
                ;;
        esac
    done
    
    # Close report for roles mode
    case "$OUTPUT_FORMAT" in
        html)
            add_to_report "</body></html>"
            ;;
        markdown)
            add_to_report "## 📊 Summary"
            add_to_report ""
            add_to_report "- Environment: $TARGET_ENVIRONMENT"
            add_to_report "- Baseline role: $BASELINE_ROLE"
            add_to_report "- Compared roles: $((${#AVAILABLE_ROLES[@]} - 1))"
            add_to_report "- Total roles in environment: ${#AVAILABLE_ROLES[@]}"
            add_to_report ""
            add_to_report "---"
            add_to_report "*Generated by compare-clusterroles.sh (roles mode)*"
            ;;
    esac
    
    # Write report and exit
    echo "$REPORT_CONTENT" > "$OUTPUT_FILE"
    log_success "Report saved to: $OUTPUT_FILE"
    exit 0
fi

# ============================================================================
# MODE: ENV - Compare same role across environments (ORIGINAL LOGIC)
# ============================================================================

# Start report for ENV mode
case "$OUTPUT_FORMAT" in
    html)
        add_to_report "<html><head><title>ClusterRole Comparison Report - Environments</title>"
        add_to_report "<style>"
        add_to_report "body { font-family: Arial, sans-serif; margin: 20px; }"
        add_to_report "table { border-collapse: collapse; width: 100%; margin: 20px 0; }"
        add_to_report "th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }"
        add_to_report "th { background-color: #4CAF50; color: white; }"
        add_to_report ".added { background-color: #d4edda; }"
        add_to_report ".removed { background-color: #f8d7da; }"
        add_to_report ".warning { background-color: #fff3cd; }"
        add_to_report "</style></head><body>"
        add_to_report "<h1>🔐 ClusterRole Comparison Report - Environments</h1>"
        add_to_report "<p>Generated: $(date)</p>"
        add_to_report "<p>Baseline: <strong>$BASELINE_ENV</strong></p>"
        ;;
    markdown)
        add_to_report "# 🔐 ClusterRole Comparison Report - Environments"
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

# Close report for ENV mode
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
        add_to_report "*Generated by compare-clusterroles.sh (env mode)*"
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

