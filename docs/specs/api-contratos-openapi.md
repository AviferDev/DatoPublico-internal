# Feature Implementation Spec: Contratos OpenAPI y versionado de API

## Source Feature

- `id`: api-contratos-openapi
- `ft_id`: FT00029 (registrado en `docs/feature-ids.md`)
- `parts`: none (atómica; ≈10–11 ficheros de producto, muy por debajo del límite de 30)
- `area`: api-publica
- `depends_on`: api-feed-diario (FT00026, `accepted`) + api-detalle-norma
  (FT00027, `accepted`) + api-busqueda (FT00028, `accepted`) + api-chat (FT00031,
  `accepted`). **`depends_on` ya está completo**; no hace falta añadir ninguna
  dependencia (ver *Dependencias* más abajo).
- `status`: not_started (al planificar)
- `source`: `feature_list.json` (`notes`: `docs/roadmap.md` 0.5-T04)
- `claim`: rama `feat/ft00029-api-contratos-openapi` ya reclamada en `origin`
  (`09572a8 chore(FT00029): claim api-contratos-openapi`), **apilada sobre
  `feat/ft00031-api-chat`** (`4fdcb8f`); sin PR abierto aún.

> **Base de rama (riesgo crítico de planificación).** La pila actual
> (`feat/ft00029` → `feat/ft00031` → `defd04f`) contiene **tres** endpoints de
> datos (`/feed`, `/publicacion/{id}`, `/chat`) pero **NO contiene `/buscar`**: la
> rama `feat/ft00031-api-chat` se cortó de `defd04f` (FT00027) y FT00028
> (`GET /buscar`) está en `origin/main` (`bfa8b87`) pero **no** en la base de la
> pila. Verificado con `git ls-tree HEAD …/plugins/` (sin `Search.kt`).
> La verificación de FT00029 exige describir **feed, detalle, búsqueda y chat**, así
> que **la base debe incluir FT00028**. El orquestador debe resolverlo antes de
> implementar: (a) rebasar `feat/ft00031-api-chat` sobre `origin/main` (que ya
> incluye FT00028) y luego rebasar `feat/ft00029` encima, o (b) esperar al merge
> del PR #30 (FT00031) y basar FT00029 sobre el `main` resultante. El planner **no**
> edita `feature_list.json` ni ramas.

> **Dependencias.** Las cuatro features de `depends_on` están `accepted`. El
> contrato **reutiliza** los DTOs de `:shared` ya congelados
> (`PublicacionDto`/`ResumenDto`/`ResumenDiarioDto`/`HighlightDto`/
> `HighlightReasonDto`/`CategoriaDto`/`SeccionBoeDto`/`PlazoDto`/`SearchResultsDto`
> de FT00028 y `Chat*Dto` de FT00031) y **no** introduce contrato nuevo de dominio.
> `embeddings-locales-onnx` (FT00015) y `recuperacion-hibrida` (FT00017) quedan
> cubiertos transitivamente por FT00028/FT00031; **no** se añaden a `depends_on`.

## Goal

Publicar, en `:backend`, los **contratos OpenAPI** de los endpoints de datos ya
existentes (tarea `0.5-T04`) y fijar una **versión de API** coherente que los
clientes puedan consumir de forma estable antes de que se construya la UI (0.6.0).

La feature introduce un **documento OpenAPI 3.1 versionado** en los recursos del
backend, una **ruta de solo lectura** que lo sirve por HTTP y una **versión de API
en el path** (`/v1`) para los endpoints de dominio, manteniendo `/health` y el
propio documento sin versionar. **No** genera código ni esquemas desde las rutas
(la generación en tiempo de compilación exige Kotlin ≥ 2.2.20 y el proyecto fija
2.1.20): el documento es un artefacto **estático, versionado y revisable**, y un
**test de gate anti-deriva** lo mantiene alineado con los DTOs `Dto` de `:shared` y
con las rutas realmente registradas.

## Non-Goals

- **Rate limiting, CORS y cuerpo de error tipado** (FT00030): el contrato documenta
  los códigos (`400`/`404`/`500`/`502`) **sin** esquema de error; el endurecimiento
  HTTP es FT00030.
- **Generación automática** del documento (compilador/Gradle de Ktor, anotaciones
  de rutas o `ktor-openapi-tools`): exige Kotlin ≥ 2.2.20 (el proyecto usa 2.1.20)
  o dependencias nuevas; se descarta (ver *Technical Approach* y *Risks*).
- **Swagger UI / ReDoc interactivos**: no los pide la verificación y añadirían
  artefactos y superficie; quedan como feature futura opcional.
- **Cambiar los contratos de dominio** (`:shared`): los DTOs se **reutilizan**
  tal cual; no se añade, renombra ni reescribe ningún `Dto`.
- **Cablear el pipeline de resumen o el indexado del corpus**: gaps de
  planificación ya registrados (Sessions 068/070).
- **Tocar `:composeApp`/CI/`init.sh`**, ni añadir migración (`V1`…`V5` intactas), ni
  dependencias Gradle nuevas, ni modificar el job/backfill ni `rag/*`.
- **Rediseñar las rutas**: el versionado solo **prefija** `/v1` a las rutas de
  dominio existentes; no cambia métodos, parámetros ni semántica.

## Job Story

When integro un cliente contra la API pública del BOE,
I want disponer de un contrato OpenAPI versionado y de rutas con una versión
explícita, que describan exactamente feed, detalle, búsqueda y chat,
so I can generar/verificar clientes y consumir la API de forma estable sin que un
cambio del contrato me rompa en silencio.

## Users And Permissions

- **Ciudadanía (usuario final):** anónima, solo lectura; sin cuentas ni datos
  personales; el contrato y las rutas son públicos.
- **Cliente CMP (FT00032+):** consumidor del contrato `:shared`; usa el documento
  como referencia y las rutas `/v1/…`.
- **Operador/desarrollador:** arranca el backend (con o sin BD) y consulta
  `/openapi.json`; ejecuta el gate.
- Sin autenticación, sin autorización y sin escritura.

## Acceptance Scenarios

### Scenario 1: el contrato se sirve y es OpenAPI válido

Given el backend arrancado (con o sin base de datos),
When `GET /openapi.json`,
Then responde `200` con `Content-Type: application/json`, un JSON que parsea y
declara `openapi` 3.1.x, `info.title` y `info.version = "0.5.0"`, y describe los
**cuatro** endpoints de dominio (`/v1/feed`, `/v1/publicacion/{id}`, `/v1/buscar`,
`/v1/chat`) y `/health`.

### Scenario 2: versionado explícito de las rutas de dominio

Given el backend con sus dependencias (BD, modelo, clave),
When se llama a los endpoints de dominio,
Then responden bajo el prefijo `/v1` (`GET /v1/feed`, `GET /v1/publicacion/{id}`,
`GET /v1/buscar`, `POST /v1/chat`); `/health` y `GET /openapi.json` **no** llevan
prefijo; una ruta de dominio **sin** `/v1` (p. ej. `GET /feed`) responde `404`.

### Scenario 3: el contrato no deriva de los DTOs `Dto`

Given el documento OpenAPI y los DTOs de `:shared`,
When el test de gate compara los esquemas documentados con los contratos,
Then los nombres de propiedad de cada esquema (`PublicacionDto`, `ResumenDto`,
`ResumenDiarioDto`, `HighlightDto`, `SearchResultsDto`, `ChatRequestDto`,
`ChatResponseDto`, `ChatCitationDto`) coinciden con los `@SerialName` de sus
`serializer().descriptor.elementNames`, y los valores de los enums de wire
(`CategoriaDto`, `SeccionBoeDto`, `HighlightReasonDto`, `ChatStatusDto`) coinciden
con sus tokens; una divergencia **falla** el test.

### Scenario 4: los códigos se documentan sin cuerpo de error tipado

Given cada endpoint,
When se documentan sus respuestas,
Then figuran `200` (y `400`/`404` en los que aplican, y `500`/`502` en `/v1/chat`)
**sin** un esquema de error compartido; el contrato de error tipado es FT00030.

### Scenario 5: arranque sin BD intacto

Given un entorno sin `POSTGRES_PASSWORD` (o sin modelo/clave para `/v1/chat`),
When arranca el backend,
Then `/health` responde `200`, `/openapi.json` responde `200` (no depende de
servicios externos) y las rutas de dominio no registradas responden `404`; con las
dependencias presentes, las rutas `/v1/…` se registran como hasta ahora.

### Scenario 6: el gate sigue sin red, BD, modelo ni OpenCode

Given el runner de CI sin PostgreSQL, sin Docker, sin el modelo E5 y sin
`OPENCODE_API_KEY`,
When se ejecuta `./gradlew build -PskipClient`, `./gradlew test`, `./gradlew
detekt` o `.harness/init.sh`,
Then todo está en verde; el contrato se sirve desde los recursos (sin red) y los
tests usan dobles deterministas.

### Scenario 7: sin dependencias nuevas ni migración

Given el árbol de build actual,
When se aplica la feature,
Then `gradle/libs.versions.toml` y `backend/build.gradle.kts` **no** añaden
dependencias ni plugins, las migraciones `V1`…`V5` quedan intactas y
`:composeApp`/CI/`init.sh` no se tocan.

## Repository Research

### Files Inspected

- Git: rama `feat/ft00029-api-contratos-openapi` (`09572a8`) apilada sobre
  `feat/ft00031-api-chat` (`4fdcb8f`), base común `defd04f` (FT00027);
  `origin/main` = `bfa8b87` (FT00028). `git ls-tree HEAD` confirma que **falta**
  `plugins/Search.kt` en la pila. PR #30 (FT00031) abierto hacia `main`.
- `backend/.../plugins/Routing.kt` — `configureRouting(feedService, detailService,
  chatService)` registra `/health` siempre y cada ruta **solo** si su servicio no
  es `null`; es el punto donde se añade el prefijo `/v1` y la ruta del documento.
- `backend/.../plugins/Health.kt` — `GET /health` → `200 {"status":"ok"}` con
  `HealthDto` (en `:backend`, no en `:shared`); no depende de BD. Operacional.
- `backend/.../plugins/Feed.kt` — `GET /feed`; `fecha` ISO obligatoria,
  `pagina`/`tamanoPagina` (default `20`, máx `100`), `400` sin cuerpo; respuesta
  `ResumenDiarioDto`.
- `backend/.../plugins/PublicationDetail.kt` — `GET /publicacion/{id}`; `id`
  opaco, `400`/`404`, respuesta `PublicacionDto`.
- `backend/.../plugins/Chat.kt` — `POST /chat`; cuerpo `ChatRequestDto`; `200`
  (incl. `sin_fundamento`), `400`, `404`, `502`, `500` sin cuerpo; respuesta
  `ChatResponseDto`.
- `origin/main:backend/.../plugins/Search.kt` — `GET /buscar` (FT00028); `q`
  obligatoria + filtros `categoria`/`desde`/`hasta`/`limite` (default `10`, máx
  `50`), `400` sin cuerpo; respuesta `SearchResultsDto`. **No está en la base
  actual de la pila** (ver *Base de rama*).
- `backend/.../Application.kt` — composition root con pool JDBC único y wiring
  condicional (embeddings, OpenCode); `configureRouting(...)`; cierre único.
- `shared/.../model/*.kt` — contrato de wire con sufijo `Dto` y `@SerialName`
  explícito: `PublicacionDto`, `ResumenDto`, `ResumenDiarioDto`, `HighlightDto`,
  `HighlightReasonDto`, `PlazoDto`, `CategoriaDto`, `SeccionBoeDto` y, de
  FT00031, `ChatRequestDto`/`ChatResponseDto`/`ChatStatusDto`/`ChatCitationDto`;
  `SearchResultsDto` de FT00028. `DatoPublicoJson` (`ignoreUnknownKeys`,
  `encodeDefaults`) en `serialization/`.
- `backend/build.gradle.kts` + `gradle/libs.versions.toml` — Kotlin **2.1.20**,
  Ktor **3.0.3**, `:shared` ya dependencia, `ktor-server-test-host` en test;
  **sin** artefacto OpenAPI ni plugin de compilador.
- `backend/src/test/kotlin/.../plugins/{FeedRouteTest,PublicationDetailRouteTest,
  ChatRouteTest}.kt` — patrón `testApplication { application { … configureRouting(…) } }`
  con dobles; las peticiones usan las rutas **sin** prefijo (deberán pasar a
  `/v1/…`). `HealthTest.kt` usa `/health` (no cambia).
- Producto: `docs/desarrollo-local.md` — guía de `curl` donde documentar
  `/openapi.json` y el prefijo `/v1`.
- Harness: `feature_list.json` (FT00029), `PROGRESS.md` (Sessions 066–071),
  `docs/feature-ids.md`, `docs/roadmap.md` §0.5 (`0.5-T04`),
  `docs/technical-discovery.md`, `CONTEXT.md`, `ARCHITECTURE.md`,
  `CONSTRAINTS.md` (§«API pública: feed/detalle/búsqueda/chat»), ADR 0003/0008/
  0021/0022/0023/0024 y los specs `api-feed-diario.md`, `api-detalle-norma.md`,
  `api-busqueda.md`, `api-chat.md`; skills `feature-spec` y
  **`ktor-backend-architecture`** (§«Layout de paquetes»: ya prevé
  `backend/src/main/resources/openapi/openapi.json`; §«API»: «Contratos OpenAPI
  versionados»).
- Ktor (documentación oficial): el **compilador OpenAPI** de Ktor exige
  **Kotlin ≥ 2.2.20**; `ktor-server-openapi` solo **sirve/renderiza** un documento
  existente (no genera esquemas desde los DTOs). No se instala.

### Existing Patterns To Follow

- **Ruta delgada en `plugins/`** (`fun Route.openApiRoutes()`), sin lógica de
  negocio, coherente con `healthRoutes()`/`feedRoutes(...)`.
- **Registro condicional** de rutas en `configureRouting(...)`; `/health` y el
  documento se registran **siempre** (sin dependencias externas).
- **Artefacto versionado en recursos**: patrón ya usado por el *golden set*
  (`rag/eval/golden-set.json`), servido desde el classpath.
- **Tests de gate con `testApplication`** y `DatoPublicoJson` para parsear; sin
  red ni BD.
- **Estilo MUST**: identificadores en inglés (KDoc en castellano), un solo
  `return`, sin `else if`, funciones ≤40 líneas, `@SerialName` explícito.

### Current Gaps

- **No existe** ningún documento OpenAPI ni ruta que lo sirva.
- **No hay** versión en las rutas: los endpoints de dominio son `/feed`,
  `/publicacion/{id}`, `/buscar`, `/chat` (sin `/v1`), decisión que el ADR 0022
  dejó explícitamente a FT00029.
- **No hay** un test que impida que el contrato derive de los DTOs.
- La base de la pila **no contiene** `/buscar` (FT00028), pese a que la
  verificación de FT00029 lo exige (ver *Base de rama*).

## Technical Approach

Deriva de `docs/roadmap.md` 0.5-T04 («Contratos OpenAPI y versionado de API»),
`docs/roadmap.md` §0.5 (criterio de salida: «los clientes pueden consumir feed,
detalle, búsqueda y chat»), `CONSTRAINTS.md` y la skill
`ktor-backend-architecture` (§«API»: «Contratos OpenAPI versionados»).

### Decisiones (fijadas en el ADR 0025)

1. **Sin dependencia Gradle nueva.** La generación en tiempo de compilación de
   Ktor exige **Kotlin ≥ 2.2.20** (el proyecto fija **2.1.20**): subir Kotlin es
   *scope creep* y riesgo. `ktor-server-openapi`/`ktor-openapi-tools` solo
   **sirven** un documento (no generan esquemas desde los DTOs) y añaden artefactos
   y superficie. Se elige un **documento estático versionado** + una ruta mínima +
   un test anti-deriva, que mantienen el gate **offline** y sin dependencias.
2. **El documento vive en recursos** (`backend/src/main/resources/openapi/
   openapi.json`, ya previsto por la skill de backend) y se sirve en
   `GET /openapi.json` (**sin** versión: es meta/operacional y estable).
3. **Versionado en el path**: los endpoints de **dominio** pasan a `/v1/…`
   (`/v1/feed`, `/v1/publicacion/{id}`, `/v1/buscar`, `/v1/chat`). `/health` y
   `/openapi.json` quedan **sin** prefijo (operacionales, fuera del contrato
   versionado). `info.version = "0.5.0"` refleja el hito que agrupa los endpoints.
   Es el **último momento barato** para versionar (la UI 0.6.0 aún no existe) y el
   ADR 0022 difirió explícitamente esta decisión a FT00029.
4. **Política de versionado** (durable, en el ADR y `CONSTRAINTS.md`): cambios
   **aditivos y compatibles** mantienen `/v1` y suben la *minor/patch* de
   `info.version`; un cambio **incompatible** exige un prefijo nuevo (`/v2`) con
   `/v1` conservado hasta su deprecación. El documento es la **fuente de verdad**
   del contrato; los DTOs `Dto` de `:shared` son su implementación.

### 1. Documento OpenAPI (`backend/src/main/resources/openapi/openapi.json`, create)

- OpenAPI **3.1.0** en JSON, `info.title = "DatoPublico API"`,
  `info.version = "0.5.0"`, descripción (público, solo lectura, sin cuentas ni
  datos personales, enlace siempre a la fuente oficial), `servers = [{ "url": "/" }]`.
- `paths` (rutas **completas**, con prefijo):
  - `GET /v1/feed` → `200` `ResumenDiarioDto`; `400`. Params `fecha` (obligatoria,
    ISO), `pagina`, `tamanoPagina`.
  - `GET /v1/publicacion/{id}` → `200` `PublicacionDto`; `400`, `404`. Path param
    `id` (opaco, p. ej. `BOE-A-2026-20979`).
  - `GET /v1/buscar` → `200` `SearchResultsDto`; `400`. Params `q` (obligatoria),
    `categoria`, `desde`, `hasta`, `limite`.
  - `POST /v1/chat` → `200` `ChatResponseDto`; `400`, `502`, `500`. Cuerpo
    `ChatRequestDto`.
  - `GET /health` → `200` `HealthDto` (operacional, sin versión).
  - `GET /openapi.json` → `200` (meta; puede documentarse como operacional).
- `components.schemas`: espejo **exacto** de los DTOs de wire (`PublicacionDto`,
  `ResumenDto`, `PlazoDto`, `ResumenDiarioDto`, `HighlightDto`,
  `HighlightReasonDto`, `CategoriaDto`, `SeccionBoeDto`, `SearchResultsDto`,
  `ChatRequestDto`, `ChatResponseDto`, `ChatStatusDto`, `ChatCitationDto`,
  `HealthDto`), con los **mismos nombres de propiedad** que sus `@SerialName` y
  los **mismos tokens** de enum. **Sin** esquema de error (FT00030).
- **Sin** secretos, sin `usage`, sin detalle de implementación.

### 2. Ruta que sirve el documento (`plugins/OpenApi.kt`, create)

- Carga el recurso **una sola vez** desde el classpath (fail-fast en arranque si
  falta; el test lo cubre) y lo sirve como `application/json`:
  `fun Route.openApiRoutes()` → `GET /openapi.json`.
- No depende de BD/modelo/clave: se registra **siempre**.

### 3. Versionado en `Routing.kt` (modify)

- `configureRouting(...)` anida las rutas de **dominio** bajo `route("/v1") { … }`
  (reutilizando `feedRoutes`/`publicationDetailRoutes`/`searchRoutes`/`chatRoutes`
  **sin** modificarlas) y registra `healthRoutes()` + `openApiRoutes()` en la raíz.
- `searchService` se añade como colaborador **opcional** (aditivo, default `null`)
  **solo si la base incluye FT00028**; si no, la base debe corregirse (ver *Base de
  rama*) y el implementador **no** debe inventar `/buscar`.
- Los tests de ruta existentes actualizan su URL (`/feed`→`/v1/feed`,
  `/publicacion/{id}`→`/v1/publicacion/{id}`, `/buscar`→`/v1/buscar`,
  `/chat`→`/v1/chat`); `HealthTest` no cambia.

### 4. Test anti-deriva (`plugins/OpenApiContractTest.kt`, create)

- Con `testApplication`, `GET /openapi.json` → `200` y JSON parseable con
  `DatoPublicoJson`/`Json.parseToJsonElement`.
- Asserts: `openapi` 3.1.x, `info.version`, y las rutas `/v1/feed`,
  `/v1/publicacion/{id}`, `/v1/buscar`, `/v1/chat`, `/health`.
- **Anti-deriva**: para cada DTO principal, el conjunto de claves del esquema
  documentado == `serializer().descriptor.elementNames` (los `@SerialName`); para
  cada enum de wire, los valores == sus tokens. Divergencia ⇒ test rojo.

### Sin anticipar lo diferido

Sin dependencias Gradle nuevas, sin migración (`V1`…`V5` intactas), sin cambios en
los DTOs de `:shared` ni en `rag/*`/`persistence/*`/`Application.kt` (salvo el
`configureRouting` ya previsto), sin CORS/rate limiting/cuerpo de error (FT00030),
sin Swagger UI, sin UI (FT00032+) y sin tocar `:composeApp`/CI/`init.sh`.

## Expected File Changes

Rutas en el repo de producto (`..`); `es/aviferdev/datopublico` se abrevia `…`:

- `backend/src/main/resources/openapi/openapi.json` — create; documento OpenAPI 3.1.
- `backend/src/main/kotlin/…/backend/plugins/OpenApi.kt` — create; `GET /openapi.json`.
- `backend/src/main/kotlin/…/backend/plugins/Routing.kt` — modify; prefijo `/v1`,
  ruta del documento y colaborador opcional `searchService`.
- `backend/src/test/kotlin/…/backend/plugins/OpenApiRouteTest.kt` — create; gate
  (200, JSON, rutas documentadas).
- `backend/src/test/kotlin/…/backend/plugins/OpenApiContractTest.kt` — create;
  anti-deriva DTOs/enums.
- `backend/src/test/kotlin/…/backend/plugins/FeedRouteTest.kt` — modify; `/v1/feed`.
- `backend/src/test/kotlin/…/backend/plugins/PublicationDetailRouteTest.kt` —
  modify; `/v1/publicacion/{id}`.
- `backend/src/test/kotlin/…/backend/plugins/ChatRouteTest.kt` — modify; `/v1/chat`.
- `backend/src/test/kotlin/…/backend/plugins/SearchRouteTest.kt` — modify;
  `/v1/buscar` (**requiere que la base incluya FT00028**).
- `docs/desarrollo-local.md` (producto) — modify; `/openapi.json`, prefijo `/v1` y
  `curl` de ejemplo.

Harness (privado): `ARCHITECTURE.md`, `CONSTRAINTS.md`, ADR `0025` + índice, skill
`ktor-backend-architecture`, `PROGRESS.md`, `feature_list.json` (ver *Durable
Documentation Impact*).

Total ≈ **10–11 ficheros de producto/código**: muy por debajo del límite de 30 →
**no** requiere división en partes `FT00029-PTn`.

## Visual Design Impact

- UI involved: no. Sin pantallas, tokens ni textos.
- Design source: no aplica.
- Screens or states affected: ninguno.
- New design artifact required: no.

## Durable Documentation Impact

- `ARCHITECTURE.md`: **update** — la frontera «Cliente → API HTTP» incorpora el
  **contrato OpenAPI** (`/openapi.json`) y el prefijo **`/v1`** de las rutas de
  dominio; `:backend` gana `plugins/OpenApi.kt` y el recurso
  `src/main/resources/openapi/openapi.json`.
- `CONSTRAINTS.md`: **update** — nueva sección **«API pública: contratos y
  versionado»**: el contrato es **público, de solo lectura** y versionado
  (`/v1/…` para dominio; `/health` y `/openapi.json` sin versión); el documento es
  la **fuente de verdad** del contrato y los DTOs `Dto` de `:shared` su
  implementación, con un **test anti-deriva** obligatorio; cambios aditivos
  mantienen `/v1` y suben `info.version`, un cambio incompatible exige `/v2`;
  **sin** dependencia Gradle de OpenAPI ni generación en compilación; los códigos
  de error se documentan **sin** esquema (FT00030).
- `AGENTS.md`: **not needed** — no cambia el flujo, el arranque ni las reglas.
- Other docs: `docs/adr/0025-openapi-contrato-versionado.md` — **create**
  (documento estático versionado, `/v1`, política de versionado, sin dependencia
  Gradle, test anti-deriva) + índice `docs/adr/README.md`;
  `.agents/skills/ktor-backend-architecture/SKILL.md` — **update** (§«API» y
  §«Estado actual»: contrato + `/v1`); `docs/desarrollo-local.md` — **update**.

## Implementation Plan

1. **Verificar la base**: confirmar que el árbol incluye `/buscar` (FT00028); si
   no, parar y reportar al orquestador (ver *Base de rama*).
2. Escribir `openapi.json` (OpenAPI 3.1) con las rutas `/v1/…` + `/health` y los
   esquemas espejo de los DTOs (nombres y tokens exactos).
3. Crear `plugins/OpenApi.kt` (`GET /openapi.json`) y registrarlo en
   `Routing.kt`; anidar las rutas de dominio bajo `route("/v1")` y añadir
   `searchService` opcional.
4. Crear `OpenApiRouteTest` y `OpenApiContractTest` (anti-deriva) en el gate.
5. Actualizar las URLs de los tests de ruta existentes a `/v1/…`.
6. Pasar el gate sin red/BD/modelo/OpenCode; actualizar `ARCHITECTURE.md`,
   `CONSTRAINTS.md`, ADR 0025 + índice, la skill y `docs/desarrollo-local.md`;
   `PROGRESS.md`/`feature_list.json` los cierra el orquestador.

## Implementation Tasks

- [ ] Verificar que la base incluye FT00028 (`/buscar`); si no, reportar y parar.
- [ ] `backend/src/main/resources/openapi/openapi.json` (3.1, `/v1/…` + `/health`,
      esquemas espejo de los DTOs).
- [ ] `plugins/OpenApi.kt` (`GET /openapi.json`, carga única del recurso,
      fail-fast).
- [ ] `plugins/Routing.kt`: `route("/v1") { … }` + `healthRoutes()` +
      `openApiRoutes()`; `searchService` opcional (aditivo).
- [ ] `OpenApiRouteTest` (200/JSON/rutas) y `OpenApiContractTest` (anti-deriva).
- [ ] Actualizar `FeedRouteTest`/`PublicationDetailRouteTest`/`ChatRouteTest`
      (`/v1/…`) y `SearchRouteTest` (`/v1/buscar`).
- [ ] Docs: `ARCHITECTURE.md`, `CONSTRAINTS.md`, ADR 0025 + índice, skill,
      `docs/desarrollo-local.md`.

## Verification Plan

Desde la raíz del producto (`..`, JDK 21 vía JBR/`JAVA_HOME`):

- **Gate sin red, BD, modelo ni OpenCode (obligatorio)**: `./gradlew :backend:test
  --rerun-tasks` y `./gradlew :shared:jvmTest` → BUILD SUCCESSFUL con los tests
  nuevos en verde (0 fallos) y el resto intacto; `./gradlew build --no-daemon
  -PskipClient` (incluye `detekt` + `:cpdCheck`), `./gradlew test`, `./gradlew
  detekt` y `env -u JAVA_HOME .harness/init.sh` → exit 0.
- **Contrato (gate)**: `OpenApiRouteTest` comprueba `GET /openapi.json` → `200`
  `application/json` y JSON válido; `OpenApiContractTest` comprueba `info.version`,
  las rutas documentadas y la **coincidencia esquema↔DTO** (nombres de propiedad y
  tokens de enum).
- **Versionado (gate)**: los tests de ruta de dominio usan `/v1/…`; `HealthTest`
  sigue con `/health`; una ruta sin `/v1` da `404` (assert en el test de la ruta
  correspondiente o en `OpenApiRouteTest`).
- **Arranque sin BD/modelo/clave**: `./gradlew :backend:run` sin
  `POSTGRES_PASSWORD` → `/health` 200, `/openapi.json` 200 y `/v1/feed`/`/v1/chat`
  404; con las dependencias, las rutas `/v1/…` responden.
- **Dependencias**: comprobar que `gradle/libs.versions.toml` y
  `backend/build.gradle.kts` no cambian; `git diff` sin migraciones ni
  `:composeApp`/CI/`init.sh`.
- **E2E**: no aplica — el repo no tiene comando E2E persistente (el cliente es
  Compose Multiplatform y aún no consume `:shared`); el flujo de API se cubre con
  `testApplication` en el gate.
- `init.sh` (harness): **no** se modifica.

## Evidence To Capture

- Salida de los tests nuevos y del gate (`build -PskipClient`, `test`, `detekt`,
  `init.sh` exit 0) con recuento y 0 fallos.
- Ejemplo real de `GET /openapi.json` (cabecera + fragmento con `info.version` y
  las rutas `/v1/…`) y de una llamada `curl` a `/v1/feed` (o `404` sin BD).
- Confirmación de que `gradle/libs.versions.toml`/`backend/build.gradle.kts` no
  cambian y de que las migraciones `V1`…`V5` quedan intactas.
- Ficheros del commit `FT00029`, PR (base apilada) y run de CI; entradas en
  `PROGRESS.md` y `feature_list.json` (`evidence`).

## Validator Checklist

- [ ] Alcance acotado: solo el documento OpenAPI, `plugins/OpenApi.kt`,
      `plugins/Routing.kt`, los tests de ruta (URLs) y docs; **sin** CORS/rate
      limiting/error tipado, **sin** Swagger UI, **sin** UI, **sin** migración,
      **sin** dependencias Gradle nuevas, **sin** cambios en los DTOs de `:shared`.
- [ ] Escenarios 1–7 pasan; **todo el gate corre sin red, BD, modelo ni OpenCode**.
- [ ] `GET /openapi.json` sirve un OpenAPI 3.1 válido con `info.version` y los
      **cuatro** endpoints de dominio documentados (feed, detalle, búsqueda, chat)
      más `/health`.
- [ ] Las rutas de **dominio** están bajo `/v1`; `/health` y `/openapi.json` **sin**
      versión; una ruta de dominio sin `/v1` responde `404`.
- [ ] El **test anti-deriva** compara los esquemas con los `@SerialName`/tokens de
      los DTOs de `:shared` y falla ante divergencia.
- [ ] El arranque **no** depende de la BD/modelo/clave (`/health` y
      `/openapi.json` operativos; rutas condicionales).
- [ ] La **base incluye FT00028** (`/buscar`) o el orquestador lo ha resuelto; el
      implementador **no** ha inventado `/buscar`.
- [ ] Sin dependencias Gradle nuevas, sin migración, `:composeApp`/CI/`init.sh`
      intactos; DTOs `Dto` con `@SerialName` explícito; `return` único, sin
      `else if`, funciones ≤40 líneas, KDoc en castellano con identificadores en
      inglés.
- [ ] `ARCHITECTURE.md`, `CONSTRAINTS.md`, ADR 0025 + índice, skill,
      `docs/desarrollo-local.md`, `PROGRESS.md` y `feature_list.json` actualizados.
- [ ] Sin comportamiento de producto no relacionado ni ficheros fuera de alcance.

## Risks / Open Questions

- **La base no contiene `/buscar` (bloqueante de planificación).** La pila
  `feat/ft00029` → `feat/ft00031` → `defd04f` (FT00027) carece de `Search.kt`
  (FT00028 está en `origin/main`). La verificación exige documentar búsqueda: el
  orquestador debe rebasar `feat/ft00031-api-chat` sobre `origin/main` (o esperar
  al merge del PR #30) y rebasar `feat/ft00029` encima. Si no, el spec no puede
  cumplirse y el implementador debe **parar y reportar**.
- **PR apilado.** El PR de FT00029 tiene base `feat/ft00031-api-chat` (no `main`),
  que a su vez se abre a `main` (PR #30). Al rebasar/mergear, resolver conflictos
  aditivos en `Routing.kt` (colaboradores opcionales) y actualizar la descripción
  del PR.
- **Tocar tests de features `accepted`.** El prefijo `/v1` obliga a actualizar las
  URLs de `FeedRouteTest`/`PublicationDetailRouteTest`/`ChatRouteTest` (y
  `SearchRouteTest`). Es **mecánico y sancionado**: el ADR 0022 difirió
  explícitamente el versionado del path a FT00029; se documenta como cambio
  esperado, no como regresión. Si el dueño prefiere **no** versionar el path, la
  alternativa es documentar solo `info.version` + política (sin `/v1`) y dejar el
  prefijo para un cambio incompatible; sería una feature trivialmente más pequeña.
- **Deriva documento↔DTOs.** Un documento estático puede quedar obsoleto si un DTO
  cambia sin actualizarlo. Mitigación: el **test anti-deriva** en el gate compara
  nombres de propiedad y tokens de enum; si `:shared` cambia, el test falla y
  fuerza la actualización del documento.
- **Sin generación automática.** Se descarta el compilador OpenAPI de Ktor (exige
  Kotlin ≥ 2.2.20; el proyecto fija 2.1.20) y los artefactos que solo sirven UI; el
  documento se mantiene a mano y se protege con el test. Documentar en el ADR.
- **`info.version` acoplada al hito.** Se usa `0.5.0` (hito de la 0.5.0). Si se
  quiere versionado semántico independiente del roadmap, es una decisión del dueño
  (ajustable en el ADR sin cambiar el mecanismo).
- **Rutas de dominio sin versión deprecadas.** No se conservan aliases sin `/v1`
  (no hay clientes todavía); si alguno existiera, añadirlos sería otra feature.
- **Swagger UI/ReDoc.** Fuera de alcance; si se quiere explorador interactivo, es
  una feature posterior con su propia decisión de dependencia.
- **División.** ≈10–11 ficheros: muy por debajo de 30 → **atómica**; no se
  recomienda partir en `FT00029-PTn`.
