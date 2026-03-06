# ============================================================
# Backend "Dual Core" Dockerfile
# Multi-stage: base → app (dev) → unittest (staging-A) → pytest (staging-B)
# ============================================================

# ---------- Stage 0: base ----------
FROM python:3.12-slim AS base

ARG UID=1000
ARG GID=1000

# System dependencies for GPG and C extensions
RUN apt-get update && apt-get install -y --no-install-recommends \
    gnupg \
    git \
    gcc \
    libpq-dev \
    wkhtmltopdf \
    && rm -rf /var/lib/apt/lists/*

# Non-root user
RUN groupadd -g ${GID} devgroup && \
    useradd -u ${UID} -g devgroup -ms /bin/bash devuser

WORKDIR /app

# Copy only dependency manifests first (layer caching)
COPY requirements.txt requirements-dev.txt ./

# Install static analysis tools on base layer
RUN pip install --no-cache-dir \
    mypy pylint radon bandit

# ---------- Stage 1: runtime app (development) ----------
FROM base AS app

RUN pip install --no-cache-dir -r requirements.txt

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
