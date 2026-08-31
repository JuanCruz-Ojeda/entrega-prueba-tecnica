# Tracks opcionales (a elección del candidato)

La base del ejercicio (ver `README_CANDIDATO.md`) alcanza para evaluar lo
esencial. Estos dos tracks son **opcionales y no obligatorios** — elegí
hacer el/los que se alineen con tu experiencia real. No hacerlos no resta
puntos de la base; hacerlos bien suma puntos extra.

## Track A — Kubernetes / Helm

Si tenés experiencia real con Kubernetes, desplegá `app/` (junto con Redis)
en un cluster local (por ejemplo `kind` o `minikube`) usando un **Helm
chart propio** (no un chart de terceros copiado sin entender qué hace).

Como mínimo:
- Deployment + Service para `app` y para `redis` (o un chart de Redis como
  dependencia, si sabés justificar por qué).
- Manejo de configuración/secrets vía `ConfigMap`/`Secret` (nada de
  variables hardcodeadas en el manifiesto).
- Un `values.yaml` con al menos un valor parametrizable (por ejemplo,
  réplicas o la imagen/tag).
- Que puedas explicar, en la defensa, qué pasa si escalás `app` a 2+
  réplicas con el estado actual (Redis compartido).

## Track B — DevSecOps / scanning en el pipeline

Si tenés experiencia con seguridad en CI/CD, agregá al pipeline
(`.github/workflows/ci.yml`) un paso de escaneo, usando herramientas
open source (no hace falta licencia paga):

- **Trivy** (o similar) para escanear la imagen Docker en busca de
  vulnerabilidades conocidas.
- **tfsec** o **checkov** para escanear el código de `infra/` si hiciste
  Terraform.

No hace falta que el pipeline falle el build por cualquier hallazgo —
mostranos que sabés configurar un umbral razonable (por ejemplo, solo
fallar en CRITICAL/HIGH) y que podés explicar por qué elegiste ese
umbral.