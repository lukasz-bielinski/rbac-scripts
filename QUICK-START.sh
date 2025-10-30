#!/usr/bin/env bash
#
# Quick Start Demo for RBAC Tools
# Shows all capabilities in 5 minutes

set -euo pipefail

echo "🔐 RBAC Tools - Quick Start Demo"
echo "================================"
echo ""

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Check if sample file exists
if [[ ! -f "clusterrole.json" ]]; then
    echo "❌ Sample file clusterrole.json not found"
    echo "   Please ensure you're in the temp/ directory"
    exit 1
fi

echo "📋 What we'll do:"
echo "  1. Split large ClusterRole into manageable pieces (3 strategies)"
echo "  2. Create sample TEST/PROD versions"
echo "  3. Compare them to find differences"
echo "  4. Generate reports"
echo ""
read -p "Press Enter to start..."

# ==============================================================================
# STEP 1: Split by API Group
# ==============================================================================
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📦 STEP 1: Splitting by API Group"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Strategy: One file per API group (kafka.strimzi.io, apps, etc.)"
echo ""

./split-clusterrole-advanced.sh clusterrole.json \
    --group-by apigroup \
    --format yaml \
    --output-dir demo-apigroup

echo ""
echo "✅ Created: demo-apigroup/"
echo "   Files: $(ls -1 demo-apigroup/*.yaml | wc -l) YAML files"
echo ""
echo "Sample files:"
ls -1 demo-apigroup/*.yaml | head -5
echo ""
read -p "Press Enter to continue..."

# ==============================================================================
# STEP 2: Split by Category (RECOMMENDED)
# ==============================================================================
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🎯 STEP 2: Splitting by Category (RECOMMENDED)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Strategy: Logical grouping (core, apps, networking, storage, etc.)"
echo ""

./split-clusterrole-advanced.sh clusterrole.json \
    --group-by category \
    --format yaml \
    --output-dir demo-category

echo ""
echo "✅ Created: demo-category/"
echo "   Files: $(ls -1 demo-category/*.yaml | wc -l) YAML files"
echo ""
echo "Categories created:"
ls -1 demo-category/*.yaml | grep -v "00-AGGREGATOR" | sed 's/.*\//  - /' | sed 's/\.yaml$//'
echo ""
read -p "Press Enter to continue..."

# ==============================================================================
# STEP 3: Split by Verb (Security Focus)
# ==============================================================================
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔒 STEP 3: Splitting by Verb (Security Focus)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Strategy: Separate read-only vs read-write permissions"
echo ""

./split-clusterrole-advanced.sh clusterrole.json \
    --group-by verb \
    --format yaml \
    --output-dir demo-verb

echo ""
echo "✅ Created: demo-verb/"
echo "   Files: $(ls -1 demo-verb/*.yaml | wc -l) YAML files"
echo ""
ls -lh demo-verb/*.yaml
echo ""
echo "💡 Use case: Grant readonly.yaml to developers, readwrite.yaml to admins"
echo ""
read -p "Press Enter to continue..."

# ==============================================================================
# STEP 4: Create Multi-Environment Setup
# ==============================================================================
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🌍 STEP 4: Creating Multi-Environment Setup"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

mkdir -p demo-compare

# Create PROD version (baseline)
echo "Creating engineer-role-PROD.yaml (baseline)..."
cp clusterrole.json demo-compare/engineer-role-PROD.json

# Convert to YAML
yq eval -P demo-compare/engineer-role-PROD.json > demo-compare/engineer-role-PROD.yaml
rm demo-compare/engineer-role-PROD.json

# Create TEST version (with some differences)
echo "Creating engineer-role-TEST.yaml (with modifications)..."
cat demo-compare/engineer-role-PROD.yaml | \
    yq eval 'del(.rules[] | select(.apiGroups[]? == "apps" and .verbs[]? == "delete"))' - | \
    yq eval '.rules += [{"apiGroups": ["test.example.com"], "resources": ["testitems"], "verbs": ["get", "list"]}]' - \
    > demo-compare/engineer-role-TEST.yaml

# Create DEV version (even more differences)
echo "Creating engineer-role-DEV.yaml (with more modifications)..."
cat demo-compare/engineer-role-TEST.yaml | \
    yq eval '.rules += [{"apiGroups": ["dev.example.com"], "resources": ["devtools"], "verbs": ["*"]}]' - \
    > demo-compare/engineer-role-DEV.yaml

echo ""
echo "✅ Created 3 environment versions:"
ls -lh demo-compare/*.yaml
echo ""
read -p "Press Enter to compare them..."

# ==============================================================================
# STEP 5: Compare Environments
# ==============================================================================
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔍 STEP 5: Comparing Across Environments"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Markdown report
echo "Generating Markdown report..."
./compare-clusterroles.sh demo-compare \
    --baseline PROD \
    --output demo-comparison.md \
    --format markdown

echo ""
echo "✅ Created: demo-comparison.md"
echo ""
echo "Report preview:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
head -30 demo-comparison.md
echo "..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# HTML report
echo "Generating HTML report..."
./compare-clusterroles.sh demo-compare \
    --baseline PROD \
    --output demo-comparison.html \
    --format html

echo "✅ Created: demo-comparison.html"
echo ""
read -p "Press Enter to see summary..."

# ==============================================================================
# STEP 6: Using the Unified CLI
# ==============================================================================
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🛠️  STEP 6: Using the Unified CLI"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

echo "The rbac-tools.sh wrapper provides a unified interface:"
echo ""
echo "1. Validate all roles:"
./rbac-tools.sh validate demo-compare
echo ""

echo "2. Split (using CLI wrapper):"
echo "   ./rbac-tools.sh split clusterrole.json"
echo ""

echo "3. Compare (using CLI wrapper):"
echo "   ./rbac-tools.sh compare demo-compare --baseline PROD"
echo ""

# ==============================================================================
# Summary
# ==============================================================================
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🎉 DEMO COMPLETE!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📁 Created Directories:"
echo "   • demo-apigroup/     - Split by API group"
echo "   • demo-category/     - Split by category (RECOMMENDED)"
echo "   • demo-verb/         - Split by verb (read-only vs write)"
echo "   • demo-compare/      - Multi-environment comparison"
echo ""
echo "📄 Generated Reports:"
echo "   • demo-comparison.md   - Markdown report"
echo "   • demo-comparison.html - HTML report (open in browser)"
echo ""
echo "🔍 Next Steps:"
echo ""
echo "1. View Markdown report:"
echo "   cat demo-comparison.md | less"
echo ""
echo "2. Open HTML report:"
echo "   xdg-open demo-comparison.html"
echo "   # or: open demo-comparison.html (macOS)"
echo ""
echo "3. Explore split files:"
echo "   ls -la demo-category/"
echo "   cat demo-category/01-core.yaml"
echo ""
echo "4. Apply to your cluster (if connected):"
echo "   kubectl apply -f demo-category/"
echo ""
echo "5. Clean up demo files:"
echo "   rm -rf demo-*"
echo ""
echo "📖 Full documentation: README-RBAC-TOOLS.md"
echo ""
echo "✨ RBAC Tools are ready to use!"



