# Feature Implementation Spec: Backfill del histórico reciente

## Source Feature

- `id`: backfill-historico
- `ft_id`: FT00011
- `parts`: none (atómica; ~10 ficheros de producción + ~5 de test + docs; por debajo del límite de 30)
- `area`: ingesta-boe
- `depends_on`: ingesta-job-diario (FT00009, `accepted` y fusionada); indirectos cerrados: publicacion-persistencia (FT00008), boe-parser-publicacion (FT00007), boe-sumario-cliente (FT00006), bootstrap-postgres-pgvector (FT00003)
- `status`: passing (rama `feat/ft00011-backfill-historico` ya reclamada, local y `origin`; implementada y autoverificada, pendiente de validación independiente)
- `source`: `feature_list.json`

## Goal

Poblar el corpus histórico del **último año** de **todo el sumario del BOE**
(secciones I, II.A, II.B, III, IV, V.A, V.B y V.C) mediante un **proceso por lotes
one-shot** en `:backend` que reutiliza las piezas ya cerradas: `BoeSumarioClient`
(FT00006), `BoePublicacionParser` (FT00007), `PublicationRepository` (*upsert* por
`id`, FT00008) y `DailyIngestionJob` (FT00009). Es el cierre de `docs/roadmap.md`
0.2-T09 y deja el corpus listo para la clasificación (FT00012) y la búsqueda.

El backfill es **idempotente** (reejecutar no duplica: *upsert* por `id`) y
**reanudable** (si el proceso se interrumpe, al relanzarlo continúa donde lo
dejó). Se ejecuta como **herramienta de línea de comandos** (tarea Gradle
dedicada) con pausas y lotes configurables para la máquina única de 8 GB; **no**
se cablea en el arranque del servidor, **no** añade endpoints, **no** clasifica y
**no** indexa.

## Non-Goals

- **Clasificación curada y plazos** (valores) → FT00012; el parser sigue dejando
  `categoria = null` / `plazo = null`.
- **Embeddings, chunking e indexado vectorial** → FT00014–FT00016.
- **Wiring en el arranque del servidor** (`Application.kt` intacto) y **endpoints
  HTTP** nuevos (API pública → FT00026+). El backfill se lanza a mano con su tarea
  Gradle.
- **Migración automática al arrancar** y despliegue/`Dockerfile` → FT00041. El
  backfill asume el esquema aplicado (`./gradlew :backend:flywayMigrate`).
- **Cron/programación** del backfill: es one-shot (nada de cron externo ni
  scheduler interno).
- **Deduplicación III ↔ V.B** fina y versionado/consolidación (siguen diferidos;
  el *upsert* por `id` cubre reejecuciones).
- **Nuevas dependencias**: se reutilizan Ktor CIO, HikariCP/JDBC y
  `logstash-logback-encoder`.

## Job Story

Cuando pongo en marcha DatoPublico por primera vez (o noto que faltan días), quiero
cargar por lotes el histórico del último año de todo el BOE sin duplicar y
pudiendo reanudar si se interrumpe, para que la búsqueda y el feed tengan corpus
desde el primer día sin esperar a que se acumule día a día.

## Users And Permissions

- **Operador/dueño** (lanza el comando en la máquina única). Sin cuentas, sin
  datos personales, sin autenticación. Usa `POSTGRES_*` (fuente única) y la API
  pública del BOE (solo lectura); si falta `POSTGRES_PASSWORD`, falla en claro
  (fail-fast).
- El arranque del backend **no** cambia: no depende del backfill ni de la BD
  (MUST de `CONSTRAINTS.md`).

## Acceptance Scenarios

### Scenario 1: planificación del rango en lotes

Given un rango `[2024-01-01, 2024-01-10]` y un tamaño de lote de 4 días,
When se divide en lotes,
Then produce `[[01-01..01-04], [01-05..01-08], [01-09..01-10]]`: **cada día
aparece una sola vez**, en orden cronológico, y el último lote puede ser más corto.

### Scenario 2: rango corto persistido sin duplicar

Given un rango de 2 fechas y el `DailyIngestionJob` real con dobles de
sumario/parser y un repositorio en memoria (o el JDBC real, opt-in),
When el backfill ejecuta el rango dos veces,
Then en la segunda pasada el número de publicaciones almacenadas **no cambia**
(*upsert* por `id`) y ninguna queda duplicada.

### Scenario 3: reanudación tras interrupción

Given un rango de 5 fechas y un lote de 2, cuando el proceso se interrumpe tras
completar las 2 primeras (checkpoint persistido),
When se relanza con el mismo checkpoint,
Then solo procesa las 3 fechas restantes: las completadas se **omiten** y el
resultado del run reporta `skipped = 2`.

### Scenario 4: un fallo de fecha no aborta y se reintenta

Given un rango de 3 fechas donde una hace fallar el sumario (`error != null`),
When el backfill ejecuta,
Then las otras 2 se completan, la fallida se cuenta en `failed`, **no** se marca
completada y el run **no** propaga la excepción; al relanzar, solo se reintenta la
fallida.

### Scenario 5: checkpoint en fichero (round-trip y fail-fast)

Given un `FileBackfillCheckpointStore` sobre un fichero inexistente,
When se guarda un checkpoint (rango + fechas completadas) y se vuelve a leer,
Then se recupera idéntico; y un fichero con formato inválido falla con mensaje
claro (fail-fast), sin arrancar un backfill silenciosamente equivocado.

### Scenario 6: pausas y lotes para baja carga (tiempo virtual)

Given `BACKFILL_BATCH_DAYS` y `BACKFILL_DELAY_MS` configurados y un `delay`
inyectable,
When el runner procesa varios lotes,
Then respeta la pausa configurada entre fechas (verificable con tiempo virtual,
sin esperar en real) y el trabajo de E/S corre en `Dispatchers.IO`.

### Scenario 7: todo el sumario (ocho secciones), ninguna descartada

Given dobles de `BoeSumarioClient`/`BoePublicacionParser` que devuelven entradas de
las ocho secciones (I, II.A, II.B, III, IV, V.A, V.B, V.C),
When el backfill procesa el rango,
Then todas se persisten (la cobertura de secciones se **hereda** de FT00006/FT00007
y aquí no se filtra ninguna).

### Scenario 8: el gate sigue sin red ni BD

Given el runner sin PostgreSQL y sin red,
When se ejecuta `./gradlew build -PskipClient`, `./gradlew test`, `./gradlew detekt`
o `.harness/init.sh`,
Then todo está en verde (tests con dobles; los opt-in se omiten sin sus variables).

### Scenario 9: verificación real opt-in (fuera del gate)

Given el PostgreSQL de `docker-compose` migrado y `DB_LIVE_TEST=1`,
When el backfill ejecuta un rango corto (2–3 fechas) con sumario/parser de prueba,
se simula una interrupción y se relanza con el mismo checkpoint,
Then hay una fila por `id` (sin duplicados), la reanudación omite las fechas
completadas y `actualizado_en` avanza solo en las reprocesadas.

## Repository Research

### Files Inspected

- Harness: `feature_list.json` (FT00011; FT00009 `accepted`), `PROGRESS.md`
  (Session 039), `docs/feature-ids.md`, `docs/roadmap.md` §0.2.0 (`0.2-T09`,
  corpus 0.2), `docs/technical-discovery.md` (backfill por lotes en baja carga),
  `docs/risks-and-open-questions.md` (rendimiento del N100), `docs/domain-model.md`
  (Backfill), `CONTEXT.md` (§Backfill), `ARCHITECTURE.md`, `CONSTRAINTS.md`,
  `docs/desarrollo-local.md`, ADRs `0003`, `0004`, `0005`, specs
  `ingesta-job-diario.md`, `publicacion-persistencia.md`,
  `boe-parser-publicacion.md`, `ingesta-observabilidad.md`.
- Producto (`..`, rama `feat/ft00011-backfill-historico` reclamada; sin ficheros
  aún): `ingesta/job/{IngestionConfig,IngestionSchedule,IngestionJob,
  IngestionScheduler,IngestionLog,IngestionRunState}.kt`,
  `ingesta/sumario/{BoeSumarioClient,BoeSumarioHttpClient}.kt`,
  `ingesta/publicacion/BoePublicacionParser.kt` (interfaz + impl
  `BoePublicacionHttpParser`),
  `persistence/PublicationRepository.kt`, `infra/{Database,DatabaseConfig}.kt`,
  `Application.kt` (wiring condicional), `backend/build.gradle.kts` (tarea Flyway,
  `application` main, `loadDotEnv`/`resolveSetting`), `.gitignore`, `.env.example`.

### Existing Patterns To Follow

- **Orquestador `suspend` reutilizable**: `DailyIngestionJob.run(date)` ya hace
  *sumario → parser → upsert* de forma idempotente y tolerante a fallos por
  entrada; el backfill **no** reimplementa esa lógica, la reutiliza.
- **Config por entorno pura y testeable** (`fromEnv(env: Map<String,String> =
  System.getenv())`) con defaults no sensibles y **fail-fast**, patrón
  `IngestionConfig`/`DatabaseConfig`.
- **Puro vs. E/S**: cálculo de lotes y mapeo de eventos de log **puros** (unidad
  del gate); reloj/`delay`/dispatchers **inyectables** (precedente
  `IngestionScheduler`/`IngestionWatchdog`).
- **Logging JSON estructurado** con LogstashEncoder y
  `StructuredArguments.entries` (clave `event` estable), patrón `IngestionLog`.
- **Cableado de recursos**: `Database.createDataSource(DatabaseConfig.fromEnv())`
  y factorías `boeSumarioHttpClient()`/`boeTextoHttpClient()` con `HttpTimeout`
  explícito; cierre de pool y clientes al terminar (patrón `IngestionRuntime`).
- Estilo MUST: `return` único, sin `else if`, funciones ≤40 líneas, KDoc en
  castellano, identificadores en inglés (incluidos los nuevos `Backfill*`).

### Current Gaps

- No existe ningún mecanismo de backfill: no hay paquete `ingesta/backfill/`, ni
  planificador de rango, ni checkpoint, ni entrada de línea de comandos.
- La única forma de ingerir es el job programado (una fecha por ventana), inviable
  para poblar ~365 días.
- No hay estado persistente de progreso de ingesta.

## Technical Approach

Todo el trabajo nuevo vive en un paquete `ingesta/backfill/` de `:backend`, sin
tocar `:shared`, `:composeApp`, la raíz del build, `settings.gradle.kts`, el CI,
`Application.kt` ni migraciones Flyway. Nombres orientativos, en inglés.

1. **`ingesta/backfill/BackfillConfig.kt`** (puro, `fromEnv`): rango y ritmo.
   Claves con defaults no sensibles: `BACKFILL_FROM` (ISO; default `TO - 1 año`),
   `BACKFILL_TO` (ISO; default **hoy** en `IngestionConfig.zone`),
   `BACKFILL_BATCH_DAYS` (default `7`, entero > 0), `BACKFILL_DELAY_MS` (default
   `500`, entero ≥ 0) y `BACKFILL_STATE_FILE` (default `.backfill-state.txt`).
   Valida fechas (`FROM <= TO`, fail-fast) reutilizando `IngestionConfig.zone`.

2. **`ingesta/backfill/BackfillRange.kt`** (puro, sin E/S): `from`/`to`
   (inclusivos), `dates()` cronológico y `batches(batchDays): List<List<LocalDate>>`
   (último lote más corto). Es la unidad verificable del escenario 1.

3. **`ingesta/backfill/BackfillCheckpoint.kt`**: `data class BackfillCheckpoint(
   from, to, completedDates: Set<LocalDate>)` + interfaz `BackfillCheckpointStore {
   load(): BackfillCheckpoint?; save(checkpoint) }`. El runner solo reanuda si el
   `(from, to)` guardado coincide; si no, empieza de cero.

4. **`ingesta/backfill/FileBackfillCheckpointStore.kt`**: implementación en
   fichero de texto (una línea de rango `range=<from>..<to>` + una fecha ISO por
   línea, ordenadas). Escritura **atómica** (fichero temporal + `Files.move`
   `ATOMIC_MOVE`); fichero ausente → `null`; formato inválido → `IllegalStateException`
   con mensaje claro (fail-fast). Un fallo de escritura se registra como aviso y
   **no** aborta el run (el *upsert* hace seguro rehacer).

5. **`ingesta/backfill/BackfillRunner.kt`** (`suspend`, orquestador + `BackfillResult`):
   recorre los lotes de `BackfillRange`; por cada fecha no completada llama a
   `IngestionJob.run(date)` en `Dispatchers.IO`, respeta `delay` entre fechas y
   persiste el checkpoint tras cada lote. Reglas: una fecha cuenta como
   **completada** solo si `error == null` **y** `failed == 0`; si no, se registra y
   se **reintenta** en el siguiente run. Nunca propaga el fallo de una fecha. El
   resultado agrega `completed`, `failed`, `skipped` y `saved`.

6. **`ingesta/backfill/BackfillLog.kt`** (puro + emisión): eventos estructurados
   con clave `event` estable (`backfill.run.started`, `backfill.batch.completed`,
   `backfill.run.completed`, `backfill.date.failed`) y campos de primer nivel vía
   `StructuredArguments.entries`. `fields(...)` es puro y es la unidad de test del
   gate (precedente `IngestionLog.runFields`).

7. **`ingesta/backfill/BackfillMain.kt`**: `main()` de la herramienta one-shot.
   Construye `DatabaseConfig`/`DataSource` y los clientes HTTP (con `HttpTimeout`),
   compone `DailyIngestionJob` (reutilizado) y `BackfillRunner`, ejecuta el rango y
   **cierra** pool y clientes en un `finally`. Log de resumen final. Un fallo de
   configuración/BD sale con mensaje claro y código distinto de cero.

8. **`backend/build.gradle.kts`** (modify): tarea `JavaExec` `:backend:backfill`
   (main `…ingesta.backfill.BackfillMainKt`, `classpath` de `sourceSets["main"]`,
   pasa el entorno del proceso). **No** se engancha a `build`/`check`. Reutiliza el
   `main()` existente (`:backend:run`) sin cambiarlo.

9. **Documentación**: `docs/desarrollo-local.md` (producto) con el comando, las
   variables `BACKFILL_*`, el formato del checkpoint y las notas de baja carga.
   `.gitignore`: ignorar `.backfill-state.txt` (estado local, no versionado).

**Riesgos clave:** (a) el gate no puede probar red/BD — dobles + opt-in; (b) el
checkpoint es un fichero local de un solo host (no replica); (c) volumen y RAM
(~365 días en la N100) — lotes, pausa configurable y `Dispatchers.IO`; (d) la
duplicación de cableado mínima con `Application.kt` podría rozar `:cpdCheck` — se
extrae un helper pequeño si hiciera falta; (e) se asume el esquema migrado.

## Expected File Changes

Rutas en el repo de producto (`..`); nombres orientativos en inglés.

- `backend/src/main/kotlin/…/backend/ingesta/backfill/BackfillConfig.kt` — create.
- `backend/src/main/kotlin/…/backend/ingesta/backfill/BackfillRange.kt` — create.
- `backend/src/main/kotlin/…/backend/ingesta/backfill/BackfillCheckpoint.kt` — create
  (modelo + interfaz de store).
- `backend/src/main/kotlin/…/backend/ingesta/backfill/FileBackfillCheckpointStore.kt`
  — create.
- `backend/src/main/kotlin/…/backend/ingesta/backfill/BackfillRunner.kt` — create
  (orquestador + `BackfillResult`).
- `backend/src/main/kotlin/…/backend/ingesta/backfill/BackfillLog.kt` — create.
- `backend/src/main/kotlin/…/backend/ingesta/backfill/BackfillMain.kt` — create
  (CLI one-shot).
- `backend/build.gradle.kts` — modify; tarea `JavaExec` `:backend:backfill`.
- `.gitignore` — modify; `.backfill-state.txt`.
- `docs/desarrollo-local.md` — modify; comando, `BACKFILL_*` y checkpoint.
- `backend/src/test/kotlin/…/backend/ingesta/backfill/BackfillConfigTest.kt` — create
  (gate; defaults, overrides, rango inválido).
- `backend/src/test/kotlin/…/backend/ingesta/backfill/BackfillRangeTest.kt` — create
  (gate; escenario 1).
- `backend/src/test/kotlin/…/backend/ingesta/backfill/FileBackfillCheckpointStoreTest.kt`
  — create (gate; escenario 5).
- `backend/src/test/kotlin/…/backend/ingesta/backfill/BackfillRunnerTest.kt` — create
  (gate; escenarios 2, 3, 4, 6, 7 con dobles).
- `backend/src/test/kotlin/…/backend/ingesta/backfill/BackfillLiveTest.kt` — create
  (opt-in `DB_LIVE_TEST=1`; escenario 9).

Harness: `ARCHITECTURE.md`, `CONSTRAINTS.md` (si procede), `docs/adr/0006-…` +
índice, `feature_list.json`, `PROGRESS.md` (ver *Durable Documentation Impact*).

**Sin cambios** en `Application.kt`, `:shared`, `:composeApp`, la raíz del build,
`settings.gradle.kts`, `.github/workflows/ci.yml` ni migraciones Flyway.

## Visual Design Impact

- UI involved: no. Sin pantallas, tokens ni textos de UI (herramienta de backend).

## Durable Documentation Impact

- `ARCHITECTURE.md`: update — `:backend` añade `ingesta/backfill/` (backfill
  one-shot por lotes que **reutiliza** `DailyIngestionJob` y el *upsert*; checkpoint
  local en fichero); se explicita que **no** se cablea en el arranque y que se lanza
  con una tarea Gradle.
- `CONSTRAINTS.md`: update (menor) — MUST durable: el backfill es **one-shot,
  idempotente por `upsert` de `id` y reanudable**; se ejecuta por lotes con pausa
  en baja carga y **no** se cablea al arranque ni cambia las reglas del gate.
  (No duplicar las reglas ya existentes de upsert, sin red en el gate y sin BD en
  el gate.)
- `AGENTS.md` (harness): not needed — no cambia el flujo ni el arranque estándar.
- **ADR `docs/adr/0006-backfill-one-shot-lotes.md`** (recomendado): registrar la
  decisión durable «backfill como herramienta CLI + tarea Gradle (sin cron ni
  wiring en el servidor), reutilizando el job diario; progreso en checkpoint local
  y reanudación; ritmo por lotes para la máquina única». Inscribir en el índice
  `docs/adr/README.md`. El planner **no** lo crea; lo escribe el implementador.
- Otros: `docs/desarrollo-local.md` (producto) — update; `README.md`/`ROADMAP.md`
  — not needed.

## Implementation Plan

1. `BackfillConfig` (rango/ritmo + validación) y `BackfillRange` (lotes) con sus
   tests de gate.
2. `BackfillCheckpoint` + `FileBackfillCheckpointStore` (round-trip y fail-fast) y
   su test.
3. `BackfillLog` (eventos + `fields` puro) y su cobertura en `BackfillRunnerTest`.
4. `BackfillRunner` reutilizando `IngestionJob`, con `delay`/dispatcher inyectables;
   tests de ejecución, reanudación, fallo por fecha y ocho secciones.
5. `BackfillMain` (CLI) + tarea `:backend:backfill`; `.gitignore`.
6. Test opt-in `DB_LIVE_TEST=1` (rango corto + reanudación) contra Postgres real;
   ejecutar el gate sin red ni BD y capturar evidencia.
7. Actualizar `ARCHITECTURE.md`, `CONSTRAINTS.md`, ADR 0006 + índice,
   `docs/desarrollo-local.md`, `PROGRESS.md` y `feature_list.json`; commit/push/PR/CI
   los gestiona el orquestador.

## Implementation Tasks

- [ ] `BackfillConfig` (env `BACKFILL_*`, default último año y hoy en
      `IngestionConfig.zone`, fail-fast).
- [ ] `BackfillRange` (`dates()`/`batches()` puros; último lote más corto).
- [ ] `BackfillCheckpoint` + `BackfillCheckpointStore` + `FileBackfillCheckpointStore`
      (escritura atómica, ausente → `null`, formato inválido → fail-fast).
- [ ] `BackfillLog` con `fields` puro y eventos `backfill.*`.
- [ ] `BackfillRunner` (`suspend`): lotes, `IngestionJob.run`, pausa inyectable,
      reanudación por checkpoint, fallo por fecha no aborta, `BackfillResult`.
- [ ] `BackfillMain` (CLI) que compone y **cierra** pool/clientes; tarea Gradle
      `:backend:backfill`.
- [ ] Tests de gate: config, rango, checkpoint, runner (ejecución/reanudación/
      fallo/secciones/tiempo virtual de la pausa).
- [ ] Test opt-in `DB_LIVE_TEST=1`: rango corto sin duplicar y reanudación real.
- [ ] `.gitignore`, `docs/desarrollo-local.md`, `ARCHITECTURE.md`,
      `CONSTRAINTS.md`, ADR 0006 + índice, `PROGRESS.md`, `feature_list.json`.

## Verification Plan

Desde la raíz del producto (`..`, JDK 21 vía JBR/`JAVA_HOME`):

- **Gate sin red ni BD (Docker parado):** `./gradlew :backend:test --rerun-tasks
  -PskipClient` → BUILD SUCCESSFUL con `BackfillConfigTest`, `BackfillRangeTest`,
  `FileBackfillCheckpointStoreTest` y `BackfillRunnerTest` en verde (el opt-in se
  omite sin `DB_LIVE_TEST`). Después `./gradlew build --no-daemon -PskipClient`,
  `./gradlew test`, `./gradlew detekt` (Detekt + `:cpdCheck`) y
  `env -u JAVA_HOME .harness/init.sh` → exit 0.
- **Scenario 1:** `BackfillRangeTest` fija `[2024-01-01..2024-01-10]` con lote 4 y
  comprueba los tres lotes y la cobertura sin repeticiones.
- **Scenarios 2/3/4/6/7:** `BackfillRunnerTest` con dobles de `IngestionJob`
  (o sumario/parser/repositorio en memoria) y `delay` virtual: ejecución doble sin
  duplicar; interrupción + reanudación (`skipped`); fecha fallida aislada y
  reintentada; pausa respetada con `runTest`/`advanceTimeBy`; ocho secciones.
- **Escenario 5:** `FileBackfillCheckpointStoreTest` en un directorio temporal:
  round-trip, fichero ausente y formato inválido (fail-fast).
- **Escenario 9 (opt-in, BD real):** `cp .env.example .env && docker compose up -d`
  + `./gradlew :backend:flywayMigrate`; luego
  `DB_LIVE_TEST=1 ./gradlew :backend:test --tests '*BackfillLiveTest'` → verde
  (una fila por `id`, reanudación omite lo completado). Entorno limpiado después
  (`docker compose down -v`, `.env` borrado, checkpoint de prueba borrado).
- **Ejecución manual (CLI):** con BD migrada,
  `BACKFILL_FROM=2024-01-01 BACKFILL_TO=2024-01-05 ./gradlew :backend:backfill`;
  observar el JSON estructurado (`event=backfill.*`) en stdout y las filas en
  `publicacion`. Reejecutar no duplica y avanza por el checkpoint. No se apunta a
  un año completo en la verificación (coste/tiempo).
- **CI:** sin cambios (sin red ni BD).
- **E2E:** no aplica — sin flujo de usuario ni endpoint nuevo.
- `init.sh` (harness): **no** se modifica.

## Evidence To Capture

- Salida de `./gradlew :backend:test` con `BackfillConfigTest`/`BackfillRangeTest`/
  `FileBackfillCheckpointStoreTest`/`BackfillRunnerTest` (recuento, 0 fallos) y el
  opt-in etiquetado.
- Escenario 1 con los lotes; escenario 3 con `skipped` y las fechas omitidas;
  escenario 5 con el round-trip y el fail-fast de formato inválido.
- Escenario 9 con `flywayMigrate`, el conteo de filas por `id` y la reanudación.
- Ejecución manual del CLI: `event=backfill.*` en stdout y consulta a `publicacion`.
- Gate sin red ni BD: `build -PskipClient`, `test`, `detekt`, `init.sh`.
- Ficheros del commit `FT00011`, PR y run de CI; entradas en `PROGRESS.md` y
  `feature_list.json` (`evidence`).

## Validator Checklist

- [ ] Alcance acotado: solo `ingesta/backfill/` (config + rango + checkpoint +
      runner + log + CLI) + tarea Gradle + `.gitignore` + tests/docs; **sin**
      clasificación (FT00012), embeddings/chunking (FT00014–16), endpoints ni
      wiring en `Application.kt`, sin migraciones nuevas, sin cron.
- [ ] Escenarios 1–9 pasan; la idempotencia y la reanudación se demuestran con
      dobles (gate) y contra Postgres real (opt-in `DB_LIVE_TEST=1`).
- [ ] El runner **reutiliza** `DailyIngestionJob`/`PublicationRepository` (no
      reimplementa la ingesta) y cubre las **ocho** secciones sin filtrar.
- [ ] Una fecha completada requiere `error == null` **y** `failed == 0`; un fallo
      de fecha no aborta y se reintenta; la reanudación omite lo completado y solo
      aplica si `(from, to)` coincide con el checkpoint.
- [ ] `FileBackfillCheckpointStore` escribe de forma atómica, tolera el fichero
      ausente y falla con mensaje claro ante formato inválido.
- [ ] El CLI cierra pool y clientes HTTP; el backfill **no** se cablea al arranque
      y `Application.kt` sigue intacto; la tarea `:backend:backfill` **no** está en
      `build`/`check`.
- [ ] La pausa por lote/fecha es configurable y verificable con tiempo virtual; el
      trabajo de E/S corre en `Dispatchers.IO`.
- [ ] `return` único, sin `else if`, funciones ≤40 líneas, KDoc en castellano,
      identificadores en inglés; ningún `@Serializable` nuevo (no aplica
      `@SerialName`).
- [ ] El gate sigue verde **sin BD** y sin red; `ARCHITECTURE.md`,
      `CONSTRAINTS.md`, ADR 0006 + índice, `docs/desarrollo-local.md`,
      `PROGRESS.md` y `feature_list.json` actualizados.
- [ ] No unrelated product behavior or extra feature work was added.

## Risks / Open Questions

- **Checkpoint local vs. en base de datos.** Se elige un **fichero** local (la
  máquina de despliegue es única y no se quiere añadir una tabla/migración al
  alcance). No replica ni sobrevive a un borrado del fichero; el *upsert* hace
  seguro rehacer. *Confirmar* que este compromiso es aceptable para el operador;
  si se exige durabilidad en la BD, sería un cambio de alcance (migración V3 +
  repositorio de checkpoint).
- **Volumen y RAM (N100).** ~365 días de todo el BOE: horas de ejecución. Se
  mitiga con lotes, pausa configurable y horario de baja carga; medir tiempos
  (riesgo abierto ya registrado en `docs/risks-and-open-questions.md`).
- **Coste de red.** Un `GET` de sumario por día y un `GET` de texto por
  publicación; el *upsert* no evita la descarga. La optimización «omitir si ya hay
  filas» se difiere (perdería correcciones del BOE).
- **Fallos parciales de fecha.** Una fecha con `failed > 0` se reintenta en el
  siguiente run; un fallo permanente se repetiría cada ejecución (visible en los
  eventos `backfill.date.failed`). Aceptable para una herramienta manual.
- **Duplicación mínima con `Application.kt`.** El CLI compone el mismo job/pool que
  el arranque; si `:cpdCheck` lo señala, extraer un helper pequeño y compartido
  (sin tocar la lógica del servidor).
- **Nombres de variables de entorno.** Se proponen `BACKFILL_*` (código nuevo en
  inglés) frente a las históricas `INGESTA_*` (castellano); *confirmar* la
  preferencia antes de implementar.
