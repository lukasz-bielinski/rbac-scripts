# 🔐 RBAC Tools - ClusterRole Management Suite

Advanced tools for managing, splitting, and comparing Kubernetes ClusterRoles across environments.

## 📦 What's Included

| Tool | Purpose | Output |
|------|---------|--------|
| `split-clusterrole-advanced.sh` | Split large ClusterRoles into maintainable aggregated components | Multiple YAML/JSON files |
| `compare-clusterroles.sh` | Compare ClusterRoles across environments (TEST, PROD, etc.) | HTML/Markdown/JSON report |
| `rbac-tools.sh` | Unified CLI wrapper for all tools | - |

## 🚀 Quick Start

### 1. Make scripts executable
```bash
chmod +x *.sh
```

### 2. Split a large ClusterRole
```bash
# From JSON
./rbac-tools.sh split engineer-role.json

# From YAML with category grouping
./rbac-tools.sh split engineer-role.yaml --group-by category --format yaml

# Custom output directory
./split-clusterrole-advanced.sh engineer-role.json --output-dir ./roles/engineer
```

### 3. Compare roles across environments
```bash
# Extract from different clusters
KUBECONFIG=~/.kube/test ./rbac-tools.sh extract engineer-role --output roles/engineer-role-TEST.yaml
KUBECONFIG=~/.kube/prod ./rbac-tools.sh extract engineer-role --output roles/engineer-role-PROD.yaml
KUBECONFIG=~/.kube/dev  ./rbac-tools.sh extract engineer-role --output roles/engineer-role-DEV.yaml

# Compare
./rbac-tools.sh compare ./roles --baseline PROD --output comparison.html --format html
```

### 4. Validate roles
```bash
./rbac-tools.sh validate ./roles
```

---

## 📚 Detailed Usage

## Split ClusterRole Tool

### Features
- **Smart Grouping**: 3 strategies for organizing permissions
  - `apigroup` - One file per API group (kafka.strimzi.io, apps, etc.)
  - `category` - Logical categories (core, networking, storage, monitoring, etc.)
  - `verb` - Separate read-only from read-write permissions
- **Git-Friendly**: Small, focused files with meaningful names
- **Auto-Aggregation**: Main role automatically combines all components
- **Clean Output**: YAML or JSON with comments and metadata

### Usage Examples

#### Strategy 1: Split by API Group
```bash
./split-clusterrole-advanced.sh engineer-role.json \
  --group-by apigroup \
  --format yaml \
  --output-dir roles/engineer-apigroups
```

**Result**:
```
roles/engineer-apigroups/
├── 00-AGGREGATOR.yaml          # Main role (apply first)
├── core.yaml                   # pods, services, configmaps
├── apps.yaml                   # deployments, statefulsets
├── kafka-strimzi-io.yaml       # Kafka resources
├── monitoring-coreos-com.yaml  # Prometheus, ServiceMonitor
└── README.md                   # Auto-generated docs
```

#### Strategy 2: Split by Category (Recommended)
```bash
./split-clusterrole-advanced.sh engineer-role.yaml \
  --group-by category \
  --format yaml
```

**Result**:
```
engineer-role_aggregated/
├── 00-AGGREGATOR.yaml
├── 01-core.yaml            # pods, services, configmaps, secrets
├── 02-apps.yaml            # deployments, statefulsets, daemonsets
├── 03-networking.yaml      # ingress, routes, networkpolicies
├── 04-storage.yaml         # pvc, pv, volumesnapshots
├── 05-monitoring.yaml      # prometheus, grafana, loki
├── 06-security.yaml        # policies, compliance
├── 07-operators.yaml       # OLM operators
├── 08-build.yaml           # builds, images, templates
├── 20-kafka.yaml           # Strimzi Kafka
└── README.md
```

**Benefits**:
- **Logical organization** - Related permissions grouped together
- **Easy reviews** - Small files, clear purpose
- **Team ownership** - Different teams can own different categories
- **Git history** - Clear what changed in networking vs storage

#### Strategy 3: Split by Verb (Security Focus)
```bash
./split-clusterrole-advanced.sh engineer-role.json \
  --group-by verb \
  --format yaml
```

**Result**:
```
engineer-role_aggregated/
├── 00-AGGREGATOR.yaml
├── readonly.yaml      # Only get, list, watch
└── readwrite.yaml     # create, update, patch, delete
```

**Use case**: Grant read-only access to developers, read-write to senior engineers.

### Apply to Cluster

```bash
# Apply all at once
kubectl apply -f engineer-role_aggregated/

# Or in order (recommended for first-time)
kubectl apply -f engineer-role_aggregated/00-AGGREGATOR.yaml
kubectl apply -f engineer-role_aggregated/ --recursive

# Verify aggregation worked
kubectl get clusterrole engineer-role -o yaml | grep -A 50 rules:
```

---

## Compare ClusterRoles Tool

### Features
- **Multi-Environment**: Compare TEST, PROD, DEV, QA, etc.
- **Detailed Diff**: Shows added/removed/changed permissions
- **Multiple Formats**: Markdown, HTML, JSON
- **Baseline Comparison**: Compare all envs against PROD (or any baseline)
- **Security Insights**: Highlights permission escalations

### Usage Examples

#### Basic Comparison

```bash
# Assuming you have:
# - roles/engineer-role-TEST.yaml
# - roles/engineer-role-PROD.yaml

./compare-clusterroles.sh ./roles \
  --baseline PROD \
  --output comparison.md \
  --format markdown
```

#### HTML Report (for stakeholders)

```bash
./compare-clusterroles.sh ./roles \
  --baseline PROD \
  --output comparison.html \
  --format html

# Open in browser
xdg-open comparison.html
```

#### Verbose Diff

```bash
./compare-clusterroles.sh ./roles \
  --baseline PROD \
  --verbose
```

### Expected File Naming

```
roles/
├── engineer-role-TEST.yaml
├── engineer-role-PROD.yaml
├── engineer-role-DEV.yaml
├── viewer-role-TEST.yaml
└── viewer-role-PROD.yaml
```

**Pattern**: `<role-name>-<ENV>.{yaml,yml,json}`

### Report Example

#### Markdown Output

```markdown
# 🔐 ClusterRole Comparison Report

**Generated**: 2025-10-29 22:00:00
**Baseline Environment**: PROD
**Environments**: TEST PROD DEV

---

## 📋 Role: `engineer-role`

### Comparison: PROD → TEST

| API Group | Resource | PROD Verbs | TEST Verbs | Difference |
|-----------|----------|------------|------------|------------|
| `kafka.strimzi.io` | `kafkas` | `get, list, watch` | `get, list, watch, create, delete` | ➕ create, delete |
| `monitoring.coreos.com` | `servicemonitors` | - | `get, list, watch` | ➕ **ADDED** |
| `apps` | `deployments` | `get, list, watch, create, update, patch, delete` | `get, list, watch` | ➖ create, update, patch, delete |
```

### Use Cases

#### 1. Pre-Production Verification
```bash
# Before promoting to PROD, check what will change
./compare-clusterroles.sh ./roles --baseline PROD

# Review output
cat comparison.md | grep "➕\|➖"
```

#### 2. Security Audit
```bash
# Check if TEST has more permissions than PROD (dangerous!)
./compare-clusterroles.sh ./roles --baseline PROD | grep "➕.*delete\|➕.*create"
```

#### 3. Compliance Check
```bash
# Ensure DEV and TEST are identical
./compare-clusterroles.sh ./roles --baseline TEST --output dev-test-diff.html
```

---

## Complete Workflow Example

### Scenario: Manage ClusterRoles for 3 Environments

```bash
#!/bin/bash
# workflow-example.sh

set -euo pipefail

ROLE_NAME="engineer-role"
ROLES_DIR="./roles"

# 1. Extract from all clusters
echo "🔄 Extracting ClusterRoles from clusters..."

KUBECONFIG=~/.kube/test kubectl get clusterrole $ROLE_NAME -o yaml > $ROLES_DIR/${ROLE_NAME}-TEST.yaml
KUBECONFIG=~/.kube/prod kubectl get clusterrole $ROLE_NAME -o yaml > $ROLES_DIR/${ROLE_NAME}-PROD.yaml
KUBECONFIG=~/.kube/dev  kubectl get clusterrole $ROLE_NAME -o yaml > $ROLES_DIR/${ROLE_NAME}-DEV.yaml

# 2. Compare
echo "🔍 Comparing environments..."
./compare-clusterroles.sh $ROLES_DIR \
  --baseline PROD \
  --output comparison-$(date +%Y%m%d).md

# 3. Split PROD version for maintenance
echo "📦 Splitting PROD role for easier maintenance..."
./split-clusterrole-advanced.sh $ROLES_DIR/${ROLE_NAME}-PROD.yaml \
  --group-by category \
  --format yaml \
  --output-dir $ROLES_DIR/${ROLE_NAME}-split

# 4. Validate all
echo "✅ Validating all roles..."
./rbac-tools.sh validate $ROLES_DIR

echo "🎉 Done! Check comparison-$(date +%Y%m%d).md for differences"
```

### Scenario: Update Role Across Environments

```bash
#!/bin/bash
# update-role-workflow.sh

ROLE_NAME="engineer-role"
SPLIT_DIR="./roles/${ROLE_NAME}-split"

# 1. Make changes to split components
# (Edit files in $SPLIT_DIR/05-monitoring.yaml for example)

# 2. Apply to DEV first
echo "🔧 Applying to DEV..."
KUBECONFIG=~/.kube/dev kubectl apply -f $SPLIT_DIR/

# 3. Test in DEV
echo "🧪 Test in DEV, then press Enter to continue to TEST"
read

# 4. Apply to TEST
echo "🔧 Applying to TEST..."
KUBECONFIG=~/.kube/test kubectl apply -f $SPLIT_DIR/

# 5. Extract and compare
KUBECONFIG=~/.kube/test kubectl get clusterrole $ROLE_NAME -o yaml > ./roles/${ROLE_NAME}-TEST-new.yaml
./compare-clusterroles.sh ./roles --baseline PROD --output pre-prod-comparison.html

echo "📊 Review pre-prod-comparison.html before PROD deployment"
echo "Press Enter to deploy to PROD..."
read

# 6. Deploy to PROD
echo "🚀 Deploying to PROD..."
KUBECONFIG=~/.kube/prod kubectl apply -f $SPLIT_DIR/

echo "✅ Deployed to all environments!"
```

---

## 🎯 Best Practices

### Splitting Roles

1. **Use category grouping** for most cases
   - Logical, maintainable, team-friendly
   
2. **Use apigroup grouping** for very large roles
   - When you have 50+ API groups
   
3. **Use verb grouping** for security-focused roles
   - Separate read-only from admin permissions

### Comparing Roles

1. **Always use PROD as baseline**
   - Makes it easy to see what's different in lower envs

2. **Store comparison reports in Git**
   - Track permission changes over time

3. **Review before promoting**
   - Use comparison reports in PR reviews

### File Organization

```
rbac/
├── roles/                      # Original extracted roles
│   ├── engineer-role-TEST.yaml
│   ├── engineer-role-PROD.yaml
│   └── engineer-role-DEV.yaml
├── split/                      # Split components (for git)
│   └── engineer-role/
│       ├── 00-AGGREGATOR.yaml
│       ├── 01-core.yaml
│       ├── 02-apps.yaml
│       └── ...
├── reports/                    # Comparison reports
│   ├── comparison-20251029.md
│   └── comparison-20251029.html
└── scripts/                    # These tools
    ├── split-clusterrole-advanced.sh
    ├── compare-clusterroles.sh
    └── rbac-tools.sh
```

### Git Workflow

```bash
# Commit split roles, not monolithic ones
git add split/engineer-role/
git commit -m "chore: split engineer-role for easier review"

# Track changes to individual components
git diff split/engineer-role/05-monitoring.yaml

# Compare branches
git diff main feature/add-kafka-access -- split/engineer-role/
```

---

## 🔧 Advanced Features

### Custom Category Mapping

Edit `split-clusterrole-advanced.sh` and modify `CATEGORY_MAP`:

```bash
declare -A CATEGORY_MAP=(
    # Your custom categories
    ["my.custom.io"]="12-custom"
    ["internal.company.com"]="13-internal"
)
```

### JSON Output for Automation

```bash
# Split and parse with jq
./split-clusterrole-advanced.sh role.json --format json

# Compare and parse
./compare-clusterroles.sh ./roles --format json --output diff.json
cat diff.json | jq '.roles[] | select(.differences > 0)'
```

### Integration with CI/CD

```yaml
# .github/workflows/rbac-check.yml
name: RBAC Compliance Check

on:
  pull_request:
    paths:
      - 'rbac/**'

jobs:
  check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Install dependencies
        run: |
          sudo apt-get install -y jq yq
      
      - name: Validate roles
        run: |
          cd rbac/scripts
          ./rbac-tools.sh validate ../split/engineer-role/
      
      - name: Compare with PROD
        run: |
          cd rbac/scripts
          ./compare-clusterroles.sh ../roles --baseline PROD --output ../reports/pr-diff.md
      
      - name: Comment PR
        uses: actions/github-script@v6
        with:
          script: |
            const fs = require('fs');
            const report = fs.readFileSync('rbac/reports/pr-diff.md', 'utf8');
            github.rest.issues.createComment({
              issue_number: context.issue.number,
              owner: context.repo.owner,
              repo: context.repo.repo,
              body: report
            });
```

---

## 📋 Requirements

- `bash` 4.0+
- `jq` 1.6+
- `yq` 4.0+ (mikefarah/yq, not python-yq)
- `kubectl` (for extract command)
- `diff`, `comm`, `sort` (standard Unix tools)

### Install Dependencies

```bash
# Ubuntu/Debian
sudo apt-get install -y jq

# Install yq
sudo wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
sudo chmod +x /usr/local/bin/yq

# macOS
brew install jq yq
```

---

## 🐛 Troubleshooting

### "jq: error parsing"

**Problem**: Invalid JSON input

**Solution**: Validate your input file:
```bash
jq '.' your-role.json
yq eval '.' your-role.yaml
```

### "ClusterRole not found"

**Problem**: Role doesn't exist in cluster

**Solution**: List available roles:
```bash
kubectl get clusterrole | grep engineer
```

### Comparison shows no differences but there are

**Problem**: File naming issue

**Solution**: Ensure files follow pattern: `<role-name>-<ENV>.{yaml,yml,json}`
```bash
# Good
engineer-role-TEST.yaml
engineer-role-PROD.yaml

# Bad
engineer-role.TEST.yaml
engineer-role-test.yaml  # env must be uppercase
```

---

## 📖 Examples

See `temp/` directory for:
- `clusterrole.json` - Sample large role
- `clusterrole_aggregated_yaml/` - Example split output

---

## 🤝 Contributing

Improvements welcome! Consider adding:
- [ ] Support for Roles (not just ClusterRoles)
- [ ] Automated PRs for role updates
- [ ] Integration with Policy-as-Code tools (OPA, Kyverno)
- [ ] Slack/Teams notifications for permission changes

---

## 📄 License

Same as parent project.

---

**Created**: 2025-10-29  
**Author**: RBAC Tools Team  
**Version**: 1.0.0



