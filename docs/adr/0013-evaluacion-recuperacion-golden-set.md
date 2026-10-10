# ADR 0013: Evaluación de la recuperación con golden set versionado, métricas puras y CLI one-shot opt-in

## Estado

Aceptado (2026-10-10). Decisión del dueño del proyecto. No supersede ningún ADR.

## Contexto

El pipeline RAG ya tiene el chunking (`ArticleChunker`, FT00014), los embeddings
(`EmbeddingProvider`/`E5EmbeddingProvider`, FT00015), el almacenamiento vectorial
(`fragmento.embedding vector(384)` + HNSW, FT00016), la recuperación híbrida
(`SearchFilter`/`SearchFilterSql`/`HybridSearch`, FT00017) y el indexado mínimo
(`FragmentIndexer`, FT00017). Falta la tarea `0.3-T05`: **medir** la calidad de la
recuperación con un conjunto de prueba versionado para detectar regresiones y
decidir con datos antes de construir resúmenes y chat encima.

Restricciones: el gate y la CI corren **sin red, sin base de datos y sin el
modelo**; PostgreSQL + pgvector con **JDBC + HikariCP sin ORM** (ADR 0003);
migraciones Flyway versionadas que **nunca** se editan una vez aplicadas; `:backend`
es una **librería sin wiring** hasta que la API (FT00026+) y la operación la
consuman; todo el código en inglés con KDoc en castellano, un solo `return`, sin
`else if` y funciones ≤40 líneas.

## Decisión

- **Golden set versionado en recursos de `main`.** El dataset vive en
  `backend/src/main/resources/rag/eval/golden-set.json` (corpus modesto con
  encabezados `Artículo N` explícitos para que el `order` del chunker sea
  determinista; ids con prefijo `EVAL-` para no colisionar con datos reales;
  consultas con `filter` y `relevant`). Vive en recursos de `main` porque lo
  consume una CLI de `main` (como `BackfillMain`), no un test.
- **DTOs `@Serializable` con sufijo `Dto` y `@SerialName` explícito en cada
  propiedad** (`RetrievalGoldenSetDto`, `RetrievalCorpusItemDto`,
  `RetrievalQueryDto`, `RetrievalFilterDto`, `RetrievalRelevantDto`);
  `section`/`category` reutilizan los enums de wire `SeccionBoeDto`/`CategoriaDto`.
  **Modelo interno sin sufijo**: `RetrievalGoldenSet`, `RetrievalQuery` y
  `FragmentRef` (valor interno, no serializable).
- **Loader puro con fail-fast.** `RetrievalGoldenSetLoader.parse(json)` y
  `load(path = null)` (recurso de classpath por defecto, o fichero) validan
  `k >= 1`, corpus y consultas no vacíos, ids únicos y **cada `FragmentRef`
  relevante existente en el corpus** (`publicationId` presente y `order >= 0`).
  Un dataset inválido falla con `IllegalArgumentException` **sin** abrir conexión.
- **Métricas puras.** `RetrievalMetrics` (sin estado ni dependencias) define
  `precisionAtK = aciertos(top-k) / min(k, recuperados)` (0 si no hay recuperados),
  `recallAtK = aciertos(top-k) / |relevantes|` (0 si no hay relevantes) y
  `reciprocalRank = 1 / posición del primer acierto` (0 si no hay).
- **Evaluador con recuperador inyectable.** `RetrievalEvaluator` compone un
  `fun interface Retriever` (cuya firma satisface `HybridSearch::search`) y
  `evaluate(dataset, k)` recupera **una vez por consulta**, mapea cada
  `FragmentMatch` a `FragmentRef` (extensión pura `toRef()`) y agrega las medias
  con un helper `mean()` que devuelve `0.0` para una lista vacía (sin `NaN`).
- **CLI one-shot sin wiring.** `RetrievalEvaluationMain` (`:backend:evaluateRetrieval`,
  `JavaExec`, grupo `application`, **fuera** de `build`/`check`) resuelve la
  conexión de `POSTGRES_*` y las rutas del modelo (`EMBEDDING_MODEL_PATH`/
  `EMBEDDING_TOKENIZER_PATH` o `backend/models/multilingual-e5-small/`), indexa el
  corpus del dataset (`FragmentIndexer`, idempotente), evalúa con `HybridSearch` y
  registra `event=retrieval.evaluation.started`/`completed` (log JSON con campos
  puros + `StructuredArguments`) y un resumen legible en stdout. Un fallo sale con
  código ≠ 0 y mensaje claro; cierra modelo y pool en `finally`. **No** se cablea
  en `Application.kt`/job/backfill.
- **Sin persistencia del histórico.** «Registrar el resultado» es log JSON +
  stdout; **no** hay tabla ni migración nueva.
- **Verificación *offline* + opt-in.** El gate cubre `RetrievalMetricsTest`,
  `RetrievalGoldenSetTest` y `RetrievalEvaluatorTest` con dobles deterministas,
  **sin red, BD ni modelo**. La ejecución real es **opt-in**
  (`DB_LIVE_TEST=1` + `EMBEDDING_LIVE_TEST=1`), con un umbral **conservador y
  documentado** (`recall@k >= 0.6`, `MRR >= 0.5`).

## Alternativas consideradas

- **Dataset en `src/test/resources`.** Descartado: la CLI es de `main` y necesita
  el recurso en su classpath (mismo patrón que `BackfillMain`).
- **Persistir las evaluaciones en una tabla.** Descartado: exigiría migración y es
  un Non-Goal explícito; el histórico por log JSON es suficiente para detectar
  regresiones.
- **Endpoints/UI de evaluación.** Descartado: la evaluación es una herramienta
  interna; los endpoints/UI de búsqueda llegan con FT00026+.
- **Métricas de sistema (latencia, memoria, coste).** Descartado: fuera de alcance;
  aquí se mide **calidad** (precision/recall/MRR).
- **Acoplar el evaluador a `HybridSearch` directamente.** Descartado: el
  `fun interface Retriever` mantiene las métricas ajenas a la recuperación y
  permite dobles deterministas en el gate.
- **Añadir reranking/fusión léxica o ajustar `ef_search`.** Descartado: se decide
  con los datos de esta evaluación, no antes.

## Consecuencias

- **Habilita** detectar regresiones de recuperación con un comando reproducible
  antes de construir resúmenes/chat (FT00019+); la evaluación es el primer
  consumidor de producto de `HybridSearch`/`FragmentIndexer`.
- **Cuesta** un paso opt-in (PostgreSQL migrado + modelo E5) para la verificación
  real; el gate no lo cubre (limitación aceptada). El corpus del golden set es
  pequeño y las cifras reales son evidencia, no una aserción ajustada.
- **Riesgo abierto**: la calidad del golden set depende del chunker determinista y
  del modelo int8; si una consulta resulta ambigua se ajusta el **dataset** (no el
  código). Un `k` bajo puede no cubrir todos los relevantes de una consulta.
- **Documentación/código**: `ARCHITECTURE.md` (`rag/evaluation/`), regla MUST en
  `CONSTRAINTS.md` §«Evaluación de recuperación», estado actual en la skill
  `rag-datapublico` §7, sección en `docs/desarrollo-local.md` y este ADR.
- **Verificación**: `RetrievalMetricsTest`/`RetrievalGoldenSetTest`/
  `RetrievalEvaluatorTest` (gate) y `RetrievalEvaluationLiveTest` (opt-in).
