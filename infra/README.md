# Infraestructura — Despliegue en AWS

Este documento describe cómo desplegaría la mini-app en AWS de forma **mínima
pero razonable para producción** (no altamente disponible ni multi-región, pero
sí resiliente a la caída de un contenedor o de una AZ).

No se usa una herramienta de IaC (Terraform/CDK) porque hoy el equipo todavía no
la adoptó; en su lugar va un **runbook con AWS CLI**. La sección final explica el
camino natural para llevarlo a IaC.

---

## 1. Arquitectura

```
                    Internet
                       │
                       ▼
             ┌───────────────────┐
             │  ALB (público)    │   :80  (→ :443 + ACM en prod real)
             │  2 subredes públ. │   health check: GET /health
             └─────────┬─────────┘
                       │  (solo el SG del ALB puede hablarle a las tasks)
                       ▼
        ┌──────────────────────────────┐
        │  ECS Service (Fargate)       │   desiredCount = 2
        │  2 tasks en 2 AZs            │   subredes privadas
        │  contenedor: mini-app:5000   │   logs → CloudWatch Logs
        └───────────────┬──────────────┘
                        │  (solo el SG de las tasks puede hablarle a Redis)
                        ▼
        ┌──────────────────────────────┐
        │  ElastiCache for Redis       │   subredes privadas
        │  1 primario (+1 réplica opc.)│   sin acceso desde Internet
        └──────────────────────────────┘

  ECR  ──(pull de imagen)──►  ECS
  Secrets Manager / SSM  ──(inyección de config/secrets)──►  task definition
```

### Componentes y por qué

| Componente | Elección | Motivo |
|---|---|---|
| Cómputo | **ECS Fargate** | No hay que administrar EC2 (parches, AMIs, capacity). Se paga por task. Escala horizontal trivial. Para **un** servicio chico, EKS es demasiada operación (control plane, upgrades, add-ons) y EC2 directo obliga a mantener el host. |
| Entrada de tráfico | **Application Load Balancer** | Termina TLS, hace health checks activos, reparte entre las tasks y las distintas AZs. Es el punto de integración con el scheduler de ECS (registro/desregistro automático de targets). |
| Registro de imágenes | **ECR** | Privado, integrado con IAM y con el pull de ECS. La CI publica ahí (tag por SHA). |
| Estado / caché | **ElastiCache for Redis** | Redis es estado compartido: no puede vivir dentro del contenedor de la app si hay 2+ réplicas. Como servicio gestionado, AWS se encarga de patching, backups, failover y monitoreo. |
| Config no sensible | Variables en la **task definition** (o **SSM Parameter Store**) | `REDIS_HOST`, `REDIS_PORT`: no son secretos, pero tampoco se hardcodean en la imagen. |
| Secrets | **AWS Secrets Manager** | Si se habilita Redis AUTH (o aparece cualquier credencial), se inyecta vía el bloque `secrets` de la task definition. Nunca en `environment` en texto plano ni en la imagen. |
| Logs | **CloudWatch Logs** (driver `awslogs`) | Centralizado, retención configurable, base para métricas y alarmas. La app ya escribe a stdout/stderr sin buffer (`PYTHONUNBUFFERED`, logs de acceso de gunicorn a stdout). |
| Red | **VPC con 2 AZs**: ALB en subredes públicas, tasks y Redis en subredes privadas, **NAT Gateway** para la salida (pull de ECR, envío de logs) | Las tasks no son alcanzables directamente desde Internet; solo el ALB. Alternativa más barata: tasks en subredes públicas con `assignPublicIp=ENABLED` y sin NAT — se ahorra el costo del NAT pero se expone la IP de la task (mitigable con SGs, pero menos limpio). |

### Seguridad de red — Security Groups encadenados

- **`alb-sg`**: inbound `80` (y `443`) desde `0.0.0.0/0`.
- **`app-sg`** (tasks ECS): inbound `5000` **solo desde `alb-sg`**.
- **`redis-sg`** (ElastiCache): inbound `6379` **solo desde `app-sg`**.

Cada capa solo acepta tráfico de la capa inmediatamente anterior.

### Qué pasa si el contenedor se cae

1. El **health check del ALB** (`GET /health`) empieza a fallar para esa task.
2. El ALB la marca `unhealthy` y deja de enviarle tráfico.
3. El **scheduler de ECS** detecta que la task no está `RUNNING`/healthy, la
   da de baja del target group y **lanza un reemplazo** para volver a
   `desiredCount = 2`.
4. Como hay **2 tasks en 2 AZs**, mientras una se recrea la otra sigue
   sirviendo: no hay downtime.
5. En un deploy malo (imagen que no arranca o no pasa health check), el
   **deployment circuit breaker** de ECS aborta el despliegue y hace
   **rollback automático** a la revisión anterior de la task definition.

El mismo comportamiento aplica si se cae una AZ entera: ECS reprograma las tasks
en la AZ sana.

### Observabilidad

- **Logs**: grupo en CloudWatch Logs por servicio (`/ecs/mini-app`), retención p. ej. 30 días.
- **Métricas**: CPU/Memoria de ECS, `HTTPCode_Target_5XX_Count`,
  `TargetResponseTime`, `HealthyHostCount`/`UnHealthyHostCount` del ALB.
- **Alarmas** (CloudWatch → SNS): `UnHealthyHostCount > 0` sostenido,
  `5XX` por encima de un umbral, CPU alta sostenida.
- Opcional: **Container Insights** para vistas agregadas del cluster.

### Escalado

`Application Auto Scaling` sobre el ECS Service, target-tracking por
`ALBRequestCountPerTarget` (o CPU). Se define un mínimo (2) y un máximo
(p. ej. 6). La app es stateless y el estado vive en Redis, así que escalar
horizontalmente es seguro. Fuera del alcance de la base, pero el diseño ya lo
permite sin cambios.

---

## 2. Runbook (AWS CLI)

Placeholders entre `<...>`. Se asume una VPC con 2 subredes públicas y 2
privadas ya existentes (o creadas aparte).

### 2.1. Variables

```bash
export AWS_REGION=us-east-1
export ACCOUNT_ID=<account-id>
export VPC_ID=<vpc-id>
export SUBNETS_PUBLICAS=<subnet-pub-a>,<subnet-pub-b>
export SUBNETS_PRIVADAS=<subnet-priv-a>,<subnet-priv-b>
export IMAGE_TAG=<git-sha>
export ECR_REPO=$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/mini-app
```

### 2.2. ECR + push de la imagen

```bash
aws ecr create-repository --repository-name mini-app \
  --image-scanning-configuration scanOnPush=true

aws ecr get-login-password --region $AWS_REGION \
  | docker login --username AWS --password-stdin $ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com

docker build -t $ECR_REPO:$IMAGE_TAG ./app
docker push $ECR_REPO:$IMAGE_TAG
```

### 2.3. Security Groups

```bash
ALB_SG=$(aws ec2 create-security-group --group-name mini-app-alb-sg \
  --description "ALB mini-app" --vpc-id $VPC_ID --query GroupId --output text)
APP_SG=$(aws ec2 create-security-group --group-name mini-app-app-sg \
  --description "Tasks mini-app" --vpc-id $VPC_ID --query GroupId --output text)
REDIS_SG=$(aws ec2 create-security-group --group-name mini-app-redis-sg \
  --description "ElastiCache mini-app" --vpc-id $VPC_ID --query GroupId --output text)

# ALB: 80 desde Internet
aws ec2 authorize-security-group-ingress --group-id $ALB_SG \
  --protocol tcp --port 80 --cidr 0.0.0.0/0

# App: 5000 solo desde el ALB
aws ec2 authorize-security-group-ingress --group-id $APP_SG \
  --protocol tcp --port 5000 --source-group $ALB_SG

# Redis: 6379 solo desde las tasks
aws ec2 authorize-security-group-ingress --group-id $REDIS_SG \
  --protocol tcp --port 6379 --source-group $APP_SG
```

### 2.4. CloudWatch Logs

```bash
aws logs create-log-group --log-group-name /ecs/mini-app
aws logs put-retention-policy --log-group-name /ecs/mini-app --retention-in-days 30
```

### 2.5. ElastiCache for Redis

```bash
aws elasticache create-cache-subnet-group \
  --cache-subnet-group-name mini-app-redis-subnets \
  --cache-subnet-group-description "Subredes privadas mini-app" \
  --subnet-ids $(echo $SUBNETS_PRIVADAS | tr ',' ' ')

aws elasticache create-replication-group \
  --replication-group-id mini-app-redis \
  --replication-group-description "Redis mini-app" \
  --engine redis --cache-node-type cache.t4g.micro \
  --num-node-groups 1 --replicas-per-node-group 1 \
  --cache-subnet-group-name mini-app-redis-subnets \
  --security-group-ids $REDIS_SG \
  --transit-encryption-enabled --at-rest-encryption-enabled

# Anotar el endpoint primario:
aws elasticache describe-replication-groups --replication-group-id mini-app-redis \
  --query 'ReplicationGroups[0].NodeGroups[0].PrimaryEndpoint.Address' --output text
export REDIS_HOST=<endpoint-anotado>
```

### 2.6. Roles IAM

```bash
# Execution role: ECS lo usa para pull de ECR, escribir logs y leer secrets.
aws iam create-role --role-name mini-app-exec \
  --assume-role-policy-document file://trust-ecs-tasks.json
aws iam attach-role-policy --role-name mini-app-exec \
  --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy
# (+ política inline con secretsmanager:GetSecretValue sobre el ARN del secret, si se usa)

# Task role: permisos de la app en runtime. La app no llama a ninguna API de AWS,
# así que va un rol vacío (o directamente no se asigna).
aws iam create-role --role-name mini-app-task \
  --assume-role-policy-document file://trust-ecs-tasks.json
```

`trust-ecs-tasks.json`:

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "Service": "ecs-tasks.amazonaws.com" },
    "Action": "sts:AssumeRole"
  }]
}
```

### 2.7. Task definition

`taskdef.json`:

```json
{
  "family": "mini-app",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "256",
  "memory": "512",
  "executionRoleArn": "arn:aws:iam::<account-id>:role/mini-app-exec",
  "taskRoleArn": "arn:aws:iam::<account-id>:role/mini-app-task",
  "containerDefinitions": [{
    "name": "mini-app",
    "image": "<account-id>.dkr.ecr.<region>.amazonaws.com/mini-app:<git-sha>",
    "essential": true,
    "portMappings": [{ "containerPort": 5000, "protocol": "tcp" }],
    "environment": [
      { "name": "REDIS_HOST", "value": "<endpoint-de-elasticache>" },
      { "name": "REDIS_PORT", "value": "6379" }
    ],
    "secrets": [
      { "name": "REDIS_AUTH_TOKEN", "valueFrom": "arn:aws:secretsmanager:<region>:<account-id>:secret:mini-app/redis-auth" }
    ],
    "logConfiguration": {
      "logDriver": "awslogs",
      "options": {
        "awslogs-group": "/ecs/mini-app",
        "awslogs-region": "<region>",
        "awslogs-stream-prefix": "app"
      }
    }
  }]
}
```

> Nota: el bloque `secrets` solo aplica si se habilita Redis AUTH. En la app
> actual `REDIS_AUTH_TOKEN` no se usa; se deja como ejemplo del patrón.

```bash
aws ecs register-task-definition --cli-input-json file://taskdef.json
```

### 2.8. Cluster ECS

```bash
aws ecs create-cluster --cluster-name mini-app \
  --settings name=containerInsights,value=enabled
```

### 2.9. ALB + target group + listener

```bash
ALB_ARN=$(aws elbv2 create-load-balancer --name mini-app-alb \
  --type application --scheme internet-facing \
  --subnets $(echo $SUBNETS_PUBLICAS | tr ',' ' ') \
  --security-groups $ALB_SG --query 'LoadBalancers[0].LoadBalancerArn' --output text)

TG_ARN=$(aws elbv2 create-target-group --name mini-app-tg \
  --protocol HTTP --port 5000 --vpc-id $VPC_ID --target-type ip \
  --health-check-path /health --health-check-interval-seconds 15 \
  --healthy-threshold-count 2 --unhealthy-threshold-count 3 \
  --query 'TargetGroups[0].TargetGroupArn' --output text)

aws elbv2 create-listener --load-balancer-arn $ALB_ARN \
  --protocol HTTP --port 80 \
  --default-actions Type=forward,TargetGroupArn=$TG_ARN
# En prod real: listener 443 con --certificates (ACM) y redirect 80→443.
```

### 2.10. ECS Service

```bash
aws ecs create-service \
  --cluster mini-app --service-name mini-app \
  --task-definition mini-app \
  --desired-count 2 --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={subnets=[$SUBNETS_PRIVADAS],securityGroups=[$APP_SG],assignPublicIp=DISABLED}" \
  --load-balancers "targetGroupArn=$TG_ARN,containerName=mini-app,containerPort=5000" \
  --health-check-grace-period-seconds 20 \
  --deployment-configuration "deploymentCircuitBreaker={enable=true,rollback=true},minimumHealthyPercent=100,maximumPercent=200"
```

### 2.11. Verificación

```bash
ALB_DNS=$(aws elbv2 describe-load-balancers --load-balancer-arns $ALB_ARN \
  --query 'LoadBalancers[0].DNSName' --output text)

curl -fsS http://$ALB_DNS/                 # {"service":"mini-app","status":"ok"}
curl -fsS http://$ALB_DNS/health           # {"status":"healthy"}
curl -fsS http://$ALB_DNS/cache-test       # hits=N
curl -fsS http://$ALB_DNS/cache-test       # hits=N+1  → Redis OK
```

### 2.12. Actualizar a una nueva versión

```bash
docker build -t $ECR_REPO:<nuevo-sha> ./app && docker push $ECR_REPO:<nuevo-sha>
# editar taskdef.json con el nuevo tag
aws ecs register-task-definition --cli-input-json file://taskdef.json
aws ecs update-service --cluster mini-app --service mini-app \
  --task-definition mini-app --force-new-deployment
```

ECS hace un **rolling update** (levanta las nuevas, espera que estén healthy en
el ALB, recién ahí baja las viejas). Si las nuevas no pasan el health check, el
circuit breaker revierte solo.

---

## 3. Camino a IaC (siguiente paso)

El runbook es la base para entender qué recursos hacen falta y cómo se
relacionan. El paso siguiente sería:

1. Traducir todo esto a **Terraform** (o CDK), con state remoto en S3 +
   lock en DynamoDB.
2. Encadenar el deploy en CI: tras el push a ECR, un job corre
   `register-task-definition` + `update-service` (o `terraform apply` del
   módulo de la task definition), autenticándose por **OIDC** (sin llaves de
   larga vida).
3. Parametrizar por ambiente (`dev` / `prod`) con workspaces o carpetas.
