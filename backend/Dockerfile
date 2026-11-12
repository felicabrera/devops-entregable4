# syntax=docker/dockerfile:1.7
# Etapa 1: instala las dependencias en un entorno virtual aislado
FROM python:3.13.18-slim-bookworm AS builder
WORKDIR /build
ENV PIP_NO_CACHE_DIR=1 PIP_DISABLE_PIP_VERSION_CHECK=1
COPY requirements.txt .
RUN python -m venv /opt/venv \
    && /opt/venv/bin/pip install --no-cache-dir -r requirements.txt \
    && find /opt/venv -name '__pycache__' -type d -prune -exec rm -rf {} + \
    && rm -rf /opt/venv/lib/python3.13/site-packages/pip /opt/venv/lib/python3.13/site-packages/pip-* \
              /opt/venv/lib/python3.13/site-packages/setuptools* /opt/venv/lib/python3.13/site-packages/wheel* \
              /opt/venv/lib/python3.13/site-packages/_distutils_hack /opt/venv/bin/pip* /opt/venv/bin/wheel*

# Etapa 2: imagen final sin pip ni herramientas de compilacion
FROM python:3.13.18-slim-bookworm AS runtime
ARG APP_VERSION=dev
LABEL org.opencontainers.image.title="notes-backend" \
      org.opencontainers.image.source="https://github.com/felicabrera/devops-entregable4" \
      org.opencontainers.image.version="${APP_VERSION}"

# Parches del sistema base y limpieza. pip no se usa en runtime: se elimina
RUN apt-get update \
    && apt-get upgrade -y --no-install-recommends \
    && rm -rf /var/lib/apt/lists/* \
    && pip uninstall -y pip setuptools wheel 2>/dev/null || true \
    && rm -rf /root/.cache \
    && groupadd --gid 10001 app \
    && useradd --uid 10001 --gid app --no-create-home --shell /usr/sbin/nologin app \
    && mkdir /data && chown app:app /data

WORKDIR /app
COPY --from=builder /opt/venv /opt/venv
COPY --chown=app:app main.py .

ENV PATH="/opt/venv/bin:$PATH" \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    DATA_DIR=/data \
    APP_VERSION=${APP_VERSION}
VOLUME /data
USER 10001:10001
EXPOSE 8000
HEALTHCHECK --interval=15s --timeout=3s --retries=3 \
    CMD ["python", "-c", "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8000/health', timeout=2).status == 200 else 1)"]
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000", "--no-server-header"]
