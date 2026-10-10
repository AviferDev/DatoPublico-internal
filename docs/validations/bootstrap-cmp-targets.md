# Validación — bootstrap-cmp-targets (FT00005)

- Fecha: 2026-10-10
- Rol: `validator` (independiente del implementador)
- Feature: `bootstrap-cmp-targets` (FT00005), estado de entrada: `passing`
- Spec: `docs/specs/bootstrap-cmp-targets.md`
- Rama de producto: `feat/ft00005-bootstrap-cmp-targets` (diff sin commitear vs `origin/main`)
- Veredicto: **`accept`**

## Checks reejecutados (evidencia real, no autoevaluación)

| Check | Comando | Resultado |
| --- | --- | --- |
| Gate estándar | `./gradlew build --no-daemon` (JDK 21 JBR) | BUILD SUCCESSFUL, **196 tareas**, `wasmJsBrowserTest SKIPPED` |
| `init.sh` | `env -u JAVA_HOME .harness/init.sh` | **exit 0**, `Gate OK: ...` |
| Escenario 1 (Android) | `:composeApp:assembleDebug` | SUCCESS; `composeApp-debug.apk` = **8.740.700 bytes** |
| Escenario 2 (Wasm) | `:composeApp:wasmJsBrowserDistribution` | SUCCESS; dist con `index.html`, `composeApp.js` (536.323 B) y dos `.wasm` (1.196.150 + 8.293.336 B) |
| Escenario 3 (iOS) | `:composeApp:compileKotlinIosSimulatorArm64` + `linkDebugFrameworkIosSimulatorArm64` **`--rerun-tasks`** | SUCCESS (2 tareas reejecutadas); `ComposeApp.framework` con binario, `Headers`, `Modules`, `Info.plist` |
| Escenario 6 (tests) | `./gradlew test` + XML | 0 fallos: composeApp `SmokeTest 1/0/0` en `jvmTest`, `testDebugUnitTest`, `testReleaseUnitTest`, `iosSimulatorArm64Test`; `:shared` 1+3+7; `:backend` 1+6+2 |
| Flyway fuera del gate | `./gradlew build --dry-run \| grep -i flyway` | vacío (esperado) |
| Lint Android | reporte `:composeApp:lint` | "No issues found." |
| Servido Wasm | `python3 -m http.server` sobre la dist | `/` 200 text/html, `/composeApp.js` 200 text/javascript, `*.wasm` 200 **application/wasm** |

### Escenario 4 (UI única) — verificado por contenido de artefactos
Búsqueda de los literales de `App()` en los artefactos compilados:
- Android: `classes3.dex` del APK contiene `DatoPublico` y `Esqueleto Compose Multiplatform` (UTF-8).
- iOS: binario `ComposeApp.framework/ComposeApp` contiene ambos (UTF-8/UTF-16LE).
- Wasm: `*.wasm` (bloque pequeño) contiene ambos (UTF-16LE).

`App()` está definida una sola vez en `commonMain`; cada plataforma aporta solo su entrypoint. Confirmado.

## Alcance, arquitectura y seguridad

- **Alcance acotado**: diff de 5 ficheros versionados + 7 nuevos; solo wiring de targets, pantalla mínima y entrypoints. Sin pantallas reales, navegación, ViewModels, red, ni `:shared` cableado (grep de `ktor/http/localhost/shared/navigation` en `composeApp` → solo falsos positivos de `xmlns` y `savedInstanceState`). Sin proyecto Xcode ni empaquetado Android/Web.
- **Desviación (a) `settings.gradle.kts`**: `PREFER_SETTINGS` + repos Ivy de Binaryen/Node/Yarn con `content { includeModule(...) }`. **Aceptable y acotada**: es requisito conocido del plugin Kotlin/Wasm (registra repos a nivel de proyecto); la alternativa `FAIL_ON_PROJECT_REPOS` rompe `:kotlinBinaryenSetup`. Documentada en `CONSTRAINTS.md`. No es scope creep.
- **Desviación (b) `wasmJsBrowserTest` desactivado**: **aceptable**; el spec ya marcaba este riesgo y autorizaba acotar la ejecución. El `SmokeTest` corre en `jvmTest`/Android/iOS y el código Wasm se compila y distribuye en el gate. Documentado en `docs/desarrollo-local.md`.
- **Seguridad**: sin hallazgos. Sin secretos en el diff ni en `composeApp/src`; sin superficie de red, auth, input de usuario, datos personales ni servicios externos. Los repos Ivy son hosts oficiales y filtrados por módulo. `local.properties` está ignorado por git y no aparece en el diff.

## Documentación/harness

- `ARCHITECTURE.md`, `CONSTRAINTS.md`, skill `compose-multiplatform-architecture` y `docs/desarrollo-local.md` actualizados y coherentes con el código.
- `AGENTS.md` sin tocar (correcto). `PROGRESS.md` (Session 026) y `feature_list.json` (evidence FT00005) coinciden con los recuentos/rutas reejecutados (196 tareas, bytes de artefactos, 9 tests backend, 11 shared).
- `docs/feature-ids.md`: FT00005 = `passing` (consistente; pendiente de persistir `accept` el orquestador).

## Hallazgos (todos Low, no bloquean)

1. `wasmJsBrowserTest` desactivado globalmente implica que la CI (ubuntu, con Chrome) tampoco lo ejecuta. Es la única tarea de test Wasm; hoy no aporta (no hay tests Wasm reales), pero conviene revisarlo al llegar UI Wasm real (FT00032+).
2. `wasmJsMain/resources/index.html` declara `<div id="root">` que queda sin usar: `main.kt` monta en `document.body` vía `ComposeViewport`. Markup muerto inofensivo; unificar (montar en `#root` o quitar el div).
3. Textos de UI literales en `App.kt` en lugar de recursos: intencional según non-goals del spec (recursos → FT00032+); entra en tensión con la regla durable «El texto de UI vive en recursos», que aplica a la UI real.
4. Aviso de Gradle 8.10.2 «Deprecated Gradle features ... incompatible with Gradle 9.0»: preexistente, no introducido por esta feature.

## No reproducido aquí

- Render visual (canvas) de la pantalla Wasm: no hay navegador de escritorio conectado a esta sesión. Confirmado que la dist se sirve con `Content-Type` correctos y que los literales de `App()` están embebidos en el `.wasm`; queda sin verificar el pintado pixel a pixel.
- Paridad CI en `ubuntu-latest` (sin Xcode): no ejecutada localmente; comportamiento estándar de KMP (targets iOS deshabilitados en hosts no-Apple) y el gate local pasa.
