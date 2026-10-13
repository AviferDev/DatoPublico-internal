# Feature Implementation Spec: Endpoint del feed diario

## Source Feature

- `id`: api-feed-diario
- `ft_id`: FT00026 (registrado en `docs/feature-ids.md`)
- `parts`: none (atómica; ≈15 ficheros de producto, por debajo del límite de 30)
- `area`: api-publica
- `depends_on`: ingesta-job-diario (FT00009, `accepted`) + destacados-diarios
  (FT00013, `accepted`) + guardrails-anti-alucinacion (FT00022, `accepted`) +
  cola-revision-confianza (FT00023, `accepted`).
- `status`: not_started (al planificar)
- `source`: `feature_list.json` (`notes`: `docs/roadmap.md` 0.5-T01)
- `claim`: rama `feat/ft00026-api-feed-diario` ya reclamada en `origin`
  (`cff2c49 chore(FT00026): claim`); sin PR abierto hacia `main`.

> **Dependencia resuelta.** El feed sirve **solo** resúmenes con
> `resumen.estado = 'publicado'`, token que **escribe** `cola-revision-confianza`
> (FT00023, `accepted`). El orquestador ya **añadió `cola-revision-confianza` a
> `depends_on`** en `feature_list.json` (2026-10-13). Guardrails (FT00022) cubre la
> validación de la fuente; destacados (FT00013) aporta el ranker.

## Goal

Exponer por HTTP, en `:backend`, el **feed diario** de publicaciones del BOE
(tarea `0.5-T01`): para una **fecha** dada, devolver las publicaciones del día que
tienen un **resumen ciudadano publicado** (`estado = 'publicado'`), cada una con su
**categoría**, su **enlace oficial**, su **resumen** y su **plazo** si existe, más
el bloque de **destacados del día** (calculado *on-the-fly* con el ranker ya
existente `relevance/HighlightRanker`, FT00013) y metadatos de **paginación**
(`pagina`/`tamanoPagina` con tamaño configurable).

La feature **cablea el primer endpoint de lectura de datos de `:backend`**:
introduce la capa de servicio, el repositorio de lectura con `JOIN publicacion ⋈
resumen`, el contrato de transporte en `:shared` y el wiring condicional en
`Application.kt` (un único pool JDBC compartido con la ingesta), sin servir jamás
un resumen no publicado. Reutiliza `PublicacionRepository`/mappers de
`persistence/`, `HighlightRanker` y los DTOs existentes de `:shared`; **no**
inventa comportamiento fuera de `docs/roadmap.md`, `docs/domain-model.md`,
`CONTEXT.md` (§Feed diario / §Destacados) y `DESIGN.md`.

## Non-Goals

- **Generar resúmenes**: la generación (FT00020), el cacheo (FT00021), los
  guardrails (FT00022) y la disposición (FT00023) son **librerías ya existentes**;
  este feature lee lo publicado, **no** cablea el pipeline de resumen. Que el feed
  aparezca poblado depende de que ese pipeline se cablee (gap de planificación, ver
  *Risks*).
- **Filtros de búsqueda** (query, categoría, rango de fechas): son `api-busqueda`
  (FT00028). El feed solo selecciona **una fecha**.
- **Detalle de publicación** (`api-detalle-norma`, FT00027) y **chat** (FT00031).
- **OpenAPI/versionado del path** (FT00029), **CORS/rate limiting/cuerpo de error
  consistente** (FT00030), **UI** (FT00032+) y **aviso de IA visible** (FT00033).
- **Persistir destacados** (se calculan *on-the-fly*; ADR 0008) ni añadir
  migraciones (`V1`…`V5` intactas, no hay cambio de esquema).
- Cambiar `Publicacion`/`PublicacionDto`/`ResumenDto`/`Highlight`/`HighlightRanker`
  (se **reutilizan**) ni el job/backfill.

## Job Story

When consulto el feed de un día,
I want recibir, en una sola llamada paginada, las publicaciones publicadas de ese
día con su resumen, su categoría y su enlace oficial, y un bloque de destacados
explicado por señales objetivas,
so I can empezar por lo relevante y saltar siempre a la fuente oficial sin que se
me sirva un resumen que no pasó los guardrails.

## Users And Permissions

- **Ciudadanía (usuario final):** anónima, solo lectura; sin cuentas ni datos
  personales; el endpoint es público.
- **Cliente CMP (FT00032):** consumidor del contrato `:shared`; elige la fecha.
- **Operador/desarrollador:** arranca el backend con PostgreSQL y ejecuta la prueba
  real **opt-in** (`DB_LIVE_TEST=1`).
- Sin autenticación, sin autorización y sin escritura.

## Acceptance Scenarios

### Scenario 1: día con publicaciones publicadas → feed paginado con resumen y destacados

Given una fecha con N publicaciones que tienen un resumen `publicado` y una de
ellas dispara señales de destacado,
When `GET /feed?fecha=<ISO>` (sin más parámetros),
Then responde `200` con `fecha`, `pagina = 1`, `tamanoPagina` por defecto,
`total = N`, `totalPaginas = ceil(N/tamanoPagina)`; `publicaciones` trae la
primera página, cada una con `resumen` (no nulo), `categoria`, `urlOficial` y
`plazo` (si existe); y `destacados` incluye esa publicación con `motivos` **no
vacío**.

### Scenario 2: solo se sirven resúmenes publicados

Given un día con una publicación con `resumen.estado = 'publicado'`, otra
`en_cola_revision` y otra `pendiente`,
When se pide el feed,
Then solo aparece la `publicado`; las demás **no** se sirven (ni en
`publicaciones` ni en `destacados`) y no cuentan en `total`.

### Scenario 3: paginación con tamaño configurable

Given el mismo día y `pagina=2&tamanoPagina=1`,
When se pide el feed,
Then `publicaciones` trae el segundo elemento en orden estable (`id` ascendente),
`pagina = 2`, `tamanoPagina = 1` y `total`/`totalPaginas` siguen reflejando el
día completo. Una `pagina` más allá de `totalPaginas` responde `200` con
`publicaciones` vacía y la misma metadata.

### Scenario 4: día sin contenido publicado → feed vacío

Given una fecha sin publicaciones o con publicaciones sin resumen publicado,
When se pide el feed,
Then responde `200` con `publicaciones` y `destacados` vacíos, `total = 0` y
`totalPaginas = 0` (no es un error).

### Scenario 5: parámetros inválidos → 400

Given una petición sin `fecha`, con `fecha` no ISO, o con `pagina`/`tamanoPagina`
no entero, `< 1` o `> MAX_PAGE_SIZE`,
When se pide el feed,
Then responde `400` (sin cuerpo tipado; el contrato de error es FT00030).

### Scenario 6: destacados deterministas y explicables

Given el mismo día,
When se pide el feed repetidamente (o en distinto orden de inserción),
Then `destacados` es idéntico y cada destacado expone ≥1 `HighlightReasonDto`
(`normative_section`, `normative_rank`, `thematic_keyword`, `open_deadline`,
`organismo_relevante`); no se expone el `score` numérico.

### Scenario 7: arranque sin base de datos intacto

Given un entorno sin `POSTGRES_PASSWORD`,
When arranca el backend,
Then `/health` responde `200`, la ruta `/feed` **no** se registra (`404`), el
arranque no falla y no se abre ninguna conexión; con base de datos, el feed se
registra y usa el **mismo pool** que la ingesta, cerrado **una sola vez** al parar.

### Scenario 8: el gate sigue sin red ni BD

Given el runner de CI sin PostgreSQL y sin red,
When se ejecuta `./gradlew build -PskipClient`, `./gradlew test`, `./gradlew
detekt` o `.harness/init.sh`,
Then todo está en verde; la prueba real se omite sin abrir conexiones.

### Scenario 9: la lectura real sirve solo publicados (opt-in)

Given `DB_LIVE_TEST=1` y el PostgreSQL de `docker-compose` con `V1`…`V5`,
When `FeedPersistenceLiveTest` inserta una publicación con resumen `publicado` y
otra con resumen `en_cola_revision`,
Then `FeedRepositoryJdbc.listPublishedByDate(fecha)` devuelve **solo** la
publicación publicada, con su resumen publicado.

## Repository Research

### Files Inspected

- `shared/src/commonMain/kotlin/…/model/{PublicacionDto,ResumenDto,PlazoDto,ResumenDiarioDto,CategoriaDto,SeccionBoeDto}.kt`
  — contrato de wire (todos con `@SerialName` explícito). `ResumenDiarioDto` está
  documentado como «Feed diario de publicaciones del BOE» y es el punto natural de
  extensión; `PublicacionDto`/`ResumenDto` ya llevan `resumen`, `categoria`,
  `urlOficial`, `plazo` y `avisoIA`.
- `backend/src/main/kotlin/…/backend/Application.kt` — composition root: crea el
  pool **solo** dentro de `configureIngestion` (`Database.createDataSource`),
  arranca Netty sin depender de BD y cierra pool/clientes en `ApplicationStopped`.
- `backend/src/main/kotlin/…/backend/plugins/{Routing,Health,Serialization,Monitoring}.kt`
  — patrón de rutas `Route.xRoutes()` + `configureRouting()`; `GET /health` sin BD;
  JSON con `DatoPublicoJson`.
- `backend/src/main/kotlin/…/backend/persistence/{PublicationRepository,SummaryRepository,ReviewQueueRepository,SummaryCacheRepository}.kt`
  — patrón JDBC (interfaz + `...Entity` + `...RepositoryJdbc`, helpers de
  `Jdbc.kt`, sin ORM, autocommit) y mappers internos `PublicationEntity.toDomain()`
  / `ResultSet.toSummaryEntity()` reutilizables. `SummaryEntity` lleva
  `id?`, `publicationId`, `whatChanges`, `whomItAffects`, `keyFigures`,
  `officialSource`, `aiNotice`, `status` (`publicado`/`en_cola_revision`/…) y
  `confidence`; **no** lleva `plazo`.
- `backend/src/main/kotlin/…/backend/relevance/{HighlightRanker,Highlight}.kt` —
  ranker **puro** `rank(List<Publicacion>): List<Highlight>` (score + reasons);
  `Highlight(publication, score, reasons)` es un valor interno sin sufijo.
- `backend/src/main/resources/db/migration/{V2,V5}*.sql` — `publicacion` (con
  `fecha_publicacion date`, índices) y `resumen` (`estado text`, FK 1:1). No hay
  cambio de esquema.
- `backend/build.gradle.kts` — `:shared` ya es dependencia; `ktor-server-test-host`
  ya está en test; **sin** dependencias nuevas.
- `backend/src/test/kotlin/…/plugins/HealthTest.kt` — patrón `testApplication {
  application { module() } }` para pruebas de rutas.
- `docs/desarrollo-local.md` (producto) — guía donde documentar el endpoint.
- Harness: `feature_list.json` (FT00026), `docs/roadmap.md` §0.5 (`0.5-T01`),
  `CONTEXT.md` §Feed diario / §Destacados, `docs/domain-model.md` (Feed, Resumen,
  Destacado), `DESIGN.md` §Layout/§Core Screens (bloque de destacados + lista),
  `docs/risks-and-open-questions.md` («Estrategia de caché y paginación de la
  API»), `ARCHITECTURE.md`, `CONSTRAINTS.md`, ADR 0008/0017/0018 y los specs
  `destacados-diarios.md`, `cola-revision-confianza.md`, `chat-generacion.md`.

### Existing Patterns To Follow

- **Ruta delgada en `plugins/`** (`Route.feedRoutes(service)`) + **servicio** sin
  Ktor (`feed/DailyFeedService`) + **repositorio JDBC** en `persistence/`.
- **Reutilizar** los mappers internos `toDomain()`/`toSummaryEntity()` y el ranker
  `HighlightRanker`; **no** duplicar lógica de destacados.
- **DTOs de transporte** en `:shared` con sufijo `Dto`, `@SerialName` explícito y
  enums de wire con token `snake_case` (patrón `CategoriaDto`).
- **Trabajo bloqueante fuera del event loop**: envolver la lectura JDBC en
  `withContext(Dispatchers.IO)` (el KDoc de `Database` lo exige).
- **Tests del gate** con dobles deterministas (`FeedRepository` en memoria) y
  `testApplication`; prueba real **opt-in** `DB_LIVE_TEST=1` (patrón existente).
- **Estilo MUST**: identificadores en inglés (KDoc en castellano), un solo `return`,
  sin `else if`, funciones ≤40 líneas, `@SerialName` explícito.

### Current Gaps

- No existe ninguna ruta de datos (`configureRouting` solo registra `/health`) ni
  capa de servicio de API.
- No hay consulta que combine `publicacion ⋈ resumen` ni que filtre por
  `estado = 'publicado'`.
- No hay contrato de transporte para destacados/destacados ni para una página.
- `Database`/`DatabaseConfig` se crean **solo** dentro de la ingesta; no hay una
  gestión de pool compartida en el composition root.

## Technical Approach

Contrato de la deriva (a partir de `CONTEXT.md`, `docs/domain-model.md`,
`docs/roadmap.md` 0.5-T01 y `DESIGN.md`): el feed es **por fecha** → `fecha` es
obligatoria; los **filtros** de categoría/rango son de FT00028 → aquí **no** hay
filtro de categoría; el `tamanoPagina` es configurable por petición; los
**destacados** se calculan *on-the-fly* sobre el día.

### 1. Contrato de transporte (`:shared`, `model/`)

- **`ResumenDiarioDto` (modify, aditivo con defaults):** se reutiliza como
  respuesta del feed añadiendo `@SerialName("destacados") highlights:
  List<HighlightDto> = emptyList()`, `@SerialName("pagina") page: Int = 1`,
  `@SerialName("tamanoPagina") pageSize: Int = 20`, `@SerialName("total") total:
  Int = 0`, `@SerialName("totalPaginas") totalPages: Int = 0`. Los campos nuevos
  tienen default, así que el wire existente sigue decodificando (los tests actuales
  siguen verdes).
- **`HighlightDto` (create):** `@SerialName("publicacion") publication:
  PublicacionDto`, `@SerialName("motivos") reasons: List<HighlightReasonDto>`.
  **No** se expone el `score` numérico (explicación objetiva, no ranking crudo).
- **`HighlightReasonDto` (create):** enum `@Serializable` de wire con token
  `snake_case` (mismo estilo que `CategoriaDto`): `NORMATIVE_SECTION =
  seccion_normativa`, `NORMATIVE_RANK = rango_normativo`, `THEMATIC_KEYWORD =
  categoria_tematica`, `OPEN_DEADLINE = plazo_abierto`, `RELEVANT_BODY =
  organismo_relevante`.
- Convención: **identificadores en inglés, tokens de wire en castellano** (el
  wire ya existente es castellano: `fecha`, `publicaciones`, `urlOficial`…).

### 2. Lectura de persistencia (`persistence/FeedRepository.kt`, create)

- `data class FeedItem(val publication: Publicacion, val summary: SummaryEntity)`
  (valor interno, sin sufijo).
- `interface FeedRepository { fun listPublishedByDate(publicationDate: String):
  List<FeedItem> }`.
- `class FeedRepositoryJdbc(dataSource)` con una sola consulta:
  `SELECT p.<columnas>, r.<columnas> FROM publicacion p JOIN resumen r ON
  r.publicacion_id = p.id WHERE p.fecha_publicacion = ?::date AND r.estado =
  'publicado' ORDER BY p.id` (parametrizada; fecha ISO con *cast* `?::date`,
  patrón de FT00017). Reutiliza los mappers internos `PublicationEntity.toDomain()`
  y `ResultSet.toSummaryEntity()`.
- **Volumen acotado**: se devuelve el día completo (no paginado en SQL) porque los
  destacados necesitan el conjunto del día y el volumen diario del BOE es de
  cientos; la paginación se hace en memoria. Si el volumen creciera, empujar el
  `LIMIT/OFFSET` a SQL es una optimización futura (documentada).
- Nota defensiva: `publicacion.categoria` es nullable en el esquema, pero FT00012
  la asigna siempre; una fila sin categoría no puede mapearse a `PublicacionDto`
  (categoría no nullable). El caso se documenta como dato corrupto (fail-fast o
  exclusión, a decidir por el implementador sin inventar categoría).

### 3. Servicio de aplicación (`feed/DailyFeedService.kt`, create)

- `class DailyFeedService(private val feedRepository: FeedRepository, private val
  highlightRanker: HighlightRanker = HighlightRanker())`.
- `suspend fun feed(date: String, page: Int = 1, pageSize: Int = DEFAULT_PAGE_SIZE):
  ResumenDiarioDto`:
  1. `require(page >= 1)` y `require(pageSize in 1..MAX_PAGE_SIZE)` (fail-fast;
     la ruta traduce a `400`).
  2. `withContext(Dispatchers.IO) { feedRepository.listPublishedByDate(date) }`
     (lectura bloqueante fuera del event loop).
  3. `highlightRanker.rank(items.map { it.publication })` → destacados del día.
  4. Ordena por `id` (ya lo hace el SQL), calcula `total`, `totalPages` (`0` si
     `total == 0`) y recorta la página `[(page-1)*pageSize, page*pageSize)`.
  5. Mapea a `ResumenDiarioDto` con `FeedDtoMapper`.
- Constantes documentadas en el `companion object`: `DEFAULT_PAGE_SIZE = 20`,
  `MAX_PAGE_SIZE = 100`.

### 4. Mapeo puro (`feed/FeedDtoMapper.kt`, create)

- `object`/funciones puras (sin red/BD/Ktor):
  - `Publicacion → PublicacionDto` (incluye `resumen` desde `SummaryEntity` y
    `plazo` desde `Publicacion.plazo`).
  - `SummaryEntity → ResumenDto` (`whatChanges→queCambia`, `whomItAffects→
    aQuienAfecta`, `keyFigures→cifrasClave`, `officialSource→fuenteOficial`,
    `aiNotice→avisoIA`; `plazo = null`: la tabla `resumen` no guarda plazo — el
    plazo fiable va en `PublicacionDto.plazo`).
  - `Highlight → HighlightDto` y `HighlightReason → HighlightReasonDto`
    (mapeo exhaustivo con `when`, sin `else if`).
- **Trazabilidad**: `PublicacionDto.urlOficial` y `ResumenDto.fuenteOficial`
  siempre presentes; `avisoIA` viaja `true` (el aviso visible es FT00033).
- Reutilizable por `api-detalle-norma` (FT00027) para el mapeo `Publicacion`.

### 5. Ruta (`plugins/Feed.kt`, create; `plugins/Routing.kt`, modify)

- `fun Route.feedRoutes(service: DailyFeedService)`: `GET /feed`.
  - Query params: `fecha` (**obligatoria**, ISO `YYYY-MM-DD`), `pagina`
    (default `1`), `tamanoPagina` (default `20`, máx `100`).
  - Valida y responde `400` si falta `fecha`, si no es ISO o si `pagina`/
    `tamanoPagina` no son enteros válidos en rango (sin cuerpo tipado; FT00030
    aportará el contrato de error).
  - `call.respond(HttpStatusCode.OK, service.feed(fecha, pagina, tamanoPagina))`.
- `configureRouting(feedService: DailyFeedService? = null)` registra `/health`
  siempre y `/feed` **solo** si `feedService != null` (patrón «solo las rutas
  cuyas dependencias existen»).

### 6. Wiring (`Application.kt`, modify)

- Crear **un único** `DataSource` en el composition root si la config de BD
  resuelve (`DatabaseConfig.fromEnv()` + `Database.createDataSource`), capturando
  el fallo (sin `POSTGRES_PASSWORD` → `null`) para **no** romper el arranque.
- Pasar el `DataSource` a `configureRouting(...)` (construyendo
  `DailyFeedService(FeedRepositoryJdbc(ds))`) **y** a la ingesta
  (`createIngestionRuntime(config, ds)`), que deja de crear y cerrar su propio
  pool: el pool lo cierra **una sola vez** el composition root en
  `ApplicationStopped`. La ingesta conserva su scope y sus clientes HTTP.
- **Sin wiring del pipeline de resumen**: FT00020–FT00023 siguen siendo librerías;
  que el feed aparezca poblado requiere un cableado posterior (ver *Risks*).

### Sin anticipar lo diferido

Sin migración (`V1`…`V5` intactas), sin cambios en `HighlightRanker`/`Highlight`
ni en `PublicacionRepository`/`SummaryRepository`, sin CORS/rate limiting/OpenAPI/
cuerpo de error (FT00029/FT00030), sin UI ni aviso visible (FT00032/FT00033), sin
dependencias Gradle nuevas, sin tocar `:composeApp`/CI/`init.sh`.

## Expected File Changes

Rutas en el repo de producto (`..`); `es/aviferdev/datopublico` se abrevia `…`:

- `shared/src/commonMain/kotlin/…/model/ResumenDiarioDto.kt` — modify; destacados
  y paginación (aditivo, con defaults).
- `shared/src/commonMain/kotlin/…/model/HighlightDto.kt` — create; destacado de wire.
- `shared/src/commonMain/kotlin/…/model/HighlightReasonDto.kt` — create; enum de wire.
- `shared/src/commonTest/kotlin/…/model/FeedContractTest.kt` — create; round-trip y
  tokens `@SerialName` de los DTOs nuevos (el gate de `:shared`).
- `backend/src/main/kotlin/…/backend/persistence/FeedRepository.kt` — create;
  `FeedItem` + interfaz + `FeedRepositoryJdbc` (`JOIN` + `estado = 'publicado'`).
- `backend/src/main/kotlin/…/backend/feed/DailyFeedService.kt` — create; servicio
  (`suspend`, paginación, destacados, constantes).
- `backend/src/main/kotlin/…/backend/feed/FeedDtoMapper.kt` — create; mapeo puro a
  `:shared`.
- `backend/src/main/kotlin/…/backend/plugins/Feed.kt` — create; `GET /feed`.
- `backend/src/main/kotlin/…/backend/plugins/Routing.kt` — modify; `configureRouting`
  admite el servicio opcional.
- `backend/src/main/kotlin/…/backend/Application.kt` — modify; pool único
  compartido + registro condicional del feed.
- `backend/src/test/kotlin/…/backend/feed/DailyFeedServiceTest.kt` — create; gate,
  `FeedRepository` en memoria (escenarios 1–6).
- `backend/src/test/kotlin/…/backend/feed/FeedDtoMapperTest.kt` — create; gate puro.
- `backend/src/test/kotlin/…/backend/plugins/FeedRouteTest.kt` — create; gate,
  `testApplication` con repositorio en memoria (200/400/404).
- `backend/src/test/kotlin/…/backend/persistence/FeedPersistenceLiveTest.kt` —
  create; **opt-in** `DB_LIVE_TEST=1` (escenario 9).
- `docs/desarrollo-local.md` (producto) — modify; endpoint feed y `curl`.

Harness (privado): `ARCHITECTURE.md`, `CONSTRAINTS.md`, ADR `0021` + índice,
`PROGRESS.md`, `feature_list.json` (ver *Durable Documentation Impact*).

Total ≈ **15 ficheros de producto** + docs: por debajo del límite de 30 → **no**
requiere división en partes `FT00026-PTn`.

## Visual Design Impact

- UI involved: no. Sin pantallas, tokens ni textos.
- Design source: `DESIGN.md` (referencia para FT00032): el feed es «bloque de
  Destacados del día arriba, luego lista» y «explicar de forma breve por qué una
  publicación es destacada»; aquí solo se produce el **contrato** (destacados +
  motivos) que la UI localizará.
- New design artifact required: no.

## Durable Documentation Impact

- `ARCHITECTURE.md`: **update** — `:shared` gana los DTOs del feed; `:backend` gana
  `feed/` (servicio) y `plugins/Feed.kt` (ruta), `persistence/FeedRepository` y el
  **pool JDBC único** compartido por API e ingesta; se documenta la frontera
  «Cliente → API HTTP (feed, solo lectura)».
- `CONSTRAINTS.md`: **update** — nueva sección **«API pública: feed diario»**:
  el feed es de **solo lectura y público** (sin cuentas); sirve **solo** resúmenes
  `estado = 'publicado'` (trazabilidad; `urlOficial`/`fuenteOficial` presentes); los
  destacados se calculan *on-the-fly* con `HighlightRanker` sin exponer `score`; la
  paginación es por `pagina`/`tamanoPagina` con default/máximo documentados; el
  arranque sigue sin depender de la BD (ruta registrada solo si hay pool) y el pool
  se cierra una vez; **sin** CORS/rate limit/OpenAPI/cuerpo de error (FT00029/
  FT00030) ni migración.
- `AGENTS.md`: **not needed** — no cambia el flujo, el arranque ni las reglas.
- Other docs: `docs/adr/0021-feed-diario-endpoint.md` — **create** (decisión
  durable: contrato de feed por fecha, solo `publicado`, destacados *on-the-fly*,
  paginación en memoria, pool único) + índice `docs/adr/README.md`;
  `.agents/skills/ktor-backend-architecture/SKILL.md` — **update** opcional
  (sección API: ruta feed + pool compartido); `docs/desarrollo-local.md` —
  **update**.

## Implementation Plan

1. Definir el contrato en `:shared` (`HighlightReasonDto`, `HighlightDto`,
   `ResumenDiarioDto` ampliado) con `@SerialName` explícito y su test de gate.
2. Crear `FeedRepository` (interfaz + `FeedItem` + `FeedRepositoryJdbc`) con el
   `JOIN` y el filtro `estado = 'publicado'`, reutilizando los mappers internos.
3. Crear `FeedDtoMapper` (puro) con sus tests.
4. Crear `DailyFeedService` (`suspend`, paginación, destacados) con su test de gate
   de dobles (escenarios 1–6).
5. Crear `plugins/Feed.kt` (`GET /feed`) y `FeedRouteTest` (`testApplication`).
6. Modificar `Routing.kt`/`Application.kt` (pool único + registro condicional);
   verificar `/health` sin BD y el arranque con BD.
7. Añadir `FeedPersistenceLiveTest` (**opt-in** `DB_LIVE_TEST=1`).
8. Pasar el gate sin red ni BD y actualizar `ARCHITECTURE.md`, `CONSTRAINTS.md`,
   ADR 0021 + índice, `docs/desarrollo-local.md`; `PROGRESS.md`/`feature_list.json`
   los cierra el orquestador.

## Implementation Tasks

- [ ] `:shared`: `HighlightReasonDto`, `HighlightDto`, `ResumenDiarioDto` ampliado
      (aditivo) + `FeedContractTest`.
- [ ] `persistence/FeedRepository` (`FeedItem` + `Jdbc`, `JOIN` + `estado =
      'publicado'`, orden por `id`, `?::date`).
- [ ] `feed/FeedDtoMapper` (puro: `Publicacion`/`SummaryEntity`/`Highlight` → `Dto`).
- [ ] `feed/DailyFeedService` (`suspend`, `withContext(Dispatchers.IO)`, paginación,
      `HighlightRanker`, `DEFAULT_PAGE_SIZE`/`MAX_PAGE_SIZE`).
- [ ] `plugins/Feed.kt` (`GET /feed`, validación de `fecha`/`pagina`/`tamanoPagina`,
      400/200) + `Routing.kt`.
- [ ] `Application.kt`: pool JDBC único compartido API/ingesta, registro condicional.
- [ ] Tests de gate: servicio (escenarios 1–6), mapper y ruta (200/400/404).
- [ ] `FeedPersistenceLiveTest` opt-in (`DB_LIVE_TEST=1`, escenario 9).
- [ ] Docs: `ARCHITECTURE.md`, `CONSTRAINTS.md`, ADR 0021 + índice,
      `docs/desarrollo-local.md`.

## Verification Plan

Desde la raíz del producto (`..`, JDK 21 vía JBR/`JAVA_HOME`):

- **Gate sin red ni BD (obligatorio)**: `./gradlew :backend:test --rerun-tasks` y
  `./gradlew :shared:jvmTest` → BUILD SUCCESSFUL con los tests nuevos en verde y el
  resto intacto; `./gradlew build --no-daemon -PskipClient` (incluye `detekt` +
  `:cpdCheck`), `./gradlew test`, `./gradlew detekt` y `env -u JAVA_HOME
  .harness/init.sh` → exit 0.
- **Rutas (gate)**: `FeedRouteTest` con `testApplication` y un `FeedRepository` en
  memoria comprueba `200` (JSON con `fecha`/`destacados`/`publicaciones`/`pagina`),
  `400` por `fecha` ausente/mal formada y por paginación inválida, y `404` cuando no
  se registra el servicio.
- **Servicio (gate)**: `DailyFeedServiceTest` cubre día mixto, solo publicados,
  paginación (incluida página fuera de rango), día vacío, determinismo y motivos no
  vacíos.
- **Arranque sin BD**: `./gradlew :backend:run` sin `POSTGRES_PASSWORD` → `/health`
  200 y `/feed` 404; con BD, el feed responde y el pool se comparte con la ingesta.
- **Escenario 9 (opt-in, fuera del gate y de la CI)**:
  ```sh
  cp .env.example .env
  docker compose up -d
  ./gradlew :backend:flywayMigrate
  DB_LIVE_TEST=1 ./gradlew :backend:test --tests '*FeedPersistenceLiveTest'
  docker compose down -v
  ```
  Esperado: solo aparece la publicación con resumen `publicado`, con su resumen.
- **E2E**: no aplica — el repo no tiene comando E2E persistente (el cliente es
  Compose Multiplatform y aún no consume `:shared`); el flujo de API se cubre con
  `testApplication` en el gate.
- `init.sh` (harness): **no** se modifica.

## Evidence To Capture

- Salida de los tests nuevos (`:shared:jvmTest` y `:backend:test`) con recuento y 0
  fallos, y del gate (`build -PskipClient`, `test`, `detekt`, `init.sh` exit 0).
- Ejemplo real de respuesta `GET /feed` (publicación con `resumen`, `categoria`,
  `urlOficial`, `plazo` y `destacados` con `motivos`) y de día vacío.
- Confirmación de que `Application.kt` arranca sin BD (`/health` 200, `/feed` 404)
  y de que `HighlightRanker`/`Publicacion`/`PublicacionDto`/`ResumenDto`/migraciones
  quedan sin cambios de contrato.
- Salida del test opt-in `FeedPersistenceLiveTest` (solo publicados).
- Ficheros del commit `FT00026`, PR y run de CI; entradas en `PROGRESS.md` y
  `feature_list.json` (`evidence`).

## Validator Checklist

- [ ] Alcance acotado: solo contrato de feed en `:shared`, `feed/`,
      `persistence/FeedRepository`, `plugins/Feed`/`Routing` y el wiring de
      `Application.kt`; **sin** generación de resúmenes, **sin** filtros de
      búsqueda, **sin** detalle/chat, **sin** CORS/rate limit/OpenAPI, **sin** UI,
      **sin** migración.
- [ ] Escenarios 1–9 pasan; **todo el gate corre sin red ni BD** y la prueba real
      se omite sin `DB_LIVE_TEST`.
- [ ] El feed sirve **solo** resúmenes `estado = 'publicado'`; las publicaciones sin
      resumen publicado no aparecen ni cuentan en `total`.
- [ ] Cada publicación trae `resumen`, `categoria` y `urlOficial`; los destacados
      traen `motivos` no vacíos y **no** exponen `score`; el resultado es
      determinista.
- [ ] Paginación por `pagina`/`tamanoPagina` con default/máximo documentados;
      `fecha` obligatoria ISO; parámetros inválidos → 400; día vacío → 200.
- [ ] El arranque **no** depende de la BD (ruta condicional, `/health` operativo) y
      el pool JDBC se crea una vez y se cierra una vez.
- [ ] La lectura JDBC bloqueante se ejecuta fuera del event loop
      (`Dispatchers.IO`); SQL parametrizado (sin concatenar entrada), sin secretos.
- [ ] DTOs `Dto` con `@SerialName` explícito, tokens de wire estables y sufijo `Dto`;
      `return` único, sin `else if`, funciones ≤40 líneas, KDoc en castellano con
      identificadores en inglés.
- [ ] `ARCHITECTURE.md`, `CONSTRAINTS.md`, ADR 0021 + índice,
      `docs/desarrollo-local.md`, `PROGRESS.md` y `feature_list.json` actualizados.
- [ ] Sin comportamiento de producto no relacionado ni ficheros fuera de alcance.

## Risks / Open Questions

- **Dependencia implícita de FT00023.** El feed filtra por `estado = 'publicado'`,
  que solo escribe `cola-revision-confianza` (FT00023). Añadir
  `cola-revision-confianza` a `depends_on` (lo aplica el orquestador).
- **Feed vacío sin el pipeline cableado.** FT00020–FT00023 son librerías sin
  wiring: nada escribe resúmenes `publicado` en runtime todavía, así que en
  producción el feed saldrá vacío hasta que exista un cableado del pipeline
  generación → guardrails → disposición. **No hay una feature en
  `feature_list.json` que lo cubra**: es un gap de planificación a resolver por el
  orquestador (esta feature es solo el endpoint). Se documenta como no-objetivo.
- **Paginación en memoria.** Se carga el día completo para rankear destacados y se
  pagina en memoria; con el volumen diario del BOE (cientos) es trivial en el N100.
  Si creciera, empujar `LIMIT/OFFSET` a SQL es una optimización futura.
- **`fecha` obligatoria frente a «hoy» por defecto.** Se exige `fecha` para no
  introducir un reloj/zona en el servidor (endpoint determinista y testeable); el
  cliente (FT00032) puede enviar «hoy» localmente. Alternativa descartada por ahora:
  default = fecha más reciente con contenido (requeriría `fecha` nullable).
- **`ResumenDto.plazo` no persistido.** La tabla `resumen` no guarda plazo; el
  plazo fiable viaja en `PublicacionDto.plazo`. Si se quiere el plazo del resumen,
  sería una extensión de esquema posterior (fuera de alcance).
- **Categoría nullable en el esquema.** FT00012 garantiza categoría; una fila sin
  categoría no mapea a `PublicacionDto` (categoría no nullable). Decidir
  exclusión/fail-fast sin inventar una categoría.
- **Refactor del wiring.** Compartir un único pool entre API e ingesta cambia
  `Application.kt` y `createIngestionRuntime`; el gate debe quedar verde y
  `/health` operativo sin BD. Es la parte con más riesgo de regresión.
- **Path sin versión.** Se usa `/feed` (coherente con `/health`); el
  versionado/OpenAPI del path es FT00029 y puede añadir el prefijo.
- **División.** ≈15 ficheros: muy por debajo de 30 → **atómica**; no se recomienda
  partir en `FT00026-PTn`.
