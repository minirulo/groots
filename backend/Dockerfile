FROM python:3.11-slim AS base

ENV PYTHONUNBUFFERED=1
ENV PYTHONPATH=/app
ARG POETRY_VERSION=1.8.5
ARG VERSION=latest
ENV API_VERSION=${VERSION}

WORKDIR /app

RUN set -eux && \
     apt-get update && apt-get install -y --no-install-recommends curl libchromaprint-tools && \
     curl -sSL https://install.python-poetry.org | POETRY_VERSION=${POETRY_VERSION} POETRY_HOME=/opt/poetry python && \
     /opt/poetry/bin/poetry config virtualenvs.create false && \
     /opt/poetry/bin/poetry config virtualenvs.in-project false

COPY src/pyproject.toml src/poetry.lock* ./

# ── dev: all deps including test/lint ──────────────────────────────────────────
FROM base AS backend-dev
RUN /opt/poetry/bin/poetry install --no-root
COPY ./scripts/ /
RUN chmod 777 /start-reload.sh

# ── prod: runtime deps only ────────────────────────────────────────────────────
FROM base AS backend-prod
RUN /opt/poetry/bin/poetry install --no-root --without dev
COPY ./scripts/ /
RUN chmod 777 /start.sh

# ── api (dev) ──────────────────────────────────────────────────────────────────
FROM backend-dev AS api-dev
COPY src/ .
ENTRYPOINT [ "/start-reload.sh" ]

# ── api (prod) ─────────────────────────────────────────────────────────────────
FROM backend-prod AS api-prod
COPY src/ .
ENTRYPOINT [ "/start.sh" ]
