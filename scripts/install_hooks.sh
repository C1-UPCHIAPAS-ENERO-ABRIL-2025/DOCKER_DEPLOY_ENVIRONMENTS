#!/usr/bin/env bash
# ============================================================
# scripts/install_hooks.sh
# Copies the hooks from /hooks into .git/hooks and makes them executable.
# Run once after cloning: bash scripts/install_hooks.sh
# ============================================================
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOKS_SRC="${PROJECT_ROOT}/hooks"
HOOKS_DST="${PROJECT_ROOT}/.git/hooks"

echo "🔗 Installing Git hooks..."

for hook in pre-commit commit-msg; do
  if [ -f "${HOOKS_SRC}/${hook}" ]; then
    cp "${HOOKS_SRC}/${hook}" "${HOOKS_DST}/${hook}"
    chmod +x "${HOOKS_DST}/${hook}"
    echo "  ✅ ${hook} installed."
  else
    echo "  ⚠️  ${hook} not found in ${HOOKS_SRC}; skipping."
  fi
done

echo ""
echo "✅ Git hooks installed successfully."
