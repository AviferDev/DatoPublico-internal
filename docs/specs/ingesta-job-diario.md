# Feature Implementation Spec: Job diario de ingesta idempotente

## Source Feature

- `id`: ingesta-job-diario
- `ft_id`: FT00009
- `parts`: none (atómica; ~16-19 ficheros, por debajo del límite de 30)
- `area`: ingesta-boe
- `depends_on`: publicacion-persistencia (FT00008, `accepted`); indirectos ya cerrados: boe-parser-publicacion (FT00007), boe-sumario-cliente (FT00006), bootstrap-postgres-pgvector (FT00003)
- `status`: passing (implementado y autoverificado 2026-10-10; rama `feat/ft00009-ingesta-job-diario`)
- `source`: `feature_list.json`

> **Nota de limpieza (2026-10-10).** Tras la aceptación, los identificadores del
> código de esta feature se renombraron a **inglés** (regla MUST nueva en
> `CONSTRAINTS.md` §«Nombres y contratos»): `IngestaConfig`→`IngestionConfig`,
> `IngestaJob`/`IngestaJobDiario`→`IngestionJob`/`DailyIngestionJob`,
> `IngestaResult`→`IngestionResult`, `IngestaSchedule`→`IngestionSchedule`,
> `IngestaScheduler`→`IngestionScheduler`, y los métodos/propiedades
> (`ejecutar`→`run`, `totalEntradas`→`totalEntries`, `guardadas`→`saved`,
> `fallidas`→`failed`, `iniciar`→`start`). El **cuerpo del spec conserva los
> nombres del plan**; el comportamiento y el JSON no cambian. Las claves de
> entorno siguen siendo `INGESTA_*` y el paquete `ingesta/job` (heredado).

> **Alcance de «deduplicación».** La verificación oficial («ejecutar el job dos
> veces sobre la misma fecha no crea duplicados») la garantiza el *upsert* por
> `id` de `PublicationRepository.save` (FT00008). La deduplicación **entre
> secciones** (III ↔ V.B, `docs/roadmap.md` 0.2-T05) se **difiere** (ver
> *Non-Goals*). «Idempotencia» = reejecutar no duplica; «detección de cambios» =
> el *upsert* reaplica la versión vigente del mismo `id`.

## Goal

Cerrar la ingesta de `docs/roadmap.md` 0.2-T04/T05: un **job programado** en
`:backend` que, a las **9:30** (hora de Madrid) y en una **segunda pasada** por la
tarde, ejecuta **descarga del sumario → parseo de cada publicación (XML) →
persistencia**, de forma **idempotente**. Se apoya en piezas ya cerradas:
`BoeSumarioClient` (FT00006), `BoePublicacionParser` (FT00007) y
`PublicationRepository` (FT00008). Es la base del backfill (FT00011),
categorización (FT00012) y observabilidad/alerta (FT00010).

Cablea el job en el arranque de forma **condicional y no bloqueante** (solo con
configuración de BD y si no está deshabilitado), y **no** clasifica, no hace
backfill, no emite alertas ni crea endpoints.

## Non-Goals

- **Clasificación curada y plazos** (valores) → FT00012. El job persiste con
  `categoria = null` / `plazo = null`, como produce hoy FT00007.
- **Backfill del histórico** → FT00011.
- **Observabilidad y alerta** (logs ricos, métrica de ausencia de ingesta) →
  FT00010. Aquí solo un log-resumen mínimo de cada ejecución.
- **Dedup III ↔ V.B por referencia/identificador** y **versionado/consolidación**
  → seguimiento posterior (ver *Riesgos / Open Questions*). Requiere un modelo de
  referencia que la ingesta aún no captura ni persiste.
- **Migración automática al arrancar** y `Dockerfile`/despliegue → FT00041. El
  job asume el esquema aplicado con `./gradlew :backend:flywayMigrate`.
- **Chunking** (FT00014), **embeddings** (FT00015/16), **resúmenes** (FT00019+).
- **Cron externo / systemd timer / Kubernetes CronJob**: la programación es
  interna (corrutina) para no añadir infraestructura en el N100.

## Job Story

Cuando el BOE publica el sumario del día,
quiero que el backend lo descargue, parsee y guarde automáticamente a las 9:30 y
en una segunda pasada por la tarde, sin duplicar lo ya guardado,
para que el corpus del día esté disponible de forma fiable sin intervención
manual y sin re-descargas duplicadas.

## Users And Permissions

- Job interno de `:backend` (proceso del servidor): sin cuentas, sin datos
  personales, sin autenticación. Usa `POSTGRES_*` (fuente única) y la API pública
  del BOE (solo lectura).
- El arranque **no** depende de la BD: si falta configuración o está
  deshabilitado, el servidor arranca igual y solo se omiten la ingesta y su
  scheduler (MUST de `CONSTRAINTS.md`).

## Acceptance Scenarios

### Scenario 1: disparo a las 9:30 y segunda pasada por la tarde

Given una configuración de horario `{09:30, 18:00}` en zona `Europe/Madrid`,
When se calcula el siguiente disparo desde un instante dado,
Then desde `09:00` el siguiente es `09:30` del mismo día; desde `09:31` es
`18:00`; desde `18:01` es `09:30` del día siguiente (el cálculo es **estricto**:
descarta el instante igual a `now`).

### Scenario 2: orquestación descarga → parseo → persistencia

Given un `BoeSumarioClient` que devuelve `N` `EntradaSumario` y un
`BoePublicacionParser` que produce una `Publicacion` por entrada,
When el job ejecuta para una fecha,
Then se llama a `PublicationRepository.save` una vez por cada entrada y el
resultado reporta `totalEntradas = N`, `guardadas = N`, `fallidas = 0`.

### Scenario 3: idempotencia (ejecutar dos veces la misma fecha)

Given un repositorio de publicaciones y un sumario con entradas conocidas,
When se ejecuta el job dos veces para la misma fecha,
Then tras la segunda ejecución el número de publicaciones almacenadas **no
cambia** (mismas `id`) y ninguna queda duplicada.

### Scenario 4: fallo parcial de una publicación no aborta el job

Given un sumario con `M` entradas donde una lanza `BoeTextoException` al parsear,
When el job ejecuta para esa fecha,
Then las otras `M-1` se persisten, el resultado reporta `fallidas = 1` y el job
**no** propaga la excepción.

### Scenario 5: el job se programa y dispara (tiempo virtual)

Given un `IngestionScheduler` con un reloj y un `delay` inyectables y virtuales,
When se avanza el tiempo hasta la ventana de la primera pasada y luego hasta la
segunda,
Then el job se ejecuta una vez por ventana (dos ejecuciones) y el bucle no muere
si una ejecución lanza.

### Scenario 6: *upsert* real contra PostgreSQL (opt-in)

Given el PostgreSQL de `docker-compose` con las migraciones aplicadas y
`DB_LIVE_TEST=1`,
When el job ejecuta dos veces la misma fecha con un sumario/parser de prueba,
Then en `publicacion` hay una fila por `id` (sin duplicados) y `actualizado_en`
avanzó en la segunda pasada (idempotencia real del *upsert*).

### Scenario 7: el gate sigue sin red ni BD

Given el runner sin PostgreSQL y sin red,
When se ejecuta `./gradlew build -PskipClient`, `./gradlew test`, `./gradlew detekt`
o `.harness/init.sh`,
Then todo está en verde (los tests del job usan dobles; los opt-in se omiten sin
sus variables).

## Repository Research

### Files Inspected

- Harness: `feature_list.json` (FT00009; FT00008 `accepted`), `PROGRESS.md` (deuda
  `HttpTimeout` → FT00009), `docs/feature-ids.md`, `docs/roadmap.md` §0.2.0
  (`0.2-T04`/`0.2-T05`), `docs/domain-model.md`, `docs/technical-discovery.md`,
  `docs/risks-and-open-questions.md` («ventana de la segunda pasada»),
  `ARCHITECTURE.md`, `CONSTRAINTS.md`, `docs/git-workflow.md` (claim, 30 fich.).
- Producto (`..`), rama `feat/ft00009-ingesta-job-diario` ya reclamada (local y
  `origin`, sin ficheros aún): `ingesta/sumario/{BoeSumarioClient,BoeSumarioHttpClient,
  EntradaSumario}.kt` (factory sin `HttpTimeout`),
  `ingesta/publicacion/{BoePublicacionParser,Publicacion,BoeTextoHttpClient}.kt`
  (factory sin `HttpTimeout`), `persistence/PublicationRepository.kt`,
  `infra/{DatabaseConfig,Database}.kt`, `Application.kt` (sin ingesta),
  `backend/build.gradle.kts` (sin `coroutines-core`), `gradle/libs.versions.toml`.

### Existing Patterns To Follow

- **Feature-first** en `ingesta/<área>/`: interfaz + impl en el mismo fichero
  (`BoePublicacionParser.kt`); consumir los colaboradores por **constructor**
  (`PublicationRepository`, `BoeSumarioClient`, `BoePublicacionParser`).
- **Config por entorno** pura y testeable (`fromEnv(env: Map<String,String> =
  System.getenv())`) con defaults no sensibles y fail-fast, patrón `AppConfig`/
  `DatabaseConfig`.
- **JDBC bloqueante** llamado fuera del hilo de eventos HTTP
  (`infra/Database.kt`): el job usa `Dispatchers.IO`.
- **Tests del gate sin red ni BD** (MUST): dobles propios o `MockEngine`;
  opt-in por variable de entorno (`BOE_LIVE_TEST`/`DB_LIVE_TEST`), omitidos sin
  la variable y fuera de `build`/`test`/`init.sh`/CI.
- Estilo MUST: `return` único, sin `else if`, funciones ≤40 líneas, KDoc en todo
  lo nuevo; coroutines ya disponibles (`kotlinx-coroutines-test` en tests).

### Current Gaps

- No existe ningún paquete `ingesta/job/` ni scheduler; `Application.kt` no cablea
  ingesta ni base de datos.
- Las factorías `boeSumarioHttpClient()`/`boeTextoHttpClient()` **no fijan
  `HttpTimeout`** (deuda Low registrada → esta feature): una descarga puede colgar
  el job indefinidamente.
- `:backend` no declara `kotlinx-coroutines-core` en `implementation` (llega
  transitivamente por Ktor, pero hay que hacerlo explícito).

## Technical Approach

1. **Configuración `ingesta/job/IngestionConfig.kt`** (pura, testeable): horario y
   zona de la ingesta, con `fromEnv`. Claves (defaults no sensibles):
   `INGESTA_ENABLED` (`true`), `INGESTA_TIMEZONE` (`Europe/Madrid`),
   `INGESTA_PRIMARY_TIME` (`09:30`), `INGESTA_SECONDARY_TIME` (`18:00`). Valida
   formato (`LocalTime`, zona IANA) con fail-fast y mensaje claro. Resuelve la
   duda abierta «ventana horaria de la segunda pasada» con un default documentado.

2. **`ingesta/job/IngestionSchedule.kt`** (puro, sin E/S): dado `now: ZonedDateTime`
   y la lista de horas, `nextRun(now): ZonedDateTime` devuelve el **siguiente**
   instante estrictamente posterior (hoy o mañana). Es la pieza que hace
   verificable «9:30 + segunda pasada» sin esperar tiempo real.

3. **`ingesta/job/IngestionJob.kt`** (orquestador, `suspend`): `ejecutar(fecha:
   LocalDate): IngestionResult`. Pasos: `BoeSumarioClient.obtenerSumario(fecha)` →
   por cada `EntradaSumario`, `BoePublicacionParser.parsear(entrada)` →
   `PublicationRepository.save(publicacion)` (upsert idempotente). Los accesos a
   BD van en `withContext(Dispatchers.IO)`. **Un fallo por entrada** (p. ej.
   `BoeTextoException`) se cuenta en `fallidas` y **no** aborta el resto; un fallo
   del sumario completo (`BoeSumarioException`) devuelve el resultado con `error`
   sin propagar. Resultado: `IngestionResult(fecha, totalEntradas, guardadas,
   fallidas, error)`. KDoc deja claro que reejecutar la misma fecha no duplica
   (upsert por `id`) y que `categoria`/`plazo` llegan `null` (FT00012).

4. **`ingesta/job/IngestionScheduler.kt`**: bucle de corrutina que calcula el
   siguiente disparo con `IngestionSchedule` (reloj inyectable, p. ej.
   `java.time.Clock`) y espera con una función `delay` inyectable (para tests de
   tiempo virtual). Al despertar, llama a `IngestionJob.ejecutar(LocalDate.now(zone))`
   y registra un **log-resumen** mínimo (fecha, total, guardadas, fallidas) en
   `Dispatchers.IO`; captura excepciones para no matar el bucle. No usa el plugin
   experimental de *scheduling* de Ktor: corrutina propia, sin nuevas
   dependencias ni API experimental.

5. **Wiring condicional en `Application.kt`**: en `module()`, si
   `IngestionConfig.fromEnv()` tiene `enabled = true` **y**
   `DatabaseConfig.fromEnv()` resuelve (hay `POSTGRES_PASSWORD`), se crea el
   `DataSource` (`Database.createDataSource`), se construyen los clientes
   (`boeSumarioHttpClient()` + `BoeTextoHttpClient` con `boeTextoHttpClient()`),
   el parser (`BoePublicacionHttpParser`), el repositorio
   (`PublicationRepositoryJdbc`) y el scheduler; se lanza en un `CoroutineScope`
   del módulo y se **cierra/cancela** en `ApplicationStopped` (cancelar scope +
   `dataSource.close()`). Cualquier fallo al construir la ingesta se registra y
   **no** impide el arranque (el servidor sigue sirviendo `/health`).

6. **Timeouts de red (deuda Low → FT00009)**: instalar `HttpTimeout` en
   `boeSumarioHttpClient()` y `boeTextoHttpClient()` (p. ej. `requestTimeoutMillis`
   y `socketTimeoutMillis` ~30 s, `connectTimeoutMillis` ~10 s, constantes
   documentadas) para que una descarga colgada no bloquee la ventana del job.

7. **`backend/build.gradle.kts`**: añadir `implementation(libs.kotlinx.coroutines.core)`.
   Sin cambios en la raíz, `settings.gradle.kts`, `:shared`, `:composeApp` ni CI.

**Riesgos clave:** (a) el job depende del esquema aplicado — en local
`flywayMigrate`, en producción la migración al arranque es de una feature
posterior; (b) el gate no puede probar red/BD — dobles + opt-in; (c) el doble
`HttpClient` se cierra al parar el servidor; (d) la ventana de la segunda pasada
es un default configurable, no una decisión de producto validada; (e) alcance
correctamente acotado (job + scheduler + wiring + timeouts).

## Expected File Changes

Rutas en el repo de producto (`..`); nombres de tipos orientativos (la convención
`ingesta/`+`Boe*` se mantiene; el implementer puede pasar los identificadores
nuevos a inglés si sigue la limpieza de FT00008, de forma consistente):

- `gradle/libs.versions.toml` — sin cambios (coroutines-core ya está declarada).
- `backend/build.gradle.kts` — modify; `implementation(libs.kotlinx.coroutines.core)`.
- `backend/src/main/kotlin/…/backend/ingesta/job/IngestionConfig.kt` — create.
- `backend/src/main/kotlin/…/backend/ingesta/job/IngestionSchedule.kt` — create.
- `backend/src/main/kotlin/…/backend/ingesta/job/IngestionJob.kt` — create
  (orquestador + `IngestionResult`).
- `backend/src/main/kotlin/…/backend/ingesta/job/IngestionScheduler.kt` — create.
- `backend/src/main/kotlin/…/backend/ingesta/sumario/BoeSumarioHttpClient.kt` —
  modify; `HttpTimeout`.
- `backend/src/main/kotlin/…/backend/ingesta/publicacion/BoeTextoHttpClient.kt` —
  modify; `HttpTimeout`, `HttpClient.close()`.
- `backend/src/main/kotlin/…/backend/Application.kt` — modify; wiring condicional
  + ciclo de vida.
- `backend/src/test/kotlin/…/backend/ingesta/job/IngestionConfigTest.kt` — create
  (gate, sin red/BD).
- `backend/src/test/kotlin/…/backend/ingesta/job/IngestionScheduleTest.kt` — create
  (gate; escenario 1 determinista).
- `backend/src/test/kotlin/…/backend/ingesta/job/IngestionJobTest.kt` — create
  (gate; orquestación, idempotencia con doble de repositorio, fallo parcial).
- `backend/src/test/kotlin/…/backend/ingesta/job/IngestionSchedulerTest.kt` — create
  (gate; tiempo virtual con `runTest`/`delay` inyectado).
- `backend/src/test/kotlin/…/backend/ingesta/job/IngestionJobLiveTest.kt` — create
  (opt-in `DB_LIVE_TEST=1`; real Postgres + sumario/parser de prueba).
- `docs/desarrollo-local.md` — modify; variables `INGESTA_*`, ejecución manual del
  job y pruebas opt-in.

Harness: `ARCHITECTURE.md`, `CONSTRAINTS.md` (si procede), `docs/adr/0004-…` +
índice, `feature_list.json`, `PROGRESS.md` (ver *Durable Documentation Impact*).

**Sin cambios** en `:shared`, `:composeApp`, la raíz del build,
`settings.gradle.kts`, `.github/workflows/ci.yml` ni migraciones Flyway.

## Visual Design Impact

- UI involved: no. Sin pantallas, tokens ni textos de UI.

## Durable Documentation Impact

- `ARCHITECTURE.md`: update — `:backend` añade `ingesta/job/` (job programado +
  scheduler) y **cablea condicionalmente** la ingesta/BD en `Application.kt`; la
  frontera **Backend → BOE** pasa de «solo cliente» a ejecutarse en runtime; el
  job asume el esquema aplicado.
- `CONSTRAINTS.md`: update (menor) — MUST durable: las **llamadas de red del
  backend fijan `HttpTimeout` explícito**; opcionalmente precisar que el job es
  idempotente por `id` (ya recogido) y que el arranque no depende de la BD (ya
  recogido). No duplicar reglas existentes.
- `AGENTS.md` (harness): not needed — no cambia flujo ni arranque estándar.
- **ADR `docs/adr/0004-ingesta-programada-interna.md`** (recomendado): registrar la
  decisión durable «scheduler interno por corrutina (sin cron externo), ventana
  9:30 + 18:00 en `Europe/Madrid` configurable por entorno, idempotencia por
  `upsert` de `id`, timeouts de red explícitos». Lo escribe el implementador/
  orquestador e inscribe el índice.
- Otros: `docs/desarrollo-local.md` (producto) — update; `README.md`/`ROADMAP.md`
  — not needed.

## Implementation Plan

1. `IngestionConfig` (env + validación) e `IngestionSchedule` (cálculo puro) con sus
   tests de gate.
2. `IngestionJob` + `IngestionResult` sobre las interfaces existentes; tests de
   gate (orquestación, idempotencia con doble, fallo parcial).
3. `IngestionScheduler` con reloj/`delay` inyectables; test de tiempo virtual.
4. `HttpTimeout` en las factorías de cliente; `call.close()` del `HttpClient` en
   el cierre (si procede).
5. Wiring condicional en `Application.kt` (DataSource + scheduler + cierre en
   `ApplicationStopped`); `implementation(coroutines-core)`.
6. Test opt-in `DB_LIVE_TEST=1`; ejecutar gate sin red/BD y capturar evidencia.
7. Actualizar `ARCHITECTURE.md`, `CONSTRAINTS.md`, ADR 0004 + índice,
   `docs/desarrollo-local.md`, `PROGRESS.md`, `feature_list.json`; commit/push/PR/CI
   los gestiona el orquestador.

## Implementation Tasks

- [ ] `IngestionConfig` (env `INGESTA_*` + validación fail-fast) e `IngestionSchedule`
      (`nextRun` estricto).
- [ ] `IngestionJob` + `IngestionResult`: sumario → parser → `save` (upsert) en
      `Dispatchers.IO`; fallo por entrada contado, no aborta.
- [ ] `IngestionScheduler`: bucle de corrutina con reloj/`delay` inyectables y
      log-resumen mínimo; nunca muere por excepción.
- [ ] `HttpTimeout` en `boeSumarioHttpClient()` y `boeTextoHttpClient()`; cierre
      del cliente HTTP.
- [ ] Wiring condicional en `Application.kt` (solo con DB configurada y
      habilitado) + cierre en `ApplicationStopped`; `coroutines-core` en
      `:backend`.
- [ ] Tests de gate: config, schedule, job (idempotencia + fallo parcial),
      scheduler (tiempo virtual).
- [ ] Test opt-in `DB_LIVE_TEST=1`: doble ejecución sin duplicar contra Postgres
      real.
- [ ] `ARCHITECTURE.md`, `CONSTRAINTS.md`, ADR 0004 + índice,
      `docs/desarrollo-local.md`, `PROGRESS.md`, `feature_list.json`.

## Verification Plan

Desde la raíz del producto (`..`, JDK 21 vía JBR/`JAVA_HOME`):

- **Gate sin red ni BD (Docker parado):** `./gradlew :backend:test --rerun-tasks
  -PskipClient` → BUILD SUCCESSFUL con `IngestionConfigTest`, `IngestionScheduleTest`,
  `IngestionJobTest` e `IngestionSchedulerTest` en verde (el opt-in se omite sin
  `DB_LIVE_TEST`). `./gradlew build --no-daemon -PskipClient`, `./gradlew test`,
  `./gradlew detekt` (Detekt + `:cpdCheck`) y `.harness/init.sh` → exit 0.
- **Scenario 1 (horario):** `IngestionScheduleTest` fija los cuatro instantes del
  escenario (09:00→09:30, 09:31→18:00, 18:01→mañana 09:30, y `now` == 09:30 →
  18:00) en `Europe/Madrid`.
- **Scenario 3 (idempotencia en gate):** `IngestionJobTest` ejecuta el job dos veces
  sobre un repositorio de doble en memoria y comprueba que el número de filas no
  cambia.
- **Scenario 6 (opt-in, BD real):** `cp .env.example .env && docker compose up -d`
  + `./gradlew :backend:flywayMigrate`; luego
  `DB_LIVE_TEST=1 ./gradlew :backend:test --tests '*IngestionJobLiveTest'` → verde
  (una fila por `id`, `actualizado_en` avanzado). Entorno limpiado después
  (`docker compose down -v`, `.env` borrado).
- **Arranque condicional (manual):** `./gradlew :backend:run` **sin**
  `POSTGRES_PASSWORD` → arranca y `/health` responde 200 (job omitido); con BD
  configurada, el log muestra el scheduler planificado. **No** se espera a las
  9:30 en real: la prueba del disparo es la unitaria.
- **CI:** sin cambios (sin red ni BD).
- **E2E:** no aplica — sin flujo de usuario ni endpoint nuevo.
- `init.sh` (harness): **no** se modifica.

## Evidence To Capture

- Salida de `./gradlew :backend:test` con `IngestionConfigTest`/`IngestionScheduleTest`/
  `IngestionJobTest`/`IngestionSchedulerTest` (recuento, 0 fallos) y el opt-in
  etiquetado.
- Escenario 1 con los cuatro instantes; escenario 3 con el recuento de filas
  invariante; escenario 6 con `flywayMigrate` y la consulta a `publicacion`
  (una fila por `id`, `actualizado_en` avanzado).
- Gate sin red ni BD: `build -PskipClient`, `test`, `detekt`, `init.sh`.
- Arranque `:backend:run` sin BD → `/health` 200; con BD → log del scheduler.
- Ficheros del commit `FT00009`, PR y run de CI; entradas en `PROGRESS.md` y
  `feature_list.json` (`evidence`).

## Validator Checklist

- [ ] Alcance acotado: `ingesta/job/` (config + schedule + job + scheduler),
      wiring condicional, `HttpTimeout` y tests; sin clasificación (FT00012), sin
      backfill (FT00011), sin alertas/observabilidad (FT00010), sin endpoints, sin
      migraciones nuevas.
- [ ] Escenarios 1–7 pasan; la idempotencia se demuestra con doble (gate) y con
      Postgres real (opt-in `DB_LIVE_TEST=1`).
- [ ] El cálculo del siguiente disparo es correcto para 9:30 y la segunda pasada
      (estricto), y el scheduler no muere por una excepción del job.
- [ ] Un fallo por entrada no aborta el job (se cuenta en `fallidas`); el fallo
      del sumario se reporta sin propagar.
- [ ] `Application.kt` arranca **sin** BD (job omitido, `/health` operativo);
      con BD configurada arranca el scheduler y se cierra en `ApplicationStopped`.
- [ ] `HttpTimeout` presente en ambas factorías de cliente HTTP.
- [ ] `return` único, sin `else if`, funciones ≤40 líneas y KDoc en todo lo nuevo.
- [ ] El gate sigue verde **sin BD** y sin red; `ARCHITECTURE.md`, `CONSTRAINTS.md`,
      ADR 0004, `docs/desarrollo-local.md`, `PROGRESS.md` y `feature_list.json`
      actualizados.
- [ ] No unrelated product behavior or extra feature work was added.

## Risks / Open Questions

- **Esquema aplicado.** El job necesita las tablas de FT00008; en local se aplican
  con `flywayMigrate` (la migración al arranque es de una feature posterior).
  Documentar y no asumir migración automática aquí.
- **Ventana de la segunda pasada.** Default `18:00`/`Europe/Madrid` configurable
  por env; si el dueño quiere otra, es cambio de config. Confirmar el default.
- **Dedup III ↔ V.B fina.** Fuera de alcance (requiere modelo de referencia/`control`
  que no se persiste). El *upsert* por `id` cubre reejecuciones y correcciones que
  conservan el `id`.
- **Coste de red en N100.** La segunda pasada re-parsea la misma fecha para aplicar
  correcciones; la optimización «omitir si ya existe» se difiere (perdería
  correcciones del BOE). Vigilar el tiempo de ejecución.
- **Cierre de recursos.** `DataSource` y `HttpClient` deben cerrarse en
  `ApplicationStopped`; un cierre mal hecho deja hilos/recursos vivos.
- **Naming.** Se mantienen `Ingesta*`/`Boe*`; si el dueño aplica la convención
  inglesa de FT00008, renombrar de forma consistente sin cambiar comportamiento.

## Implementation Note (FT00009, 2026-10-10)

Implementado por el `implementer` sin ampliar alcance; estado `passing`, pendiente
de validación independiente. Desviaciones/aclaraciones respecto al plan:

- **`IngestionJob` es interfaz + implementación** `DailyIngestionJob`
  (mismo fichero `IngestionJob.kt`), siguiendo el patrón del paquete
  (`BoeSumarioClient`/`BoeSumarioHttpClient`, `BoePublicacionParser`/
  `BoePublicacionHttpParser`). Así el scheduler depende de la interfaz y se prueba
  con un doble sin tocar la BD.
- **`IngestionConfig.fromEnv` recorta espacios** en los valores del entorno antes de
  validarlos (acepta `" false "`).
- **HikariCP falla rápido sin PostgreSQL**: `Database.createDataSource` valida la
  conexión al construir el pool, así que el arranque **con** `POSTGRES_PASSWORD`
  pero **sin** BD alcanzable registra `Ingesta no arrancada: Failed to initialize
  pool…` y el servidor sigue en pie (`/health` 200). El arranque **sin**
  `POSTGRES_PASSWORD` registra `Ingesta no arrancada: Contraseña de base de datos
  no definida…`. En ambos casos el arranque no bloquea (MUST). El log
  `Ingesta programada: horas=[09:30, 18:00] zona=Europe/Madrid` se observó con el
  PostgreSQL de `docker-compose` levantado.
- **Timeout de red** en ambas factorías: `connectTimeoutMillis` 10 s,
  `requestTimeoutMillis`/`socketTimeoutMillis` 30 s.
- **Entorno de verificación**: Docker de esta máquina corre en **Colima**
  (`DOCKER_HOST=unix://$HOME/.colima/default/docker.sock`); el `docker-compose` se
  levantó con `POSTGRES_PORT=55432` para no chocar con otros contenedores y se
  limpió con `docker compose down -v` (sin `.env` versionado).
- **Gate** (sin red ni BD): `:backend:test --rerun-tasks -PskipClient` → **80
  tests, 0 fallos** (19 nuevos: `IngestionConfigTest` 7, `IngestionScheduleTest` 5,
  `IngestionJobTest` 5, `IngestionSchedulerTest` 1, `IngestionJobLiveTest` 1 omitido por
  variable); `build --no-daemon -PskipClient`, `test` (3 módulos), `detekt`
  (+`:cpdCheck`) e `.harness/init.sh` → verdes. Opt-in `DB_LIVE_TEST=1` contra
  PostgreSQL real → verde.
- Durable: ADR `docs/adr/0004-ingesta-programada-interna.md` (+ índice),
  `ARCHITECTURE.md`, `CONSTRAINTS.md` (MUST de `HttpTimeout`), skill
  `ktor-backend-architecture`, `docs/desarrollo-local.md`.
