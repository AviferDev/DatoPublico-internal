#!/usr/bin/env bash
set -euo pipefail

HARNESS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$HARNESS_DIR/.." && pwd)"

echo "Harness (privado):       $HARNESS_DIR"
echo "Repositorio de producto: $PROJECT_ROOT"

# Gradle necesita un JDK. No asumimos `java` en PATH: respetamos JAVA_HOME, si no
# usamos `/usr/libexec/java_home` (macOS) y, en último término, el JBR de Android
# Studio. Si no se encuentra ninguno, fallamos con un mensaje claro.
jdk_source=""
if [[ -n "${JAVA_HOME:-}" && -x "${JAVA_HOME}/bin/java" ]]; then
  jdk_source="JAVA_HOME"
elif [[ -x /usr/libexec/java_home ]] && candidate="$(/usr/libexec/java_home 2>/dev/null)" \
     && [[ -x "${candidate}/bin/java" ]]; then
  JAVA_HOME="$candidate"
  jdk_source="/usr/libexec/java_home"
elif [[ -x "/Applications/Android Studio.app/Contents/jbr/Contents/Home/bin/java" ]]; then
  JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
  jdk_source="Android Studio JBR"
fi

if [[ -z "${JAVA_HOME:-}" ]]; then
  echo "ERROR: no se encontró ningún JDK (JAVA_HOME, /usr/libexec/java_home ni el JBR de Android Studio)." >&2
  exit 1
fi
export JAVA_HOME
echo "JDK:                     $JAVA_HOME (${jdk_source})"

if [[ ! -x "$PROJECT_ROOT/gradlew" ]]; then
  echo "ERROR: no existe el wrapper ejecutable '$PROJECT_ROOT/gradlew'; el bootstrap no está completo." >&2
  exit 1
fi

echo ""
echo "Gate no bloqueante: compila y testea los tres módulos. No arranca servidores."
echo "  (cd \"$PROJECT_ROOT\" && ./gradlew build --no-daemon)"
echo ""

cd "$PROJECT_ROOT"
./gradlew build --no-daemon

echo ""
echo "Gate OK: build + tests de :shared, :backend y :composeApp en verde."
echo "Siguiente paso: elegir la primera feature lista de .harness/feature_list.json."
