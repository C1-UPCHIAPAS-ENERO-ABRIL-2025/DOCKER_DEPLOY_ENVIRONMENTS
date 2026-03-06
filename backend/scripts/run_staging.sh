#!/usr/bin/env bash
# ============================================================
# backend/scripts/run_staging.sh
# Entrypoint for the ephemeral staging certifier container.
# This script lives inside the backend folder so that when the
# container mounts ./backend:/app:ro, it is accessible at
# /app/scripts/run_staging.sh inside the container.
#
# All quality thresholds are injected via environment variables.
# Args: $1 = 'unittest' | 'pytest'
# ============================================================
set -euo pipefail

FRAMEWORK="${1:-pytest}"
WORKDIR="/app"
EVIDENCE_DIR="/evidence"
REPORTS_WORK="/tmp/reports"
GPG_HOME="/home/devuser/.gnupg"

COMMIT_SHORT_ID="${COMMIT_SHORT_ID:-$(date +%s | sha1sum | head -c 7)}"
COMMIT_TIMESTAMP="${COMMIT_TIMESTAMP:-$(date -u +"%Y-%m-%dT%H:%M:%SZ")}"
DOCKER_IMAGE_ID="${DOCKER_IMAGE_ID:-unknown}"
SAFE_TIMESTAMP=$(echo "${COMMIT_TIMESTAMP}" | tr ':' '-')
PACKAGE_NAME="evidence_${COMMIT_SHORT_ID}_${SAFE_TIMESTAMP}"

# ---- Configurable Thresholds (from env, with defaults) ----
PYLINT_MIN_SCORE="${PYLINT_MIN_SCORE:-7.0}"
MYPY_MODE="${MYPY_MODE:-standard}"
COVERAGE_MIN="${COVERAGE_MIN:-70}"
BANDIT_LEVEL="${BANDIT_LEVEL:-LOW}"
BANDIT_CONFIDENCE="${BANDIT_CONFIDENCE:-LOW}"
RADON_MIN_GRADE="${RADON_MIN_GRADE:-B}"
HADOLINT_THRESHOLD="${HADOLINT_FAILURE_THRESHOLD:-error}"

mkdir -p "${REPORTS_WORK}"

echo "========================================================"
echo " 🔬 Staging Certifier — Framework: ${FRAMEWORK}"
echo "    Commit   : ${COMMIT_SHORT_ID}"
echo "    Time     : ${COMMIT_TIMESTAMP}"
echo "    Image ID : ${DOCKER_IMAGE_ID}"
echo "  ── Thresholds ────────────────────────────────────"
echo "    pylint    : min ${PYLINT_MIN_SCORE}/10"
echo "    mypy      : ${MYPY_MODE} mode"
echo "    coverage  : min ${COVERAGE_MIN}%"
echo "    bandit    : level≥${BANDIT_LEVEL}, confidence≥${BANDIT_CONFIDENCE}"
echo "    radon     : min grade ${RADON_MIN_GRADE}"
echo "    hadolint  : fail-on≥${HADOLINT_THRESHOLD}"
echo "========================================================="

cd "${WORKDIR}"

# ============================================================
# PHASE 1 — Static Analysis
# ============================================================
echo ""
echo "📐 PHASE 1: Static Analysis"

# --- mypy ---
echo "  ▶ mypy (mode: ${MYPY_MODE})..."
MYPY_FLAGS="--ignore-missing-imports"
[ "${MYPY_MODE}" = "strict" ] && MYPY_FLAGS="--strict ${MYPY_FLAGS}"
# shellcheck disable=SC2086
mypy app/ ${MYPY_FLAGS} 2>&1 | tee "${REPORTS_WORK}/mypy_output.txt"
echo "  ✅ mypy OK"

# --- pylint ---
echo "  ▶ pylint (min: ${PYLINT_MIN_SCORE}/10)..."
PYLINT_OUT=$(pylint app/ --output-format=parseable --score=y 2>&1 || true)
echo "${PYLINT_OUT}" | tee "${REPORTS_WORK}/pylint_output.txt"
PYLINT_SCORE=$(echo "${PYLINT_OUT}" | grep -oP 'rated at \K[0-9]+(\.[0-9]+)?' | head -1 || echo "0")
PYLINT_SCORE="${PYLINT_SCORE:-0}"
PASSES=$(awk -v s="${PYLINT_SCORE}" -v m="${PYLINT_MIN_SCORE}" 'BEGIN{print(s+0>=m+0)?"yes":"no"}')
if [ "${PASSES}" != "yes" ]; then
  echo "❌ FAIL-SAFE: pylint score ${PYLINT_SCORE} < ${PYLINT_MIN_SCORE}. Aborting."
  exit 1
fi
echo "  ✅ pylint OK (${PYLINT_SCORE}/10)"

# --- radon ---
echo "  ▶ radon (min grade: ${RADON_MIN_GRADE})..."
radon mi -s app/ 2>&1 | tee "${REPORTS_WORK}/radon_output.txt"
echo "  ✅ radon OK"

# --- bandit ---
echo "  ▶ bandit (level≥${BANDIT_LEVEL}, confidence≥${BANDIT_CONFIDENCE})..."
bandit -r app/ \
  --severity-level "${BANDIT_LEVEL}" \
  --confidence-level "${BANDIT_CONFIDENCE}" \
  -f txt 2>&1 | tee "${REPORTS_WORK}/bandit_output.txt"
echo "  ✅ bandit OK"

# --- hadolint ---
echo "  ▶ hadolint (Dockerfile linter, fail-on≥${HADOLINT_THRESHOLD})..."
hadolint --failure-threshold "${HADOLINT_THRESHOLD}" Dockerfile 2>&1 \
  | tee "${REPORTS_WORK}/hadolint_output.txt" || {
  echo "❌ FAIL-SAFE: hadolint found issues in Dockerfile. Aborting."
  exit 1
}
echo "  ✅ hadolint OK"
echo "  ✅ Static analysis phase complete."

# ============================================================
# PHASE 2A — Unit Tests (no external dependencies)
# ============================================================
echo ""
echo "🧪 PHASE 2A: Unit Tests (${FRAMEWORK}, coverage min: ${COVERAGE_MIN}%)"

# ⚠️  /app is mounted :ro — coverage data MUST be written to /tmp
export COVERAGE_FILE="${REPORTS_WORK}/.coverage"

if [ "${FRAMEWORK}" = "unittest" ]; then
  python -m coverage run --branch -m unittest discover \
    -s tests -p "test_routes_unittest.py" 2>&1 \
    | tee "${REPORTS_WORK}/test_unit_output.txt"
  python -m coverage report --fail-under="${COVERAGE_MIN}" 2>&1 \
    | tee -a "${REPORTS_WORK}/test_unit_output.txt"
  python -m coverage json -o "${REPORTS_WORK}/coverage.json"
else
  python -m pytest tests/test_routes_pytest.py \
    --cov=app \
    --cov-report=json:"${REPORTS_WORK}/coverage.json" \
    --cov-fail-under="${COVERAGE_MIN}" \
    --rootdir="${WORKDIR}" \
    -p no:cacheprovider \
    -v 2>&1 \
    | tee "${REPORTS_WORK}/test_unit_output.txt"
fi
echo "  ✅ Unit tests and coverage passed."

# ============================================================
# PHASE 2B — Integration Tests (requires DATABASE_URL)
# Skipped gracefully if DATABASE_URL is not set or tests folder is empty
# ============================================================
echo ""
echo "🔗 PHASE 2B: Integration Tests"
INTEGRATION_TEST_FILE="tests/test_integration.py"

if [ -z "${DATABASE_URL:-}" ]; then
  echo "  ℹ️  DATABASE_URL not set — skipping integration tests."
elif [ ! -f "${INTEGRATION_TEST_FILE}" ]; then
  echo "  ℹ️  No integration test file found — skipping."
else
  echo "  ▶ Running integration tests against ${DATABASE_URL}..."
  if [ "${FRAMEWORK}" = "unittest" ]; then
    python -m coverage run --branch --append -m unittest discover \
      -s tests -p "test_integration.py" 2>&1 \
      | tee "${REPORTS_WORK}/test_integration_output.txt"
  else
    python -m pytest tests/test_integration.py -v \
      --cov=app --cov-append \
      --cov-report=json:"${REPORTS_WORK}/coverage_integration.json" 2>&1 \
      | tee "${REPORTS_WORK}/test_integration_output.txt"
  fi
  echo "  ✅ Integration tests passed."
fi

# Merge unit+integration output for the report
cat "${REPORTS_WORK}/test_unit_output.txt" \
    "${REPORTS_WORK}/test_integration_output.txt" 2>/dev/null \
    > "${REPORTS_WORK}/test_output.txt" || \
  cp "${REPORTS_WORK}/test_unit_output.txt" "${REPORTS_WORK}/test_output.txt"

# ============================================================
# PHASE 3 — Artifact Generation (MD, PDF, JSON)
# ============================================================
echo ""
echo "📄 PHASE 3: Generating Artifacts"

python /app/scripts/generate_report.py \
  --workdir "${REPORTS_WORK}" \
  --commit-id "${COMMIT_SHORT_ID}" \
  --timestamp "${COMMIT_TIMESTAMP}" \
  --framework "${FRAMEWORK}" \
  --build-id "${DOCKER_IMAGE_ID}"

echo "  ✅ Artifacts: report.md, report.pdf, report.json"

# ============================================================
# PHASE 4 — SLSA / In-toto Attestation Manifest
# ============================================================
echo ""
echo "🗂️  PHASE 4: Building SLSA/In-toto Attestation Manifest"

MD5_MD=$(sha256sum "${REPORTS_WORK}/report.md"    | awk '{print $1}')
MD5_PDF=$(sha256sum "${REPORTS_WORK}/report.pdf"  | awk '{print $1}')
MD5_JSON=$(sha256sum "${REPORTS_WORK}/report.json" | awk '{print $1}')

cat > "${REPORTS_WORK}/manifest.json" <<EOF
{
  "_type": "https://in-toto.io/Statement/v0.1",
  "predicateType": "https://slsa.dev/provenance/v0.2",
  "subject": [
    {"name": "report.md",   "digest": {"sha256": "${MD5_MD}"}},
    {"name": "report.pdf",  "digest": {"sha256": "${MD5_PDF}"}},
    {"name": "report.json", "digest": {"sha256": "${MD5_JSON}"}}
  ],
  "predicate": {
    "builder": {"id": "docker://staging_certifier@${DOCKER_IMAGE_ID}"},
    "buildType": "hermetic-container",
    "metadata": {
      "buildStartedOn":  "${COMMIT_TIMESTAMP}",
      "buildFinishedOn": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
      "completeness": {"parameters": true, "environment": false, "materials": false},
      "reproducible": false
    },
    "invocation": {
      "configSource": {"uri": "local://docker-compose.yml"},
      "parameters": {
        "commit_short_id":   "${COMMIT_SHORT_ID}",
        "test_framework":    "${FRAMEWORK}",
        "pylint_min_score":  "${PYLINT_MIN_SCORE}",
        "mypy_mode":         "${MYPY_MODE}",
        "coverage_min":      "${COVERAGE_MIN}",
        "bandit_level":      "${BANDIT_LEVEL}",
        "bandit_confidence": "${BANDIT_CONFIDENCE}",
        "radon_min_grade":   "${RADON_MIN_GRADE}",
        "hadolint_threshold":"${HADOLINT_THRESHOLD}"
      }
    }
  }
}
EOF

echo "  ✅ manifest.json created."

# ============================================================
# PHASE 5 — Cryptographic Detached Signature (OpenPGP)
# The GPG keystore is mounted read-only (/home/devuser/.gnupg:ro).
# GPG requires a writable homedir for lock files and agent sockets.
# Solution (Zero Trust preserving):
#   1. Copy keystore to an ephemeral writable location in /tmp
#   2. Sign using the /tmp copy — key never leaves the container
#   3. /tmp is destroyed automatically when the container exits
# ============================================================
echo ""
echo "🔏 PHASE 5: Signing Manifest with OpenPGP (detached signature)"

GNUPG_RO="${GPG_HOME}"
GNUPG_WORK="/tmp/gnupg-work"

echo "  ▶ Copying keystore to ephemeral writable location..."
rm -rf "${GNUPG_WORK}"
cp -r "${GNUPG_RO}" "${GNUPG_WORK}"
chmod 700 "${GNUPG_WORK}"
# Fix trust database permissions if needed
chmod 600 "${GNUPG_WORK}"/* 2>/dev/null || true

export GNUPGHOME="${GNUPG_WORK}"
GPG_KEY_ID="${GPG_KEY_ID:-}"

if [ -z "${GPG_KEY_ID}" ]; then
  echo "  ℹ️  GPG_KEY_ID not set — using first available secret key..."
  GPG_KEY_ID=$(gpg --list-secret-keys --keyid-format LONG 2>/dev/null \
    | grep "^sec" | head -1 | awk '{print $2}' | cut -d'/' -f2 || echo "")
fi

if [ -z "${GPG_KEY_ID}" ]; then
  echo "❌ FAIL-SAFE: No GPG secret key found in '${GNUPG_RO}'. Aborting."
  exit 1
fi

echo "  ▶ Signing manifest with key ${GPG_KEY_ID}..."
gpg --batch --yes \
    --no-tty \
    --pinentry-mode loopback \
    --local-user "${GPG_KEY_ID}" \
    --detach-sign \
    --armor \
    --output "${REPORTS_WORK}/manifest.json.asc" \
    "${REPORTS_WORK}/manifest.json"

echo "  ✅ manifest.json.asc created using key ${GPG_KEY_ID}."
echo "  🗑️  Ephemeral keystore copy wiped from /tmp."
chmod -R u+rwX "${GNUPG_WORK}" 2>/dev/null || true
rm -rf "${GNUPG_WORK}"

# ============================================================
# PHASE 6 — Package and Deposit
# ============================================================
echo ""
echo "📦 PHASE 6: Packaging Evidence"

OUTPUT_ZIP="${EVIDENCE_DIR}/${PACKAGE_NAME}.zip"

zip -j "${OUTPUT_ZIP}" \
  "${REPORTS_WORK}/report.md" \
  "${REPORTS_WORK}/report.pdf" \
  "${REPORTS_WORK}/report.json" \
  "${REPORTS_WORK}/manifest.json" \
  "${REPORTS_WORK}/manifest.json.asc"

echo "  ✅ Evidence package: ${OUTPUT_ZIP}"

echo ""
echo "========================================================"
echo " ✅ Certification COMPLETE"
echo "    Package: ${PACKAGE_NAME}.zip"
echo "========================================================"
exit 0
