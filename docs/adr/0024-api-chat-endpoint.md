# ADR 0024: Endpoint de chat RAG sobre la librería FT00025, primer `CitationResolver` de producción y wiring condicional de OpenCode + embeddings sobre el pool único

## Estado

Aceptado (2026-10-13). Decisión del dueño del proyecto para FT00031 (`api-chat`).
Reutiliza los ADR 0020 (chat RAG como librería), 0021 (feed y pool único), 0023
(wiring condicional del proveedor de embeddings) y 0015 (proveedor de texto
intercambiable); no supersede ninguno.

## Contexto

FT00025 dejó el **chat RAG** como **librería sin wiring** (`rag/chat/`:
`RagChatService`, `ChatResult`/`ChatStatus`/`ChatCitation`, `CitationResolver`), con
grounding léxico y citas inyectadas, pero **sin** implementación de producción del
`CitationResolver`, sin contrato de transporte y sin consumidor de runtime. FT00031
es la tarea `0.5-T06`: exponer por HTTP, en `:backend`, el chat del BOE —dada una
pregunta o una afirmación, responder solo con el corpus y citar la fuente oficial—
y **cablear por primera vez** en el composition root el proveedor de texto de
OpenCode (fail-fast de `OPENCODE_API_KEY`) y el proveedor de embeddings locales
(ONNX), reutilizando el **pool JDBC único** de FT00026.

Restricciones: el gate y la CI corren **sin red, sin base de datos, sin el modelo
E5 y sin `OPENCODE_API_KEY`**; el arranque debe funcionar en entornos parciales
(solo salud) y registrar **solo** las rutas cuyas dependencias existen; la
generación real depende de OpenCode y **no** es determinista (no puede ser la unidad
verificable del gate); PostgreSQL + pgvector con JDBC + HikariCP **sin ORM** (ADR
0003); todo el código en inglés con KDoc en castellano, un solo `return`, sin
`else if` y funciones ≤40 líneas; el contrato de error tipado y el rate limiting son
FT00030 (no de esta feature).

## Decisión

- **El chat es un endpoint de solo lectura y público** (`POST /chat`, coherente con
  `/feed` y `/publicacion/{id}`). Se elige `POST` con cuerpo `ChatRequestDto`
  (`{"consulta":"…"}`) porque la consulta/afirmación puede ser un párrafo largo, es
  una operación de cómputo **no cacheable** y un preflight CORS (FT00030) se
  dispara con `POST`+JSON. No hay autenticación, historial ni escritura.
- **Se reutiliza `rag/chat` (FT00025) sin modificarlo**: `ChatService`
  (`suspend`, `Dispatchers.IO`) envuelve `RagChatService.answer` y mapea su
  `ChatResult` a `ChatResponseDto` con `ChatDtoMapper` (puro). El **contexto se
  acota** al `limit` por defecto de `RagChatService` (`DEFAULT_LIMIT = 5`, no
  controlable por el cliente) y la consulta con `MAX_QUERY_LENGTH` (= 1000,
  constante documentada). **No** se expone el `usage` (control de coste interno).
- **Primer `CitationResolver` de producción.** `PublicationCitationResolver` adapta
  `PublicationRepository.findById` al `fun interface` de FT00025:
  `ChatCitation(id, titulo, urlOficial)`. La **fuente oficial se inyecta** desde la
  publicación (el modelo solo aporta **índices** de fragmento); una publicación no
  resoluble **descarta** la cita y no se inventa una fuente. **No** se revalida la
  URL con `OfficialSourceValidator`: la URL no la produce el modelo y
  `Publicacion.urlOficial` ya es la fuente de verdad persistida. Vive en `chat/`
  (no en `persistence/`) para no añadir a `persistence/` una dependencia hacia
  `rag/chat`.
- **Contrato de transporte en `:shared`** (`model/`), con sufijo `Dto` y
  `@SerialName` explícito: `ChatRequestDto` (`consulta`), `ChatResponseDto`
  (`consulta` eco, `estado`, `respuesta`, `citas`), `ChatStatusDto` (enum de wire
  `snake_case`: `respondida`/`refutada`/`sin_fundamento`) y `ChatCitationDto`
  (`publicacionId`/`titulo`/`urlOficial`). `sin_fundamento` **no** es error y lleva
  `citas` vacía; `respondida`/`refutada` llevan **≥1** cita. **Sin** `usage`, sin
  paginación y sin historial.
- **Errores sin cuerpo tipado** (FT00030 unificará el contrato): un cuerpo ausente
  o ilegible, una `consulta` en blanco o más larga que `MAX_QUERY_LENGTH` responden
  `400`; un fallo del proveedor (`TextGenerationException`) o una salida no
  interpretable (`ChatGenerationException`) responden `502` (no se devuelve una
  respuesta a medias); un fallo de la inferencia local (`EmbeddingException`)
  responde `500`. `CancellationException` se re-lanza.
- **Wiring condicional y cierre único.** El composition root construye el proveedor
  de embeddings (`E5EmbeddingProvider`/`EmbeddingConfig.fromEnv()`) y el runtime de
  texto de OpenCode (`OpenCodeConfig.fromEnv()` + `openCodeHttpClient()` +
  `OpenCodeTextGenerationProvider`) **capturando su fail-fast** (sin modelo o sin
  clave ⇒ aviso + `null`, sin romper el arranque). `chatServiceOf(dataSource,
  embeddingProvider, textRuntime)` devuelve `null` si falta cualquiera de los tres;
  `configureRouting` registra `/chat` **solo** si el servicio no es `null`. Sin BD,
  modelo o clave, `/chat` es `404` y `/health` sigue `200`. El pool, el proveedor de
  embeddings y el cliente HTTP de OpenCode se cierran **una sola vez** en
  `ApplicationStopped`. El parámetro `chatService` de `configureRouting` es
  **aditivo y compatible** (default `null`).
- **La clave vive solo en el servidor** (`OPENCODE_API_KEY`) y nunca se registra;
  la recuperación ONNX/JDBC y la resolución de citas JDBC van fuera del event loop
  (`Dispatchers.IO`); el SQL está parametrizado.

## Alternativas consideradas

- **Que el endpoint devuelva también el `usage`/las puntuaciones de grounding.**
  Descartado: el consumo de tokens es interno (control de coste FT00030) y la UI no
  lo necesita; el contrato queda mínimo.
- **`GET /chat?q=…`.** Descartado por la longitud de la consulta y la
  cacheabilidad; `POST`+JSON es coherente con una operación de cómputo.
- **Definir el contrato del chat en `:backend`.** Descartado: el cliente CMP
  (FT00037) lo consume desde `:shared`, como el resto del contrato.
- **Exponer los estados con el nombre del enum Kotlin.** Descartado: se usan tokens
  de wire `snake_case` (`CategoriaDto`/`HighlightReasonDto`) estables y localizables.
- **Revalidar la `urlOficial` con `OfficialSourceValidator`.** Descartado: la URL
  no la produce el modelo y es la fuente de verdad ya persistida; revalidarla sería
  redundante.
- **Registrar `/chat` siempre (fail-fast del arranque sin modelo/clave).**
  Descartado: rompería el arranque en entornos parciales; el patrón es ruta
  condicional y `/health` operativo.
- **Cablear el pipeline de resumen y el indexado del corpus.** Descartado: son
  gaps de planificación (Sessions 068/070) fuera del alcance; con el corpus vacío
  `/chat` devuelve `sin_fundamento` hasta que existan esos cableados.
- **Persistir el historial del chat o cachear respuestas.** Descartado: sin cuentas
  ni historial (`CONSTRAINTS.md` §«Producto y datos»); la caché/rate limiting son
  FT00030.

## Consecuencias

- **Habilita** el chat de verificación del BOE por HTTP con trazabilidad a la
  fuente: la UI de chat (FT00037) ya tiene contrato (estados y citas) y el backend
  comparte el pool único con el feed/el detalle/la ingesta.
- **Cuesta** que el endpoint sea **más caro** por consulta que el feed: sin rate
  limiting (FT00030) el endpoint público es vulnerable a abuso; la mitigación de
  esta feature es el contexto acotado (limit fijo + `MAX_QUERY_LENGTH` + topes del
  prompt), la ausencia de historial y el `usage` no expuesto.
- **Corpus vacío en runtime**: el pipeline de resumen (FT00020–FT00023) y el
  indexado del corpus siguen **sin cablear**; con el endpoint cableado, `/chat`
  devolverá `sin_fundamento` (índice vacío) hasta que existan esos cableados. Es un
  gap de planificación, no un fallo de la feature.
- **Solapamiento con FT00028 (PR #29).** FT00028 también cablea el proveedor de
  embeddings y toca `Routing.kt`/`Application.kt`; FT00031 lo hace **aditivo y
  compatible** sin reutilizar su código (no estaba en la base). Si FT00028 se mergea
  antes, se **reutiliza** su helper/cierre en vez de duplicarlo.
- **Sin migración** (`V1`…`V5` intactas), sin dependencias Gradle nuevas, sin CORS,
  *rate limiting*, OpenAPI ni cuerpo de error tipado (FT00029/FT00030) y sin UI
  (FT00037).
- **Documentación/código**: `ARCHITECTURE.md`, `CONSTRAINTS.md` §«API pública: chat
  RAG», las skills `ktor-backend-architecture`/`rag-datapublico`,
  `docs/desarrollo-local.md` (producto) y este ADR.
- **Verificación**: `ChatContractTest` (`:shared`), `ChatDtoMapperTest`,
  `PublicationCitationResolverTest`, `ChatServiceTest` y `ChatRouteTest`
  (`testApplication`, `200`/`400`/`404`/`502`/`500`) en el gate con dobles
  deterministas, sin red/BD/modelo/OpenCode; `ChatRouteLiveTest`
  (`OPENCODE_LIVE_TEST=1`) y `PublicationCitationResolverLiveTest`
  (`DB_LIVE_TEST=1`) son **opt-in**.
