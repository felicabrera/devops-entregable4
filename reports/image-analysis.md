# Analisis de las imagenes Docker

Fecha: 2026-11-11. Imagenes construidas localmente en macOS (arm64) con `scripts/init.sh`
(`notes-backend:dev` y `notes-frontend:dev`). Herramientas: `dive` 0.13 (modo CI, salida JSON en
`reports/image-analysis/*-dive.json`), `docker history` (`*-history.txt`) y `docker image inspect`.

SlimToolkit (`slim xray` 1.40.11 y `mint xray` 1.41.8, tanto el binario de macOS como la imagen
`mintoolkit/mint`) no pudo leer las imagenes: Docker Desktop 29 usa el almacen de imagenes de
containerd y la herramienta falla al exportar las capas (`client version 1.33 is too old` con el
binario y `unexpected EOF / invalid tar header` con la imagen). Por eso el analisis de capas se hizo
con dive, que es la alternativa indicada para Windows pero funciona igual en macOS. El script
`scripts/image-analysis.sh` deja ambos intentos registrados.

## Resumen

| Imagen | Base | Tamano (docker inspect) | Tamano de capas (dive) | Capas | Eficiencia (dive) | Bytes duplicados | Usuario |
|---|---|---|---|---|---|---|---|
| `notes-backend` | `python:3.13.18-slim-bookworm` | 259.2 MB (base sola: 206.1 MB) | 184.5 MB | 8 (6 con contenido) | 98.4 % | 4.8 MB | `10001:10001` |
| `notes-frontend` | `nginxinc/nginx-unprivileged:1.31.7-alpine` | 101.1 MB (base sola: 91.3 MB) | 66.3 MB | 12 (4 con contenido) | 82.2 % | 21.6 MB | `101` |

`docker inspect` reporta el tamano descomprimido en disco con el almacen de containerd; dive suma el
tamano de las capas del manifiesto. En ambas imagenes la base aporta mas del 75 % del total.

## Backend (`notes-backend`)

Capas con contenido (dive):

| # | Tamano | Origen |
|---|---|---|
| 0 | 97.2 MB | Debian bookworm (base) |
| 1 | 8.5 MB | `ca-certificates`, `netbase`, `tzdata` (base) |
| 2 | 40.1 MB | Python 3.13 compilado (base) |
| 4 | 4.1 MB | `apt-get upgrade`, usuario `app`, `/data` (nuestro Dockerfile) |
| 6 | 34.6 MB | `COPY /opt/venv` desde la etapa `builder` (dependencias) |
| 7 | 4.6 kB | `main.py` |

Que aporta el multi-stage: la etapa `builder` instala las dependencias con pip dentro de un
virtualenv y la etapa `runtime` solo copia `/opt/venv`. En la imagen final no quedan `pip`,
`setuptools`, `wheel` ni la cache de pip (`pip uninstall` + sin `~/.cache`), lo que ademas elimina
las dependencias vendorizadas de pip que Trivy marcaba en entregas anteriores. El tamano paso de
271 MB (entregable 3, una sola etapa) a 259 MB con la misma base y mas dependencias.

Archivos duplicados entre capas (4.8 MB): `/var/cache/debconf/templates.dat`, `/var/lib/dpkg/status`
y logs de apt/dpkg reescritos por `apt-get upgrade`. Son el costo de aplicar parches en una capa
propia encima de la base.

## Frontend (`notes-frontend`)

| # | Tamano | Origen |
|---|---|---|
| 0 | 8.7 MB | Alpine minirootfs (base) |
| 1 | 10.5 MB | usuario `nginx` y paquetes base (base) |
| 8 | 41.5 MB | nginx y modulos (base) |
| 9 | 5.6 MB | `apk upgrade` y limpieza (nuestro Dockerfile) |
| 10, 11 | 8.4 kB | `nginx.conf` y el sitio estatico precomprimido |

El sitio pesa menos de 10 kB; la etapa `builder` (Alpine + gzip) solo valida y precomprime los
archivos para `gzip_static`, de modo que la imagen final no lleva gzip ni herramientas de build.
Los 21.6 MB "ineficientes" que reporta dive son `libcrypto`, `libssl`, `libcurl` y `ld-musl`
duplicados: `apk upgrade` reemplaza esas librerias en una capa nueva mientras la version anterior
sigue en la capa de la base.

## Observaciones y optimizaciones posibles

1. **Parches de la base en una capa propia.** `apt-get upgrade` / `apk upgrade` agregan 4.1 MB y
   5.6 MB y duplican archivos. Cuando la imagen base ya esta al dia (el `python:3.13.18` del
   2026-11-11 no tenia paquetes pendientes) la capa queda casi vacia; cuando no lo esta, es la unica
   forma de cerrar CVEs sin esperar una nueva base. Alternativa: reconstruir con `--no-cache` y fijar
   la base por digest cada vez que el escaneo semanal encuentre parches.
2. **Base Debian vs. distroless.** El 75 % del backend es Debian + Python. Una base
   `gcr.io/distroless/python3` o `python:3.13-alpine` bajaria la imagen a 60 a 90 MB, a costa de
   compilar `uvloop`/`httptools` (Alpine, musl) o de perder la shell y `find`/`cat` que se usan en
   la demostracion de Falco. Se dejo Debian slim por compatibilidad de wheels y para poder
   reproducir el evento de Falco.
3. **Extras de uvicorn.** `uvicorn[standard]` trae `uvloop`, `httptools`, `websockets`, `watchfiles`
   y `python-dotenv` (unos 12 MB del venv). Para una API sin websockets ni recarga en caliente se
   podria instalar `uvicorn` sin extras y perder solo el event loop acelerado.
4. **Una capa menos en el frontend.** `nginx-unprivileged` ya borra `default.conf` en su
   entrypoint; se podria evitar el `RUN` propio si no se aplicaran parches, dejando solo los `COPY`.
5. **Lo que ya esta bien.** Etiquetas fijas (sin `latest`), usuario no root en ambas imagenes,
   `.dockerignore` que excluye tests y entornos virtuales, `HEALTHCHECK`, `readOnlyRootFilesystem`
   soportado (los unicos directorios escribibles se montan como `emptyDir`), y `main.py` en la
   ultima capa para aprovechar la cache de build cuando solo cambia el codigo.
