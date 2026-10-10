# Feature Implementation Spec: Evaluación de recuperación (precision/recall)

## Source Feature

- `id`: evaluacion-recuperacion
- `ft_id`: FT00018 (registrado en `docs/feature-ids.md`)
- `parts`: none (atómica; ~12 ficheros de producto, por debajo del límite de 30)
- `area`: rag
- `depends_on`: recuperacion-hibrida (FT00017, `accepted`)
- `status`: not_started (al planificar)
- `source`: `feature_list.json`
- `claim`: rama `feat/ft00018-evaluacion-recuperacion` (parte de
  `feat/ft00017-recuperacion-hibrida` → `feat/ft00016-pgvector-indexado`, stack de
  PRs; FT00016/FT00017 `accepted` pero con PR #17/#18 aún sin fusionar).

> **Encaje con FT00014–FT00017.** FT00018 **no** cambia la recuperación: se apoya
> en las piezas ya implementadas y **sin wiring** — `rag/chunking/ArticleChunker`
> (FT00014), `rag/embeddings/EmbeddingProvider` + `E5EmbeddingProvider` (FT00015),
> `persistence/FragmentRepository` + `PgVector` + `V3` (FT00016),
> `rag/retrieval/HybridSearch` + `SearchFilter` (FT00017) y
> `rag/indexing/FragmentIndexer` (FT00017). FT00018 es la **evaluación**
> (tarea `0.3-T05`) que FT00017 dejó expresamente fuera de alcance.

## Goal

Añadir en `:backend`, como **librería y herramienta one-shot sin wiring**, la
**evaluación de la recuperación** (tarea `0.3-T05`): un **golden set** versionado
de consultas → fragmentos esperados y una evaluación que mide **precision@k,
recall@k y MRR** (medias por consulta), ejecutable con **un comando**
(`:backend:evaluateRetrieval`) y cuyo resultado queda **registrado** (log JSON
estructurado + resumen en stdout).

La evaluación indexa el **corpus del propio golden set** con el modelo E5 real
(`FragmentIndexer`) en PostgreSQL y ejecuta cada consulta con `HybridSearch`
(reutiliza FT00017 sin modificarla). La **lógica de métricas y el modelo del
dataset son puros y testables sin red ni BD** (gate); la ejecución real contra
PostgreSQL + modelo E5 es **opt-in**.

## Non-Goals

- **Cambiar** la recuperación, el `SearchFilter`, el chunker, los embeddings, el
  repositorio o la migración `V3`: FT00018 **solo mide** lo existente.
- **Endpoints/API/UI** de evaluación o de búsqueda → FT00026+/no aplica.
- **Wiring en el arranque**: `Application.kt`, `ingesta/job/`, `ingesta/backfill/`
  intactos.
- **Persistir el histórico de evaluaciones** en una tabla: **sin migración nueva**
  (registro por log JSON + stdout).
- **Evaluación de resúmenes/chat** (golden set de publicaciones, FT00024) o del
  **ranking de destacados** (FT00013): otras métricas.
- **Reranking, fusión léxica, `ef_search`, índice GIN/trigram**: se miden si
  existen, pero **no** se añaden aquí.
- **Indexar el corpus completo** del BOE: la evaluación usa su corpus de prueba.
- **Métricas de sistema** (latencia, memoria, coste): fuera de alcance.

## Job Story

Cuando construyo el RAG base sobre el BOE,
quiero medir con un conjunto de prueba versionado la calidad de la recuperación
(precision/recall/MRR) con un comando reproducible,
para poder detectar regresiones y decidir con datos antes de construir resúmenes
y chat encima.

## Users And Permissions

- Desarrollador / responsable de calidad (interno): ejecuta la evaluación a mano
  con la tarea Gradle sobre el PostgreSQL de `docker-compose` y el modelo E5
  local. Sin cuentas, sin datos personales, sin autenticación. Conexión derivada
  de `POSTGRES_*` (fail-fast si falta la contraseña); modelo por ruta de entorno
  o directorio por defecto, **fail-fast** si no existe. La ejecución real es
  **opt-in**; el gate no toca red, BD ni modelo.

## Acceptance Scenarios

### Scenario 1: métricas puras correctas

Given listas de fragmentos recuperados y conjuntos de fragmentos relevantes,
When se llama a `RetrievalMetrics.precisionAtK`/`recallAtK`/`reciprocalRank`,
Then devuelven los valores esperados (incluidos los casos límite: `k` mayor que
los recuperados, sin relevantes, sin aciertos, acierto en primera posición).

### Scenario 2: el golden set versionado parsea y es coherente

Given el recurso `rag/eval/golden-set.json`,
When se carga con `RetrievalGoldenSetLoader`,
Then produce un dataset con `k >= 1`, corpus y consultas no vacíos, ids únicos y
**cada fragmento esperado existe en el corpus** (publicación + `order` válidos).

### Scenario 3: dataset inválido falla en claro

Given un JSON sin corpus, con `k < 1`, con ids duplicados o con un fragmento
esperado que no está en el corpus,
When se carga,
Then falla con `IllegalArgumentException` y mensaje claro, **sin** abrir conexión.

### Scenario 4: el evaluador agrega las métricas por consulta

Given un dataset de prueba y un recuperador (doble determinista),
When se llama a `RetrievalEvaluator.evaluate(dataset, k)`,
Then se recupera una vez por consulta con su `SearchFilter` y su `k`, y devuelve
precision/recall/MRR por consulta y sus medias.

### Scenario 5: el gate sigue sin red, BD ni modelo

Given el runner de CI sin PostgreSQL, sin Docker y sin el modelo E5,
When se ejecuta `./gradlew build -PskipClient`, `./gradlew test`, `./gradlew
detekt` o `.harness/init.sh`,
Then todo está en verde; los tests de métricas/dataset/evaluador corren con
dobles y la prueba real se omite sin abrir conexión ni cargar el modelo.

### Scenario 6: evaluación real de extremo a extremo (opt-in)

Given PostgreSQL migrado (Docker) y el modelo E5 descargado,
When se ejecuta `DB_LIVE_TEST=1 EMBEDDING_LIVE_TEST=1 ./gradlew
:backend:evaluateRetrieval` (o el test live equivalente),
Then el corpus del golden set se indexa con el modelo real, cada consulta se
recupera con `HybridSearch`, y se registra un evento JSON
`event=retrieval.evaluation.completed` con `precision`/`recall`/`mrr` agregados
junto a un resumen legible por consulta.

## Repository Research

### Files Inspected

- `.harness/feature_list.json` (FT00018; FT00017 `accepted`), `PROGRESS.md`,
  `docs/feature-ids.md`, `docs/roadmap.md` §0.3.0 (`0.3-T05`),
  `docs/technical-discovery.md` («Pruebas de recuperación (precision/recall)»),
  `ARCHITECTURE.md`, `CONSTRAINTS.md` (§«Recuperación híbrida e indexado»,
  §«Estilo», §«Nombres», §«Operación»), skill **`rag-datapublico`** §7,
  `docs/specs/recuperacion-hibrida.md` (FT00017), `docs/adr/README.md`.
- Producto `..`:
  - `backend/src/main/kotlin/…/backend/rag/retrieval/HybridSearch.kt`
    (`search(query, filter, limit)`), `SearchFilter.kt`, `SearchFilterSql.kt`.
  - `backend/src/main/kotlin/…/backend/rag/indexing/FragmentIndexer.kt`
    (`index(publicacion): Int`).
  - `backend/src/main/kotlin/…/backend/persistence/FragmentRepository.kt`
    (`FragmentEntity`, `FragmentMatch`, `findNearest`), `PublicationRepository.kt`
    (`PublicationEntity`/`Publicacion`), `PgVector.kt`.
  - `backend/src/main/kotlin/…/backend/rag/embeddings/E5EmbeddingProvider.kt`
    (`from(modelPath, tokenizerPath)`, `DIMENSIONS`), `EmbeddingConfig.kt`.
  - `backend/src/main/kotlin/…/backend/ingesta/backfill/`
    (`BackfillMain.kt`, `BackfillConfig.kt`, `BackfillLog.kt`) — **patrón de la
    herramienta CLI one-shot + log JSON**.
  - `backend/src/main/kotlin/…/backend/ingesta/publicacion/Publicacion.kt`.
  - `backend/src/test/kotlin/…/backend/rag/retrieval/HybridSearchTest.kt`,
    `HybridSearchLiveTest.kt`, `…/rag/indexing/FragmentIndexerLiveTest.kt` —
    **patrón de dobles** y de **tests opt-in** (`DB_LIVE_TEST`/`EMBEDDING_LIVE_TEST`).
  - `backend/build.gradle.kts` (tarea `JavaExec` `backfill`, fuera de
    `build`/`check`), `backend/src/main/resources/db/migration/V2`/`V3`.
- Git: rama `feat/ft00018-evaluacion-recuperacion` (stack de PRs FT00016→FT00017).

### Existing Patterns To Follow

- **Métricas puras** en un objeto sin dependencias, con test en espejo del
  paquete; **servicios** que componen repositorio/proveedor sin conocer Ktor.
- **DTOs `@Serializable`** con sufijo `Dto` y `@SerialName` explícito en **cada**
  propiedad; **modelo interno sin sufijo** (p. ej. `EntradaSumario` → aquí
  `RetrievalGoldenSet`, `RetrievalQuery`, `FragmentRef`).
- **CLI one-shot** (`main()` + tarea Gradle `JavaExec` **no** enganchada a
  `build`/`check`), con fail-fast y cierre de recursos en `finally`
  (`BackfillMain`).
- **Log JSON estructurado** con clave estable `event` y mapas de campos **puros**
  (`BackfillLog`).
- **Tests opt-in por variable de entorno** fuera del gate; sin la variable, el
  `@Test` se omite sin abrir sockets ni cargar el modelo.
- **Identificadores en inglés; KDoc/comentarios en castellano**; **estilo MUST**:
  un solo `return`, sin `else if`, funciones ≤40 líneas; **reutilizar** antes de
  escribir (`HybridSearch`, `FragmentIndexer`, `E5EmbeddingProvider`,
  `DatoPublicoJson`, `Publicacion`).

### Current Gaps

- No existe ningún conjunto de consultas → fragmentos esperados (golden set).
- No existe lógica de métricas (precision/recall/MRR) en el proyecto.
- No existe un comando de evaluación ni un registro estructurado de su resultado.
- `HybridSearch`/`FragmentIndexer` son librerías sin ningún consumidor de
  producto todavía; FT00018 es su primer consumidor (junto al chat futuro).

## Technical Approach

### `rag/evaluation/RetrievalMetrics.kt` (puro, sin dependencias)

```kotlin
/** Referencia estable de un fragmento: publicación oficial + `order` del chunker. */
data class FragmentRef(val publicationId: String, val order: Int)

object RetrievalMetrics {
    fun precisionAtK(retrieved: List<FragmentRef>, relevant: Set<FragmentRef>, k: Int): Double
    fun recallAtK(retrieved: List<FragmentRef>, relevant: Set<FragmentRef>, k: Int): Double
    fun reciprocalRank(retrieved: List<FragmentRef>, relevant: Set<FragmentRef>): Double
}
```

Definiciones documentadas en KDoc: `precision@k = aciertos(top-k) /
min(k, recuperados)` (0 si no hay recuperados); `recall@k = aciertos(top-k) /
|relevantes|` (0 si no hay relevantes); `MRR = 1 / posición del primer acierto`
(0 si no hay). `FragmentRef` es valor interno **sin sufijo** (no serializable).

### `rag/evaluation/RetrievalGoldenSet.kt` (DTOs + modelo + loader)

- **DTOs `@Serializable`** (sufijo `Dto`, `@SerialName` en cada propiedad) que
  reflejan el JSON: `RetrievalGoldenSetDto` (`version`, `k`, `corpus`, `queries`),
  `RetrievalCorpusItemDto` (`id`, `title`, `date`, `section`, `category`,
  `organization`, `text`), `RetrievalQueryDto` (`id`, `query`, `filter`,
  `relevant`) con `RetrievalFilterDto` y `RetrievalRelevantDto`.
  `section`/`category` usan los enums `SeccionBoeDto`/`CategoriaDto` (token de
  wire estable).
- **Modelo interno sin sufijo**: `RetrievalGoldenSet(version, k,
  corpus: List<Publicacion>, queries: List<RetrievalQuery>)` y
  `RetrievalQuery(id, text, filter: SearchFilter, relevant: Set<FragmentRef>)`.
  El corpus se mapea a `Publicacion` (reutilizando el modelo existente) para
  pasarlo a `FragmentIndexer`.
- **Loader**: `RetrievalGoldenSetLoader.parse(json: String):
  RetrievalGoldenSet` (puro, con `DatoPublicoJson`) y `load(path: String? = null)`
  (recurso de classpath por defecto `/rag/eval/golden-set.json`, o fichero si se
  indica). Valida y **fail-fast** con `IllegalArgumentException`: `k >= 1`, corpus
  y consultas no vacíos, ids únicos y **cada `FragmentRef` relevante existe en el
  corpus** (`publicationId` presente y `order >= 0`).

### `rag/evaluation/RetrievalEvaluator.kt` (servicio, sin BD)

```kotlin
/** Recuperador inyectable; `HybridSearch::search` encaja con esta firma. */
fun interface Retriever {
    fun retrieve(query: String, filter: SearchFilter, limit: Int): List<FragmentMatch>
}

class RetrievalEvaluator(private val retriever: Retriever) {
    fun evaluate(dataset: RetrievalGoldenSet, k: Int = dataset.k): RetrievalEvaluationResult
}
```

`evaluate` valida `k >= 1`, recupera una vez por consulta (`retriever.retrieve`),
mapea cada `FragmentMatch` a `FragmentRef` (extensión interna
`FragmentMatch.toRef()`), calcula las tres métricas y **agrega medias**. Resultados
en valores internos sin sufijo: `RetrievalEvaluationResult(k, queryCount,
meanPrecision, meanRecall, meanMrr, perQuery)` y `RetrievalQueryResult(queryId,
precision, recall, reciprocalRank, retrieved)`. Las medias usan un helper
`List<Double>.mean()` (0.0 si vacío) para no producir `NaN`.

### `rag/evaluation/RetrievalEvaluationLog.kt` (log JSON, puro + emisión)

Objeto con eventos estables `retrieval.evaluation.started` /
`retrieval.evaluation.completed`, claves `event`, `dataset_version`, `k`,
`queries`, `precision`, `recall`, `mrr`; mapas de campos **puros** (`startedFields`,
`completedFields`) y funciones `logStarted`/`logCompleted` (mismo patrón que
`BackfillLog`, con `StructuredArguments`). Sin telemetría: canal = stdout.

### `rag/evaluation/RetrievalEvaluationMain.kt` (CLI one-shot)

`main()` compone `Database.createDataSource(DatabaseConfig.fromEnv())`, resuelve
las rutas del modelo (`EMBEDDING_MODEL_PATH`/`EMBEDDING_TOKENIZER_PATH` o
`backend/models/multilingual-e5-small/` por defecto) y construye
`E5EmbeddingProvider.from(...)` con **fail-fast** si faltan DB o modelo. Carga el
golden set (`RetrievalGoldenSetLoader.load()`; ruta override opcional por
`RETRIEVAL_EVAL_DATASET`, `k` override por `RETRIEVAL_EVAL_K`), indexa el corpus
(`FragmentIndexer.index` por publicación, idempotente), construye
`RetrievalEvaluator(Retriever { q, f, l -> HybridSearch(provider, repository).search(q, f, l) })`,
evalúa, **emite el log estructurado**, imprime el resumen por consulta + agregado
y cierra provider y pool en `finally`. Sale con código ≠ 0 y mensaje claro si algo
falla. **No** se cablea en el arranque.

### `backend/src/main/resources/rag/eval/golden-set.json` (dataset versionado)

Formato (autocontenido y reproducible):

```json
{
  "version": "1.0.0",
  "k": 5,
  "corpus": [
    {
      "id": "EVAL-1",
      "title": "Convocatoria de ayudas …",
      "date": "2026-10-09",
      "section": "III",
      "category": "BECAS_SUBVENCIONES_Y_AYUDAS",
      "organization": "Ministerio de Universidades",
      "text": "Artículo 1\n…\nArtículo 2\n…"
    }
  ],
  "queries": [
    {
      "id": "q-ayudas",
      "query": "ayudas para prácticas formativas de estudiantes",
      "filter": { "section": "III", "category": "BECAS_SUBVENCIONES_Y_AYUDAS" },
      "relevant": [ { "publicationId": "EVAL-1", "order": 0 } ]
    }
  ]
}
```

Corpus **modesto** (unas pocas publicaciones de secciones distintas, con
encabezados `Artículo N` explícitos para que el `order` del chunker sea
determinista y legible). Los `id` del corpus llevan prefijo `EVAL-` para no
colisionar con datos reales. El `k` y los tokens exactos se fijan en el
implementador; el spec fija la **estructura** y las validaciones.

### Sin wiring y sin anticipar lo diferido

`Application.kt`, `ingesta/`, `ArticleChunker`, `rag/embeddings/`, `rag/retrieval/`,
`rag/indexing/`, `persistence/`, `infra/`, migraciones, `:shared`, `:composeApp`,
`.github/workflows/ci.yml` e `init.sh` quedan **intactos** (salvo la tarea Gradle
nueva). Sin dependencias Gradle nuevas. Sin migración nueva. Dirección de
dependencia: `rag/evaluation` (capa superior) depende de `rag/retrieval`,
`rag/indexing`, `rag/embeddings` y `persistence` (correcto).

## Expected File Changes

Rutas en el repo de producto (`..`); `es/aviferdev/datopublico/backend` se abrevia
como `…/backend`:

- `backend/src/main/kotlin/…/backend/rag/evaluation/RetrievalMetrics.kt` — create;
  `FragmentRef` + métricas puras.
- `backend/src/main/kotlin/…/backend/rag/evaluation/RetrievalGoldenSet.kt` —
  create; DTOs `@Serializable`, modelo interno y loader con fail-fast.
- `backend/src/main/kotlin/…/backend/rag/evaluation/RetrievalEvaluator.kt` —
  create; `Retriever` + agregación de métricas.
- `backend/src/main/kotlin/…/backend/rag/evaluation/RetrievalEvaluationLog.kt` —
  create; eventos JSON estructurados.
- `backend/src/main/kotlin/…/backend/rag/evaluation/RetrievalEvaluationMain.kt` —
  create; CLI one-shot.
- `backend/src/main/resources/rag/eval/golden-set.json` — create; dataset
  versionado.
- `backend/src/test/kotlin/…/backend/rag/evaluation/RetrievalMetricsTest.kt` —
  create; gate, métricas y casos límite.
- `backend/src/test/kotlin/…/backend/rag/evaluation/RetrievalGoldenSetTest.kt` —
  create; gate, parseo del recurso real + fail-fast de datasets inválidos.
- `backend/src/test/kotlin/…/backend/rag/evaluation/RetrievalEvaluatorTest.kt` —
  create; gate, con `Retriever` doble.
- `backend/src/test/kotlin/…/backend/rag/evaluation/RetrievalEvaluationLiveTest.kt`
  — create; **opt-in** `DB_LIVE_TEST=1` + `EMBEDDING_LIVE_TEST=1`.
- `backend/build.gradle.kts` — modify; tarea `JavaExec` `evaluateRetrieval`
  (grupo `application`, fuera de `build`/`check`).
- `docs/desarrollo-local.md` — modify; sección de evaluación de recuperación
  (comandos opt-in).

Harness (privado): `ARCHITECTURE.md`, `CONSTRAINTS.md`, ADR `0013` + índice,
`.agents/skills/rag-datapublico/SKILL.md`, `feature_list.json`, `PROGRESS.md`
(ver *Durable Documentation Impact*).

**Sin cambios** en `rag/retrieval/`, `rag/indexing/`, `rag/chunking/`,
`rag/embeddings/`, `persistence/`, `infra/`, migraciones (`V1`/`V2`/`V3`),
`Application.kt`, `ingesta/`, `:shared`, `:composeApp`, la raíz del build, CI e
`init.sh`.

## Visual Design Impact

- UI involved: no. Sin pantallas, tokens ni textos de UI.

## Durable Documentation Impact

- `ARCHITECTURE.md`: update — `rag/` gana `evaluation/` (golden set, métricas
  puras, evaluador, CLI one-shot); subrayar que **no** cambia la recuperación y
  que sigue **sin wiring**.
- `CONSTRAINTS.md`: update — nueva sección **«Evaluación de recuperación»** con
  MUST: el golden set es **versionado** y su estructura/validaciones son las del
  spec; las métricas son **puras** y testables sin BD; la ejecución real es
  **opt-in** (`DB_LIVE_TEST=1` + `EMBEDDING_LIVE_TEST=1`) con la tarea
  `:backend:evaluateRetrieval` **fuera** de `build`/`check`; **no** se persiste el
  histórico ni se añade migración; la evaluación **no** cambia la recuperación.
- `AGENTS.md`: not needed — no cambia el flujo ni el camino de arranque.
- **ADR `docs/adr/0013-evaluacion-recuperacion-golden-set.md`** (recomendado):
  decisión durable «evaluación de recuperación con golden set versionado en
  resources, métricas puras (precision@k/recall@k/MRR) y CLI one-shot opt-in; sin
  cambiar la recuperación ni persistir el histórico». El planner **no** lo crea;
  lo escribe el implementador/orquestador y lo inscribe en `docs/adr/README.md`.
- `.agents/skills/rag-datapublico/SKILL.md`: update — §7 «Estado actual del
  producto (FT00018)» (golden set, métricas, comando de evaluación).
- `docs/desarrollo-local.md` (producto): update — comandos opt-in de la
  evaluación.
- `feature_list.json`/`PROGRESS.md`: los cierra el orquestador.

## Implementation Plan

1. Crear `RetrievalMetrics` (puro) y `RetrievalMetricsTest`.
2. Crear los DTOs/modelo/loader del golden set (`RetrievalGoldenSet`) y
   `RetrievalGoldenSetTest` (recurso real + fail-fast); autorizar el dataset
   `rag/eval/golden-set.json`.
3. Crear `RetrievalEvaluator` (`Retriever`) y `RetrievalEvaluatorTest`.
4. Crear `RetrievalEvaluationLog` y la CLI `RetrievalEvaluationMain`; registrar la
   tarea `evaluateRetrieval` en `backend/build.gradle.kts`.
5. Añadir `RetrievalEvaluationLiveTest` (`DB_LIVE_TEST=1` +
   `EMBEDDING_LIVE_TEST=1`).
6. Ejecutar el gate sin red ni BD y la evaluación real opt-in; actualizar
   `ARCHITECTURE.md`, `CONSTRAINTS.md`, ADR 0013 + índice, skill RAG y
   `docs/desarrollo-local.md`. `PROGRESS.md`/`feature_list.json` los cierra el
   orquestador.

## Implementation Tasks

- [ ] `RetrievalMetrics`: `FragmentRef` + `precisionAtK`/`recallAtK`/
      `reciprocalRank` (puros, con casos límite documentados).
- [ ] `RetrievalGoldenSet`: DTOs `@Serializable` (`@SerialName` en cada
      propiedad) + modelo interno + loader con fail-fast.
- [ ] `golden-set.json`: corpus modesto con encabezados `Artículo N` y consultas
      con `filter`/`relevant` (refs válidos).
- [ ] `RetrievalEvaluator`: `Retriever` + `evaluate(dataset, k)` con medias.
- [ ] `RetrievalEvaluationLog`: eventos `retrieval.evaluation.*` y campos puros.
- [ ] `RetrievalEvaluationMain`: CLI que indexa el corpus, evalúa y registra.
- [ ] Tarea Gradle `:backend:evaluateRetrieval` (fuera de `build`/`check`).
- [ ] `RetrievalMetricsTest`, `RetrievalGoldenSetTest`, `RetrievalEvaluatorTest`
      (gate, sin red/BD/modelo).
- [ ] `RetrievalEvaluationLiveTest` (`DB_LIVE_TEST=1` + `EMBEDDING_LIVE_TEST=1`).
- [ ] Docs durables: ARCHITECTURE, CONSTRAINTS, ADR 0013 + índice, skill RAG,
      `docs/desarrollo-local.md`.

## Verification Plan

Desde la raíz del producto (`..`, JDK 21 vía JBR/`JAVA_HOME`):

- **Gate sin red ni BD (obligatorio)**: `./gradlew :backend:test --rerun-tasks` →
  BUILD SUCCESSFUL con `RetrievalMetricsTest`, `RetrievalGoldenSetTest` y
  `RetrievalEvaluatorTest` en verde (0 fallos) y el resto de `:backend` intacto.
  `./gradlew build --no-daemon -PskipClient` (incluye `:backend:detekt` y
  `:cpdCheck`), `./gradlew test`, `./gradlew detekt` y
  `env -u JAVA_HOME .harness/init.sh` → exit 0.
- **Offline confirmado**: los tests del gate **no** abren conexión ni cargan el
  modelo; el test live se **omite** sin `DB_LIVE_TEST`/`EMBEDDING_LIVE_TEST`.
- **Escenario 6 (opt-in, fuera del gate y de la CI)**:
  ```sh
  backend/tools/download-embedding-model.sh
  cp .env.example .env && docker compose up -d
  ./gradlew :backend:flywayMigrate
  DB_LIVE_TEST=1 EMBEDDING_LIVE_TEST=1 ./gradlew :backend:evaluateRetrieval
  DB_LIVE_TEST=1 EMBEDDING_LIVE_TEST=1 ./gradlew :backend:test --tests '*RetrievalEvaluationLiveTest'
  ```
  Esperado: el corpus se indexa con el modelo E5 real, cada consulta se recupera
  con `HybridSearch`, y se registra `event=retrieval.evaluation.completed` con
  `precision`/`recall`/`mrr` y un resumen por consulta; el test live afirma un
  **umbral conservador documentado** (p. ej. `recall@k >= 0.8`) e imprime las
  métricas reales para la evidencia.
- **E2E**: no aplica — no hay flujo de usuario ni endpoint nuevo (el repo no tiene
  comando E2E; el cliente es Compose Multiplatform). El comando de evaluación es
  la verificación observable de esta feature.
- `init.sh` (harness): **no** se modifica; la tarea `evaluateRetrieval` **no** se
  engancha a `build`/`check`.

## Evidence To Capture

- Salida de `./gradlew :backend:test` con los tests nuevos de gate (recuento, 0
  fallos) y del gate (`build -PskipClient`, `test`, `detekt`, `init.sh` exit 0).
- Salida de la evaluación real opt-in: evento JSON
  `event=retrieval.evaluation.completed` con `precision`/`recall`/`mrr` y el
  resumen por consulta; resultado del `RetrievalEvaluationLiveTest`.
- Ficheros del commit `FT00018`, PR y run de CI; entradas en `PROGRESS.md` y
  `feature_list.json` (`evidence`).

## Validator Checklist

- [ ] Alcance acotado: solo `rag/evaluation/` + `golden-set.json` + la tarea
      Gradle + `docs/desarrollo-local.md` y sus tests; **sin** tocar
      `rag/retrieval/`, `rag/indexing/`, `rag/chunking/`, `rag/embeddings/`,
      `persistence/`, `infra/`, migraciones, `Application.kt`, `ingesta/`,
      `:shared`, `:composeApp`, CI ni `init.sh`.
- [ ] Escenarios 1–6 pasan; **todo el gate corre sin red, BD ni modelo** y el live
      se omite sin sus variables.
- [ ] El golden set es versionado, válido y coherente (refs existen en el corpus);
      un dataset inválido falla con `IllegalArgumentException` sin abrir conexión.
- [ ] Las métricas son puras y correctas en los casos límite; el evaluador agrega
      medias sin `NaN` y pasa `query`/`filter`/`k` al recuperador.
- [ ] La CLI registra `event=retrieval.evaluation.completed` con las métricas y
      cierra pool y modelo; la tarea **no** está enganchada a `build`/`check`.
- [ ] `return` único, sin `else if`, funciones ≤40 líneas, KDoc en castellano con
      identificadores en inglés; `@SerialName` explícito en todo `@Serializable`.
- [ ] `ARCHITECTURE.md`, `CONSTRAINTS.md`, ADR 0013 + índice, skill RAG,
      `docs/desarrollo-local.md`, `PROGRESS.md` y `feature_list.json` actualizados.
- [ ] No unrelated product behavior or extra feature work was added.

## Risks / Open Questions

- **Calidad y robustez del golden set.** Las expectativas se escriben contra el
  chunker determinista (encabezados `Artículo N` explícitos) y el modelo E5 int8;
  el `order` debe ser estable. Mitigación: el loader valida que cada `FragmentRef`
  existe en el corpus y la prueba live registra las métricas reales; si una
  consulta resulta ambigua, se ajusta el corpus/consulta (es un dataset, no
  código).
- **Umbral del test live.** El modelo int8 y el corpus pequeño pueden dar
  `recall@k < 1.0`; el umbral debe ser **conservador y documentado** (no
  perfección) para no producir falsos negativos entre máquinas. Las cifras reales
  quedan como evidencia, no como aserción ajustada.
- **Dataset en `src/main/resources`.** Al ser usado por una CLI de `main`, el
  dataset vive en recursos de producción (se empaqueta en el jar); es pequeño y
  versionado. Alternativa considerada: `src/test/resources` (descartada porque la
  CLI es de `main`, como `BackfillMain`).
- **Convención `Dto` en un artefacto interno.** Los tipos `@Serializable` del
  golden set llevan sufijo `Dto` por la norma MUST, aunque el dataset sea de
  desarrollo; el modelo interno (`RetrievalGoldenSet`, `RetrievalQuery`,
  `FragmentRef`) va sin sufijo.
- **Duplicación (CPD).** Los dobles de test del evaluador pueden parecerse a
  `RecordingFragmentRepository`; mantenerlos **mínimos y locales** al paquete de
  evaluación para no disparar `:cpdCheck` (umbral 100 tokens).
- **Acoplamiento a la firma de `HybridSearch`.** `Retriever` es un `fun interface`
  que `HybridSearch::search` satisface; si su firma cambia, el adaptador de la CLI
  se ajusta sin tocar las métricas (que no conocen la recuperación).
- **Sin persistencia del histórico.** «Registrar el resultado» se interpreta como
  log JSON + stdout; persistir evaluaciones en una tabla exigiría migración y es
  un Non-Goal explícito.
- **Índice HNSW con corpus pequeño.** Con pocas filas PostgreSQL puede usar *seq
  scan*; la evaluación mide **calidad**, no el plan de ejecución (el `EXPLAIN` con
  volumen real queda para operación). No se ajusta `ef_search` aquí.
