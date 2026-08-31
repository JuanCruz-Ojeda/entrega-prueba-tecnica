# Prueba técnica — DevOps / Cloud Engineer

## Contexto

Te dejamos un mini-servicio (`app/`) con un `docker-compose.yml` que
**no levanta correctamente tal como está**. La idea no es que escribas una
app desde cero, sino que trabajes como trabajarías en el día a día: recibís
algo con problemas y tenés que dejarlo funcionando, bien hecho, y
documentado.

## Qué te pedimos

1. **Hacé que todo levante** con un solo comando (`docker compose up --build`
   o el que definas — ver sección "Entregable"). Explorá por qué no funciona
   ahora mismo.
2. **Revisá el `Dockerfile`** de `app/` y mejorá lo que consideres que no
   sigue buenas prácticas para un ambiente productivo.
3. **Completá el pipeline de CI** en `.github/workflows/ci.yml` (está con
   TODOs). No hace falta que pusheé a un registro real si no tenés uno a
   mano — dejalo documentado.
4. **Infraestructura**: en `infra/README.md` tenés el detalle. En resumen,
   contanos (en código o en un runbook) cómo desplegarías esto en AWS.
5. **Un `README.md`** en la raíz (podés reemplazar este archivo o agregar
   uno nuevo) que explique: cómo levantar todo con un solo comando, qué
   cambiaste y por qué, y qué harías distinto si tuvieras más tiempo.

## Qué queda a tu criterio (a propósito)

No te decimos qué herramienta de IaC usar, ni qué logging/monitoreo
agregar, ni si hace falta escalar horizontalmente. Tomá esas decisiones
vos y explicá el porqué.

## Tracks opcionales

Además de lo anterior, en `TRACKS_OPCIONALES.md` tenés dos desafíos
extra (Kubernetes/Helm y DevSecOps/scanning) — **completamente
opcionales**. Hacé los que se alineen con tu experiencia real; no vamos
a penalizarte por no hacerlos si el resto está sólido.

## Tiempo

Pensalo para no más de 2-3 horas (hasta 4 si encarás algún track
opcional). No hace falta que quede "perfecto" — preferimos ver
prioridades claras (qué resolviste primero y por qué) a que intentes
cubrir todo a medias.

## Entregable

Un repositorio (link a GitHub/GitLab, público o con acceso para
nosotros) o un `.zip` con todo el proyecto, incluyendo tu `README.md`
final. Importante: **quien lo revise tiene que poder levantar tu solución
con un solo comando**, así que asegurate de dejar eso bien claro y
probado (por ejemplo desde una carpeta limpia, clonando de nuevo).

## Defensa

Vas a tener ~20-30 minutos para mostrarnos tu solución corriendo y
explicar tus decisiones. Podés usar cualquier herramienta (documentación,
IA, lo que uses normalmente en tu trabajo) — lo que nos importa es que
puedas explicar y, si hace falta, modificar en vivo cualquier parte de lo
que entregaste.
