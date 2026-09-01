# Track opcional B — DevSecOps / scanning en CI

El pipeline (`.github/workflows/ci.yml`, job `security-scan`) corre dos scanners
open-source en cada push y cada PR, en paralelo a `build-test`.

| Scanner | Qué mira | ¿Bloquea? | Por qué ese umbral |
|---|---|---|---|
| **Trivy** | Vulnerabilidades conocidas (CVEs) en la imagen: paquetes del SO + dependencias Python | **Sí**, en `CRITICAL`/`HIGH` **con fix disponible** (`--ignore-unfixed`) | Son amenazas concretas y accionables: hay un parche. Bloquear obliga a actualizarse. Lo que todavía no tiene fix no lo podés resolver vos hoy — bloquear ahí solo dejaría el pipeline rojo para siempre. |
| **Checkov** | Misconfiguración / malas prácticas en `Dockerfile`, chart de Helm y el propio `ci.yml` | **No** (`soft-fail` en `.checkov.yaml`) | Son reglas de buenas prácticas, más subjetivas y con más falsos positivos entre frameworks. Sirven para visibilidad y revisión humana (pestaña **Security → Code scanning**), no para frenar entregas. |

**`publish` depende de `security-scan`**: no se publica a GHCR una imagen que no pasó
el gate de Trivy.

Ambos generan resultados en formato **SARIF** y los suben a *Security → Code
scanning* del repo, en categorías separadas (`trivy` / `checkov`).

> Nota: la subida a *Code scanning* solo funciona en repos **públicos** (o con
> GitHub Advanced Security). En un repo privado el paso está marcado
> `continue-on-error` y el job no falla — el reporte completo igual queda en el
> log de `security-scan`. Al pasar el repo a público, la pestaña Security se
> puebla sola.

---

## Trivy — hallazgos y qué se hizo

Corrida inicial contra la imagen: **3 CRITICAL, 18 HIGH** (166 en total).
De esos, **5 HIGH tenían fix** → con el umbral, el build fallaba.

### Arreglados de verdad (no suprimidos)

| Hallazgo | Causa | Fix |
|---|---|---|
| `CVE-2026-14456` en `openssl` / `libssl3t64` (3 paquetes) | La capa `FROM python:3.11-slim` estaba **cacheada**: no bajaba el manifest nuevo, ya parcheado | `--pull` / `pull: true` en todos los builds (compose y `build-push-action`) |
| `CVE-2026-23949` en `jaraco.context`, `CVE-2026-24049` en `wheel` | `pip`/`setuptools`/`wheel` vienen en la imagen base y **no se usan en runtime** (solo para instalar) | `pip uninstall -y pip setuptools wheel` en la misma capa del `RUN` (`app/Dockerfile`) |

Después de estos dos cambios: **0 hallazgos `CRITICAL`/`HIGH` con fix.** El gate pasa
limpio, sin necesidad de `.trivyignore` (queda vacío).

### Lo que queda (y por qué no bloquea)

- **3 `CRITICAL`**, todas en `perl-base` (`CVE-2026-13221`, `CVE-2026-42496`, `CVE-2026-8376`):
  un paquete que trae Debian por defecto, **sin fix disponible todavía**, y que la
  aplicación (Python puro) **nunca ejecuta**. Sin exposición real.
- **~13 `HIGH`** sin fix, en paquetes del SO base. Se resolverán solas cuando Debian
  publique los parches y se rebuildee (el `--pull` los va a incorporar).

`--ignore-unfixed` es lo que deja pasar exactamente estos: hallazgos sobre los que
hoy no se puede accionar.

---

## Checkov — hallazgos y qué se hizo

Corrida inicial: **`Dockerfile` 53/53 OK**, **GitHub Actions 56/56 OK**,
**Helm 217/271** → **54 fallos**, casi todos sobre `securityContext` de Kubernetes.

### Arreglados de verdad (`helm/mini-app/templates/`)

Se agregó `securityContext` a nivel pod y contenedor en `app`, `redis` y el pod de
`helm test`:

- `runAsNonRoot: true` + `runAsUser`/`runAsGroup` explícitos (la imagen ya corría
  no-root; ahora Kubernetes lo sabe y lo impone).
- `seccompProfile: RuntimeDefault`.
- `allowPrivilegeEscalation: false`, `capabilities: drop: [ALL]`.
- `automountServiceAccountToken: false` (ningún pod llama a la API de k8s).
- `fsGroup` en Redis para que el PVC quede escribible corriendo como no-root.
- Resources requests/limits en el pod de `helm test`.

Resultado: **54 → 25 fallos**. Verificado que el chart sigue desplegando y funcionando
(`helm test` + smoke test OK, Redis escribe en el PVC).

### Lo que queda (decisiones conscientes)

| Check | # | Por qué se acepta |
|---|---|---|
| `CKV_K8S_21` namespace por defecto | 7 | El namespace es una decisión de **instalación** (`helm install -n ...`), no del chart. El chart no lo hardcodea a propósito. |
| `CKV_K8S_15` `imagePullPolicy: Always` | 3 | Intencional: `IfNotPresent` es **necesario** para el flujo local con `minikube image load` (sin registry). |
| `CKV_K8S_43` imagen por digest | 3 | En local se usa el tag mutable `:dev` para iterar. En un deploy real se pinnearía la imagen de GHCR por digest. |
| `CKV_K8S_22` filesystem read-only | 3 | gunicorn (socket de control) y Redis (`--appendonly`) necesitan rutas escribibles; requeriría montar `emptyDir`. Pendiente. |
| `CKV_K8S_35` secrets como archivo | 2 | La app lee `REDIS_PASSWORD` de env; pasarlo como archivo montado necesita cambiar el código. Pendiente. |
| `CKV_K8S_40` UID alto | 2 | El UID lo fija la **imagen de terceros** (`redis`=999, `curl_user`=100). La app sí cumple (uid 10001). |
| `CKV_K8S_8/9` probes en el pod de test | 2 | Es un pod de un solo uso que corre y termina — readiness/liveness no aplican. |
| `CKV2_K8S_6` NetworkPolicy | 3 | Feature más grande; además el CNI por defecto de minikube no la impone. Pendiente. |

Todos están en el SARIF y visibles en *Security → Code scanning*; ninguno está oculto.

---

## Correr los scanners en local

```bash
# Trivy — vulnerabilidades en la imagen
docker build --pull -t mini-app:scan ./app
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
  aquasec/trivy image --severity CRITICAL,HIGH --ignore-unfixed mini-app:scan

# Checkov — misconfiguración IaC
docker run --rm -v "$PWD:/repo" -w /repo bridgecrew/checkov:latest \
  --config-file .checkov.yaml
```

---

## Con más tiempo

- Filesystem read-only en los contenedores (`emptyDir` para las rutas escribibles).
- `NetworkPolicy` restringiendo el tráfico app ↔ redis ↔ test.
- Firma de la imagen (cosign) y publicación de un **SBOM** junto a la imagen.
- Secrets montados como archivo en vez de env var.
