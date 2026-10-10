# Feature Implementation Spec: Esqueleto Ktor con healthcheck

## Source Feature

- `id`: bootstrap-ktor-healthcheck
- `ft_id`: FT00004
- `parts`: none (atomic)
- `area`: fundaciones
- `depends_on`: bootstrap-monorepo-gradle (FT00001, `accepted`)
- `status`: passing (implementada y autoverificada; pendiente de validación
  independiente; rama `feat/ft00004-bootstrap-ktor-healthcheck`)
- `source`: `feature_list.json`

## Goal

Crear el **esqueleto del backend Ktor** en `:backend`: un servidor Netty que
arranca con **configuración por entorno** (host/puerto/entorno/nivel de log con
valores por defecto seguros), **logging estructurado** (JSON) y un **endpoint de
healthcheck** `GET /health` que responde `200 {"status":"ok"}`. Es la base de
`docs/roadmap.md` 0.1-T03 y el punto de apoyo de la ingesta (FT00006, FT00009),
la API pública (FT00026+) y el despliegue (FT00041).

El arranque **no** debe depender de la base de datos ni de ningún servicio
externo: los subsistemas que aún no existen (Hikari/Flyway, OpenCode, ONNX,
repositorios) llegarán en features posteriores y se cablearán
condicionalmente en el composition root.

## Non-Goals

- **Persistencia en el arranque** (HikariCP/`DataSource`, Flyway al arrancar),
  migraciones en `run` y acceso a BD → FT00003 ya dejó las tareas Flyway
  explícitas; su wiring en la app llega con FT00008+.
- **Endpoints de dominio** (feed, detalle, búsqueda, chat), CORS, rate limiting,
  errores JSON, OpenAPI → FT00026–FT00031/FT030; aquí solo `/health`.
- **Cliente del BOE, ingesta, RAG, resúmenes, destacados**: features posteriores.
- **Dockerfile del backend, HTTPS, secretos reales, backups, métricas/alertas de
  producción** → FT00041/FT00042.
- **HOCON/`application.conf` con `EngineMain`**: se descarta como mecanismo de
  configuración de esta feature (ver *Technical Approach*).

## Job Story

Cuando desarrollo las features del backend,
quiero un servidor Ktor mínimo que arranque con un comando y exponga un
healthcheck con logging estructurado,
para poder trabajar y desplegar el backend de forma reproducible y comprobar que
el proceso está vivo sin depender de la base de datos.

## Users And Permissions

- Desarrollador / operador (único actor): ejecuta `./gradlew :backend:run` y
  consulta `/health` con `curl`. Sin cuentas ni datos personales; no hay
  autenticación en este endpoint operativo.

## Acceptance Scenarios

### Scenario 1: el servidor arranca y el healthcheck responde

Given el repo compilado y sin variables de entorno,
When ejecuto `./gradlew :backend:run`,
Then el servidor Netty arranca (por defecto en `0.0.0.0:8080`) y
`curl -s http://localhost:8080/health` devuelve HTTP `200` con cuerpo
`{"status":"ok"}`.

### Scenario 2: configuración por entorno

Given `SERVER_PORT=8090` (y opcionalmente `SERVER_HOST`),
When ejecuto `./gradlew :backend:run` y consulto `http://localhost:8090/health`,
Then el servidor escucha en el puerto indicado y responde `200 {"status":"ok"}`.

### Scenario 3: arranque sin base de datos

Given una máquina/runner **sin PostgreSQL**,
When ejecuto `./gradlew :backend:run` (o `./gradlew build`),
Then el servidor arranca y `/health` responde sin intentar conectarse a ninguna
base de datos.

### Scenario 4: test de integración del healthcheck

Given el test con `testApplication`,
When hago `GET /health`,
Then la respuesta es `200`, `Content-Type: application/json` y el cuerpo
deserializa a `HealthDto(status = "ok")`.

### Scenario 5: error claro de configuración

Given `SERVER_PORT=no-es-un-numero`,
When ejecuto `./gradlew :backend:run`,
Then el arranque falla con un mensaje claro (no arranca en silencio en un puerto
por defecto).

## Repository Research

### Files Inspected

- `.harness/feature_list.json` (FT00004), `PROGRESS.md` (Sessions 017–022),
  `docs/feature-ids.md` — FT00001/FT00002/FT00003 `accepted`; siguiente feature
  `bootstrap-ktor-healthcheck`.
- `.harness/docs/roadmap.md` §0.1.0 (`0.1-T03`: «Esqueleto Ktor: healthcheck,
  configuración por entorno, logging») y `docs/technical-discovery.md`
  (Ktor/Netty, logs estructurados, secretos por entorno, N100/8 GB).
- Skill `ktor-backend-architecture` — layout de paquetes, composition root en
  `Application.kt`, `plugins/` (serialization, routing, health), `infra/`
  (config), `backend/src/main/resources/logback.xml`, regla de dependencia y
  wiring condicional.
- `.harness/ARCHITECTURE.md` (fronteras; `:backend` = Ktor), `CONSTRAINTS.md`
  (gate de build sin servicios externos; sin credenciales versionadas; fail-fast
  ante configuración ausente), nota `CONSTRAINTS.md` de que el backend en
  producción aplica migraciones al arrancar (FT00004+, no en esta feature).
- Producto `..`: `settings.gradle.kts` (`:shared`, `:backend`, `:composeApp`),
  `build.gradle.kts` raíz (plugins `apply false`, incluido `libs.plugins.ktor`;
  task raíz `test` que agrega `:backend:test`), `gradle/libs.versions.toml`
  (Ktor 3.0.3, kotlinx.serialization 1.8.0, coroutines 1.10.1 predeclarados;
  `ktor-server-core`, `ktor-server-netty`, `ktor-serialization-kotlinx-json` ya
  como alias; falta `${...}` para content-negotiation/call-logging/test-host y
  logback).
- Producto: `backend/build.gradle.kts` (Kotlin JVM + plugin Flyway + configuración
  `flyway`; `implementation(project(":shared"))`; sin `application`/`main`),
  `backend/src/main/resources/db/migration/V1__esquema_base.sql`,
  `backend/src/test/.../SmokeTest.kt`, `shared/src/commonMain/.../serialization/DatoPublicoJson.kt`,
  `.github/workflows/ci.yml` (`./gradlew build --no-daemon`, sin BD),
  `.harness/init.sh` (gate no bloqueante), `docs/desarrollo-local.md` y
  `README.md` (guía de entorno local).
- `git branch`/`git ls-remote` → rama `feat/ft00004-bootstrap-ktor-healthcheck`
  en local y `origin` (claim hecho, commit `chore(FT00004): claim`).

### Existing Patterns To Follow

- Version catalog + Kotlin DSL; namespace `es.aviferdev.datopublico.backend`;
  commits con scope `FT00004`.
- Layout por feature con roles (`plugins/`, `infra/`, `Application.kt` como
  composition root; sin framework de DI).
- Configuración y secretos **solo** por entorno (defaults no sensibles; fail-fast
  si algo obligatorio falta) — coherente con FT00003.
- Reutilizar `DatoPublicoJson` de `:shared` para la serialización JSON.
- El gate `./gradlew build` / `init.sh` debe seguir verde **sin** servicios
  externos; los tests Ktor usan `testApplication` (sin abrir puerto real).

### Current Gaps

- `:backend` no tiene `main`, ni `application` plugin, ni dependencias Ktor de
  servidor cableadas, ni `logback.xml`, ni configuración por entorno.
- No existe `Application.kt`, ni paquete `plugins/`/`infra/`.
- El catálogo no tiene `ktor-server-content-negotiation`,
  `ktor-server-call-logging`, `ktor-server-test-host` ni logback.
- No hay `mainClass` declarado para la tarea `run`.

## Technical Approach

1. **Build de `:backend`** (`backend/build.gradle.kts`, sin romper Flyway):
   - Aplicar el plugin `application` (para la tarea `run`) y
     `alias(libs.plugins.ktor)` (plugin Gradle de Ktor, ya predeclarado en la
     raíz con `apply false`).
   - `application { mainClass.set("es.aviferdev.datopublico.backend.ApplicationKt") }`
     — **obligatorio**: el plugin de Ktor por defecto apunta a
     `io.ktor.server.netty.EngineMain`, que exige `application.conf` (fuera de
     alcance); si no se sobreescribe, `:backend:run` fallará.
   - Dependencias:
     `ktor-server-core`, `ktor-server-netty`,
     `ktor-server-content-negotiation`, `ktor-serialization-kotlinx-json`,
     `ktor-server-call-logging`, `logback-classic` y
     `logstash-logback-encoder` (logs JSON). Test:
     `ktor-server-test-host`. Preservar la configuración `flyway` existente y no
     engancharla a `build`/`check`.
   - El plugin `io.ktor.plugin` no debe hacer que `run`/`build` requieran
     `application.conf`; si apareciera ese problema, usar solo `application`
     (documentar en la evidencia).
2. **Configuración por entorno** (`infra/AppConfig.kt`):
   - `data class AppConfig(val host: String, val port: Int, val environment: String, val logLevel: String)`.
   - `AppConfig.fromEnv(env: Map<String, String> = System.getenv())` para poder
     testear sin tocar el entorno real:
     `SERVER_HOST` (default `0.0.0.0`), `SERVER_PORT`? `PORT`? (default `8080`),
     `APP_ENV` (default `local`), `LOG_LEVEL` (default `INFO`).
   - Puerto no numérico o fuera de rango → `IllegalArgumentException` con mensaje
     claro (fail-fast). Sin secretos y sin imprimir valores sensibles.
3. **Composition root** (`Application.kt`):
   - `fun main()`: lee `AppConfig.fromEnv()` y
     `embeddedServer(Netty, port = config.port, host = config.host, module = Application::module).start(wait = true)`.
   - `fun Application.module()`: instala `configureSerialization()`,
     `configureMonitoring()` y `configureRouting()`. Sin BD, sin Hikari, sin
     Flyway: el arranque no depende de servicios externos.
4. **Plugins Ktor** (`plugins/`):
   - `Serialization.kt`: `install(ContentNegotiation) { json(DatoPublicoJson) }`
     (reutiliza la config de `:shared`).
   - `Monitoring.kt`: `install(CallLogging) { level = Level.INFO }`.
   - `Routing.kt`: `fun Application.configureRouting() { routing { healthRoutes() } }`.
   - `Health.kt`: `@Serializable data class HealthDto(val status: String = "ok")`
     y `fun Route.healthRoutes() { get("/health") { call.respond(HttpStatusCode.OK, HealthDto()) } }`.
     `HealthDto` se define **en `:backend`** (endpoint operativo del servidor, no
     parte del contrato de dominio compartido; se evita ampliar `:shared`). Al
     ser un tipo serializable de transporte lleva el sufijo `Dto`; la regla MUST
     de `CONSTRAINTS.md` está acotada a `:shared` y no se contradice.
5. **Logging estructurado** (`backend/src/main/resources/logback.xml`):
   - `ConsoleAppender` con `net.logstash.logback.encoder.LogstashEncoder`
     (una línea JSON por evento), campo `env` con `${APP_ENV:-local}` y nivel
     raíz `${LOG_LEVEL:-INFO}`. Sin telemetría ni destino externo (solo stdout).
   - Si `logstash-logback-encoder` diera incompatibilidad con Logback 1.5, usar
     `PatternLayoutEncoder` con formato clave=valor de una línea y registrarlo en
     la evidencia (la exigencia es "logging estructurado", no una librería).
6. **Tests** (`backend/src/test/...`):
   - `plugins/HealthTest.kt`: con `testApplication { application { module() } }`,
     `GET /health` → `200`, `application/json`, cuerpo `{"status":"ok"}`.
   - `infra/AppConfigTest.kt`: defaults con `emptyMap()`, overrides con
     `SERVER_PORT=8090`, y fallo con puerto inválido.
   - Mantener el `SmokeTest.kt` existente.

**Riesgos clave:** desajuste de `mainClass` con el plugin de Ktor (mitigado
sobreescribiéndolo); compatibilidad de versiones de logback/logstash; no
introducir dependencia de BD en `run`/`build`; puerto 8080 ocupado en local
(configurable por entorno).

## Expected File Changes

Rutas en el repo de producto (`..`):

- `gradle/libs.versions.toml` — modify; versiones `logback`/`logstash` y aliases
  `ktor-server-content-negotiation`, `ktor-server-call-logging`,
  `ktor-server-test-host`, `logback-classic`, `logstash-logback-encoder`.
- `backend/build.gradle.kts` — modify; plugins `application`/`io.ktor.plugin`,
  `mainClass` y dependencias; conservar Flyway intacto.
- `backend/src/main/kotlin/es/aviferdev/datopublico/backend/Application.kt` — create.
- `backend/src/main/kotlin/es/aviferdev/datopublico/backend/infra/AppConfig.kt` — create.
- `backend/src/main/kotlin/es/aviferdev/datopublico/backend/plugins/{Serialization,Monitoring,Routing,Health}.kt` — create.
- `backend/src/main/resources/logback.xml` — create.
- `backend/src/test/kotlin/es/aviferdev/datopublico/backend/plugins/HealthTest.kt` — create.
- `backend/src/test/kotlin/es/aviferdev/datopublico/backend/infra/AppConfigTest.kt` — create.
- `backend/src/test/kotlin/es/aviferdev/datopublico/backend/SmokeTest.kt` — keep as-is.
- `docs/desarrollo-local.md` — update; añadir arranque del backend
  (`./gradlew :backend:run`), variables `SERVER_HOST`/`SERVER_PORT`/`APP_ENV`/
  `LOG_LEVEL` y logs JSON.

No se toca la raíz del build, `:shared`, `:composeApp`, `.github/workflows/ci.yml`
ni las migraciones Flyway (la CI debe seguir verde sin BD).

## Visual Design Impact

- UI involved: no. Sin pantallas, tokens ni textos de UI.

## Durable Documentation Impact

- `ARCHITECTURE.md` (harness): update — `:backend` deja de ser pre-bootstrap:
  anotar que ya existe el composition root Ktor (`Application.kt`), `plugins/` e
  `infra/` y el endpoint `/health`.
- `CONSTRAINTS.md`: update — añadir un MUST durable: el arranque del backend
  **no** depende de la base de datos ni de servicios externos; se registran solo
  los subsistemas/rutas cuyas dependencias existen (healthcheck operativo sin
  BD), y la configuración es por entorno con fail-fast en valores inválidos.
- `AGENTS.md` (harness): not needed — no cambia flujo, arranque ni reglas de
  repo.
- Otros: `docs/desarrollo-local.md` (producto) — update, arranque y variables del
  backend; `README.md`/`ROADMAP.md` — not needed (guía de arranque = 0.1-T07).

## Implementation Plan

1. Actualizar el version catalog y `backend/build.gradle.kts` (plugins,
   `mainClass`, dependencias Ktor/logback) conservando Flyway.
2. Crear `infra/AppConfig.kt` (lectura de entorno con defaults y fail-fast).
3. Crear `Application.kt` (composition root) y `plugins/` (serialization,
   monitoring, routing, health) con un arranque que no depende de la BD.
4. Añadir `logback.xml` con salida JSON estructurada.
5. Escribir los tests `HealthTest` y `AppConfigTest`; mantener `SmokeTest`.
6. Verificar `:backend:run` + `/health`, `:backend:test` y `./gradlew build`
   (sin BD); actualizar `CONSTRAINTS.md`/`ARCHITECTURE.md`/`docs/desarrollo-local.md`,
   `PROGRESS.md` y `feature_list.json`; commit/push/PR (CI) los gestiona el
   orquestador.

## Implementation Tasks

- [ ] Catálogo: aliases `ktor-server-content-negotiation`,
      `ktor-server-call-logging`, `ktor-server-test-host`, `logback-classic`,
      `logstash-logback-encoder` (+ versiones).
- [ ] `:backend`: plugins `application` + `io.ktor.plugin`, `mainClass` en
      `ApplicationKt`, dependencias de servidor; Flyway intacto y fuera de
      `build`/`check`.
- [ ] `AppConfig.kt`: `fromEnv(map)` con `SERVER_HOST`/`SERVER_PORT`(`PORT`)/
      `APP_ENV`/`LOG_LEVEL`, defaults y fail-fast de puerto inválido.
- [ ] `Application.kt`: `main()` con `embeddedServer(Netty, …)` y
      `Application.module()` (serialization + monitoring + routing).
- [ ] `plugins/Serialization.kt` (ContentNegotiation con `DatoPublicoJson`).
- [ ] `plugins/Monitoring.kt` (CallLogging) y `plugins/Routing.kt`.
- [ ] `plugins/Health.kt`: `HealthDto` + `GET /health` → `200 {"status":"ok"}`.
- [ ] `logback.xml` con encoder JSON (o fallback clave=valor documentado).
- [ ] Tests `HealthTest` (testApplication) y `AppConfigTest` (defaults/override/
      fallo); `SmokeTest` intacto.
- [ ] `./gradlew :backend:run` arranca y `/health` responde en verde.
- [ ] `CONSTRAINTS.md`, `ARCHITECTURE.md`, `docs/desarrollo-local.md`,
      `PROGRESS.md` y `feature_list.json` actualizados.

## Verification Plan

Desde la raíz del producto (`..`, JDK 21 vía JBR/`JAVA_HOME`):

- **Arranque + healthcheck** (en segundo plano; `run` es bloqueante):
  `SERVER_PORT=8090 ./gradlew :backend:run` → logs JSON por stdout; en otra
  terminal `curl -s -o /dev/null -w '%{http_code}' http://localhost:8090/health`
  → `200` y `curl -s http://localhost:8090/health` → `{"status":"ok"}`; después
  detener el proceso.
- **Config por defecto**: arrancar sin variables y comprobar que escucha en
  `8080`; `SERVER_PORT=no-numero` → falla con mensaje claro.
- **Tests**: `./gradlew :backend:test --rerun-tasks` → `BUILD SUCCESSFUL` con
  `HealthTest` y `AppConfigTest` (XML sin failures/errors); `SmokeTest` sigue.
- **Gate estándar sin BD**: parar el servidor y `./gradlew build --no-daemon` →
  `BUILD SUCCESSFUL`; `./gradlew test` → 3 módulos verdes; `.harness/init.sh` →
  exit 0.
- **E2E**: no aplica — no hay flujo de usuario ni harness E2E persistente; el
  test de integración con `testApplication` cubre la ruta HTTP `/health`.
- `init.sh` (harness): no se modifica; sigue siendo el gate no bloqueante que
  ejecuta `./gradlew build` y **no** arranca servidores.

## Evidence To Capture

- Salida de `:backend:run` (log JSON de arranque con puerto/entorno) y de
  `curl` sobre `/health` (`200 {"status":"ok"}`), con el puerto usado.
- Salida de `./gradlew :backend:test` (nombres y resultado de `HealthTest`/
  `AppConfigTest`) y de `./gradlew build` sin BD; `init.sh` exit 0.
- Prueba de fail-fast con `SERVER_PORT` inválido.
- Ficheros del commit `FT00004`, PR y run de CI; entradas en `PROGRESS.md` y
  `feature_list.json` (`evidence`).

## Validator Checklist

- [ ] Implementation stays within scope (solo esqueleto Ktor + `/health` +
      config por entorno + logging; sin BD/Hikari/Flyway en `run`, sin endpoints
      de dominio, sin CORS/rate limit/OpenAPI).
- [ ] Escenarios 1–5 pasan (arranque, `/health` 200 `{"status":"ok"}`,
      configuración por `SERVER_PORT`, arranque y `build` sin BD, test de
      integración, fail-fast de puerto inválido).
- [ ] `mainClass` apunta a `ApplicationKt` y `:backend:run` arranca (no
      `EngineMain`/`application.conf`).
- [ ] Logging estructurado real (JSON o clave=valor de una línea) y sin
      secretos ni telemetría externa.
- [ ] El gate `./gradlew build`/`init.sh` sigue verde sin servicios externos y
      las tareas Flyway siguen fuera de `build`/`check`.
- [ ] `CONSTRAINTS.md`, `ARCHITECTURE.md`, `docs/desarrollo-local.md`,
      `PROGRESS.md` y `feature_list.json` actualizados correctamente.
- [ ] No unrelated product behavior or extra feature work was added.

## Implementation Notes (2026-10-10, FT00004)

Notas de implementación; **no** cambian el alcance ni los escenarios del spec.

1. **Plugin de serialización en `:backend` (gap del spec, dentro de alcance).** El
   spec lista `ktor-serialization-kotlinx-json` como dependencia, pero `HealthDto`
   es un tipo `@Serializable` **de `:backend`**: sin aplicar
   `org.jetbrains.kotlin.plugin.serialization` en el módulo, no se genera el
   serializador y `GET /health` falla en runtime
   (`Serializer for class 'HealthDto' is not found`). Se añadió el plugin al
   bloque `plugins` de `backend/build.gradle.kts` (ya predeclarado en la raíz con
   `apply false`). Es el único cambio no listado literalmente en *Expected File
   Changes*.
2. **`mainClass` y plugin de Ktor.** Con `application { mainClass.set(
   "es.aviferdev.datopublico.backend.ApplicationKt") }` tras aplicar
   `io.ktor.plugin`, `:backend:run` arranca el `main()` propio: no se usó
   `EngineMain` ni hizo falta `application.conf` (era el riesgo previsto en el
   spec; no se materializó). El plugin de Ktor añade tareas shadow
   (`shadowDistTar`/`shadowDistZip`) al `assemble`, que quedan verdes.
3. **Artefacto del entorno en el puerto 8080.** En la máquina de implementación
   `127.0.0.1:8080` lo ocupa el *mux* SSH de Colima, así que `curl
   http://localhost:8080/health` responde a ese otro servicio aunque el servidor
   haya enlazado `0.0.0.0:8080`. La verificación del escenario 1 se hizo contra
   la IP de LAN del host (`200 {"status":"ok"}`) además del test
   `AppConfigTest` (`fromEnv(emptyMap()).port == 8080`). No es un defecto del
   código.
4. **`logback.xml` con `logstash-logback-encoder` 8.0 + Logback 1.5.12** funcionó
   sin incompatibilidades: una línea JSON por evento en stdout con
   `app`/`env`/`level`; no hizo falta el *fallback* a `PatternLayoutEncoder`.
   `${APP_ENV:-local}` y `${LOG_LEVEL:-INFO}` resuelven del entorno (verificado
   con `APP_ENV=staging` → `"env":"staging"`).

