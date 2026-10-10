# Architecture — DatoPublico

> Mapa durable de módulos y fronteras. **No** es un inventario de ficheros. El
> detalle por módulo vive en las skills `ktor-backend-architecture`,
> `compose-multiplatform-architecture` y `rag-datapublico`.

## Módulos (monorepo Gradle)

- **`:shared`** — DTOs y lógica compartida con `kotlinx.serialization`.
  Namespace `es.aviferdev.datopublico`.
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
  Existe **`persistence/`** (FT00008): repositorios **JDBC**
  + entidades `...Entity` de `publicacion`, `fragmento`, `resumen` y
  `cola_revision`, más los helpers JDBC compartidos; la configuración de
  conexión (`infra/DatabaseConfig`, derivada de `POSTGRES_*`) y el pool
  (`infra/Database`, HikariCP ≤5) viven en `infra/`. El resto de paquetes
  llega con sus features. `Application.kt` **cablea la ingesta de forma
  condicional y no bloqueante**: solo si `INGESTA_ENABLED` está activo y la
  configuración de BD resuelve; un fallo al construirla se registra y el
  servidor sigue sirviendo `/health`; al parar se cancela el bucle y se cierran
  el pool y los clientes HTTP. El **mismo scope** arranca el scheduler y el
  vigilante de ventanas perdidas (`IngestionWatchdog`); la alerta es un log
  `ERROR` estructurado (`event=ingestion.missed`), **sin** alertas externas ni
  telemetría.
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
  internals del backend.
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
  `resumen` y `cola_revision`. La conexión se **deriva** de `POSTGRES_*` (fuente
  única, la misma que Compose/Flyway) y falla en claro si falta la contraseña. El
  *upsert* de publicación por `id` es idempotente y es la base del job diario: la
  segunda pasada reejecuta la misma fecha sin duplicar. `Application.kt` crea el
  pool **solo** si la ingesta está habilitada y la config de BD resuelve, y lo
  cierra en `ApplicationStopped`. La **recuperación híbrida** (FT00017) consulta
  `fragmento` con un `JOIN publicacion` para aplicar los **filtros de metadatos**
  parametrizados (fecha/categoría/sección/organismo) junto a la distancia coseno;
  los valores de categoría/plazo los produce la ingesta desde FT00012
  (`ingesta/categorizacion/`, ver `docs/adr/0007`). Ver `docs/adr/0012`.
- **Backend:** `plugins/` (HTTP) → servicios → dominio puro → repositorios y
  clientes → `infra/`.
- **IA:** embeddings **locales** (ONNX) y generación/chat **remoto** (OpenCode),
  cada uno tras una interfaz intercambiable. Los embeddings están **implementados**
  como librería en `rag/embeddings/` (FT00015, ADR 0010): E5 int8 vía ONNX Runtime
  en CPU, tras `EmbeddingProvider`; **no** cableados aún y sin anticipar
  pgvector/HNSW (FT00016).
- **Datos:** PostgreSQL + pgvector; migraciones Flyway (`V1` esquema base, `V2`
  persistencia, `V3` embedding + HNSW). Sin cuentas ni datos personales.

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
