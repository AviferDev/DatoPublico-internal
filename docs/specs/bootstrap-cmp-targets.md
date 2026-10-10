# Feature Implementation Spec: Esqueleto Compose Multiplatform (Android, Web, iOS)

## Source Feature

- `id`: bootstrap-cmp-targets
- `ft_id`: FT00005
- `parts`: none (atomic)
- `area`: fundaciones
- `depends_on`: bootstrap-monorepo-gradle (FT00001, `accepted`)
- `status`: planned (a implementar; rama `feat/ft00005-bootstrap-cmp-targets` ya reclamada)
- `source`: `feature_list.json`

## Goal

Convertir `:composeApp` (hoy un módulo KMP con **solo `jvm()`** y un `SmokeTest`)
en el **esqueleto del cliente Compose Multiplatform**: aplicar el plugin de Compose
y `com.android.application`, declarar los targets **Android**, **Web (Wasm)** e
**iOS**, añadir una **pantalla mínima compartida en `commonMain`** y un
**entrypoint por plataforma**. El módulo debe compilar para las tres plataformas
de producto y seguir dejando el gate estándar (`./gradlew build` / `./gradlew
test` / `.harness/init.sh`) en verde, sin depender de la base de datos. Es la base
de `docs/roadmap.md` 0.1-T05 y habilita toda la UI compartida (`ui-feed` FT00032 y
siguientes).

## Non-Goals

- **Pantallas reales** (feed, detalle, búsqueda, chat), navegación, ViewModels,
  tema completo, recursos/idiomas, cliente HTTP y cache → FT00032–FT00037.
- **Ampliar los targets de `:shared`** (Android/iOS/Wasm) ni **cablear
  `:composeApp → :shared`**: `:shared` solo declara `jvm()` y añadir la dependencia
  hoy rompería la resolución de metadata para `androidTarget`/`iosArm64`/`wasmJs`;
  se hará cuando la primera UI necesite DTOs (FT00032).
- **Proyecto Xcode `iosApp/`** (firma, Info.plist, TestFlight, App Store) →
  `dist-ios` (FT00040); aquí solo se genera el **framework/klib** de Kotlin.
- **Empaquetado/firma de Android** (keystore, AAB, Play Store), iconos/splash y
  temas definitivos → `dist-android` (FT00038); **despliegue Web** → `dist-web`
  (FT00039).
- **URL del backend por plataforma** (`BuildConfig`/`Info.plist`/config Wasm) y
  cualquier llamada a red → FT00035/FT00032; **nunca** cablear `http://localhost`
  en `commonMain` (ver `CONSTRAINTS.md`/skill).
- **Tests de UI por plataforma** y tests de screenshot → features de UI.

## Job Story

Cuando desarrollo el cliente multiplataforma, quiero un módulo `:composeApp` que
compile Android/Wasm/iOS y renderice una pantalla mínima desde una única fuente en
`commonMain`, para poder construir la UI compartida de las tres plataformas sin
volver a tocar el wiring de build.

## Users And Permissions

- Desarrollador (único actor): ejecuta los comandos Gradle del módulo y verifica
  APK, distribución Wasm y framework iOS. Sin cuentas, sin datos personales, sin
  red en esta feature.

## Acceptance Scenarios

### Scenario 1: Android compila

Given el SDK de Android disponible (`local.properties` con `sdk.dir` o
`ANDROID_HOME`),
When ejecuto `./gradlew :composeApp:assembleDebug`,
Then la tarea termina en `BUILD SUCCESSFUL` y se genera
`composeApp/build/outputs/apk/debug/composeApp-debug.apk`.

### Scenario 2: Web (Wasm) compila y renderiza la pantalla

Given Node/Yarn gestionados por el plugin y sin servicios externos,
When ejecuto `./gradlew :composeApp:wasmJsBrowserDistribution`,
Then se genera la distribución en
`composeApp/build/dist/wasmJs/productionExecutable/` (`index.html` + `.wasm`), y al
servirla en un navegador se muestra la **pantalla mínima** («DatoPublico»).

### Scenario 3: iOS genera klib y framework

Given un host macOS con Xcode,
When ejecuto `./gradlew :composeApp:compileKotlinIosSimulatorArm64` y
`./gradlew :composeApp:linkDebugFrameworkIosSimulatorArm64`,
Then ambas terminan en `BUILD SUCCESSFUL` y se genera
`composeApp/build/bin/iosSimulatorArm64/debugFramework/ComposeApp.framework`.

### Scenario 4: pantalla mínima compartida

Given el código de UI en `commonMain`,
When compilo cualquiera de los tres targets,
Then la pantalla se define una sola vez (`App()` en `commonMain`) y cada
plataforma solo aporta su entrypoint (`MainActivity`, `main()`, `MainViewController`).

### Scenario 5: gate estándar sigue verde sin Xcode ni base de datos

Given `ubuntu-latest` (con SDK de Android, **sin** Xcode ni PostgreSQL),
When la CI ejecuta `./gradlew build --no-daemon`,
Then termina en verde: Android y Wasm se construyen y los targets iOS se
**ignoran** en hosts no-Apple (el gate no requiere Xcode).

### Scenario 6: tests existentes intactos

Given el `SmokeTest` de `commonTest`,
When ejecuto `./gradlew test`,
Then la task raíz agrega `:shared:jvmTest`, `:backend:test` y `:composeApp:jvmTest`
y todos pasan.

## Repository Research

### Files Inspected

- `.harness/feature_list.json` (FT00005), `PROGRESS.md`, `docs/feature-ids.md` —
  FT00001–FT00004 `accepted`; FT00005 es la siguiente feature lista.
- `.harness/ARCHITECTURE.md` (módulos y fronteras; `:composeApp` = cliente CMP),
  `CONSTRAINTS.md` (gate sin servicios externos; convención de nombres),
  `DESIGN.md` (dirección visual y tokens), `docs/technical-discovery.md`
  (Compose Multiplatform Android/iOS/Wasm), `docs/roadmap.md` §0.1.0 (0.1-T05) y
  §0.6.0.
- Skill `compose-multiplatform-architecture` — topología de build decidida
  (`androidTarget()`, `iosArm64()`+`iosSimulatorArm64()` con `binaries.framework`,
  `wasmJs { browser(); binaries.executable() }`), regla de UI compartida en
  `commonMain` y arquitectura objetivo.
- Producto (`..`): `composeApp/build.gradle.kts` (solo `jvm()` + `SmokeTest`),
  `shared/build.gradle.kts` (solo `jvm()`), `settings.gradle.kts`
  (`pluginManagement` con `google()` filtrado + Plugin Portal; `google()` en
  repos), `build.gradle.kts` raíz (plugins `apply false`: compose-multiplatform,
  compose-compiler, android-application; task `test` que agrega
  `:composeApp:jvmTest`), `gradle/libs.versions.toml` (AGP `8.7.3`, Compose MP
  `1.7.3`, Kotlin `2.1.20`; `androidMinSdk=26`/`targetSdk=35`/`compileSdk=35`;
  alias compose/AGP predeclarados y **sin usar**), `gradle.properties`,
  `.github/workflows/ci.yml` (ubuntu, temurin 21, `./gradlew build --no-daemon`),
  `.gitignore` (`local.properties` y `**/build/` ignorados), `.harness/init.sh`.
- `composeApp/src/commonTest/.../SmokeTest.kt` (paquete
  `es.aviferdev.datopublico.app`), `composeApp/src` no tiene `commonMain` todavía.

### Existing Patterns To Follow

- Version catalog + Kotlin DSL; namespace `es.aviferdev.datopublico` (la app usa
  `es.aviferdev.datopublico.app`, coherente con `SmokeTest`).
- Plugins predeclarados en la raíz con `apply false`: solo hay que aplicarlos en
  `:composeApp`. AGP y Compose MP están ya en el catálogo con versiones fijadas.
- Comentarios de `:composeApp`/`:shared` anticipan esta feature («los targets
  Android/iOS/Wasm llegan con FT00005»).
- `settings.gradle.kts` ya expone `google()` para AGP y `pluginManagement` con el
  filtro `com\.android.*`; **no** hay que tocarlo.
- Gate estándar: `./gradlew build` / `./gradlew test` / `.harness/init.sh` (no
  arranca servidores); la CI corre sin PostgreSQL.

### Current Gaps

- `:composeApp` no aplica Compose ni AGP; no tiene `commonMain`, ni
  `AndroidManifest.xml`, ni entrypoints; solo `jvm()`.
- El catálogo no tiene `androidx.activity:activity-compose` ni (si hiciera falta)
  `kotlinx-browser`; tampoco dependencias Compose (se obtienen de los accesores
  del plugin `compose.*`, no del catálogo).
- `gradle.properties` no declara `android.useAndroidX=true` (AGP lo exige al usar
  androidx); no existe `local.properties` (ignorado por git).

## Technical Approach

1. **Plugins de `:composeApp`** (`composeApp/build.gradle.kts`): aplicar
   `alias(libs.plugins.kotlin.multiplatform)`,
   `alias(libs.plugins.compose.multiplatform)`,
   `alias(libs.plugins.compose.compiler)` y
   `alias(libs.plugins.android.application)`. Los cuatro ya están en la raíz con
   `apply false`.
2. **Targets** (`kotlin { }`):
   - `androidTarget()`.
   - `iosArm64()` e `iosSimulatorArm64()`, cada uno con
     `binaries.framework { baseName = "ComposeApp"; isStatic = true }`.
   - `wasmJs { browser(); binaries.executable() }`.
   - **Conservar `jvm()`** como target de tests/dev: mantiene la task
     `:composeApp:jvmTest` y, con ella, la task raíz `test` y el `SmokeTest` sin
     tocar `build.gradle.kts` de la raíz. Sin app de escritorio distribuible.
   - `jvmToolchain(21)` se mantiene.
3. **Bloque `android { }`** (AGP): `namespace = "es.aviferdev.datopublico"`,
   `compileSdk = libs.versions.androidCompileSdk.get().toInt()` (35),
   `defaultConfig { applicationId = "es.aviferdev.datopublico"; minSdk = 26;
   targetSdk = 35; versionCode = 1; versionName = "0.1.0" }` y
   `compileOptions` a Java 21 si hiciera falta. No fijar `signingConfig` (el APK
   de debug va sin firmar config).
4. **Dependencias por source set**:
   - `commonMain`: `compose.runtime`, `compose.foundation`, `compose.material3`,
     `compose.ui` (accesores del plugin Compose) y `compose.components.resources`
     solo si se usan recursos (no necesario).
   - `androidMain`: `libs.androidx.activity.compose` (nuevo alias en el catálogo);
     `implementation(compose.preview)` opcional.
   - `wasmJsMain`: `libs.kotlinx.browser` si `kotlinx.browser.document` no se
     resuelve por transitividad (Compose 1.7 ya lo arrastra normalmente).
   - `commonTest`: mantener `kotlin("test")` (`SmokeTest`).
5. **Pantalla mínima compartida** (`commonMain`, paquete
   `es.aviferdev.datopublico.app`): `App.kt` con
   `@Composable fun App()` que aplica `MaterialTheme` y muestra un `Surface` con
   un `Column`/`Text` («DatoPublico» + subtítulo «Esqueleto Compose
   Multiplatform»), usando el color `primary` de `DESIGN.md` como base. Sin red,
   sin estado, sin recursos aún.
6. **Entrypoints por plataforma** (mínimos):
   - Android (`androidMain`): `MainActivity.kt` (`ComponentActivity` +
     `setContent { App() }`) y `androidMain/AndroidManifest.xml` con
     `<application>` y la activity `exported=true` + intent-filter LAUNCHER. Para
     evitar fallos de lint por falta de icono, usar
     `android:icon="@android:drawable/sym_def_app_icon"` (o un icono mínimo).
   - Wasm (`wasmJsMain`): `main.kt` con `fun main()` que monta `App()` en el
     `#root`/`document.body` usando `androidx.compose.ui.window.ComposeViewport`
     (API de Compose 1.7.3); `index.html` con `<div id="root">` si el plugin no lo
     genera.
   - iOS (`iosMain`): `MainViewController.kt` con
     `fun MainViewController() = ComposeUIViewController { App() }`.
7. **Catálogo / propiedades**: añadir `androidxActivityCompose` (p. ej. `1.9.3`)
   y alias `androidx-activity-compose`; `android.useAndroidX=true` en
   `gradle.properties` (y `android.nonTransitiveRClass=true`). Subir
   `org.gradle.jvmargs` a `-Xmx3g` **solo si** hay OOM con Kotlin/Native o Webpack
   (N100 = 8 GB → no subir más de lo necesario).
8. **CI / gate**: no se esperan cambios en `.github/workflows/ci.yml`.
   `ubuntu-latest` **incluye** el SDK de Android (`ANDROID_HOME`) y **no** tiene
   Xcode: los targets iOS de Kotlin/Native están **deshabilitados** en hosts
   no-Apple y `./gradlew build` los ignora; Android y Wasm se construyen con las
   herramientas de la imagen.

**Riesgos clave:**
- **Compatibilidad de versiones** AGP 8.7.3 / Gradle 8.10.2 / Kotlin 2.1.20 /
  Compose MP 1.7.3 / compose-compiler 2.1.20: son predeclaradas y compatibles; si
  aparece un desajuste runtime/compiler, fijar la combinación soportada y
  documentarlo.
- **Tests Wasm en CI**: `./gradlew build` ejecuta `allTests`, que incluye
  `wasmJsBrowserTest` (Karma/Chrome headless). `ubuntu-latest` trae Chrome; si el
  runner no lo encuentra, configurar el testtask de Wasm (p. ej. `nodejs`) o
  acotar la ejecución, y documentarlo en la evidencia.
- **SDK de Android en local**: sin `local.properties` (gitignored) ni
  `ANDROID_HOME`, AGP no encuentra el SDK; exportarlo o crear `local.properties`
  con `sdk.dir` para la verificación local.
- **iOS solo en macOS**: el framework solo se enlaza en host Apple; en Linux se
  verifica que el gate no intenta tareas iOS (se ignoran). El klib de iOS debe
  compilar en macOS.
- **No añadir `:shared` como dependencia** en esta feature (los targets de
  `:shared` no coinciden todavía) — de lo contrario falla la resolución de
  metadata.
- **API Wasm**: la firma exacta de `ComposeViewport`/`kotlinx.browser.document`
  depende de Compose 1.7.3; contrastar con la plantilla oficial.

## Expected File Changes

Rutas en el repo de producto (`..`):

- `composeApp/build.gradle.kts` — modify; plugins Compose/AGP, targets
  Android/iOS/Wasm (+ `jvm()`), bloque `android { }` y dependencias por source set.
- `gradle/libs.versions.toml` — modify; versión `androidxActivityCompose` y alias
  `androidx-activity-compose` (y `kotlinx-browser` solo si se necesita).
- `gradle.properties` — modify; `android.useAndroidX=true`
  (+ `nonTransitiveRClass`); `jvmargs` solo si hay OOM.
- `composeApp/src/commonMain/kotlin/es/aviferdev/datopublico/app/App.kt` — create;
  pantalla mínima compartida.
- `composeApp/src/androidMain/AndroidManifest.xml` — create.
- `composeApp/src/androidMain/kotlin/es/aviferdev/datopublico/app/MainActivity.kt`
  — create.
- `composeApp/src/wasmJsMain/kotlin/es/aviferdev/datopublico/app/main.kt` — create.
- `composeApp/src/wasmJsMain/resources/index.html` — create (si el plugin no lo
  genera); contenedor de la app Wasm.
- `composeApp/src/iosMain/kotlin/es/aviferdev/datopublico/app/MainViewController.kt`
  — create.
- `composeApp/src/commonTest/.../SmokeTest.kt` — keep as-is.
- `docs/desarrollo-local.md` — update; requisitos (JDK 21, SDK Android, Xcode) y
  comandos de Android/Wasm/iOS.
- `build.gradle.kts` (raíz) — not needed funcionalmente (la task `test` sigue
  apuntando a `:composeApp:jvmTest`); solo actualizar el comentario si se toca.
- `settings.gradle.kts`, `.github/workflows/ci.yml` — **not needed** (google() y
  filtro AGP ya presentes; el runner ya cubre Android/Wasm).

## Visual Design Impact

- UI involved: yes (mínima).
- Design source: `../../DESIGN.md` (tokens: `primary #1A4D8F`, `background
  #F7F9FC`, tipografía sans-serif).
- Screens or states affected: una **pantalla placeholder** (sin estados de
  carga/error/vacío reales). Aplicar solo `MaterialTheme` y el color `primary`; no
  diseñar componentes nuevos.
- New design artifact required: no — las pantallas reales llegan con `ui-feed`
  (FT00032) y siguientes; `DESIGN.md` ya es la fuente de verdad.

## Durable Documentation Impact

- `../../ARCHITECTURE.md`: update — `:composeApp` deja de ser pre-bootstrap: se
  anota que ya compila con Compose MP para Android/iOS/Wasm con UI compartida en
  `commonMain` (más un target `jvm()` solo para tests).
- `../../CONSTRAINTS.md`: update — nuevos MUST: la **UI compartida vive en
  `commonMain`** y cada plataforma aporta **solo su entrypoint**; el gate
  `./gradlew build`/`init.sh` no requiere Xcode (los targets iOS se ignoran en
  hosts no-Apple). (Evitar reglas efímeras de build.)
- `../../AGENTS.md`: not needed — no cambia el flujo ni el camino de arranque.
- Otros: skill `.harness/.agents/skills/compose-multiplatform-architecture/SKILL.md`
  §«Estado actual» — update (`:composeApp` ya existe y compila; `:shared` aún no
  se cablea). `docs/desarrollo-local.md` (producto) — update. `README.md`/
  `ROADMAP.md` — not needed.

## Implementation Plan

1. Catálogo y `gradle.properties`: añadir `androidx-activity-compose` y
   `android.useAndroidX=true`.
2. `composeApp/build.gradle.kts`: aplicar plugins Compose/AGP, declarar
   `androidTarget()`/`iosArm64()`/`iosSimulatorArm64()` (con framework)/`wasmJs`
   (browser + executable) y conservar `jvm()`; configurar el bloque `android { }` y
   las dependencias por source set.
3. Crear `App.kt` en `commonMain` (pantalla mínima) y los entrypoints
   `MainActivity`/`main.kt`/`MainViewController` + `AndroidManifest.xml`/`index.html`.
4. Verificar Android (`assembleDebug`), Wasm (`wasmJsBrowserDistribution`, pantalla
   en el navegador) e iOS (klib + framework) y el gate (`build`/`test`/`init.sh`).
5. Actualizar `ARCHITECTURE.md`, `CONSTRAINTS.md`, la skill de Compose y
   `docs/desarrollo-local.md`; registrar evidencia y actualizar `PROGRESS.md` y
   `feature_list.json` (commit/push/PR/CI los gestiona el orquestador).

## Implementation Tasks

- [ ] Catálogo: alias `androidx-activity-compose` (+ versión); `kotlinx-browser`
      solo si hace falta.
- [ ] `gradle.properties`: `android.useAndroidX=true` (+ `nonTransitiveRClass`);
      `jvmargs` a `-Xmx3g` solo si hay OOM.
- [ ] `:composeApp`: plugins `kotlin.multiplatform` + `compose.multiplatform` +
      `compose.compiler` + `android.application`.
- [ ] Targets: `androidTarget()`, `iosArm64()`/`iosSimulatorArm64()` con
      `binaries.framework { baseName = "ComposeApp"; isStatic = true }`,
      `wasmJs { browser(); binaries.executable() }`; conservar `jvm()`.
- [ ] Bloque `android { }`: `namespace`/`applicationId`
      `es.aviferdev.datopublico`, `compileSdk 35`, `minSdk 26`, `targetSdk 35`.
- [ ] `commonMain`: `App.kt` con `App()` (MaterialTheme + texto), sin red ni estado.
- [ ] `androidMain`: `MainActivity.kt` + `AndroidManifest.xml` (LAUNCHER).
- [ ] `wasmJsMain`: `main.kt` (`ComposeViewport`/`#root`) e `index.html`.
- [ ] `iosMain`: `MainViewController.kt` (`ComposeUIViewController { App() }`).
- [ ] `./gradlew :composeApp:assembleDebug` genera el APK.
- [ ] `./gradlew :composeApp:wasmJsBrowserDistribution` genera la distribución y la
      pantalla se ve en el navegador.
- [ ] `./gradlew :composeApp:compileKotlinIosSimulatorArm64` y
      `:composeApp:linkDebugFrameworkIosSimulatorArm64` generan el framework.
- [ ] Gate: `./gradlew build`, `./gradlew test`, `.harness/init.sh` en verde; iOS
      ignorado sin Xcode.
- [ ] Documentación durable (`ARCHITECTURE.md`, `CONSTRAINTS.md`, skill Compose) y
      `docs/desarrollo-local.md`; `PROGRESS.md` y `feature_list.json`.

## Verification Plan

Desde la raíz del producto (`..`, JDK 21 vía JBR/`JAVA_HOME`; SDK Android con
`local.properties`/`ANDROID_HOME`; Xcode para iOS):- **Android**: `./gradlew :composeApp:assembleDebug` → `BUILD SUCCESSFUL`; existe
  `composeApp/build/outputs/apk/debug/composeApp-debug.apk`. (Opcional: instalar
  en un emulador/dispositivo y ver la pantalla; no obligatorio para el gate.)
- **Web (Wasm)**: `./gradlew :composeApp:wasmJsBrowserDistribution` →
  `BUILD SUCCESSFUL`; `composeApp/build/dist/wasmJs/productionExecutable/` contiene
  `index.html` y `*.wasm`. Manual: servir ese directorio (p. ej. `npx serve` o un
  servidor estático) y abrir en el navegador; se ve la pantalla mínima. Para
  iterar: `./gradlew :composeApp:wasmJsBrowserDevelopmentRun` (proceso
  **bloqueante**; no usar en `init.sh`).
- **iOS**: `./gradlew :composeApp:compileKotlinIosSimulatorArm64` → `BUILD
  SUCCESSFUL` (klib); `./gradlew :composeApp:linkDebugFrameworkIosSimulatorArm64`
  → `BUILD SUCCESSFUL` y `composeApp/build/bin/iosSimulatorArm64/debugFramework/
  ComposeApp.framework`. (Alternativa device: `iosArm64`.)
- **Gate estándar sin servicios externos**: `./gradlew build --no-daemon` →
  `BUILD SUCCESSFUL`; `./gradlew test` → `:shared:jvmTest`, `:backend:test`,
  `:composeApp:jvmTest` verdes; `env -u JAVA_HOME .harness/init.sh` → exit 0.
- **Sin Xcode (paridad CI)**: comprobar que `./gradlew build` no intenta tareas de
  enlace iOS en un host no-Apple (en local basta verificar que la CI, ubuntu, queda
  en verde tras el push). Las tareas de Kotlin/Native para targets no soportados
  por el host se ignoran.
- **E2E**: no aplica — no hay harness E2E persistente ni flujo de usuario; esta
  feature solo demuestra compilación/render mínimo y mantiene el `SmokeTest`.
- **`init.sh`**: no se modifica; sigo siendo el gate no bloqueante que ejecuta
  `./gradlew build --no-daemon` y **no** arranca servidores.

## Evidence To Capture

- Salida de `:composeApp:assembleDebug` y ruta del APK generado.
- Salida de `:composeApp:wasmJsBrowserDistribution`, listado del directorio de
  distribución y captura/confirmación de la pantalla en el navegador.
- Salida de `:composeApp:compileKotlinIosSimulatorArm64` y
  `linkDebugFrameworkIosSimulatorArm64` + ruta del `.framework`/klib.
- Salida de `./gradlew build --no-daemon`, `./gradlew test` y `init.sh` (exit 0);
  run de CI en verde (sin Xcode) y PR.
- Ficheros del commit `FT00005`, entrada en `PROGRESS.md` y `feature_list.json`
  (`evidence`).

## Validator Checklist

- [ ] Alcance: solo wiring de targets + pantalla mínima + entrypoints; sin
      pantallas reales, navegación, red, `:shared` cableado ni proyecto Xcode.
- [ ] Escenarios 1–6 pasan (Android APK, Wasm distribuido y renderizado, iOS
      klib+framework, UI única en `commonMain`, gate verde sin Xcode/BD, tests
      intactos).
- [ ] `App()` vive en `commonMain` y cada plataforma aporta solo su entrypoint.
- [ ] `jvm()` se conserva y la task raíz `test` sigue cubriendo `:composeApp:jvmTest`.
- [ ] No se cablea `http://localhost` ni dependencia `:shared` (targets no
      coincidentes) en `commonMain`.
- [ ] Gate `./gradlew build`/`test`/`init.sh` verde sin servicios externos; iOS no
      bloquea en hosts no-Apple.
- [ ] `ARCHITECTURE.md`, `CONSTRAINTS.md`, skill de Compose y
      `docs/desarrollo-local.md` actualizados; `PROGRESS.md` y `feature_list.json`
      corregidos.
- [ ] No se añadió comportamiento ni features fuera de alcance.

## Notas de implementación (FT00005)

Hallazgos durante la implementación que **corrigen/amplían** este spec:

- **`settings.gradle.kts` sí hubo que tocarlo** (el spec lo daba por «not needed»).
  El plugin de Kotlin/Wasm registra a nivel de proyecto repositorios Ivy para las
  distribuciones de **Binaryen**, **Node** y **Yarn**; con
  `RepositoriesMode.FAIL_ON_PROJECT_REPOS` el build falla en
  `:composeApp:kotlinBinaryenSetup` (`repository ... was added by unknown code`).
  Solución: `RepositoriesMode.PREFER_SETTINGS` (el settings sigue siendo la fuente
  única de verdad) + declarar esos tres repositorios Ivy con el **layout exacto**
  del plugin (`BinaryenSetupTask`/`NodeJsSetupTask`/`YarnSetupTask`) y `content`
  filtrado a `com.github.webassembly`/`org.nodejs`/`com.yarnpkg`. Durable en
  `CONSTRAINTS.md`.
- **Tests de Wasm acotados del gate**: se probó la ruta `nodejs()` (la que sugiere
  el spec) para no depender de Chrome, pero `wasmJsNodeTest` **falla** porque el
  módulo `.wasm` de Skiko no se puede cargar bajo Node («both async and sync
  fetching of the wasm failed»). Se mantiene `browser()` (necesario para
  `wasmJsBrowserDistribution`) y se **desactiva** `wasmJsBrowserTest` (Karma/Chrome)
  del gate. El `SmokeTest` sigue corriendo en `jvmTest`, en los tests unitarios de
  Android (`testDebugUnitTest`/`testReleaseUnitTest`) y en `iosSimulatorArm64Test`.
  Nota: se descartó `useKarma { useChromeHeadless() }` porque no hay Chrome en la
  máquina de verificación. Documentado en `docs/desarrollo-local.md`.
- **`index.html`**: el bundle web de producción se llama `composeApp.js` (nombre
  por defecto), que coincide con el `<script src>` del `index.html` creado; la
  pantalla se monta en `document.body` vía `ComposeViewport`.
- **`jvmToolchain(21)` + `compileOptions` Java 21**: AGP exige que el `jvmTarget`
  de Kotlin y el `sourceCompatibility`/`targetCompatibility` coincidan; se fijan a
  21.
- **`android.useAndroidX=true` + `android.nonTransitiveRClass=true`** añadidos a
  `gradle.properties` (AGP los exige al usar `androidx.activity:activity-compose`).
- **`kotlin-js-store/yarn.lock`**: artefacto versionado generado por el plugin
  (`kotlinUpgradeYarnLock`) para reproducir la instalación npm del cliente Web.
