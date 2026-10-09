# Feature Implementation Spec: Estructura del monorepo Gradle

## Source Feature

- `id`: bootstrap-monorepo-gradle
- `ft_id`: FT00001
- `parts`: none (atomic)
- `area`: fundaciones
- `depends_on`: none
- `status`: not_started (rama `feat/ft00001-bootstrap-monorepo-gradle` ya reclamada con push)
- `source`: `feature_list.json`

## Goal

Dejar el repositorio público (`..`, `DatoPublico`) con un monorepo Gradle Kotlin
DSL reproducible: un solo proyecto multi-módulo (`:shared`, `:backend`,
`:composeApp`) declarado en un version catalog, un wrapper commiteado y una CI de
GitHub Actions que ejecuta `build + tests` en verde. Es la base técnica
(`docs/roadmap.md` 0.1-T01 y 0.1-T06) sobre la que se montan las features
siguientes; **no** añade todavía DTOs, Ktor ni UI.

## Non-Goals

- DTOs y `kotlinx.serialization` en `:shared` → `bootstrap-shared-dtos` (FT00002).
- Docker Compose con PostgreSQL/pgvector y Flyway → `bootstrap-postgres-pgvector`.
- Servidor Ktor, healthcheck, config por entorno y logging → `bootstrap-ktor-healthcheck`.
- Targets Android/iOS/Web (Wasm) reales de Compose → `bootstrap-cmp-targets`.
- Lógica de negocio, clases de dominio o endpoints. Cualquier DTO del BOE.
- Publicación de la README/guía de entornos (`0.1-T07`).

## Job Story

Cuando arranco el desarrollo de DatoPublico sobre un repo aún vacío,
quiero un monorepo Gradle que compile y pase tests con un solo comando,
para poder construir cada capa (shared, backend, cliente) sin reconfigurar el
build una y otra vez.

## Users And Permissions

- Desarrollador (único, a tiempo parcial): compila y testea en local con JDK 21.
- CI (GitHub Actions): ejecuta el gate de build+tests en cada push/PR al repo
  público. Sin cuentas ni permisos del usuario final.

## Acceptance Scenarios

### Scenario 1: build completo desde la raíz

Given un checkout limpio del repo público con JDK 21 y el wrapper Gradle
commiteado,
When se ejecuta `./gradlew build` desde la raíz,
Then la build termina en `BUILD SUCCESSFUL` y se configuran los tres módulos
`:shared`, `:backend` y `:composeApp`.

### Scenario 2: tests verdes ejecutables

Given el mismo checkout,
When se ejecuta `./gradlew test`,
Then las tareas de test de los módulos existen, se ejecutan (no `NO-SOURCE`) y
pasan.

### Scenario 3: dependencia entre módulos

Given los tres módulos incluidos,
When `:backend` declara `implementation(project(":shared"))`,
Then `./gradlew :backend:compileKotlin` resuelve `:shared` sin fallos.

### Scenario 4: CI en verde

Given un push/PR a `main` del repo público,
When GitHub Actions ejecuta el workflow de build+tests en `ubuntu-latest`,
Then el job finaliza en verde sin pasos manuales.

### Scenario 5: wrapper autosuficiente

Given una máquina/runner sin Gradle instalado,
When se usa `./gradlew` en lugar de `gradle`,
Then la build funciona porque `gradlew`, `gradlew.bat`,
`gradle/wrapper/gradle-wrapper.properties` y `gradle-wrapper.jar` están
commiteados.

## Repository Research

### Files Inspected

- `.harness/feature_list.json` y `PROGRESS.md` — entrada FT00001, verificación,
  notas y estado pre-bootstrap (sin módulos Gradle).
- `.harness/docs/roadmap.md` §0.1.0 — tareas 0.1-T01 (monorepo) y 0.1-T06 (CI).
- `.harness/docs/technical-discovery.md` — Kotlin DSL + version catalog, KMP,
  JDK 21, PostgreSQL/pgvector.
- `.harness/ARCHITECTURE.md` y `CONSTRAINTS.md` — módulos/namespaces objetivo y
  reglas operativas (secretos, secciones, IA).
- Skills `ktor-backend-architecture` y `compose-multiplatform-architecture` —
  JDK 21, multi-proyecto con version catalog, `:backend`/`:composeApp` dependen de
  `:shared`, namespaces.
- Producto (`..`): `git ls-files` → solo `.gitignore`, `LICENSE`, `README.md`,
  `ROADMAP.md`; no hay `settings.gradle.kts`, wrapper ni módulos.
- Producto: `git branch` → estamos en `feat/ft00001-bootstrap-monorepo-gradle`;
  `git status` limpio; la rama existe en `origin` (claim hecho).

### Existing Patterns To Follow

- Namespaces: raíz `es.aviferdev.datopublico`; backend
  `es.aviferdev.datopublico.backend` (`ARCHITECTURE.md`, skills).
- Version catalog + Kotlin DSL como decisión de stack ya cerrada.
- JDK 21 (toolchain) en todo el proyecto.
- Rama `feat/ft00001-...` y commits con `FT00001` como scope
  (`docs/git-workflow.md`); `init.sh` es no bloqueante y no arranca servidores.

### Current Gaps

- No existe wrapper Gradle ni distribución local de Gradle **ni JDK** en la
  máquina (`java -version` y `gradle` fallan); el implementer debe instalar JDK 21
  y una Gradle 8.x para generar el wrapper, o descargar el wrapper oficial.
- No existe `.github/workflows/`, `gradle.properties` ni
  `gradle/libs.versions.toml`.
- `.gitignore` no cubre artefactos Gradle (`.gradle/`, `build/`).

## Technical Approach

Bootstrap estructural mínimo y compilable, sin funcionalidad de producto:

1. **Wrapper y toolchain.** Generar el wrapper con Gradle 8.x
   (`gradle wrapper --gradle-version <8.x estable>`) y commitear
   `gradlew`, `gradlew.bat`, `gradle/wrapper/*`. Fijar JDK 21 con toolchain en
   Gradle y `actions/setup-java` (temurin) en CI.
2. **settings.gradle.kts.** `pluginManagement`/`dependencyResolutionManagement`
   con `repositories` (Maven Central, Google, Gradle Plugin Portal) e
   `include(":shared", ":backend", ":composeApp")`.
3. **Version catalog.** `gradle/libs.versions.toml` centraliza versiones y
   aliases. Para FT00001 basta Kotlin (multiplatform/JVM) y `kotlin("test")`;
   se predeclaran (sin activar) las versiones de AGP, Compose Multiplatform,
   Ktor, `kotlinx.serialization` y coroutines para que las activan FT00002/04/05.
4. **Módulos mínimos** (sin features):
   - `:shared` → plugin `kotlin("multiplatform")` con **solo target `jvm()`** y
     un test smoke en `commonTest`. Los targets wasm/iOS llegan con FT00005.
   - `:backend` → plugin `kotlin("jvm")`, `implementation(project(":shared"))` y
     un test smoke. El `application`/Ktor llega con FT00004.
   - `:composeApp` → plugin `kotlin("multiplatform")` con **solo target `jvm()`**
     y un test smoke. El plugin Compose y los targets Android/iOS/Wasm llegan con
     FT00005.
   - Restringir a `jvm()` ahora mantiene `./gradlew build` verde en
     `ubuntu-latest` sin Android SDK, Xcode ni descargas de Kotlin/Native.
5. **Root build.gradle.kts** que declare los plugins con `apply false`.
6. **gradle.properties** con `org.gradle.jvmargs` razonable y
   `kotlin.code.style=official` (sin configuration-cache hasta que el proyecto
   madure).
7. **CI** `.github/workflows/ci.yml`: `ubuntu-latest`, JDK 21, caché Gradle,
   `./gradlew build --no-daemon` (cubre `test`).
8. **`.gitignore`** con artefactos Gradle; **no** ignorar
   `gradle/wrapper/gradle-wrapper.jar`.

Alternativa aceptable si no se puede instalar Gradle: descargar la distribución
8.x, generar el wrapper, borrar la instalación temporal y commitear el wrapper;
documentar el comando exacto en la evidencia.

## Expected File Changes

Rutas provisionales: el repo aún no tiene build. Todas se crean en el repo de
producto (raíz `..`).

- `settings.gradle.kts` — create; proyecto raíz e `include` de los 3 módulos.
- `build.gradle.kts` — create; plugins raíz `apply false`.
- `gradle.properties` — create; propiedades JVM/Kotlin.
- `gradle/libs.versions.toml` — create; version catalog.
- `gradlew`, `gradlew.bat` y `gradle/wrapper/{gradle-wrapper.jar,gradle-wrapper.properties}` — create; wrapper commiteado (el jar también).
- `shared/build.gradle.kts` (+ `src/commonTest/.../SmokeTest.kt`) — create; KMP `jvm()` con test smoke.
- `backend/build.gradle.kts` (+ `src/test/.../backend/SmokeTest.kt`) — create; Kotlin JVM, dependencia de `:shared` y test smoke.
- `composeApp/build.gradle.kts` (+ `src/commonTest/.../app/SmokeTest.kt`) — create; KMP `jvm()` con test smoke.
- `.github/workflows/ci.yml` — create; build+tests.
- `.gitignore` — modify; ignorar `.gradle/`, `build/`, `**/build/`,
  `local.properties`, `.kotlin/`, `*.hprof`.

## Visual Design Impact

- UI involved: no. No hay UI ni tokens visuales en esta feature.

## Durable Documentation Impact

- `ARCHITECTURE.md` (harness): not needed — ya describe los módulos y namespaces
  que esta feature materializa.
- `CONSTRAINTS.md`: not needed — no introduce reglas MUST/MUST NOT nuevas.
- `AGENTS.md` (harness): not needed — el flujo de arranque y los comandos
  previstos ya figuran; esta feature los hace reales.
- Otros: ninguno. La README del producto pertenece a `0.1-T07` (fuera de
  alcance). `PROGRESS.md` y `feature_list.json` son evidencia de cierre.

## Implementation Plan

1. Instalar/confirmar JDK 21 y obtener Gradle 8.x; generar el wrapper desde
   `..` y verificar `./gradlew --version`.
2. Crear `settings.gradle.kts`, `build.gradle.kts`, `gradle.properties` y
   `gradle/libs.versions.toml`.
3. Crear los tres módulos con sus `build.gradle.kts` mínimos y un test smoke por
   módulo; declarar `:backend` → `:shared`.
4. Ejecutar `./gradlew build` y `./gradlew test` en local hasta verde.
5. Añadir `.github/workflows/ci.yml` y actualizar `.gitignore`.
6. Commit con scope `FT00001`, push de la rama y abrir PR; comprobar CI.

## Implementation Tasks

- [ ] Confirmar JDK 21 y generar/commitear el wrapper Gradle 8.x.
- [ ] Escribir `settings.gradle.kts` con `include(":shared", ":backend", ":composeApp")`.
- [ ] Crear `gradle/libs.versions.toml` con aliases de plugins y librerías.
- [ ] Root `build.gradle.kts` con plugins `apply false` y `gradle.properties`.
- [ ] Crear `:shared` KMP (`jvm()`) + test smoke en `commonTest`.
- [ ] Crear `:backend` Kotlin JVM + `implementation(project(":shared"))` + test smoke.
- [ ] Crear `:composeApp` KMP (`jvm()`) + test smoke.
- [ ] Ejecutar `./gradlew build` y `./gradlew test` hasta verde.
- [ ] Añadir `.github/workflows/ci.yml` (JDK 21, `./gradlew build`).
- [ ] Actualizar `.gitignore` con artefactos Gradle (sin ignorar el wrapper).
- [ ] Commit `feat(FT00001): ...`, push y PR; verificar CI verde.

## Verification Plan

- Desde la raíz del producto (`..`):
  - `./gradlew build` → `BUILD SUCCESSFUL`.
  - `./gradlew test` → tareas de test ejecutadas y verdes (no `NO-SOURCE`).
  - `./gradlew projects` → lista `:shared`, `:backend`, `:composeApp`.
  - `./gradlew :backend:compileKotlin` → resuelve `:shared` sin fallos.
- CI: el workflow de GitHub Actions de `build + tests` finaliza en verde en el PR.
- E2E: no aplica. No hay flujo de usuario, autenticación, routing ni API todavía;
  los tests smoke de los módulos son suficientes para esta feature.
- `init.sh` (harness): sigue siendo no bloqueante y no arranca servidores; tras
  el bootstrap sus comandos impresos (`./gradlew build`, `./gradlew test`) pasan
  a ser reales. No se modifica en esta feature.

## Evidence To Capture

- Salida de `./gradlew --version` (versión Gradle + JVM).
- Salida de `./gradlew build` y `./gradlew test` (resumen `BUILD SUCCESSFUL`).
- Salida de `./gradlew projects` mostrando los tres módulos y de
  `./gradlew :backend:compileKotlin`.
- URL/estado del workflow de CI en verde (run del PR) y lista de ficheros del
  commit `FT00001`.
- Entrada breve en `PROGRESS.md` y `feature_list.json` (`evidence`).

## Validator Checklist

- [ ] Implementation stays within this feature's scope (sin DTOs, Ktor, UI,
      Docker ni lógica de negocio).
- [ ] `./gradlew build` y `./gradlew test` pasan desde la raíz del producto.
- [ ] `:shared`, `:backend` y `:composeApp` existen y están en el version catalog.
- [ ] `:backend` depende de `:shared` y compila.
- [ ] El wrapper está commiteado (incluido `gradle-wrapper.jar`) y funciona sin
      Gradle del sistema.
- [ ] CI de GitHub Actions en verde.
- [ ] `.gitignore` cubre artefactos Gradle sin excluir el wrapper.
- [ ] Verification evidence is present (comandos, salida y run de CI).
- [ ] No unrelated product behavior or extra feature work was added.
- [ ] `feature_list.json` y `PROGRESS.md` actualizados correctamente.
