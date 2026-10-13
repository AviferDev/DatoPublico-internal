# Feature Implementation Spec: Endpoint de chat RAG

## Source Feature

- `id`: api-chat
- `ft_id`: FT00031 (registrado en `docs/feature-ids.md`)
- `parts`: none (atómica; ≈18 ficheros de producto, por debajo del límite de 30)
- `area`: api-publica
- `depends_on`: chat-generacion (FT00025, `accepted`) — **más dependencias
  implícitas** que el orquestador debería añadir: `api-feed-diario` (FT00026,
  `accepted`) y `embeddings-locales-onnx` (FT00015, `accepted`). Ver
  *Dependencias implícitas* más abajo; `recuperacion-hibrida` (FT00017) y
  `generacion-resumen-go` (FT00020) quedan **cubiertos transitivamente** por
  FT00025.
- `status`: not_started (al planificar)
- `source`: `feature_list.json` (`notes`: `docs/roadmap.md` 0.5-T06)
- `claim`: rama `feat/ft00031-api-chat` ya reclamada en `origin`
  (`eed4c85 chore(FT00031): claim api-chat`), partiendo de `origin/main` (que ya
  incluye FT00025/FT00026/FT00027). **Nota de base**: `api-busqueda` (FT00028) está
  abierto en **PR #29 sin mergear**, así que su `search/SearchService`, su
  `plugins/Search.kt` y su cableado del proveedor de embeddings **no** están en esta
  base; los cambios en `Routing.kt`/`Application.kt` se hacen **aditivos y
  compatibles** (colaborador opcional extra) y **no** se reutiliza código de FT00028.

> **Dependencias implícitas.** FT00031 **reutiliza sin modificar** la librería
> `rag/chat` (FT00025) y su recuperación (`HybridSearch`/`SearchFilter`, FT00017,
> vía FT00025) y el proveedor de texto OpenCode (`TextGenerationProvider`/
> `OpenCodeConfig`, FT00020, vía FT00025). Además **cablea por primera vez** en el
> composition root el proveedor de embeddings (`E5EmbeddingProvider`/
> `EmbeddingConfig`, FT00015) y **reutiliza el pool JDBC único** y la firma
> `configureRouting(feedService, detailService)` que introdujo `api-feed-diario`
> (FT00026). El orquestador debería añadir `api-feed-diario` (FT00026) y
> `embeddings-locales-onnx` (FT00015) a `depends_on` (el planner **no** edita
> `feature_list.json`). `cola-revision-confianza` (FT00023) **no** es necesaria: la
> cita del chat apunta a la **publicación** del fragmento (su `urlOficial`), no al
> resumen publicado (ver *Technical Approach*).

## Goal

Exponer por HTTP, en `:backend`, el **chat RAG** del BOE (tarea `0.5-T06`): dada
una **consulta** o una **afirmación a verificar** en lenguaje natural, devolver una
**respuesta fundamentada** con los tres estados del dominio (`respondida`,
`refutada`, `sin_fundamento`) y las **citas a la fuente oficial** de las
publicaciones usadas.

La feature **cablea por primera vez** la librería `rag/chat` (FT00025) en el
composition root: introduce la capa de servicio de aplicación, el **primer
`CitationResolver` de producción** (sobre `PublicationRepository.findById`), el
contrato de transporte en `:shared` y el **wiring condicional** del proveedor de
texto OpenCode (fail-fast de `OPENCODE_API_KEY`) y del proveedor de embeddings
locales (ONNX), reutilizando el **pool JDBC único** existente. Sin BD, sin modelo o
sin clave, la ruta `/chat` **no** se registra (`404`) y el arranque no falla. No se
modifica `rag/chat` (FT00025): se consume tal cual.

## Non-Goals

- **Modificar `rag/chat`** (`RagChatService`, `ChatResult`/`ChatStatus`/
  `ChatCitation`, `ChatPromptBuilder`, `ChatOutputParser`, `ChatGroundingChecker`,
  `CitationResolver`): se **reutilizan** sin cambios.
- **Rate limiting, CORS, OpenAPI/versionado del path y cuerpo de error consistente**
  (FT00029/FT00030): la ruta responde `400`/`404`/`502`/`500` **sin cuerpo tipado**.
  La cláusula de FT00031 «respeta el rate limiting y devuelve errores consistentes»
  la entrega **FT00030** (ver *Risks*).
- **Filtros de la consulta** (categoría/fecha/sección/organismo): la recuperación del
  chat usa el `SearchFilter()` por defecto; los filtros son de `api-busqueda`
  (FT00028).
- **UI de chat** y textos visibles → FT00037 (`ui-chat`): aquí solo se produce el
  **contrato** (estados y citas) que la UI localizará.
- **Persistencia del historial** del chat en el servidor → fuera de alcance (sin
  cuentas ni historial; `CONSTRAINTS.md` §«Producto y datos»).
- **Exponer el consumo de tokens (`usage`) en el wire** ni cachear respuestas:
  el `usage` se propaga en `ChatResult` pero **no** viaja al cliente; el control de
  cuota/rate limiting es FT00030.
- **Cablear el pipeline de resumen** (FT00020–FT00023) o el **indexado del corpus**:
  gaps de planificación ya registrados (Sessions 068/070); la ruta se cablea, pero
  el corpus puede estar vacío en runtime.
- Cambiar `HybridSearch`/`SearchFilter`, `TextGenerationProvider`/
  `OpenCodeTextGenerationProvider`/`OpenCodeConfig`, `PublicationRepository`/
  `SummaryRepository`/`FeedRepository`, `rag/embeddings` ni migraciones
  (`V1`…`V5` intactas; **sin** migración nueva).

## Job Story

When hago una pregunta sobre el BOE o pego una afirmación para verificarla,
I want recibir, en una sola llamada HTTP, una respuesta **fundamentada solo en el
corpus** con el estado correcto (`respondida`/`refutada`/`sin_fundamento`) y las
**citas a la fuente oficial**,
so I can comprobar qué dice el BOE y saltar siempre al enlace oficial sin que se me
sirva una afirmación fuera del corpus.

## Users And Permissions

- **Ciudadanía (usuario final):** anónima, solo lectura; sin cuentas ni datos
  personales; el endpoint es público.
- **Cliente CMP (FT00037):** consumidor del contrato `:shared`; envía la consulta y
  renderiza la respuesta, su estado y sus citas.
- **Operador/desarrollador:** arranca el backend con PostgreSQL, el modelo E5 y
  `OPENCODE_API_KEY`, y ejecuta la prueba real **opt-in**.
- Sin autenticación, sin autorización y sin escritura; el chat **no** persiste
  historial.

## Acceptance Scenarios

### Scenario 1: pregunta respondida → 200 con cita a la fuente oficial

Given un corpus con fragmentos que sustentan la respuesta y un proveedor de texto
que devuelve `estado = "respondida"` con `citas = [0]`,
When `POST /chat` con `{"consulta": "<pregunta>"}`,
Then responde `200` con `ChatResponseDto`: `consulta` eco, `estado =
respondida`, `respuesta` no vacía y **≥1** `ChatCitationDto` con `urlOficial` de la
publicación del fragmento citado.

### Scenario 2: afirmación falsa refutada → 200 con citas

Given un corpus que contradice la afirmación y una salida del modelo con `estado =
"refutada"` y `citas` no vacías,
When se consulta,
Then responde `200` con `estado = refutada` y **≥1** cita a la fuente oficial.

### Scenario 3: consulta sin base → 200 sin fundamento (no es error)

Given un corpus que no permite confirmar ni refutar (o **cero** fragmentos
recuperados),
When se consulta,
Then responde `200` con `estado = sin_fundamento`, `respuesta` (mensaje del modelo
o de dominio) y `citas` **vacía**; el proveedor **no** se invoca si no hay contexto.

### Scenario 4: consulta inválida o cuerpo ilegible → 400

Given una petición sin `consulta`, con `consulta` en blanco, con `consulta` más
larga que `ChatService.MAX_QUERY_LENGTH` o con un cuerpo que no es
`ChatRequestDto` válido,
When se consulta,
Then responde `400` (sin cuerpo tipado; el contrato de error es FT00030).

### Scenario 5: arranque sin BD, sin modelo o sin clave → ruta no registrada

Given un entorno **sin** `POSTGRES_PASSWORD`, **sin** `EMBEDDING_MODEL_PATH`/
`EMBEDDING_TOKENIZER_PATH` (o sin el modelo en disco) o **sin** `OPENCODE_API_KEY`,
When arranca el backend,
Then `/health` responde `200`, la ruta `/chat` **no** se registra (`404`), el
arranque **no** falla y no se abre ninguna conexión. Con BD, modelo **y** clave,
`/chat` se registra sobre el **mismo pool** que el feed/el detalle/la ingesta; el
pool, el proveedor de embeddings y el cliente HTTP de OpenCode se cierran **una sola
vez** en `ApplicationStopped`.

### Scenario 6: fallo del proveedor o salida no interpretable → 5xx sin cuerpo tipado

Given que `RagChatService.answer` lanza `TextGenerationException` (fallo de
OpenCode) o `ChatGenerationException` (salida no parseable / índice fuera de rango),
When se consulta,
Then responde `502` (no se devuelve una respuesta a medias); un fallo de inferencia
local (`EmbeddingException`) responde `500` (sin cuerpo tipado; FT00030 unificará el
contrato).

### Scenario 7: el gate sigue sin red, BD, modelo ni OpenCode

Given el runner de CI sin PostgreSQL, sin Docker, sin el modelo E5 y sin
`OPENCODE_API_KEY`,
When se ejecuta `./gradlew build -PskipClient`, `./gradlew test`, `./gradlew detekt`
o `.harness/init.sh`,
Then todo está en verde; el `TextGenerationProvider`/`EmbeddingProvider` son
**dobles deterministas** en los tests y las pruebas reales se omiten sin sus
variables.

### Scenario 8: extremo a extremo real (opt-in)

Given `OPENCODE_LIVE_TEST=1` y `OPENCODE_API_KEY` definidos (con recuperación en
memoria, sin PostgreSQL ni ONNX),
When se ejecuta `ChatRouteLiveTest`,
Then `POST /chat` responde `200` con una respuesta fundamentada y **≥1** cita; sin
la clave, el test falla en claro (fail-fast).

### Scenario 9: resolución real de la cita (opt-in)

Given `DB_LIVE_TEST=1` y el PostgreSQL de `docker-compose` con `V1`…`V5`,
When `PublicationCitationResolverLiveTest` inserta una publicación y resuelve su
cita,
Then devuelve `ChatCitation(publicationId, titulo, urlOficial)`; un id inexistente
devuelve `null`.

## Repository Research

### Files Inspected

- Harness: `feature_list.json` (FT00031), `PROGRESS.md` (Sessions 066–070),
  `docs/feature-ids.md`, `docs/roadmap.md` §0.5 (`0.5-T06`), `CONTEXT.md`
  (§Consulta / chat RAG, §Verificación con fuentes externas), `docs/domain-model.md`
  (§Consulta: `recibida → respondida | refutada | sin_fundamento`; §Edge Cases),
  `DESIGN.md` (§Layout/§Components/§Core Screens: «Chat RAG», «Respuesta de chat» y
  estados), `docs/risks-and-open-questions.md` («Guardrails y umbral del chat RAG»,
  «Límites de uso y coste del chat», «Abuso del chat RAG»), `ARCHITECTURE.md`,
  `CONSTRAINTS.md` (§«API pública: feed diario»/«detalle»/«búsqueda», §«Chat RAG»,
  §«IA y coste», §«Nombres», §«Serialización»), ADR 0020/0021/0022, y los specs
  `chat-generacion.md` (FT00025), `api-feed-diario.md` (FT00026) y
  `api-busqueda.md` (FT00028); skills **`ktor-backend-architecture`** y
  **`rag-datapublico`** §5/§7.
- Producto `..` (rama `feat/ft00031-api-chat`, base `origin/main` = FT00025/26/27):
  - `backend/.../rag/chat/{RagChatService,ChatResult,CitationResolver,ChatPromptBuilder,ChatOutputDto,ChatOutputParser,ChatGroundingChecker}.kt`
    — **verificado**: `RagChatService.answer(query, filter, limit)` (`suspend`,
    `DEFAULT_LIMIT = 5`, `UNFOUNDED_MESSAGE`), `ChatResult.Answered`/`Refuted`/
    `Unfounded`, `ChatCitation(publicationId, title, officialUrl)`,
    `ChatStatus` (interno, no `@Serializable`), `ChatGenerationException`, y
    `CitationResolver` (`fun interface` **sin implementación de producción**). Se
    **reutilizan sin cambios**.
  - `backend/.../rag/generation/{TextGenerationProvider,OpenCodeConfig,OpenCodeTextGenerationProvider}.kt`
    — **verificado**: interfaz `suspend` + `GenerationRequest`/`GenerationResponse`/
    `TokenUsage`; `OpenCodeConfig` (**`internal`**, fail-fast de `OPENCODE_API_KEY`)
    y `OpenCodeTextGenerationProvider` (**constructor `internal`**) + factory
    `openCodeHttpClient()` (CIO + `ContentNegotiation` + `HttpTimeout`). Nunca se ha
    cableado en el arranque.
  - `backend/.../rag/embeddings/{EmbeddingProvider,E5EmbeddingProvider,EmbeddingConfig}.kt`
    — **verificado**: `E5EmbeddingProvider.from(modelPath, tokenizerPath, maxTokens)`
    (fail-fast, `AutoCloseable`) y `EmbeddingConfig.fromEnv()` (**`internal`**,
    fail-fast `EmbeddingException`). Nunca se ha cableado en el arranque.
  - `backend/.../persistence/{PublicationRepository,FeedRepository,FragmentRepository}.kt`
    — **verificado**: `PublicationRepository.findById(id): Publicacion?` (con
    `titulo`/`urlOficial`), `FeedRepositoryJdbc` (patrón de lectura JDBC) y
    `FragmentRepository`/`FragmentMatch`. `PublicationRepository` es la base del
    `CitationResolver` de producción; **no** se modifica.
  - `backend/.../ingesta/publicacion/Publicacion.kt` — **verificado**: `id`,
    `titulo`, `urlOficial` (la cita se deriva de aquí).
  - `backend/.../Application.kt` — **verificado**: composition root con **pool JDBC
    único** (`createDataSourceOrNull`, `feedServiceOf`, `detailServiceOf`,
    `monitorDataSource`, cierre en `ApplicationStopped`) y `configureRouting(
    feedService, detailService)`.
  - `backend/.../plugins/{Routing,Feed,PublicationDetail}.kt` — **verificado**:
    patrón `Route.xRoutes(dep)` + `configureRouting(...)` condicional (registra cada
    ruta solo si su servicio no es `null`); `FeedRequest.from` como valor interno de
    la capa HTTP.
  - `backend/.../rag/retrieval/{HybridSearch,SearchFilter}.kt` — **verificado**:
    `HybridSearch(embeddingProvider, fragmentRepository).search(query, filter,
    limit)`; se **reutiliza** vía `RagChatService`.
  - `backend/.../rag/review/SummaryState.kt` — **verificado** (`PUBLISHED =
    "publicado"`); **no** interviene en el chat (la cita no exige resumen publicado).
  - `shared/.../model/{PublicacionDto,ResumenDto,HighlightDto,HighlightReasonDto}.kt`
    — contrato de wire con sufijo `Dto` y `@SerialName` explícito; **no** existe aún
    ningún DTO de chat (lo define esta feature).
  - Tests: `backend/.../rag/chat/RagChatServiceTest.kt` (dobles
    `FakeTextGenerationProvider`/`FakeEmbeddingProvider`/`FakeFragmentRepository`),
    `RagChatServiceLiveTest.kt` (opt-in con fragmentos en memoria),
    `plugins/FeedRouteTest.kt`/`PublicationDetailRouteTest.kt` (`testApplication` con
    dobles) y `persistence/FeedPersistenceLiveTest.kt` (`DB_LIVE_TEST=1`). Patrones a
    seguir.
  - `backend/build.gradle.kts` — `:shared`, `ktor-server-test-host` y el plugin de
    serialización ya presentes; **sin dependencias nuevas**.
- Git: rama `feat/ft00031-api-chat` (claim `eed4c85`) en `origin`; **PR #29**
  (FT00028) abierto sin mergear sobre `main`.

### Existing Patterns To Follow

- **Ruta delgada en `plugins/`** (`Route.chatRoutes(service)`) + **servicio sin
  Ktor** (`chat/ChatService`) + **adaptador de repositorio** (`chat/PublicationCitationResolver`).
- **`configureRouting(...)` con colaboradores opcionales**: cada ruta se registra
  **solo** si su servicio no es `null`; el arranque no depende de servicios externos.
- **Trabajo bloqueante fuera del event loop**: la recuperación ONNX/JDBC y la
  resolución de citas JDBC se envuelven en `withContext(Dispatchers.IO)`.
- **DTOs de transporte** en `:shared` con sufijo `Dto`, `@SerialName` explícito y
  enums de wire con token `snake_case` (patrón `CategoriaDto`/`HighlightReasonDto`).
- **Wiring condicional con cierre único**: `createXOrNull()` captura el fallo de
  configuración (sin romper el arranque) y cierra los recursos una vez en
  `ApplicationStopped` (patrón FT00026/FT00028).
- **Tests del gate** con dobles deterministas y `testApplication`; pruebas reales
  **opt-in** (`OPENCODE_LIVE_TEST=1`, `DB_LIVE_TEST=1`).
- **Estilo MUST**: identificadores en inglés (KDoc en castellano), un solo `return`,
  sin `else if`, funciones ≤40 líneas, `@SerialName` explícito.

### Current Gaps

- No existe ningún endpoint de **chat** ni capa de servicio que componga
  `RagChatService` con la lectura de publicaciones.
- `CitationResolver` (FT00025) **no tiene implementación de producción**: la cita no
  se puede resolver todavía.
- `OpenCodeConfig`/`OpenCodeTextGenerationProvider` y `E5EmbeddingProvider` **nunca**
  se han cableado en el arranque.
- No hay contrato de transporte para la petición ni para la respuesta del chat.
- `configureRouting` solo admite `feedService`/`detailService`; el chat necesita un
  colaborador opcional **adicional**.

## Technical Approach

Deriva de `docs/roadmap.md` 0.5-T06 («consulta o afirmación a verificar contra el
BOE, con citas a la fuente»), `docs/domain-model.md` («Consulta: `recibida →
respondida | refutada | sin_fundamento`»), `CONTEXT.md` (§Consulta / chat RAG) y
`DESIGN.md` («Chat RAG: pregunta o afirmación, respuesta con citas y estados»).
El chat **no** se acota a una publicación (verifica contra todo el corpus) y sus
citas apuntan a la **publicación** del fragmento (su `urlOficial`), que puede no
tener un resumen publicado: la cita es **la fuente del corpus**, no un resumen
servido (diferencia deliberada respecto de feed/detalle/búsqueda).

### 1. Contrato de transporte (`:shared`, `model/`)

- **`ChatRequestDto` (create):** `@SerialName("consulta") val query: String` — la
  pregunta o afirmación a verificar.
- **`ChatResponseDto` (create):** `@SerialName("consulta") val query: String` (eco),
  `@SerialName("estado") val status: ChatStatusDto`,
  `@SerialName("respuesta") val answer: String`,
  `@SerialName("citas") val citations: List<ChatCitationDto> = emptyList()`.
- **`ChatStatusDto` (create):** enum de wire `@Serializable` con token `snake_case`
  (estilo `CategoriaDto`): `ANSWERED = respondida`, `REFUTED = refutada`,
  `UNFOUNDED = sin_fundamento`. Es el **wire** de `ChatStatus` (interno en FT00025).
- **`ChatCitationDto` (create):** `@SerialName("publicacionId")`,
  `@SerialName("titulo")`, `@SerialName("urlOficial")`.
- Sin `usage`: el consumo de tokens es interno (control de coste FT00030).
- **Sin** paginación/historial: una consulta → una respuesta.

### 2. Primer `CitationResolver` de producción (`chat/PublicationCitationResolver.kt`, create)

- `class PublicationCitationResolver(private val publicationRepository:
  PublicationRepository) : CitationResolver`.
- `override fun resolve(publicationId: String): ChatCitation? =
  publicationRepository.findById(publicationId)?.let { p -> ChatCitation(p.id,
  p.titulo, p.urlOficial) }` — la **fuente oficial se inyecta** desde la publicación
  (el modelo solo aporta índices). Una publicación no resoluble ⇒ `null` (el servicio
  descarta esa cita; no se inventa fuente).
- **No** revalida la URL con `OfficialSourceValidator`: la URL **no** la produce el
  modelo y `Publicacion.urlOficial` es la fuente de verdad ya persistida.
- JDBC **bloqueante**: se invoca dentro del `Dispatchers.IO` del servicio.
- Vive en `chat/` (no en `persistence/`) para no añadir a `persistence/` una
  dependencia hacia `rag/chat`; `chat/ → persistence` es la dirección natural.

### 3. Mapeo puro (`chat/ChatDtoMapper.kt`, create)

- `object ChatDtoMapper` (sin red/BD/Ktor):
  - `toResponseDto(query: String, result: ChatResult): ChatResponseDto`.
  - `toCitationDto(citation: ChatCitation): ChatCitationDto`.
  - `statusOf(result): ChatStatusDto` con un `when` exhaustivo (`Answered`→
    `ANSWERED`, `Refuted`→`REFUTED`, `Unfounded`→`UNFOUNDED`), sin `else if`.

### 4. Servicio de aplicación (`chat/ChatService.kt`, create)

- `class ChatService(private val ragChatService: RagChatService)`.
- `suspend fun ask(query: String): ChatResponseDto`:
  1. `require(query.isNotBlank())` y `require(query.length <= MAX_QUERY_LENGTH)`
     (fail-fast; la ruta traduce a `400`). Mirror de `DailyFeedService.feed`.
  2. `withContext(Dispatchers.IO) { ChatDtoMapper.toResponseDto(query,
     ragChatService.answer(query)) }` (recuperación ONNX/JDBC y citas JDBC fuera del
     event loop).
- **Contexto acotado**: se usa el `limit` por defecto de `RagChatService`
  (`DEFAULT_LIMIT = 5`, **no** controlable por el cliente) y el
  `ChatPromptBuilder` ya acota fragmentos y longitud; la consulta se acota con
  `MAX_QUERY_LENGTH` (constante documentada en el `companion object`). No hay
  historial ni caché; el `usage` no se expone.

### 5. Ruta (`plugins/Chat.kt`, create; `plugins/Routing.kt`, modify — aditivo)

- `fun Route.chatRoutes(service: ChatService)`: `POST /chat`.
  - Cuerpo JSON `ChatRequestDto` (`call.receiveNullable<ChatRequestDto>()`); un
    cuerpo ausente/ilegible o una `consulta` en blanco o más larga que
    `ChatService.MAX_QUERY_LENGTH` responden `400` (valor interno `ChatRequest.from`,
    mismo patrón que `FeedRequest`).
  - `call.respond(HttpStatusCode.OK, service.ask(query))`.
  - Traducción de errores **sin cuerpo tipado** (FT00030 unificará el contrato):
    `TextGenerationException`/`ChatGenerationException` ⇒ `502`; `EmbeddingException`
    ⇒ `500`; `CancellationException` se re-lanza.
- `configureRouting(feedService, detailService, chatService: ChatService? = null)`
  registra `/chat` **solo** si `chatService != null`. **Aditivo y compatible**: los
  llamantes existentes siguen compilando; si FT00028 (PR #29) ya está en la base, el
  parámetro `searchService` pasa a ser el tercero y `chatService` el cuarto
  (conflicto trivial, aditivo, a resolver por el orquestador).

### 6. Wiring (`Application.kt`, modify — aditivo)

- `createEmbeddingProviderOrNull()`: `E5EmbeddingProvider.from(EmbeddingConfig
  .fromEnv().modelPath, .tokenizerPath, .maxTokens)`; captura `Exception`
  (`EmbeddingException` incluida) → `log.warn` + `null` (rethrow de
  `CancellationException`). **El arranque no falla** si falta el modelo.
  **Nota**: si FT00028 ya está en la base, **reutilizar** su
  `createEmbeddingProviderOrNull`/cierre en vez de duplicarlos (conflicto aditivo).
- `createTextGenerationOrNull(): TextGenerationRuntime?`: `OpenCodeConfig.fromEnv()`
  (fail-fast de `OPENCODE_API_KEY`) + `openCodeHttpClient()` +
  `OpenCodeTextGenerationProvider(client, config)`; captura `TextGenerationException`
  → `log.warn` + `null`. Devuelve un pequeño `AutoCloseable` que cierra el
  `HttpClient` (la clave vive **solo** en el servidor y nunca se registra).
- `chatServiceOf(dataSource, embeddingProvider, textRuntime)`: `null` si falta
  cualquiera; si no, `ChatService(RagChatService(HybridSearch(embeddingProvider,
  FragmentRepositoryJdbc(dataSource)), textRuntime.provider,
  PublicationCitationResolver(PublicationRepositoryJdbc(dataSource))))`.
- `configureRouting(feedServiceOf(dataSource), detailServiceOf(dataSource),
  chatServiceOf(...))`; cerrar el pool, el proveedor de embeddings y el cliente HTTP
  **una sola vez** en `ApplicationStopped`.
- **Sin** cablear el pipeline de resumen ni el indexado del corpus (gaps de
  planificación; ver *Risks*).

### Sin anticipar lo diferido

Sin migración (`V1`…`V5` intactas), sin dependencias Gradle nuevas, sin
CORS/rate limiting/OpenAPI/cuerpo de error (FT00029/FT00030), sin UI (FT00037), sin
tocar `:composeApp`/CI/`init.sh`, sin modificar `rag/chat`, `rag/generation`,
`rag/embeddings`, `rag/retrieval`, `persistence/*` ni el job/backfill.

## Expected File Changes

Rutas en el repo de producto (`..`); `es/aviferdev/datopublico` se abrevia `…`:

- `shared/src/commonMain/kotlin/…/model/ChatRequestDto.kt` — create; consulta.
- `shared/src/commonMain/kotlin/…/model/ChatResponseDto.kt` — create; respuesta.
- `shared/src/commonMain/kotlin/…/model/ChatStatusDto.kt` — create; enum de wire.
- `shared/src/commonMain/kotlin/…/model/ChatCitationDto.kt` — create; cita.
- `shared/src/commonTest/kotlin/…/model/ChatContractTest.kt` — create; gate,
  round-trip y tokens `@SerialName`.
- `backend/src/main/kotlin/…/backend/chat/ChatService.kt` — create; servicio.
- `backend/src/main/kotlin/…/backend/chat/ChatDtoMapper.kt` — create; mapeo puro.
- `backend/src/main/kotlin/…/backend/chat/PublicationCitationResolver.kt` — create;
  primer `CitationResolver` de producción.
- `backend/src/main/kotlin/…/backend/plugins/Chat.kt` — create; `POST /chat`.
- `backend/src/main/kotlin/…/backend/plugins/Routing.kt` — modify; colaborador
  opcional.
- `backend/src/main/kotlin/…/backend/Application.kt` — modify; wiring condicional.
- `backend/src/test/kotlin/…/backend/chat/ChatServiceTest.kt` — create; gate.
- `backend/src/test/kotlin/…/backend/chat/ChatDtoMapperTest.kt` — create; gate puro.
- `backend/src/test/kotlin/…/backend/chat/PublicationCitationResolverTest.kt` —
  create; gate con repositorio en memoria.
- `backend/src/test/kotlin/…/backend/plugins/ChatRouteTest.kt` — create; gate,
  `testApplication` (200/400/404/502/500).
- `backend/src/test/kotlin/…/backend/chat/ChatRouteLiveTest.kt` — create; **opt-in**
  `OPENCODE_LIVE_TEST=1`.
- `backend/src/test/kotlin/…/backend/persistence/PublicationCitationResolverLiveTest.kt`
  — create; **opt-in** `DB_LIVE_TEST=1`.
- `docs/desarrollo-local.md` (producto) — modify; sección «Chat RAG (`POST /chat`)».

Harness (privado): `ARCHITECTURE.md`, `CONSTRAINTS.md`, ADR `0024` + índice,
skills `ktor-backend-architecture`/`rag-datapublico`, `PROGRESS.md`,
`feature_list.json` (ver *Durable Documentation Impact*).

Total ≈ **18 ficheros de producto/código** + docs: por debajo del límite de 30 →
**no** requiere división en partes `FT00031-PTn`.

## Rename Mapping

No aplica: la feature es **código nuevo** con identificadores en **inglés** y KDoc
en castellano. Los tokens de wire del estado (`respondida`/`refutada`/
`sin_fundamento`) son **datos de dominio** y se conservan tal cual.

## Visual Design Impact

- UI involved: no. Sin pantallas, tokens ni textos.
- Design source: `DESIGN.md` §Layout/§Components/§Core Screens («Chat RAG»,
  «Respuesta de chat: texto + lista de citas, con estado "sin fundamento"/"refutada"
  claramente señalado» y §Estados). Aquí solo se produce el **contrato** (los tres
  estados y las citas) que la UI de chat (FT00037) localizará.
- Screens or states affected: ninguno (el contrato cubre `respondida`/`refutada`/
  `sin_fundamento`).
- New design artifact required: no.

## Durable Documentation Impact

- `ARCHITECTURE.md`: **update** — `:shared` gana los DTOs del chat; `:backend` gana
  `chat/` (`ChatService`, `ChatDtoMapper`, `PublicationCitationResolver`) y
  `plugins/Chat.kt`; la frontera «Cliente → API HTTP» incorpora el **chat RAG** y la
  frontera «Backend → OpenCode» queda **cableada** por primera vez (también para
  chat); el composition root cablea de forma condicional el proveedor de embeddings
  y el proveedor de texto sobre el pool único.
- `CONSTRAINTS.md`: **update** — nueva sección **«API pública: chat RAG»**: solo
  lectura y público; responde **solo** con el contexto recuperado y **cita la fuente
  oficial** (la URL la **inyecta** el `CitationResolver` desde la publicación, nunca
  el modelo); `respondida`/`refutada` exigen ≥1 cita; `sin_fundamento` no lleva citas
  y no es error; contexto vacío **no** invoca al proveedor; el arranque no depende de
  la BD/modelo/clave (ruta condicional, `/health` operativo) y los recursos se
  cierran una sola vez; parámetros inválidos ⇒ `400` sin cuerpo tipado; sin
  CORS/rate limiting/OpenAPI (FT00029/FT00030), sin UI (FT00037), sin persistir
  historial, sin migración; pruebas reales **opt-in**.
- `AGENTS.md`: **not needed** — no cambia el flujo, el arranque ni las reglas.
- Other docs: `docs/adr/0024-api-chat-endpoint.md` — **create** (decisión durable:
  endpoint de chat RAG sobre la librería FT00025, primer `CitationResolver` de
  producción, wiring condicional de OpenCode + embeddings sobre el pool único, sin
  persistir historial, errores sin cuerpo tipado) + índice `docs/adr/README.md`;
  `.agents/skills/ktor-backend-architecture/SKILL.md` — **update** (§Estado actual y
  §API: `/chat`); `.agents/skills/rag-datapublico/SKILL.md` — **update** §5/§7 (el
  chat se cablea en la API); `docs/desarrollo-local.md` — **update**.

## Implementation Plan

1. Definir el contrato en `:shared` (`ChatStatusDto`, `ChatCitationDto`,
   `ChatRequestDto`, `ChatResponseDto`) con `@SerialName` explícito y su test de gate.
2. Crear `PublicationCitationResolver` (sobre `PublicationRepository.findById`) con
   su test de gate.
3. Crear `ChatDtoMapper` (puro) y `ChatService` (`suspend`, `Dispatchers.IO`,
   `MAX_QUERY_LENGTH`) con sus tests de gate con dobles.
4. Crear `plugins/Chat.kt` (`POST /chat`, validación, `400`/`200`, errores
   `502`/`500`) y `ChatRouteTest` (`testApplication`).
5. Modificar `Routing.kt` (colaborador opcional) y `Application.kt` (proveedor de
   embeddings + proveedor de texto condicionales + cierre único); verificar `/health`
   sin BD/modelo/clave y el arranque con todos.
6. Añadir `ChatRouteLiveTest` (`OPENCODE_LIVE_TEST=1`) y
   `PublicationCitationResolverLiveTest` (`DB_LIVE_TEST=1`).
7. Pasar el gate sin red, BD, modelo ni OpenCode y actualizar `ARCHITECTURE.md`,
   `CONSTRAINTS.md`, ADR 0024 + índice, skills y `docs/desarrollo-local.md`;
   `PROGRESS.md`/`feature_list.json` los cierra el orquestador.

## Implementation Tasks

- [ ] `:shared`: `ChatRequestDto`, `ChatResponseDto`, `ChatStatusDto`,
      `ChatCitationDto` + `ChatContractTest`.
- [ ] `chat/PublicationCitationResolver` (primer `CitationResolver` de producción,
      `PublicationRepository.findById`).
- [ ] `chat/ChatDtoMapper` (puro: `ChatResult` → `ChatResponseDto`, estados y citas).
- [ ] `chat/ChatService` (`suspend`, `Dispatchers.IO`, `MAX_QUERY_LENGTH`, contexto
      acotado al `limit` por defecto).
- [ ] `plugins/Chat.kt` (`POST /chat`, `receiveNullable`, `400`/`200`, `502`/`500`) +
      `plugins/Routing.kt` (colaborador opcional).
- [ ] `Application.kt`: `createEmbeddingProviderOrNull` + `createTextGenerationOrNull`
      + `chatServiceOf` + cierre único; rutas condicionales.
- [ ] Tests de gate: contrato de `:shared`, resolver, mapper, servicio y ruta
      (200/400/404/502/500).
- [ ] Live opt-in: `ChatRouteLiveTest` (`OPENCODE_LIVE_TEST=1`) y
      `PublicationCitationResolverLiveTest` (`DB_LIVE_TEST=1`).
- [ ] Docs: `ARCHITECTURE.md`, `CONSTRAINTS.md`, ADR 0024 + índice, skills y
      `docs/desarrollo-local.md`.

## Verification Plan

Desde la raíz del producto (`..`, JDK 21 vía JBR/`JAVA_HOME`):

- **Gate sin red, BD, modelo ni OpenCode (obligatorio)**: `./gradlew :backend:test
  --rerun-tasks` y `./gradlew :shared:jvmTest` → BUILD SUCCESSFUL con los tests
  nuevos en verde (0 fallos) y el resto intacto; `./gradlew build --no-daemon
  -PskipClient` (incluye `detekt` + `:cpdCheck`), `./gradlew test`, `./gradlew
  detekt` y `env -u JAVA_HOME .harness/init.sh` → exit 0.
- **Offline confirmado**: `ChatServiceTest`/`ChatRouteTest` usan un
  `TextGenerationProvider` y un `EmbeddingProvider` dobles y un `CitationResolver`
  fake; los live se **omiten** sin `OPENCODE_LIVE_TEST`/`DB_LIVE_TEST` (sin abrir
  sockets ni cargar el modelo).
- **Rutas (gate)**: `ChatRouteTest` con `testApplication` comprueba `200` (JSON con
  `consulta`/`estado`/`respuesta`/`citas`), `200` con `estado = sin_fundamento` y
  `citas` vacía, `400` por consulta ausente/en blanco/desmesurada o cuerpo ilegible,
  `404` cuando no se registra el servicio, y `502`/`500` por fallo tipado.
- **Servicio (gate)**: `ChatServiceTest` cubre respondida/refutada/sin fundamento,
  cita con `urlOficial`, contexto vacío sin invocar al proveedor y `require` de la
  consulta.
- **Arranque sin BD/modelo/clave**: `./gradlew :backend:run` sin
  `POSTGRES_PASSWORD` (o sin `EMBEDDING_MODEL_PATH`, o sin `OPENCODE_API_KEY`) →
  `/health` 200 y `/chat` 404; con los tres, `/chat` responde y el pool/proveedores
  se comparten y se cierran una sola vez.
- **Escenarios 8–9 (opt-in, fuera del gate y de la CI)**:
  ```sh
  OPENCODE_LIVE_TEST=1 OPENCODE_API_KEY=<clave> \
    ./gradlew :backend:test --tests '*ChatRouteLiveTest'
  cp .env.example .env && docker compose up -d
  ./gradlew :backend:flywayMigrate
  DB_LIVE_TEST=1 ./gradlew :backend:test --tests '*PublicationCitationResolverLiveTest'
  docker compose down -v
  ```
  Esperado: `POST /chat` responde con cita a la fuente; el resolver devuelve la cita
  de una publicación real y `null` para un id inexistente.
- **E2E**: no aplica — el repo no tiene comando E2E persistente (el cliente es
  Compose Multiplatform y aún no consume `:shared`); el flujo de API se cubre con
  `testApplication` en el gate.
- `init.sh` (harness): **no** se modifica.

## Evidence To Capture

- Salida de los tests nuevos (`:shared:jvmTest` y `:backend:test`) con recuento y 0
  fallos, y del gate (`build -PskipClient`, `test`, `detekt`, `init.sh` exit 0).
- Ejemplo real de `POST /chat` con `estado = respondida` y ≥1 cita con `urlOficial`,
  de `refutada` y de `sin_fundamento` (citas vacías).
- Confirmación de que `Application.kt` arranca sin BD/modelo/clave (`/health` 200,
  `/chat` 404) y de que `rag/chat`, `rag/generation`, `rag/embeddings`,
  `rag/retrieval`, `persistence/*` y las migraciones quedan sin cambios de contrato.
- Salida de los tests opt-in (`ChatRouteLiveTest`, `PublicationCitationResolverLiveTest`).
- Ficheros del commit `FT00031`, PR y run de CI; entradas en `PROGRESS.md` y
  `feature_list.json` (`evidence`).

## Validator Checklist

- [ ] Alcance acotado: solo `:shared` (DTOs del chat), `chat/`, `plugins/Chat`/
      `Routing` y el wiring de `Application.kt`; **sin** modificar `rag/chat`,
      **sin** rate limiting/CORS/OpenAPI, **sin** UI, **sin** historial, **sin**
      migración, **sin** dependencias Gradle nuevas.
- [ ] Escenarios 1–9 pasan; **todo el gate corre sin red, BD, modelo ni OpenCode** y
      los opt-in se omiten sin sus variables (con dobles deterministas).
- [ ] Se **reutiliza** `RagChatService`/`ChatResult`/`CitationResolver` (FT00025) sin
      modificarlos; el **primer `CitationResolver` de producción** se implementa
      sobre `PublicationRepository.findById` y la URL la **inyecta** desde la
      publicación (el modelo solo aporta índices).
- [ ] El wire refleja los tres estados (`respondida`/`refutada`/`sin_fundamento`);
      `sin_fundamento` **no** es error (200) y lleva `citas` vacía; `respondida`/
      `refutada` llevan ≥1 cita con `urlOficial`.
- [ ] Parámetros: `consulta` obligatoria, no vacía y con máximo documentado; cuerpo
      ilegible ⇒ `400`; `404` si la ruta no se registra; fallos tipados ⇒ `502`/`500`
      sin cuerpo tipado (FT00030 unificará el contrato).
- [ ] El arranque **no** depende de la BD, el modelo ni la clave (rutas
      condicionales, `/health` operativo) y el pool, el proveedor de embeddings y el
      cliente HTTP se cierran una sola vez.
- [ ] La recuperación ONNX/JDBC y la resolución de citas van fuera del event loop
      (`Dispatchers.IO`); la clave de OpenCode vive **solo** en el servidor y no se
      registra; SQL parametrizado.
- [ ] DTOs `Dto` con `@SerialName` explícito y tokens de wire estables; `return`
      único, sin `else if`, funciones ≤40 líneas, KDoc en castellano con
      identificadores en inglés.
- [ ] `ARCHITECTURE.md`, `CONSTRAINTS.md`, ADR 0024 + índice, skills,
      `docs/desarrollo-local.md`, `PROGRESS.md` y `feature_list.json` actualizados.
- [ ] Sin comportamiento de producto no relacionado ni ficheros fuera de alcance.

## Risks / Open Questions

- **Rate limiting y errores consistentes son FT00030.** La `verification` de FT00031
  menciona «respeta el rate limiting y devuelve errores consistentes», pero
  `api-cors-ratelimit-errores` (FT00030) **depende** de `api-chat` (FT00031): esas
  dos cláusulas las entrega FT00030, no esta feature. El orquestador debería
  ajustar la `verification` de FT00031 (o anotar que se validan con FT00030); el
  planner **no** edita `feature_list.json`.
- **Solapamiento con FT00028 (PR #29).** FT00028 también cablea el proveedor de
  embeddings (`createEmbeddingProviderOrNull`) y toca `Routing.kt`/`Application.kt`.
  FT00031 lo hace **aditivo y compatible** sin reutilizar su código (no está en la
  base); si FT00028 se mergea antes, reutilizar su helper/cierre en vez de duplicarlo
  (conflicto trivial, a resolver por el orquestador).
- **`CitationResolver` de producción: hasta `limit` consultas por consulta.** El
  `fun interface` resuelve por `publicationId`; el servicio hace hasta `DEFAULT_LIMIT`
  (= 5) `findById` por PK. Es despreciable en el N100; un método por lote sería una
  extensión posterior de `PublicationRepository` (no de esta feature).
- **La cita no exige resumen publicado.** A diferencia de feed/detalle/búsqueda, la
  cita apunta a la **publicación** del fragmento (su `urlOficial`), exista o no un
  resumen `publicado`; es coherente con verificar contra el **corpus**, no contra el
  feed. `cola-revision-confianza` (FT00023) **no** es dependencia.
- **Corpus vacío en runtime.** El pipeline de resumen (FT00020–FT00023) y el
  indexado del corpus siguen **sin cablear** (gaps de las Sessions 068/070): con el
  endpoint cableado, `/chat` devolverá `sin_fundamento` (índice vacío) hasta que
  existan esos cableados. Es un gap de planificación, no un fallo de esta feature.
- **Abuso y coste.** El chat es más caro por consulta que el feed; sin rate limiting
  (FT00030) el endpoint público es vulnerable a abuso. Mitigación parcial en esta
  feature: contexto acotado (limit fijo + `MAX_QUERY_LENGTH` + topes del prompt), sin
  historial y `usage` no expuesto. El control de cuota/rate limiting es FT00030.
- **Grounding léxico conservador.** Una paráfrasis válida puede degradar a
  `sin_fundamento` (falso negativo, fail-safe); el umbral (`MIN_CLAIM_SUPPORT = 0.6`)
  es una constante ajustable de FT00022.
- **No determinismo del modelo.** La respuesta real depende de OpenCode y no es
  reproducible; el gate usa dobles y las pruebas reales son opt-in.
- **`consulta` larga.** Se acota con `MAX_QUERY_LENGTH` para no inflar el prompt ni
  el coste; el límite se documenta y es ajustable.
- **Path sin versión.** Se usa `/chat` (coherente con `/feed`, `/publicacion/{id}`,
  `/buscar`); el versionado/OpenAPI del path es FT00029.
- **Método del endpoint.** Se elige `POST /chat` con cuerpo `ChatRequestDto` (la
  consulta/afirmación puede ser un párrafo largo; es una operación de cómputo no
  cacheable; un preflight CORS —FT00030— se dispara con POST+JSON). Alternativa
  considerada: `GET /chat?q=…` (descartada por longitud y cacheabilidad).
- **División.** ≈18 ficheros: muy por debajo de 30 → **atómica**; no se recomienda
  partir en `FT00031-PTn`.
