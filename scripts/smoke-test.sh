#!/usr/bin/env bash
#
# Smoke test de la mini-app. Verifica que el stack levantado responde bien:
#   - GET /            -> 200
#   - GET /health      -> 200
#   - GET /cache-test  -> 200 y el contador de Redis incrementa entre llamadas
#
# Uso:
#   ./scripts/smoke-test.sh [BASE_URL]
#
# BASE_URL por defecto: http://localhost:8080
# Sirve tanto para CI como para la demo local.

set -euo pipefail

BASE_URL="${1:-http://localhost:8080}"
TIMEOUT_SEGUNDOS="${SMOKE_TIMEOUT:-60}"

rojo()  { printf '\033[31m%s\033[0m\n' "$*"; }
verde() { printf '\033[32m%s\033[0m\n' "$*"; }

# Devuelve el código HTTP de un GET a la ruta indicada.
http_code() {
  curl -s -o /dev/null -w '%{http_code}' "${BASE_URL}$1"
}

# Espera a que /health responda 200 (la app puede tardar en arrancar).
esperar_app() {
  echo "Esperando a que la app responda en ${BASE_URL}/health (hasta ${TIMEOUT_SEGUNDOS}s)..."
  local fin=$(( SECONDS + TIMEOUT_SEGUNDOS ))
  while (( SECONDS < fin )); do
    if [ "$(http_code /health)" = "200" ]; then
      verde "La app está arriba."
      return 0
    fi
    sleep 2
  done
  rojo "Timeout: la app no respondió 200 en ${BASE_URL}/health"
  return 1
}

# Verifica que una ruta devuelve 200.
check_200() {
  local ruta="$1"
  local code
  code="$(http_code "$ruta")"
  if [ "$code" = "200" ]; then
    verde "OK   GET ${ruta} -> 200"
  else
    rojo  "FALLA GET ${ruta} -> ${code} (esperaba 200)"
    return 1
  fi
}

# Verifica que el contador de Redis incrementa entre dos llamadas a /cache-test.
check_redis_incrementa() {
  local r1 r2 h1 h2
  r1="$(curl -fsS "${BASE_URL}/cache-test")"
  r2="$(curl -fsS "${BASE_URL}/cache-test")"
  # La respuesta es JSON tipo {"hits":"5","redis_host":"redis"}
  h1="$(printf '%s' "$r1" | grep -o '"hits":"[0-9]*"' | grep -o '[0-9]*')"
  h2="$(printf '%s' "$r2" | grep -o '"hits":"[0-9]*"' | grep -o '[0-9]*')"
  if [ -n "$h1" ] && [ -n "$h2" ] && [ "$h2" -gt "$h1" ]; then
    verde "OK   /cache-test: el contador de Redis incrementó (${h1} -> ${h2})"
  else
    rojo  "FALLA /cache-test: el contador no incrementó (${h1:-?} -> ${h2:-?})"
    rojo  "      respuesta 1: ${r1}"
    rojo  "      respuesta 2: ${r2}"
    return 1
  fi
}

main() {
  esperar_app
  check_200 /
  check_200 /health
  check_200 /cache-test
  check_redis_incrementa
  echo
  verde "Smoke test OK"
}

main "$@"
