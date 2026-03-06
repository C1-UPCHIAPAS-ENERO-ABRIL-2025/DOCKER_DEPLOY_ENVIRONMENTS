#!/usr/bin/env bash
# ============================================================
# scripts/run_staging.sh
# Entrypoint for the ephemeral staging certifier container.
# Executes: static analysis → dynamic tests → report generation
#           → SLSA manifest → GPG sign → ZIP package
#
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
SAFE_TIMESTAMP=$(echo "${COMMIT_TIMESTAMP}" | tr ':' '-')
PACKAGE_NAME="evidence_${COMMIT_SHORT_ID}_${SAFE_TIMESTAMP}"

mkdir -p "${REPORTS_WORK}"

echo "========================================================"
echo " 🔬 Staging Certifier — Framework: ${FRAMEWORK}"
echo "    Commit  : ${COMMIT_SHORT_ID}"
echo "    Time    : ${COMMIT_TIMESTAMP}"
echo "========================================================"

cd "${WORKDIR}"

# ============================================================
# PHASE 1 — Static Analysis
# mypy, pylint, radon, bandit — abort on any failure
# ============================================================
echo ""
echo "📐 PHASE 1: Static Analysis"

echo "  ▶ mypy..."
mypy app/ --ignore-missing-imports 2>&1 | tee "${REPORTS_WORK}/mypy_output.txt"
echo "  ✅ mypy OK"

echo "  ▶ pylint..."
pylint app/ --output-format=parseable 2>&1 | tee "${REPORTS_WORK}/pylint_output.txt"
echo "  ✅ pylint OK"

echo "  ▶ radon maintainability..."
radon mi -s app/ 2>&1 | tee "${REPORTS_WORK}/radon_output.txt"

echo "  ▶ bandit security scan..."
bandit -r app/ -f txt 2>&1 | tee "${REPORTS_WORK}/bandit_output.txt"
echo "  ✅ Static analysis phase complete."

# ============================================================
# PHASE 2 — Dynamic Tests
# Runs either unittest or pytest depending on $FRAMEWORK
# ============================================================
echo ""
echo "🧪 PHASE 2: Dynamic Tests (${FRAMEWORK})"

if [ "${FRAMEWORK}" = "unittest" ]; then
  python -m coverage run --branch -m unittest discover -s tests -p "test_routes_unittest.py" 2>&1 \
    | tee "${REPORTS_WORK}/test_output.txt"
  python -m coverage report --fail-under=70 2>&1 \
    | tee -a "${REPORTS_WORK}/test_output.txt"
  python -m coverage json -o "${REPORTS_WORK}/coverage.json"
else
  python -m pytest tests/test_routes_pytest.py \
    --cov=app --cov-report=json:"${REPORTS_WORK}/coverage.json" \
    --cov-fail-under=70 -v 2>&1 \
    | tee "${REPORTS_WORK}/test_output.txt"
fi

echo "  ✅ Tests and coverage passed."

# ============================================================
# PHASE 3 — Artifact Generation (MD, PDF, JSON)
# ============================================================
echo ""
echo "📄 PHASE 3: Generating Artifacts"

python /app/scripts/generate_report.py \
  --workdir "${REPORTS_WORK}" \
  --commit-id "${COMMIT_SHORT_ID}" \
  --timestamp "${COMMIT_TIMESTAMP}" \
  --framework "${FRAMEWORK}"

echo "  ✅ Artifacts: report.md, report.pdf, report.json"

# ============================================================
# PHASE 4 — SLSA / In-toto Attestation Manifest
# ============================================================
echo ""
echo "🗂️  PHASE 4: Building SLSA/In-toto Attestation Manifest"

MD5_MD=$(sha256sum "${REPORTS_WORK}/report.md"   | awk '{print $1}')
MD5_PDF=$(sha256sum "${REPORTS_WORK}/report.pdf" | awk '{print $1}')
MD5_JSON=$(sha256sum "${REPORTS_WORK}/report.json" | awk '{print $1}')

DOCKER_IMAGE=$(docker inspect --format='{{index .RepoDigests 0}}' "$(hostname)" 2>/dev/null || echo "local/staging-certifier")

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
    "builder": {"id": "docker://staging_certifier"},
    "buildType": "hermetic-container",
    "metadata": {
      "buildStartedOn":  "${COMMIT_TIMESTAMP}",
      "buildFinishedOn": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
      "completeness": {"parameters": true, "environment": false, "materials": false},
      "reproducible": false
    },
    "invocation": {
      "configSource": {
        "uri": "local://docker-compose.yml",
        "digest": {"sha256": "$(sha256sum /app/../docker-compose.yml 2>/dev/null | awk '{print $1}' || echo 'n/a')"}
      },
      "parameters": {
        "commit_short_id": "${COMMIT_SHORT_ID}",
        "test_framework":  "${FRAMEWORK}"
      }
    }
  }
}
EOF

echo "  ✅ manifest.json created."

# ============================================================
# PHASE 5 — Cryptographic Detached Signature (OpenPGP)
# GPG keystore is mounted read-only — key is NEVER copied
# ============================================================
echo ""
echo "🔏 PHASE 5: Signing Manifest with OpenPGP (detached signature)"

export GNUPGHOME="${GPG_HOME}"
GPG_KEY_ID="${GPG_KEY_ID:-}"

if [ -z "${GPG_KEY_ID}" ]; then
  echo "  ℹ️  GPG_KEY_ID not set — using first available secret key..."
  GPG_KEY_ID=$(gpg --list-secret-keys --keyid-format LONG 2>/dev/null \
    | grep "^sec" | head -1 | awk '{print $2}' | cut -d'/' -f2 || echo "")
fi

if [ -z "${GPG_KEY_ID}" ]; then
  echo "❌ FAIL-SAFE: No GPG secret key found in '${GPG_HOME}'. Aborting."
  exit 1
fi

gpg --batch --yes \
    --local-user "${GPG_KEY_ID}" \
    --detach-sign \
    --armor \
    --output "${REPORTS_WORK}/manifest.json.asc" \
    "${REPORTS_WORK}/manifest.json"

echo "  ✅ manifest.json.asc created using key ${GPG_KEY_ID}."

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
