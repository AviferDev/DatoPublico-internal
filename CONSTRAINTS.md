# Constraints — DatoPublico

> Reglas operativas **MUST / MUST NOT** que toda feature debe respetar. Añade
> aquí solo restricciones durables que futuras features deban cumplir.

## Producto y datos

- **MUST**: cada resumen publicado lleva enlace visible a la **fuente oficial**.
- **MUST NOT**: cuentas de usuario ni almacenamiento de datos personales **de
  quien usa la app** (nada de perfiles); el contenido del BOE es información
  pública y **nunca se restringe**.
- **MUST NOT**: analítica o telemetría de uso.
- **MUST**: el chat verifica **solo** contra el corpus del BOE (sin fuentes
  externas) y **no** persiste historial en el servidor.
- **MUST**: el aviso de contenido generado por IA es visible.
- **MUST**: el corpus de la 1.0.0 es **todo el sumario del BOE** (secciones I,
  II.A, II.B, III, IV, V.A, V.B y V.C) y se usan **todos los campos** que ofrece
  la API. Ninguna sección ni campo del BOE se excluye por «datos personales» ese
  principio aplica solo a los datos de los usuarios de la app.

## Fuentes externas (ingesta)

- **MUST**: el contenido remoto del BOE se trata como **no confiable**. El XML
  estructurado (`xml.php`) se parsea con *secure processing* del parser del JDK y
  con **DTD y entidades externas deshabilitadas** (`disallow-doctype-decl`,
  `ACCESS_EXTERNAL_DTD`/`ACCESS_EXTERNAL_SCHEMA` vacíos, sin expandir
  referencias), para evitar XXE y *billion laughs*.
- **MUST**: la descarga del texto oficial es una **llamada de red** y queda sujeta
  a la regla de tests opt-in (`BOE_LIVE_TEST=1`) de la sección «Operación»;
  nunca se ejecuta en el gate ni en la CI.
- **MUST**: las **llamadas de red del backend** fijan un `HttpTimeout` explícito
  (conexión ~10 s, petición/socket ~30 s) para que una descarga colgada del BOE no
  bloquee indefinidamente la ventana del job (FT00009).

## IA y coste

- **MUST**: embeddings **locales** (`multilingual-e5-small` int8, ONNX), tras una
  interfaz de proveedor.
- **MUST**: generación y chat por **OpenCode**, tras una interfaz intercambiable;
  la clave vive **solo** en el servidor.
- **MUST**: cachear resúmenes por publicación y aplicar **rate limiting** al chat.
- **MUST NOT**: publicar afirmaciones fuera del contexto recuperado (si el corpus
  no lo sustenta, se declara `sin_fundamento`/`refutada`).

## Contrato del resumen ciudadano

- **MUST**: todo resumen ciudadano cumple el **contrato** validado en `:shared`
  (`validation/CitizenSummaryValidator`, FT00019): **fuente oficial obligatoria**
  como enlace absoluto `http(s)://`, «¿Qué cambia?» y «¿A quién afecta?» no vacíos
  y «Cifras clave» sin entradas en blanco (la lista **puede** estar vacía). Decisión
  durable en `docs/adr/0014`.
- **MUST**: la **variante** de empleo público y becas
  (`OPOSICIONES_Y_EMPLEO_PUBLICO`, `BECAS_SUBVENCIONES_Y_AYUDAS`) exige **plazo**
  con `fechaLimite` no vacía; el resto de categorías no lo exigen. La variante es un
  **valor interno** (sin `Dto`, no `@Serializable`).
- **MUST**: el validador del contrato es **puro** (sin red, BD, reloj ni estado),
  **acumula violaciones y no lanza**: un resumen inválido es un resultado esperado
  (lo consumirán FT00022/FT00023), no un error de programación. Se distingue del
  *fail-fast* de configuración (`PgVector`, `SearchFilterSql`), que sí son errores
  de programación.
- **MUST NOT**: este validador comprueba solo el **contrato** (estructura y
  presencia de la fuente), **no la veracidad**: la **alcanzabilidad** del enlace y
  las afirmaciones fuera del contexto recuperado son **guardrails de contenido**
  (FT00022). Tampoco cambia el **contrato de wire** de `ResumenDto` (congelado).

## Generación de resumen ciudadano

- **MUST**: el **proveedor de texto** va tras una **interfaz intercambiable**
  (`rag/generation/TextGenerationProvider`, `suspend`); OpenCode la implementa
  (`OpenCodeTextGenerationProvider`) y es la **única** pieza que conoce Ktor/HTTP.
  La **clave** vive **solo en el servidor** (`OPENCODE_API_KEY` por entorno; nunca
  versionada ni en logs) y su ausencia es **fail-fast** (`TextGenerationException`).
  Decisión durable en `docs/adr/0015`.
- **MUST**: la **fuente oficial se inyecta** de forma determinista desde
  `Publicacion.urlOficial` (`SummaryGenerationDto.toResumenDto`) y `avisoIA = true`;
  **nunca** la produce el modelo. La salida del modelo solo aporta «¿Qué cambia?»,
  «¿A quién afecta?», «Cifras clave» y, si procede, el plazo.
- **MUST**: la salida se **valida** con `CitizenSummaryValidator` (FT00019); un
  resumen que no cumple el contrato **no se publica**: el servicio devuelve
  `CitizenSummaryResult.Invalid` con las violaciones (resultado tipado, **no** una
  excepción). Una salida **no parseable** (vacía o JSON inválido) es un fallo
  distinto: lanza `SummaryGenerationException` tipada.
- **MUST**: el prompt trabaja **solo** con el contexto recuperado y lo delimita
  como **datos, no instrucciones**; la variante de empleo/beca
  (`OPOSICIONES_Y_EMPLEO_PUBLICO`, `BECAS_SUBVENCIONES_Y_AYUDAS`) pide **plazo**.
  `publication.categoria` nula es **fail-fast** (`IllegalArgumentException`) antes
  de recuperar o invocar al proveedor.
- **MUST NOT**: la generación es una **librería sin wiring**: **no** se construye
  en `Application.kt`/job/backfill, no añade endpoints/UI ni migración, y **no**
  anticipa lo diferido — **sin** cacheo ni control de coste (FT00021), **sin**
  guardrails de contenido/alcanzabilidad (FT00022), **sin** cola de revisión ni
  aviso de IA (FT00022/FT00023) y **sin** chat (FT00025). No se modifican
  `ResumenDto`/`CitizenSummaryValidator`/`HybridSearch` (se reutilizan).
- **MUST**: la prueba real contra OpenCode es **opt-in**
  (`OPENCODE_LIVE_TEST=1`, fail-fast sin clave), fuera de `build`/`test`/`init.sh` y
  de la CI; el gate cubre config, proveedor (`MockEngine`), parser, prompt y servicio
  con **dobles deterministas**, sin red ni BD.

## Cacheo y control de coste

- **MUST**: la **clave de caché** del resumen ciudadano es **determinista** y
  combina **publicación + modelo + versión de prompt**; un cambio de cualquiera de
  los tres produce una clave distinta y, por tanto, un **fallo de caché** (nunca
  se sirve un resumen obsoleto). Es un valor **puro** y **fail-fast**
  (`IllegalArgumentException`) si algún componente está en blanco. La
  `PROMPT_VERSION` es una constante **manual**: hay que **subirla** al cambiar el
  prompt de forma incompatible. Decisión durable en `docs/adr/0016`.
- **MUST**: **solo** se cachean resúmenes **`Valid`** (los que cumplen el contrato);
  un resumen `Invalid` **no** se cachea. El resumen cacheado se guarda como el
  `ResumenDto` **serializado** en una tabla **propia** (`resumen_cache`, separada de
  la tabla `resumen` que guarda el resumen publicado).
- **MUST**: **cada** generación (acierto de caché o llamada al proveedor)
  **registra** tokens (prompt/completion/total) y `cache_hit` en `generacion_uso`
  (`cache_hit = true` con 0 tokens en un acierto); en un **acierto** el proveedor
  **no** se invoca. Si la respuesta no trae `usage`, se registran **0** tokens (no
  es fail-fast: no se inventa consumo). Se registran **tokens**, no tarifas.
- **MUST**: la migración `V4` (`resumen_cache` + `generacion_uso`) es **versionada**
  (`V1`/`V2`/`V3` no se editan) y queda **fuera** de `build`/`check` (tarea
  explícita `:backend:flywayMigrate`). El *upsert* de la caché es **idempotente**
  por `cache_key`.
- **MUST NOT**: la caché es una **librería sin wiring**: **no** se construye en
  `Application.kt`/job/backfill, no añade endpoints/UI y **no** anticipa lo
  diferido (guardrails FT00022, cola de revisión FT00023, chat FT00025, rate
  limiting). El **modelo** se **inyecta** por constructor (en producción, de
  `OpenCodeConfig`): la caché no lo lee de la config.
- **MUST**: la prueba real de la caché y del uso contra PostgreSQL es **opt-in**
  (`DB_LIVE_TEST=1`), fuera de `build`/`test`/`init.sh` y de la CI; el gate cubre
  la clave, el servicio con caché, el uso del proveedor y el contrato SQL de `V4`
  con **dobles deterministas**, sin red ni BD.

## Guardrails anti-alucinación y trazabilidad

- **MUST**: ningún resumen se **publica** sin **fuente oficial válida**: enlace
  `https://`, host del BOE (`www.boe.es`, `boe.es`) e **idéntico** al
  `urlOficial` de la publicación de origen (trazabilidad), ni con **afirmaciones no
  sustentadas** por el contexto recuperado. La decisión es **tipada**
  (`GuardrailDecision.PUBLISHABLE`/`NEEDS_REVIEW`/`DISCARDED`) y expone una
  **puntuación de grounding** `[0,1]`; la baja confianza va a `NEEDS_REVIEW` (no se
  publica y FT00023 la encolará). Decisión durable en `docs/adr/0017`.
- **MUST**: el guardrail de **contenido** es **offline, puro y determinista** (sin
  red, BD, reloj ni LLM) y **reutiliza** `CitizenSummaryValidator` (FT00019) para el
  **contrato**, sin duplicar reglas ni cambiar el contrato de wire de `ResumenDto`.
  El **grounding** es **léxico** (cifras estrictas + fracción de términos de
  contenido ≥ `MIN_CLAIM_SUPPORT` = 0.6) y **conservador**: un falso negativo lleva a
  revisión/descarte, nunca a publicar. Los umbrales (`DISCARD_THRESHOLD` = 0.5,
  `REVIEW_THRESHOLD` = 0.8) son constantes documentadas y ajustables sin cambiar
  firmas.
- **MUST**: la **alcanzabilidad** de la fuente es un **puerto** `suspend`
  (`SourceReachability`); su implementación HTTP (`HttpSourceReachability`) usa un
  `HttpClient` **inyectado** con `HttpTimeout` y `followRedirects = false` (2xx/3xx ⇒
  alcanzable; fallo de red ⇒ `false`). El guardrail recibe el puerto **opcional**: sin
  él solo valida la **estructura**; **no** conoce Ktor.
- **MUST NOT**: el guardrail es una **librería sin wiring**: **no** se construye en
  `Application.kt`/job/backfill, **no** añade endpoints/UI ni migración y **no**
  anticipa lo diferido — **sin** cola de revisión, estados del resumen, `confianza`
  persistida ni aviso de IA (FT00023), **sin** publicación en `resumen`
  (FT00023/FT00026) y **sin** chat (FT00025). **No** escribe en `resumen` ni en
  `cola_revision` y **no** modifica `ResumenDto`/`CitizenSummaryValidator`/
  `HybridSearch`/`CitizenSummaryGenerator`/`CachedCitizenSummaryGenerator`.
- **MUST**: la prueba real de **alcanzabilidad** es **opt-in** (`BOE_LIVE_TEST=1`),
  fuera de `build`/`test`/`init.sh` y de la CI; sin la variable, el test se **omite
  sin abrir sockets**. El gate cubre normalizador, validador de fuente, grounding,
  evaluador con dobles y `HttpSourceReachability` con `MockEngine`, **sin red ni BD**.

## Cola de revisión y disposición del resumen

- **MUST**: la disposición **consume** la decisión tipada de FT00022
  (`GuardrailDecision`): **no** se define un umbral de revisión nuevo ni se duplica
  el grounding; `NEEDS_REVIEW` (y su rango `[DISCARD_THRESHOLD, REVIEW_THRESHOLD)`
  más violaciones) ya lo decide el guardrail. La `confianza` persistida es el
  `groundingScore`. Decisión durable en `docs/adr/0018`.
- **MUST**: `NEEDS_REVIEW` **no** publica: el resumen queda `en_cola_revision` y se
  encola una entrada `pendiente` en `cola_revision`; `PUBLISHABLE` publica
  (`estado = publicado`); `DISCARDED` queda `descartado` (ni publica ni encola). El
  feed futuro filtra `estado = 'publicado'`. El resumen publicado lleva
  `aviso_ia = true` (el aviso **visible** es FT00033).
- **MUST**: el encolado es **idempotente por resumen pendiente**: índice único
  parcial `ON cola_revision (resumen_id) WHERE estado = 'pendiente'` (migración
  `V5`, versionada, `V1`…`V4` no se editan) + *upsert* (`ON CONFLICT … DO UPDATE SET
  motivo`). Reencolar **actualiza** el motivo y **no** duplica la fila; se conserva
  el historial de revisiones cerradas. `ReviewQueueRepository` gana `listPending()`;
  `listBySummary` se mantiene y `SummaryRepository` **no** se modifica.
- **MUST**: la disposición es una **librería sin wiring** (`rag/review/`): **no** se
  construye en `Application.kt`/job/backfill, no añade endpoints/UI y **no** anticipa
  lo diferido (feed/endpoints/UI y revisión manual `revisado → publicado|descartado`
  son FT00026+/FT00033, aviso de IA visible FT00033, chat FT00025). No modifica
  `SummaryGuardrail`/`ResumenDto`/`CitizenSummaryValidator`/`HybridSearch`/`:shared`/
  `:composeApp`/CI/`init.sh`. `motivo` es diagnóstico interno (nombres de violación),
  **no** texto de UI.
- **MUST**: la prueba real de disposición (publicar + encolar + reencolado
  idempotente) es **opt-in** (`DB_LIVE_TEST=1`, solo PostgreSQL, sin OpenCode ni
  modelo E5), fuera de `build`/`test`/`init.sh` y de la CI; el gate cubre los
  estados, el motivo, el servicio con **dobles deterministas** y el contrato SQL de
  `V5`, sin red ni BD.

## API pública: feed diario

- **MUST**: el feed diario (`GET /feed`) es de **solo lectura y público**, sin
  cuentas ni datos personales, y se consulta **por fecha** obligatoria ISO-8601
  (`fecha`); no filtra por categoría (FT00028). Decisión durable en
  `docs/adr/0021`.
- **MUST**: sirve **solo** publicaciones con `resumen.estado = 'publicado'` (token
  que escribe FT00023); las demás no aparecen ni cuentan en `total`. Cada
  publicación lleva `resumen`, `categoria` y `urlOficial` (trazabilidad); el
  `avisoIA` viaja tal cual lo persistió la disposición (el aviso visible es
  FT00033).
- **MUST**: los destacados se calculan ***on-the-fly*** con `HighlightRanker`
  (ADR 0008) sobre el día completo, **no** se persisten; el contrato expone
  `motivos` (`HighlightReasonDto`, ≥1 por destacado) y **no** el `score` numérico.
- **MUST**: la paginación es por `pagina`/`tamanoPagina` (default `20`, máximo
  `100`), en memoria; `total`/`totalPaginas` reflejan el **día completo**. Un
  `fecha` ausente/no ISO o una paginación no entera, `< 1` o `> 100` responden
  `400`; un día sin publicado responde `200` con listas vacías.
- **MUST**: el arranque **no** depende de la BD: el composition root crea un
  **pool JDBC único** solo si la config resuelve, lo comparte entre el feed y la
  ingesta y lo cierra **una sola vez** en `ApplicationStopped`; `/feed` se registra
  **solo** si hay pool y `/health` queda operativo sin BD. La lectura JDBC
  bloqueante va en `Dispatchers.IO` y el SQL está **parametrizado** (fecha con
  *cast* `?::date`), sin secretos.
- **MUST NOT**: esta feature **no** añade CORS, *rate limiting*, OpenAPI, versionado
  del path ni cuerpo de error consistente (FT00029/FT00030), ni UI (FT00032+), ni
  migración (`V1`…`V5` intactas). **No** cambia `HighlightRanker`/`Highlight`,
  `PublicacionRepository`/`SummaryRepository`, el job/backfill ni
  `:composeApp`/CI/`init.sh`; reutiliza sus mappers y su ranker.
- **MUST**: la prueba real (solo se sirve el resumen publicado) es **opt-in**
  (`DB_LIVE_TEST=1`), fuera de `build`/`test`/`init.sh` y de la CI; el gate cubre
  el contrato de `:shared`, el repositorio con dobles, el servicio, el mapeo y la
  ruta con `testApplication`, sin red ni BD.

## API pública: detalle de publicación

- **MUST**: el detalle (`GET /publicacion/{id}`) es de **solo lectura y público**,
  sin cuentas ni datos personales, y se consulta por el **identificador oficial**
  del BOE como **segmento de path** (`BOE-A-2026-20979`). Decisión durable en
  `docs/adr/0022`.
- **MUST**: sirve **solo** publicaciones con `resumen.estado = 'publicado'` (token
  tipado `SummaryState.PUBLISHED` que escribe FT00023); un resumen no publicado (o
  ausente), un identificador desconocido y una publicación sin categoría (dato
  corrupto) responden `404` sin inventar categoría ni resumen. La respuesta es el
  **mismo** `PublicacionDto` de `:shared` que usa el feed, con `urlOficial`,
  `fuenteOficial` (trazabilidad), `avisoIA` y `plazo`; **no** se crea ningún DTO
  nuevo.
- **MUST**: el detalle **reutiliza** el mapeo puro `FeedDtoMapper.toPublicacionDto`
  de FT00026 y los repositorios `PublicationRepository.findById` +
  `SummaryRepository.findByPublication`; **no** duplica el SQL del feed ni modifica
  `FeedRepository`/`HighlightRanker`/`SummaryRepository`.
- **MUST**: el `id` es un segmento de path; un `id` **en blanco** o más largo que
  `PublicationDetailService.MAX_ID_LENGTH` responde `400` **sin cuerpo tipado** y un
  id desconocido/no publicado responde `404` (no es un error). El **formato** del
  identificador es **opaco** (la existencia decide `200`/`404`); **no** se valida.
- **MUST**: el arranque **no** depende de la BD: el composition root construye el
  detalle sobre el **mismo pool JDBC único** que el feed y la ingesta y registra
  `/publicacion/{id}` **solo** si hay pool; sin BD la ruta no se registra (`404`) y
  `/health` queda operativo. La lectura JDBC va en `Dispatchers.IO` y el SQL está
  parametrizado.
- **MUST NOT**: esta feature **no** añade CORS, *rate limiting*, OpenAPI, versionado
  del path ni cuerpo de error consistente (FT00029/FT00030), ni UI/aviso visible
  (FT00033), ni migración (`V1`…`V5` intactas). **No** cambia el contrato de
  `:shared`, ni el pipeline de resumen, ni `:composeApp`/CI/`init.sh`.
- **MUST**: la prueba real (solo se sirve el resumen publicado) es **opt-in**
  (`DB_LIVE_TEST=1`), fuera de `build`/`test`/`init.sh` y de la CI; el gate cubre el
  servicio y la ruta con dobles deterministas y `testApplication`, sin red ni BD.

## API pública: búsqueda

- **MUST**: la búsqueda (`GET /buscar`) es de **solo lectura y pública**, sin
  cuentas ni datos personales, y se consulta con `q` **obligatoria** (no vacía) más
  filtros opcionales: `categoria` como **token de wire** de `CategoriaDto`,
  `desde`/`hasta` ISO-8601 **inclusivas** y `limite` (default `10`, máx `50`).
  Decisión durable en `docs/adr/0023`.
- **MUST**: sirve **solo** publicaciones con `resumen.estado = 'publicado'` (token
  tipado `SummaryState.PUBLISHED` que escribe FT00023); las demás no aparecen
  (aunque el fragmento exista). Cada resultado es el **mismo** `PublicacionDto` de
  `:shared` que el feed (con `resumen`, `categoria` y `urlOficial`), y se
  **reutiliza** el mapeo puro `FeedDtoMapper`; **no** hay DTO ni mapper nuevo por
  ítem.
- **MUST**: la recuperación **reutiliza** `HybridSearch`/`SearchFilter`/
  `SearchFilterSql` (FT00017) **sin modificarlos**; el filtro de metadatos va
  parametrizado. El resultado es **top-k** (ANN, sin `total` ni paginación) y se
  **deduplica** por publicación conservando el orden de relevancia, con una ventana
  de sobre-recuperación `limite * CANDIDATE_FACTOR` (`CANDIDATE_FACTOR = 5`,
  heurística documentada).
- **MUST**: la lectura por lote de las publicaciones publicadas vive en
  `FeedRepository.listPublishedByIds` (`ANY(?)`, token `SummaryState.PUBLISHED`,
  categoría nula excluida); un lote vacío devuelve lista vacía **sin** abrir
  conexión. `FeedRepository` solo se **amplía**; `PublicationRepository`/
  `SummaryRepository`/`HighlightRanker` no se tocan.
- **MUST**: `q` ausente/en blanco, `categoria` no válida, fecha no ISO o `limite` no
  entero, `< 1` o `> MAX_LIMIT` responden `400` **sin cuerpo tipado** (el contrato
  de error es FT00030); una consulta sin resultados y un rango `desde > hasta`
  responden `200` con `resultados` vacío.
- **MUST**: el arranque **no** depende de la BD ni del modelo: el composition root
  **cablea por primera vez** el proveedor de embeddings (`E5EmbeddingProvider`,
  FT00015) de forma **condicional** (sin modelo o config ⇒ `null`, con aviso y sin
  fallo), registra `/buscar` **solo** si hay pool **y** proveedor (`404` en caso
  contrario) y cierra el pool y el proveedor **una sola vez** en
  `ApplicationStopped`. `/health` queda operativo sin BD ni modelo.
- **MUST**: la inferencia ONNX y la lectura JDBC (bloqueantes) van fuera del event
  loop (`Dispatchers.IO`); el SQL está parametrizado, sin secretos.
- **MUST NOT**: esta feature **no** añade CORS, *rate limiting*, OpenAPI, versionado
  del path ni cuerpo de error (FT00029/FT00030), ni UI (FT00032+), ni migración
  (`V1`…`V5` intactas), ni dependencias Gradle nuevas. **No** modifica
  `HybridSearch`/`SearchFilter`/`SearchFilterSql`/`FragmentRepository`/`PgVector`/
  `ArticleChunker`/`rag/embeddings`/`SummaryRepository`/`PublicationRepository`/
  `HighlightRanker`/el job/backfill ni `:composeApp`/CI/`init.sh`.
- **MUST**: la prueba real (publicación relevante primero con el modelo E5 y solo
  publicados) es **opt-in** (`DB_LIVE_TEST=1` + `EMBEDDING_LIVE_TEST=1`), fuera de
  `build`/`test`/`init.sh` y de la CI; el gate cubre el contrato de `:shared`, el
  servicio, la lectura por lote y la ruta con dobles deterministas y
  `testApplication`, sin red, BD ni modelo.

## API pública: chat

- **MUST**: el chat (`POST /chat`) es de **solo lectura y público**, sin cuentas ni
  datos personales, sin historial persistido, y se consulta con un cuerpo JSON
  `ChatRequestDto` (`{"consulta":"…"}`). Decisión durable en `docs/adr/0024`.
- **MUST**: responde **solo** con el contexto recuperado y **cita la fuente
  oficial**: `respondida`/`refutada` **exigen** ≥1 cita resoluble a la `urlOficial`
  de la publicación del fragmento citado; `sin_fundamento` **no** es error (`200`),
  lleva `citas` vacía y el proveedor **no** se invoca si no hay contexto. La URL la
  **inyecta** el `CitationResolver` de producción
  (`PublicationCitationResolver` sobre `PublicationRepository.findById`), nunca el
  modelo (que solo aporta **índices**); una publicación no resoluble descarta esa
  cita.
- **MUST**: el contrato de transporte vive en `:shared` con sufijo `Dto` y
  `@SerialName` explícito (`ChatRequestDto`/`ChatResponseDto`/`ChatStatusDto`/
  `ChatCitationDto`); el enum de wire usa tokens `snake_case`
  (`respondida`/`refutada`/`sin_fundamento`). **No** se expone el consumo de tokens
  (`usage`): el control de coste/rate limiting es FT00030.
- **MUST**: la consulta se acota con `ChatService.MAX_QUERY_LENGTH` y el contexto
  con el `limit` por defecto de `RagChatService` (**no** controlable por el
  cliente); una `consulta` ausente, en blanco, desmesurada o un cuerpo ilegible
  responden `400` **sin cuerpo tipado**; un fallo del proveedor
  (`TextGenerationException`) o una salida no interpretable
  (`ChatGenerationException`) responden `502` y un fallo de la inferencia local
  (`EmbeddingException`) responde `500` (el contrato de error es FT00030).
- **MUST**: el arranque **no** depende de la BD, el modelo ni la clave: el
  composition root cablea de forma **condicional** el proveedor de embeddings
  (ONNX) y el proveedor de texto (OpenCode, fail-fast de `OPENCODE_API_KEY`
  capturado ⇒ `null`) sobre el **mismo pool JDBC único**; `/chat` se registra
  **solo** si existen los tres y `/health` queda operativo sin ninguno. El pool, el
  proveedor de embeddings y el cliente HTTP de OpenCode se cierran **una sola vez**
  en `ApplicationStopped`. La clave vive **solo** en el servidor y no se registra.
- **MUST**: la recuperación ONNX/JDBC y la resolución de citas JDBC (bloqueantes)
  van fuera del event loop (`Dispatchers.IO`); el SQL está parametrizado, sin
  secretos. El parámetro `chatService` de `configureRouting` es **aditivo y
  compatible**.
- **MUST NOT**: esta feature **no** modifica `rag/chat`/`rag/generation`/
  `rag/embeddings`/`rag/retrieval`/`persistence/*` (se reutilizan), **no** añade
  CORS, *rate limiting*, OpenAPI, versionado del path ni cuerpo de error (FT00029/
  FT00030), ni UI (FT00037), ni migración (`V1`…`V5` intactas), ni dependencias
  Gradle nuevas, ni cablea el pipeline de resumen/indexado del corpus. **No** toca
  `:composeApp`/CI/`init.sh`.
- **MUST**: las pruebas reales (respuesta con cita contra OpenCode y resolución de
  la cita contra PostgreSQL) son **opt-in** (`OPENCODE_LIVE_TEST=1` y
  `DB_LIVE_TEST=1`), fuera de `build`/`test`/`init.sh` y de la CI; el gate cubre el
  contrato de `:shared`, el mapeo, el resolver, el servicio y la ruta con dobles
  deterministas y `testApplication`, sin red, BD, modelo ni OpenCode.

## API pública: contratos y versionado

- **MUST**: el **contrato OpenAPI** es **público y de solo lectura** y el
  versionado vive en el **path**: los endpoints de **dominio** se sirven bajo
  `/v1/…` (`/v1/feed`, `/v1/publicacion/{id}`, `/v1/buscar`, `/v1/chat`) y
  `/health` y `GET /openapi.json` quedan **sin** versión (operacionales y
  estables). El prefijo solo versiona: **no** cambia métodos, parámetros ni
  semántica. Decisión durable en `docs/adr/0025`.
- **MUST**: el **documento es la fuente de verdad** del contrato y los **DTOs
  `Dto` de `:shared` su implementación**. El documento es un artefacto **estático
  y versionado** en los recursos de `:backend`
  (`src/main/resources/openapi/openapi.json`, OpenAPI **3.1**) y se sirve en
  `GET /openapi.json` (`200` `application/json`, `info.version = "0.5.0"`),
  **siempre** registrado y **sin** depender de la base de datos, el modelo ni
  OpenCode.
- **MUST**: un **test anti-deriva** en el gate contrasta los esquemas documentados
  con los `@SerialName` (`serializer().descriptor.elementNames`) y los **tokens**
  de los enums de wire reales de `:shared`; una divergencia **falla**. Si un DTO
  cambia, hay que actualizar el documento.
- **MUST**: los cambios **aditivos y compatibles** mantienen `/v1` y suben la
  *minor/patch* de `info.version`; un cambio **incompatible** exige un prefijo
  nuevo (`/v2`) con `/v1` conservado hasta su deprecación. **No** se conservan
  aliases sin `/v1`.
- **MUST**: los códigos de error (`400`/`404`/`429`/`500`/`502`) se documentan
  **con** el esquema de error compartido `ApiErrorDto`/`ApiErrorCodeDto`; el CORS y
  el rate limiting los entrega **FT00030** (ver §«API pública: endurecimiento HTTP»
  y `docs/adr/0026`).
- **MUST NOT**: esta feature **no** añade dependencia Gradle de OpenAPI ni
  generación en tiempo de compilación (el compilador de Ktor exige Kotlin
  ≥ 2.2.20 y el proyecto fija 2.1.20), **no** añade migración (`V1`…`V5`
  intactas), **no** cambia los DTOs de `:shared` ni los servicios/rutas de
  dominio (solo **prefija** `/v1`), y **no** toca `:composeApp`/CI/`init.sh` ni
  añade Swagger UI/ReDoc.

## API pública: endurecimiento HTTP

- **MUST**: el **CORS** es configurable por entorno (`CORS_ALLOWED_ORIGINS`) y se
  resuelve con el plugin oficial `CORS`; con la variable **ausente/vacía** se
  permite cualquier origen (`anyHost()`) porque la API es pública y **sin
  credenciales** (no hay datos de usuario que proteger), y con una lista se aplica
  una **allowlist estricta**. `allowCredentials` es siempre `false`. El origen de
  producción se fija con `CORS_ALLOWED_ORIGINS` en el despliegue (FT00039).
  Decisión durable en `docs/adr/0026`.
- **MUST**: el **rate limiting** es **por IP** (`request.origin.remoteHost`) y **en
  memoria** (por instancia; el backend es un único proceso, **sin** Redis ni
  almacén compartido), con un cupo **general** para `/v1/…`
  (`RATE_LIMIT_REQUESTS`, por defecto 60/60 s) y otro más **estricto** para
  `/v1/chat` (`CHAT_RATE_LIMIT_REQUESTS`, por defecto 6/60 s, porque es lo más
  caro); `/health` y `/openapi.json` quedan **exentos** (operacionales). Superar el
  cupo responde `429` con `Retry-After`. **No** se confía en cabeceras de proxy
  (`X-Forwarded-For`/`Forwarded`): el trust de proxy es FT00041.
- **MUST**: cualquier error de la API (`400`/`404`/`429`/`500`/`502`) responde un
  **cuerpo JSON tipado** `ApiErrorDto` (`{"codigo":…,"mensaje":…}`) con
  `Content-Type` JSON, vía el plugin oficial `StatusPages`; los tokens de
  `ApiErrorCodeDto` son `snake_case` y **estables**. El `mensaje` es **genérico** y
  **nunca** filtra detalles internos (trazas, SQL, mensajes de proveedores). El
  `429` **conserva** la cabecera `Retry-After`. **No** cambia ningún **código** de
  estado.
- **MUST**: los tres plugins (`CORS`, `RateLimit`, `StatusPages`) son **oficiales**
  de Ktor a la versión fijada (3.0.3) y **no** abren sockets ni servicios: el gate
  sigue **offline** (tests con `testApplication`). Son las **únicas** dependencias
  Gradle nuevas de FT00030 (excepción deliberada a la pauta de las features de API
  previas, documentada). El composition root los instala **siempre** (no dependen
  de BD/modelo/clave) y el rate limiting solo se aplica a las rutas de dominio
  (`configureRouting(..., applyRateLimits = true)`).
- **MUST**: el contrato OpenAPI refleja el error tipado (esquemas
  `ApiErrorDto`/`ApiErrorCodeDto`, respuestas de error con su `$ref` y `429` con
  `Retry-After`) y el **test anti-deriva** lo cubre; el cambio es aditivo y
  compatible (`/v1` se mantiene y `info.version` sube a `0.5.1`).
- **MUST NOT**: esta feature **no** añade autenticación/autorización ni cuotas por
  usuario, **no** usa rate limiting distribuido/persistente, **no** implementa
  trust de proxy, **no** añade Swagger UI ni UI, **no** cambia los DTOs de dominio,
  los servicios, `rag/*` o `persistence/*`, **no** añade migración (`V1`…`V5`
  intactas) y **no** toca `:composeApp`/CI/`init.sh`. Los tests de ruta `accepted`
  existentes siguen verdes (`applyRateLimits` por defecto `false`).
- **MUST**: la verificación (preflight CORS, `429` con `Retry-After`, cuerpo de
  error en `400`/`404`/`429`/`500`/`502` y contrato OpenAPI) es de **gate** con
  `testApplication` y dobles deterministas, sin red, BD, modelo ni OpenCode. No
  aplica E2E persistente.

## Chat RAG

- **MUST**: el chat responde **solo** con el contexto recuperado del BOE y **cita la
  fuente oficial**: una respuesta `respondida`/`refutada` **exige** al menos una
  cita resoluble a la URL oficial de la publicación del fragmento citado; sin
  ninguna, la respuesta **no se publica** y se devuelve `sin_fundamento`. Decisión
  durable en `docs/adr/0020`.
- **MUST**: la **fuente oficial no la produce el modelo**: el modelo solo aporta
  **índices** de fragmento y el `CitationResolver` **inyecta** la cita
  (`ChatCitation(publicationId, title, officialUrl)`) desde la publicación (en
  producción, `PublicationRepository.findById`). Una publicación no resoluble
  descarta esa cita (no se inventa una fuente).
- **MUST**: un guardrail de **grounding léxico** (reutiliza `SummaryTextNormalizer`
  y `SummaryGroundingChecker.MIN_CLAIM_SUPPORT` = 0.6, sin umbral nuevo) **degrada a
  `sin_fundamento`** cualquier respuesta `respondida`/`refutada` cuyas afirmaciones
  no estén sustentadas por el contexto. Es **conservador** (un falso negativo
  degrada, nunca publica una posible alucinación).
- **MUST**: el **contexto vacío** declara `sin_fundamento` **sin invocar** al
  proveedor; una salida **no parseable**, un **estado desconocido** o un **índice de
  fragmento fuera de rango** ⇒ `ChatGenerationException` tipada (no se devuelve una
  respuesta a medias).
- **MUST NOT**: el chat es una **librería sin wiring** (`rag/chat/`): **no** se
  construye en `Application.kt`/job/backfill, no añade endpoints/UI ni migración y
  **no** anticipa lo diferido — **sin** rate limiting ni control de cuota
  (FT00030), **sin** UI (FT00037) y **sin** persistir el historial del chat. (El
  endpoint/API y el DTO de wire en `:shared` los entregó **FT00031**, que **consume**
  esta librería sin modificarla; ver §«API pública: chat».) No se
  modifican `TextGenerationProvider`/`OpenCodeTextGenerationProvider`/`OpenCodeConfig`
  (FT00020), `SummaryTextNormalizer`/`SummaryGroundingChecker` (FT00022) ni
  `HybridSearch`/`SearchFilter` (FT00017): se **reutilizan**.
- **MUST**: la prueba real contra OpenCode es **opt-in** (`OPENCODE_LIVE_TEST=1`,
  fail-fast sin clave), fuera de `build`/`test`/`init.sh` y de la CI; el gate cubre
  prompt, parser, grounding y servicio con **dobles deterministas**, sin red ni BD.

## Categorización y plazos

- **MUST**: la categoría de una publicación es una **regla curada determinista**
  a partir de la **sección** y el **epígrafe** (con el título como respaldo), sin
  IA/LLM ni embeddings; el clasificador es **puro** y **siempre** devuelve una
  `CategoriaDto` (nunca `null`), cayendo en la categoría por defecto de la
  sección, y **conserva** el epígrafe original como metadato. Decisión durable en
  `docs/adr/0007`.
- **MUST**: la extracción del plazo de solicitud es **heurística y acotada**
  (patrones concretos + puerta de contexto y descarte de ejecución/resolución/
  recurso/subsanación/alegaciones/informe); devuelve **vacío** (`null`) si no es
  fiable y **nunca** inventa una fecha. Los «días hábiles» cuentan solo sábados y
  domingos (sin calendario de festivos), límite documentado.

## Relevancia y destacados

- **MUST**: el ranking de destacados es **automático, objetivo, determinista y
  explicable**: usa **señales objetivas documentadas** (sección normativa, rango
  normativo, categoría curada, plazo abierto y organismo de una lista curada y
  modesta), **sin IA/LLM ni señales editoriales o subjetivas**, y **cada
  destacado expone su motivo** (`HighlightReason`, nunca vacío). Es **puro** (sin
  red, BD, reloj, aleatoriedad ni estado) y su salida **no depende del orden de
  entrada**; un día sin señales devuelve lista vacía. La señal de organismo es
  **modesta** y **nunca** decide por sí sola un destacado. Decisión durable en
  `docs/adr/0008`.
- **MUST**: en la 1.0.0 los destacados se **calculan *on-the-fly*** sobre la lista
  del día (`PublicationRepository.listByDate`), **no se persisten**: no hay
  columna, migración, repositorio ni segunda pasada en el job/backfill.

## RAG / fragmentación

- **MUST**: el **chunking es puro y determinista** sobre `Publicacion.texto`
  (paquete `rag/` de `:backend`; `rag/chunking/ArticleChunker`): sin IA/LLM, red,
  base de datos, reloj, aleatoriedad ni estado; la misma `Publicacion` produce
  siempre la misma lista. Decisión durable en `docs/adr/0009`.
- **MUST**: se fragmenta por **artículo/disposición** conservando su
  **referencia** (la línea de encabezado) y con **variante por sección** para las
  secciones sin artículos (II.A/II.B/IV/V.A/V.B/V.C: `reference = "Sección " +
  seccion.name`). El texto se cubre **sin solapamiento**: la concatenación de los
  fragmentos reproduce las líneas del texto de origen, en orden, sin repetirlas ni
  omitirlas.
- **MUST**: cada fragmento respeta el presupuesto del modelo E5 (**≤512 tokens**),
  con una **estimación provisional documentada e inyectable** por constructor
  (`charsPerToken = 3` por defecto) mientras el chunker se mantiene **puro**;
  FT00015 **expone** el tokenizador real (`countTokens`) sin modificar
  `ArticleChunker`, y la inyección/calibración del contador real en el chunker
  queda **diferida** (no forma parte de FT00016, que solo almacena vectores); un
  párrafo que supere el presupuesto se parte por palabras y conserva la misma
  `reference`. `order` es **contiguo** `0..n-1` en orden de documento.
- **MUST NOT**: la fragmentación **no anticipa lo diferido** — sin embeddings/ONNX
  en el propio chunker (FT00015), sin columna `embedding vector(384)` ni índice
  HNSW ni migración (FT00016), sin recuperación (FT00017) — y **no** escribe en
  PostgreSQL ni se cablea en `Application.kt`/job/backfill. El encaje con la
  persistencia es solo el mapeo puro `Fragment.toEntity()` (`id = null`, sin abrir
  conexión).

## Almacenamiento vectorial (pgvector)

- **MUST**: el embedding de `fragmento` es la columna **`embedding vector(384)`
  nullable** (dimensión del modelo E5 `-small`) con índice **HNSW**
  `vector_cosine_ops` (`m = 16`, `ef_construction = 64`), creada en la migración
  `V3`. Decisión durable en `docs/adr/0011`.
- **MUST**: el vector se guarda y consulta como **literal textual** (`[v1,v2,…]`,
  formato independiente del *locale*) enlazado con el *cast* `?::vector`, **sin
  ORM** y sin depender de `PGobject`; `PgVector` (puro) valida la dimensión **384**
  con **fail-fast** (`IllegalArgumentException`) **antes** de tocar la base de
  datos.
- **MUST**: `findNearest` filtra los fragmentos **sin embedding**
  (`embedding IS NOT NULL`) y ordena por **distancia coseno** ascendente; `limit`
  debe ser `>= 1` (fail-fast). **Sin** filtros de metadatos: la recuperación
  híbrida es de FT00017.
- **MUST**: la prueba real de similitud e índice HNSW es **opt-in**
  (`DB_LIVE_TEST=1`) contra el PostgreSQL de `docker-compose`, fuera de
  `build`/`test`/`init.sh` y de la CI; el gate cubre la conversión pura
  (`PgVectorTest`) y el contrato SQL de `V3`
  (`FragmentEmbeddingMigrationSqlTest`) sin red ni BD. `saveEmbedding` **no**
  crea el fragmento: la fila la crea `save` (FT00008/FT00014).

## Embeddings locales

- **MUST**: los embeddings son **locales** (`intfloat/multilingual-e5-small` int8)
  vía **ONNX Runtime en CPU**, tras una **interfaz intercambiable**
  (`EmbeddingProvider`); el resto del pipeline no conoce ONNX ni el modelo. El
  tokenizador XLM-R es el de DJL (`HuggingFaceTokenizer`) sobre un
  `tokenizer.json` local. Decisión durable en `docs/adr/0010`.
- **MUST**: se aplican los **prefijos obligatorios** `query: ` (consulta) y
  `passage: ` (fragmento); los vectores se **normalizan** (L2) y tienen **384
  dimensiones**; la entrada se recorta a **≤512 tokens**; el proveedor expone el
  **contador real** `countTokens` (cierre del provisional de FT00014).
- **MUST NOT**: el modelo (`model.onnx`, ~118 MB) y el `tokenizer.json` **no** se
  versionan ni se descargan en `build`/`test`/`init.sh`/CI; viven en
  `backend/models/` (**gitignored**), se aprovisionan con
  `backend/tools/download-embedding-model.sh` y se referencian por **ruta
  absoluta** de entorno (`EMBEDDING_MODEL_PATH`/`EMBEDDING_TOKENIZER_PATH`) con
  **fail-fast** (`EmbeddingException`) si faltan o no existen, **sin** *fallback*
  ni descarga silenciosa.
- **MUST**: la prueba contra el **modelo real** es **opt-in**
  (`EMBEDDING_LIVE_TEST=1`), fuera de `build`/`test`/`init.sh`/CI; el gate cubre el
  contrato y la aritmética con **dobles deterministas** (sin red ni artefactos).
- **MUST NOT**: el proveedor de embeddings (FT00015) **no** se cablea en
  `Application.kt`/job/backfill; el **almacenamiento** vectorial vive en
  `persistence/` (FT00016, `embedding vector(384)` + HNSW) y la **recuperación
  híbrida** (FT00017) es quien combina proveedor y repositorio.

## Recuperación híbrida e indexado

- **MUST**: la recuperación híbrida (FT00017) filtra **solo** por los metadatos
  existentes (`fecha_publicacion`, `categoria`, `seccion`, `organismo`) **combinados
  con `AND`** y siempre **parametrizados** (`?`, nunca concatenando entrada); el
  `SearchFilter` es un valor interno (sin sufijo, **no** `@Serializable`) y su
  traducción a SQL (`SearchFilterSql.whereClause`/`parameters`) es **pura**, con
  orden documentado y coherente. Las fechas ISO-8601 se enlazan como **texto con
  *cast* `?::date`** y una fecha no ISO falla con `IllegalArgumentException`
  **antes** de tocar la base de datos. Decisión durable en `docs/adr/0012`.
- **MUST**: `FragmentRepository.findNearest(queryEmbedding, filter, limit)` filtra
  los fragmentos **sin embedding** (`embedding IS NOT NULL`), aplica el filtro vía
  `JOIN publicacion` y ordena por **distancia coseno** ascendente; el `findNearest`
  de 2 argumentos (FT00016) **delega** con `SearchFilter()` sin romper su contrato.
  `limit < 1`, dimensión ≠384 o fecha no ISO son **fail-fast**
  (`IllegalArgumentException`) antes de abrir la conexión.
- **MUST**: la **composición** proveedor de embeddings + repositorio de fragmentos
  vive en **`rag/`** (servicios `HybridSearch` en `rag/retrieval/` y
  `FragmentIndexer` en `rag/indexing/`), **no** en `persistence/`; se **extiende**
  la interfaz existente (`FragmentRepository`) en vez de declarar un *port* nuevo
  para no duplicar SQL. La consulta usa `embedQuery` (prefijo `query: `) y los
  fragmentos `embedPassage` (prefijo `passage: `).
- **MUST**: el indexado mínimo (`FragmentIndexer.index`) es **idempotente** por el
  *upsert* de `(publicacion_id, orden)`: fragmenta (`ArticleChunker`), persiste cada
  fragmento (`save`) y guarda su embedding (`saveEmbedding`), **sin** *batching*,
  sin transacción multi-repositorio y **sin** indexar el corpus completo (operación
  posterior).
- **MUST**: la recuperación y el indexado son una **librería sin wiring**: **no** se
  construyen en `Application.kt` ni en el job/backfill, **no** hay endpoints/UI ni
  migración nueva, y **no** se anticipa lo diferido (evaluación FT00018;
  resúmenes/chat FT00019+; reranking/fusión léxica/índice GIN o trigram y ajuste de
  `ef_search`, que quedan para la evaluación/operación).
- **MUST**: las pruebas reales (filtros sobre PostgreSQL con vectores sintéticos, e
  indexado + recuperación con el modelo E5 real) son **opt-in**
  (`DB_LIVE_TEST=1` y `EMBEDDING_LIVE_TEST=1`), fuera de
  `build`/`test`/`init.sh`/CI; el gate cubre la traducción SQL, el servicio y el
  indexado con **dobles deterministas**, sin red ni BD.

## Evaluación de recuperación

- **MUST**: el **golden set** de evaluación es **versionado** en los recursos de
  `:backend` (`rag/eval/golden-set.json`) y su estructura y validaciones son las
  del spec FT00018: `k >= 1`, corpus y consultas no vacíos, ids únicos y **cada
  fragmento relevante existente en el corpus** (`publicationId` presente y
  `order >= 0`). Un dataset inválido falla con `IllegalArgumentException` **sin**
  abrir conexión. Decisión durable en `docs/adr/0013`.
- **MUST**: las métricas de recuperación (`precision@k`, `recall@k` y MRR) son
  **puras** (sin red, BD, modelo, reloj ni estado) y testables en el gate con
  dobles deterministas; el evaluador **agrega medias sin `NaN`** (media de una
  lista vacía = `0.0`) y **no** conoce el proveedor de embeddings ni Ktor.
- **MUST**: la evaluación **no cambia la recuperación**: reutiliza
  `SearchFilter`/`HybridSearch`/`FragmentIndexer` tal cual. La ejecución real es
  **opt-in** (`DB_LIVE_TEST=1` + `EMBEDDING_LIVE_TEST=1`) con la tarea
  `:backend:evaluateRetrieval` **fuera** de `build`/`check`/`init.sh` y de la CI;
  el test live afirma un **umbral conservador y documentado** (no perfección).
- **MUST NOT**: la evaluación **no persiste el histórico** (log JSON estructurado
  `event=retrieval.evaluation.*` + stdout) ni añade migración; **no** se cablea en
  `Application.kt`/job/backfill y **no** se anticipa lo diferido (resúmenes/chat,
  endpoints/UI, reranking/fusión léxica, indexado del corpus completo).

## Evaluación de resúmenes

- **MUST**: el **golden set** de evaluación de resúmenes es **versionado** en los
  recursos de `:backend` (`rag/eval/summary-golden-set.json`) y su estructura y
  validaciones son las del spec FT00024: versión y entradas no vacías,
  identificadores únicos (con prefijo `EVAL-S`), categoría, título y texto
  presentes, y **resumen de referencia con «¿Qué cambia?» y «¿A quién afecta?» no
  vacíos**. Un dataset inválido falla con `IllegalArgumentException` **sin** abrir
  conexión ni invocar al generador. Decisión durable en `docs/adr/0019`.
- **MUST**: las métricas del resumen (`SummaryQualityMetrics`: F1 léxico por campo
  y *recall* de cifras) son **puras** (sin red, BD, modelo, reloj ni estado),
  **reutilizan** `SummaryTextNormalizer` de FT00022 y son testables en el gate con
  un generador **doble**; el evaluador agrega medias sin `NaN` (media de una lista
  vacía = `0.0`), deriva el acierto por umbral, cuenta los resúmenes **inválidos
  como fallo** (sin lanzar) y **no** conoce OpenCode ni Ktor.
- **MUST**: la evaluación **no cambia la generación ni los guardrails**: reutiliza
  `CitizenSummaryGenerator`/`CitizenSummaryResult`/`SummaryGenerationDto` (FT00020)
  y `SummaryTextNormalizer` (FT00022) tal cual. La ejecución real es **opt-in**
  (`OPENCODE_LIVE_TEST=1` + `DB_LIVE_TEST=1` + `EMBEDDING_LIVE_TEST=1`) con la tarea
  `:backend:evaluateSummary` **fuera** de `build`/`check`/`init.sh` y de la CI; el
  test live afirma un **umbral conservador y documentado** (no perfección): el F1
  léxico penaliza paráfrasis válidas y el objetivo es detectar **regresiones**.
- **MUST NOT**: la evaluación **no persiste el histórico** (log JSON estructurado
  `event=summary.evaluation.*` + stdout) ni añade migración; **no** se cablea en
  `Application.kt`/job/backfill y **no** se anticipa lo diferido (endpoints/UI de
  evaluación, juez LLM, ajuste automático del prompt o `PROMPT_VERSION`, métricas de
  sistema como latencia/coste, evaluación de chat).

## Persistencia y base de datos

- **MUST**: el acceso a datos usa **JDBC + HikariCP**, **sin ORM** (nada de
  Exposed/Hibernate). Los repositorios viven en `persistence/` (interfaz +
  entidad `...Entity` + implementación JDBC) y el pool/configuración en `infra/`;
  la conexión se **deriva** de `POSTGRES_*` (fuente única). Decisión durable en
  `docs/adr/0003`.
- **MUST**: la escritura de una publicación es **upsert por `id`**
  (`INSERT … ON CONFLICT (id) DO UPDATE`), **idempotente**: reejecutar la ingesta
  (FT00009) no crea filas duplicadas.
- **MUST**: las pruebas que **tocan la base de datos real** son **opt-in** por
  `DB_LIVE_TEST=1` contra el PostgreSQL de `docker-compose`, y quedan **fuera**
  de `build`/`test`/`init.sh` y de la CI (patrón `BOE_LIVE_TEST`). El gate cubre
  config de conexión, mapeo y contrato SQL de la migración **sin** PostgreSQL.
- **MUST**: las migraciones Flyway son versionadas y **nunca** se edita una ya
  aplicada (`V1`/`V2`/`V3`); lo diferido (p. ej. los filtros de metadatos de la
  recuperación híbrida, FT00017) **no** se anticipa.

## Nombres y contratos

- **MUST**: **todo el código va en inglés**. Los **identificadores** (paquetes,
  tipos, funciones, propiedades, constantes, parámetros, variables y los nombres
  de clases y métodos de test) se escriben en **inglés**; no se introducen
  identificadores en castellano. El **KDoc y los comentarios** van en castellano
  (idioma de la documentación del proyecto), igual que los mensajes dirigidos al
  operador. No se traducen los identificadores que son **datos/tokens de la
  fuente** (p. ej. los valores de wire de `CategoriaDto`/`SeccionBoeDto`). El
  código anterior a esta regla con identificadores en castellano es **deuda** a
  renombrar de forma incremental (FT00047); el código nuevo no añade más.
- **MUST**: **todo tipo `@Serializable`/de transporte** lleva sufijo `Dto`: el
  contrato de `:shared` — las `data class` (`PublicacionDto`, `ResumenDto`,
  `PlazoDto`, `ResumenDiarioDto`) y los **enums de wire** (`CategoriaDto`,
  `SeccionBoeDto`) — y también los DTOs de transporte de `:backend`
  (`HealthDto`, `BoeSumarioResponseDto`, `BoeSeccionDto`…). La configuración de
  serialización no es un tipo de contrato y va sin `Dto` (`DatoPublicoJson`).
- **MUST**: en las capas internas, entidades de persistencia `...Entity`, filas
  `...Row` y modelos de UI `...Ui`. Un **modelo de dominio/valor interno** que no
  sea serializable ni `Entity`/`Row`/`Ui` va **sin sufijo** (p. ej.
  `EntradaSumario`). Sin prefijos en ningún caso.

## Serialización (kotlinx.serialization)

- **MUST**: en todo tipo `@Serializable`, **cada propiedad** lleva `@SerialName`
  explícito, **aunque el nombre Kotlin coincida** con la clave JSON; no se confía
  en el nombre por defecto. Aplica al contrato de `:shared` y a los DTOs de
  transporte de `:backend`. Los valores de los enums de wire también llevan su
  `@SerialName`.

## Estilo de código

- **MUST**: cada función/método tiene **una sola salida** (`return` único);
  prohibido el *early return* (retornos intermedios). Se resuelve con expresiones
  (`when`, operador Elvis, `if`/`else` como expresión, `buildList`, etc.). Aplica
  **también a los tests**. Los códigos de salida temprana de lambdas etiquetadas
  (`return@…`, p. ej. `return@runTest`) se evitan igualmente: usa guardas `if` y
  deja el cuerpo sin salidas etiquetadas.
- **MUST**: **no** se usa `else if`. Las cadenas de guardas se resuelven con
  `when` (`when { cond -> …; else -> … }`), como expresión o como sentencia. Un
  `if` simple de dos ramas sigue permitido.
- **MUST**: las funciones son **cortas y con una sola responsabilidad**: máximo
  **40 líneas** (objetivo **30**), sin contar KDoc, comentarios ni líneas en
  blanco. Si se supera, se **extraen** sub-funciones o componentes.
- **MUST**: **reutilizar antes de escribir**. Antes de crear UI o lógica nueva,
  busca un componente/función equivalente en **todo** el repositorio (no solo en
  la feature en curso). Si lo van a usar **≥2 features**, muévelo a
  `design/components/`; si es de una sola feature, a `feature/<nombre>/ui/components/`.

## Documentación de código (KDoc)

- **MUST**: todo el código Kotlin que se añada o modifique lleva documentación
  **KDoc** (`/** … */`): clases, interfaces, objetos, funciones, propiedades y
  tipos públicos, con `@param`/`@property`/`@return`/`@throws`/`@see` cuando aporten.
- **MUST**: documentar el **porqué** de lo no obvio (contratos, invariantes,
  efectos secundarios, límites), no solo el qué. El KDoc vive junto al código; no
  se duplica en `docs/` lo que ya explica el KDoc.
- Un cambio que añade o modifica API sin KDoc es motivo de revisión en el PR.

## Arquitectura por capas: crear la capa que falte

- **MUST**: al añadir código, si la **capa o directorio** que le corresponde según
  la arquitectura **no existe todavía**, se **crea** y se coloca ahí; nunca en un
  paquete plano o en la capa equivocada «porque aún no existe».
- **MUST**: al implementar una feature, si falta una capa (p. ej. `domain/` o
  `data/`) se crea con sus componentes mínimos (interfaz + implementación, caso de
  uso, ViewModel…). No se inventan capas ni nombres nuevos: se siguen las skills
  `ktor-backend-architecture`, `compose-multiplatform-architecture` y
  `rag-datapublico` y `ARCHITECTURE.md`.

## Cliente (Compose Multiplatform)

- **MUST**: la **UI compartida** de `:composeApp` vive en `commonMain`; cada
  plataforma aporta **solo su entrypoint** (Android `MainActivity`, Wasm `main()`,
  iOS `MainViewController`). No duplicar pantallas por plataforma.
- **MUST**: el gate estándar (`./gradlew build -PskipClient`, `.harness/init.sh`
  por defecto) **no** exige el Android SDK ni arranca Xcode; el cliente
  (`:composeApp`) se añade con `--with-client`/`--with-ios`/`--with-all`. Los targets
  iOS se ignoran en hosts no-Apple y los tests de Wasm en navegador (Karma/Chrome)
  quedan fuera del gate.
- **MUST**: toda función `@Composable` de UI (pantallas, componentes y
  sub-composables) incluye al menos una `@Preview` (`org.jetbrains.compose.ui.tooling.preview.Preview`)
  en `commonMain`, junto al composable y dentro del tema. Los composables privados
  se previsualizan en el mismo fichero. Una preview **no** es un test y no autoriza
  tests de vistas/composables.
- **MUST**: **nunca** se provoca a propósito un *crash* que cierre la app. No se usan
  `throw`, `error(...)`, `TODO()` ni asertos como camino de control (en el código de
  producción). Los fallos (red, parseo, permisos, estados inesperados) se **modelan y
  se muestran** como estado gestionado (mensaje, reintento o estado vacío).
- **MUST**: todo texto visible al usuario sale de **recursos**
  (`composeResources/values*/strings.xml`, consumido con `stringResource(Res.string.*)`),
  nunca hardcodeado. La clave existe en **todos** los locales. Solo se permiten
  literales para símbolos tipográficos (flechas, separadores) y en `@Preview`.
- **MUST**: los **iconos con significado** usan **Material Icons**
  (`Icon(Icons.Outlined.*)`), con `contentDescription` cuando transmiten información;
  los glifos Unicode/ASCII se reservan a lo tipográfico dentro de un texto.
- **MUST**: las pantallas leen sus colores **solo** de `MaterialTheme.colorScheme.*`;
  nunca fijan un color de runtime. Los literales de color solo se permiten en `@Preview`.
- **MUST**: el tema del cliente es **`DatoPublicoTheme`** (`design/theme/`), la
  **única** entrada de tema: mapea los tokens de `DESIGN.md` (color, tipografía y
  formas) a `MaterialTheme` y es el **único** lugar con literales de color. Una
  pantalla nueva no define su propio `MaterialTheme`. Decisión durable en
  `docs/adr/0027`.
- **MUST**: los **componentes reutilizables** del cliente viven en
  `design/components/` (los usa ≥2 features o los reutilizarán las siguientes:
  `CategoryLabel`, `PublicationCard`, `PublicationBadges`); lo específico de una
  sola feature va en `feature/<nombre>/ui/`. Decisión durable en `docs/adr/0027`.
- **MUST**: los **textos de UI** de `:composeApp` salen de
  `composeResources/values*/strings.xml` (leídos con `stringResource(Res.string.*)`)
  y la **fecha** se formatea con una función pura `dd/mm/aaaa` (sin
  `java.time`/`kotlinx-datetime`, que romperían iOS/Wasm). Decisión durable en
  `docs/adr/0027`.
- **MUST**: el cliente Android declara un tema **sin ActionBar**
  (`@android:style/Theme.Material.Light.NoActionBar` en `AndroidManifest.xml`) y el
  contenido raíz se pinta con `safeDrawingPadding()`. Con `targetSdk 35` el modo
  *edge-to-edge* está forzado: un ActionBar de plataforma se **superpone** al
  contenido de Compose y oculta el encabezado de la pantalla.
- **MUST**: la pantalla de **detalle** (`feature/detail/`) muestra **siempre** el
  **enlace a la fuente oficial** (`OfficialSourceLink`, con guarda `http(s)://`
  antes de `LocalUriHandler`) y el **aviso de contenido generado por IA**
  (`AiNotice`); una URL inválida **no** provoca crash. Su punto de invocación es
  `DetailRoute(stateHolder, onBack)` (contrato; la navegación la cablea FT00034).
  Decisión durable en `docs/adr/0028`.
- **MUST**: `PublicationCategory`/`HighlightReason`/`Deadline`/`formatIsoDate`
  viven en `feature/feed/domain`; las features nuevas los **reutilizan**
  importándolos desde ahí (la extracción a un `core/model` neutral está **diferida**;
  ver `docs/adr/0028`).
- **MUST**: el cliente consume la API por el **cliente HTTP común** de
  `core/network/` (`ktor-client` con motores por plataforma, `HttpTimeout`
  explícito y errores **tipados** como valores; `CancellationException` se
  relanza). La **URL base** y la fecha del día se resuelven por plataforma con
  `expect/actual`; **nunca** un `http://…` fijo en `commonMain`. Decisión durable
  en `docs/adr/0029`.
- **MUST**: `:composeApp` **no** depende de `:shared` (se mantiene el gate
  SDK-free); el contrato se refleja con **DTOs de wire propios** (capa
  anti-corrupción, sufijo `Dto` y `@SerialName`) y un mapeo puro a los modelos de
  dominio del cliente. Decisión durable en `docs/adr/0029`.
- **MUST**: la **cache offline** es un puerto (`FeedCache`) con implementación en
  memoria y **sin datos personales**; al fallar la red se sirve el último contenido
  cacheado o se muestra el estado de error. La persistencia entre arranques no es
  un requisito (deuda futura). Decisión durable en `docs/adr/0029`.

## Build y repositorios

- **MUST**: el **gate de calidad es bloqueante**: `./gradlew detekt` ejecuta Detekt en
  `:backend`, `:shared` y `:composeApp` (config en `config/detekt/detekt.yml`, deuda
  conocida en `config/detekt/<módulo>-baseline.xml`) y, enganchado a él, el chequeo global
  de duplicación **`:cpdCheck`** (CPD de PMD, `language = kotlin`, umbral 100 tokens, barre
  todo `<módulo>/src/**/*.kt` salvo tests). Un hallazgo nuevo o un duplicado rompe el build.
  `check`/`build` lo arrastran, así que `./init.sh` también.
- **MUST**: el **gate estándar es SDK-free**: `./gradlew build -PskipClient` compila y testea
  solo `:shared` y `:backend` (no exige el Android SDK). `:composeApp` se incluye sin el flag
  y exige el Android SDK. `.harness/init.sh` es SDK-free por defecto y añade el cliente con
  `--with-client`/`--with-ios`/`--with-all`. `-PskipClient` lo reutilizará la imagen del backend.
- **MUST**: las distribuciones de herramientas de Kotlin/JS-Wasm (Binaryen, Node,
  Yarn) se declaran como repositorios Ivy en `settings.gradle.kts`, que usa
  `RepositoriesMode.PREFER_SETTINGS`. El plugin de Kotlin/Wasm las registra a
  nivel de proyecto, así que `FAIL_ON_PROJECT_REPOS` rompería el build. Mantén el
  settings como **fuente única de verdad** de repositorios.

## Decisiones y flujo

- **MUST**: las decisiones **durables** (modelo de datos, arquitectura, integración
  externa, despliegue, flujo de trabajo, seguridad) se registran como **ADR** en
  `docs/adr/` (formato e índice en `docs/adr/README.md`); para reabrir una decisión
  aceptada se escribe un ADR nuevo que la supersede/adjusta, no se edita el anterior.
- **MUST**: los PR que cambian la interfaz (`:composeApp` o `DESIGN.md`) llevan
  **capturas antes/después** en `docs/pr/<rama>/` (ver `docs/pr/README.md` y
  `docs/git-workflow.md`). Un cambio visual sin capturas ni justificación no se mergea.
- **MUST**: ningún PR de producto supera los **30 ficheros**; si se excede, se divide
  en partes `FTxxxxx-PTn` (`docs/git-workflow.md`).

## Operación

- **MUST**: ingesta diaria a las **9:30** más una **segunda pasada**; alerta si no
  se ejecuta.
- **MUST**: el backfill histórico es **one-shot**, **idempotente** por *upsert* de
  `id` y **reanudable** (checkpoint **local en fichero**); se ejecuta por **lotes
  con pausa configurable** en baja carga mediante una tarea explícita
  (`./gradlew :backend:backfill`) y **no** se cablea al arranque del servidor ni
  cambia las reglas del gate (sin red ni BD en `build`/`test`/`init.sh`). El
  *runner* **reutiliza** el job diario y no filtra secciones (ADR 0006).
- **MUST**: la observabilidad de la ingesta usa **eventos de log JSON con clave
  `event` estable** (ejecución: `ingestion.run.completed`/`ingestion.run.failed`;
  ventana perdida: `ingestion.missed`) y la alerta de ingesta ausente es un log
  `ERROR`; **sin** alertas externas (email, push, webhooks) ni telemetría. La
  gracia tras una ventana se configura con `INGESTA_GRACE_MINUTES` (default 30).
- **MUST**: migraciones Flyway versionadas; **nunca** editar una ya aplicada.
- **MUST**: el gate de build/tests (`./gradlew build`, `.harness/init.sh`) **no**
  depende de servicios externos (base de datos). Las migraciones se ejecutan con
  una tarea explícita (`./gradlew :backend:flywayMigrate`) y las tareas Flyway
  **nunca** se enganchan a `build`/`check` (la CI corre sin PostgreSQL).
- **MUST**: los tests del gate (`./gradlew build`, `./gradlew test`,
  `.harness/init.sh`) **no** hacen **llamadas de red**. Cualquier prueba contra un
  servicio externo (p. ej. la API de datos abiertos del BOE) es **opt-in** por
  variable de entorno y queda **fuera** de `build`/`test`/`init.sh` y de la CI;
  sin la variable, el test se omite sin abrir sockets (`BOE_LIVE_TEST=1`).
- **MUST NOT**: incluir credenciales en ficheros versionados, **ni siquiera de
  desarrollo** (sin contraseñas literales ni como *fallback* en código, compose,
  CI o plantillas). La única fuente es el entorno/`.env` (ignorado por git); la
  plantilla `.env.example` solo admite *placeholders* explícitos no secretos.
- **MUST**: un secreto ausente debe **fallar con mensaje claro** (fail-fast), no
  caer en un valor por defecto silencioso. `POSTGRES_PASSWORD` es obligatorio en
  `docker-compose` (`:?`) y la contraseña de Flyway no tiene default en el build
  (usa `FLYWAY_PASSWORD` o `POSTGRES_PASSWORD`).
- **MUST NOT**: duplicar la configuración de conexión entre herramientas. Las
  piezas de conexión tienen una **única fuente de verdad** (`POSTGRES_*`, la
  misma que consume `docker-compose`) y las variables propias de cada herramienta
  (`FLYWAY_*`) son solo *overrides* opcionales: cambiar `POSTGRES_PORT` (o
  host/db/usuario) debe bastar para que Flyway apunte al mismo sitio.
- **MUST**: el PostgreSQL local de desarrollo se publica **solo en loopback**
  (`127.0.0.1`), nunca en `0.0.0.0`.
- **MUST**: el arranque del backend **no** depende de la base de datos ni de
  servicios externos: se registran solo los subsistemas/rutas cuyas dependencias
  existen (el healthcheck `GET /health` queda operativo sin PostgreSQL). La
  configuración es **por entorno**, con valores por defecto no sensibles y
  **fail-fast** (arranque abortado con mensaje claro) si un valor es inválido.
- **N100 / 8 GB**: backfill por lotes en baja carga; `shared_buffers` ~1 GB,
  heap JVM ~1 GB, swap activado.

## Despliegue

Decisión durable en `docs/adr/0030`; el runbook está en `deploy/README.md`.

- **MUST**: los secretos se inyectan **solo por entorno** (`deploy/.env.production`,
  ignorado por git y con permisos restringidos) y **nunca** se versionan; la
  plantilla `deploy/.env.production.example` solo admite *placeholders*. Un secreto
  ausente **falla con mensaje claro** (fail-fast).
- **MUST**: en producción, PostgreSQL se publica **solo en loopback**
  (`127.0.0.1`) y el **backend no publica puerto**: la única entrada es **Nginx**
  (80/443). HTTPS obligatorio.
- **MUST**: la confianza de cabeceras de proxy (`TRUST_PROXY_HEADERS`) es **opt-in**
  (por defecto `false`); con ella, el plugin oficial `XForwardedHeaders`
  (`useFirstProxy()`) hace que el rate limiting use la **IP real** del cliente. Solo
  es segura porque el backend no publica puerto.
- **MUST**: la ingesta en producción es el **scheduler interno** (ADR 0004); **no**
  se añade cron externo.
- **MUST**: el **modelo E5 no va en la imagen** (se monta por volumen `:ro`);
  aprovisionarlo con `backend/tools/download-embedding-model.sh`.
- **MUST**: el **gate no arranca servidores ni Docker**. `docker build`,
  `docker compose config`, el lint de Nginx y `flywayMigrate` son **opt-in**
  (fuera de `build`/`check`/CI); el único test nuevo usa `testApplication` y no abre
  sockets.
- **MUST**: los puertos publicados de Nginx son **parametrizables**
  (`HTTP_PORT`/`HTTPS_PORT`, defaults 80/443) para no ocupar el 80/443 si el VPS ya
  tiene otro servicio; hay dos vías documentadas (detrás de un proxy existente o
  publicar el backend directo con `deploy/docker-compose.backend-direct.yml`, solo
  pruebas y sin HTTPS).
