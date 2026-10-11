# Feature Implementation Spec: Cola de revisión por baja confianza

## Source Feature

- `id`: cola-revision-confianza
- `ft_id`: FT00023 (registrado en `docs/feature-ids.md`; siguiente libre `FT00048`)
- `parts`: none (atómica; ≈12 ficheros de producto, por debajo del límite de 30)
- `area`: simplificacion-ia
- `depends_on`: guardrails-anti-alucinacion (FT00022, `accepted`). **Su
  implementación vive en la rama `feat/ft00022-guardrails-anti-alucinacion`,
  pendiente de merge a `main`**; este spec se diseña contra el spec aceptado y
  el **ADR 0017**, no contra el árbol fusionado.
- `status`: not_started (al planificar)
- `source`: `feature_list.json`
- `claim`: rama `feat/ft00023-cola-revision-confianza` ya creada y publicada en
  `origin`; sin PR abierto hacia `main`.

## Goal

Añadir en `:backend`, como **librería sin wiring**, la **disposición del resumen
ciudadano tras los guardrails** (tarea `0.4-T06`): el resumen generado y evaluado
por FT00022 (`SummaryGuardrailResult`) se **persiste con su estado** en la tabla
`resumen` y, si su decisión es `NEEDS_REVIEW` (baja confianza), entra en la
**cola de revisión interna** (`cola_revision`) **sin publicarse**. Un resumen
`PUBLISHABLE` se **publica directamente** (estado `publicado`, que es lo que
consumirá el feed de FT00026); uno `DISCARDED` queda `descartado`. La feature
representa los **estados del resumen** de `docs/domain-model.md`, guarda la
**confianza** (`groundingScore`) y garantiza el **aviso de IA** en el resumen
publicado. La cola **no bloquea el resto del feed**: encolar es un efecto local,
nunca una excepción.

**No** se define un umbral nuevo: la decisión tipada y los umbrales
(`DISCARD_THRESHOLD` = 0.5, `REVIEW_THRESHOLD` = 0.8) son de FT00022 (ADR 0017) y
aquí se **consumen**. La feature es sustituible por dobles deterministas en el
gate, que corre **sin red ni BD**.

## Non-Goals

- **Generar** el resumen o **evaluar** los guardrails: FT00020/FT00022 se
  **reutilizan** tal cual.
- **Umbrales o grounding** nuevos: la confianza y la decisión vienen ya
  calculadas por `SummaryGuardrail` (ADR 0017). No se duplica el modelo de umbral.
- **Feed / endpoints / UI**: la consulta del feed (`estado = publicado`) y el
  detalle son **FT00026/FT00027**; el aviso de IA **visible** es **FT00033**.
  Aquí solo se persiste el estado y se encola.
- **Revisión manual** (transición `revisado → publicado|descartado` por un
  operador): sin API/UI en esta feature; el estado `revisado` se **modela** pero
  no se transiciona.
- **Wiring** en `Application.kt`/job/backfill: el servicio se construye en
  FT00026+.
- **Chat** (FT00025), **evaluación de calidad** (FT00024), **rate limiting**
  (FT00030).
- Cambios en `ResumenDto`/`CitizenSummaryValidator`/`HybridSearch`/
  `SummaryGuardrail` ni en el contrato de wire (congelado). **No** se modifica
  FT00008/FT00020/FT00021/FT00022 salvo la extensión idempotente de
  `ReviewQueueRepository` (ver §5).

## Job Story

When el backend ha generado y evaluado el resumen ciudadano de una publicación,
I want persistirlo con su estado y encolar los de baja confianza sin publicarlos,
so I can no publicar un resumen dudoso, dejar que el feed siga sirviendo el resto
y tener la cola lista para una revisión interna.

## Users And Permissions

- **Backend (disposición, FT00023):** consumidor interno; sin cuentas ni datos
  personales.
- **Operador/desarrollador:** inspecciona la cola pendiente (`listPending`) y
  ejecuta la prueba real **opt-in** (`DB_LIVE_TEST=1`).
- **FT00026+ (feed):** consumirá solo los resúmenes `publicado`; la cola es
  interna.
- **Usuario final (ciudadanía):** anónimo; no ve nada nuevo en esta feature.

## Acceptance Scenarios

### Scenario 1: un resumen de baja confianza entra en la cola y no en el feed

Given un `ResumenDto` con contrato y fuente válidos y un `SummaryGuardrailResult`
con `decision = NEEDS_REVIEW` y `groundingScore` en
`[DISCARD_THRESHOLD, REVIEW_THRESHOLD)`
When `SummaryDispositionService.dispose(publication, summary, result)` se ejecuta
Then el resumen se persiste con `estado = en_cola_revision` y
`confianza = groundingScore`; existe **una** entrada `cola_revision` en estado
`pendiente` con el motivo de las violaciones; y **no** hay resumen `publicado`
(el feed futuro filtra `estado = 'publicado'`, así que queda fuera).

### Scenario 2: un resumen de alta confianza se publica directamente

Given un `SummaryGuardrailResult` con `decision = PUBLISHABLE` y
`groundingScore >= REVIEW_THRESHOLD`
When se dispone
Then el resumen se persiste con `estado = publicado`, `confianza = groundingScore`
y `aviso_ia = true`, y **no** se crea ninguna entrada en `cola_revision`.

### Scenario 3: un resumen descartado no se publica ni se encola

Given un `SummaryGuardrailResult` con `decision = DISCARDED`
When se dispone
Then el resumen se persiste con `estado = descartado` y **no** se encola ni se
publica.

### Scenario 4: encolar es idempotente por resumen pendiente

Given un resumen ya encolado (`en_cola_revision` + entrada `pendiente`)
When se vuelve a disponer como `NEEDS_REVIEW`
Then sigue habiendo **una sola** entrada pendiente para ese resumen y el `motivo`
se actualiza (el índice único parcial de `V5` + *upsert* lo garantizan).

### Scenario 5: el estado persiste con los tokens del modelo de dominio

Given el enum de estados
When se mapea cada valor a su token
Then coinciden con `docs/domain-model.md` (`pendiente`, `generado`,
`validado_por_guardrails`, `publicado`, `en_cola_revision`, `revisado`,
`descartado`).

### Scenario 6: el gate sigue sin red ni BD

Given el runner de CI sin red, sin clave de OpenCode y sin PostgreSQL
When se ejecuta `./gradlew build -PskipClient`, `./gradlew test`, `./gradlew
detekt` o `.harness/init.sh`
Then todo está en verde; la prueba real se omite sin abrir conexiones.

### Scenario 7: la disposición se persiste de verdad (opt-in)

Given `DB_LIVE_TEST=1` y el PostgreSQL de `docker-compose` con la migración `V5`
When `ReviewQueuePersistenceLiveTest` publica un resumen y encola otro
Then el publicado se lee `publicado` con su `confianza`, el encolado aparece en
`listPending()`, y reencolarlo **no** duplica la fila pendiente.

## Repository Research

### Files Inspected

- `backend/src/main/kotlin/…/rag/guardrails/SummaryGuardrail.kt` y
  `SummaryGuardrailResult.kt`, `GuardrailDecision.kt` — **verificado** (en la
  rama FT00022): la decisión tipada `PUBLISHABLE`/`NEEDS_REVIEW`/`DISCARDED`, la
  puntuación `groundingScore` `[0,1]` y los umbrales viven aquí; FT00023 los
  **consume**.
- `backend/src/main/kotlin/…/persistence/SummaryRepository.kt` — `SummaryEntity`
  (`publicationId`, `whatChanges`, `whomItAffects`, `keyFigures`, `officialSource`,
  `aiNotice`, `status` = `pendiente` por defecto, `confidence: Double?`) y
  `save` (upsert por `publicacion_id` con `RETURNING id`); se **reutiliza**.
- `backend/src/main/kotlin/…/persistence/ReviewQueueRepository.kt` — interfaz
  `save`/`listBySummary`, `ReviewQueueEntity` (`id?`, `summaryId`, `reason?`,
  `status = "pendiente"`); su KDoc ya anuncia que «la colocación en la cola llega
  con FT00023». Se **extiende** (idempotencia + `listPending`).
- `backend/src/main/kotlin/…/persistence/{SummaryCacheRepository,GenerationUsageRepository}.kt`
  — patrón de repositorio JDBC (interfaz + entidad + `...RepositoryJdbc`, helpers
  `queryRows`/`executeUpdate`, *upsert* idempotente, sin ORM) a seguir.
- `backend/src/main/resources/db/migration/{V2,V4}*.sql` — `resumen` y
  `cola_revision` **ya existen** (`V2`); `V4` es el patrón de migración nueva.
  `V5` es la siguiente y **no** se editan las anteriores.
- `backend/src/test/kotlin/…/persistence/{MigrationSqlTest,ResumenCacheMigrationSqlTest}.kt`
  — patrón de test del **contrato SQL** de una migración desde el classpath, sin BD.
- `backend/src/test/kotlin/…/persistence/SummaryCachePersistenceLiveTest.kt` —
  patrón de prueba **opt-in** `DB_LIVE_TEST=1` con `Database.createDataSource` y
  limpieza.
- `backend/src/test/kotlin/…/rag/guardrails/SummaryGuardrailTest.kt` — patrón de
  **dobles deterministas** para el gate.
- `backend/src/main/kotlin/…/rag/summary/CachedCitizenSummaryGenerator.kt` — patrón
  de servicio de `rag/` que compone repositorios de `persistence/` y envuelve el
  resultado tipado; modelo para el servicio de disposición.
- `shared/src/commonMain/kotlin/…/model/ResumenDto.kt` — `avisoIA: Boolean = true`;
  contrato **congelado**, no se toca.
- `docs/domain-model.md` (§Resumen ciudadano: `generado → validado_por_guardrails
  → publicado | en_cola_revision → revisado → publicado|descartado`),
  `docs/roadmap.md` 0.4-T06, `.agents/skills/rag-datapublico/SKILL.md` §6,
  `CONSTRAINTS.md` §«Guardrails anti-alucinación y trazabilidad»,
  `docs/adr/0017`, y los specs `guardrails-anti-alucinacion.md` (FT00022),
  `cacheo-resumenes.md` (FT00021) y `contrato-resumen-ciudadano.md` (FT00019).

### Existing Patterns To Follow

- **Repositorio JDBC** (interfaz + `...Entity` + `...RepositoryJdbc`) con helpers
  de `persistence/Jdbc.kt`, sin ORM, autocommit por método.
- **Migración Flyway** nueva por feature (`V5`), nunca editar `V1`…`V4`; test del
  contrato SQL leyendo el recurso del classpath.
- **Servicio de `rag/`** que compone piezas puras y repositorios, sin Ktor ni HTTP.
- **Tests opt-in** por variable de entorno (`DB_LIVE_TEST=1`) fuera de gate/CI;
  dobles deterministas en el gate.
- **Estilo MUST**: identificadores en inglés, KDoc en castellano, un solo `return`,
  sin `else if`, funciones ≤40 líneas, `@SerialName` explícito en todo
  `@Serializable`, sufijo `Dto` en tipos de transporte, `...Entity` en persistencia.

### Current Gaps

- El resumen generado y evaluado **no se persiste** en `resumen`: FT00022 no
  escribe; FT00021 solo cachea en su tabla propia.
- La `cola_revision` **no se rellena** y no hay forma de encolar de forma
  idempotente.
- No existe una **representación tipada de los estados** del resumen.

## Technical Approach

Nuevo paquete en `:backend`:
`es.aviferdev.datopublico.backend.rag.review` (librería **pura** salvo la
persistencia por repositorios inyectados). Dirección de dependencia correcta:
`rag/review/` → `rag/guardrails/` (`SummaryGuardrailResult`/`GuardrailDecision`),
`persistence/` (`SummaryRepository`/`ReviewQueueRepository`),
`ingesta/publicacion/` (`Publicacion`) y `:shared` (`ResumenDto`).

### 1. Estados del resumen (puro) — `SummaryState.kt`

- `enum class SummaryState(val persistedValue: String)` con los **siete** estados
  de `docs/domain-model.md` (identificadores en inglés; el token persistido es el
  valor de dominio, **dato**, no identificador):
  `PENDING` = `pendiente`, `GENERATED` = `generado`, `VALIDATED` =
  `validado_por_guardrails`, `PUBLISHED` = `publicado`, `IN_REVIEW` =
  `en_cola_revision`, `REVIEWED` = `revisado`, `DISCARDED` = `descartado`.
- `companion object { fun fromPersisted(value: String): SummaryState? }`.
- Los tokens coinciden con `resumen.estado` (`V2`, default `pendiente`) y
  `cola_revision.estado` (default `pendiente`), así que **no** requiere migración
  de datos. La disposición automática usa `PUBLISHED`/`IN_REVIEW`/`DISCARDED`; el
  resto queda reservado al wiring/operador (FT00026+).

### 2. Resultado de la disposición — `SummaryReviewOutcome.kt`

- `sealed interface SummaryReviewOutcome` (valor interno, sin sufijo):
  `data class Published(val summaryId: Long)`,
  `data class Queued(val summaryId: Long, val reviewId: Long)`,
  `data class Discarded(val summaryId: Long)`.
- Refleja la disposición y los `id` persistidos para el wiring/test.

### 3. Motivo de revisión (puro) — `ReviewReasonFormatter.kt`

- `object ReviewReasonFormatter.of(result: SummaryGuardrailResult): String`:
  devuelve los nombres de `guardrailViolations` unidos por `,`
  (`"UNSUPPORTED_CLAIM,UNSUPPORTED_FIGURE"`); si no hay violaciones (caso límite),
  devuelve la constante `LOW_GROUNDING`. Nunca vacío. Es **puro y determinista**
  (diagnóstico interno del operador; no es texto de UI).

### 4. Servicio de disposición — `SummaryDispositionService.kt`

- `class SummaryDispositionService(private val summaries: SummaryRepository,
  private val reviewQueue: ReviewQueueRepository)`.
- `fun dispose(publication: Publicacion, summary: ResumenDto, guardrail:
  SummaryGuardrailResult): SummaryReviewOutcome` con un `when
  (guardrail.decision)` **exhaustivo** (sin `else if`):
  - `PUBLISHABLE` → persiste con `SummaryState.PUBLISHED`, devuelve `Published`;
  - `NEEDS_REVIEW` → persiste con `SummaryState.IN_REVIEW`, encola
    (`ReviewQueueEntity(summaryId = id, reason = ReviewReasonFormatter.of(...))`)
    y devuelve `Queued`;
  - `DISCARDED` → persiste con `SummaryState.DISCARDED`, devuelve `Discarded`.
- Persistencia común (una sola función, sin duplicar): mapea el `ResumenDto` a
  `SummaryEntity(publicationId = publication.id, whatChanges = summary.queCambia,
  whomItAffects = summary.aQuienAfecta, keyFigures = summary.cifrasClave,
  officialSource = summary.fuenteOficial, aiNotice = summary.avisoIA, status =
  state.persistedValue, confidence = guardrail.groundingScore)` y llama a
  `summaries.save`. El `id` devuelto se obtiene con `checkNotNull` (fail-fast si
  la BD no lo devuelve, nunca un `!!`).
- **Invariante de aviso de IA**: `dispose` exige `summary.avisoIA` (fail-fast
  `IllegalArgumentException` si es `false`); el resumen generado por FT00020
  siempre lo trae `true`. La parte **visible** del aviso es FT00033.
- **Invariante de no-bloqueo**: un `NEEDS_REVIEW` **nunca** publica y encolar es
  un efecto local; el servicio no lanza por baja confianza.
- **Umbral**: no se define ninguno; `NEEDS_REVIEW` (y su rango
  `[DISCARD_THRESHOLD, REVIEW_THRESHOLD)` más violaciones) ya lo decide FT00022.
  La `confianza` persistida es el `groundingScore`.

### 5. Persistencia — migración `V5` + repositorio (`persistence/`)

- **`backend/src/main/resources/db/migration/V5__cola_revision_pendiente_unique.sql`
  (create)**: un **índice único parcial** que permite como mucho **una** entrada
  pendiente por resumen (idempotencia del encolado) y conserva el historial de
  revisiones cerradas:
  ```sql
  CREATE UNIQUE INDEX cola_revision_pendiente_unique
      ON cola_revision (resumen_id)
      WHERE estado = 'pendiente';
  ```
  No toca `resumen` ni añade columnas; `V1`…`V4` no se editan.
- **`ReviewQueueRepository.kt` (modify)**: el `INSERT` de `save` pasa a *upsert*
  idempotente (`ON CONFLICT (resumen_id) WHERE estado = 'pendiente' DO UPDATE SET
  motivo = EXCLUDED.motivo RETURNING id`) y se añade `listPending():
  List<ReviewQueueEntity>` (`WHERE estado = 'pendiente' ORDER BY id`) para el
  consumidor FT00026+ y el test. `listBySummary` se mantiene.
- **`SummaryRepository.kt`**: **no** se modifica (su `save` ya es upsert por
  `publicacion_id` con `estado`/`confianza`).

### Sin wiring y sin anticipar lo diferido

`Application.kt`, `ingesta/`, `job`, `backfill`, `HybridSearch`,
`SummaryGuardrail`, `ResumenDto`/`CitizenSummaryValidator`, `:shared`,
`:composeApp`, CI e `init.sh` quedan **intactos**. Sin dependencias Gradle nuevas.
La migración `V5` **no** se engancha a `build`/`check` (tarea explícita
`:backend:flywayMigrate`). El **feed** (consulta por `estado = publicado`), los
endpoints, la UI, el aviso de IA visible y la revisión manual **no** se anticipan.

## Expected File Changes

Rutas en el repo de producto (`..`); `es/aviferdev/datopublico/backend` se abrevia
como `…/backend`:

- `backend/src/main/kotlin/…/backend/rag/review/SummaryState.kt` — create; enum de estados.
- `backend/src/main/kotlin/…/backend/rag/review/SummaryReviewOutcome.kt` — create; resultado tipado.
- `backend/src/main/kotlin/…/backend/rag/review/ReviewReasonFormatter.kt` — create; motivo puro.
- `backend/src/main/kotlin/…/backend/rag/review/SummaryDispositionService.kt` — create; servicio.
- `backend/src/main/kotlin/…/backend/persistence/ReviewQueueRepository.kt` — modify;
  *upsert* idempotente + `listPending`.
- `backend/src/main/resources/db/migration/V5__cola_revision_pendiente_unique.sql`
  — create; índice único parcial.
- `backend/src/test/kotlin/…/backend/rag/review/SummaryStateTest.kt` — create; gate.
- `backend/src/test/kotlin/…/backend/rag/review/ReviewReasonFormatterTest.kt` — create; gate.
- `backend/src/test/kotlin/…/backend/rag/review/SummaryDispositionServiceTest.kt` —
  create; gate, dobles (escenarios 1–4).
- `backend/src/test/kotlin/…/backend/persistence/ReviewQueueMigrationSqlTest.kt` —
  create; gate, contrato SQL de `V5`.
- `backend/src/test/kotlin/…/backend/persistence/ReviewQueuePersistenceLiveTest.kt`
  — create; **opt-in** `DB_LIVE_TEST=1`.
- `docs/desarrollo-local.md` (producto) — modify; sección de la cola y comando opt-in.

Harness (privado): `ARCHITECTURE.md`, `CONSTRAINTS.md`, ADR `0018` + índice,
`.agents/skills/rag-datapublico/SKILL.md`, `feature_list.json`, `PROGRESS.md`
(ver *Durable Documentation Impact*).

Total ≈ **12 ficheros de producto** + docs: por debajo del límite de 30. **No**
requiere división en partes.

## Visual Design Impact

- UI involved: no. Sin pantallas, tokens ni textos de UI (el aviso de IA visible y
  el detalle son FT00033).
- Design source: no aplica.
- Screens or states affected: ninguno.
- New design artifact required: no.

## Durable Documentation Impact

- `ARCHITECTURE.md`: **update** — `rag/` gana `review/` (estados del resumen +
  servicio de disposición); `persistence/` refina `cola_revision` (encolado
  idempotente + `listPending`); nueva migración `V5`; se documenta la etapa
  «generación → guardrails → **publicación | cola de revisión**».
- `CONSTRAINTS.md`: **update** — nueva sección **«Cola de revisión y disposición
  del resumen»** (MUST): la decisión de FT00022 se **consume** (sin umbral nuevo);
  `NEEDS_REVIEW` **no** publica y se encola (idempotente por resumen pendiente);
  `PUBLISHABLE` publica con `estado = publicado`; el resumen publicado lleva
  `aviso_ia = true`; la confianza persistida es el `groundingScore`; migración `V5`
  versionada; **sin wiring**; prueba real **opt-in** (`DB_LIVE_TEST=1`).
- `AGENTS.md`: **not needed** — no cambian el flujo, el arranque ni las reglas
  operativas.
- Other docs: `docs/adr/0018-cola-revision-disposicion-resumen.md` — **create**
  (ver *Open Questions* para el contenido propuesto) + índice;
  `.agents/skills/rag-datapublico/SKILL.md` §6 — **update** (estado FT00023);
  `docs/desarrollo-local.md` — **update**.

## Implementation Plan

1. Crear `SummaryState` (enum + `fromPersisted`) y su test de gate.
2. Crear `SummaryReviewOutcome` y `ReviewReasonFormatter` (puro) con su test de gate.
3. Crear la migración `V5` (índice único parcial) y `ReviewQueueMigrationSqlTest`
   (contrato SQL, sin BD).
4. Extender `ReviewQueueRepository` (*upsert* idempotente + `listPending`).
5. Crear `SummaryDispositionService` con su test de gate de dobles (escenarios
   1–4: publicar, encolar, descartar, encolado idempotente; aviso de IA).
6. Añadir `ReviewQueuePersistenceLiveTest` (**opt-in** `DB_LIVE_TEST=1`).
7. Pasar el gate sin red ni BD y registrar evidencia; actualizar `ARCHITECTURE.md`,
   `CONSTRAINTS.md`, ADR 0018 + índice, skill RAG y `docs/desarrollo-local.md`.
   `PROGRESS.md`/`feature_list.json` los cierra el orquestador.

## Implementation Tasks

- [ ] `SummaryState` (siete estados + `persistedValue` + `fromPersisted`).
- [ ] `SummaryReviewOutcome` (`Published`/`Queued`/`Discarded`).
- [ ] `ReviewReasonFormatter` (motivo puro desde las violaciones).
- [ ] Migración `V5` (índice único parcial de pendientes) + test del contrato SQL.
- [ ] `ReviewQueueRepository` idempotente (`ON CONFLICT … WHERE estado =
      'pendiente'`) + `listPending`.
- [ ] `SummaryDispositionService.dispose` (consume `GuardrailDecision`; publica /
      encola / descarta; `confianza` y `aviso_ia`; no duplica la cola).
- [ ] Tests de gate: estados, motivo, servicio con dobles, contrato SQL de `V5`.
- [ ] `ReviewQueuePersistenceLiveTest` opt-in (`DB_LIVE_TEST=1`).
- [ ] Docs durables: ARCHITECTURE, CONSTRAINTS, ADR 0018 + índice, skill RAG,
      `docs/desarrollo-local.md`.

## Verification Plan

Desde la raíz del producto (`..`, JDK 21 vía JBR/`JAVA_HOME`):

- **Gate sin red ni BD (obligatorio)**: `./gradlew :backend:test --rerun-tasks` →
  BUILD SUCCESSFUL con los tests nuevos en verde (0 fallos) y los **314 de
  FT00022** intactos. `./gradlew build --no-daemon -PskipClient` (incluye
  `:backend:detekt` y `:cpdCheck`), `./gradlew test`, `./gradlew detekt` y
  `env -u JAVA_HOME .harness/init.sh` → exit 0.
- **Offline confirmado**: sin `DB_LIVE_TEST`, la prueba real se **omite** sin abrir
  conexiones; ningún test del gate toca red ni BD.
- **Escenarios 1–4 (gate)**: cubiertos por `SummaryDispositionServiceTest` con
  dobles en memoria de `SummaryRepository`/`ReviewQueueRepository` (publicar sin
  encolar, encolar sin publicar, descartar, encolado idempotente) y
  `ReviewReasonFormatterTest`.
- **Escenario 5 (gate)**: `SummaryStateTest` comprueba el token persistido de cada
  estado y `fromPersisted`.
- **Escenario 7 (opt-in, fuera del gate y de la CI)**:
  ```sh
  cp .env.example .env
  docker compose up -d
  ./gradlew :backend:flywayMigrate
  DB_LIVE_TEST=1 ./gradlew :backend:test --tests '*ReviewQueuePersistenceLiveTest'
  docker compose down -v
  ```
  Esperado: el publicado se lee `publicado` con su `confianza`; el encolado aparece
  en `listPending()`; reencolarlo no duplica la fila pendiente. Solo necesita
  PostgreSQL (sin OpenCode ni modelo E5).
- **E2E**: no aplica — librería sin flujo de usuario ni endpoint nuevo (el repo no
  tiene comando E2E; el cliente es Compose Multiplatform).
- `init.sh` (harness): **no** se modifica; no se le añade ningún paso de red ni de BD.

## Evidence To Capture

- Salida de `./gradlew :backend:test` con los tests nuevos de gate (recuento, 0
  fallos) y del gate (`build -PskipClient`, `test`, `detekt`, `init.sh` exit 0).
- Confirmación de que los **314 tests de FT00022 siguen verdes** y de que
  `Application.kt`/`SummaryGuardrail`/`ResumenDto`/`CitizenSummaryValidator`/
  `HybridSearch`/`:shared`/`:composeApp`/CI/`init.sh` quedan intactos.
- Casos por test: `PUBLISHABLE` publica sin encolar; `NEEDS_REVIEW` encola sin
  publicar; `DISCARDED` ni publica ni encola; reencolado idempotente; aviso de IA.
- Salida del test opt-in `ReviewQueuePersistenceLiveTest` (round-trip + idempotencia).
- Ficheros del commit `FT00023`, PR y run de CI; entradas en `PROGRESS.md` y
  `feature_list.json` (`evidence`).

## Validator Checklist

- [ ] Alcance acotado: solo `rag/review/`, `persistence/ReviewQueueRepository` y la
      migración `V5` + sus tests; **sin** feed/endpoints/UI, **sin** chat (FT00025),
      **sin** wiring; `Application.kt`/`SummaryGuardrail`/`ResumenDto`/
      `CitizenSummaryValidator`/`HybridSearch`/`:shared`/`:composeApp`/CI/`init.sh`
      intactos.
- [ ] Escenarios 1–7 pasan; **todo el gate corre sin red ni BD** y la prueba real
      se omite sin `DB_LIVE_TEST`.
- [ ] La decisión de FT00022 se **consume**; **no** se introduce un umbral nuevo ni
      se duplica el grounding.
- [ ] `NEEDS_REVIEW` **no** publica y aparece en la cola; `PUBLISHABLE` publica
      (`estado = publicado`); `DISCARDED` queda `descartado`. La `confianza`
      persistida es el `groundingScore`.
- [ ] El encolado es **idempotente** por resumen pendiente (índice único parcial +
      *upsert*); `V5` versionada y fuera de `build`/`check`; SQL parametrizado, sin
      secretos.
- [ ] El resumen publicado lleva `aviso_ia = true` (aviso visible → FT00033).
- [ ] Los estados persisten con los tokens de `docs/domain-model.md`.
- [ ] `return` único, sin `else if`, funciones ≤40 líneas, KDoc en castellano con
      identificadores en inglés; `@SerialName` explícito donde aplique y sufijo
      `Dto` solo en tipos de transporte; `...Entity` en persistencia.
- [ ] `ARCHITECTURE.md`, `CONSTRAINTS.md`, ADR 0018 + índice, skill RAG,
      `docs/desarrollo-local.md`, `PROGRESS.md` y `feature_list.json` actualizados.
- [ ] Sin comportamiento de producto no relacionado ni ficheros fuera de alcance.

## Open Questions / Risks

- **ADR 0018 propuesto** — `docs/adr/0018-cola-revision-disposicion-resumen.md`
  (título: «Disposición del resumen guardado: estado + confianza persistidos y
  cola de revisión idempotente»). Contenido: consumir `GuardrailDecision` (sin
  umbral nuevo), persistir el estado (`publicado`/`en_cola_revision`/`descartado`)
  y la `confianza` (`groundingScore`) en la tabla `resumen` existente, encolar los
  `NEEDS_REVIEW` en `cola_revision` de forma idempotente (índice único parcial de
  pendientes), representar los estados del dominio y **no** cablear. Alternativas
  descartadas: tabla de cola propia; umbral de revisión nuevo; publicar solo (sin
  registrar `descartado`); diferir la escritura a FT00026.
- **FT00022 aún sin fusionar.** Su implementación vive en
  `feat/ft00022-guardrails-anti-alucinacion`; la rama de FT00023 debe **incluir ese
  commit** (o rebasarse tras el merge) para que `SummaryGuardrailResult`/
  `GuardrailDecision` existan. El orquestador gestiona el orden de merge.
- **FT00008 se toca mínimamente.** El *upsert* idempotente y `listPending` extienden
  `ReviewQueueRepository` (cuyo KDoc ya lo anticipa); no cambia `SummaryRepository`.
- **Índice único parcial sobre datos previos.** Crear `cola_revision_pendiente_unique`
  falla si ya existieran duplicados pendientes; en la práctica la tabla está vacía
  (nadie escribía en ella). Riesgo de desarrollo documentado.
- **`descartado` persistido.** Se guarda el resumen descartado con estado
  `descartado` para observabilidad; un contrato roto puede dejar campos vacíos
  (permitidos por `NOT NULL`). Si el producto prefiere no persistir descartes, se
  ajusta sin cambiar la cola.
- **Motivo como diagnóstico.** `cola_revision.motivo` guarda nombres de violación
  en inglés (diagnóstico interno), no texto de UI; la revisión manual (operador)
  llega con FT00026+/FT00042.
- **Disposición inerte sin wiring.** Hasta que FT00026+ construya el servicio, la
  disposición no se usa en runtime; el valor de la feature es la pieza y sus
  garantías. El feed debe filtrar por `estado = 'publicado'` (responsabilidad de
  FT00026).
