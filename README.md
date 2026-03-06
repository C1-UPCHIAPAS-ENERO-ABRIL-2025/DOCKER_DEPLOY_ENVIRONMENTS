# ModestInventary — Docker Orchestration Project

A certified, zero-trust full-stack project demonstrating Docker hermetic builds, ephemeral staging, and cryptographic evidence generation.

## Architecture

```
Frontend (React) ─► Nginx (sole gateway, port 8080) ─► Internet
Backend  (Flask) ─────────────────────────────────── frontend-backend network (internal)
Database (Postgres) ──────────────────────────────── backend-db network (internal: true)
```

## Quick Start

### 1. Initialize (first time only)

```bash
# Copy env template
cp .env.example .env

# Run the dev initialization script (sets up UID/GID + GPG keys)
bash scripts/init_dev.sh

# Install Git hooks
bash scripts/install_hooks.sh
```

### 2. Start Development Environment

```bash
docker compose --profile development up --build
```

Access the app at **http://localhost:3000**

Hot-reload is active for both frontend (Vite HMR) and backend (Flask debug mode) via symbolic volume mounts.

---

## Profiles

| Profile       | Command                                                       | Purpose                   |
| ------------- | ------------------------------------------------------------- | ------------------------- |
| `development` | `docker compose --profile development up`                     | Local dev with hot-reload |
| `staging`     | `docker compose --profile staging run --rm staging_certifier` | Ephemeral certification   |

---

## Staging & Certification

The staging environment is triggered **automatically** by a `[set]`-tagged commit:

```bash
git commit -m "feat: my feature [set]"
```

This triggers the `hooks/commit-msg` hook, which:

1. Launches an ephemeral container (does **not** touch the dev environment)
2. Runs static analysis → tests → artifact generation → GPG signing
3. Deposits a `evidence_output/evidence_<id>_<timestamp>.zip` package
4. **Aborts the commit** if any step fails (fail-safe)

### Test Framework Rotation (Dual Core)

Change `TEST_FRAMEWORK` in your `.env` to switch between unittest and pytest:

```dotenv
TEST_FRAMEWORK=unittest   # Capa A
TEST_FRAMEWORK=pytest     # Capa B (default)
```

---

## Evidence Package

The `evidence_output/*.zip` contains:

| File                | Description                                  |
| ------------------- | -------------------------------------------- |
| `report.md`         | Human-readable Markdown report               |
| `report.pdf`        | Visual, immutable PDF rendering              |
| `report.json`       | Raw structured data for dashboards           |
| `manifest.json`     | SLSA/In-toto attestation with SHA-256 hashes |
| `manifest.json.asc` | OpenPGP detached signature of the manifest   |

### Verifying Evidence Integrity

```bash
# Unzip the package
unzip evidence_output/evidence_*.zip -d /tmp/evidence

# Verify the GPG signature (cryptographic authenticity)
gpg --verify /tmp/evidence/manifest.json.asc /tmp/evidence/manifest.json

# Verify that the SHA-256 hashes in the manifest match the actual files
sha256sum /tmp/evidence/report.md /tmp/evidence/report.pdf /tmp/evidence/report.json
# → Compare these against the values in manifest.json > subject[].digest.sha256
```

---

## GPG Key Management

The developer's GPG key lives **only on the host** inside `.docker-gnupg/`.
During staging, it is **injected as read-only** into the container — it is never copied into the image.

```
volume: .docker-gnupg → /home/devuser/.gnupg:ro
```

The private key never leaves your machine.
