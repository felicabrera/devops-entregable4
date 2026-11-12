# syntax=docker/dockerfile:1.7
# Etapa 1: valida y precomprime los archivos estaticos (gzip_static en nginx)
FROM alpine:3.24.4 AS builder
WORKDIR /site
COPY index.html styles.css app.js ./
RUN apk add --no-cache gzip=1.15-r0 \
    && for f in index.html styles.css app.js; do gzip -9 -k "$f"; done \
    && ls -l

# Etapa 2: nginx sin privilegios (uid 101, puerto 8080, pid en /tmp)
FROM nginxinc/nginx-unprivileged:1.31.7-alpine AS runtime
LABEL org.opencontainers.image.title="notes-frontend" \
      org.opencontainers.image.source="https://github.com/felicabrera/devops-entregable4"
USER root
RUN rm -f /etc/nginx/conf.d/default.conf \
    && apk upgrade --no-cache \
    && rm -rf /usr/share/nginx/html/*
COPY --chown=101:101 nginx.conf /etc/nginx/templates/default.conf.template
COPY --from=builder --chown=101:101 /site/ /usr/share/nginx/html/
USER 101
ENV BACKEND_HOST=notes-backend \
    BACKEND_PORT=8000 \
    NGINX_ENVSUBST_OUTPUT_DIR=/etc/nginx/conf.d
EXPOSE 8080
HEALTHCHECK --interval=15s --timeout=3s --retries=3 \
    CMD ["wget", "-q", "-O", "/dev/null", "http://127.0.0.1:8080/healthz"]
