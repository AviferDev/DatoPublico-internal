#!/usr/bin/env bash
set -euo pipefail

HARNESS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$HARNESS_DIR/.." && pwd)"

echo "Harness (privado):      $HARNESS_DIR"
echo "Repositorio de producto: $PROJECT_ROOT"
echo "Estado del harness:     pre-bootstrap"
echo ""
echo "La aplicación aún no está inicializada: no existen módulos Gradle ni build."
echo "Comandos previstos tras el bootstrap técnico:"
echo "  - Compilar/verificar:  (cd \"$PROJECT_ROOT\" && ./gradlew build)"
echo "  - Tests:               (cd \"$PROJECT_ROOT\" && ./gradlew test)"
echo "  - Backend en local:    (cd \"$PROJECT_ROOT\" && ./gradlew :backend:run)"
echo "  - Base de datos:       (cd \"$PROJECT_ROOT\" && docker compose up -d)"
echo ""
echo "Siguiente paso: elegir la primera feature lista de feature_list.json y"
echo "realizar el bootstrap técnico. Este script devuelve 0 a propósito en la"
echo "fase pre-bootstrap."
