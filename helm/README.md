# Track opcional A — Kubernetes / Helm

Chart propio (`helm/mini-app/`) para desplegar la app + Redis en un cluster local
(minikube). No usa charts de terceros.

## Qué incluye

| Recurso | Kind | Por qué |
|---|---|---|
| `mini-app` | Deployment | La app es stateless → réplicas intercambiables. `replicaCount` parametrizable. |
| `mini-app` | Service (ClusterIP) | Entrada a la app; balancea entre réplicas. |
| `mini-app-redis` | StatefulSet (1 réplica) | Redis tiene estado → identidad estable + PVC propio (`volumeClaimTemplates`). |
| `mini-app-redis` | Service headless | DNS directo al pod de Redis (sin balanceo). |
| `mini-app` | ConfigMap | `REDIS_HOST`, `REDIS_PORT` (no sensible). |
| `mini-app-redis` | Secret | Password de Redis. Se genera aleatoria y se preserva entre `helm upgrade`. |

Config y secrets **nunca** hardcodeados en los manifiestos: la app los recibe por
`envFrom` (ConfigMap) y `secretKeyRef` (Secret).

## Prerequisitos

- `helm` v3, `kubectl`, `minikube`, `docker`
- Se corre desde la raíz del repo.

## Camino de testeo (de 0 a 0)

Todos los comandos desde la raíz del repo.

### 1. Cluster e imagen

```bash
minikube start --driver=docker --cpus=4 --memory=4096
kubectl get nodes                                   # minikube Ready

docker build -t mini-app:dev ./app                  # build local (la de GHCR es privada)
minikube image load mini-app:dev
minikube image ls | grep mini-app                   # docker.io/library/mini-app:dev
```

### 2. Validar el chart (sin cluster)

```bash
helm lint helm/mini-app
helm template mini-app helm/mini-app | head -60     # revisar el render
```

### 3. Instalar y esperar

```bash
helm upgrade --install mini-app ./helm/mini-app
kubectl rollout status deployment/mini-app --timeout=120s
kubectl rollout status statefulset/mini-app-redis --timeout=120s
kubectl get pod,svc,statefulset,pvc,cm,secret -l app.kubernetes.io/instance=mini-app
```

Esperado: 2 pods `Running`, 2 Services (uno `None` = headless), StatefulSet `1/1`,
PVC `Bound`, 1 ConfigMap, 1 Secret.

### 4. Probar la app

```bash
helm test mini-app --logs                           # Phase: Succeeded + salida de los curl

kubectl port-forward svc/mini-app 8080:5000 >/dev/null &
./scripts/smoke-test.sh                             # / /health /cache-test + contador sube
kill %1
```

### 5. Demo escalado (respuesta del track)

```bash
helm upgrade --install mini-app ./helm/mini-app --set app.replicaCount=3
kubectl rollout status deployment/mini-app --timeout=120s
kubectl get pod -l app.kubernetes.io/component=app  # 3 pods

# Terminal A: tráfico desde dentro del cluster (kube-proxy balancea)
kubectl run tester --rm -it --image=curlimages/curl --restart=Never -- \
  sh -c 'for i in $(seq 1 30); do curl -s http://mini-app:5000/cache-test; echo; done'
#   -> hits crece monotónico: estado consistente

# Terminal B: qué pod atendió cada request
kubectl logs -l app.kubernetes.io/component=app --prefix --tail=60 | grep cache-test
#   -> los 3 nombres de pod aparecen sirviendo

helm upgrade --install mini-app ./helm/mini-app --set app.replicaCount=1   # volver a 1 réplica
```

> `--set app.replicaCount=1` debe pasarse de forma explícita: este Helm conserva
> los valores del release anterior. Alternativa: `--reset-values`, que restablece
> los valores por defecto del chart.

### 6. Demo persistencia

```bash
PW=$(kubectl get secret mini-app-redis -o jsonpath='{.data.redis-password}' | base64 -d)
kubectl exec mini-app-redis-0 -- sh -c "redis-cli -a '$PW' --no-auth-warning get hits"   # N
kubectl delete pod mini-app-redis-0
kubectl rollout status statefulset/mini-app-redis --timeout=120s
kubectl exec mini-app-redis-0 -- sh -c "redis-cli -a '$PW' --no-auth-warning get hits"   # sigue N
```

### 7. Demo rollback (opcional)

```bash
helm history mini-app                               # lista de revisiones
helm rollback mini-app 1                            # volver a la revisión 1
```

### 8. Cerrar todo (volver al estado inicial)

```bash
helm uninstall mini-app
kubectl delete pod,pvc -l app.kubernetes.io/instance=mini-app
kubectl get all,pvc,cm,secret -l app.kubernetes.io/instance=mini-app   # sin recursos
helm list                                                             # vacío

# reset total del cluster (opcional):
minikube delete
```

## Valores parametrizables (`values.yaml`)

| Clave | Default | Para qué |
|---|---|---|
| `app.replicaCount` | `1` | Réplicas de la app (escalado horizontal). |
| `image.repository` / `image.tag` | `mini-app` / `dev` | Imagen a desplegar. Para GHCR: `ghcr.io/juancruz-ojeda/entrega-prueba-tecnica` + `imagePullSecrets`. |
| `image.pullPolicy` | `IfNotPresent` | Usa la imagen ya cargada, no hace pull. |
| `redis.auth.password` | `""` (autogenerada) | Password de Redis. Con valor: fija (útil para `--set` en demos). |
| `redis.persistence.size` | `128Mi` | Tamaño del PVC de Redis. |
| `redis.persistence.storageClass` | `""` (default del cluster) | StorageClass del PVC. |
| `app.resources` / `redis.resources` | requests/limits chicos | Recursos de cada contenedor. |

Ejemplo: `helm upgrade --install mini-app ./helm/mini-app --set app.replicaCount=3`

## La pregunta de la defensa: ¿qué pasa si escalo `app` a 2+ réplicas?

**Es seguro.** La app es stateless y todo el estado vive en Redis. Las N réplicas
usan el mismo Service (`mini-app-redis`), así que el contador `hits` es consistente
porque Redis es la única fuente de verdad. Verificado: con 3 réplicas, 10 requests
seguidos a `/cache-test` por el Service devuelven el contador creciendo monotónico.

**El límite es Redis, no la app:**

- Redis es **1 sola instancia** → punto único de falla. Si el pod cae, las réplicas
  de la app pierden el backend hasta que el StatefulSet lo recrea (~10-15s).
- El **PVC** da durabilidad ante reinicio del pod (verificado: se mata
  `mini-app-redis-0` y el contador sobrevive). **No** protege ante caída de nodo ni
  borrado del PVC.
- Escalar el **StatefulSet de Redis** a 2+ réplicas sería **incorrecto** con este
  chart: cada pod tendría su propio dataset, sin replicación → el contador se
  volvería inconsistente según qué pod atienda.
- Redis HA de verdad = StatefulSet + Redis Sentinel/Cluster, o un servicio
  gestionado. En producción es exactamente lo que propone
  [`../infra/README.md`](../infra/README.md): **ElastiCache for Redis** con réplica.

## Limpieza

```bash
helm uninstall mini-app
# helm uninstall NO borra: (a) el PVC del StatefulSet (protección de datos)
# ni (b) el pod de helm test (política before-hook-creation, para poder ver
# sus logs). Se limpian a mano:
kubectl delete pod,pvc -l app.kubernetes.io/instance=mini-app
```

## Notas

- `docker-compose.yml` corre Redis **sin** password a propósito (dev local simple).
  El soporte de `REDIS_PASSWORD` en `app/app.py` es opcional y retrocompatible: sin
  la variable, la app se conecta sin auth.
- `helm template ./helm/mini-app` renderiza los manifiestos sin cluster (útil para
  revisar). En ese modo la password del Secret se ve distinta en cada render porque
  `lookup` no tiene cluster contra el cual consultar; en `helm install/upgrade` el
  comportamiento es el correcto (se genera una vez y se preserva).
