# Architecture — DatoPublico

> Mapa durable de módulos y fronteras. **No** es un inventario de ficheros. El
> detalle por módulo vive en las skills `ktor-backend-architecture`,
> `compose-multiplatform-architecture` y `rag-datapublico`.

## Módulos (monorepo Gradle)

- **`:shared`** — DTOs y lógica compartida con `kotlinx.serialization`.
  Namespace `es.aviferdev.datopublico`. FT00019 añade **`validation/`**: la
  validación **pura del contrato** del resumen ciudadano (`CitizenSummaryValidator`
  + `CitizenSummaryVariant`/`CitizenSummaryVariantResolver` y
  `CitizenSummaryValidation`), que **acumula violaciones y no lanza** (un resumen
  inválido es un estado esperado, no una excepción de programación) y **no cambia**
  el contrato de wire de `ResumenDto`. Es el **contrato** (estructura y presencia
  de la fuente); los **guardrails de contenido** (alcanzabilidad del enlace y
  afirmaciones fuera del contexto recuperado) son de FT00022. Ver `docs/adr/0014`.
  FT00026 añade al contrato de wire el **feed diario**: `HighlightReasonDto` (enum
  de motivos con token `snake_case`), `HighlightDto` (publicación + motivos, **sin**
  `score`) y `ResumenDiarioDto` ampliado con `destacados` y paginación
  (`aditivo con defaults`). Ver `docs/adr/0021`.
  FT00028 añade al contrato de wire la **búsqueda**: `SearchResultsDto` (`q` eco de
  la consulta + `resultados`, una lista del **mismo** `PublicacionDto` del feed,
  **sin** `total` ni paginación). Ver `docs/adr/0023`.
  FT00031 añade al contrato de wire el **chat RAG**: `ChatRequestDto` (`consulta`),
  `ChatResponseDto` (`consulta` eco, `estado`, `respuesta` y `citas`), el enum de
  wire `ChatStatusDto` (`respondida`/`refutada`/`sin_fundamento`) y
  `ChatCitationDto` (`publicacionId`/`titulo`/`urlOficial`); **sin** `usage`. Ver
  `docs/adr/0024`.
  FT00030 añade al contrato de wire el **error tipado**: `ApiErrorDto` (`codigo`,
  `mensaje`) y el enum de wire `ApiErrorCodeDto` (`solicitud_invalida`,
  `no_encontrado`, `demasiadas_peticiones`, `error_interno`,
  `servicio_no_disponible`), con `@SerialName` explícito y tokens `snake_case`. Ver
  `docs/adr/0026`.
- **`:backend`** — Ktor: ingesta del BOE, RAG, resúmenes, destacados y API.
  Namespace `es.aviferdev.datopublico.backend`. Ya existe el **esqueleto**
  (composition root `Application.kt`, `plugins/` e `infra/`, `GET /health`,
  configuración por entorno y logging JSON) y existe **`ingesta/`**:
  `ingesta/sumario/` (cliente del sumario diario del BOE + modelo interno y
  filtrado de secciones), `ingesta/publicacion/` (parser del **texto XML**
  oficial `xml.php`, cliente de texto, modelo `Publicacion` y combinador
  sumario + texto) e `ingesta/job/` (FT00009: config del horario `IngestionConfig`,
  cálculo puro del siguiente disparo `IngestionSchedule`, orquestador
  `IngestionJob`/`DailyIngestionJob` y scheduler por corrutina `IngestionScheduler`;
  FT00010 añade **observabilidad**: evento de log estructurado por ejecución
  `IngestionLog`, estado en memoria de ventanas intentadas `IngestionRunState`,
  detector puro de ventanas perdidas `MissedIngestionDetector`, sumidero de alerta
  `IngestionAlertSink`/`LoggingAlertSink` y vigilante `IngestionWatchdog`).
  FT00011 añade **`ingesta/backfill/`**: la herramienta CLI *one-shot*
  (`:backend:backfill`, `BackfillMain`) que recorre por lotes el rango histórico
  (`BackfillConfig`/`BackfillRange`) reutilizando `DailyIngestionJob` y el *upsert*,
  con **checkpoint local en fichero** (`FileBackfillCheckpointStore`) para
  reanudar y ritmo pausado (`BackfillRunner`); **no** se cablea en el arranque del
  servidor ni se engancha a `build`/`check`. Ver `docs/adr/0006`.
  FT00012 añade **`ingesta/categorizacion/`**: el clasificador curado
  determinista `PublicationClassifier` (sección + epígrafe + título → una de las
  11 `CategoriaDto`, con reglas ordenadas y categoría por defecto por sección) y
  el extractor acotado de plazos `DeadlineExtractor` (`plazo de <N> días
  [hábiles|naturales]` y fechas explícitas, con puerta de contexto), ambos
  **puros** (sin IA, red, BD ni reloj); `PublicacionParser` los recibe como
  colaboradores con default y rellena `categoria`/`plazo`, sin tocar
  `Application.kt`. Ver `docs/adr/0007`.
  FT00013 añade **`relevance/`**: el ranker puro y explicable
  `HighlightRanker` (`Highlight` + `HighlightReason`) que, dada la lista de
  publicaciones de un día (`PublicationRepository.listByDate`), marca un
  subconjunto como destacado por **señales objetivas** (sección I, rango
  normativo, categoría curada de FT00012, plazo abierto y organismo en una lista
  curada y modesta) y expone el **motivo** de cada destacado. Es **puro** (sin
  IA, red, BD, reloj ni estado), se **calcula *on-the-fly*** (sin persistencia)
  y no se cablea en el arranque: lo consumirá el feed (FT00026). Ver
  `docs/adr/0008`.
  FT00014 añade **`rag/`**: el modelo de dominio `Fragment` (sin sufijo) y el
  chunker **puro, determinista y sin red/BD** `rag/chunking/ArticleChunker`
  (`chunk(Publicacion): List<Fragment>`). Fragmenta `Publicacion.texto` por
  **artículo/disposición** conservando la **referencia**, con **variante por
  sección** para las secciones sin artículos (II.A/II.B/IV/V.A/V.B/V.C),
  cobertura **sin solapamiento** y presupuesto **≤512 tokens** (estimación
  provisional `charsPerToken = 3`, inyectable por constructor). El mapeo a
  persistencia es la extensión pura `Fragment.toEntity()` en `persistence/`;
  **no** genera embeddings (FT00015), **no** escribe en PostgreSQL ni anticipa la
  columna `embedding`/HNSW (FT00016) y **no** se cablea en el arranque. Ver
  `docs/adr/0009`.
  FT00015 añade **`rag/embeddings/`**: el proveedor de embeddings locales tras
  una **interfaz intercambiable** (`EmbeddingProvider` + `E5EmbeddingProvider`,
  `intfloat/multilingual-e5-small` int8 vía **ONNX Runtime en CPU**), con los
  **prefijos obligatorios** `query: `/`passage: `, *mean pooling* con máscara,
  vectores **normalizados** de **384 dims** y el **tokenizador XLM-R real** (DJL)
  que expone `countTokens` (cierra el contador provisional de FT00014). Es una
  **librería**: **no** se cablea en el arranque ni en el job; el modelo y el
  tokenizador **no** se versionan (se aprovisionan fuera del gate con
  `backend/tools/download-embedding-model.sh`, `backend/models/` gitignored) y su
  prueba contra el modelo real es **opt-in** (`EMBEDDING_LIVE_TEST=1`). No
  anticipa pgvector/HNSW (FT00016) ni la recuperación (FT00017) y **no** toca
  `ArticleChunker`/`persistence/`. Ver `docs/adr/0010`.
  FT00016 añade el **almacenamiento vectorial**: la migración `V3` da a `fragmento`
  la columna `embedding vector(384)` (nullable) y su **índice HNSW** coseno
  (`vector_cosine_ops`); `persistence/PgVector` convierte de forma **pura** entre
  `FloatArray` y el literal `[v1,v2,…]` (dimensión 384, fail-fast) y
  `FragmentRepository` gana `saveEmbedding` (literal con *cast* `?::vector`) y
  `findNearest` (vecinos más cercanos por distancia coseno, excluyendo los nulos).
  Es una **librería**: **no** se cablea en el arranque y **no** incluye filtros de
  metadatos (recuperación híbrida, FT00017) ni evaluación (FT00018); la prueba
  real contra PostgreSQL es **opt-in** (`DB_LIVE_TEST=1`). Ver `docs/adr/0011`.
  FT00017 añade **`rag/retrieval/`** y **`rag/indexing/`**: `SearchFilter` (valor
  interno sin sufijo: fechas ISO-8601, categoría, sección y organismo),
  `SearchFilterSql` (puro: cláusula ` AND …` parametrizada y parámetros en orden
  documentado, `?::date` y fail-fast de fecha no ISO), `HybridSearch` (servicio
  que vectoriza la consulta con `embedQuery` y llama a `findNearest` filtrado) y
  `FragmentIndexer` (indexado mínimo: fragmenta, `save` y guarda el embedding de
  *pasaje*; idempotente por *upsert*). `FragmentRepository` gana
  `findNearest(queryEmbedding, filter, limit)` (con `JOIN publicacion` y `WHERE`
  dinámico) y `findEmbedding`; el `findNearest` de 2 argumentos de FT00016 delega.
  Sigue siendo una **librería sin wiring**: **no** se construye en `Application.kt`
  ni en el job/backfill, no hay endpoints/UI ni migración nueva, y la prueba real
  es **opt-in** (`DB_LIVE_TEST=1` y, para el modelo, `EMBEDDING_LIVE_TEST=1`). Ver
  `docs/adr/0012`.
  FT00018 añade **`rag/evaluation/`**: la **evaluación de la recuperación** con un
  **golden set versionado** (recurso `rag/eval/golden-set.json`), métricas **puras**
  (`RetrievalMetrics`: `precision@k`/`recall@k`/MRR), el loader con fail-fast
  (`RetrievalGoldenSetLoader`), el evaluador con un `Retriever` inyectable
  (`RetrievalEvaluator`) y la CLI one-shot `RetrievalEvaluationMain` (tarea
  `:backend:evaluateRetrieval`, **fuera** de `build`/`check`). Indexa el corpus del
  propio dataset con el modelo E5 real y evalúa cada consulta con `HybridSearch`
  (reutiliza FT00017 **sin modificarla**). Sigue siendo **sin wiring**; la prueba
  real es **opt-in** (`DB_LIVE_TEST=1` + `EMBEDDING_LIVE_TEST=1`) y **no** se
  persiste el histórico (log JSON + stdout, sin migración). Ver `docs/adr/0013`.
  FT00020 añade **`rag/generation/`** y **`rag/summary/`**: el proveedor de texto
  **intercambiable** (`TextGenerationProvider` + `GenerationRequest`/
  `GenerationResponse`) con la implementación OpenCode
  (`OpenCodeTextGenerationProvider`, DTOs de wire con sufijo `Dto`, factory
  `openCodeHttpClient`, `Bearer` y parseo de `choices[0].message.content`) y su
  config por entorno con fail-fast de `OPENCODE_API_KEY` (`OpenCodeConfig`); y el
  **servicio de resumen ciudadano** (`CitizenSummaryGenerator`) que recupera con
  `HybridSearch`, construye el prompt puro (`CitizenSummaryPromptBuilder`), parsea
  la salida (`SummaryOutputParser`, quita *fences* de Markdown) e **inyecta la
  fuente oficial** desde `Publicacion.urlOficial` (nunca la produce el modelo) antes
  de **validar el contrato** con `CitizenSummaryValidator` (FT00019): devuelve
  `CitizenSummaryResult.Valid` o `Invalid` (un resumen inválido **no** se publica;
  no es una excepción). Sigue siendo una **librería sin wiring** y la prueba real es
  **opt-in** (`OPENCODE_LIVE_TEST=1`). Ver `docs/adr/0015`.
  FT00021 añade el **cacheo del resumen ciudadano** y el **control de coste**:
  `rag/summary/SummaryCacheKey` (clave **pura y determinista** = publicación +
  **modelo** + **versión de prompt**, fail-fast) y
  `rag/summary/CachedCitizenSummaryGenerator` (envuelve a `CitizenSummaryGenerator`
  sin reescribir su pipeline: consulta la caché **antes** del proveedor; en acierto
  devuelve el resumen cacheado sin llamar a OpenCode y registra uso con
  `cache_hit = true` y 0 tokens; en fallo genera, registra el uso real y **cachea
  solo si es `Valid`**). `GenerationResponse` gana `usage: TokenUsage?` (opcional) y
  el proveedor OpenCode parsea el bloque `usage`; `CitizenSummaryResult` propaga el
  uso de forma **compatible**. La persistencia son dos repositorios JDBC en
  `persistence/` (`SummaryCacheRepository` con codec JSON puro del `ResumenDto` y
  `GenerationUsageRepository` con `totalTokens()`) y la migración `V4`
  (`resumen_cache` + `generacion_uso`, tabla propia y separada de `resumen`). Sigue
  siendo una **librería sin wiring** (modelo inyectado por constructor, en
  producción de `OpenCodeConfig`); la prueba real es **opt-in** (`DB_LIVE_TEST=1`).
  Ver `docs/adr/0016`.
  FT00022 añade **`rag/guardrails/`**: la **capa de guardrails anti-alucinación y
  trazabilidad** que se ejecuta **después** de generar y **antes** de publicar
  (`SummaryGuardrail.evaluate(publication, summary, context)`). Combina la validación
  de **contrato** (`CitizenSummaryValidator`, FT00019, sin duplicar reglas) con la de
  **fuente** (`OfficialSourceValidator`: `https://`, host del BOE e **igualdad** con
  `Publicacion.urlOficial`; y el puerto `suspend` opcional `SourceReachability` /
  `HttpSourceReachability` con `HttpClient` inyectado y factory) y el **grounding**
  léxico (`SummaryTextNormalizer` + `SummaryGroundingChecker`: cifras estrictas y
  ≥`MIN_CLAIM_SUPPORT` = 0.6 de términos de contenido). Devuelve
  `SummaryGuardrailResult` con `GuardrailDecision` (`PUBLISHABLE`/`NEEDS_REVIEW`/
  `DISCARDED`), `isPublishable`, las violaciones de contrato y contenido y una
  **puntuación de grounding** `[0,1]` (umbrales `DISCARD_THRESHOLD` = 0.5 y
  `REVIEW_THRESHOLD` = 0.8). Es **offline, determinista y sin persistencia** (no
  escribe en `resumen` ni `cola_revision`; FT00023/FT00026) y **sin wiring**; la
  alcanzabilidad real es **opt-in** (`BOE_LIVE_TEST=1`). Ver `docs/adr/0017`.
  FT00023 añade **`rag/review/`**: la **disposición del resumen tras los
  guardrails** que **consume** la decisión tipada de FT00022 (sin umbral nuevo) y
  la **persiste**: `SummaryState` (los siete estados de `docs/domain-model.md`),
  `SummaryReviewOutcome` (`Published`/`Queued`/`Discarded`) y
  `SummaryDispositionService.dispose`, que escribe `estado` + `confianza`
  (`groundingScore`) en `resumen` y **encola** los `NEEDS_REVIEW` en `cola_revision`
  **sin publicarlos** (el publicado lleva `aviso_ia = true`; el aviso visible es
  FT00033). El encolado es **idempotente** por resumen pendiente: la migración `V5`
  crea un **índice único parcial** y `ReviewQueueRepository` pasa a *upsert*
  (`ON CONFLICT … DO UPDATE SET motivo`) y gana `listPending()`; `listBySummary` se
  mantiene. `SummaryRepository` **no** se modifica. Sigue siendo una **librería sin
  wiring** (el feed/endpoints/UI y la revisión manual son FT00026+/FT00033) y la
  prueba real es **opt-in** (`DB_LIVE_TEST=1`). Ver `docs/adr/0018`.
  FT00024 añade al paquete **`rag/evaluation/`** la **evaluación de la calidad del
  resumen ciudadano**: un **golden set versionado** (recurso
  `rag/eval/summary-golden-set.json` con publicaciones y su **resumen de
  referencia**, ids con prefijo `EVAL-S`), métricas **puras**
  (`SummaryQualityMetrics`: F1 léxico por campo con `SummaryTextNormalizer` de
  FT00022 + *recall* de cifras), el loader con fail-fast
  (`SummaryGoldenSetLoader`), el evaluador con un `fun interface SummaryGenerator`
  inyectable (`SummaryQualityEvaluator`: genera una vez por entrada, medias sin
  `NaN`, `hitRate` e `invalidCount`; un resumen inválido cuenta como fallo) y la CLI
  one-shot `SummaryEvaluationMain` (tarea `:backend:evaluateSummary`, **fuera** de
  `build`/`check`). **No** cambia la generación ni los guardrails: reutiliza
  `CitizenSummaryGenerator`/`SummaryGenerationDto` (FT00020) y
  `SummaryTextNormalizer` (FT00022) **sin modificarlos**; indexa el corpus con el
  modelo E5 real (`FragmentIndexer`) y evalúa cada resumen contra su referencia.
  Sigue siendo **sin wiring**; la prueba real es **opt-in**
  (`OPENCODE_LIVE_TEST=1` + `DB_LIVE_TEST=1` + `EMBEDDING_LIVE_TEST=1`) y **no** se
  persiste el histórico (log JSON `event=summary.evaluation.started`/`completed` +
  stdout, sin migración). Ver `docs/adr/0019`.
  FT00025 añade **`rag/chat/`**: la **generación del chat RAG** como librería sin
  wiring. `ChatPromptBuilder` (puro) construye el prompt con la consulta y el
  contexto **numerado** delimitado como **datos, no instrucciones**;
  `ChatOutputDto`/`ChatOutputParser` (puros) parsean la salida estructurada
  (**estado + respuesta + citas**) y traducen el token de estado con fail-fast;
  `ChatGroundingChecker` (puro) reutiliza `SummaryTextNormalizer` y
  `SummaryGroundingChecker.MIN_CLAIM_SUPPORT` (= 0.6) para degradar a
  `sin_fundamento` una respuesta no sustentada; `CitationResolver` es el
  `fun interface` que **inyecta** la fuente oficial desde la publicación (el modelo
  solo aporta índices); y `RagChatService.answer` compone recuperación → prompt →
  proveedor → parser → grounding → citas → `ChatResult.Answered`/`Refuted`/
  `Unfounded`. El **contexto vacío** declara `sin_fundamento` **sin invocar** al
  proveedor y una respuesta citada exige ≥1 cita resoluble. Sigue siendo **sin
  wiring** (el endpoint/rate limiting son FT00031 y la UI FT00037) y la prueba real
  es **opt-in** (`OPENCODE_LIVE_TEST=1`). Ver `docs/adr/0020`.
  FT00026 añade **`feed/`** y **`plugins/Feed.kt`**: el **feed diario** (primer
  endpoint de lectura de datos, `GET /feed?fecha=…&pagina=…&tamanoPagina=…`). La
  ruta delgada valida (`fecha` ISO obligatoria; paginación con default/máximo) y
  delega en `DailyFeedService` (`suspend`, lectura JDBC en `Dispatchers.IO`,
  paginación en memoria y destacados *on-the-fly* con `HighlightRanker`), que
  compone `FeedRepositoryJdbc` (una consulta `publicacion ⋈ resumen` filtrada por
  `estado = 'publicado'`, orden por `id`, fecha con *cast* `?::date`) y
  `FeedDtoMapper` (puro, hacia el contrato de `:shared`). Solo se sirven resúmenes
  publicados; `total`/`totalPaginas` reflejan el día completo y los destacados
  exponen `motivos` **sin** `score`. `configureRouting` registra `/feed` **solo**
  si el servicio no es `null`; el composition root crea un **pool JDBC único**
  compartido por la API y la ingesta y lo cierra una vez en `ApplicationStopped`
  (sin BD: `/health` operativo y `/feed` 404). Ver `docs/adr/0021`.
  FT00027 añade **`publication/`** y **`plugins/PublicationDetail.kt`**: el
  **detalle de una publicación** (`GET /publicacion/{id}`), el segundo endpoint de
  lectura de datos. `PublicationDetailService` (`suspend`, lectura JDBC en
  `Dispatchers.IO`) compone `PublicationRepository.findById` +
  `SummaryRepository.findByPublication` y **reutiliza** el mapeo puro
  `feed/FeedDtoMapper`; **solo** sirve publicaciones con resumen `publicado` (si no,
  identificador desconocido o categoría nula ⇒ `404`; `id` en blanco o desmesurado
  ⇒ `400`). `configureRouting` registra `/publicacion/{id}` **solo** si el servicio
  no es `null`; el composition root lo construye sobre el **mismo pool único** que
  el feed y la ingesta. En FT00027 aún **no** había búsqueda; OpenAPI/CORS/
  *rate limiting* (FT00029/FT00030) y la migración siguen pendientes. Ver
  `docs/adr/0022`.
  FT00028 añade **`search/`** y **`plugins/Search.kt`**: la **búsqueda** sobre el
  corpus (`GET /buscar?q=…&categoria=…&desde=…&hasta=…&limite=…`), el tercer
  endpoint de lectura de datos. `SearchService` (`suspend`, `Dispatchers.IO`)
  compone `HybridSearch` (FT00017, **sin modificarla**) con la lectura de
  publicaciones publicadas: recupera por similitud con filtros (`SearchFilter`),
  **deduplica** por publicación y **reutiliza** el mapeo puro `feed/FeedDtoMapper`;
  el resultado es **top-k** (`limite`, default 10, máx 50) sin paginación. Solo se
  sirven publicaciones con resumen `publicado`, resueltas por lote con
  `FeedRepository.listPublishedByIds` (`ANY(?)`, token `SummaryState.PUBLISHED`);
  un parámetro inválido responde `400` sin cuerpo tipado y una consulta sin
  resultados, `200` con lista vacía. `configureRouting` registra `/buscar` **solo**
  si el servicio no es `null`; el composition root **cablea por primera vez** el
  proveedor de embeddings locales (`E5EmbeddingProvider`, FT00015) de forma
  **condicional** (sin modelo, `/buscar` 404 y `/health` operativo) sobre el
  **mismo pool único** que el feed y la ingesta, y cierra el proveedor **una sola
  vez** en `ApplicationStopped`. Sin migración (`V1`…`V5` intactas) ni CORS/OpenAPI/
  *rate limiting*. Ver `docs/adr/0023`.
  FT00031 añade **`chat/`** y **`plugins/Chat.kt`**: el **chat RAG**
  (`POST /chat`), que **consume** la librería `rag/chat` (FT00025) **sin
  modificarla**. `ChatService` (`suspend`, `Dispatchers.IO`) envuelve
  `RagChatService.answer` y mapea su `ChatResult` al contrato de `:shared` con
  `ChatDtoMapper` (puro); la consulta se acota con `MAX_QUERY_LENGTH` y el contexto
  con el `limit` por defecto de `RagChatService` (no controlable por el cliente).
  `PublicationCitationResolver` es el **primer `CitationResolver` de producción**:
  adapta `PublicationRepository.findById` e **inyecta** la fuente oficial desde la
  publicación (el modelo solo aporta índices). El composition root **cablea por
  primera vez** el proveedor de texto de OpenCode (`OpenCodeConfig.fromEnv()` +
  `openCodeHttpClient()` + `OpenCodeTextGenerationProvider`, **fail-fast** de
  `OPENCODE_API_KEY` capturado ⇒ `null`) y reutiliza el proveedor de embeddings
  (ONNX) sobre el **mismo pool único**; `/chat` se registra **solo** si existen los
  tres (sin BD, modelo o clave es `404` y `/health` sigue `200`) y el pool, el
  proveedor y el cliente HTTP se cierran **una sola vez** en `ApplicationStopped`.
  Un cuerpo ilegible o una consulta inválida responden `400`, un fallo del proveedor
  o una salida no interpretable `502` y un fallo de la inferencia local `500` (sin
  cuerpo tipado; FT00030 unificará el contrato). Sin migración (`V1`…`V5` intactas)
  ni CORS/OpenAPI/*rate limiting*. Ver `docs/adr/0024`.
  FT00029 añade **`plugins/OpenApi.kt`** y el recurso
  **`src/main/resources/openapi/openapi.json`**: el **contrato OpenAPI 3.1
  estático y versionado** de los endpoints de dominio, servido en
  `GET /openapi.json` (`200` `application/json`, **siempre** registrado, sin
  depender de BD/modelo/OpenCode) y protegido por un **test anti-deriva**
  (`OpenApiContractTest`) que contrasta los esquemas con los `@SerialName`/tokens
  de los DTOs de `:shared`. `configureRouting` **prefija `/v1`** a las rutas de
  dominio (`/v1/feed`, `/v1/publicacion/{id}`, `/v1/buscar`, `/v1/chat`)
  reutilizando las funciones de ruta **sin** modificarlas; `/health` y
  `/openapi.json` quedan **sin** versión. Sin dependencia Gradle nueva, sin
  generación en compilación (Kotlin 2.1.20), sin migración y sin Swagger UI. Ver
  `docs/adr/0025`. (Las menciones a `/feed`, `/publicacion/{id}`, `/buscar` y
  `/chat` de las features anteriores se sirven **hoy** bajo ese prefijo `/v1`.)
  FT00030 añade **`plugins/{Cors,RateLimiting,Errors}.kt`** e
  **`infra/HttpHardeningConfig.kt`**: el **endurecimiento HTTP** de la API. **CORS**
  configurable por entorno (`CORS_ALLOWED_ORIGINS`; por defecto permisivo porque la
  API es pública y **sin credenciales**, con allowlist estricta si se define),
  **rate limiting por IP en memoria** (cupo general para `/v1/…`, por defecto
  60/60 s, y más **estricto** para `/v1/chat`, 6/60 s; `/health` y
  `/openapi.json` **exentos**) y **cuerpo de error tipado**
  `ApiErrorDto`/`ApiErrorCodeDto` (`:shared`) para `400`/`404`/`429`/`500`/`502` vía
  `StatusPages`, sin filtrar internos. Usa tres plugins **oficiales** de Ktor
  (CORS, RateLimit, StatusPages; dependencias Gradle nuevas, excepción deliberada
  documentada en el ADR 0026). El contrato OpenAPI se amplía (esquema de error,
  `429` con `Retry-After`, `info.version` `0.5.1`) y los tests de ruta `accepted`
  siguen verdes porque `configureRouting` aplica el rate limiting solo con
  `applyRateLimits = true` (por defecto `false`). Sin migración. Ver
  `docs/adr/0026`.
  Existe **`persistence/`** (FT00008): repositorios **JDBC**
  + entidades `...Entity` de `publicacion`, `fragmento`, `resumen` y
  `cola_revision`, más los helpers JDBC compartidos; la configuración de
  conexión (`infra/DatabaseConfig`, derivada de `POSTGRES_*`) y el pool
  (`infra/Database`, HikariCP ≤5) viven en `infra/`. El resto de paquetes
  llega con sus features. `Application.kt` **cablea la ingesta de forma
  condicional y no bloqueante**: solo si `INGESTA_ENABLED` está activo y la
  configuración de BD resuelve; un fallo al construirla se registra y el
  servidor sigue sirviendo `/health`; al parar se cancela el bucle y se cierran
  el **pool único** (una sola vez) y los clientes HTTP. El **mismo scope** arranca
  el scheduler y el vigilante de ventanas perdidas (`IngestionWatchdog`); la
  alerta es un log `ERROR` estructurado (`event=ingestion.missed`), **sin**
  alertas externas ni telemetría.
- **`:composeApp`** — cliente Compose Multiplatform (Android, iOS, Web).
  Namespace `es.aviferdev.datopublico`. Ya **existe y compila** para
  `androidTarget`, `iosArm64`/`iosSimulatorArm64` (framework `ComposeApp`) y
  `wasmJs` (browser, ejecutable), con la **UI compartida en `commonMain`**
  (`App()`) y un entrypoint por plataforma; además conserva `jvm()` **solo** para
  tests/dev. Desde FT00032 tiene la **primera UI real**: `design/` (tema
  `DatoPublicoTheme` con los tokens de `DESIGN.md` y componentes reutilizables
  `CategoryLabel`/`PublicationCard`/`PublicationBadges` en `design/components/`),
  **recursos i18n** en `composeResources/values/strings.xml` (todo texto visible
  sale de `stringResource(Res.string.*)`) y la **primera capa de feature** por
  capas `feature/feed/{domain,data,ui}` (modelos propios del cliente,
  `GetDailyFeed` + `FeedRepository`, `InMemoryFeedRepository` con datos de
  ejemplo, `FeedUiState`/`FeedStateHolder`/`FeedRoute`/`FeedScreen`/
  `HighlightsSection`). Desde FT00033 añade la **segunda capa de feature**
  `feature/detail/{domain,data,ui}` (`PublicationDetail`/`CitizenSummary`,
  `GetPublicationDetail`, `DetailRepository`+`InMemoryDetailRepository`,
  `DetailUiState`/`DetailStateHolder`/`DetailRoute`/`DetailScreen`) y los
  componentes `AiNotice`/`OfficialSourceLink`/`SectionBlock`; el detalle se
  entrega como **contrato** (`DetailRoute`, sin cablear la navegación). Desde
  FT00035 el **feed real** lo sirve un **cliente HTTP común** (`core/network/`,
  `ktor-client` con motores por plataforma, URL base y fecha por `expect/actual`,
  `HttpTimeout` y errores tipados) y `feature/feed/data/` añade **DTOs de wire del
  cliente** (capa anti-corrupción), su **mapeo al dominio** y una **cache offline en
  memoria**. Desde FT00034 el estado del feed lo expone un **`FeedViewModel`**
  (androidx.lifecycle multiplataforma) como `StateFlow<FeedUiState>` (UDF, composables
  stateless, `collectAsStateWithLifecycle`) y la app monta el **grafo de navegación**
  `app/AppNavHost`/`app/AppRoutes` (`feed` y `detail/{publicationId}`,
  `navigation-compose` oficial); el destino `detail` monta ya la **pantalla real**
  de FT00033 (`DetailRoute`, integrada por FT00034-PT1). Desde FT00037 añade la capa
  `feature/chat/{domain,data,ui}` (chat RAG con los estados de dominio, citas y
  aviso de IA; `HttpChatRepository` sobre `core/network`), el destino `chat` y una
  acción en el encabezado del feed. Desde FT00036 añade `feature/search/{domain,data,ui}`
  (búsqueda con filtros de categoría y rango de fechas; `HttpSearchRepository` sobre
  `core/network`), el destino `search` y una acción en el encabezado del feed. El
  encabezado del feed (con las acciones de chat y búsqueda) es visible en **todos**
  los estados. Desde FT00039-PT1 la **URL base de la API de la Web** se inyecta en
  **build time** (propiedad Gradle `apiBaseUrl` → constante `API_BASE_URL` generada
  **solo** en `wasmJsMain`; sin la propiedad vale `http://localhost:8080`) y el shell
  `index.html` lleva **metadatos SEO estáticos**. `:composeApp` **sigue sin cablear
  `:shared`** (para no romper el gate SDK-free). Decisiones durables en
  `docs/adr/0027`, `docs/adr/0028`, `docs/adr/0029`, `docs/adr/0031`,
  `docs/adr/0032` y `docs/adr/0033`.

## Build y gate

- Raíz Gradle multi-proyecto (Kotlin DSL) con **version catalog** (`gradle/libs.versions.toml`).
- `:shared` y `:backend` son **SDK-free**; `:composeApp` aplica AGP (exige el Android SDK)
  y se incluye salvo con `-PskipClient`.
- **Gate de calidad bloqueante**: **Detekt** por módulo (`config/detekt/detekt.yml` +
  `config/detekt/<módulo>-baseline.xml`) y **CPD** global (`:cpdCheck`, PMD, umbral 100
  tokens); `check`/`build` y `.harness/init.sh` los ejecutan. Un hallazgo nuevo o un
  duplicado rompe el build.
- **Gate estándar** (`.harness/init.sh`, SDK-free): `./gradlew build -PskipClient` +
  `./gradlew detekt`. Con `--with-client`/`--with-ios`/`--with-all` se añade el cliente
  (Android/Web, iOS).
- **Migraciones** Flyway con tareas explícitas (`./gradlew :backend:flywayMigrate`), fuera
  de `check`; la CI no necesita base de datos.

## Despliegue

Decisión durable en `docs/adr/0030`; runbook en `deploy/README.md`.

- **Imagen del backend** (`backend/Dockerfile`, multi-stage): build con JDK 21
  (`installDist -PskipClient`, sin Android SDK) y runtime JRE 21, usuario no-root,
  **sin secretos ni modelo**; `.dockerignore` deja el contexto pequeño.
- **Compose de producción** (`deploy/docker-compose.prod.yml`): `postgres`
  (pgvector, **solo loopback**, volumen `pgdata`), `backend` (**sin puerto
  publicado**; modelo montado `:ro`) y `nginx` (**única entrada**, puertos
  parametrizables `HTTP_PORT`/`HTTPS_PORT`), con `restart: unless-stopped` y
  healthchecks.
- **Nginx** termina **TLS** (certbot manual), redirige HTTP→HTTPS y hace proxy a
  `backend:8080` con `X-Forwarded-*`; el backend confía en esas cabeceras **solo**
  si `TRUST_PROXY_HEADERS=true` (por defecto false) para que el rate limiting vea la
  IP real.
- **Secretos por entorno** (`deploy/.env.production`, ignorado; plantilla
  `.example` versionada) con *fail-fast*. La **ingesta** es el scheduler interno
  (ADR 0004); **sin** cron externo. El **gate sigue offline** (Docker/`compose`/
  lint/`flywayMigrate` son opt-in). Alternativas para no ocupar el 80 documentadas
  (detrás de un proxy existente o backend directo sin Nginx).

### Publicación (CI/CD)

Decisión durable en `docs/adr/0034`; runbook en `docs/release.md` (producto).

- **Workflows** en `.github/workflows/`: `release.yml` (*umbrella* `workflow_dispatch`
  con `targets`/`version`/`environment`, que llama a los workflows por destino) y
  `release-backend.yml` (`workflow_call` + `workflow_dispatch` + `push: tags: v*`).
  PT2/PT3/PT4 (Web/Android/iOS) añadirán los suyos y su job al *umbrella*. Acción
  compuesta común `.github/actions/setup-jdk-gradle` (JDK 21 temurin + Gradle con
  caché) para los jobs que compilan en el runner.
- **Backend**: job `image` (Buildx → **GHCR**, `packages: write`, tags `<version>` y
  `latest`, caché `type=gha`) y job `deploy` (entorno `production`, **SSH** con
  acción *pinned*): fija el checkout del servidor en el tag y ejecuta
  `scripts/release/deploy-backend.sh` (pull + Flyway + `up -d` + health-check,
  fail-fast). Flyway usa la tarea Gradle del host si hay JDK y, si no, el contenedor
  `flyway/flyway` contra `127.0.0.1`.
- **Compose de producción generalizado**: `image: ${BACKEND_IMAGE}:${BACKEND_VERSION}`
  además de `build:`, de modo que el servidor hace `pull` del tag publicado y el
  desarrollo local sigue construyendo.
- **Reglas**: disparo manual o por tag (nunca en `push` a `main`), versión = tag
  semver, permisos mínimos, `cancel-in-progress: false`, secretos solo en GitHub
  Secrets/Environments o en el servidor, y el **gate intacto** (`ci.yml` y
  `.harness/init.sh` sin cambios; la verificación local es estática).


### Web (Wasm): build y servido

- **URL de la API por build**: la Web resuelve su URL base con la constante
  `API_BASE_URL` generada por la tarea `:composeApp:generateApiBaseUrlConfig` a
  partir de la propiedad Gradle `apiBaseUrl` (`-PapiBaseUrl=<url>`); sin la
  propiedad vale `http://localhost:8080` (desarrollo). La constante se genera
  **solo** en `wasmJsMain`
  (`composeApp/build/generated/apiConfig/wasmJsMain/`, no versionada) y se enlaza
  al source set, así que cualquier compilación de Wasm la regenera. Android, iOS
  y JVM **no** cambian su URL base.
- **Artefacto de producción**: `composeApp/build/dist/wasmJs/productionExecutable/`
  (`index.html` + `composeApp.js` + `*.wasm` + `favicon.svg` +
  `composeResources/`). El pipeline de **FT00052-PT2** lo publica por `rsync`/SSH
  y el Nginx lo sirve como **estático** en su *webroot* con *fallback* SPA
  (`try_files … /index.html`), conservando el proxy de `/v1/*`, `/health` y
  `/openapi.json` hacia el backend. El `deploy/` de FT00041 hoy **solo** hace
  proxy.
- **SEO del shell**: metadatos **estáticos** en `index.html` (título,
  `description`, `canonical`, `robots`, Open Graph y `theme-color`); el contenido
  lo pinta el cliente Wasm, así que **no** hay SSR ni SEO por norma (Non-Goal). El
  dominio de `canonical`/`og:url`/`og:image` es un *placeholder* hasta FT00052-PT2.
- **El gate sigue offline**: el servido estático es manual/opt-in y no se engancha
  a `build`/`test`/`detekt`/`init.sh` ni a la CI.

## Fronteras

- **Cliente → API HTTP** (público, solo lectura). El cliente no conoce los
  internals del backend. Desde FT00029 los endpoints de **dominio** se sirven bajo
  el prefijo de versión **`/v1`** y existe un **contrato OpenAPI 3.1** estático y
  versionado (`GET /openapi.json`, **sin** versión, como `/health`), que es la
  **fuente de verdad** del contrato (los DTOs `Dto` de `:shared` son su
  implementación, con un test anti-deriva en el gate); ver `docs/adr/0025`. Desde
  FT00026 el backend sirve el **feed diario**
  (`GET /v1/feed?fecha=…`, FT00026) con las publicaciones cuyo resumen está
  `publicado`, paginadas y con los destacados del día explicados por motivos, y
  desde FT00027 el **detalle de publicación** (`GET /v1/publicacion/{id}`), que
  reutiliza el **mismo** contrato `PublicacionDto` y el mismo mapeo que el feed, y
  desde FT00028 la **búsqueda** (`GET /v1/buscar?q=…`), que devuelve las
  publicaciones publicadas más relevantes por similitud semántica con el mismo
  contrato, y desde FT00031 el **chat RAG** (`POST /v1/chat`), que responde una
  pregunta o verifica una afirmación contra el corpus con los tres estados del
  dominio y las **citas a la fuente oficial** (contrato propio en `:shared`; ver
  `docs/adr/0021`, `docs/adr/0022`, `docs/adr/0023` y `docs/adr/0024`). Desde
  FT00030 la frontera incorpora **CORS** (resuelve el *preflight* del cliente Web),
  **rate limiting por IP en memoria** (general para `/v1/…` y más estricto para el
  chat; `/health` y `/openapi.json` exentos) y un **contrato de error tipado**
  (`ApiErrorDto`) para `400`/`404`/`429`/`500`/`502`, documentado en el OpenAPI; ver
  `docs/adr/0026`.
- **Backend → BOE** (API de datos abiertos + XML oficial, solo lectura, **sin
  clave ni credenciales**): `ingesta/` obtiene el sumario diario (JSON) y, por
  cada entrada, el **texto XML estructurado** (`xml.php`); el job programado
  (`ingesta/job/`, FT00009) **ejecuta esa descarga en runtime** a las 09:30 y en
  una segunda pasada (18:00 por defecto, `Europe/Madrid`, configurable) y
  persiste el resultado. Los clientes HTTP fijan `HttpTimeout` explícito. Es una
  dependencia **externa en tiempo de ejecución**, no del gate: los tests del gate
  no hacen red y las pruebas contra el BOE son opt-in. La **fuente de verdad** del
  texto y los metadatos es el XML estructurado, no el HTML (`txt.php`) ni el PDF
  (ver `docs/adr/0002`). El **backfill** (`ingesta/backfill/`, FT00011) reutiliza
  estas mismas piezas para poblar el histórico por lotes, fuera del arranque
  (ver `docs/adr/0006`).
- **Backend → PostgreSQL** (JDBC + **HikariCP**, **sin ORM**; migraciones
  **Flyway**; ver `docs/adr/0003`): los repositorios de `persistence/` escriben
  y leen `publicacion` (con `categoria` y `plazo` nullable), `fragmento` (con
  `embedding vector(384)` nullable e índice **HNSW** coseno desde FT00016),
  `resumen` y `cola_revision`; desde FT00021, `resumen_cache` (caché del resumen
  por clave determinista, con FK en cascada a `publicacion`) y `generacion_uso`
  (log de tokens, **sin** FK). La conexión se **deriva** de `POSTGRES_*` (fuente
  única, la misma que Compose/Flyway) y falla en claro si falta la contraseña. El
  *upsert* de publicación por `id` es idempotente y es la base del job diario: la
  segunda pasada reejecuta la misma fecha sin duplicar. Desde FT00026
  `Application.kt` crea un **pool único** si la config de BD resuelve, lo comparte
  entre el feed, el detalle, la búsqueda y el chat (API) y la ingesta, y lo cierra
  **una sola vez** en `ApplicationStopped`; sin BD no hay pool y ni el feed, ni el
  detalle, ni la búsqueda, ni el chat se registran (desde FT00031 el chat exige
  además el modelo E5 y `OPENCODE_API_KEY`). La
  **recuperación híbrida** (FT00017) consulta
  `fragmento` con un `JOIN publicacion` para aplicar los **filtros de metadatos**
  parametrizados (fecha/categoría/sección/organismo) junto a la distancia coseno;
  los valores de categoría/plazo los produce la ingesta desde FT00012
  (`ingesta/categorizacion/`, ver `docs/adr/0007`). Ver `docs/adr/0012`.
- **Backend → OpenCode** (API OpenAI-compatible, **solo salida**, con **clave
  solo en el servidor** por entorno `OPENCODE_API_KEY`, nunca versionada ni en
  logs): el proveedor de texto (`rag/generation/`, FT00020) envía el prompt con el
  contexto recuperado y lee `choices[0].message.content`; los clientes HTTP fijan
  `HttpTimeout` explícito. Es una dependencia **externa en tiempo de ejecución**, no
  del gate: los tests del gate usan un doble/`MockEngine` sin red y la prueba real
  es **opt-in** (`OPENCODE_LIVE_TEST=1`). Desde FT00031 el composition root lo
  **cablea de forma condicional** para el chat (sin `OPENCODE_API_KEY` el cliente
  queda a `null` y `/chat` es `404`, sin romper el arranque) y cierra el `HttpClient`
  una sola vez en `ApplicationStopped`. La **fuente oficial** no la produce el
  modelo: en el resumen se inyecta desde `Publicacion.urlOficial` (ver `docs/adr/0015`)
  y en el chat (`rag/chat/`, FT00025, ADR 0020) el modelo solo aporta **índices** de
  fragmento y el `CitationResolver` inyecta la URL de la publicación (en producción,
  `PublicationCitationResolver` sobre `PublicationRepository.findById`; ver
  `docs/adr/0024`).
- **Backend:** `plugins/` (HTTP) → servicios → dominio puro → repositorios y
  clientes → `infra/`.
- **IA:** embeddings **locales** (ONNX) y generación/chat **remoto** (OpenCode),
  cada uno tras una interfaz intercambiable. Los embeddings están **implementados**
  como librería en `rag/embeddings/` (FT00015, ADR 0010): E5 int8 vía ONNX Runtime
  en CPU, tras `EmbeddingProvider`; desde FT00028 se **cablea de forma
  condicional** en el composition root (sin modelo, `/buscar` 404) sobre
  pgvector/HNSW (FT00016). La **generación** está implementada como librería en
  `rag/generation/` + `rag/summary/` (FT00020, ADR 0015), tras
  `TextGenerationProvider`; desde FT00031 el chat la **cablea de forma
  condicional** en el composition root (sin `OPENCODE_API_KEY`, `/chat` 404) y el
  **cacheo** del resumen y el **control de coste** (FT00021, ADR 0016) la envuelven
  también **sin** wiring.
  Los **guardrails anti-alucinación** (FT00022, ADR 0017) verifican fuente y
  grounding **después** de generar y **antes** de publicar, también como librería sin
  wiring y sin persistencia. El **chat RAG** (`rag/chat/`, FT00025, ADR 0020) usa el
  mismo proveedor de texto intercambiable, con grounding léxico (reutiliza FT00022)
  y **citas inyectadas** desde la publicación.
- **Datos:** PostgreSQL + pgvector; migraciones Flyway (`V1` esquema base, `V2`
  persistencia, `V3` embedding + HNSW, `V4` caché de resúmenes + uso de tokens,
  `V5` índice único parcial de la cola de revisión pendiente).
  Sin cuentas ni datos personales.

## Reglas transversales

- El dominio es puro (sin Ktor, JDBC, ONNX ni HTTP).
- **Trazabilidad** obligatoria: todo resumen apunta a la fuente oficial.
- Secretos y claves **solo** por entorno, en el servidor.
- El texto de UI vive en recursos y en castellano.

## Convenciones de nombres

- **Todo el código (identificadores) va en inglés**: paquetes, tipos, funciones,
  propiedades, constantes, parámetros, variables y nombres de tests; el **KDoc y
  los comentarios van en castellano** (documentación del proyecto). Los
  identificadores que son datos/*tokens* de la fuente (*wire*) no se traducen. El
  código heredado en castellano (`PublicacionDto`, `CategoriaDto`,
  `EntradaSumario`, `Publicacion`, `BoeSumarioClient`…) se renombró a inglés en
  **FT00047** (sin cambio de wire/BD); el código nuevo no añade identificadores en
  castellano.
- **Todo tipo `@Serializable`/de transporte** lleva sufijo **`Dto`**: el contrato
  de **`:shared`** (las `data class` `PublicationDto`, `SummaryDto`, `DeadlineDto`,
  `DailySummaryDto` y los **enums de wire** `CategoryDto`, `BoeSectionDto`) y
  también los DTOs de transporte de **`:backend`** (`HealthDto`,
  `BoeSummaryResponseDto`, `BoeSectionNodeDto`…). Aplica a **cualquier** tipo
  `@Serializable`, no solo a los contenedores.
- La **configuración de serialización** (`DatoPublicoJson`) **no** es un tipo de
  contrato y va **sin** `Dto`.
- **Todo tipo `@Serializable`**: cada propiedad lleva `@SerialName` explícito,
  aunque el nombre coincida con la clave de wire (sin depender del nombre por
  defecto); los valores de los enums de wire también lo llevan.
- En las capas internas: entidades de persistencia `...Entity`, filas `...Row`,
  modelos de UI `...Ui`. Un **modelo de dominio/valor interno** que no sea
  serializable ni `Entity`/`Row`/`Ui` va **sin sufijo** (p. ej. `SummaryEntry`).
- **Sin prefijos** (nada de notación húngara).
