# Requisitos

Qué hace falta tener instalado para correr cada parte del proyecto, y cómo
instalarlo en **WSL2 Debian** (que es donde se desarrolló y probó).

| Nivel | Para qué | Herramientas |
|---|---|---|
| **0 — base** | `docker compose up --build` (el entregable que se califica) | `git`, `curl`, Docker Engine + `docker compose` v2 |
| **1 — Track A** | Desplegar el chart de Helm en un cluster local | + `kubectl`, `minikube`, `helm` v3 |
| **2 — Track B** | Correr Trivy / Checkov en local | nada extra (se corren como contenedores) |

> `gh` (GitHub CLI) **no** hace falta para correr ni defender el proyecto — solo
> se usó para el flujo de Pull Requests.

---

## Nivel 0 — base (obligatorio)

### `git` y `curl`

```bash
sudo apt-get update && sudo apt-get install -y git curl
```

### Docker Engine + Compose v2 + buildx

**Importante:** el paquete `docker.io` de Debian trae una versión vieja (Docker
20.10) **sin `docker compose`** (el subcomando) ni buildx. Con eso el proyecto
**no levanta**. Hay que usar el repo oficial de Docker:

```bash
# instala docker-ce + docker-compose-plugin + docker-buildx-plugin
curl -fsSL https://get.docker.com | sudo sh

# poder usar docker sin sudo
sudo usermod -aG docker "$USER"

# arrancar el daemon
sudo systemctl enable --now docker 2>/dev/null || sudo service docker start
```

Cerrá y reabrí la terminal de WSL para que tome el grupo `docker`.

### Verificar

```bash
docker compose version      # -> Docker Compose version v2.x  (no "command not found")
docker run --rm hello-world # -> "Hello from Docker!"
```

### Correr el proyecto

```bash
git clone https://github.com/JuanCruz-Ojeda/entrega-prueba-tecnica.git
cd entrega-prueba-tecnica
docker compose up --build
# en otra terminal:
./scripts/smoke-test.sh
```

---

## Nivel 1 — Track A (Kubernetes / Helm)

Requiere el Nivel 0 (Docker es el driver de minikube).

```bash
# kubectl
curl -LO "https://dl.k8s.io/release/$(curl -Ls https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -m 0755 kubectl /usr/local/bin/kubectl && rm kubectl

# minikube
curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
sudo install minikube-linux-amd64 /usr/local/bin/minikube && rm minikube-linux-amd64

# helm v3
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

### Verificar

```bash
kubectl version --client
minikube version
helm version
```

### Correr el Track A

```bash
minikube start --driver=docker --cpus=4 --memory=4096
docker build -t mini-app:dev ./app && minikube image load mini-app:dev
helm upgrade --install mini-app ./helm/mini-app
```

Detalle completo (escalado, persistencia, limpieza) en
[`helm/README.md`](helm/README.md).

---

## Nivel 2 — Track B (scanners en local)

**Nada que instalar.** Trivy y Checkov se corren como contenedores:

```bash
# Trivy — vulnerabilidades en la imagen
docker build --pull -t mini-app:scan ./app
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
  aquasec/trivy image --severity CRITICAL,HIGH --ignore-unfixed mini-app:scan

# Checkov — misconfiguración IaC
docker run --rm -v "$PWD:/repo" -w /repo bridgecrew/checkov:latest --config-file .checkov.yaml
```

Umbrales y hallazgos en [`security/README.md`](security/README.md).

---

## Versiones con las que se desarrolló y probó

| Herramienta | Versión |
|---|---|
| Debian (WSL2) | 12 (bookworm) |
| Docker Engine | 29.7.2 |
| Docker Compose | v2 (5.5.0) |
| Buildx | 0.36.1 |
| kubectl | v1.33.1 |
| minikube | v1.36.0 |
| Helm | v3.21.4 |
| git | 2.39.5 |

No son versiones mínimas estrictas: cualquier Docker con `compose` v2 y buildx,
y cualquier `helm` v3 / `kubectl` reciente, deberían funcionar.
