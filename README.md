# Mini-servicio Flask + Redis — solución

[![CI](https://github.com/JuanCruz-Ojeda/entrega-prueba-tecnica/actions/workflows/ci.yml/badge.svg)](https://github.com/JuanCruz-Ojeda/entrega-prueba-tecnica/actions/workflows/ci.yml)

Mini-servicio HTTP (Flask) que expone tres endpoints y usa Redis como caché /
contador. Este repo parte de un enunciado que **no levantaba** y lo deja
funcionando, endurecido y documentado.

- `GET /`           → `{"service":"mini-app","status":"ok"}`
- `GET /health`     → `{"status":"healthy"}` (usado por los health checks)
- `GET /cache-test` → incrementa un contador en Redis y lo devuelve

## Origen del proyecto

Este repositorio resuelve una **prueba técnica de DevOps / Cloud Engineer**: se
recibe un mini-servicio que no levanta y hay que dejarlo funcionando, endurecido
y documentado, en 2-3 horas.

El enunciado original, tal como fue recibido y sin modificar, está en
[`enunciado/`](enunciado/). El primer commit del historial (`Estado inicial de
la prueba técnica`) es el código de partida intacto; a partir de ahí cada commit
resuelve un problema puntual, así que `git log` cuenta el razonamiento paso a
paso.

---

## Cómo levantarlo (un solo comando)

Requisitos: Docker + Docker Compose v2.

```bash
docker compose up --build
```

Esto buildea la imagen, levanta Redis y la app, y espera a que Redis esté
sano antes de arrancar la app.

- App: <http://localhost:8080/>
- Health: <http://localhost:8080/health>
- Cache: <http://localhost:8080/cache-test>

Para pararlo:

```bash
docker compose down          # conserva el volumen de Redis
docker compose down -v       # borra también el volumen
```

Probado desde una carpeta limpia (`git clone` → `docker compose up --build`).

### Verificación rápida

Todo en una línea (levanta, prueba, baja):

```bash
docker compose up --build -d && ./scripts/smoke-test.sh && docker compose down -v
```

`scripts/smoke-test.sh` espera a que la app responda, y verifica que `/`,
`/health` y `/cache-test` devuelven 200 y que el contador de Redis incrementa
entre llamadas. Es el mismo script que corre la CI.

---

## Verificación completa (paso a paso)

```bash
# 1. Levantar el stack
docker compose up --build -d

# 2. Endpoints + contador de Redis
./scripts/smoke-test.sh

# 3. La app corre como usuario sin privilegios (no root)
docker compose exec app id
#    -> uid=10001(appuser) gid=10001(appuser)

# 4. Healthchecks de Compose en verde
docker compose ps
#    -> app y redis en estado "Up ... (healthy)"

# 5. Resiliencia: si el proceso principal termina por su cuenta (crash, OOM),
#    "restart: unless-stopped" recrea el contenedor solo.
docker inspect mini-app-app-1 --format 'reinicios={{.RestartCount}}'   # -> 0
docker compose exec app sh -c 'kill -TERM 1'                           # mata el master de gunicorn
sleep 12
docker inspect mini-app-app-1 --format 'reinicios={{.RestartCount}}'   # -> 1
curl -fsS http://localhost:8080/health                                 # -> {"status":"healthy"}

# 6. Bajar todo (y borrar el volumen de Redis)
docker compose down -v
```

### Lo mismo que corre la CI, en local

```bash
# Lint (ruff, con las reglas de ruff.toml)
docker run --rm -v "$PWD:/io" -w /io ghcr.io/astral-sh/ruff:0.16.5 check .

# Build de la imagen
docker build -t mini-app ./app
```

### Desde un clon limpio (como lo hará quien revise)

```bash
git clone https://github.com/JuanCruz-Ojeda/entrega-prueba-tecnica.git
cd entrega-prueba-tecnica
docker compose up --build -d && ./scripts/smoke-test.sh && docker compose down -v
```

---

## Qué cambié y por qué

### El stack no levantaba

| # | Problema | Fix | Por qué |
|---|---|---|---|
| 1 | `docker-compose.yml` mapeaba `8080:8080`, pero la app escucha en `5000` | Mapeo `8080:5000` | Sin esto no había nada escuchando del lado del contenedor en 8080. |
| 2 | Compose nunca le pasaba `REDIS_HOST` a la app → usaba `localhost` → `/cache-test` daba 500 | `environment: REDIS_HOST=${REDIS_HOST:-redis}` | En la red de Compose, Redis se resuelve por el nombre del servicio (`redis`). |
| 3 | Clave `version:` obsoleta | Se quitó | Compose v2 la ignora y avisa; ensucia la salida. |
| 4 | Sin orden de arranque ni chequeos de salud | `depends_on: condition: service_healthy` + `healthcheck` en app y redis + `restart: unless-stopped` | La app no arranca hasta que Redis está realmente listo; si el proceso muere, el contenedor se reinicia solo. |

### Dockerfile (buenas prácticas para producción)

| Antes | Ahora | Por qué |
|---|---|---|
| `FROM python:3.11` (imagen full, ~1 GB) | `python:3.11-slim` (imagen final **134 MB**) | Menos superficie de ataque, pull y deploy más rápidos. |
| `COPY . .` antes de `pip install` | Copiar `requirements.txt` → instalar → después `COPY app.py` | La cache de capas: cambiar el código ya no reinstala dependencias. |
| Corría como `root` | Usuario de sistema sin privilegios (`appuser`) | Reduce el impacto de un compromiso del contenedor. |
| `CMD ["python", "app.py"]` (servidor de desarrollo de Flask) | `gunicorn` (servidor WSGI de producción, 2 workers) | El server de desarrollo no está pensado para producción. |
| Sin `HEALTHCHECK` | `HEALTHCHECK` contra `/health` | Sirve también fuera de Compose (p. ej. como señal en ECS). |
| — | `.dockerignore`, `PYTHONUNBUFFERED`, `PYTHONDONTWRITEBYTECODE` | Contexto de build más chico y logs sin buffer. |

### Aplicación

Cambios mínimos (no era el objetivo reescribir la app):

- Se quitó `import time` (no se usaba).
- Orden de imports según isort (lo pedía el linter).

### CI/CD

`.github/workflows/ci.yml` estaba lleno de TODOs. Ahora tiene dos jobs:

**`build-test`** — corre en cada push y en cada PR:

1. **Lint** con `ruff` (reglas fijadas explícitamente en `ruff.toml`).
2. **Build + smoke test**: levanta el stack con Compose y corre
   `scripts/smoke-test.sh`. Si algo falla, vuelca los logs de Compose.

**`publish`** — solo en push a `main` y solo si `build-test` pasó:

3. Buildea y **publica la imagen en GHCR**
   (`ghcr.io/juancruz-ojeda/entrega-prueba-tecnica`), con los tags
   `latest` y `sha-<commit>`, labels OCI (repo, revisión) y cache de capas
   entre corridas. Usa el `GITHUB_TOKEN` que ya provee Actions (sin secrets)
   y permisos acotados a `packages: write` solo en ese job.

Para desplegar a AWS el camino es análogo (login por OIDC → push a ECR →
`aws ecs update-service`); el detalle está en [`infra/README.md`](infra/README.md).

### Infraestructura

Ver [`infra/README.md`](infra/README.md): arquitectura (ECS Fargate + ALB +
ElastiCache) con justificación de cada decisión y un **runbook de AWS CLI**
paso a paso. No se usó Terraform a propósito (el equipo todavía no lo adoptó);
el documento explica el camino para llevarlo a IaC.

---

## Decisiones que quedaron a mi criterio

| Decisión | Por qué |
|---|---|
| **gunicorn** en vez del server de Flask | Producción real: manejo de múltiples requests, robustez ante carga. |
| Imagen **slim** (no `alpine`) | `alpine` con Python trae dolores de cabeza con wheels compiladas; `slim` es el punto medio. |
| Usuario **no-root** en la imagen | Principio de menor privilegio. |
| **Healthchecks** en Compose y en la imagen | Que `depends_on` espere a Redis *listo*, no solo *creado*; señal de vida clara para cualquier orquestador. |
| Redis con **volumen nombrado + appendonly** | El contador sobrevive a reinicios locales. En AWS esto lo reemplaza ElastiCache. |
| **ECS Fargate** (no EC2 ni EKS) | Mínima operación para un servicio chico. |
| **ElastiCache** (no Redis en contenedor) en AWS | Con 2+ réplicas de la app, el estado tiene que estar afuera y gestionado. |
| **Secrets Manager** para credenciales | Nunca secretos en la imagen ni en `environment` en texto plano. |
| Logs a **stdout/stderr** → CloudWatch | La app no gestiona archivos de log; el entorno los recolecta. |
| `ruff.toml` con reglas explícitas | CI y local dan el mismo resultado, sin depender de defaults de la herramienta. |

---

## Qué haría con más tiempo

- **Pin de dependencias por hash** (`pip-tools` / `--require-hashes`) para builds
  100% reproducibles.
- **Tests unitarios** de los endpoints con `pytest` + `fakeredis` (hoy solo hay
  smoke test de integración).
- **Multi-stage build** si las dependencias crecieran y necesitaran toolchain.
- **IaC real** (Terraform/CDK) en lugar del runbook, con state remoto y deploy
  desde CI vía OIDC.
- **HTTPS** en el ALB (ACM) con redirect 80→443.
- **Auto scaling** del servicio ECS configurado (target-tracking).
- **Scanning** en CI: Trivy sobre la imagen (umbral CRITICAL/HIGH) y
  checkov/tfsec si se agrega Terraform. Ver [`enunciado/TRACKS_OPCIONALES.md`](enunciado/TRACKS_OPCIONALES.md).
- **Track A (Kubernetes/Helm)**: chart propio para correr lo mismo en un cluster.

---

## Estructura del repo

```
.
├── app/
│   ├── app.py             # la aplicación Flask (sin cambios de lógica)
│   ├── requirements.txt   # flask, redis, gunicorn
│   ├── Dockerfile         # imagen de producción
│   └── .dockerignore
├── scripts/
│   └── smoke-test.sh      # verificación de endpoints (CI + local)
├── infra/
│   └── README.md          # arquitectura AWS + runbook
├── enunciado/             # el enunciado original, sin modificar
│   ├── README.md          # consigna
│   ├── infra.md           # consigna de infraestructura
│   └── TRACKS_OPCIONALES.md
├── .github/workflows/
│   └── ci.yml             # lint + build + smoke test
├── docker-compose.yml     # levanta todo con un comando
├── ruff.toml              # config del linter
├── .env.example
└── README.md              # este archivo
```
