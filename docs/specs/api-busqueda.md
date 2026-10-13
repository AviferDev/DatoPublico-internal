# Feature Implementation Spec: Endpoint de búsqueda

## Source Feature

- `id`: api-busqueda
- `ft_id`: FT00028 (registrado en `docs/feature-ids.md`)
- `parts`: none (atómica; ≈14 ficheros de producto, por debajo del límite de 30)
- `area`: api-publica
- `depends_on`: recuperacion-hibrida (FT00017, `accepted`) — **más las
  dependencias implícitas** que el orquestador debe añadir: `api-feed-diario`
  (FT00026, `accepted`; se **reutilizan** `FeedDtoMapper` y se **extiende**
  `FeedRepository`) y `cola-revision-confianza` (FT00023, `accepted`; la búsqueda
  sirve **solo** resúmenes `estado = 'publicado'`, token que escribe FT00023).
  `chunking-articulos` (FT00014), `embeddings-locales-onnx` (FT00015) y
  `pgvector-indexado` (FT00016) quedan **cubiertos transitivamente** por FT00017.
- `status`: not_started (al planificar)
- `source`: `feature_list.json` (`notes`: `docs/roadmap.md` 0.5-T03)
- `claim`: rama `feat/ft00028-api-busqueda` ya reclamada en `origin`
  (`bdacc23 chore(FT00028): claim`), partiendo de `origin/main` `8bc7ad8` (que ya
  incluye FT00026). Sin PR abierto hacia `main`. **Nota de base**: FT00027
  (`api-detalle-norma`) está abierto en **PR #28 sin mergear**, así que su cambio
  en `Routing.kt`/`Application.kt` **no** está en esta base; el wiring de FT00028
  se hace **aditivo y compatible** (colaborador opcional extra).

> **Dependencias implícitas.** La búsqueda devuelve **publicaciones** con su
> resumen ciudadano **publicado** (mismo contrato `PublicacionDto` que el feed y el
> detalle; ADR 0021/0022). Servir solo `publicado` ata la feature al token que
> escribe FT00023 y reutilizar el mapeo/lectura de FT00026 la ata a FT00026. El
> orquestador debe añadir `api-feed-diario` (FT00026) y `cola-revision-confianza`
> (FT00023) a `depends_on` en `feature_list.json` (ambas `accepted` y ya en
> `main`). No se añaden más: FT00017 ya arrastra FT00014/FT00015/FT00016.

## Goal

Exponer por HTTP, en `:backend`, el **endpoint de búsqueda** del corpus (tarea
`0.5-T03`): dada una **consulta** (`q`), con **filtros opcionales de categoría**
(`categoria`) y **rango de fechas** (`desde`/`hasta`), devolver las
**publicaciones** más relevantes, ordenadas por **similitud semántica** sobre los
fragmentos indexados y **deduplicadas** por publicación. Cada resultado es el
**mismo** `PublicacionDto` de `:shared` que sirve el feed (con su `resumen`,
`categoria`, `urlOficial` y `plazo`), y se sirve **solo** si tiene un resumen
`estado = 'publicado'` (trazabilidad y coherencia con feed/detalle).

La feature **reutiliza sin modificar** la recuperación híbrida
(`rag/retrieval`: `HybridSearch`/`SearchFilter`/`SearchFilterSql`, FT00017) y el
mapeo/servicio de lectura del feed (`feed/FeedDtoMapper`, `persistence/FeedRepository`,
FT00026); **cablea por primera vez** el proveedor de embeddings locales
(`rag/embeddings`, FT00015) de forma **condicional** (solo si el modelo está
disponible), registra `/buscar` **solo** si hay pool y proveedor, y reutiliza el
**pool JDBC único** ya compartido por la API y la ingesta. **No** inventa
comportamiento fuera de `docs/roadmap.md` 0.5-T03, `docs/domain-model.md`
(§Búsqueda), `DESIGN.md` (§Core Screens: Búsqueda) y el precedente ADR 0021/0022.

## Non-Goals

- **Chat RAG** (`api-chat`, FT00031) y **rate limiting** (FT00030).
- **CORS, OpenAPI/versionado del path y cuerpo de error consistente**
  (FT00029/FT00030): la búsqueda responde `400` **sin cuerpo tipado**, como el feed.
- **UI** (FT00032+): aquí solo se produce el **contrato** que consumirá el cliente.
- **Fragmento/snippet del fragmento que casa** en la respuesta: se devuelve la
  publicación (su `resumen` publicado), no el fragmento crudo. Diferido.
- **Filtros de sección/organismo** (existen en `SearchFilter`, pero la feature solo
  expone categoría y fecha; el «ámbito» es de `0.9-T01`).
- **Reranking, fusión léxica (BM25/trigram), `ef_search`, paginación profunda**:
  la búsqueda es **top-k** (semántica ANN), no paginable de forma significativa.
- **Indexar el corpus completo** (operación, fuera de alcance): la búsqueda solo
  consulta el índice `fragmento` existente.
- **Modificar** `HybridSearch`/`SearchFilter`/`SearchFilterSql`/`FragmentRepository`/
  `PgVector`/`ArticleChunker`/`rag/embeddings` (se **reutilizan** tal cual),
  `SummaryRepository`/`PublicationRepository`/`HighlightRanker`, el job/backfill,
  ni `:shared` (más allá del DTO nuevo), `:composeApp`, CI, `init.sh` o migraciones
  (`V1`…`V5` intactas; **sin** migración nueva).

## Job Story

When busco un tema concreto («becas para jóvenes», «oposiciones de sanidad») y
acoto por categoría o por fecha,
I want recibir una lista breve de publicaciones del BOE relevantes, cada una con su
resumen ciudadano publicado y su enlace oficial,
so I can encontrar normas más allá del feed del día y saltar siempre a la fuente
oficial sin que se me sirva una publicación sin resumen publicado.

## Users And Permissions

- **Ciudadanía (usuario final):** anónima, solo lectura; sin cuentas ni datos
  personales; el endpoint es público.
- **Cliente CMP (FT00032/FT00037):** consumidor del contrato `:shared`; envía `q`
  y los filtros, y renderiza `PublicacionDto`.
- **Operador/desarrollador:** arranca el backend con PostgreSQL y el modelo E5, y
  ejecuta la prueba real **opt-in** (`DB_LIVE_TEST=1`, `EMBEDDING_LIVE_TEST=1`).
- Sin autenticación, sin autorización y sin escritura.

## Acceptance Scenarios

### Scenario 1: consulta con filtro de categoría → publicaciones de esa categoría

Given un índice con fragmentos de publicaciones de categorías distintas, todas con
resumen `publicado`,
When `GET /buscar?q=<tema>&categoria=becas_subvenciones_y_ayudas`,
Then responde `200` con `SearchResultsDto` (`q` eco de la consulta, `resultados`
con las publicaciones que casan), **solo** de esa categoría, deduplicadas, con su
`resumen` (no nulo), `categoria` y `urlOficial`, y sin superar `limite`.

### Scenario 2: rango de fechas inclusivo

Given publicaciones en fechas distintas,
When `GET /buscar?q=<tema>&desde=2026-01-01&hasta=2026-03-31`,
Then solo aparecen publicaciones con `desde <= fechaPublicacion <= hasta`.

### Scenario 3: solo se sirven resúmenes publicados

Given una publicación con resumen `publicado`, otra `en_cola_revision` y otra
`pendiente` (las tres con fragmentos que casan),
When se busca,
Then solo aparece la `publicado`; las demás **no** se sirven (aunque el fragmento
exista) ni un enlace roto: el resultado es coherente con `/feed` y
`/publicacion/{id}`.

### Scenario 4: consulta sin resultados → 200 con lista vacía

Given una consulta sin fragmentos que cumplan,
When se busca,
Then responde `200` con `resultados` vacío (no es un error); el estado «sin
resultados» lo pinta el cliente (FT00032+).

### Scenario 5: parámetros inválidos → 400

Given una petición sin `q` o con `q` en blanco, con `categoria` que no es un token
válido (`CategoriaDto`), con `desde`/`hasta` no ISO (`YYYY-MM-DD`), o con `limite`
no entero, `< 1` o `> MAX_LIMIT`,
When se busca,
Then responde `400` (sin cuerpo tipado; el contrato de error es FT00030). Un rango
`desde > hasta` **no** es error: responde `200` con `resultados` vacío.

### Scenario 6: arranque sin BD o sin modelo intacto

Given un entorno **sin** `POSTGRES_PASSWORD` o **sin** `EMBEDDING_MODEL_PATH`/
`EMBEDDING_TOKENIZER_PATH` (o sin el modelo en disco),
When arranca el backend,
Then `/health` responde `200`, la ruta `/buscar` **no** se registra (`404`), el
arranque **no** falla y no se abre ninguna conexión. Con BD **y** modelo, `/buscar`
se registra, usa el **mismo pool** que el feed/la ingesta (cerrado una sola vez) y
el proveedor de embeddings se cierra **una sola vez** en `ApplicationStopped`.

### Scenario 7: el gate sigue sin red, BD ni modelo

Given el runner de CI sin PostgreSQL, sin Docker y sin el modelo E5,
When se ejecuta `./gradlew build -PskipClient`, `./gradlew test`, `./gradlew
detekt` o `.harness/init.sh`,
Then todo está en verde; el `EmbeddingProvider` es un **doble determinista** en los
tests y las pruebas reales se omiten sin sus variables.

### Scenario 8: extremo a extremo real (opt-in)

Given PostgreSQL migrado (Docker) y el modelo E5 descargado,
When se indexa una publicación (`FragmentIndexer`) y se ejecuta
`DB_LIVE_TEST=1 EMBEDDING_LIVE_TEST=1` sobre `/buscar` (o `SearchService.search`),
Then la publicación relevante aparece **primero** y el filtro de categoría/fecha se
respeta.

## Repository Research

### Files Inspected

- `.harness/feature_list.json` (FT00028; FT00026/FT00027/FT00023/FT00017
  `accepted`), `PROGRESS.md` (Sessions 066–069), `docs/feature-ids.md`,
  `docs/roadmap.md` §0.5 (`0.5-T03`), `docs/domain-model.md` (§Búsqueda),
  `DESIGN.md` §Core Screens (Búsqueda), `docs/risks-and-open-questions.md`
  («Estrategia de caché y paginación de la API»), `docs/technical-discovery.md`
  (§Data and Storage: filtros SQL por metadatos), `CONTEXT.md`,
  `ARCHITECTURE.md`, `CONSTRAINTS.md` (§«API pública: feed diario», §«Recuperación
  híbrida e indexado», §«Nombres», §«Serialización»), skills
  **`ktor-backend-architecture`** y **`rag-datapublico`** §4, ADR 0012, 0021 y
  0022, y los specs `recuperacion-hibrida.md`, `api-feed-diario.md` y
  `api-detalle-norma.md`.
- Producto `..` (rama `feat/ft00028-api-busqueda`, base `8bc7ad8`):
  - `backend/.../rag/retrieval/HybridSearch.kt` (`search(query, filter, limit)`,
    `DEFAULT_LIMIT = 10`, fail-fast de `query`/`limit`), `SearchFilter.kt`
    (`publishedFrom`/`publishedTo`/`category`/`section`/`organization`, valor
    interno sin sufijo) y `SearchFilterSql.kt` (`whereClause`/`parameters` puros,
    `?::date`, fail-fast de fecha no ISO).
  - `backend/.../persistence/FragmentRepository.kt` (`findNearest`, `FragmentMatch`,
    `FragmentEntity`, `toEntity`), `Jdbc.kt` (`queryRows`, `executeUpdate`),
    `SummaryRepository.kt` (`SummaryEntity`, `toSummaryEntity`, `findByPublication`),
    `PublicationRepository.kt` (`PublicationEntity`, `toDomain`, `findById`).
  - `backend/.../persistence/FeedRepository.kt` (`FeedItem`, `FeedRepository`,
    `FeedRepositoryJdbc` con `PUBLICATION_COLUMNS`/`SUMMARY_COLUMNS` **privados**,
    `toFeedItem`/`toFeedPublicationEntity`, filtro `estado = 'publicado'`,
    `?::date`, exclusión de categoría nula).
  - `backend/.../feed/DailyFeedService.kt` (`suspend`, `Dispatchers.IO`,
    paginación, constantes) y `feed/FeedDtoMapper.kt`
    (`toPublicacionDto(Publicacion, SummaryEntity)` **puro**, reutilizable).
  - `backend/.../plugins/Routing.kt` (`configureRouting(feedService: DailyFeedService? = null)`),
    `plugins/Feed.kt` (`GET /feed` + `FeedRequest.from`), `plugins/Serialization.kt`.
  - `backend/.../Application.kt` (composition root con **pool JDBC único**
    condicional, `createDataSourceOrNull`, `feedServiceOf`, cierre en
    `ApplicationStopped`, `configureIngestion`).
  - `backend/.../rag/embeddings/{EmbeddingProvider,E5EmbeddingProvider,EmbeddingConfig}.kt`
    (`E5EmbeddingProvider.from(modelPath, tokenizerPath, maxTokens)`,
    `EmbeddingConfig.fromEnv()` internal con fail-fast `EmbeddingException`,
    `AutoCloseable`), y `rag/review/SummaryState.kt`
    (`PUBLISHED.persistedValue = "publicado"`).
  - `shared/.../model/{PublicacionDto,ResumenDiarioDto,CategoriaDto,SeccionBoeDto}.kt`
    (wire con `@SerialName` explícito; `CategoriaDto` con tokens `snake_case`).
  - `backend/.../test/.../plugins/FeedRouteTest.kt` (patrón `testApplication` con
    repositorio en memoria), `persistence/FeedPersistenceLiveTest.kt`,
    `rag/retrieval/HybridSearchLiveTest.kt`, `rag/indexing/FragmentIndexerLiveTest.kt`
    (`DB_LIVE_TEST=1` / `EMBEDDING_LIVE_TEST=1`).
- Git: rama `feat/ft00028-api-busqueda` (claim `bdacc23`) en `origin`; `main` en
  `8bc7ad8` (incluye FT00026); **PR #28** (FT00027) abierto sin mergear.

### Existing Patterns To Follow

- **Ruta delgada en `plugins/`** + **servicio sin Ktor** (`search/SearchService`) +
  **repositorio JDBC** en `persistence/`; `configureRouting(...)` recibe
  colaboradores opcionales y registra cada ruta solo si existen.
- **Reutilizar** `HybridSearch` (que ya compone `embedQuery` + `findNearest`
  filtrado), `SearchFilter`/`SearchFilterSql` (filtros parametrizados),
  `FeedDtoMapper.toPublicacionDto` y los mappers internos de `FeedRepositoryJdbc`;
  **no** duplicar SQL ni mapeo.
- **DTO de transporte** en `:shared` con sufijo `Dto`, `@SerialName` explícito y
  tokens estables (el wire existente es castellano: `publicaciones`, `fecha`…).
- **Trabajo bloqueante fuera del event loop**: la lectura JDBC y la inferencia ONNX
  se envuelven en `withContext(Dispatchers.IO)`.
- **Tests del gate** con dobles deterministas (`EmbeddingProvider`/`FragmentRepository`/
  `FeedRepository` en memoria) y `testApplication`; pruebas reales **opt-in**
  (`DB_LIVE_TEST=1`, `EMBEDDING_LIVE_TEST=1`).
- **Estilo MUST**: identificadores en inglés (KDoc en castellano), un solo `return`,
  sin `else if`, funciones ≤40 líneas, `@SerialName` explícito.

### Current Gaps

- No existe ningún endpoint de **búsqueda** ni capa de servicio que componga
  `HybridSearch` con la lectura de publicaciones publicadas.
- `FeedRepository` solo lee **por fecha** (`listPublishedByDate`): no hay lectura por
  lote de identificadores para resolver los fragmentos devueltos.
- `EmbeddingProvider` **nunca** se ha **cableado** en el arranque: el composition
  root no lo construye ni lo cierra.
- `configureRouting` solo admite el `feedService`; la búsqueda necesita un
  colaborador opcional **adicional**.
- No hay contrato de transporte para una lista de resultados de búsqueda.

## Technical Approach

Deriva de `docs/roadmap.md` 0.5-T03 («query + filtros de categoría y fecha»),
`docs/domain-model.md` («Búsqueda: consulta del usuario con filtros de categoría y
fecha») y `DESIGN.md` («Búsqueda: campo + filtros (categoría, fecha) + resultados»).
La unidad de resultado es la **Publicación** (no el fragmento): el cliente navega al
detalle y renderiza la tarjeta del feed, por eso se devuelve el **mismo**
`PublicacionDto` y **solo** publicaciones con resumen publicado (ADR 0021/0022).

### 1. Contrato de transporte (`:shared`, `model/`)

- **`SearchResultsDto` (create):**
  - `@SerialName("q") val query: String` (eco de la consulta).
  - `@SerialName("resultados") val results: List<PublicacionDto> = emptyList()`.
  - Sin `total`/paginación: la búsqueda es **top-k** (ANN), no paginable de forma
    significativa (documentado en el ADR).
- **Sin** DTO de resultado por ítem: cada resultado es un `PublicacionDto` completo
  (se **reutiliza** el contrato y `FeedDtoMapper`).

### 2. Lectura de persistencia (`persistence/FeedRepository.kt`, modify — aditivo)

- Añadir a la interfaz:
  ```kotlin
  /** Publicaciones con resumen publicado cuyos id están en [ids] (lote). */
  fun listPublishedByIds(ids: List<String>): List<FeedItem>
  ```
- `FeedRepositoryJdbc` la implementa **reutilizando** `PUBLICATION_COLUMNS`/
  `SUMMARY_COLUMNS` y `toFeedItem()`:
  ```sql
  SELECT <publicacion> , <resumen>
  FROM publicacion p
  JOIN resumen r ON r.publicacion_id = p.id
  WHERE p.id = ANY(?) AND r.estado = ?
  ```
  *binding*: `statement.connection.createArrayOf("text", ids.toTypedArray())` +
  `SummaryState.PUBLISHED.persistedValue` (token tipado de FT00023, ya que
  `persistence/` **ya** depende de `rag` —`Fragment`—; evita el literal
  `'publicado'` que sí usa FT00026). Se mantiene la exclusión de **categoría nula**
  (dato corrupto). `ids` vacío ⇒ lista vacía **sin** abrir conexión (guard).
- **No** se toca `PublicationRepository`/`SummaryRepository` ni el SQL por fecha.

### 3. Servicio de aplicación (`search/SearchService.kt`, create)

```kotlin
class SearchService(
    private val hybridSearch: HybridSearch,
    private val feedRepository: FeedRepository,
) {
    suspend fun search(
        query: String,
        category: CategoriaDto? = null,
        publishedFrom: String? = null,
        publishedTo: String? = null,
        limit: Int = DEFAULT_LIMIT,
    ): SearchResultsDto
}
```
1. `require(query.isNotBlank())` y `require(limit in 1..MAX_LIMIT)` (fail-fast; la
   ruta lo traduce a `400`). Mirror de `DailyFeedService.feed`.
2. `filter = SearchFilter(publishedFrom, publishedTo, category)`.
3. `matches = withContext(Dispatchers.IO) { hybridSearch.search(query, filter,
   candidateLimit(limit)) }` (vectoriza con `embedQuery` y consulta
   `findNearest` filtrado; **reutiliza** FT00017 sin modificarlo).
4. `rankedIds = matches.map { it.fragment.publicationId }.distinct().take(limit)`
   (deduplica por publicación conservando el orden de relevancia).
5. `items = withContext(Dispatchers.IO) { feedRepository.listPublishedByIds(rankedIds) }`;
   se reordenan por el índice de `rankedIds` y se descartan las publicaciones **sin**
   resumen publicado (el filtro vive en SQL).
6. `SearchResultsDto(query = query, results = ordered.map { FeedDtoMapper.toPublicacionDto(it.publication, it.summary) })`.
- Constantes en `companion object` (documentadas): `DEFAULT_LIMIT = 10` (alineado con
  `HybridSearch.DEFAULT_LIMIT`), `MAX_LIMIT = 50`, `CANDIDATE_FACTOR = 5`
  (`candidateLimit = limit * CANDIDATE_FACTOR`, heurística para que el recorte por
  publicación no deje por debajo de `limit` resultados distintos).

### 4. Ruta (`plugins/Search.kt`, create; `plugins/Routing.kt`, modify — aditivo)

- `fun Route.searchRoutes(service: SearchService)`: `GET /buscar`.
  - Query params: `q` (**obligatoria**, no vacía), `categoria` (opcional, **token de
    wire** de `CategoriaDto`, p. ej. `normas_y_legislacion`; se resuelve por el
    contrato `@SerialName` compartido, **no** por nombre de enum), `desde`/`hasta`
    (opcionales, ISO `YYYY-MM-DD` inclusivas), `limite` (opcional, default `10`,
    máx `50`).
  - `SearchRequest.from(parameters)` (valor interno de la capa HTTP, no DTO) valida
    y devuelve `null` ⇒ `400` (misma forma que `FeedRequest`); `q` ausente/en blanco,
    `categoria` presente pero inválida, fecha no ISO o `limite` inválido ⇒ `400`.
  - `call.respond(HttpStatusCode.OK, service.search(...))`.
- `configureRouting(feedService: DailyFeedService? = null, searchService: SearchService? = null)`
  registra `/buscar` **solo** si `searchService != null`. **Aditivo y compatible**:
  los llamantes existentes (`configureRouting()`, `configureRouting(feedService)`)
  siguen compilando; tras el merge de FT00027 (PR #28) este parámetro pasa a ser el
  tercer colaborador (conflicto trivial a resolver por el orquestador).

### 5. Wiring (`Application.kt`, modify)

- Añadir `createEmbeddingProviderOrNull()`: intenta `E5EmbeddingProvider.from(
  EmbeddingConfig.fromEnv().modelPath, .tokenizerPath, .maxTokens)`; captura
  `Exception` (`EmbeddingException` incluida) → `log.warn` + `null`
  (rethrow de `CancellationException`). **El arranque no falla** si falta el modelo.
- `searchServiceOf(dataSource, embeddingProvider) = if (dataSource == null ||
  embeddingProvider == null) null else SearchService(HybridSearch(embeddingProvider,
  FragmentRepositoryJdbc(dataSource)), FeedRepositoryJdbc(dataSource))`.
- `configureRouting(feedServiceOf(dataSource), searchServiceOf(dataSource, embeddingProvider))`.
- Cerrar el proveedor **una sola vez** en `ApplicationStopped` (es `AutoCloseable`),
  igual que el pool. El pool lo comparte la búsqueda con el feed y la ingesta.
- **Sin** wiring del pipeline de resumen (FT00020–FT00023 siguen siendo librerías):
  el índice de fragmentos puede estar vacío en runtime hasta que exista el indexado
  del corpus (mismo gap de planificación que FT00026, ver *Risks*).

### Sin anticipar lo diferido

Sin migración (`V1`…`V5` intactas), sin dependencias Gradle nuevas, sin CORS/rate
limiting/OpenAPI/cuerpo de error (FT00029/FT00030), sin UI (FT00032+), sin tocar
`:composeApp`/CI/`init.sh`, sin modificar `HybridSearch`/`SearchFilter`/
`SearchFilterSql`/`FragmentRepository`/`PgVector`/`rag/embeddings`/
`SummaryRepository`/`PublicationRepository`/`HighlightRanker`.

## Expected File Changes

Rutas en el repo de producto (`..`); `es/aviferdev/datopublico` se abrevia `…`:

- `shared/src/commonMain/kotlin/…/model/SearchResultsDto.kt` — create; contrato de
  respuesta (`q` + `resultados`).
- `shared/src/commonTest/kotlin/…/model/SearchContractTest.kt` — create; gate,
  round-trip y tokens `@SerialName`.
- `backend/src/main/kotlin/…/backend/search/SearchService.kt` — create; servicio
  (`suspend`, `Dispatchers.IO`, dedup, constantes).
- `backend/src/main/kotlin/…/backend/persistence/FeedRepository.kt` — modify;
  `listPublishedByIds(ids)` (batch, `ANY(?)`, token `SummaryState.PUBLISHED`).
- `backend/src/main/kotlin/…/backend/plugins/Search.kt` — create; `GET /buscar` +
  `SearchRequest.from` (validación 400).
- `backend/src/main/kotlin/…/backend/plugins/Routing.kt` — modify; colaborador
  opcional `searchService`.
- `backend/src/main/kotlin/…/backend/Application.kt` — modify; proveedor de
  embeddings condicional + servicio de búsqueda + cierre.
- `backend/src/test/kotlin/…/backend/search/SearchServiceTest.kt` — create; gate,
  dobles (escenarios 1–4, 7).
- `backend/src/test/kotlin/…/backend/plugins/SearchRouteTest.kt` — create; gate,
  `testApplication` (200/400/404).
- `backend/src/test/kotlin/…/backend/persistence/SearchPersistenceLiveTest.kt` —
  create; **opt-in** `DB_LIVE_TEST=1` (solo publicados por lote).
- `backend/src/test/kotlin/…/backend/search/SearchServiceLiveTest.kt` — create;
  **opt-in** `DB_LIVE_TEST=1` + `EMBEDDING_LIVE_TEST=1` (modelo E5 + PostgreSQL).
- `docs/desarrollo-local.md` (producto) — modify; sección «Búsqueda
  (`GET /buscar`)» con `curl` y variables `EMBEDDING_*`.

Harness (privado): `ARCHITECTURE.md`, `CONSTRAINTS.md`, ADR `0023` + índice,
skills `ktor-backend-architecture`/`rag-datapublico`, `PROGRESS.md`,
`feature_list.json` (ver *Durable Documentation Impact*).

Total ≈ **14 ficheros de producto/código** + docs: por debajo del límite de 30 →
**no** requiere división en partes `FT00028-PTn`.

## Visual Design Impact

- UI involved: no. Sin pantallas, tokens ni textos.
- Design source: `DESIGN.md` §Core Screens («Búsqueda: campo + filtros (categoría,
  fecha) + resultados») y §Components (tarjeta de publicación reutilizada por el
  feed); aquí solo se produce el **contrato** que la UI consumirá (FT00032+).
- New design artifact required: no.

## Durable Documentation Impact

- `ARCHITECTURE.md`: **update** — `:shared` gana `SearchResultsDto`; `:backend` gana
  `search/` (servicio) y `plugins/Search.kt` (ruta), amplía `FeedRepository` y
  **cablea por primera vez** el `EmbeddingProvider` (ONNX) en el composition root;
  la frontera «Cliente → API HTTP» incorpora la búsqueda.
- `CONSTRAINTS.md`: **update** — nueva sección **«API pública: búsqueda»**: solo
  lectura y pública; devuelve publicaciones con resumen `publicado` (token de
  FT00023) como el feed/detalle; filtros por categoría y rango de fechas
  parametrizados vía `SearchFilter`; top-k (sin paginación); reutiliza
  `HybridSearch`/`FeedDtoMapper`; el arranque no depende del modelo (ruta
  condicional); el proveedor de embeddings se cierra una vez; pruebas reales
  **opt-in**; sin CORS/rate limit/OpenAPI/cuerpo de error ni migración.
- `AGENTS.md`: **not needed** — no cambia el flujo, el arranque ni las reglas.
- **ADR `docs/adr/0023-api-busqueda-endpoint.md`** (create, por el
  implementer/orquestador): decisión durable «búsqueda sobre el corpus con
  `HybridSearch`, resultado a nivel de publicación, solo resúmenes `publicado` y
  top-k; wiring condicional del proveedor de embeddings» + índice
  `docs/adr/README.md`.
- `.agents/skills/ktor-backend-architecture/SKILL.md`: **update** (sección API:
  `/buscar` + pool/proveedor condicional).
- `.agents/skills/rag-datapublico/SKILL.md`: **update** §4 (la búsqueda HTTP consume
  `HybridSearch`).
- `docs/desarrollo-local.md` (producto): **update**.
- `feature_list.json`/`PROGRESS.md`: los cierra el orquestador.

## Implementation Plan

1. Definir el contrato `SearchResultsDto` en `:shared` con `@SerialName` explícito y
   su test de gate (`SearchContractTest`).
2. Ampliar `FeedRepository`/`FeedRepositoryJdbc` con `listPublishedByIds` (batch,
   `ANY(?)`, token `SummaryState.PUBLISHED`, exclusión de categoría nula).
3. Crear `SearchService` (`suspend`, `Dispatchers.IO`, dedup, `candidateLimit`) y su
   test de gate con dobles (`SearchServiceTest`, escenarios 1–4).
4. Crear `plugins/Search.kt` (`GET /buscar`, validación, `400`) y `SearchRouteTest`
   (`testApplication`, 200/400/404).
5. Modificar `Routing.kt` (colaborador opcional) y `Application.kt` (proveedor de
   embeddings condicional + servicio + cierre); verificar `/health` sin BD/modelo y
   el arranque con ambos.
6. Añadir `SearchPersistenceLiveTest` y `SearchServiceLiveTest` (**opt-in**).
7. Pasar el gate sin red ni BD ni modelo y actualizar `ARCHITECTURE.md`,
   `CONSTRAINTS.md`, ADR 0023 + índice, skills y `docs/desarrollo-local.md`;
   `PROGRESS.md`/`feature_list.json` los cierra el orquestador.

## Implementation Tasks

- [ ] `:shared`: `SearchResultsDto` (`q` + `resultados`) + `SearchContractTest`.
- [ ] `persistence/FeedRepository`: `listPublishedByIds` (batch, `ANY(?)`,
      `SummaryState.PUBLISHED.persistedValue`, categoría nula excluida).
- [ ] `search/SearchService`: `search(query, category, publishedFrom, publishedTo,
      limit)` (dedup, `CANDIDATE_FACTOR`, `DEFAULT_LIMIT`/`MAX_LIMIT`).
- [ ] `plugins/Search.kt` (`GET /buscar`, validación de `q`/`categoria`/`desde`/`hasta`/
      `limite`, 400/200) + `plugins/Routing.kt`.
- [ ] `Application.kt`: `createEmbeddingProviderOrNull` + `searchServiceOf` +
      cierre del proveedor; rutas condicionales.
- [ ] Tests de gate: servicio (escenarios 1–4), contrato de `:shared` y ruta
      (200/400/404).
- [ ] Live opt-in: `SearchPersistenceLiveTest` (`DB_LIVE_TEST=1`) y
      `SearchServiceLiveTest` (`DB_LIVE_TEST=1` + `EMBEDDING_LIVE_TEST=1`).
- [ ] Docs: `ARCHITECTURE.md`, `CONSTRAINTS.md`, ADR 0023 + índice, skills y
      `docs/desarrollo-local.md`.

## Verification Plan

Desde la raíz del producto (`..`, JDK 21 vía JBR/`JAVA_HOME`):

- **Gate sin red ni BD ni modelo (obligatorio)**: `./gradlew :backend:test
  --rerun-tasks` y `./gradlew :shared:jvmTest` → BUILD SUCCESSFUL con los tests
  nuevos en verde (0 fallos) y el resto intacto; `./gradlew build --no-daemon
  -PskipClient` (incluye `detekt` + `:cpdCheck`), `./gradlew test`, `./gradlew
  detekt` y `env -u JAVA_HOME .harness/init.sh` → exit 0.
- **Offline confirmado**: `SearchServiceTest`/`SearchRouteTest` usan un
  `EmbeddingProvider` y un `FeedRepository` en memoria; los live se **omiten** sin
  `DB_LIVE_TEST`/`EMBEDDING_LIVE_TEST` (sin abrir sockets ni cargar el modelo).
- **Rutas (gate)**: `SearchRouteTest` con `testApplication` comprueba `200` (JSON con
  `q`/`resultados`), `400` por `q` ausente/en blanco, `categoria` inválida, fecha no
  ISO y `limite` inválido, y `404` cuando no se registra el servicio.
- **Servicio (gate)**: `SearchServiceTest` cubre filtro de categoría, rango de
  fechas, solo publicados, dedup/orden por relevancia, sin resultados y el recorte a
  `limit`.
- **Arranque sin BD/modelo**: `./gradlew :backend:run` sin `POSTGRES_PASSWORD` (o sin
  `EMBEDDING_MODEL_PATH`) → `/health` 200 y `/buscar` 404; con ambos, `/buscar`
  responde y el pool se comparte con el feed/la ingesta.
- **Escenario 8 (opt-in, fuera del gate y de la CI)**:
  ```sh
  cp .env.example .env && docker compose up -d
  ./gradlew :backend:flywayMigrate
  backend/tools/download-embedding-model.sh
  DB_LIVE_TEST=1 ./gradlew :backend:test --tests '*SearchPersistenceLiveTest'
  DB_LIVE_TEST=1 EMBEDDING_LIVE_TEST=1 ./gradlew :backend:test --tests '*SearchServiceLiveTest'
  docker compose down -v
  ```
  Esperado: solo se sirven publicados; la publicación relevante aparece primero y el
  filtro de categoría/fecha se respeta.
- **E2E**: no aplica — el repo no tiene comando E2E persistente (el cliente es
  Compose Multiplatform y aún no consume `:shared`); el flujo de API se cubre con
  `testApplication` en el gate.
- `init.sh` (harness): **no** se modifica.

## Evidence To Capture

- Salida de los tests nuevos (`:shared:jvmTest` y `:backend:test`) con recuento y 0
  fallos, y del gate (`build -PskipClient`, `test`, `detekt`, `init.sh` exit 0).
- Ejemplo real de respuesta `GET /buscar` (publicación con `resumen`, `categoria`,
  `urlOficial`, `plazo`) y de búsqueda sin resultados.
- Confirmación de que `Application.kt` arranca sin BD y sin modelo (`/health` 200,
  `/buscar` 404) y de que `HybridSearch`/`SearchFilter`/`SearchFilterSql`/
  migraciones quedan sin cambios de contrato.
- Salida de los tests opt-in (`SearchPersistenceLiveTest`, `SearchServiceLiveTest`).
- Ficheros del commit `FT00028`, PR y run de CI; entradas en `PROGRESS.md` y
  `feature_list.json` (`evidence`).

## Validator Checklist

- [ ] Alcance acotado: solo `:shared` (`SearchResultsDto`), `search/`,
      `persistence/FeedRepository` (aditivo), `plugins/Search`/`Routing` y el wiring
      de `Application.kt`; **sin** chat, **sin** CORS/rate limit/OpenAPI, **sin** UI,
      **sin** migración, **sin** dependencias Gradle nuevas.
- [ ] Escenarios 1–8 pasan; **todo el gate corre sin red, BD ni modelo** y los
      opt-in se omiten sin sus variables (con doble de `EmbeddingProvider`).
- [ ] La búsqueda sirve **solo** publicaciones con resumen `estado = 'publicado'`
      (token `SummaryState.PUBLISHED`); las no publicadas no aparecen.
- [ ] Cada resultado es el **mismo** `PublicacionDto` de `:shared` con `resumen`,
      `categoria` y `urlOficial`; se **reutiliza** `FeedDtoMapper` (sin DTO ni mapper
      nuevo por ítem).
- [ ] Se **reutilizan** `HybridSearch`/`SearchFilter`/`SearchFilterSql` sin
      modificarlos; no hay SQL ni mapeo duplicado; `FeedRepository` solo se amplía.
- [ ] Parámetros: `q` obligatoria; `categoria` como token de wire; `desde`/`hasta`
      ISO inclusivas; `limite` con default/máximo documentados; inválidos → 400; sin
      resultados → 200.
- [ ] El arranque **no** depende de la BD ni del modelo (rutas condicionales,
      `/health` operativo) y el pool y el proveedor se cierran una sola vez.
- [ ] La inferencia ONNX y la lectura JDBC van fuera del event loop
      (`Dispatchers.IO`); SQL parametrizado (sin concatenar entrada), sin secretos.
- [ ] `SearchResultsDto` con sufijo `Dto` y `@SerialName` explícito; `return` único,
      sin `else if`, funciones ≤40 líneas, KDoc en castellano con identificadores en
      inglés.
- [ ] `ARCHITECTURE.md`, `CONSTRAINTS.md`, ADR 0023 + índice, skills,
      `docs/desarrollo-local.md`, `PROGRESS.md` y `feature_list.json` actualizados.
- [ ] Sin comportamiento de producto no relacionado ni ficheros fuera de alcance.

## Risks / Open Questions

- **Wiring del proveedor de embeddings (ONNX) por primera vez.** Es la parte con más
  riesgo: construir `E5EmbeddingProvider` en el arranque carga el modelo (~118 MB,
  CPU) y consume memoria en el N100/8 GB. Mitigación: construcción **condicional**
  (captura `EmbeddingException` → `null`, `/buscar` 404) y cierre único. Si el
  orquestador lo prefiere, puede dividirse en `FT00028-PT1` (servicio + ruta con
  proveedor inyectado) y `FT00028-PT2` (wiring), pero el endpoint sería inútil sin
  PT2; se recomienda **atómica**.
- **Dependencia implícita de FT00023/FT00026.** La búsqueda sirve solo
  `estado='publicado'` (token de FT00023) y reutiliza `FeedDtoMapper`/`FeedRepository`
  (FT00026). El orquestador debe añadirlas a `depends_on`; ambas ya están en `main`.
- **Dedup con top-k heurístico.** `candidateLimit = limit * CANDIDATE_FACTOR` es una
  heurística: si un mismo documento copa los fragmentos, pueden devolverse menos de
  `limit` publicaciones. Se documenta; un `DISTINCT ON (publicacion_id)` en SQL
  quedaría como optimización futura (hoy no se toca el SQL de FT00017).
- **Sin snippet del fragmento.** El resultado no muestra el fragmento que casó; la
  tarjeta usa el `resumen` publicado (coherente con el feed). Añadir `referencia`/
  `fragmento` al DTO es una extensión posterior (no rompe el wire si se hace con
  defaults).
- **Índice vacío en runtime.** El indexado del corpus completo no existe (operación
  diferida): igual que el feed sin el pipeline de resumen, `/buscar` dará listas
  vacías hasta que exista ese indexado. Es un gap de planificación, no un fallo.
- **Conflicto con FT00027 (PR #28).** Ambos tocan `Routing.kt`/`Application.kt`; el
  cambio es aditivo (parámetro opcional) y el conflicto, trivial, lo resuelve el
  orquestador al mergear.
- **Tokens de wire.** Se usa `q` (consulta) y `desde`/`hasta` (fechas) en query
  string; la categoría llega como token `@SerialName` de `CategoriaDto` (snake_case),
  resuelta por el contrato de serialización. Alternativa considerada: `consulta` como
  nombre del parámetro (descartada por solaparse con la entidad de dominio
  `Consulta` del chat).
- **`limite` frente a paginación.** Se elige **top-k** (`limite`, default `10`, máx
  `50`) frente a `pagina`/`tamanoPagina` del feed porque la búsqueda es ANN y un
  `total`/paginación profunda no son significativos; decisión a registrar en el ADR
  0023.
- **`desde > hasta`.** No es error (200 con lista vacía); el `SearchFilterSql` es
  coherente. Alternativa: 400; se descarta para no añadir reglas que el dominio no
  exige.
- **División.** ≈14 ficheros: muy por debajo de 30 → **atómica**; no se recomienda
  partir en `FT00028-PTn`.
