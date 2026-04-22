#!/usr/bin/env bash
# check-import-tiers.sh — Enforce the ADR-0008 four-tier import-map rule.
#
# A file in a lower tier must not import a type from a higher tier. This
# script is a conservative heuristic:
#   - It maps each Swift file to a tier based on its directory prefix.
#   - It scans for `import ZeroDark...` statements (which the codebase
#     does not use — we're one module) and for type-name references that
#     exist ONLY in a higher tier's subtree. This catches the common
#     mistake: a core service referencing a View type by name.
#
# The grammar is dumb on purpose — it's a pre-commit rather than a
# semantic analyzer. Fast and false-positive-tolerant.
#
# Tier definitions match ADR 0008:
#   0 Primitives : Diagnostics/, Hardware/Common/
#   1 Core       : Security/, SecurityLayer/, Navigation/Core/,
#                  Intelligence/ActionBoundary/, CommunicationCore/DTN/
#   2 Domains    : Navigation/, Intelligence/, Medical/,
#                  SpatialIntelligence/, CommunicationCore/,
#                  Scenarios/, Services/, FieldOps/, Coordination/,
#                  Hardware/, LiDAR/, Planning/, Mapping/, Logistics/,
#                  Training/
#   3 UI + App   : App/, UI/, Tier1/Features/
#
# Usage:
#   scripts/check-import-tiers.sh              # advisory mode (exit 0)
#   scripts/check-import-tiers.sh --strict     # fail on new violations above baseline
#
# The codebase has a documented pre-existing backlog of tier violations
# (see docs/adr/0008-import-map-tiers.md). In advisory mode the linter
# prints every violation it sees and exits 0. In --strict mode it
# compares against BASELINE (the expected count) and exits non-zero only
# when the count goes UP — so existing violations don't block every PR
# but new ones trip the gate.

set -euo pipefail

STRICT=0
for arg in "$@"; do
  case "$arg" in
    --strict) STRICT=1 ;;
  esac
done

BASELINE=70   # current pre-existing count (as of PR-P3); refresh down when cleaning up.

SRC_ROOT="Sources/MLXEdgeLLM"

if [[ ! -d "$SRC_ROOT" ]]; then
  echo "error: run from repo root (expected $SRC_ROOT)" >&2
  exit 2
fi

# Map a file path to its tier integer (0–3). Returns 2 for anything that
# doesn't match a tier-0/1/3 prefix — domains default.
tier_for() {
  local path="$1"
  case "$path" in
    *"$SRC_ROOT/Diagnostics/"*|*"$SRC_ROOT/Hardware/Common/"*)
      echo 0 ;;
    *"$SRC_ROOT/Security/"*|*"$SRC_ROOT/SecurityLayer/"*|*"$SRC_ROOT/Navigation/Core/"*|*"$SRC_ROOT/Intelligence/ActionBoundary/"*|*"$SRC_ROOT/CommunicationCore/DTN/"*)
      echo 1 ;;
    *"$SRC_ROOT/App/"*|*"$SRC_ROOT/UI/"*|*"$SRC_ROOT/Tier1/Features/"*)
      echo 3 ;;
    *)
      echo 2 ;;
  esac
}

# Some type names are tier-3-only. Add to this list (one per line) as
# violations come up. The regex is a whole-word match.
TIER3_ONLY_NAMES=(
  "MapTabView"
  "IntelTabView"
  "OpsTabView"
  "NavTabView"
  "LiDARTabView"
  "SettingsTabView"
  "ContentView"
  "ZeroDarkBootView"
  "AppLockGate"
)

# Some imports are tier-3-only (the UI framework).
TIER3_ONLY_IMPORTS=(
  "SwiftUI"
  "UIKit"
)

violations=0

# Walk every Swift file once; cheap enough at ~700 files.
while IFS= read -r -d '' file; do
  file_tier=$(tier_for "$file")

  # Tier 0 + 1 must not import SwiftUI / UIKit.
  if [[ "$file_tier" == "0" || "$file_tier" == "1" ]]; then
    for t3_import in "${TIER3_ONLY_IMPORTS[@]}"; do
      if grep -qE "^import[[:space:]]+${t3_import}\\b" "$file"; then
        echo "tier-violation: $file (tier $file_tier) imports $t3_import (tier 3)"
        violations=$((violations + 1))
      fi
    done
  fi

  # Tier 0–2 must not reference tier-3-only View names. Skip when the
  # reference is the file's own type (AppLockGate.swift mentioning
  # AppLockGate is obviously legitimate).
  if [[ "$file_tier" != "3" ]]; then
    basename=$(basename "$file" .swift)
    for name in "${TIER3_ONLY_NAMES[@]}"; do
      if [[ "$basename" == "$name" ]]; then
        continue
      fi
      if grep -qE "\\b${name}\\b" "$file"; then
        echo "tier-violation: $file (tier $file_tier) references $name (tier 3)"
        violations=$((violations + 1))
      fi
    done
  fi

done < <(find "$SRC_ROOT" -name '*.swift' -type f -print0)

echo
echo "import-map: $violations violation(s) (baseline: $BASELINE)"

if [[ $STRICT -eq 1 && $violations -gt $BASELINE ]]; then
  echo "strict mode: count rose above baseline ($BASELINE); failing."
  echo "See docs/adr/0008-import-map-tiers.md for the rule."
  exit 1
fi
