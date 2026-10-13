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
  el feed y la ingesta. Sigue **sin** filtros de búsqueda (FT00028), OpenAPI/CORS/
  *rate limiting* (FT00029/FT00030) ni migración. Ver `docs/adr/0022`.
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
  tests/dev. Aún **no** depende de `:shared` (llega con la primera UI que necesite
  DTOs, FT00032).

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

## Fronteras

- **Cliente → API HTTP** (público, solo lectura). El cliente no conoce los
  internals del backend. Desde FT00026 el backend sirve el **feed diario**
  (`GET /feed?fecha=…`, FT00026) con las publicaciones cuyo resumen está
  `publicado`, paginadas y con los destacados del día explicados por motivos, y
  desde FT00027 el **detalle de publicación** (`GET /publicacion/{id}`), que
  reutiliza el **mismo** contrato `PublicacionDto` y el mismo mapeo que el feed
  (ver `docs/adr/0021` y `docs/adr/0022`). Los demás endpoints (búsqueda FT00028,
  chat FT00031, OpenAPI/CORS/*rate limiting* FT00029/FT00030) llegan con sus
  features.
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
  entre el feed y el detalle (API) y la ingesta, y lo cierra **una sola vez** en
  `ApplicationStopped`; sin BD no hay pool y ni el feed ni el detalle se registran. La
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
  es **opt-in** (`OPENCODE_LIVE_TEST=1`). La **fuente oficial** no la produce el
  modelo: en el resumen se inyecta desde `Publicacion.urlOficial` (ver `docs/adr/0015`)
  y en el chat (`rag/chat/`, FT00025, ADR 0020) el modelo solo aporta **índices** de
  fragmento y el `CitationResolver` inyecta la URL de la publicación.
- **Backend:** `plugins/` (HTTP) → servicios → dominio puro → repositorios y
  clientes → `infra/`.
- **IA:** embeddings **locales** (ONNX) y generación/chat **remoto** (OpenCode),
  cada uno tras una interfaz intercambiable. Los embeddings están **implementados**
  como librería en `rag/embeddings/` (FT00015, ADR 0010): E5 int8 vía ONNX Runtime
  en CPU, tras `EmbeddingProvider`; **no** cableados aún y sin anticipar
  pgvector/HNSW (FT00016). La **generación** está implementada como librería en
  `rag/generation/` + `rag/summary/` (FT00020, ADR 0015), tras
  `TextGenerationProvider`, **sin** wiring ni endpoints; el **cacheo** del resumen y
  el **control de coste** (FT00021, ADR 0016) la envuelven también **sin** wiring.
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
  `EntradaSumario`, `Publicacion`, `BoeSumarioClient`…) se renombra de forma
  incremental (deuda **FT00047**); el código nuevo no añade identificadores en
  castellano.
- **Todo tipo `@Serializable`/de transporte** lleva sufijo **`Dto`**: el contrato
  de **`:shared`** (las `data class` `PublicacionDto`, `ResumenDto`, `PlazoDto`,
  `ResumenDiarioDto` y los **enums de wire** `CategoriaDto`, `SeccionBoeDto`) y
  también los DTOs de transporte de **`:backend`** (`HealthDto`,
  `BoeSumarioResponseDto`, `BoeSeccionDto`…). Aplica a **cualquier** tipo
  `@Serializable`, no solo a los contenedores.
- La **configuración de serialización** (`DatoPublicoJson`) **no** es un tipo de
  contrato y va **sin** `Dto`.
- **Todo tipo `@Serializable`**: cada propiedad lleva `@SerialName` explícito,
  aunque el nombre coincida con la clave de wire (sin depender del nombre por
  defecto); los valores de los enums de wire también lo llevan.
- En las capas internas: entidades de persistencia `...Entity`, filas `...Row`,
  modelos de UI `...Ui`. Un **modelo de dominio/valor interno** que no sea
  serializable ni `Entity`/`Row`/`Ui` va **sin sufijo** (p. ej. `EntradaSumario`).
- **Sin prefijos** (nada de notación húngara).
