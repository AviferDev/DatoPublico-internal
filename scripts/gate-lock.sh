#!/usr/bin/env bash
# Cerrojo compartido para serializar ejecuciones pesadas de Gradle sobre el
# mismo árbol de trabajo. Necesario cuando varias validaciones/implementaciones
# corren en paralelo: Gradle no admite dos builds concurrentes en el mismo
# directorio y falla por *timeout* de bloqueo.
#
# Uso (desde `.harness/`):
#   ./scripts/gate-lock.sh ./init.sh --with-client
#   ./scripts/gate-lock.sh bash -c 'cd .. && ./gradlew :backend:test --rerun-tasks'
#
# El cerrojo se mantiene durante toda la ejecución del comando y se libera al
# terminar (incluidos errores). Si el proceso dueño muere, el cerrojo queda
# obsoleto y se detecta por PID.
#
# Resuelve el JDK igual que `init.sh` (JAVA_HOME → /usr/libexec/java_home → JBR de
# Android Studio), para que los comandos que invocan `gradlew` funcionen aunque el
# shell no traiga JAVA_HOME.
set -euo pipefail

if [[ -z "${JAVA_HOME:-}" || ! -x "${JAVA_HOME}/bin/java" ]]; then
  if [[ -x /usr/libexec/java_home ]] && candidate="$(/usr/libexec/java_home 2>/dev/null)" \
     && [[ -x "${candidate}/bin/java" ]]; then
    export JAVA_HOME="$candidate"
  elif [[ -x "/Applications/Android Studio.app/Contents/jbr/Contents/Home/bin/java" ]]; then
    export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
  fi
fi

LOCK_DIR="${TMPDIR:-/tmp}/datopublico-gate.lock"
WAIT_SECONDS=3600
WAITED=0

release_stale_lock() {
  if [[ -f "$LOCK_DIR/pid" ]]; then
    local owner
    owner="$(cat "$LOCK_DIR/pid" 2>/dev/null || true)"
    if [[ -n "$owner" ]] && ! kill -0 "$owner" 2>/dev/null; then
      echo "gate-lock: cerrojo obsoleto del PID $owner; se libera." >&2
      rm -rf "$LOCK_DIR"
    fi
  fi
}

cleanup() {
  rm -rf "$LOCK_DIR" 2>/dev/null || true
}

while ! mkdir "$LOCK_DIR" 2>/dev/null; do
  release_stale_lock
  if [[ "$WAITED" -ge "$WAIT_SECONDS" ]]; then
    echo "gate-lock: tiempo de espera agotado (${WAIT_SECONDS}s) esperando '$LOCK_DIR'." >&2
    exit 1
  fi
  if [[ "$WAITED" -eq 0 ]]; then
    echo "gate-lock: en espera de otro build en curso ('$LOCK_DIR')..." >&2
  fi
  sleep 5
  WAITED=$((WAITED + 5))
done

printf '%s\n' "$$" > "$LOCK_DIR/pid"
trap cleanup EXIT INT TERM

"$@"
