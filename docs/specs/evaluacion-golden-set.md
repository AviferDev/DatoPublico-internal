# Feature Implementation Spec: Evaluación de calidad con golden set

## Source Feature

- `id`: evaluacion-golden-set
- `ft_id`: FT00024 (registrado en `docs/feature-ids.md`)
- `parts`: none (atómica; ~12 ficheros de producto, por debajo del límite de 30)
- `area`: simplificacion-ia
- `depends_on`: generacion-resumen-go (FT00020, `accepted`). **Recomendado añadir
  `guardrails-anti-alucinacion` (FT00022)**: las métricas reutilizan el
  normalizador léxico puro `SummaryTextNormalizer` de FT00022 (ver *Risks*).
- `status`: not_started (al planificar)
- `source`: `feature_list.json`
- `claim`: rama `feat/ft00024-evaluacion-golden-set` (ya creada y pusheada por el
  orquestador).

> **Encaje con FT00018–FT00022.** FT00024 **no** cambia la generación ni el
> cacheo ni los guardrails: **reutiliza** las piezas ya implementadas y sin
> wiring — `rag/summary/CitizenSummaryGenerator` + `CitizenSummaryResult`
> (FT00020/FT00021), `SummaryGenerationDto` (FT00020),
> `SummaryTextNormalizer` (FT00022) y, para la CLI, `HybridSearch`/
> `FragmentIndexer` (FT00017), `E5EmbeddingProvider` (FT00015),
> `OpenCodeTextGenerationProvider`/`OpenCodeConfig` (FT00020) y
> `Database`/`DatabaseConfig` (FT00003). Es la tarea `0.4-T05` que FT00018 dejó
> expresamente fuera de alcance («Evaluación de resúmenes/chat… FT00024»).

## Goal

Añadir en `:backend`, como **librería y herramienta one-shot sin wiring**, la
**evaluación de calidad de los resúmenes ciudadanos** (tarea `0.4-T05`): un
**golden set versionado de publicaciones con resumen de referencia** y una
medición **determinista y offline** del **acierto en «¿Qué cambia?» y «¿A quién
afecta?»**, ejecutable con **un comando** (`:backend:evaluateSummary`) y cuyo
resultado queda **registrado** (log JSON estructurado + resumen en stdout).

La generación real (OpenCode) se ejecuta **detrás de una costura inyectable**
(`SummaryGenerator`), de modo que el **gate es determinista y sin red/BD** (usa
un doble) y la ejecución real contra OpenCode + PostgreSQL + modelo E5 es
**opt-in**. La comparación con el resumen de referencia usa métricas **puras**
(F1 léxico por campo + *recall* de cifras) sobre el normalizador ya existente.

## Non-Goals

- **Cambiar** la generación, el prompt, el parser, la caché o los guardrails:
  FT00024 **solo mide** lo existente. `CitizenSummaryGenerator`,
  `SummaryGenerationDto`, `CitizenSummaryValidator`, `SummaryGuardrail` y
  `SummaryTextNormalizer` se **reutilizan** sin modificar.
- **Juez LLM (LLM-as-judge)** como métrica del gate: se descarta (no es
  determinista ni offline). No se añade.
- **Endpoints/API/UI** de evaluación → FT00026+/no aplica.
- **Wiring en el arranque**: `Application.kt`, `ingesta/job/`, `ingesta/backfill/`
  intactos.
- **Persistir el histórico de evaluaciones** en una tabla: **sin migración nueva**
  (registro por log JSON + stdout).
- **Evaluación de recuperación** (FT00018) y **de chat** (FT00025): otras
  métricas; no se tocan.
- **Ajuste automático del prompt** a partir del resultado: fuera de alcance (el
  resultado informa una decisión humana; `PROMPT_VERSION` se sube a mano).
- **Métricas de sistema** (latencia, memoria, coste de tokens): fuera de alcance.

## Job Story

Cuando construyo la simplificación con IA sobre el BOE,
quiero medir con un golden set de publicaciones y resúmenes de referencia el
acierto de «¿Qué cambia?» y «¿A quién afecta?» con un comando reproducible,
para poder detectar regresiones y decidir con datos antes de publicar y de
construir la cola de revisión y el chat encima.

## Users And Permissions

- Desarrollador / responsable de calidad (interno): ejecuta la evaluación a mano
  con la tarea Gradle sobre el PostgreSQL de `docker-compose`, el modelo E5 local
  y la clave `OPENCODE_API_KEY`. Sin cuentas, sin datos personales, sin
  autenticación. Conexión derivada de `POSTGRES_*` (fail-fast si falta la
  contraseña); clave de OpenCode por entorno (fail-fast si falta); modelo por ruta
  de entorno o directorio por defecto (fail-fast si no existe). La ejecución real
  es **opt-in**; el gate no toca red, BD, modelo ni OpenCode.

## Acceptance Scenarios

### Scenario 1: métricas puras correctas

Given un resumen generado y un resumen de referencia,
When se llama a `SummaryQualityMetrics.tokenF1` y `figuresRecall`,
Then devuelven los valores esperados (incluidos los casos límite: sin solape,
solape total, referencia sin cifras, tokens vacíos).

### Scenario 2: el golden set versionado parsea y es coherente

Given el recurso `rag/eval/summary-golden-set.json`,
When se carga con `SummaryGoldenSetLoader`,
Then produce un dataset con `entries` no vacío, ids únicos, cada entrada con
publicación (con categoría y texto) y un resumen de referencia con
«¿Qué cambia?» y «¿A quién afecta?» no vacíos.

### Scenario 3: dataset inválido falla en claro

Given un JSON sin entradas, con ids duplicados, con una entrada sin categoría o
con un resumen de referencia con un campo vacío,
When se carga,
Then falla con `IllegalArgumentException` y mensaje claro, **sin** abrir conexión
ni invocar al generador.

### Scenario 4: el evaluador agrega el acierto por entrada

Given un dataset de prueba y un generador (doble determinista),
When se llama a `SummaryQualityEvaluator.evaluate(dataset)`,
Then se genera una vez por entrada, se calcula el F1 de cada campo y el *recall*
de cifras contra la referencia, se deriva el `hit` por entrada y se devuelven las
medias y la tasa de acierto (`hitRate`), sin `NaN`.

### Scenario 5: un resumen inválido cuenta como fallo

Given un generador que devuelve `CitizenSummaryResult.Invalid`,
When se evalúa,
Then esa entrada no lanza: se registra como fallo (F1 = 0 en ambos campos,
`invalid = true`) y se contabiliza en `invalidCount`.

### Scenario 6: el gate sigue sin red, BD, modelo ni OpenCode

Given el runner de CI sin PostgreSQL, sin Docker, sin el modelo E5 y sin
`OPENCODE_API_KEY`,
When se ejecuta `./gradlew build -PskipClient`, `./gradlew test`, `./gradlew
detekt` o `.harness/init.sh`,
Then todo está en verde; los tests de métricas/dataset/evaluador corren con
dobles y la prueba real se omite sin abrir conexión ni invocar al proveedor.

### Scenario 7: evaluación real de extremo a extremo (opt-in)

Given PostgreSQL migrado (Docker), el modelo E5 descargado y `OPENCODE_API_KEY`,
When se ejecuta `OPENCODE_LIVE_TEST=1 DB_LIVE_TEST=1 EMBEDDING_LIVE_TEST=1
./gradlew :backend:evaluateSummary`,
Then el corpus del golden set se indexa con el modelo real, cada publicación se
resume con `CitizenSummaryGenerator` (OpenCode), se mide el acierto contra su
referencia y se registra un evento JSON `event=summary.evaluation.completed` con
las medias de F1 de ambos campos, el *recall* de cifras y la tasa de acierto,
junto a un resumen legible por entrada.

## Repository Research

### Files Inspected

- `.harness/feature_list.json` (FT00018 `accepted`, FT00020/FT00021 `accepted`,
  FT00022 `in_progress`, FT00024 `not_started`), `PROGRESS.md` (Sessions
  048–055), `docs/feature-ids.md`, `docs/roadmap.md` §0.4.0 (`0.4-T05`),
  `docs/build-brief.md` (Validation Plan/Success Criteria),
  `docs/domain-model.md` (Resumen ciudadano + Confianza),
  `ARCHITECTURE.md`, `CONSTRAINTS.md` (§«Evaluación de recuperación», §«Generación
  de resumen ciudadano», §«Estilo», §«Nombres», §«Operación»), skill
  **`rag-datapublico`** §5/§6/§7, `docs/specs/evaluacion-recuperacion.md`
  (FT00018), `docs/adr/0013`, `docs/adr/README.md`.
- Producto `..`:
  - `backend/src/main/kotlin/…/backend/rag/summary/CitizenSummaryGenerator.kt`
    (`suspend generate(publication, limit): CitizenSummaryResult`),
    `CitizenSummaryResult.kt`, `SummaryGenerationDto.kt`
    (`queCambia`/`aQuienAfecta`/`cifrasClave`/`plazo` + `toResumenDto(source)`),
    `CitizenSummaryPromptBuilder.kt` (`PROMPT_VERSION`),
    `SummaryOutputParser.kt`.
  - `backend/src/main/kotlin/…/backend/rag/guardrails/SummaryTextNormalizer.kt`
    (`object` puro: `tokens`, `contentTokens`, `figures`, `sentences`).
  - `backend/src/main/kotlin/…/backend/rag/evaluation/` (FT00018:
    `RetrievalGoldenSet.kt` con `RetrievalGoldenSetLoader` + DTOs,
    `RetrievalMetrics.kt`, `RetrievalEvaluator.kt` con `fun interface Retriever`,
    `RetrievalEvaluationLog.kt`, `RetrievalEvaluationMain.kt`) — **patrón exacto a
    seguir**.
  - `backend/src/main/kotlin/…/backend/rag/generation/` (`TextGenerationProvider`,
    `OpenCodeConfig`, `OpenCodeTextGenerationProvider`),
    `rag/retrieval/HybridSearch.kt`, `rag/indexing/FragmentIndexer.kt`,
    `rag/embeddings/E5EmbeddingProvider.kt`, `persistence/PublicationRepository.kt`,
    `persistence/FragmentRepository.kt`, `infra/Database.kt`/`DatabaseConfig.kt`,
    `ingesta/publicacion/Publicacion.kt`.
  - `backend/src/main/resources/rag/eval/golden-set.json` (FT00018),
    `backend/build.gradle.kts` (tareas `backfill` y `evaluateRetrieval`
    `JavaExec` fuera de `build`/`check`), `backend/src/test/kotlin/…/rag/evaluation/`
    (tests de gate + `RetrievalEvaluationLiveTest`).
- Git: rama `feat/ft00024-evaluacion-golden-set` (claim).

### Existing Patterns To Follow

- **Métricas puras** en un `object` sin dependencias, con test en espejo del
  paquete; **servicios** que componen colaboradores inyectables sin conocer Ktor.
- **Golden set versionado** en recursos de `main` (`/rag/eval/*.json`) + loader
  `object` con **fail-fast** (`IllegalArgumentException`) y override por fichero.
- **DTOs `@Serializable`** con sufijo `Dto` y `@SerialName` explícito en **cada**
  propiedad; **modelo interno sin sufijo** (`SummaryGoldenSet`,
  `SummaryGoldenSetEntry`, `SummaryQualityResult`…).
- **Costura inyectable** con `fun interface` (`SummaryGenerator`, análoga a
  `Retriever`); el doble determinista vive en el test del paquete.
- **CLI one-shot** (`main()` + tarea Gradle `JavaExec` **no** enganchada a
  `build`/`check`), con fail-fast y cierre de recursos en `finally`
  (`RetrievalEvaluationMain`).
- **Log JSON estructurado** con clave estable `event` y mapas de campos **puros**
  (`RetrievalEvaluationLog`).
- **Tests opt-in por variable de entorno** fuera del gate; sin la variable, el
  `@Test` se omite sin abrir sockets ni cargar el modelo.
- **Identificadores en inglés; KDoc/comentarios en castellano**; **estilo MUST**:
  un solo `return`, sin `else if`, funciones ≤40 líneas; **reutilizar** antes de
  escribir.

### Current Gaps

- No existe ningún conjunto de publicaciones con resumen de referencia (golden
  set de resúmenes).
- No existe lógica de comparación de resúmenes (F1 léxico por campo, *recall* de
  cifras) ni una tasa de acierto.
- No existe un comando de evaluación de resúmenes ni un registro estructurado de
  su resultado.
- `CitizenSummaryGenerator` (FT00020) aún no tiene un consumidor de producto; la
  evaluación es su primer consumidor (junto a la futura publicación FT00026+).

## Technical Approach

### `rag/evaluation/SummaryQualityMetrics.kt` (puro, sin dependencias)

`object SummaryQualityMetrics` que reutiliza `SummaryTextNormalizer` (FT00022):

```kotlin
fun tokenF1(hypothesis: String, reference: String): Double
fun figuresRecall(summary: SummaryGenerationDto, referenceFigures: List<String>): Double
```

Definiciones documentadas en KDoc (multiconjunto de `contentTokens`):
`precision = |∩| / |hipótesis|`, `recall = |∩| / |referencia|`,
`F1 = 2·P·R / (P+R)` (`0.0` si `P+R = 0` o la referencia no tiene términos);
`figuresRecall` = fracción de cifras de la referencia presentes en las cifras del
resumen (unión de `queCambia` + `aQuienAfecta` + `cifrasClave`), `1.0` si la
referencia no tiene cifras (verdad vacua). **Sin** red, BD, reloj ni estado.

### `rag/evaluation/SummaryGoldenSet.kt` (DTOs + modelo + loader)

- **DTOs `@Serializable`** (sufijo `Dto`, `@SerialName` en cada propiedad):
  `SummaryGoldenSetDto` (`version`, `entries`), `SummaryGoldenSetEntryDto`
  (`id`, `title`, `date`, `section`, `category`, `organization`, `text`,
  `reference`). `section`/`category` reutilizan `SeccionBoeDto`/`CategoriaDto`;
  **`reference` reutiliza `SummaryGenerationDto`** (FT00020) — es exactamente la
  forma del resumen de referencia (`queCambia`/`aQuienAfecta`/`cifrasClave`/
  `plazo`).
- **Modelo interno sin sufijo**: `SummaryGoldenSet(version,
  entries: List<SummaryGoldenSetEntry>)` y
  `SummaryGoldenSetEntry(id, publication: Publicacion,
  reference: SummaryGenerationDto)`. La entrada se mapea a `Publicacion`
  (reutilizando el modelo existente) para pasarla al generador.
- **Loader** `object SummaryGoldenSetLoader`: `parse(json)` (puro, con
  `DatoPublicoJson`) y `load(path: String? = null)` (recurso de classpath por
  defecto `/rag/eval/summary-golden-set.json`, o fichero). Valida y **fail-fast**
  con `IllegalArgumentException`: `version` no vacía, `entries` no vacío, ids
  únicos, cada entrada con `category` presente y `text`/`title` no vacíos, y el
  resumen de referencia con `queCambia`/`aQuienAfecta` no vacíos.

### `rag/evaluation/SummaryQualityEvaluator.kt` (servicio, sin BD)

```kotlin
/** Generador inyectable; `CitizenSummaryGenerator::generate` encaja con esta firma. */
fun interface SummaryGenerator {
    suspend fun generate(publication: Publicacion, limit: Int): CitizenSummaryResult
}

class SummaryQualityEvaluator(
    private val generator: SummaryGenerator,
    private val hitThreshold: Double = DEFAULT_HIT_THRESHOLD,
)
```

`evaluate(dataset)` es **`suspend`**: genera una vez por entrada, y por cada
resultado **`Valid`** calcula `whatChangesF1`/`whoIsAffectedF1` (`tokenF1` de
cada campo contra su referencia) y `figuresRecall`; un resultado **`Invalid`**
**no lanza**: se registra como fallo (`0.0`/`0.0`/`0.0`, `invalid = true`) y suma
`invalidCount`. Por entrada, `hit = whatChangesF1 >= hitThreshold &&
whoIsAffectedF1 >= hitThreshold`. Agrega **medias sin `NaN`** con un helper
`List<Double>.mean()` (`0.0` si vacío) y `hitRate = hits / entries`.

Resultados en valores internos sin sufijo: `SummaryQualityResult(entryCount,
meanWhatChangesF1, meanWhoIsAffectedF1, meanFiguresRecall, hitRate, invalidCount,
perEntry)` y `SummaryEntryResult(entryId, whatChangesF1, whoIsAffectedF1,
figuresRecall, hit, invalid)`. `DEFAULT_HIT_THRESHOLD = 0.5` (documentado,
ajustable; el umbral exacto se calibra con datos reales, no en el gate).

### `rag/evaluation/SummaryEvaluationLog.kt` (log JSON, puro + emisión)

Eventos estables `summary.evaluation.started` / `summary.evaluation.completed`
con claves `event`, `dataset_version`, `entries`, `what_changes_f1`,
`who_is_affected_f1`, `figures_recall`, `hit_rate`, `invalid`; mapas de campos
**puros** (`startedFields`, `completedFields`) y funciones
`logStarted`/`logCompleted` (mismo patrón que `RetrievalEvaluationLog`, con
`StructuredArguments`). Sin telemetría: canal = stdout.

### `rag/evaluation/SummaryEvaluationMain.kt` (CLI one-shot)

`main()` compone `Database.createDataSource(DatabaseConfig.fromEnv())`, resuelve
las rutas del modelo (`EMBEDDING_MODEL_PATH`/`EMBEDDING_TOKENIZER_PATH` o
`backend/models/multilingual-e5-small/`) y `OpenCodeConfig.fromEnv()` (fail-fast
de `OPENCODE_API_KEY`), construye `E5EmbeddingProvider.from(...)`,
`OpenCodeTextGenerationProvider` y `CitizenSummaryGenerator(HybridSearch(...),
provider)` con **fail-fast** si faltan DB, modelo o clave. Carga el golden set
(`SummaryGoldenSetLoader.load()`; ruta override opcional por `SUMMARY_EVAL_DATASET`),
indexa el corpus (`PublicationRepositoryJdbc.save` + `FragmentIndexer.index` por
publicación, idempotente), evalúa con
`SummaryQualityEvaluator { publication, limit -> generator.generate(publication, limit) }`,
**emite el log estructurado**, imprime el resumen por entrada + agregado y cierra
provider y pool en `finally`. Sale con código ≠ 0 y mensaje claro si algo falla.
**No** se cablea en el arranque.

### `backend/src/main/resources/rag/eval/summary-golden-set.json` (dataset versionado)

Formato (autocontenido y reproducible):

```json
{
  "version": "1.0.0",
  "entries": [
    {
      "id": "EVAL-S1",
      "title": "Convocatoria de ayudas …",
      "date": "2026-10-09",
      "section": "III",
      "category": "BECAS_SUBVENCIONES_Y_AYUDAS",
      "organization": "Ministerio de Universidades",
      "text": "Artículo 1\n…\nArtículo 2\n…",
      "reference": {
        "queCambia": "Se convocan ayudas para prácticas formativas …",
        "aQuienAfecta": "Estudiantes universitarios que cursen titulaciones oficiales …",
        "cifrasClave": ["2.000 ayudas", "6 meses"]
      }
    }
  ]
}
```

Corpus **modesto** (unas pocas publicaciones de secciones/categorías distintas,
con encabezados `Artículo N` explícitos para que el `order` del chunker sea
determinista y legible, y una de empleo/beca con plazo). Los `id` llevan prefijo
`EVAL-S` para no colisionar con datos reales ni con `EVAL-` de FT00018. Los
tokens exactos y el tamaño del set los fija el implementador; el spec fija la
**estructura** y las validaciones.

### Sin wiring y sin anticipar lo diferido

`Application.kt`, `ingesta/`, `rag/summary/`, `rag/generation/`,
`rag/guardrails/`, `rag/retrieval/`, `rag/indexing/`, `rag/chunking/`,
`rag/embeddings/`, `persistence/`, `infra/`, migraciones (`V1`–`V4`), `:shared`,
`:composeApp`, `.github/workflows/ci.yml` e `init.sh` quedan **intactos** (salvo
la tarea Gradle nueva). Sin dependencias Gradle nuevas. Sin migración nueva.
Dirección de dependencia: `rag/evaluation` (capa superior) depende de
`rag/summary`, `rag/guardrails`, `rag/retrieval`, `rag/indexing`,
`rag/embeddings` y `persistence` (correcto).

## Expected File Changes

Rutas en el repo de producto (`..`); `es/aviferdev/datopublico/backend` se abrevia
como `…/backend`:

- `backend/src/main/kotlin/…/backend/rag/evaluation/SummaryQualityMetrics.kt` —
  create; métricas puras.
- `backend/src/main/kotlin/…/backend/rag/evaluation/SummaryGoldenSet.kt` —
  create; DTOs `@Serializable`, modelo interno y loader con fail-fast.
- `backend/src/main/kotlin/…/backend/rag/evaluation/SummaryQualityEvaluator.kt` —
  create; `SummaryGenerator` + agregación del acierto.
- `backend/src/main/kotlin/…/backend/rag/evaluation/SummaryEvaluationLog.kt` —
  create; eventos JSON estructurados.
- `backend/src/main/kotlin/…/backend/rag/evaluation/SummaryEvaluationMain.kt` —
  create; CLI one-shot.
- `backend/src/main/resources/rag/eval/summary-golden-set.json` — create; dataset
  versionado.
- `backend/src/test/kotlin/…/backend/rag/evaluation/SummaryQualityMetricsTest.kt`
  — create; gate, métricas y casos límite.
- `backend/src/test/kotlin/…/backend/rag/evaluation/SummaryGoldenSetTest.kt` —
  create; gate, parseo del recurso real + fail-fast de datasets inválidos.
- `backend/src/test/kotlin/…/backend/rag/evaluation/SummaryQualityEvaluatorTest.kt`
  — create; gate, con `SummaryGenerator` doble (incluye el caso `Invalid`).
- `backend/src/test/kotlin/…/backend/rag/evaluation/SummaryEvaluationLiveTest.kt`
  — create; **opt-in** `OPENCODE_LIVE_TEST=1` + `DB_LIVE_TEST=1` +
  `EMBEDDING_LIVE_TEST=1`.
- `backend/build.gradle.kts` — modify; tarea `JavaExec` `evaluateSummary`
  (grupo `application`, fuera de `build`/`check`).
- `docs/desarrollo-local.md` — modify; sección de evaluación de resúmenes
  (comandos opt-in).

Harness (privado): `ARCHITECTURE.md`, `CONSTRAINTS.md`, ADR `0018` + índice,
`.agents/skills/rag-datapublico/SKILL.md`, `feature_list.json`, `PROGRESS.md`
(ver *Durable Documentation Impact*).

**Sin cambios** en `rag/summary/`, `rag/generation/`, `rag/guardrails/`,
`rag/retrieval/`, `rag/indexing/`, `rag/chunking/`, `rag/embeddings/`,
`persistence/`, `infra/`, migraciones, `Application.kt`, `ingesta/`, `:shared`,
`:composeApp`, la raíz del build, CI e `init.sh`.

## Visual Design Impact

- UI involved: no. Sin pantallas, tokens ni textos de UI.

## Durable Documentation Impact

- `ARCHITECTURE.md`: update — `rag/evaluation/` gana la **evaluación de resúmenes**
  (golden set de publicaciones + referencia, métricas F1 puras, CLI one-shot);
  subrayar que **no** cambia la generación ni los guardrails y que sigue **sin
  wiring**.
- `CONSTRAINTS.md`: update — nueva sección **«Evaluación de resúmenes»** con
  MUST: el golden set es **versionado** (`rag/eval/summary-golden-set.json`) y su
  estructura/validaciones son las del spec; las métricas son **puras** (F1 léxico
  + *recall* de cifras, sin red/BD/reloj) y testables sin BD; el gate usa un
  generador **doble**; la ejecución real es **opt-in** (`OPENCODE_LIVE_TEST=1` +
  `DB_LIVE_TEST=1` + `EMBEDDING_LIVE_TEST=1`) con la tarea
  `:backend:evaluateSummary` **fuera** de `build`/`check`; **no** se persiste el
  histórico ni se añade migración; la evaluación **no** cambia la generación.
- `AGENTS.md`: not needed — no cambia el flujo ni el camino de arranque.
- **ADR `docs/adr/0018-evaluacion-resumenes-golden-set.md`** (recomendado;
  siguiente número libre tras 0017): decisión durable «evaluación de la calidad
  del resumen ciudadano con golden set versionado de publicaciones + resumen de
  referencia, métricas léxicas puras (F1 por campo + *recall* de cifras) y CLI
  one-shot opt-in; sin juez LLM, sin cambiar la generación ni persistir el
  histórico». El planner **no** lo crea; lo escribe el implementador/orquestador y
  lo inscribe en `docs/adr/README.md`.
- `.agents/skills/rag-datapublico/SKILL.md`: update — §7 «Estado actual del
  producto (FT00024)» (golden set de resúmenes, métricas y comando).
- `docs/desarrollo-local.md` (producto): update — comandos opt-in de la
  evaluación de resúmenes.
- `feature_list.json`/`PROGRESS.md`: los cierra el orquestador (incluida, si se
  acepta, la recomendación de añadir `guardrails-anti-alucinacion` a
  `depends_on`).

## Implementation Plan

1. Crear `SummaryQualityMetrics` (puro) y `SummaryQualityMetricsTest`.
2. Crear los DTOs/modelo/loader del golden set (`SummaryGoldenSet`) y
   `SummaryGoldenSetTest` (recurso real + fail-fast); autorizar el dataset
   `rag/eval/summary-golden-set.json`.
3. Crear `SummaryQualityEvaluator` (`SummaryGenerator`) y
   `SummaryQualityEvaluatorTest`.
4. Crear `SummaryEvaluationLog` y la CLI `SummaryEvaluationMain`; registrar la
   tarea `evaluateSummary` en `backend/build.gradle.kts`.
5. Añadir `SummaryEvaluationLiveTest` (`OPENCODE_LIVE_TEST=1` +
   `DB_LIVE_TEST=1` + `EMBEDDING_LIVE_TEST=1`).
6. Ejecutar el gate sin red ni BD y la evaluación real opt-in; actualizar
   `ARCHITECTURE.md`, `CONSTRAINTS.md`, ADR 0018 + índice, skill RAG y
   `docs/desarrollo-local.md`. `PROGRESS.md`/`feature_list.json` los cierra el
   orquestador.

## Implementation Tasks

- [ ] `SummaryQualityMetrics`: `tokenF1` + `figuresRecall` (puros, con casos
      límite documentados; reutiliza `SummaryTextNormalizer`).
- [ ] `SummaryGoldenSet`: DTOs `@Serializable` (`@SerialName` en cada propiedad) +
      modelo interno + loader con fail-fast.
- [ ] `summary-golden-set.json`: corpus modesto con encabezados `Artículo N`,
      referencias `queCambia`/`aQuienAfecta` y cifras clave (incl. una
      convocatoria de empleo/beca).
- [ ] `SummaryQualityEvaluator`: `SummaryGenerator` + `evaluate(dataset)` con
      medias, `hitRate` y `invalidCount`.
- [ ] `SummaryEvaluationLog`: eventos `summary.evaluation.*` y campos puros.
- [ ] `SummaryEvaluationMain`: CLI que indexa el corpus, genera y evalúa.
- [ ] Tarea Gradle `:backend:evaluateSummary` (fuera de `build`/`check`).
- [ ] `SummaryQualityMetricsTest`, `SummaryGoldenSetTest`,
      `SummaryQualityEvaluatorTest` (gate, sin red/BD/modelo/OpenCode).
- [ ] `SummaryEvaluationLiveTest` (`OPENCODE_LIVE_TEST=1` + `DB_LIVE_TEST=1` +
      `EMBEDDING_LIVE_TEST=1`).
- [ ] Docs durables: ARCHITECTURE, CONSTRAINTS, ADR 0018 + índice, skill RAG,
      `docs/desarrollo-local.md`.

## Verification Plan

Desde la raíz del producto (`..`, JDK 21 vía JBR/`JAVA_HOME`):

- **Gate sin red ni BD (obligatorio)**: `./gradlew :backend:test --rerun-tasks` →
  BUILD SUCCESSFUL con `SummaryQualityMetricsTest`, `SummaryGoldenSetTest` y
  `SummaryQualityEvaluatorTest` en verde (0 fallos) y el resto de `:backend`
  intacto. `./gradlew build -PskipClient` (incluye `:backend:detekt` y
  `:cpdCheck`), `./gradlew test`, `./gradlew detekt` y
  `env -u JAVA_HOME .harness/init.sh` → exit 0.
- **Offline confirmado**: los tests del gate **no** abren conexión ni invocan a
  OpenCode ni cargan el modelo; el test live se **omite** sin
  `OPENCODE_LIVE_TEST`/`DB_LIVE_TEST`/`EMBEDDING_LIVE_TEST`.
- **Escenario 7 (opt-in, fuera del gate y de la CI)**:
  ```sh
  backend/tools/download-embedding-model.sh
  cp .env.example .env && docker compose up -d
  ./gradlew :backend:flywayMigrate
  OPENCODE_API_KEY=… OPENCODE_LIVE_TEST=1 DB_LIVE_TEST=1 EMBEDDING_LIVE_TEST=1 \
    ./gradlew :backend:evaluateSummary
  OPENCODE_API_KEY=… OPENCODE_LIVE_TEST=1 DB_LIVE_TEST=1 EMBEDDING_LIVE_TEST=1 \
    ./gradlew :backend:test --tests '*SummaryEvaluationLiveTest'
  ```
  Esperado: el corpus se indexa con el modelo E5 real, cada publicación se resume
  con OpenCode, se mide el acierto contra su referencia y se registra
  `event=summary.evaluation.completed` con las medias de F1, el *recall* de cifras
  y la tasa de acierto; el test live afirma un **umbral conservador documentado**
  (p. ej. `meanWhatChangesF1 >= 0.3` y `hitRate >= 0.3`) e imprime las métricas
  reales para la evidencia.
- **E2E**: no aplica — no hay flujo de usuario ni endpoint nuevo (el repo no tiene
  comando E2E; el cliente es Compose Multiplatform). El comando de evaluación es
  la verificación observable de esta feature.
- `init.sh` (harness): **no** se modifica; la tarea `evaluateSummary` **no** se
  engancha a `build`/`check`.

## Evidence To Capture

- Salida de `./gradlew :backend:test` con los tests nuevos de gate (recuento, 0
  fallos) y del gate (`build -PskipClient`, `test`, `detekt`, `init.sh` exit 0).
- Salida de la evaluación real opt-in: evento JSON
  `event=summary.evaluation.completed` con las medias de F1 de ambos campos, el
  *recall* de cifras y la tasa de acierto, más el resumen por entrada; resultado
  del `SummaryEvaluationLiveTest`.
- Ficheros del commit `FT00024`, PR y run de CI; entradas en `PROGRESS.md` y
  `feature_list.json` (`evidence`).

## Validator Checklist

- [ ] Alcance acotado: solo `rag/evaluation/` (ficheros `Summary*`) +
  `rag/eval/summary-golden-set.json` + la tarea Gradle + `docs/desarrollo-local.md`
  y sus tests; **sin** tocar `rag/summary/`, `rag/generation/`,
  `rag/guardrails/`, `rag/retrieval/`, `rag/indexing/`, `rag/chunking/`,
  `rag/embeddings/`, `persistence/`, `infra/`, migraciones, `Application.kt`,
  `ingesta/`, `:shared`, `:composeApp`, CI ni `init.sh`.
- [ ] Escenarios 1–7 pasan; **todo el gate corre sin red, BD, modelo ni OpenCode**
  y el live se omite sin sus variables.
- [ ] El golden set es versionado, válido y coherente (ids únicos, referencias no
  vacías, categoría presente); un dataset inválido falla con
  `IllegalArgumentException` sin abrir conexión.
- [ ] Las métricas son puras y correctas en los casos límite; el evaluador agrega
  medias sin `NaN`, cuenta `Invalid` como fallo y pasa cada publicación al
  generador.
- [ ] La CLI registra `event=summary.evaluation.completed` con las métricas y
  cierra pool, modelo y cliente; la tarea **no** está enganchada a
  `build`/`check`.
- [ ] `return` único, sin `else if`, funciones ≤40 líneas, KDoc en castellano con
  identificadores en inglés; `@SerialName` explícito en todo `@Serializable`.
- [ ] `ARCHITECTURE.md`, `CONSTRAINTS.md`, ADR 0018 + índice, skill RAG,
  `docs/desarrollo-local.md`, `PROGRESS.md` y `feature_list.json` actualizados.
- [ ] No unrelated product behavior or extra feature work was added.

## Risks / Open Questions

- **Dependencia de `SummaryTextNormalizer` (FT00022).** Las métricas reutilizan el
  normalizador puro de FT00022. FT00024 declara `depends_on` solo FT00020;
  **recomendación**: añadir `guardrails-anti-alucinacion` a `depends_on` (FT00022
  está `in_progress` y se aceptará antes). Alternativa si FT00022 no estuviera
  disponible: tokenizar localmente (minúsculas + sin acentos + alfanumérico) en
  `SummaryQualityMetrics`, asumiendo una ligera duplicación. El planner **no**
  edita `feature_list.json`; lo aplica el orquestador.
- **Calidad del golden set.** Las referencias se escriben a mano y el corpus es
  pequeño; el acierto depende de la redacción de la referencia. Mitigación: el
  loader valida la coherencia y las cifras reales quedan como evidencia (no como
  aserción ajustada).
- **F1 léxico penaliza paráfrasis válidas.** La comparación es léxica (sin
  *stemming* ni sinónimos): una paráfrasis correcta puede bajar el F1. Se asume
  como límite documentado; el umbral de `hit` es **conservador y ajustable** y el
  objetivo es detectar **regresiones**, no certificar calidad absoluta.
- **Calibración del umbral.** `DEFAULT_HIT_THRESHOLD = 0.5` es un punto de
  partida; el valor definitivo se fija con datos reales. El gate no depende del
  valor (usa un doble determinista); el test live usa un umbral conservador.
- **Opt-in más pesado.** La ejecución real exige PostgreSQL + modelo E5 + clave de
  OpenCode (tres recursos), a diferencia de FT00018 (dos). Queda documentado; el
  gate no lo cubre (limitación aceptada).
- **Duplicación (CPD).** El loader y la CLI siguen el patrón de
  `RetrievalGoldenSetLoader`/`RetrievalEvaluationMain`; mantenerlos **mínimos** y
  locales al paquete para no disparar `:cpdCheck` (umbral 100 tokens). Si CPD
  señala duplicación, extraer un helper `internal` compartido (p. ej. lectura de
  recurso de classpath) es un refactor aditivo permitido, sin cambio de
  comportamiento.
- **Acoplamiento a la firma del generador.** `SummaryGenerator` es un `fun
  interface` `suspend` que `CitizenSummaryGenerator::generate` satisface; si su
  firma cambia, se ajusta el adaptador de la CLI sin tocar las métricas (que no
  conocen el generador).
- **Sin persistencia del histórico.** «Registrar el resultado» se interpreta como
  log JSON + stdout; persistir evaluaciones en una tabla exigiría migración y es
  un Non-Goal explícito.
- **Determinismo del corpus.** El `order` del chunker debe ser estable: se usan
  encabezados `Artículo N` explícitos, como en FT00018.
