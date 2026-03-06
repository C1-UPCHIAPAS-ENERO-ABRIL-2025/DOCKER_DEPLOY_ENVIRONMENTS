#!/usr/bin/env bash
# ============================================================
# scripts/install_hooks.sh
# Configures Git to use the project's hooks/ directory directly.
#
# Run once after cloning:
#   bash scripts/install_hooks.sh
# ============================================================
set -euo pipefail

echo "🔗 Configuring Git hooks path..."

# Point Git to the versioned hooks/ folder (relative path — works on all OSes)
git config core.hooksPath hooks

# On Windows (NTFS), chmod does NOT set the git executable bit.
# git update-index --chmod=+x is the correct way to mark hooks as executable
# so that Git for Windows will actually run them.
git update-index --chmod=+x hooks/pre-commit
git update-index --chmod=+x hooks/commit-msg

# Also try chmod for Linux/macOS compatibility (harmless if NTFS ignores it)
chmod +x hooks/pre-commit hooks/commit-msg 2>/dev/null || true

echo "  ✅ Git will now use hooks from: hooks/"
echo "  ✅ Executable bit set in git index (Windows compatible)"
echo ""
echo "✅ Done! No need to run this script again after updating hooks."
echo "   Hook changes take effect immediately."
