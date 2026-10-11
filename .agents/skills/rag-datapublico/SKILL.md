---
name: rag-datapublico
description: Guía del pipeline RAG de DatoPublico sobre el BOE (todo el sumario: Secciones I, II.A, II.B, III, IV, V.A, V.B y V.C). Úsala al ingerir o fragmentar publicaciones, generar o almacenar embeddings, indexar en pgvector, montar recuperación híbrida, generar resúmenes o respuestas de chat con citas, aplicar guardrails o evaluar calidad (golden set, precision/recall). Fija las convenciones del proyecto (chunking, multilingual-e5-small int8, protección anti-alucinación, trazabilidad a la fuente) y describe el patrón objetivo y sus riesgos conocidos.
---

# RAG de DatoPublico (BOE)

El valor del producto está en recuperar bien y **no inventar**. Toda afirmación
mostrada al usuario debe apoyarse en fragmentos del BOE y llevar **enlace a la
fuente oficial**. Lee también `docs/domain-model.md`,
`docs/technical-discovery.md` y `CONTEXT.md`.

> Antecedente: una PoC temporal (`poc/boe-rag`) validó el pipeline de punta a
> punta (ingesta → chunking → embeddings ONNX → pgvector → recuperación →
> generación con cita; recall/MRR 1.0 sobre un set mínimo). Se **eliminó** a
> propósito: era una prueba temporal. Sus lecciones están destiladas en esta
> skill; no la busques en el repo.

## Pipeline

```
ingesta BOE → chunking → embeddings (ONNX) → pgvector → recuperación híbrida
   → generación (OpenCode) → guardrails → publicación | cola_revision
```

## 1. Ingesta y chunking

- Corpus: **todo el sumario del BOE** — **I** (disposiciones generales), **II.A**
  (nombramientos), **II.B** (empleo), **III** (otras disposiciones), **IV**
  (Administración de Justicia), **V.A** (contratación pública), **V.B** (otros
  anuncios) y **V.C** (anuncios particulares). Cada sección tiene estructura y
  vocabulario distintos: el chunking necesita **variantes por sección**, no una
  regla única.
- Fragmenta por **artículo/disposición** conservando su referencia. No generes
  solapamientos inválidos; los fragmentos deben cubrir el texto.
- Normaliza: el BOE usa **espacio duro (`\u00a0`)** tras etiquetas como
  «Artículo»; inserta saltos por párrafo y ancla los encabezados a **inicio de
  línea**. Omitir esto produce referencias erróneas.
- Cada fragmento guarda metadatos de metadatos de filtrado: publicación,
  categoría, fecha, organismo y referencia de artículo/sección.

### Estado actual del producto (FT00014)

- La fragmentación **ya está implementada** en `:backend`:
  `es.aviferdev.datopublico.backend.rag.chunking.ArticleChunker`
  (`chunk(Publicacion): List<Fragment>`) y el modelo de dominio
  `rag.Fragment` (`publicationId`, `order`, `reference`, `content`, sin sufijo).
  Es **pura, determinista y sin red/BD**, con variante por sección y cobertura sin
  solapamiento; el mapeo a persistencia es la extensión pura `Fragment.toEntity()`
  en `persistence/FragmentRepository.kt`. Decisión durable en
  `docs/adr/0009`.
- **Estimación de tokens provisional**: `ArticleChunker` usa
  `ceil(length / charsPerToken)` con `charsPerToken = 3` y `maxTokens = 512`
  (ambos inyectables por constructor) porque el tokenizador real E5 llega con
  **FT00015**. Es conservadora; FT00015 deberá recalibrarla o inyectar el
  contador real sin cambiar la firma.
- La detección de encabezados es **heurística por texto** (la `Publicacion` no
  conserva el `class="articulo"`): una línea que empiece por «Artículo»/
  «Disposición» se trata como encabezado. Validado con los fixtures reales de las
  ocho secciones.

## 2. Embeddings (locales)

- Modelo por defecto: **`intfloat/multilingual-e5-small` cuantizado int8** vía
  **ONNX Runtime en CPU**; **384 dimensiones**, contexto **512 tokens**.
- Prefijos obligatorios: `query: ` para la consulta y `passage: ` para los
  fragmentos. Sin prefijo la calidad cae.
- Normaliza los vectores. No superes 512 tokens por fragmento.
- El modelo vive tras una **interfaz de proveedor** para poder cambiar a `-base`
  (768 dims) sin tocar el resto del código. Cambiar de modelo implica **rediseñar
  la columna y reindexar**.
- Herramienta configurable por entorno; clave de OpenCode solo en el servidor.

### Estado actual del producto (FT00015)

- El proveedor de embeddings **ya está implementado** en `:backend`, paquete
  `es.aviferdev.datopublico.backend.rag.embeddings`: interfaz pública
  `EmbeddingProvider` (`dimensions`, `embedQuery`, `embedPassage`, `embedPassages`,
  `AutoCloseable`) + implementación `E5EmbeddingProvider`
  (`intfloat/multilingual-e5-small` int8 vía **ONNX Runtime en CPU**, tokenizador
  XLM-R de DJL). Aplica los **prefijos obligatorios** `query: `/`passage: `,
  *mean pooling* con máscara, **normaliza** (L2) y devuelve **384 dims**;
  `VectorMath` (`meanPool`/`l2Normalize`/`cosineSimilarity`) es puro y lo
  reutilizará la recuperación. Decisión durable en `docs/adr/0010`.
- **Tokenizador real**: `E5Tokenizer.countTokens` cierra el **contador provisional**
  de FT00014 (`ArticleChunker` se mantiene **puro**, sin dependencia nativa; la
  inyección/calibración del contador real en el chunker queda **diferida**, no
  forma parte de FT00016, que solo almacena vectores).
- **Aprovisionamiento**: el modelo (~118 MB) y el `tokenizer.json` **no** se
  versionan; se descargan con `backend/tools/download-embedding-model.sh` a
  `backend/models/` (gitignored) y se referencian por **ruta absoluta**
  (`EMBEDDING_MODEL_PATH`/`EMBEDDING_TOKENIZER_PATH`) con fail-fast. El gate no
  descarga nada; el modelo real se prueba **opt-in**
  (`EMBEDDING_LIVE_TEST=1`). No está cableado y **no** anticipa pgvector/HNSW
  (FT00016) ni la recuperación (FT00017).

## 3. Almacenamiento vectorial

- PostgreSQL + **pgvector**; columna de dimensión **384**; índice **HNSW**.
- Filtros SQL por metadatos (fecha, categoría, organismo) combinados con la
  similitud. Verifica que el índice **se usa** en la consulta.

### Estado actual del producto (FT00016)

- El **almacenamiento vectorial** ya está implementado en `:backend`:
  `persistence/PgVector` (puro: `DIMENSIONS = 384`, `toLiteral`/`parse`, fail-fast
  de dimensión, formato independiente del *locale*) y `FragmentRepository`
  ampliado con `saveEmbedding` y `findNearest` (`FragmentMatch` = fragmento +
  distancia coseno). Migración `V3__fragmento_embedding.sql`: columna
  **`embedding vector(384)` nullable** + índice **HNSW** `vector_cosine_ops`
  (`m = 16`, `ef_construction = 64`). El vector se guarda como **literal textual
  con *cast* `?::vector`** (sin ORM ni `PGobject`); `findNearest` filtra
  `embedding IS NOT NULL` y ordena por distancia ascendente. Decisión durable en
  `docs/adr/0011`.
- FT00016 dejó **sin filtros de metadatos** y **sin wiring** (los añade FT00017,
  ver §4): `Application.kt`/job/backfill, `ArticleChunker`, `rag/embeddings/` y
  `:shared` intactos; no genera embeddings (no construye `E5EmbeddingProvider`).
- **Verificación**: el gate cubre `PgVectorTest` y
  `FragmentEmbeddingMigrationSqlTest` **sin red ni BD**; la prueba real (vecino más
  cercano, exclusión de nulos e índice HNSW usado con `SET enable_seqscan = off`)
  es **opt-in** `DB_LIVE_TEST=1` contra el PostgreSQL de `docker-compose`.

## 4. Recuperación híbrida

- Combina filtros SQL con similitud vectorial; devuelve top-k fragmentos con su
  referencia y score.
- Ordena por relevancia; deja la puerta a un **reranking** si la calidad lo pide.

### Estado actual del producto (FT00017)

- La **recuperación híbrida** ya está implementada en `:backend`, paquete
  `es.aviferdev.datopublico.backend.rag.retrieval`: `SearchFilter` (valor interno
  sin sufijo: fechas ISO-8601, `CategoriaDto`, `SeccionBoeDto`, organismo),
  `SearchFilterSql` (puro: `whereClause` + `parameters` en orden documentado,
  parametrizado con `?`, fechas con *cast* `?::date` y fail-fast de fecha no ISO) y
  `HybridSearch` (servicio que vectoriza la consulta con `embedQuery` y delega en
  `FragmentRepository.findNearest(vector, filter, limit)`). `FragmentRepository`
  gana `findNearest` filtrado (con `JOIN publicacion`) y `findEmbedding`; el
  `findNearest` de 2 argumentos de FT00016 delega con `SearchFilter()`. Decisión
  durable en `docs/adr/0012`.
- **Indexado mínimo** en `rag/indexing/FragmentIndexer` (cierra el aplazamiento de
  FT00016): fragmenta (`ArticleChunker`), persiste cada fragmento (`save`) y guarda
  su embedding de *pasaje* (`embedPassage` + `saveEmbedding`); **idempotente** por
  el *upsert* de `(publicacion_id, orden)`. **Sin** *batching*, sin transacción
  multi-repositorio y **sin** indexar el corpus completo (operación posterior).
- **Sin wiring**: `Application.kt`/job/backfill, `ArticleChunker`,
  `rag/embeddings/`, `infra/` y `:shared` intactos; sin migración nueva. La
  recuperación la consumirán la evaluación (FT00018) y el chat (FT00019+); el
  reranking y la fusión léxica quedan abiertos.
- **Verificación**: el gate cubre `SearchFilterSqlTest`, `HybridSearchTest` y
  `FragmentIndexerTest` **sin red ni BD**; las pruebas reales son **opt-in** —
  `HybridSearchLiveTest` (`DB_LIVE_TEST=1`, vectores sintéticos) y
  `FragmentIndexerLiveTest` (`DB_LIVE_TEST=1` + `EMBEDDING_LIVE_TEST=1`, modelo E5
  real) contra el PostgreSQL de `docker-compose`.

## 5. Generación (resumen y chat)

- Proveedor: **OpenCode** (OpenAI-compatible, candidato `deepseek-v4.1-flash`)
  tras una interfaz intercambiable.
- **Resumen ciudadano:** salida estructurada "¿Qué cambia?", "¿A quién afecta?",
  "Cifras clave", con **cita obligatoria** a la fuente. Variante para empleo/beca
  (incluye **plazo**).
- **Chat/consulta:** acepta una pregunta o una **afirmación a verificar**;
  responde con las citas y distingue **respondida**, **refutada** y
  **sin_fundamento**.
- El prompt trabaja **solo** con el contexto recuperado; prohibido el
  conocimiento libre del modelo.

### Estado actual del producto (FT00019)

- El **contrato** del resumen ciudadano ya está fijado y **validado** en
  `:shared`, paquete `es.aviferdev.datopublico.validation`:
  `CitizenSummaryValidator.validate(summary, category)` es un validador **puro**
  (sin red/BD/reloj/estado) que **acumula violaciones y no lanza**
  (`CitizenSummaryValidation.isValid` derivado). Comprueba **fuente oficial
  obligatoria** (`http(s)://`), «¿Qué cambia?»/«¿A quién afecta?» no vacíos,
  cifras clave sin entradas en blanco y, en la variante
  `EMPLOYMENT_OR_SCHOLARSHIP` (`OPOSICIONES_Y_EMPLEO_PUBLICO`,
  `BECAS_SUBVENCIONES_Y_AYUDAS`), plazo con `fechaLimite` no vacía. Decisión
  durable en `docs/adr/0014`.
- Reutiliza `ResumenDto`/`CategoriaDto`/`PlazoDto` **sin** cambiar el contrato de
  wire (congelado). Es **contrato**, no veracidad: la alcanzabilidad del enlace y
  las afirmaciones fuera del contexto recuperado son **guardrails** de FT00022, y
  el **aviso de IA** se exige en FT00023. La **generación** (prompts, OpenCode) es
  FT00020.

### Estado actual del producto (FT00020)

- La **generación del resumen ciudadano** ya está implementada en `:backend` como
  **librería sin wiring**, en dos paquetes: `rag/generation/` (interfaz
  `TextGenerationProvider` `suspend` + `GenerationRequest`/`GenerationResponse` +
  `TextGenerationException`; config `OpenCodeConfig` con **fail-fast** de
  `OPENCODE_API_KEY`, base URL `https://opencode.ai/zen/go/v1`, modelo
  `deepseek-v4.1-flash` y temperatura `0.0`; impl `OpenCodeTextGenerationProvider`
  con DTOs de wire sufijo `Dto`, `Bearer`, `POST {baseUrl}/chat/completions` y
  factory `openCodeHttpClient`) y `rag/summary/` (`CitizenSummaryPromptBuilder`
  puro que delimita el contexto como **datos, no instrucciones** y pide plazo en
  empleo/beca; `SummaryOutputParser` puro que quita *fences* y falla con
  `SummaryGenerationException`; `SummaryGenerationDto.toResumenDto` que **inyecta**
  `fuenteOficial` desde `Publicacion.urlOficial` y `avisoIA = true`;
  `CitizenSummaryResult.Valid`/`Invalid` y `CitizenSummaryGenerator`, que compone
  `HybridSearch` → prompt → proveedor → parser → `CitizenSummaryValidator`).
  Decisión durable en `docs/adr/0015`.
- **La fuente oficial no la produce el modelo**: se inyecta de forma determinista;
  un resumen que no cumple el contrato **no se publica** (`Invalid` con las
  violaciones, no una excepción). `publication.categoria` nula es fail-fast.
- **Sin wiring** (`Application.kt`/job/backfill, migraciones, `:shared` y
  `:composeApp` intactos) y **sin** cacheo (FT00021), guardrails (FT00022) ni chat
  (FT00025). **Verificación**: el gate cubre config, proveedor (`MockEngine`),
  parser, prompt y generador con **dobles deterministas**, sin red ni BD; la prueba
  real es **opt-in** (`OPENCODE_LIVE_TEST=1`, sin PostgreSQL ni ONNX; fail-fast sin
  clave).

### Estado actual del producto (FT00021)

- El **cacheo del resumen ciudadano** y el **control de coste** ya están
  implementados en `:backend` como **librería sin wiring**: `rag/summary/`
  (`SummaryCacheKey` puro = **publicación + modelo + versión de prompt**, fail-fast;
  `CachedCitizenSummaryGenerator` + `CachedSummaryResult` que **envuelven** a
  `CitizenSummaryGenerator` — consulta la caché **antes** del proveedor, en acierto
  devuelve lo cacheado **sin llamar** a OpenCode y registra uso con
  `cache_hit = true` y 0 tokens; en fallo genera, registra el uso real y **cachea
  solo si es `Valid`**; `CitizenSummaryPromptBuilder.PROMPT_VERSION = "v1"`
  **pública** y manual). `GenerationResponse` gana `usage: TokenUsage?` (opcional) y
  el proveedor OpenCode parsea el bloque `usage`; `CitizenSummaryResult` propaga el
  uso de forma **compatible**. Persistencia en `persistence/`
  (`SummaryCacheRepository` con codec JSON puro del `ResumenDto` y
  `GenerationUsageRepository` con `totalTokens()`) + migración `V4`
  (`resumen_cache` — tabla **propia y separada** de `resumen` — y `generacion_uso`,
  **sin** FK). Decisión durable en `docs/adr/0016`.
- **Reglas**: solo se cachean resúmenes `Valid`; cada generación (acierto o fallo)
  registra tokens y `cache_hit`; cambiar el **modelo** o la **versión del prompt**
  invalida la caché; el **modelo** se **inyecta** por constructor (en producción, de
  `OpenCodeConfig`). **Sin wiring** (`Application.kt`/job/backfill, endpoints/UI,
  `:shared` y `:composeApp` intactos) y **sin** anticipar guardrails (FT00022), cola
  de revisión (FT00023) ni chat (FT00025). **Verificación**: el gate cubre clave,
  servicio con caché, uso del proveedor y contrato SQL de `V4` con **dobles
  deterministas**, sin red ni BD; la prueba real es **opt-in** (`DB_LIVE_TEST=1`,
  solo PostgreSQL).

### Estado actual del producto (FT00025)

- La **generación del chat RAG** ya está implementada en `:backend` como **librería
  sin wiring**, paquete nuevo `es.aviferdev.datopublico.backend.rag.chat`:
  `RagChatService.answer(query, filter, limit)` compone `HybridSearch` (FT00017) →
  `ChatPromptBuilder` (puro: consulta + contexto **numerado** `[0]`, `[1]`…
  delimitado como **datos, no instrucciones**) → `TextGenerationProvider`
  (FT00020) → `ChatOutputParser` (puro: *fences* + JSON + token de estado con
  fail-fast) → `ChatGroundingChecker` → `CitationResolver` y devuelve un resultado
  tipado con los tres estados del dominio: `ChatResult.Answered`/`Refuted`/
  `Unfounded` (`ChatStatus.ANSWERED`/`REFUTED`/`UNFOUNDED`). Decisión durable en
  `docs/adr/0020`.
- **La fuente oficial se inyecta, no la produce el modelo**: el modelo solo aporta
  **índices** de fragmento (`citas`) y el `CitationResolver` (`fun interface`)
  resuelve la publicación a `ChatCitation(publicationId, title, officialUrl)` (en
  producción, `PublicationRepository.findById`). Una respuesta
  `respondida`/`refutada` **exige** ≥1 cita resoluble; sin ninguna, o si el
  grounding la considera no sustentada, **degrada a `sin_fundamento`** con el
  mensaje de dominio `UNFOUNDED_MESSAGE`. El **contexto vacío** declara
  `sin_fundamento` **sin invocar** al proveedor; una salida no parseable, un estado
  desconocido o un índice fuera de rango ⇒ `ChatGenerationException` tipada.
- **Grounding léxico reutilizado**: `ChatGroundingChecker` usa
  `SummaryTextNormalizer` y `SummaryGroundingChecker.MIN_CLAIM_SUPPORT` (= 0.6) de
  FT00022; es **conservador** (un falso negativo degrada, nunca publica una posible
  alucinación). **Sin wiring** (`Application.kt`/job/backfill, endpoints/UI,
  `:shared`/`:composeApp`, migraciones intactos) y **sin** rate limiting/cuota
  (FT00030/FT00031) ni persistencia de historial. **Verificación**: el gate cubre
  prompt, parser, grounding y servicio con **dobles deterministas**, sin red ni BD;
  la prueba real es **opt-in** (`OPENCODE_LIVE_TEST=1`, sin PostgreSQL ni ONNX;
  fail-fast sin clave).

## 6. Guardrails (anti-alucinación y trazabilidad)

- Ningún resumen se publica sin **enlace válido** a la fuente oficial.
- Ninguna afirmación fuera del contexto recuperado. Si el corpus no sustenta la
  respuesta, se declara **sin_fundamento** (no se inventa).
- Resúmenes de **baja confianza** van a `cola_revision`, sin bloquear el feed.
- Cachea resúmenes por publicación para no regenerar ni gastar tokens de más.

### Estado actual del producto (FT00022)

- La **capa de guardrails anti-alucinación y trazabilidad** ya está implementada en
  `:backend` como **librería sin wiring**, paquete nuevo
  `es.aviferdev.datopublico.backend.rag.guardrails`: `SummaryGuardrail.evaluate(publication,
  summary, context)` se ejecuta **después** de generar (FT00020) y **antes** de
  publicar, y compone la validación de **contrato** (`CitizenSummaryValidator`,
  FT00019), la de **fuente** (`OfficialSourceValidator` + el puerto opcional
  `SourceReachability`) y el **grounding** léxico (`SummaryGroundingChecker`). Devuelve
  un `SummaryGuardrailResult` con `GuardrailDecision` (`PUBLISHABLE`/`NEEDS_REVIEW`/
  `DISCARDED`), `isPublishable`, las violaciones de contrato y de contenido y una
  **puntuación de grounding** `[0,1]`. Decisión durable en `docs/adr/0017`.
- **Fuente oficial**: `OfficialSourceValidator.isOfficial` exige `https://`, host del
  BOE (`www.boe.es`/`boe.es`) e **igualdad** con `Publicacion.urlOficial` (trazabilidad;
  en FT00020 la fuente se inyecta desde la publicación). La **alcanzabilidad** real es
  un puerto `suspend` (`HttpSourceReachability`, `HttpClient` inyectado, 2xx/3xx ⇒
  `true`; fallo de red ⇒ `false`) que el guardrail recibe **opcional**: sin puerto solo
  se valida la estructura.
- **Grounding léxico**: `SummaryTextNormalizer` (tokens sin acentos/palabras vacías,
  cifras, oraciones) y `SummaryGroundingChecker` (una afirmación está sustentada si
  **todas** sus cifras están en el contexto y ≥`MIN_CLAIM_SUPPORT` = 0.6 de sus
  términos de contenido; `score` = sustentadas/total). Umbrales `DISCARD_THRESHOLD` =
  0.5 y `REVIEW_THRESHOLD` = 0.8. Es **conservador** (falso negativo ⇒ revisión o
  descarte, nunca publicar).
- **Sin wiring y sin persistir**: `Application.kt`/job/backfill, migraciones, `:shared`
  y `:composeApp` intactos; **no** escribe en `resumen` ni en `cola_revision` (FT00023/
  FT00026). **Verificación**: el gate cubre normalizador, validador de fuente, grounding,
  evaluador con dobles y `HttpSourceReachability` con `MockEngine`, **sin red ni BD**; la
  alcanzabilidad real es **opt-in** (`BOE_LIVE_TEST=1`).

### Estado actual del producto (FT00023)

- La **disposición del resumen tras los guardrails** ya está implementada en
  `:backend` como **librería sin wiring**, paquete nuevo
  `es.aviferdev.datopublico.backend.rag.review`: `SummaryDispositionService.dispose(publication,
  summary, guardrail)` **consume** la `GuardrailDecision` de FT00022 (sin umbral
  nuevo), persiste el **estado** y la **confianza** (`groundingScore`) en `resumen` y
  **encola** los `NEEDS_REVIEW` en `cola_revision` **sin publicarlos** (el publicado
  lleva `aviso_ia = true`; el aviso **visible** es FT00033). Decisión durable en
  `docs/adr/0018`.
- **Estados y resultado**: `SummaryState` (los siete tokens de `docs/domain-model.md`;
  `PUBLISHED` = `publicado`, `IN_REVIEW` = `en_cola_revision`, `DISCARDED` =
  `descartado`) y `SummaryReviewOutcome` (`Published`/`Queued`/`Discarded`).
  `ReviewReasonFormatter.of` construye el `motivo` interno de la cola.
- **Encolado idempotente**: la migración `V5` (`cola_revision_pendiente_unique`)
  crea un **índice único parcial** `ON cola_revision (resumen_id) WHERE estado =
  'pendiente'`; `ReviewQueueRepository` pasa a *upsert* (`ON CONFLICT … DO UPDATE
  SET motivo`) y gana `listPending()` (consumidor FT00026+). `SummaryRepository` y
  `SummaryGuardrail` **no** se tocan.
- **Sin wiring**: `Application.kt`/job/backfill, endpoints/UI y la revisión manual
  (`revisado → publicado|descartado`) son de FT00026+/FT00033; `:shared`/`:composeApp`
  intactos. **Verificación**: el gate cubre estados, motivo, servicio con dobles y el
  contrato SQL de `V5`, sin red ni BD; la disposición real es **opt-in**
  (`DB_LIVE_TEST=1`, solo PostgreSQL).

## 7. Evaluación

- **Recuperación:** precision/recall (y recall@k / MRR) sobre un set de prueba.
- **Resúmenes:** **golden set** de publicaciones con referencia; mide acierto en
  "¿Qué cambia?" y "¿A quién afecta?".
- **Chat:** respuestas con citas correctas, refutación de afirmaciones falsas y
  comportamiento ante preguntas sin fundamento.

### Estado actual del producto (FT00018)

- La **evaluación de la recuperación** ya está implementada en `:backend`, paquete
  `es.aviferdev.datopublico.backend.rag.evaluation`: `RetrievalMetrics` (puro:
  `precision@k`/`recall@k`/`reciprocalRank` con `FragmentRef`), el **golden set
  versionado** (`rag/eval/golden-set.json`, DTOs `@Serializable` con sufijo `Dto` y
  `RetrievalGoldenSetLoader` con fail-fast: `k >= 1`, ids únicos y cada fragmento
  relevante existente en el corpus), `RetrievalEvaluator` (`fun interface Retriever`
  + medias sin `NaN`) y la CLI one-shot `RetrievalEvaluationMain` (tarea
  `:backend:evaluateRetrieval`, **fuera** de `build`/`check`). Decisión durable en
  `docs/adr/0013`.
- **Reutiliza FT00017 sin modificarla**: indexa el corpus del propio dataset con
  `FragmentIndexer` (idempotente) y evalúa cada consulta con `HybridSearch`. **Sin
  wiring** (`Application.kt`/job/backfill intactos) y **sin** persistir el
  histórico: el resultado es log JSON (`event=retrieval.evaluation.started`/
  `completed` con `precision`/`recall`/`mrr`) + resumen en stdout; sin migración.
- **Verificación**: el gate cubre `RetrievalMetricsTest`, `RetrievalGoldenSetTest` y
  `RetrievalEvaluatorTest` **sin red, BD ni modelo**; la ejecución real es
  **opt-in** (`DB_LIVE_TEST=1` + `EMBEDDING_LIVE_TEST=1`) con umbral conservador
  (`recall@k >= 0.6`, `MRR >= 0.5`), contra el PostgreSQL de `docker-compose` y el
  modelo E5 real.

### Estado actual del producto (FT00024)

- La **evaluación de la calidad del resumen ciudadano** ya está implementada en
  `:backend`, paquete `es.aviferdev.datopublico.backend.rag.evaluation`:
  `SummaryQualityMetrics` (puro: `tokenF1` por campo con el multiconjunto de
  `contentTokens` de `SummaryTextNormalizer` y `figuresRecall` de cifras), el
  **golden set versionado** (`rag/eval/summary-golden-set.json`, ids `EVAL-S`, DTOs
  `@Serializable` con sufijo `Dto` —la referencia **reutiliza** `SummaryGenerationDto`—
  y `SummaryGoldenSetLoader` con fail-fast), `SummaryQualityEvaluator`
  (`fun interface SummaryGenerator` + medias sin `NaN`, `hitRate` e `invalidCount`;
  un `CitizenSummaryResult.Invalid` cuenta como fallo) y la CLI one-shot
  `SummaryEvaluationMain` (tarea `:backend:evaluateSummary`, **fuera** de
  `build`/`check`). Decisión durable en `docs/adr/0019`.
- **Reutiliza FT00020/FT00022 sin modificarlas**: indexa el corpus del dataset con
  `FragmentIndexer`, genera cada resumen con `CitizenSummaryGenerator` (OpenCode) y
  lo compara con su referencia. **Sin wiring** (`Application.kt`/job/backfill
  intactos) y **sin** persistir el histórico: el resultado es log JSON
  (`event=summary.evaluation.started`/`completed` con `what_changes_f1`/
  `who_is_affected_f1`/`figures_recall`/`hit_rate`/`invalid`) + resumen por entrada
  en stdout; sin migración.
- **Verificación**: el gate cubre `SummaryQualityMetricsTest`, `SummaryGoldenSetTest`
  y `SummaryQualityEvaluatorTest` **sin red, BD, modelo ni OpenCode**; la ejecución
  real es **opt-in** (`OPENCODE_LIVE_TEST=1` + `DB_LIVE_TEST=1` +
  `EMBEDDING_LIVE_TEST=1`) con umbral conservador (`meanWhatChangesF1 >= 0.3`,
  `hitRate >= 0.3`). El F1 es **léxico** (penaliza paráfrasis): el objetivo es
  detectar **regresiones**, no certificar calidad absoluta. La **generación** del
  chat ya existe (`rag/chat/`, FT00025), pero su **evaluación** (respuestas con
  citas, refutaciones y `sin_fundamento`) sigue pendiente: llegará después, con su
  propio golden set.

## Riesgos conocidos

- Chunking por expresiones regulares es **heurístico**; la vía de producto debería
  aprovechar la estructura/XML del BOE cuando sea posible.
- `int8` degrada ligeramente la calidad; **no** se ha comparado aún contra fp32 ni
  `-base` sobre corpus real.
- Corpus de prueba pequeño; validar con volúmenes reales antes de confiar en las
  métricas.
- Las Secciones II.A, II.B, III, IV, V.A, V.B y V.C son más irregulares que la I:
  parser, chunking y clasificación requieren validación con datos reales; puede
  haber duplicidad III ↔ V.B (base reguladora y extracto).
- Coste del chat por tokens: aplicar rate limiting y control de contexto.
