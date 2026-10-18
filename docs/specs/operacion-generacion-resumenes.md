# FT00049 — Generación one-shot de resúmenes ciudadanos y sesión de OpenCode

## Source Feature

- `id`: `operacion-generacion-resumenes`
- `ft_id`: `FT00049` (registrado en `docs/feature-ids.md`)
- `parts`: none (atómica; 6 ficheros de producto)
- `area`: `operacion`
- `depends_on`: `generacion-resumen-go` (FT00020), `cola-revision-confianza` (FT00023),
  `pgvector-indexado` (FT00016)
- `status`: `in_progress` (al escribir este spec; entregada en `main` y pendiente de
  validación/aceptación)
- `source`: `feature_list.json` (petición directa del dueño, sesión 082)
- `delivered_in`: commit `d3125e5` (PR #42), fusionado en `main` (sesión 083)

> **Spec retroactivo.** Escrito **después** de la entrega (commit `d3125e5`, PR #42 ya
> fusionado en `main`) para cerrar la gobernanza: la feature se implementó como petición
> directa del dueño, sin spec previo. Describe el **contrato realmente entregado**, no
> planifica trabajo nuevo. El orquestador mantiene `feature_list.json`/`PROGRESS.md`.

## Goal

Cerrar el **aplazamiento de wiring** del resumen ciudadano (FT00020–FT00023 eran
librerías sin cablear) con una **herramienta de operación one-shot** que genera y
publica resúmenes reales de un rango de fechas (`:backend:generateSummaries`), y
**arreglar el proveedor de OpenCode** para que envíe la cabecera obligatoria
`x-opencode-session` (sin ella el endpoint devolvía `400`), de modo que la generación
de resúmenes y el chat dejen de fallar por esa causa. Los resúmenes publicados aparecen
en el feed y la búsqueda.

## Non-Goals

- **Endpoints/UI nuevos**: el CLI no se cablea en el arranque del servidor; el feed y la
  búsqueda ya sirven los resúmenes `publicado` (FT00026/FT00028).
- **Cambiar el contrato del resumen, los guardrails o la disposición**: se **reutilizan**
  (FT00019/FT00022/FT00023) sin modificarlos.
- **Revisión manual de la cola**: sigue fuera; la cola es FT00023.
- **Programación automática** (cron/ingesta): el job diario es FT00009; aquí es una
  ejecución manual *opt-in*.
- **Migración** nueva: `V1`…`V5` intactas; el pipeline usa el esquema existente.
- **Backfill de publicaciones**: es FT00011 (el CLI solo consume lo ya ingerido).

## Acceptance Scenarios

Derivados de `feature_list.json.verification` y del comportamiento real entregado:

### Scenario 1: el proveedor envía la sesión y el User-Agent
Given una petición de generación,
When el proveedor la construye,
Then incluye la cabecera `x-opencode-session` (id estable por proceso: valor de
`OPENCODE_SESSION_ID` o `datopublico-<uuid>` nuevo) y un `User-Agent` propio
(`datopublico-backend/0.1`), además de `Authorization: Bearer` y el cuerpo
OpenAI-compatible.

### Scenario 2: generación y publicación real de un rango
Given PostgreSQL, el modelo E5 y `OPENCODE_API_KEY` disponibles,
When se ejecuta `SUMMARY_FROM=… SUMMARY_TO=… SUMMARY_LIMIT=… ./gradlew
:backend:generateSummaries`,
Then recorre las publicaciones del rango, indexa sus fragmentos (E5), genera con
OpenCode, aplica los guardrails y **publica**, **encola** o **descarta** según la
disposición; los publicados aparecen en `GET /v1/feed`.

### Scenario 3: reejecutable y con tope
Given una ejecución previa,
When se vuelve a ejecutar sobre el mismo rango,
Then las publicaciones con resumen real ya generado se marcan `ALREADY_DONE` (no
consumen tope ni llaman al proveedor) y no se duplican resúmenes (upsert).

### Scenario 4: un fallo aislado no aborta la ejecución
Given una publicación cuyo procesamiento falla,
When el pipeline la procesa,
Then registra `FAILED` para esa publicación y **continúa** con las siguientes; solo
una configuración inválida (p. ej. falta `OPENCODE_API_KEY` o una fecha mal formada)
aborta con código ≠ 0 y mensaje claro.

### Scenario 5: balance estructurado al terminar
Given una ejecución completada,
When termina,
Then registra una línea JSON `summary.generation.completed` con el rango y los
contadores `published`/`queued`/`discarded`/`invalid`/`already_done`/`failed`.

### Scenario 6: configuración por entorno con fail-fast
Given `SUMMARY_FROM`/`SUMMARY_TO`/`SUMMARY_LIMIT`/`SUMMARY_DELAY_MS`,
When se resuelven,
Then el rango es inclusivo (por defecto, el día de hoy), `SUMMARY_LIMIT` ≥ 1 (por
defecto 25) y `SUMMARY_DELAY_MS` ≥ 0 (por defecto 250 ms); una fecha inválida o un
rango invertido lanza un error claro.

### Scenario 7: el gate sigue verde sin red ni BD
Given el entorno de CI sin red, BD, modelo ni OpenCode,
When se ejecutan `:backend:detekt` y `:cpdCheck`,
Then quedan en verde y la tarea `:backend:generateSummaries` **no** se engancha a
`build`/`check`.

## Delivered Changes (Expected File Changes)

Rutas en el repo de producto (`..`); `es/aviferdev/datopublico` se abrevia `…`:

- `backend/src/main/kotlin/…/backend/rag/generation/OpenCodeTextGenerationProvider.kt` — **modify**; cabecera `x-opencode-session` (`SESSION_HEADER`) con id estable por proceso (`OPENCODE_SESSION_ID` o UUID) y `User-Agent` propio.
- `backend/src/main/kotlin/…/backend/rag/summary/GenerateSummariesConfig.kt` — **create**; configuración pura del rango/tope/pausa desde `SUMMARY_*` con fail-fast.
- `backend/src/main/kotlin/…/backend/rag/summary/SummaryGenerationPipeline.kt` — **create**; compone repositorios JDBC + `FragmentIndexer` + `HybridSearch` + `CitizenSummaryGenerator` + `SummaryGuardrail` + `SummaryDispositionService`; indexa, genera, valida y dispone.
- `backend/src/main/kotlin/…/backend/rag/summary/GenerateSummariesMain.kt` — **create**; `main()` del CLI, recorrido por fechas, tope/pausa, contadores y log JSON.
- `backend/build.gradle.kts` — **modify**; tarea `JavaExec` `:backend:generateSummaries` (grupo `application`, fuera de `build`/`check`).
- `backend/src/test/kotlin/…/backend/rag/generation/OpenCodeTextGenerationProviderTest.kt` — **modify**; verifica `x-opencode-session` y `User-Agent` no vacíos.

## Technical Approach (real entregado)

- **Cabecera de sesión**: `OpenCodeTextGenerationProvider` envía `x-opencode-session`
  con `sessionId` inyectable (por defecto `defaultSessionId()`: `OPENCODE_SESSION_ID`
  o `datopublico-<UUID>` por proceso) y `User-Agent: datopublico-backend/0.1`. El
  proveedor es compartido con el **chat** (mismo `TextGenerationProvider` cableado en
  `Application.kt`), así que el arreglo beneficia a ambos.
- **Pipeline** (`SummaryGenerationPipeline`): sobre el **mismo** pool JDBC y el
  **mismo** proveedor E5, reutiliza `PublicationRepositoryJdbc`, `SummaryRepositoryJdbc`,
  `ReviewQueueRepositoryJdbc`, `FragmentIndexer`, `HybridSearch`,
  `CitizenSummaryGenerator`, `SummaryGuardrail` y `SummaryDispositionService`; indexa
  los fragmentos, recupera el contexto con el **mismo filtro** que el generador y
  dispone el resultado.
- **Recorrido** (`GenerateSummariesMain`): resuelve conexión (`POSTGRES_*`), OpenCode
  (fail-fast) y E5; itera las fechas del rango; salta las que ya tienen resumen real
  (`confidence != null`); aísla fallos por publicación; cierra siempre pool, modelo y
  cliente HTTP; sale con código 0/1.
- **Reejecutable**: el guardado es un *upsert* por publicación (sobrescribe resúmenes
  previos, incluidos *seed* de desarrollo) sin duplicar.
- **Estados** (`SummaryOutcome`): `PUBLISHED`, `QUEUED`, `DISCARDED`, `INVALID`,
  `ALREADY_DONE`, `FAILED`.

## Durable Documentation Impact

- `ARCHITECTURE.md`: **update** — `:backend` gana la **herramienta de operación
  one-shot** `rag/summary/` (`GenerateSummariesConfig`/`SummaryGenerationPipeline`/
  `GenerateSummariesMain`, tarea `:backend:generateSummaries`) que **cablea** el
  pipeline de resumen (indexado E5 → OpenCode → guardrails → disposición); y el
  proveedor de OpenCode envía la cabecera `x-opencode-session` (id estable por
  proceso). Hoy el documento describe las librerías (FT00020–FT00023) pero **no** este
  cableado ni la cabecera.
- `CONSTRAINTS.md`: **update (pequeño)** — regla durable de operación: la generación
  real es una tarea **opt-in** (`:backend:generateSummaries`, fuera de `build`/`check`)
  con config `SUMMARY_*` y requiere PostgreSQL + modelo E5 + `OPENCODE_API_KEY`; el
  proveedor de OpenCode **debe** enviar `x-opencode-session`.
- `AGENTS.md`: **not needed** — no cambia el flujo, el arranque ni la verificación.
- Other docs: `docs/desarrollo-local.md` (producto) — **update** (documentar
  `:backend:generateSummaries`, `SUMMARY_*` y `OPENCODE_SESSION_ID`); ADR — **not
  needed** (el pipeline reutiliza decisiones de FT00020/FT00022/FT00023).

## Verification Plan

Desde la raíz del producto (`..`, JDK 21):

- **Gate**: `./gradlew :backend:detekt` y `./gradlew :cpdCheck` → verde.
- **Test del proveedor (sin red)**: `OpenCodeTextGenerationProviderTest` verifica la
  cabecera `x-opencode-session` y el `User-Agent` no vacíos.
- **Gate completo**: `./gradlew test -PskipClient`, `./gradlew build -PskipClient` y
  `.harness/init.sh` → exit 0 (la tarea `generateSummaries` no se ejecuta).
- **Ejecución real (opt-in, fuera del gate y de la CI)**:
  ```sh
  cp .env.example .env            # define POSTGRES_PASSWORD
  docker compose up -d
  ./gradlew :backend:flywayMigrate
  OPENCODE_API_KEY=<clave> \
  SUMMARY_FROM=2026-10-13 SUMMARY_TO=2026-10-14 SUMMARY_LIMIT=25 \
    ./gradlew :backend:generateSummaries
  curl -s 'http://localhost:8080/v1/feed?fecha=2026-10-13' | jq .
  ```
  Esperado: reparto `PUBLISHED`/`QUEUED`/`INVALID`/`DISCARDED` coherente y publicados
  visibles en el feed (evidencia registrada en `PROGRESS.md`, sesión 082).
- **E2E**: no aplica — el repo no tiene comando E2E persistente; la cobertura es el
  test del proveedor y la ejecución real *opt-in*.

## Evidence To Capture

- Salida de `:backend:detekt`/`:cpdCheck` y del test del proveedor (cabecera + UA).
- Salida de la ejecución real con el balance `summary.generation.completed` y un
  `curl` a `/v1/feed` con publicados.
- Ficheros del commit `d3125e5`, PR #42 y confirmación de fusión en `main` (sesión 083).

## Validator Checklist

- [ ] El proveedor envía `x-opencode-session` y `User-Agent`; el test lo verifica.
- [ ] `:backend:generateSummaries` es opt-in, no enganchada a `build`/`check`, con
      config `SUMMARY_*` y fail-fast de `OPENCODE_API_KEY`.
- [ ] Reutiliza indexado/guardrails/disposición sin modificarlos; upsert reejecutable;
      fallos aislados por publicación.
- [ ] Gate verde sin red/BD/modelo/OpenCode; `ARCHITECTURE.md`/`CONSTRAINTS.md`
      actualizados; ≤30 ficheros en el PR.
- [ ] Sin cambios en migraciones, `:shared`, `:composeApp`, CI ni `init.sh`.

## Risks / Open Questions

- **Fracción alta enviada a revisión.** Los guardrails (FT00022/23) envían a la cola de
  revisión una fracción alta de resúmenes, por lo que el feed visible (`publicado`) es
  un subconjunto; observado en sesión 082. No es un fallo del CLI, pero limita el
  resultado visible.
- **El `400` del chat se beneficia del mismo arreglo, sin test específico del chat.**
  El `user_visible_behavior` menciona el chat; el test entregado solo cubre el
  proveedor. Decidir si basta con la cobertura del proveedor compartido o se quiere un
  test de `/v1/chat`.
- **Cabecera de sesión y trazabilidad.** `OPENCODE_SESSION_ID` **se documentó** en
  `docs/desarrollo-local.md` (reparación 2026-10-18); el id por proceso cambia entre
  ejecuciones (afecta al enrutado/cacheo de OpenCode, no a la corrección).
- **Ejecución real no automatizable aquí.** Requiere PostgreSQL, modelo E5 y
  `OPENCODE_API_KEY`; queda como verificación manual *opt-in*.
