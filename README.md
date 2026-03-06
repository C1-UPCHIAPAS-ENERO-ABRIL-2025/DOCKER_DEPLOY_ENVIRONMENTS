# ModestInventory — Docker Orchestration & Certified Evidence System

A full-stack project demonstrating **zero-trust Docker orchestration**, ephemeral staging, and **cryptographic evidence generation** with a fully automated quality gate.

## Architecture

```
Frontend (React/Vite) ─► Nginx (gateway)  ─► http://localhost:3000 (dev)
Backend  (Flask)      ─────────────────────── frontend-backend network (internal)
Database (PostgreSQL) ─────────────────────── backend-db network (internal: true)
```

---

## Quick Start

### 1. Initialize (first time only)

```bash
# Copy env template and fill in your values
cp .env.example .env

# Set up UID/GID and GPG identity
bash scripts/init_dev.sh

# Configure Git to use the versioned hooks (run once per clone)
bash scripts/install_hooks.sh
```

### 2. Start Development

```bash
docker compose --profile development up --build
```

Access the app at **http://localhost:3000** — hot-reload active on both frontend (Vite HMR) and backend (Flask debug).

---

## Profiles & Ports

| Profile       | Command                                           | URL                   |
| ------------- | ------------------------------------------------- | --------------------- |
| `development` | `docker compose --profile development up --build` | http://localhost:3000 |
| `staging`     | triggered automatically by `[set]` commit tag     | http://localhost:3001 |

---

## Git Hooks (Quality Gate)

Two hooks are installed via `core.hooksPath` — no files are ever copied to `.git/hooks/`. Changes to `hooks/` take effect immediately.

### `pre-commit` — runs before every commit

Executes inside isolated Docker containers (zero OS dependency):

| Tool       | What it checks                    | Threshold (`.env`)                 |
| ---------- | --------------------------------- | ---------------------------------- |
| `mypy`     | Type safety                       | `MYPY_MODE=standard\|strict`       |
| `pylint`   | Code quality score                | `PYLINT_MIN_SCORE=6.5`             |
| `hadolint` | Dockerfile best practices (all 3) | `HADOLINT_FAILURE_THRESHOLD=error` |

### `commit-msg` — triggered only on `[set]`-tagged commits

```bash
git commit -m "feat: my feature [set]"
```

Launches an **ephemeral staging certifier** that:

1. Runs the full static analysis pipeline
2. Runs unit tests (Phase 2A) and integration tests if `DATABASE_URL` is set (Phase 2B)
3. Generates artifacts (`.md`, `.pdf`, `.json`)
4. Builds an SLSA/In-toto attestation manifest with SHA-256 hashes
5. Signs the manifest with your GPG key (key **never** leaves the host)
6. Packages everything into `evidence_output/evidence_<id>_<timestamp>.zip`
7. **Aborts the commit** if any step fails

---

## Quality Thresholds (configurable in `.env`)

All thresholds are passed into the staging container and recorded in the SLSA manifest for full traceability.

```dotenv
PYLINT_MIN_SCORE=6.5          # 0.0–10.0
MYPY_MODE=standard            # standard | strict
COVERAGE_MIN=70               # 0–100 (%)
BANDIT_LEVEL=LOW              # LOW | MEDIUM | HIGH
BANDIT_CONFIDENCE=LOW         # LOW | MEDIUM | HIGH
RADON_MIN_GRADE=B             # A | B | C | D
HADOLINT_FAILURE_THRESHOLD=error  # error | warning | info | style | ignore
TEST_FRAMEWORK=pytest         # pytest | unittest
```

---

## Staging Pipeline Phases

| Phase    | Description                                                      |
| -------- | ---------------------------------------------------------------- |
| Phase 1  | Static analysis: `mypy`, `pylint`, `radon`, `bandit`, `hadolint` |
| Phase 2A | Unit tests with coverage (`pytest` or `unittest`)                |
| Phase 2B | Integration tests against real DB (skipped if no `DATABASE_URL`) |
| Phase 3  | Artifact generation: `report.md`, `report.pdf`, `report.json`    |
| Phase 4  | SLSA/In-toto manifest with SHA-256 attestation                   |
| Phase 5  | OpenPGP detached signature (GPG key mounted `:ro`)               |
| Phase 6  | ZIP package deposited to `evidence_output/`                      |

---

## Evidence Package

The `evidence_output/*.zip` contains:

| File                | Description                                                            |
| ------------------- | ---------------------------------------------------------------------- |
| `report.md`         | Human-readable Markdown report                                         |
| `report.pdf`        | Visual PDF rendering                                                   |
| `report.json`       | Raw structured data                                                    |
| `manifest.json`     | SLSA/In-toto attestation with SHA-256 hashes + quality thresholds used |
| `manifest.json.asc` | OpenPGP detached signature of the manifest                             |

### Verify integrity

```bash
unzip evidence_output/evidence_*.zip -d /tmp/evidence
gpg --verify /tmp/evidence/manifest.json.asc /tmp/evidence/manifest.json
sha256sum /tmp/evidence/report.md /tmp/evidence/report.pdf /tmp/evidence/report.json
# Compare against manifest.json > subject[].digest.sha256
```

---

## Project Structure

```
project_root/
├── backend/                  # Python Flask API
│   ├── Dockerfile            # Multi-stage: base → app (dev) → unittest → pytest
│   ├── scripts/
│   │   ├── run_staging.sh    # Staging certifier entrypoint (runs inside container)
│   │   └── generate_report.py
│   └── tests/
│       ├── test_routes_pytest.py
│       ├── test_routes_unittest.py
│       └── test_integration.py   # Integration tests (DATABASE_URL guarded)
├── frontend/                 # React/Vite UI
├── nginx/                    # Reverse proxy gateway
├── hooks/                    # Git hooks (versioned, not in .git/)
│   ├── pre-commit            # mypy + pylint + hadolint gate
│   └── commit-msg            # [set] → staging certifier trigger
├── scripts/                  # Host-side scripts
│   ├── init_dev.sh           # First-time setup (UID/GID + GPG)
│   └── install_hooks.sh      # Sets git config core.hooksPath
├── evidence_output/          # ZIP evidence packages (gitignored content)
├── .docker-gnupg/            # Developer GPG keystore (mounted :ro to container)
├── docker-compose.yml        # Profiles: development | staging
└── .env                      # Local config (copy from .env.example)
```

---

## GPG Zero-Trust Design

The developer's GPG key lives **only on the host** inside `.docker-gnupg/`.
During staging, it is injected as **read-only** into the ephemeral container:

```
.docker-gnupg/ → /home/devuser/.gnupg:ro
```

The private key is never copied into the Docker image. An ephemeral writable copy is created in `/tmp` for signing, then immediately wiped. The original keystore is never modified.
