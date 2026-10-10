# Feature Implementation Spec: Observabilidad de la ingesta diaria

## Source Feature

- `id`: ingesta-observabilidad
- `ft_id`: FT00010
- `parts`: none (atómica; ~9 ficheros de producción + ~6 de test + docs; por debajo del límite de 30)
- `area`: ingesta-boe
- `depends_on`: ingesta-job-diario (FT00009, `accepted` y fusionada)
- `status`: not_started
- `source`: `feature_list.json` (notas: `docs/roadmap.md` 0.2-T07)

## Goal

Dar **observabilidad** al job diario de ingesta de FT00009: cada ejecución deja
un **evento de log estructurado** (JSON de primer nivel) con la fecha y las
publicaciones persistidas, y un **vigilante interno** emite una **alerta** si una
de las ventanas esperadas (09:30 o segunda pasada) pasa **sin que la ingesta se
haya intentado** o si una ejecución **falla**. Es la decisión de operación de la
sección «Observability» de `docs/technical-discovery.md` (0.2-T07), sin añadir
telemetría ni servicios externos.

El alcance es **solo observabilidad**: no clasifica, no hace backfill, no cambia
el comportamiento de la ingesta, no añade endpoints y no emite datos personales
(no hay usuarios).

## Non-Goals

- **Clasificación curada y plazos** de las publicaciones → FT00012.
- **Backfill del histórico** (recuperar ventanas perdidas) → FT00011.
- **Alertas externas** (email, push, PagerDuty, webhooks) o **telemetría/
  analítica de uso**: prohibidas por `CONSTRAINTS.md`. La alerta es un log
  estructurado de nivel `ERROR` con un evento estable (canal de operación).
- **Distinguir altas de actualizaciones** (`created` vs `updated`): el *upsert*
  por `id` (FT00008) no lo reporta hoy; requeriría cambiar `PublicationRepository`
  y su SQL. Se difiere. «Publicaciones nuevas de la ejecución» = publicaciones
  **persistidas para la fecha ingerida** (`saved`), que es lo que ya produce
  `IngestionResult`.
- **Endpoint de estado/health** nuevo o ampliación de `GET /health` → fuera de
  alcance (FT00004 y API pública posterior).
- **Watchdog de procesos caídos**: si el proceso no está en marcha no puede
  alertar; la recuperación de una ventana perdida es del backfill (FT00011).

## Job Story

Cuando el job de ingesta se ejecuta (o **debería** ejecutarse) a las 9:30 y en
la segunda pasada, quiero que deje un registro estructurado de lo ingerido y que
se advierta si una ventana se queda sin ejecutar, para detectar de forma
temprana que el corpus del día se ha quedado incompleto sin tener que revisar la
base de datos a mano.

## Users And Permissions

- **Operador/dueño** (lee los logs JSON de stdout) y el proceso del backend.
  Sin cuentas, sin datos personales, sin autenticación, sin servicios externos.
- El arranque sigue **sin depender de la BD**: si la ingesta no se cablea (sin
  `POSTGRES_PASSWORD` o `INGESTA_ENABLED=false`), el vigilante tampoco arranca y
  `/health` sigue operativo (MUST de `CONSTRAINTS.md`).

## Acceptance Scenarios

### Scenario 1: log estructurado de una ejecución correcta

Given un `IngestionResult` de `2026-10-09` con `totalEntries=205`, `saved=205`,
`failed=0` y sin error,
When se construye el evento de ejecución,
Then sus campos son `event=ingestion.run.completed`, `ingestion_date=2026-10-09`,
`total_entries=205`, `publications_saved=205` y `publications_failed=0`.

### Scenario 2: una ejecución fallida emite alerta

Given un resultado con `error="BOE caído"` (fallo del sumario),
When se construye el evento de ejecución,
Then el evento es `event=ingestion.run.failed` con `error="BOE caído"` a nivel
`ERROR`/`WARN`.

### Scenario 3: se detecta la ventana de la tarde sin ejecutar

Given horario `{09:30, 18:00}` en `Europe/Madrid`, `startedAt` = 08:00 (local) del
día, `grace` = 30 min, ventanas intentadas `{09:30}` y `now` = 19:00 (local),
When se calculan las ventanas perdidas,
Then el resultado es `[18:00]`.

### Scenario 4: no hay falsos positivos si ambas ventanas se ejecutaron

Given el mismo horario, `startedAt` 08:00, `grace` 30 min, ventanas intentadas
`{09:30, 18:00}` y `now` 19:00,
When se calculan las ventanas perdidas,
Then el resultado es vacío.

### Scenario 5: las ventanas anteriores al arranque no se vigilan

Given `startedAt` = 10:00 (local, después de la primera ventana), `grace` 30 min,
ninguna ventana intentada y `now` = 19:00,
When se calculan las ventanas perdidas,
Then el resultado es `[18:00]` (la 09:30 es anterior al arranque y no se reclama).

### Scenario 6: la ventana aún dentro de su margen no se considera perdida

Given `startedAt` 08:00, `grace` 30 min, intentadas `{09:30}` y `now` 18:15,
When se calculan las ventanas perdidas,
Then el resultado es vacío (18:00 + 30 min todavía no ha vencido).

### Scenario 7: el vigilante alerta una sola vez por ventana (tiempo virtual)

Given un `IngestionWatchdog` con reloj y `delay` virtuales y un sumidero de
alertas de prueba, con solo la ventana de 09:30 intentada,
When se avanza el tiempo más allá de 18:00 + `grace` y se ejecutan varios ticks,
Then el sumidero recibe **exactamente una** alerta para la ventana de 18:00 (sin
repetirla en los ticks siguientes).

### Scenario 8: el gate sigue sin red ni BD

Given el runner sin PostgreSQL y sin red,
When se ejecuta `./gradlew :backend:test -PskipClient`, `./gradlew build -PskipClient`,
`./gradlew detekt` o `.harness/init.sh`,
Then todo está en verde y ningún test abre sockets ni toca la base de datos.

## Repository Research

### Files Inspected

- Harness: `feature_list.json` (FT00010; FT00009 `accepted`), `docs/feature-ids.md`
  (FT00010 registrado), `docs/roadmap.md` §0.2 `0.2-T07`, `docs/technical-discovery.md`
  §Observability, `docs/risks-and-open-questions.md`, `CONSTRAINTS.md` §«Operación»/
  «Producto y datos», `ARCHITECTURE.md`, `docs/adr/0004-ingesta-programada-interna.md`,
  `docs/specs/ingesta-job-diario.md`, skill `ktor-backend-architecture`.
- Producto (`..`, rama `feat/ft00010-ingesta-observabilidad` reclamada):
  `ingesta/job/{IngestionConfig,IngestionSchedule,IngestionJob,IngestionScheduler}.kt`,
  `Application.kt`, `infra/{AppConfig,DatabaseConfig,Database}.kt`,
  `persistence/PublicationRepository.kt`, `resources/logback.xml`,
  `backend/build.gradle.kts`, `gradle/libs.versions.toml`, tests de
  `ingesta/job/` (`IngestionConfigTest`, `IngestionScheduleTest`, `IngestionJobTest`,
  `IngestionSchedulerTest`).

### Existing Patterns To Follow

- **Config por entorno pura y testeable** (`IngestionConfig.fromEnv(env)`), con
  defaults no sensibles y fail-fast (`CONSTRAINTS.md` §«Operación»).
- **Logging JSON** vía LogstashEncoder (`resources/logback.xml`), una línea por
  evento en stdout, con `customFields` `app`/`env`. La dependencia
  `logstash-logback-encoder` 8.0 ya está en `:backend`; su utilidad
  `StructuredArguments.entries(Map)` emite campos JSON de primer nivel.
- **Scheduler interno por corrutina** con reloj (`now`) y espera (`delay`)
  **inyectables** para probar con **tiempo virtual** (`IngestionSchedulerTest`,
  `runTest`/`advanceTimeBy`). El vigilante sigue el mismo patrón.
- **Puros y sin E/S** para lo verificable (`IngestionSchedule.nextRun`); el
  cálculo de ventanas perdidas será igualmente puro.
- **Cableado condicional y no bloqueante** en `Application.kt`; cierre vía
  cancelación del `CoroutineScope` en `ApplicationStopped`.
- Estilo MUST: `return` único, sin `else if`, funciones ≤40 líneas, KDoc en
  castellano e identificadores en inglés.

### Current Gaps

- El `IngestionScheduler` ya registra un **log-resumen plano**
  (`logger.info("Ingesta de {}: total={}, ...")`): el mensaje va dentro del campo
  `message` del JSON, sin campos estructurados ni evento estable.
- **No existe ninguna alerta** si una ventana pasa sin ejecutarse, ni distinción
  explícita de una ejecución fallida con un evento de nivel `ERROR`.
- `IngestionSchedule` mantiene `times`/`zone` **privados** y no expone las
  ventanas de un día; el vigilante necesita enumerarlas.
- No existe estado de «ventana intentada» que el vigilante pueda consultar.

## Technical Approach

Todo el trabajo vive en `ingesta/job/` (observabilidad de la ingesta), sin tocar
`:shared`, `:composeApp`, la raíz del build, `settings.gradle.kts`, CI ni
migraciones. Nombres orientativos; el implementer los fija en inglés.

1. **`IngestionSchedule.kt` (modify)**: exponer `val zone: ZoneId` (getter
   público) y añadir `fun runsOn(date: LocalDate): List<ZonedDateTime>` que
   devuelve, ordenadas, las ventanas (`times`) de `date` en `zone`. Puro y
   reutilizable por el detector.

2. **`IngestionConfig.kt` (modify)**: añadir `grace: Duration` desde
   `INGESTA_GRACE_MINUTES` (default **30**), validada como entero > 0 con
   fail-fast y mensaje claro (mismo patrón que `parseTime`). Reutiliza
   `firstNonBlank`.

3. **`IngestionLog.kt` (create)**: evento estructurado de ejecución.
   - Constantes estables: `EVENT_RUN_COMPLETED = "ingestion.run.completed"`,
     `EVENT_RUN_FAILED = "ingestion.run.failed"` y claves de campo
     (`event`, `ingestion_date`, `total_entries`, `publications_saved`,
     `publications_failed`, `error`).
   - `fun runFields(result: IngestionResult): Map<String, Any?>` **puro**: elige
     el evento según `result.error` (`null` → completado; no nulo → fallido) y
     mapea los campos. Es la unidad de test del gate.
   - `fun logRun(logger: Logger, result: IngestionResult)`: emite el evento con
     `StructuredArguments.entries(runFields(result))`; nivel `INFO` si completado,
     `ERROR` si falló (una ejecución fallida es una «ingesta ausente»).

4. **`IngestionRunState.kt` (create)**: estado en memoria, seguro para
   concurrencia (p. ej. `ConcurrentHashMap.newKeySet<Instant>()`), con
   `markAttempted(window: Instant)` e `isAttempted(window: Instant): Boolean`.
   El scheduler marca la ventana **antes** de ejecutarla (para no alertar durante
   una ejecución larga).

5. **`MissedIngestionDetector.kt` (create)**: **puro**.
   `fun detect(now: ZonedDateTime, startedAt: Instant, schedule: IngestionSchedule, isAttempted: (Instant) -> Boolean, grace: Duration): List<ZonedDateTime>`
   devuelve, de `schedule.runsOn(now.toLocalDate())`, las ventanas `w` que cumplen
   `w.toInstant() <= now.toInstant() - grace`, `w.toInstant() >= startedAt` y
   `!isAttempted(w.toInstant())`. Las ventanas anteriores a `startedAt` (proceso
   aún no en marcha) no se reclaman.

6. **`IngestionAlertSink.kt` (create)**: interfaz
   `fun alert(missed: ZonedDateTime)` + implementación por defecto
   `LoggingAlertSink` que emite `event=ingestion.missed` a `ERROR` con la fecha,
   la ventana y `grace` (vía `StructuredArguments`). Inyectable para tests.

7. **`IngestionWatchdog.kt` (create)**: bucle de corrutina con `now`/`delay`
   inyectables. Cada `interval` (constante interna por defecto 5 min, parametrizable
   en constructor) calcula las ventanas perdidas con `MissedIngestionDetector` y
   llama a `sink.alert(window)` **una sola vez por ventana** (dedupe con un
   `MutableSet<Instant>`), sin morir por excepción. No usa Ktor scheduling.

8. **`IngestionScheduler.kt` (modify)**: recibe `runState` y `logger`; en
   `runWindow` marca la ventana (`runState.markAttempted(next.toInstant())`) antes
   de `job.run(date)`, y sustituye `logSummary` por `IngestionLog.logRun`. Se
   mantiene el `catch` que no mata el bucle.

9. **`Application.kt` (modify)**: crea `IngestionRunState`, se lo pasa al
   scheduler y arranca el `IngestionWatchdog` en el **mismo** `CoroutineScope`
   (se cancela en `ApplicationStopped`, ya existente). Añade el log de arranque
   con la gracia configurada. Sin recursos nuevos que cerrar.

**Riesgos clave:** (a) el canal de alerta es un log JSON de stdout (no hay
servicios externos admitidos) — un monitor de logs debe vigilar el evento
`ingestion.missed`/`ingestion.run.failed`; (b) el vigilante solo cubre ventanas
mientras el proceso está vivo (arranque tardío → ventana no vigilada, la recupera
FT00011); (c) distinguir altas/actualizaciones queda diferido (necesita cambiar
el repositorio); (d) el gate no puede probar el JSON real de Logstash en firme, se
prueba el mapeo **puro** de campos.

## Expected File Changes

Rutas en el repo de producto (`..`); nombres orientativos en inglés.

- `backend/src/main/kotlin/…/backend/ingesta/job/IngestionSchedule.kt` — modify;
  `zone` público + `runsOn(date)`.
- `backend/src/main/kotlin/…/backend/ingesta/job/IngestionConfig.kt` — modify;
  `grace` (`INGESTA_GRACE_MINUTES`, default 30) + validación.
- `backend/src/main/kotlin/…/backend/ingesta/job/IngestionLog.kt` — create;
  eventos estructurados + `runFields` puro.
- `backend/src/main/kotlin/…/backend/ingesta/job/IngestionRunState.kt` — create;
  ventanas intentadas en memoria.
- `backend/src/main/kotlin/…/backend/ingesta/job/MissedIngestionDetector.kt` —
  create; detección pura de ventanas perdidas.
- `backend/src/main/kotlin/…/backend/ingesta/job/IngestionAlertSink.kt` — create;
  interfaz + emisión de la alerta `ingestion.missed`.
- `backend/src/main/kotlin/…/backend/ingesta/job/IngestionWatchdog.kt` — create;
  bucle de corrutina con reloj/`delay` inyectables.
- `backend/src/main/kotlin/…/backend/ingesta/job/IngestionScheduler.kt` — modify;
  marcar la ventana y emitir el evento estructurado.
- `backend/src/main/kotlin/…/backend/Application.kt` — modify; cableado del estado
  y del vigilante en el scope existente.
- `backend/src/test/kotlin/…/backend/ingesta/job/IngestionLogTest.kt` — create
  (gate; escenarios 1–2).
- `backend/src/test/kotlin/…/backend/ingesta/job/MissedIngestionDetectorTest.kt` —
  create (gate; escenarios 3–6).
- `backend/src/test/kotlin/…/backend/ingesta/job/IngestionWatchdogTest.kt` — create
  (gate; escenario 7 con tiempo virtual y sumidero de prueba).
- `backend/src/test/kotlin/…/backend/ingesta/job/IngestionConfigTest.kt` — modify;
  cubrir `grace` (default, override, inválido).
- `backend/src/test/kotlin/…/backend/ingesta/job/IngestionSchedulerTest.kt` —
  modify; comprobar que la ventana queda marcada como intentada.
- `docs/desarrollo-local.md` — modify; `INGESTA_GRACE_MINUTES`, eventos
  estructurados y cómo leerlos/depurarlos.

Harness: `ARCHITECTURE.md`, `CONSTRAINTS.md`, `docs/adr/0005-…` + índice,
`feature_list.json`, `PROGRESS.md` (ver *Durable Documentation Impact*).

**Sin cambios** en `:shared`, `:composeApp`, la raíz del build,
`settings.gradle.kts`, `.github/workflows/ci.yml`, migraciones Flyway ni
`logback.xml` (los campos estructurados van por `StructuredArguments`, no por
configuración).

## Visual Design Impact

- UI involved: no. Sin pantallas, tokens ni textos de UI (feature de backend).

## Durable Documentation Impact

- `ARCHITECTURE.md`: update — `ingesta/job/` añade observabilidad (evento
  estructurado por ejecución y vigilante de ventanas perdidas) y `Application.kt`
  arranca el vigilante en el mismo scope condicional; canal de alerta = log
  `ERROR` estructurado, sin telemetría.
- `CONSTRAINTS.md`: update (menor) — MUST durable: la observabilidad de la
  ingesta usa **eventos de log JSON con clave `event` estable** y la alerta de
  ingesta ausente es un log `ERROR`; **sin** alertas externas ni telemetría de
  uso (no duplicar la regla ya existente de «sin analítica/telemetría»).
- `AGENTS.md` (harness): not needed — no cambia flujo, arranque ni comandos.
- **ADR `docs/adr/0005-observabilidad-ingesta-logs-watchdog.md`** (recomendado):
  registrar la decisión durable «observabilidad de la ingesta por logs
  estructurados + vigilante interno; alerta = log `ERROR` con evento estable;
  sin alerting externo ni telemetría en la 1.0.0; `INGESTA_GRACE_MINUTES`
  configurable». Inscribir en el índice de `docs/adr/README.md`.
- Otros: `docs/desarrollo-local.md` (producto) — update; `README.md`/`ROADMAP.md`
  — not needed.

## Implementation Plan

1. `IngestionSchedule.runsOn`/`zone` + `IngestionConfig.grace`; ajustar
   `IngestionConfigTest`.
2. `IngestionLog` (eventos + `runFields`) y su test de gate.
3. `IngestionRunState`, `MissedIngestionDetector` y sus tests (escenarios 3–6).
4. `IngestionAlertSink` + `IngestionWatchdog`; test con tiempo virtual (escenario 7).
5. Integrar en `IngestionScheduler` (marcar intento + evento estructurado) y en
   `Application.kt` (scope/cancelación); actualizar `IngestionSchedulerTest`.
6. Ejecutar el gate sin red ni BD y capturar evidencia; actualizar
   `docs/desarrollo-local.md`, `ARCHITECTURE.md`, `CONSTRAINTS.md`, ADR 0005 +
   índice, `PROGRESS.md` y `feature_list.json`; commit/push/PR/CI los gestiona el
   orquestador.

## Implementation Tasks

- [ ] `IngestionSchedule.runsOn(date)` + `zone` público.
- [ ] `IngestionConfig.grace` (`INGESTA_GRACE_MINUTES`, default 30, fail-fast).
- [ ] `IngestionLog` con `runFields` puro y emisión estructurada
      (`ingestion.run.completed` / `ingestion.run.failed`).
- [ ] `IngestionRunState` (ventanas intentadas) y su integración en el scheduler.
- [ ] `MissedIngestionDetector.detect` puro (ventanas pasadas + gracia, no
      intentadas, no anteriores al arranque).
- [ ] `IngestionAlertSink` + `IngestionWatchdog` (corrutina con reloj/`delay`
      inyectables, dedupe por ventana, nunca muere).
- [ ] Cableado en `Application.kt` (mismo scope condicional; cierre en
      `ApplicationStopped`).
- [ ] Tests de gate: `IngestionLogTest`, `MissedIngestionDetectorTest`,
      `IngestionWatchdogTest`; ampliar `IngestionConfigTest`/`IngestionSchedulerTest`.
- [ ] `docs/desarrollo-local.md`, `ARCHITECTURE.md`, `CONSTRAINTS.md`, ADR 0005 +
      índice, `PROGRESS.md`, `feature_list.json`.

## Verification Plan

Desde la raíz del producto (`..`, JDK 21 vía JBR/`JAVA_HOME`):

- **Gate sin red ni BD (Docker parado):** `./gradlew :backend:test --rerun-tasks
  -PskipClient` → BUILD SUCCESSFUL con `IngestionLogTest`,
  `MissedIngestionDetectorTest`, `IngestionWatchdogTest`,
  `IngestionConfigTest` e `IngestionSchedulerTest` en verde. Después
  `./gradlew build --no-daemon -PskipClient`, `./gradlew test`, `./gradlew detekt`
  (Detekt + `:cpdCheck`) y `env -u JAVA_HOME .harness/init.sh` → exit 0.
- **Escenarios 1–2:** `IngestionLogTest` comprueba los campos de
  `runFields` para un resultado correcto y para uno con `error`.
- **Escenarios 3–6:** `MissedIngestionDetectorTest` fija los cuatro instantes
  (ventana perdida, sin perdidas, ventana anterior al arranque, dentro de gracia)
  en `Europe/Madrid`.
- **Escenario 7:** `IngestionWatchdogTest` con `runTest`/`advanceTimeBy` avanza
  más allá de `18:00 + grace` y comprueba que el sumidero de prueba recibe una
  única alerta por ventana.
- **Log JSON real (manual, con BD):** con `POSTGRES_PASSWORD` y el PostgreSQL de
  `docker-compose` arriba
  (`:backend:flywayMigrate`), `./gradlew :backend:run` y observar en stdout las
  líneas JSON con `"event":"ingestion.run.completed"` y sus campos; forzar una
  ventana perdida bajando `INGESTA_GRACE_MINUTES` y ajustando `INGESTA_*` (no se
  espera a las 09:30 en real: la prueba del disparo es unitaria y con tiempo
  virtual). Limpiar el entorno (`docker compose down -v`, `.env` borrado).
- **CI:** sin cambios (sin red ni BD).
- **E2E:** no aplica — sin flujo de usuario ni endpoint nuevo.
- `init.sh` (harness): **no** se modifica.

## Evidence To Capture

- Salida de `./gradlew :backend:test` con los nuevos tests (recuento, 0 fallos) y
  los cuatro escenarios del detector con sus instantes.
- Salida de `./gradlew build -PskipClient`, `test`, `detekt` e `init.sh` (exit 0).
- Línea JSON estructurada observada en `:backend:run`
  (`event=ingestion.run.completed` con `publications_saved`) y una alerta
  `event=ingestion.missed` provocada con una ventana perdida/gracia corta.
- Ficheros del commit `FT00010`, PR y run de CI; entradas en `PROGRESS.md` y
  `feature_list.json` (`evidence`).

## Validator Checklist

- [ ] Alcance acotado: eventos estructurados de ejecución + vigilante de ventanas
      perdidas + config de gracia + cableado; sin clasificación (FT00012), sin
      backfill (FT00011), sin endpoints, sin migraciones, sin telemetría ni
      alertas externas.
- [ ] Escenarios 1–8 pasan; el evento incluye `event` estable y el recuento de
      publicaciones persistidas por ejecución.
- [ ] `MissedIngestionDetector` es puro y correcto para gracia, ventanas
      anteriores al arranque y ventanas intentadas; el vigilante alerta una sola
      vez por ventana y no muere por excepción.
- [ ] `Application.kt` arranca **sin** BD (vigilante omitido, `/health` operativo);
      con BD configurada arranca dentro del scope condicional y se cancela en
      `ApplicationStopped` sin recursos nuevos sin cerrar.
- [ ] `return` único, sin `else if`, funciones ≤40 líneas, KDoc en castellano e
      identificadores en inglés; ningún tipo `@Serializable` nuevo (no aplica
      `@SerialName`).
- [ ] El gate sigue verde **sin BD** y sin red; `ARCHITECTURE.md`,
      `CONSTRAINTS.md`, ADR 0005 + índice, `docs/desarrollo-local.md`,
      `PROGRESS.md` y `feature_list.json` actualizados.
- [ ] No unrelated product behavior or extra feature work was added.

## Risks / Open Questions

- **Canal de alerta.** Al no admitirse alertas externas ni telemetría, la alerta
  es un log `ERROR` con `event=ingestion.missed`; requiere que un monitor de logs
  vigile ese evento. Es una limitación conocida, no un fallo de la feature.
- **Proceso caído.** El vigilante solo cubre ventanas mientras el proceso está en
  marcha; un arranque posterior a la ventana no la reclama (la recuperación del
  histórico es FT00011). Confirmar que este comportamiento es aceptable.
- **Granularidad de la gracia.** `INGESTA_GRACE_MINUTES` (default 30) debe ser
  mayor que la duración típica de una pasada; en el N100 hay que vigilar el
  tiempo de ejecución (ya anotado en ADR 0004).
- **«Nuevas» vs altas/actualizaciones.** El evento cuenta las publicaciones
  persistidas para la fecha (upsert); distinguir altas de actualizaciones exige
  cambiar `PublicationRepository`/SQL y se difiere.
- **Falsos positivos por reloj.** El reloj del host debe estar sincronizado; el
  cálculo usa `Europe/Madrid` configurable y es determinista con reloj inyectado.
