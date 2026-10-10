#!/usr/bin/env bash
set -euo pipefail

# Gate de arranque y verificación. Por defecto es **SDK-free**: compila y testea
# `:shared` y `:backend` (`-PskipClient` excluye `:composeApp`, que exige el
# Android SDK) y ejecuta el gate de calidad (detekt + CPD). Flags opt-in:
#   --with-client  incluye el cliente Android/Web (`:composeApp`; exige Android SDK)
#   --with-ios     incluye el cliente y enlaza el framework iOS de simulador (exige Xcode)
#   --with-all     activa ambos clientes
# No arranca servidores.
WITH_CLIENT=0
WITH_IOS=0
for arg in "$@"; do
  case "$arg" in
    --with-client) WITH_CLIENT=1 ;;
    --with-ios) WITH_IOS=1 ;;
    --with-all) WITH_CLIENT=1; WITH_IOS=1 ;;
    *) echo "Aviso: argumento desconocido '$arg' (se ignora)" ;;
  esac
done

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

# El cliente (`:composeApp`) aplica `com.android.application`, así que Gradle
# configura el Android SDK aunque la tarea sea iOS. Se resuelve de
# ANDROID_HOME/ANDROID_SDK_ROOT o de las rutas habituales si no está exportado.
if [[ "$WITH_CLIENT" -eq 1 || "$WITH_IOS" -eq 1 ]]; then
  if [[ -z "${ANDROID_HOME:-}" && -z "${ANDROID_SDK_ROOT:-}" ]]; then
    for candidate in "$HOME/Library/Android/sdk" "$HOME/Android/Sdk"; do
      if [[ -d "$candidate" ]]; then
        export ANDROID_HOME="$candidate"
        echo "ANDROID_HOME=$ANDROID_HOME (Android SDK detectado)"
        break
      fi
    done
  fi
  if [[ -z "${ANDROID_HOME:-}" && -z "${ANDROID_SDK_ROOT:-}" ]]; then
    echo "ERROR: no se encontró el Android SDK. Define ANDROID_HOME para compilar el cliente." >&2
    exit 1
  fi
fi

if [[ "$WITH_IOS" -eq 1 ]] && ! xcodebuild -version >/dev/null 2>&1; then
  echo "ERROR: no se encontró Xcode (xcodebuild). Instálalo para compilar el cliente iOS." >&2
  exit 1
fi

cd "$PROJECT_ROOT"

echo ""
if [[ "$WITH_CLIENT" -eq 1 || "$WITH_IOS" -eq 1 ]]; then
  echo "Gate (con cliente): ./gradlew build"
  ./gradlew build --no-daemon
else
  echo "Gate (SDK-free): ./gradlew build -PskipClient"
  ./gradlew build -PskipClient --no-daemon
fi

# Gate de calidad (bloqueante): detekt + CPD (`:cpdCheck`, global). `build` ya lo
# ejecuta vía `check`; se corre explícito para que el gate quede a la vista.
echo ""
echo "Gate de calidad: ./gradlew detekt (+ :cpdCheck)"
if [[ "$WITH_CLIENT" -eq 1 || "$WITH_IOS" -eq 1 ]]; then
  ./gradlew detekt --no-daemon
else
  ./gradlew detekt -PskipClient --no-daemon
fi

if [[ "$WITH_IOS" -eq 1 ]]; then
  echo ""
  echo "Gate iOS: ./gradlew :composeApp:linkDebugFrameworkIosSimulatorArm64"
  ./gradlew :composeApp:linkDebugFrameworkIosSimulatorArm64 --no-daemon
fi

echo ""
echo "Gate OK."
echo "Arranque manual del backend (no lo hace este script):"
echo "  (cd \"$PROJECT_ROOT\" && ./gradlew :backend:run)"
echo "  curl -i http://localhost:8080/health"
