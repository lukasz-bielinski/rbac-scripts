#!/bin/bash
set -euo pipefail

ORIGINAL="$1"
SPLIT_DIR="$2"

echo "════════════════════════════════════════════════════════════"
echo "🔍 PORÓWNANIE: $(basename $ORIGINAL) vs $SPLIT_DIR/"
echo "════════════════════════════════════════════════════════════"
echo ""

# Original stats
ORIG_RULES=$(jq '.rules | length' "$ORIGINAL")
ORIG_APIGROUPS=$(jq -r '.rules[].apiGroups[]?' "$ORIGINAL" | sort -u | wc -l)
ORIG_RESOURCES=$(jq -r '.rules[].resources[]?' "$ORIGINAL" | sort -u | wc -l)

# Split stats (tylko pliki komponentowe, bez agregatora)
cd "$SPLIT_DIR"
SPLIT_RULES=$(for f in [0-9]*.yaml; do yq eval -o=json '.rules[]?' "$f"; done | jq -s '. | length')
SPLIT_APIGROUPS=$(for f in [0-9]*.yaml; do yq eval -o=json '.rules[]?' "$f"; done | jq -r '.apiGroups[]?' | sort -u | wc -l)
SPLIT_RESOURCES=$(for f in [0-9]*.yaml; do yq eval -o=json '.rules[]?' "$f"; done | jq -r '.resources[]?' | sort -u | wc -l)

echo "📊 Statystyki:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
printf "%-20s %10s %10s %10s\n" "" "Original" "Split" "Status"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
printf "%-20s %10s %10s " "Rules:" "$ORIG_RULES" "$SPLIT_RULES"
if [ "$ORIG_RULES" -eq "$SPLIT_RULES" ]; then echo "✅"; else echo "❌"; fi

printf "%-20s %10s %10s " "API Groups:" "$ORIG_APIGROUPS" "$SPLIT_APIGROUPS"
if [ "$ORIG_APIGROUPS" -eq "$SPLIT_APIGROUPS" ]; then echo "✅"; else echo "❌"; fi

printf "%-20s %10s %10s " "Resources:" "$ORIG_RESOURCES" "$SPLIT_RESOURCES"
if [ "$ORIG_RESOURCES" -eq "$SPLIT_RESOURCES" ]; then echo "✅"; else echo "❌"; fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Sprawdź co zniknęło
cd - > /dev/null
MISSING_API=$(comm -23 \
  <(jq -r '.rules[].apiGroups[]?' "$ORIGINAL" | sort -u) \
  <(cd "$SPLIT_DIR" && for f in [0-9]*.yaml; do yq eval -o=json '.rules[]?' "$f"; done | jq -r '.apiGroups[]?' | sort -u))

if [ -n "$MISSING_API" ]; then
  echo "❌ Zniknęły API Groups:"
  echo "$MISSING_API"
  echo ""
fi

MISSING_RES=$(comm -23 \
  <(jq -r '.rules[].resources[]?' "$ORIGINAL" | sort -u) \
  <(cd "$SPLIT_DIR" && for f in [0-9]*.yaml; do yq eval -o=json '.rules[]?' "$f"; done | jq -r '.resources[]?' | sort -u))

if [ -n "$MISSING_RES" ]; then
  echo "❌ Zniknęły Resources:"
  echo "$MISSING_RES" | head -20
  echo ""
fi

if [ -z "$MISSING_API" ] && [ -z "$MISSING_RES" ]; then
  echo "✅ Wszystkie API Groups i Resources zachowane!"
fi
