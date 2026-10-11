# Feature Implementation Spec: Cacheo de resúmenes y control de coste

## Source Feature

- `id`: cacheo-resumenes
- `ft_id`: FT00021 (registrado en `docs/feature-ids.md`)
- `parts`: none (atómica; ≈18 ficheros de producto, por debajo del límite de 30)
- `area`: simplificacion-ia
- `depends_on`: generacion-resumen-go (FT00020, `accepted`, ya en `main`)
- `status`: not_started (al planificar)
- `source`: `feature_list.json`
- `claim`: rama `feat/ft00021-cacheo-resumenes` ya reclamada en `origin`
  (`f7cf517`); sin PR abierto hacia `main`.

## Goal

Añadir en `:backend`, como **librería sin wiring**, el **cacheo del resumen
ciudadano** y el **registro del consumo de tokens** (tarea `0.4-T04`): un resumen
ya generado para una publicación **no se vuelve a generar** mientras no cambien
el **modelo** ni la **versión del prompt**, y cada generación deja constancia de
los **tokens** (prompt/completion/total) consumidos.

El servicio existente (`CitizenSummaryGenerator`, FT00020) se envuelve con una
capa de caché que consulta la caché **antes** de invocar al proveedor. Si hay
acierto, devuelve el `ResumenDto` cacheado **sin llamar** a OpenCode y registra
una fila de uso con `cache_hit = true` y 0 tokens; si no, genera, persiste el
resumen **solo si es válido**, registra el uso real y lo devuelve. La caché vive
en PostgreSQL (migración `V4` + repositorios JDBC) y es sustituible por un doble
en el gate, que corre **sin red ni BD**.

## Non-Goals

- **Guardrails de contenido** (alcanzabilidad del enlace, afirmaciones fuera del
  contexto) → FT00022; **cola de revisión/confianza/estados** → FT00023.
- **Publicar** el resumen en la tabla `resumen` (es el resumen publicado, no la
  caché) → FT00023/FT00026. Aquí la caché es una tabla **propia y separada**.
- **Endpoints Ktor**, API, UI y **wiring** en `Application.kt`/job/backfill.
- **Rate limiting** del chat (FT00025/FT00030) y **chat RAG**.
- **Coste en euros**: se registran **tokens**, no tarifas (la conversión
  monetaria, si llega, es de operación).
- Cambios en `ResumenDto`/`CitizenSummaryValidator`/`HybridSearch` (se reutilizan)
  ni en el contrato de wire.

## Job Story

When el backend genera el resumen ciudadano de una publicación del BOE que ya se
resumió antes con el mismo modelo y prompt,
I want reutilizar el resumen cacheado y registrar cuántos tokens se gastaron,
so I can no volver a pagar una generación idéntica y vigilar el coste del LLM.

## Users And Permissions

- **Backend (cacheo, FT00021):** consumidor interno; sin cuentas, sin datos
  personales, sin autenticación de usuario.
- **Operador/desarrollador:** consulta el consumo de tokens por publicación (a
  través del repositorio) y ejecuta la prueba real **opt-in** con PostgreSQL.
- **Usuario final (ciudadanía):** anónimo; no ve nada nuevo en esta feature
  (la UI de detalle es FT00033).

## Acceptance Scenarios

### Scenario 1: segunda generación de la misma publicación reutiliza la caché

Given una publicación ya generada y cacheada (mismo modelo y `promptVersion`) y
un doble de `TextGenerationProvider`
When se vuelve a llamar `CachedCitizenSummaryGenerator.generate(publication)`
Then devuelve `CachedSummaryResult(cacheHit = true)` con el resumen cacheado, el
proveedor **no** recibe ninguna petición (su contador de llamadas no aumenta) y
se registra un uso con `cache_hit = true` y 0 tokens.

### Scenario 2: primera generación (fallo de caché) invoca al proveedor y cachea

Given una publicación sin resumen cacheado y un proveedor que devuelve un JSON
válido con `usage` (`prompt_tokens`/`completion_tokens`/`total_tokens`)
When se genera
Then devuelve `CachedSummaryResult(cacheHit = false)` con `Valid`, el resumen
queda almacenado en la caché y se registra el uso real (tokens del proveedor).

### Scenario 3: un resumen inválido no se cachea

Given una publicación de becas y una salida del modelo **sin plazo**
When se genera
Then devuelve `Invalid` con `MISSING_DEADLINE`, **no** se guarda nada en la caché
y **sí** se registra el uso (se gastaron tokens).

### Scenario 4: cambiar el modelo o la versión del prompt invalida la caché

Given una publicación cacheada con `model = A` y `promptVersion = v1`
When se genera con `model = B` (o `promptVersion = v2`)
Then la clave de caché es distinta, se trata como fallo de caché y el proveedor
vuelve a ser invocado.

### Scenario 5: la clave de caché es determinista y exige entradas no vacías

Given `publicationId`, `model` y `promptVersion`
When se calcula `SummaryCacheKey.of(...)` dos veces
Then devuelve la misma cadena; y con cualquiera de los tres en blanco falla con
`IllegalArgumentException` (fail-fast, error de programación).

### Scenario 6: el proveedor OpenCode expone el uso de tokens

Given un `MockEngine` que responde a `POST /chat/completions` con el bloque
`usage` (y otro que **no** lo trae)
When `OpenCodeTextGenerationProvider.generate(request)` se ejecuta
Then `GenerationResponse.usage` lleva los tokens del proveedor; sin `usage` en la
respuesta, `usage` es `null` (no es un error).

### Scenario 7: el gate sigue sin red ni BD

Given el runner de CI sin red, sin clave de OpenCode y sin PostgreSQL
When se ejecuta `./gradlew build -PskipClient`, `./gradlew test`, `./gradlew
detekt` o `.harness/init.sh`
Then todo está en verde; las pruebas reales se omiten sin abrir sockets ni
conexiones.

### Scenario 8: la caché y el uso se persisten de verdad (opt-in)

Given `DB_LIVE_TEST=1` y el PostgreSQL de `docker-compose` con la migración `V4`
When `SummaryCachePersistenceLiveTest` guarda/lee un resumen y registra/agrega uso
Then `find` devuelve el mismo `ResumenDto`, `totalTokens()` cuadra y el *upsert*
de la caché es idempotente por `cache_key`.

## Repository Research

### Files Inspected

- `backend/src/main/kotlin/…/rag/generation/TextGenerationProvider.kt` —
  **verificado**: `GenerationResponse` **solo** tiene `text: String`; **no** lleva
  `usage`. Hay que **ampliarlo** para el control de coste.
- `backend/src/main/kotlin/…/rag/generation/OpenCodeTextGenerationProvider.kt` —
  DTOs de wire privados (`ChatCompletionResponseDto` sin `usage`); punto donde se
  parsea `choices[0].message.content` y donde añadir `usage`.
- `backend/src/main/kotlin/…/rag/generation/OpenCodeConfig.kt` — `model` (`internal`)
  y defaults; la caché necesita el **nombre del modelo** (se inyecta, no se lee
  aquí).
- `backend/src/main/kotlin/…/rag/summary/CitizenSummaryGenerator.kt` — servicio
  `generate(publication, limit): CitizenSummaryResult`; **no** persiste ni expone
  el uso; se **envuelve** (no se reescribe su pipeline).
- `backend/src/main/kotlin/…/rag/summary/CitizenSummaryResult.kt` — `Valid`/
  `Invalid` sin `usage`; se amplía de forma **compatible** (campo con default
  `null`).
- `backend/src/main/kotlin/…/rag/summary/CitizenSummaryPromptBuilder.kt` —
  constantes privadas (`MAX_FRAGMENTS`, `SYSTEM_PROMPT`…); se le añade la
  constante pública `PROMPT_VERSION`.
- `backend/src/main/kotlin/…/persistence/{SummaryRepository,PublicationRepository,FragmentRepository,Jdbc}.kt`
  — patrón de repositorio (interfaz + `...Entity` + impl JDBC, helpers `queryRows`/
  `executeUpdate`, *upsert* por clave, sin ORM).
- `backend/src/main/resources/db/migration/{V1,V2,V3}*.sql` — esquema y estilo de
  migración; `V4` es la siguiente y **no** se editan las anteriores.
- `backend/src/test/kotlin/…/persistence/{MigrationSqlTest,FragmentEmbeddingMigrationSqlTest}.kt`
  — patrón de test del **contrato SQL** de una migración desde el classpath, sin BD.
- `backend/src/test/kotlin/…/persistence/PublicationPersistenceTest.kt` — patrón de
  test de **mapeo puro** dominio ↔ entidad, sin BD.
- `backend/src/test/kotlin/…/rag/summary/CitizenSummaryGeneratorTest.kt` — dobles
  (`FakeTextGenerationProvider`, `FakeFragmentRepository`, `FakeEmbeddingProvider`);
  debe seguir verde.
- `shared/src/commonMain/kotlin/…/model/ResumenDto.kt` — `@Serializable`; se
  serializa a JSON para la columna de caché sin tocar el wire.
- `docs/desarrollo-local.md` (producto) §«Generación del resumen ciudadano»,
  `docs/adr/0015`, `.agents/skills/rag-datapublico/SKILL.md` §5–6, `CONSTRAINTS.md`
  §«IA y coste», `docs/roadmap.md` 0.4-T04.

### Existing Patterns To Follow

- **Repositorio JDBC** (interfaz + `...Entity` + `...RepositoryJdbc` en un solo
  fichero) con helpers de `persistence/Jdbc.kt`, sin ORM, autocommit por método.
- **Migración Flyway** nueva por feature (`V4`), nunca editar `V1`/`V2`/`V3`; test
  del contrato SQL leyendo el recurso del classpath.
- **Servicio de `rag/`** como composición de piezas puras/reutilizadas, sin Ktor
  ni HTTP; el proveedor real solo lo conoce la impl OpenCode.
- **Tests opt-in** por variable de entorno (`DB_LIVE_TEST=1`) fuera de
  gate/CI; dobles deterministas en el gate.
- **Estilo MUST**: identificadores en inglés, KDoc en castellano, un solo `return`,
  sin `else if`, funciones ≤40 líneas, `@SerialName` explícito en todo
  `@Serializable`, sufijo `Dto` en tipos de transporte, `...Entity` en persistencia.

### Current Gaps

- `GenerationResponse` no expone tokens; el proveedor OpenCode no parsea `usage`.
- `CitizenSummaryGenerator` no persiste ni devuelve el uso.
- No existe ninguna tabla ni repositorio de caché o de consumo de tokens.
- No existe la noción de **versión de prompt** para invalidar la caché.

## Technical Approach

### 1. Uso de tokens en el proveedor (`rag/generation/`)

- **`TextGenerationProvider.kt` (modify, compatible)**: nuevo valor interno
  `TokenUsage(promptTokens, completionTokens, totalTokens)` (sin sufijo, no
  `@Serializable`) y `GenerationResponse(text: String, usage: TokenUsage? = null)`.
  El default `null` mantiene verde a FT00020.
- **`OpenCodeTextGenerationProvider.kt` (modify)**: `ChatCompletionResponseDto`
  gana `usage: ChatUsageDto? = null`; `ChatUsageDto` mapea
  `prompt_tokens`/`completion_tokens`/`total_tokens` con `@SerialName` explícito.
  `decode` construye `GenerationResponse(text, usage?.toTokenUsage())`. Sin `usage`
  en la respuesta ⇒ `null` (no es error).

### 2. Uso en el resultado de la generación (`rag/summary/`)

- **`CitizenSummaryResult.kt` (modify, compatible)**: `Valid(summary, usage:
  TokenUsage? = null)` e `Invalid(violations, usage: TokenUsage? = null)`.
- **`CitizenSummaryGenerator.kt` (modify)**: `generate` propaga
  `response.usage` al resultado (`resultOf(summary, validation, response.usage)`).
  El pipeline (HybridSearch → prompt → proveedor → parser → validador) **no
  cambia**.
- **`CitizenSummaryPromptBuilder.kt` (modify)**: constante **pública**
  `PROMPT_VERSION = "v1"`; subirla (o cambiar el modelo) invalida la caché.

### 3. Clave de caché (pura) — `rag/summary/SummaryCacheKey.kt` (create)

- `object SummaryCacheKey { fun of(publicationId: String, model: String,
  promptVersion: String): String }`: devuelve `"$publicationId|$model|$promptVersion"`
  (delimitador `|`, ausente en ids del BOE, modelos y versiones). **Fail-fast**
  (`IllegalArgumentException`) si alguno está en blanco. Determinista y pura.
- La clave incluye **modelo** y **versión de prompt** para que un cambio de
  cualquiera de los dos **no** sirva caché obsoleta.

### 4. Persistencia — migración `V4` + repositorios (`persistence/`)

- **`backend/src/main/resources/db/migration/V4__resumen_cache_uso.sql` (create)**:
  - `resumen_cache`: `cache_key text PRIMARY KEY`, `publicacion_id text NOT NULL
    REFERENCES publicacion (id) ON DELETE CASCADE`, `modelo text NOT NULL`,
    `prompt_version text NOT NULL`, `resumen text NOT NULL` (JSON de `ResumenDto`),
    `creado_en timestamptz NOT NULL DEFAULT now()`; índice por `publicacion_id`.
  - `generacion_uso`: `id bigint GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY`,
    `publicacion_id text NOT NULL`, `cache_key text NOT NULL`, `modelo text NOT
    NULL`, `prompt_tokens integer NOT NULL DEFAULT 0`, `completion_tokens integer
    NOT NULL DEFAULT 0`, `total_tokens integer NOT NULL DEFAULT 0`, `cache_hit
    boolean NOT NULL DEFAULT false`, `creado_en timestamptz NOT NULL DEFAULT
    now()`; índice por `publicacion_id`.
- **`SummaryCacheRepository.kt` (create)**: interfaz (`find(cacheKey):
  SummaryCacheEntity?`, `put(entity): SummaryCacheEntity`), `SummaryCacheEntity`
  (`cacheKey`, `publicationId`, `model`, `promptVersion`, `summary: ResumenDto`),
  codec puro JSON (`ResumenDto` ↔ `String` con `DatoPublicoJson`) y
  `SummaryCacheRepositoryJdbc` (*upsert* por `cache_key`).
- **`GenerationUsageRepository.kt` (create)**: interfaz (`record(usage)`,
  `listByPublication(publicationId)`, `totalTokens(): Long`),
  `GenerationUsageEntity` (`id?`, `publicationId`, `cacheKey`, `model`,
  `promptTokens`, `completionTokens`, `totalTokens`, `cacheHit`) y
  `GenerationUsageRepositoryJdbc` (insert + consultas agregadas).

### 5. Servicio con caché — `rag/summary/CachedCitizenSummaryGenerator.kt` (create)

- `data class CachedSummaryResult(val result: CitizenSummaryResult, val
  cacheHit: Boolean)` (valor interno, sin sufijo).
- `CachedCitizenSummaryGenerator(generator: CitizenSummaryGenerator,
  cache: SummaryCacheRepository, usage: GenerationUsageRepository, model: String,
  promptVersion: String = CitizenSummaryPromptBuilder.PROMPT_VERSION)`:
  `suspend fun generate(publication, limit = DEFAULT_LIMIT): CachedSummaryResult`.
  - Calcula la clave (`SummaryCacheKey.of`), consulta la caché; en **acierto**
    registra un uso con `cache_hit = true` y 0 tokens y devuelve
    `Valid(summary)` cacheado; en **fallo** invoca al generador, registra el uso
    real (`usage` del resultado o 0), **cachea solo si es `Valid`** y devuelve el
    resultado con `cacheHit = false`.
  - El **modelo** se inyecta por constructor (en producción, de `OpenCodeConfig`):
    no se lee de la config aquí. Sin wiring.
- `rag/summary/SummaryCacheKeyTest.kt`, `CachedCitizenSummaryGeneratorTest.kt`
  (create) y ampliación de `CitizenSummaryGeneratorTest`/`OpenCodeTextGenerationProviderTest`.

### Sin wiring y sin anticipar lo diferido

`Application.kt`, `ingesta/`, `job`, `backfill`, `HybridSearch`,
`ResumenDto`/`CitizenSummaryValidator`, `:shared`, `:composeApp`, CI e `init.sh`
quedan **intactos**. Sin dependencias Gradle nuevas. La migración `V4` **no** se
engancha a `build`/`check` (tarea explícita `:backend:flywayMigrate`). La
publicación del resumen en la tabla `resumen` (FT00023/FT00026) y el rate limiting
(FT00030) **no** se anticipan.

## Expected File Changes

Rutas en el repo de producto (`..`); `es/aviferdev/datopublico/backend` se abrevia
como `…/backend`:

- `backend/src/main/kotlin/…/backend/rag/generation/TextGenerationProvider.kt` —
  modify; `TokenUsage` + `GenerationResponse.usage` (compatible).
- `backend/src/main/kotlin/…/backend/rag/generation/OpenCodeTextGenerationProvider.kt`
  — modify; DTO `usage` + parseo.
- `backend/src/main/kotlin/…/backend/rag/summary/CitizenSummaryResult.kt` — modify;
  `usage` en `Valid`/`Invalid` (compatible).
- `backend/src/main/kotlin/…/backend/rag/summary/CitizenSummaryGenerator.kt` —
  modify; propaga el uso.
- `backend/src/main/kotlin/…/backend/rag/summary/CitizenSummaryPromptBuilder.kt` —
  modify; `PROMPT_VERSION` público.
- `backend/src/main/kotlin/…/backend/rag/summary/SummaryCacheKey.kt` — create; clave pura.
- `backend/src/main/kotlin/…/backend/rag/summary/CachedCitizenSummaryGenerator.kt` —
  create; servicio de caché + `CachedSummaryResult`.
- `backend/src/main/kotlin/…/backend/persistence/SummaryCacheRepository.kt` — create;
  interfaz + entidad + codec JSON + impl JDBC.
- `backend/src/main/kotlin/…/backend/persistence/GenerationUsageRepository.kt` —
  create; interfaz + entidad + impl JDBC.
- `backend/src/main/resources/db/migration/V4__resumen_cache_uso.sql` — create;
  `resumen_cache` + `generacion_uso`.
- `backend/src/test/kotlin/…/backend/rag/summary/SummaryCacheKeyTest.kt` — create; gate.
- `backend/src/test/kotlin/…/backend/rag/summary/CachedCitizenSummaryGeneratorTest.kt`
  — create; gate, dobles (acierto/fallo/inválido/clave distinta).
- `backend/src/test/kotlin/…/backend/rag/summary/CitizenSummaryGeneratorTest.kt` —
  modify; caso de propagación del uso (resto verde).
- `backend/src/test/kotlin/…/backend/rag/generation/OpenCodeTextGenerationProviderTest.kt`
  — modify; `usage` presente/ausente con `MockEngine`.
- `backend/src/test/kotlin/…/backend/persistence/ResumenCacheMigrationSqlTest.kt` —
  create; gate, contrato SQL de `V4`.
- `backend/src/test/kotlin/…/backend/persistence/SummaryCachePersistenceTest.kt` —
  create; gate, codec JSON puro de `ResumenDto`.
- `backend/src/test/kotlin/…/backend/persistence/SummaryCachePersistenceLiveTest.kt`
  — create; **opt-in** `DB_LIVE_TEST=1`.
- `docs/desarrollo-local.md` (producto) — modify; sección de caché y comando opt-in.

Harness (privado): `ARCHITECTURE.md`, `CONSTRAINTS.md`, ADR `0016` + índice,
`.agents/skills/rag-datapublico/SKILL.md`, `feature_list.json`, `PROGRESS.md`
(ver *Durable Documentation Impact*).

Total ≈ **18 ficheros de producto** + docs: por debajo del límite de 30. **No**
requiere división en partes.

## Visual Design Impact

- UI involved: no. Sin pantallas, tokens ni textos de UI (la UI de detalle es FT00033).
- Design source: no aplica.
- Screens or states affected: ninguno.
- New design artifact required: no.

## Durable Documentation Impact

- `ARCHITECTURE.md`: **update** — `persistence/` gana los repositorios de caché y
  de uso; `rag/summary/` gana `SummaryCacheKey` y `CachedCitizenSummaryGenerator`;
  `GenerationResponse` expone `usage`; nueva migración `V4` (`resumen_cache` +
  `generacion_uso`).
- `CONSTRAINTS.md`: **update** — nueva sección **«Cacheo y control de coste»**
  (MUST): clave determinista = publicación + **modelo** + **versión de prompt**
  (un cambio de cualquiera invalida); **solo** se cachean resúmenes `Valid`; cada
  generación (acierto o fallo) **registra** tokens y `cache_hit`; migración `V4`
  versionada; **sin wiring**; prueba real **opt-in** (`DB_LIVE_TEST=1`).
- `AGENTS.md`: **not needed** — no cambian el flujo, el arranque ni las reglas
  operativas.
- Other docs: `docs/adr/0016-cacheo-resumenes-uso-tokens.md` — **create** (decisión
  durable: caché en tabla propia frente a reutilizar `resumen`, clave con
  modelo/prompt, uso por generación) + índice; `.agents/skills/rag-datapublico/SKILL.md`
  §5–6 — **update** (estado FT00021); `docs/desarrollo-local.md` — **update**.

## Implementation Plan

1. Ampliar el proveedor: `TokenUsage` + `GenerationResponse.usage` y el parseo de
   `usage` en `OpenCodeTextGenerationProvider` (DTO `ChatUsageDto`); ampliar
   `OpenCodeTextGenerationProviderTest` (`MockEngine`) y `CitizenSummaryResult` +
   `CitizenSummaryGenerator` para propagar el uso.
2. Añadir `PROMPT_VERSION` público en `CitizenSummaryPromptBuilder` y
   `SummaryCacheKey` (puro) con su test de gate.
3. Crear la migración `V4` y su `ResumenCacheMigrationSqlTest` (contrato SQL, sin BD).
4. Crear `SummaryCacheRepository` (entidad + codec JSON + impl JDBC) y
   `SummaryCachePersistenceTest` (codec puro) y `GenerationUsageRepository`.
5. Crear `CachedCitizenSummaryGenerator` + `CachedSummaryResult` con su test de
   gate de dobles (acierto no llama al proveedor, fallo cachea y registra tokens,
   inválido no cachea, modelo/prompt distintos invalidan).
6. Añadir `SummaryCachePersistenceLiveTest` (**opt-in** `DB_LIVE_TEST=1`).
7. Pasar el gate sin red ni BD y registrar evidencia; actualizar `ARCHITECTURE.md`,
   `CONSTRAINTS.md`, ADR 0016 + índice, skill RAG y `docs/desarrollo-local.md`.
   `PROGRESS.md`/`feature_list.json` los cierra el orquestador.

## Implementation Tasks

- [ ] `TokenUsage` + `GenerationResponse.usage` y parseo de `usage` en el proveedor.
- [ ] `CitizenSummaryResult`/`CitizenSummaryGenerator` propagan el uso (compatible).
- [ ] `CitizenSummaryPromptBuilder.PROMPT_VERSION` público.
- [ ] `SummaryCacheKey` (puro, determinista, fail-fast).
- [ ] Migración `V4` (`resumen_cache` + `generacion_uso`) + test del contrato SQL.
- [ ] `SummaryCacheRepository` (entidad + codec JSON + impl JDBC).
- [ ] `GenerationUsageRepository` (entidad + impl JDBC; `totalTokens`).
- [ ] `CachedCitizenSummaryGenerator` + `CachedSummaryResult`.
- [ ] Tests de gate: clave, generador con caché (dobles), uso del proveedor, codec.
- [ ] `SummaryCachePersistenceLiveTest` opt-in (`DB_LIVE_TEST=1`).
- [ ] Docs durables: ARCHITECTURE, CONSTRAINTS, ADR 0016 + índice, skill RAG,
      `docs/desarrollo-local.md`.

## Verification Plan

Desde la raíz del producto (`..`, JDK 21 vía JBR/`JAVA_HOME`):

- **Gate sin red ni BD (obligatorio)**: `./gradlew :backend:test --rerun-tasks` →
  BUILD SUCCESSFUL con los tests nuevos en verde (0 fallos) y los **253 de
  FT00020** intactos. `./gradlew build --no-daemon -PskipClient` (incluye
  `:backend:detekt` y `:cpdCheck`), `./gradlew test`, `./gradlew detekt` y
  `env -u JAVA_HOME .harness/init.sh` → exit 0.
- **Offline confirmado**: sin `DB_LIVE_TEST`/`OPENCODE_LIVE_TEST`, las pruebas
  reales se **omiten** sin abrir sockets ni conexiones; ningún test del gate toca
  red ni BD.
- **Escenarios 1–5 (gate)**: cubiertos por `CachedCitizenSummaryGeneratorTest`
  (dobles: acierto sin llamada al proveedor, fallo que cachea y registra tokens,
  inválido que no cachea, clave distinta por modelo/prompt) y `SummaryCacheKeyTest`.
- **Escenario 6 (gate)**: `OpenCodeTextGenerationProviderTest` con `MockEngine`
  (respuesta con `usage` ⇒ tokens; sin `usage` ⇒ `null`).
- **Escenario 8 (opt-in, fuera del gate y de la CI)**:
  ```sh
  cp .env.example .env
  docker compose up -d
  ./gradlew :backend:flywayMigrate
  DB_LIVE_TEST=1 ./gradlew :backend:test --tests '*SummaryCachePersistenceLiveTest'
  docker compose down -v
  ```
  Esperado: `find` devuelve el mismo `ResumenDto`; `totalTokens()` cuadra;
  *upsert* idempotente por `cache_key`. Solo necesita PostgreSQL (sin OpenCode ni
  modelo E5: el proveedor es un doble en memoria).
- **E2E**: no aplica — librería sin flujo de usuario ni endpoint nuevo (el repo no
  tiene comando E2E; el cliente es Compose Multiplatform).
- `init.sh` (harness): **no** se modifica; no se le añade ningún paso de red ni de BD.

## Evidence To Capture

- Salida de `./gradlew :backend:test` con los tests nuevos de gate (recuento, 0
  fallos) y del gate (`build -PskipClient`, `test`, `detekt`, `init.sh` exit 0).
- Confirmación de que los **253 tests de FT00020 siguen verdes** y de que
  `ResumenDto`/`CitizenSummaryValidator`/`HybridSearch`/`Application.kt`/job/
  backfill/`:shared`/`:composeApp`/CI/`init.sh` quedan intactos.
- Salida del test opt-in `SummaryCachePersistenceLiveTest` (round-trip y agregado)
  y del *upsert* idempotente.
- Ficheros del commit `FT00021`, PR y run de CI; entradas en `PROGRESS.md` y
  `feature_list.json` (`evidence`).

## Validator Checklist

- [ ] Alcance acotado: solo `rag/generation/` (uso), `rag/summary/` (clave +
      servicio con caché) y `persistence/` (dos repositorios) + migración `V4` y
      sus tests; **sin** guardrails (FT00022), cola de revisión (FT00023), chat
      (FT00025), endpoints/UI ni wiring; `ResumenDto`/`CitizenSummaryValidator`/
      `HybridSearch`/`Application.kt`/job/backfill/`:shared`/`:composeApp`/CI/`init.sh`
      intactos.
- [ ] Escenarios 1–8 pasan; **todo el gate corre sin red ni BD** y las pruebas
      reales se omiten sin `DB_LIVE_TEST`.
- [ ] La **clave de caché** incluye publicación + modelo + versión de prompt;
      cambiar el modelo o la versión provoca fallo de caché (se invoca al
      proveedor). Solo se cachean resúmenes `Valid`.
- [ ] Cada generación (acierto y fallo) **registra** tokens y `cache_hit`; el
      proveedor **no** se invoca en un acierto de caché.
- [ ] `GenerationResponse.usage` es **opcional** (sin `usage` ⇒ `null`, no error);
      `CitizenSummaryResult` se amplía de forma **compatible** (FT00020 verde).
- [ ] Migración `V4` versionada (no se editan `V1`/`V2`/`V3`) y fuera de
      `build`/`check`; SQL parametrizado, sin secretos versionados.
- [ ] `return` único, sin `else if`, funciones ≤40 líneas, KDoc en castellano con
      identificadores en inglés; `@SerialName` explícito en cada `@Serializable` y
      sufijo `Dto` en los DTOs de transporte; `...Entity` en persistencia.
- [ ] `ARCHITECTURE.md`, `CONSTRAINTS.md`, ADR 0016 + índice, skill RAG,
      `docs/desarrollo-local.md`, `PROGRESS.md` y `feature_list.json` actualizados.
- [ ] Sin comportamiento de producto no relacionado ni ficheros fuera de alcance.

## Open Questions / Risks

- **Modelo inyectado, no leído.** La caché recibe el nombre del modelo por
  constructor (en producción vendrá de `OpenCodeConfig`); si quien cablee pasa un
  modelo distinto del real, la clave sería incorrecta. Se documenta y se exige
  coherencia en el wiring (FT00026+).
- **Versión de prompt manual.** `PROMPT_VERSION` es una constante: olvidar
  subirla al cambiar el prompt serviría resúmenes obsoletos. Se documenta como
  regla en `CONSTRAINTS.md`.
- **Cambios de reglas del validador.** Un cambio en `CitizenSummaryValidator`
  (FT00019) no invalida la caché por sí solo (la clave no lo incluye); si las
  reglas cambian de forma incompatible, habrá que versionar la clave o purgar la
  caché. Riesgo aceptado y documentado.
- **`usage` ausente en la respuesta del proveedor.** Se registra 0 tokens (no es
  fail-fast): no se inventa consumo, pero el agregado puede subestimar.
- **Resumen cacheado como JSON en `text`.** Frente a duplicar las columnas de
  `resumen`, se guarda el `ResumenDto` serializado; el coste es un `decode`/`encode`
  por operación y acoplar la caché al `ResumenDto` (que es el contrato). Se
  justifica en el ADR 0016.
- **Caché inerte sin wiring.** Hasta que FT00026+ construya el servicio, la caché
  no se usa en runtime; el valor de la feature es la pieza y sus garantías.
- **FK a `publicacion`.** El `put` de la caché requiere que la publicación exista
  (lo está: la generación recupera fragmentos con `JOIN publicacion`).
