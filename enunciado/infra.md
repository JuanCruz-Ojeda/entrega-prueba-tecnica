<!--
Contenido original de infra/README.md tal como fue recibido (sin modificar).
La resolución está en infra/README.md en la raíz del repositorio.
-->

# Infraestructura

Esta carpeta está vacía a propósito.

Tu tarea: describir y/o codificar cómo desplegarías esta app en AWS de forma
mínima pero razonable para un ambiente productivo (no hace falta que sea
altamente disponible ni multi-región).

No te decimos qué herramienta usar. Elegí la que mejor conozcas y justificá
la elección en tu README principal:

- Terraform / CloudFormation / Pulumi con código real, o
- Un runbook detallado (paso a paso, con comandos de AWS CLI) si no tenés
  experiencia con una herramienta de IaC — nos interesa más ver que
  entendés qué recursos hacen falta y por qué, que la sintaxis exacta de
  una herramienta puntual.

Como mínimo esperamos que pienses en: cómo se ejecuta el contenedor
(EC2, ECS/Fargate, o lo que prefieras), cómo entra tráfico (load balancer),
cómo se manejan las variables de entorno / secrets, y qué pasaría si el
contenedor se cae.
