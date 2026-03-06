# ============================================================
# Backend "Dual Core" Dockerfile
# Multi-stage: base → app (dev) → unittest (staging-A) → pytest (staging-B)
# ============================================================

# Pull hadolint binary from the official image (zero OS dependency)
# This is done before `base` so the binary can be reused across stages.
FROM hadolint/hadolint:latest AS hadolint-bin

# ---------- Stage 0: base ----------
FROM python:3.12-slim-bookworm AS base

ARG UID=1000
ARG GID=1000

# Silence pip root-user warnings (we intentionally build as root in Docker)
ENV PIP_ROOT_USER_ACTION=ignore

# System dependencies for GPG, C extensions, and PDF generation (weasyprint)
RUN apt-get update && apt-get install -y --no-install-recommends \
    gnupg \
    zip \
    git \
    gcc \
    libpq-dev \
    shared-mime-info \
    libcairo2 \
    libpango-1.0-0 \
    libpangocairo-1.0-0 \
    libgdk-pixbuf-2.0-0 \
    libffi-dev \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Create user
RUN groupadd -g ${GID} devgroup && \
    useradd -u ${UID} -g devgroup -ms /bin/bash devuser

WORKDIR /app

# [CRITICAL] Copy dependency manifests for pip install in downstream stages
COPY requirements.txt requirements-dev.txt ./

# Install static analysis tools (separated from project requirements)
RUN pip install --no-cache-dir mypy pylint radon bandit

# Import hadolint binary from official image (zero OS dependency)
COPY --from=hadolint-bin /bin/hadolint /usr/local/bin/hadolint

# ---------- Stage 1: runtime app (development) ----------
FROM base AS app

RUN pip install --no-cache-dir -r requirements.txt

# Copy source (dev stage: volumes override at runtime for hot-reload)
COPY . .

USER devuser
EXPOSE 5000
CMD ["flask", "--app", "wsgi", "run", "--host=0.0.0.0", "--port=5000", "--debug"]

# ---------- Stage 2: unittest (Capa A) ----------
FROM base AS unittest-stage

RUN pip install --no-cache-dir -r requirements.txt && \
    pip install --no-cache-dir coverage jinja2 weasyprint

USER devuser
WORKDIR /app

ENTRYPOINT ["/app/scripts/run_staging.sh", "unittest"]

# ---------- Stage 3: pytest (Capa B) ----------
FROM base AS pytest-stage

RUN pip install --no-cache-dir -r requirements.txt && \
    pip install --no-cache-dir pytest pytest-cov jinja2 weasyprint

USER devuser
WORKDIR /app

ENTRYPOINT ["/app/scripts/run_staging.sh", "pytest"]
