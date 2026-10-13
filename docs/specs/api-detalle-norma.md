# Feature Implementation Spec: Endpoint de detalle de publicación

## Source Feature

- `id`: api-detalle-norma
- `ft_id`: FT00027 (registrado en `docs/feature-ids.md`; `not_started`)
- `parts`: none (atómica; ≈8 ficheros de producto, muy por debajo del límite de 30)
- `area`: api-publica
- `depends_on`: guardrails-anti-alucinacion (FT00022, `accepted`) +
  cola-revision-confianza (FT00023, `accepted`) + ingesta-job-diario (FT00009,
  `accepted`) + publicacion-persistencia (FT00008, `accepted`).
- `status`: not_started (al planificar)
- `source`: `feature_list.json` (`notes`: `docs/roadmap.md` 0.5-T02)
- `claim`: rama `feat/ft00027-api-detalle-norma` ya reclamada
  (`ec0f03c chore(FT00027): claim api-detalle-norma`); **PR apilado**: la rama base
  de esta feature es `feat/ft00026-api-feed-diario` (PR #27 aún **sin mergear** en
  `main`).

> **Dependencia resuelta.** El detalle sirve **solo** publicaciones con
> `resumen.estado = 'publicado'`, token que **escribe** `cola-revision-confianza`
> (FT00023, `accepted`). Igual que en FT00026, el orquestador debe **añadir
> `cola-revision-confianza`** a `depends_on` en `feature_list.json` (no lo hace el
> planner). Guardrails (FT00022) cubre la validación de la fuente del resumen
> servido; `ingesta-job-diario`/`publicacion-persistencia` son la procedencia del
> dato que se lee.

> **Base apilada.** El árbol de trabajo de `feat/ft00027-…` incluye ya el código de
> FT00026: el endpoint `/feed`, el **pool JDBC único** en `Application.kt`,
> `plugins/Routing.kt` modificado, el contrato de feed en `:shared`
> (`HighlightDto`/`HighlightReasonDto`/`ResumenDiarioDto`) y el mapeo reutilizable
> `backend/…/feed/FeedDtoMapper.kt`. Esta feature **lo reutiliza** (no lo
> duplica) y su PR se abre con **base `feat/ft00026-api-feed-diario`**.

## Goal

Exponer por HTTP, en `:backend`, el **detalle de una publicación** del BOE (tarea
`0.5-T02`): dado el identificador oficial de una publicación
(`BOE-A-2026-20979`), devolver su **resumen ciudadano estructurado** («¿Qué
cambia?», «¿A quién afecta?», «Cifras clave»), su **categoría**, su **plazo** (si
es una convocatoria con plazo fiable) y el **enlace a la fuente oficial**, más el
**aviso de IA**. Solo se sirven publicaciones cuyo resumen está **publicado**
(`estado = 'publicado'`), igual que el feed (FT00026).

La feature **reutiliza al máximo lo ya construido**: el contrato de `:shared`
`PublicacionDto` (que ya lleva `categoria`, `urlOficial`, `resumen`, `plazo` y
`avisoIA`), el mapeo puro `feed/FeedDtoMapper` (que FT00026 dejó explícitamente
reutilizable para FT00027) y los repositorios JDBC existentes
`PublicationRepository.findById` y `SummaryRepository.findByPublication` sobre el
**pool único** que ya crea `Application.kt`. **No** inventa comportamiento fuera de
`docs/roadmap.md` (0.5-T02), `docs/domain-model.md` (Publicación/Resumen/Plazo),
`CONTEXT.md`, `DESIGN.md` (pantalla detalle) ni del precedente de FT00026.

## Non-Goals

- **Generar/cachear/guardar resúmenes**: FT00020–FT00023 son **librerías ya
  existentes**; esta feature **lee** lo publicado, no cablea el pipeline. El gap
  de planificación de FT00026 (nada escribe `publicado` en runtime) sigue vigente
  (ver *Risks*).
- **Filtros/búsqueda** (`api-busqueda`, FT00028), **chat** (FT00031), **feed**
  (FT00026, ya hecho).
- **OpenAPI/versionado del path** (FT00029), **CORS/rate limiting/cuerpo de error
  consistente** (FT00030), **UI** (FT00033) y **aviso de IA visible** (FT00033).
- **Cambiar el contrato de wire de `:shared`**: se **reutiliza** `PublicacionDto`
  tal cual; **no** se crea ningún DTO nuevo.
- **Migración** (`V1`…`V5` intactas; no hay cambio de esquema) ni **tocar** el
  job/backfill, `:composeApp`, CI, `init.sh`, ni las dependencias Gradle.
- Modificar `PublicationRepository`/`SummaryRepository`/`FeedRepository`/
  `FeedDtoMapper`/`HighlightRanker` (se **reutilizan**) ni el pipeline de resumen.

## Job Story

When consulto el detalle de una publicación (por ejemplo, pulsando una tarjeta del
feed o abriendo un enlace compartido),
I want recibir su resumen ciudadano completo, su categoría, su plazo si lo tiene y
su enlace a la fuente oficial, sin que se me sirva un resumen que no pasó los
guardrails,
so I can entender qué cambia y a quién afecta y saltar siempre a la fuente oficial.

## Users And Permissions

- **Ciudadanía (usuario final):** anónima, solo lectura; sin cuentas ni datos
  personales; el endpoint es público.
- **Cliente CMP (FT00033):** consumidor del contrato `:shared` (`PublicacionDto`).
- **Operador/desarrollador:** arranca el backend con PostgreSQL y ejecuta la prueba
  real **opt-in** (`DB_LIVE_TEST=1`).
- Sin autenticación, sin autorización y sin escritura.

## Acceptance Scenarios

### Scenario 1: publicación con resumen publicado → detalle 200

Given una publicación con `resumen.estado = 'publicado'`,
When `GET /publicacion/{id}` con su identificador oficial,
Then responde `200` con un `PublicacionDto`: `id`, `titulo`, `fechaPublicacion`,
`organismo`, `seccion`, `epigrafe`, `categoria`, `urlOficial`, `resumen` (no nulo,
con `queCambia`/`aQuienAfecta`/`cifrasClave`/`fuenteOficial`/`avisoIA`) y `plazo`
(si la publicación lo tiene).

### Scenario 2: solo se sirve un resumen publicado

Given una publicación cuyo resumen está `en_cola_revision` (o `pendiente`/`generado`/
`descartado`) o que no tiene resumen,
When se pide su detalle,
Then responde `404` (no se sirve un resumen no publicado), sin cuerpo tipado.

### Scenario 3: identificador desconocido → 404

Given una publicación que no existe,
When se pide `GET /publicacion/{id}` con ese id,
Then responde `404` (no es un error).

### Scenario 4: identificador vacío o desmesurado → 400

Given una petición con un identificador en blanco (solo espacios) o más largo que
`MAX_ID_LENGTH`,
When se pide el detalle,
Then responde `400` (sin cuerpo tipado; el contrato de error es FT00030).

### Scenario 5: arranque sin base de datos intacto

Given un entorno sin `POSTGRES_PASSWORD`,
When arranca el backend,
Then `/health` responde `200`, las rutas `/feed` y `/publicacion/{id}` **no** se
registran (`404`), el arranque no falla y no se abre ninguna conexión; con base de
datos, ambas rutas se registran y usan el **mismo pool** ya compartido con la
ingesta, cerrado **una sola vez** al parar.

### Scenario 6: trazabilidad y determinismo

Given un detalle servido,
When se repite la petición,
Then la respuesta es **idéntica** y siempre incluye `urlOficial` (de la publicación)
y `fuenteOficial` (del resumen) con enlace al BOE, y `avisoIA` tal cual lo persistió
la disposición; los destacados no participan en el detalle.

### Scenario 7: el gate sigue sin red ni BD

Given el runner de CI sin PostgreSQL y sin red,
When se ejecuta `./gradlew build -PskipClient`, `./gradlew test`, `./gradlew detekt`
o `.harness/init.sh`,
Then todo está en verde; la prueba real se omite sin abrir conexiones.

### Scenario 8: la lectura real sirve solo publicados (opt-in)

Given `DB_LIVE_TEST=1` y el PostgreSQL de `docker-compose` con `V1`…`V5`,
When `PublicationDetailLiveTest` inserta una publicación con resumen `publicado` y
otra con resumen `en_cola_revision`,
Then el servicio devuelve el DTO de la publicada y `null` (⇒ `404`) para la
encolada.

## Repository Research

### Files Inspected

- `shared/src/commonMain/kotlin/…/model/{PublicacionDto,ResumenDto,PlazoDto,CategoriaDto,SeccionBoeDto}.kt`
  — contrato de wire (todos con `@SerialName` explícito). `PublicacionDto` ya lleva
  `id`, `titulo`, `fechaPublicacion`, `organismo`, `seccion`, `epigrafe`,
  `categoria`, `urlOficial`, `resumen?` y `plazo?`; **es exactamente** la respuesta
  del detalle, así que **no** hace falta un DTO nuevo.
- `backend/src/main/kotlin/…/backend/Application.kt` — composition root: crea un
  **pool JDBC único** (`createDataSourceOrNull`) solo si la config de BD resuelve,
  construye `DailyFeedService(FeedRepositoryJdbc(ds))` (`feedServiceOf`),
  `configureRouting(feedService)`, arranca la ingesta con el mismo `ds` y cierra el
  pool **una sola vez** en `ApplicationStopped` (`monitorDataSource`).
- `backend/src/main/kotlin/…/backend/plugins/{Routing,Feed}.kt` — patrón de rutas
  `fun Route.xRoutes(dep)` + `configureRouting(feedService?)` que registra `/feed`
  **solo** si el servicio no es `null`; validación de query params → `400` sin
  cuerpo. `plugins/Health.kt` siempre registrado.
- `backend/src/main/kotlin/…/backend/feed/{DailyFeedService,FeedDtoMapper}.kt` —
  servicio `suspend` (lectura JDBC en `Dispatchers.IO`) y **mapeo puro**
  `FeedDtoMapper.toPublicacionDto(Publicacion, SummaryEntity): PublicacionDto`; su
  KDoc dice explícitamente que es **reutilizable por FT00027**.
- `backend/src/main/kotlin/…/backend/persistence/{PublicationRepository,SummaryRepository}.kt`
  — `PublicationRepositoryJdbc.findById(id): Publicacion?` (PK) y
  `SummaryRepositoryJdbc.findByPublication(id): SummaryEntity?` (FK única 1:1),
  con mappers internos `toPublicationEntity()`/`toSummaryEntity()` y helpers
  `Jdbc.kt` (sin ORM, autocommit).
- `backend/src/main/kotlin/…/backend/persistence/FeedRepository.kt` — patrón de
  lectura `publicacion ⋈ resumen` con `r.estado = 'publicado'` (FT00026). Su KDoc
  declara que **no** anticipa el detalle (FT00027): aquí se reutilizan los dos
  repositorios existentes en vez de duplicar su SQL.
- `backend/src/main/kotlin/…/backend/rag/review/SummaryState.kt` — enum de los
  siete estados; `PUBLISHED.persistedValue == "publicado"`. Se usa el **token
  tipado** (no un literal) para decidir si se sirve.
- `backend/src/main/kotlin/…/backend/ingesta/publicacion/Publicacion.kt` — modelo
  de dominio con `categoria: CategoriaDto?` y `plazo: PlazoDto?`.
- `backend/src/test/kotlin/…/backend/plugins/FeedRouteTest.kt` y
  `…/persistence/FeedPersistenceLiveTest.kt` — patrones de `testApplication` con
  repositorio en memoria y de test **opt-in** `DB_LIVE_TEST=1` (lectura de `.env`).
- `backend/build.gradle.kts` — `:shared` ya es dependencia; `ktor-server-test-host`
  ya está en test; **sin** dependencias nuevas.
- `docs/desarrollo-local.md` (producto) — guía donde documentar el endpoint y su `curl`.
- Harness: `feature_list.json` (FT00027), `docs/roadmap.md` §0.5 (`0.5-T02`),
  `docs/domain-model.md` (Publicación/Resumen/Plazo), `CONTEXT.md`,
  `DESIGN.md` (§Layout/§Core Screens: «Detalle de publicación: resumen estructurado
  + plazo (si aplica) + fuente oficial + aviso de IA»), `ARCHITECTURE.md`,
  `CONSTRAINTS.md`, ADR 0014/0017/0018/0021 y los specs `api-feed-diario.md`,
  `cola-revision-confianza.md`, `guardrails-anti-alucinacion.md`.

### Existing Patterns To Follow

- **Ruta delgada en `plugins/`** (`Route.xRoutes(service)`) + **servicio** sin Ktor
  (`publication/PublicationDetailService`) + **repositorios JDBC** existentes en
  `persistence/`.
- **Reutilizar** `FeedDtoMapper.toPublicacionDto` y los repositorios
  `PublicationRepository`/`SummaryRepository`; **no** duplicar SQL ni el mapeo.
- **Trabajo bloqueante fuera del event loop**: envolver las lecturas JDBC en
  `withContext(Dispatchers.IO)`.
- **Tests del gate** con dobles deterministas (`PublicationRepository`/
  `SummaryRepository` en memoria) y `testApplication`; prueba real **opt-in**
  `DB_LIVE_TEST=1`.
- **Estilo MUST**: identificadores en inglés (KDoc en castellano), un solo `return`,
  sin `else if`, funciones ≤40 líneas, `@SerialName` explícito (los DTO ya lo cumplen).

### Current Gaps

- No existe ninguna ruta que devuelva una sola publicación por identificador.
- `configureRouting` solo conoce el `feedService`; hay que generalizarlo a dos
  servicios opcionales.
- `Application.kt` construye solo el servicio del feed; el detalle necesita su
  propio servicio construido sobre el **mismo** `dataSource`.

## Technical Approach

Contrato derivado (de `docs/roadmap.md` 0.5-T02, `docs/domain-model.md`,
`CONTEXT.md`, `DESIGN.md` y el precedente FT00026): el detalle es **una sola
publicación por su identificador oficial**, sirve **solo resúmenes publicados** y
devuelve el **mismo** `PublicacionDto` que el feed usa. No hay parámetros de
filtro; el identificador es el recurso.

### 1. Ruta (`plugins/PublicationDetail.kt`, create)

- `fun Route.publicationDetailRoutes(service: PublicationDetailService)`:
  `GET /publicacion/{id}`.
  - `id` es el **segmento de path** con el identificador oficial del BOE
    (`BOE-A-2026-20979`). Se elige **path param** (recurso estable, enlaces
    compartibles; roadmap `0.9-T03`) frente a query param.
  - Si `id` falta (Ktor no casa la ruta ⇒ `404`), está **en blanco** o supera
    `MAX_ID_LENGTH` (p. ej. `128`) ⇒ `400` **sin cuerpo tipado** (el contrato de
    error es FT00030).
  - Llama a `service.detail(id)`; `null` ⇒ `404`; un DTO ⇒ `200` con
    `call.respond(HttpStatusCode.OK, detail)`.
  - No conoce SQL ni el pipeline de resumen.
- `configureRouting` (`plugins/Routing.kt`, modify): añade un segundo colaborador
  opcional `detailService: PublicationDetailService? = null` y registra
  `/publicacion/{id}` **solo** si no es `null` (mismo patrón «solo las rutas cuyas
  dependencias existen»). `/health` y `/feed` se mantienen.

### 2. Servicio de aplicación (`publication/PublicationDetailService.kt`, create)

- `class PublicationDetailService(private val publicationRepository:
  PublicationRepository, private val summaryRepository: SummaryRepository)`.
- `suspend fun detail(id: String): PublicacionDto?`:
  1. En **un único** `withContext(Dispatchers.IO) { … }`: `publicationRepository.
     findById(id)` y `summaryRepository.findByPublication(id)` (ambas PK/FK, sin
     `JOIN` nuevo; el volumen es de una fila).
  2. Devuelve `null` (⇒ `404`) si la publicación no existe, si su `categoria` es
     `null` (dato corrupto, patrón de FT00026; **nunca** se inventa categoría) o si
     no hay resumen con `status == SummaryState.PUBLISHED.persistedValue`.
  3. En caso contrario, `FeedDtoMapper.toPublicacionDto(publication, summary)`.
- Constante documentada `MAX_ID_LENGTH`. Un solo `return`, sin `else if`, ≤40 líneas.

### 3. Wiring (`Application.kt`, modify)

- Construir `PublicationDetailService(PublicationRepositoryJdbc(dataSource),
  SummaryRepositoryJdbc(dataSource))` **solo** si `dataSource != null`
  (`detailServiceOf`), reutilizando el **pool único** existente; pasarlo a
  `configureRouting(feedService, detailService)`.
- Sin cambio de ciclo de vida: el pool lo sigue creando/cerrando el composition
  root una sola vez.

### Sin anticipar lo diferido

Sin migración (`V1`…`V5` intactas), sin cambios en el contrato de `:shared`, sin
CORS/rate limiting/OpenAPI/cuerpo de error (FT00029/FT00030), sin UI ni aviso
visible (FT00033), sin dependencias Gradle nuevas, sin tocar `:composeApp`/CI/
`init.sh`.

## Expected File Changes

Rutas en el repo de producto (`..`); `es/aviferdev/datopublico` se abrevia `…`:

- `backend/src/main/kotlin/…/backend/publication/PublicationDetailService.kt` —
  create; servicio (`suspend`, `Dispatchers.IO`, reutiliza repos y mapper).
- `backend/src/main/kotlin/…/backend/plugins/PublicationDetail.kt` — create;
  `GET /publicacion/{id}` + validación de `id` (`400`) y `MAX_ID_LENGTH`.
- `backend/src/main/kotlin/…/backend/plugins/Routing.kt` — modify; segundo servicio
  opcional y registro condicional de la ruta.
- `backend/src/main/kotlin/…/backend/Application.kt` — modify; construir el detalle
  sobre el pool único y pasarlo al routing.
- `backend/src/test/kotlin/…/backend/publication/PublicationDetailServiceTest.kt` —
  create; gate con repositorios en memoria (escenarios 1–3, 6).
- `backend/src/test/kotlin/…/backend/plugins/PublicationDetailRouteTest.kt` —
  create; gate, `testApplication` (200/400/404, incluida la ruta no registrada).
- `backend/src/test/kotlin/…/backend/persistence/PublicationDetailLiveTest.kt` —
  create; **opt-in** `DB_LIVE_TEST=1` (escenario 8).
- `docs/desarrollo-local.md` (producto) — modify; endpoint detalle y `curl`.

Harness (privado): `ARCHITECTURE.md`, `CONSTRAINTS.md`, ADR `0022` + índice,
`PROGRESS.md`, `feature_list.json` (ver *Durable Documentation Impact*).

Total ≈ **8 ficheros de producto** + docs: por debajo del límite de 30 → **no**
requiere división en partes `FT00027-PTn`.

## Visual Design Impact

- UI involved: no. Sin pantallas, tokens ni textos.
- Design source: `DESIGN.md` (§Core Screens: «Detalle de publicación: resumen
  estructurado + plazo (si aplica) + fuente oficial + aviso de IA»). Aquí solo se
  produce el **contrato** que la UI de detalle (FT00033) localizará; `avisoIA`
  viaja en el DTO y el aviso **visible** es FT00033.
- New design artifact required: no.

## Durable Documentation Impact

- `ARCHITECTURE.md`: **update** — `:backend` gana `publication/`
  (`PublicationDetailService`) y `plugins/PublicationDetail.kt`; la frontera
  «Cliente → API HTTP» pasa a listar el **detalle** (`GET /publicacion/{id}`) como
  segundo endpoint de solo lectura, sobre el **mismo pool** que el feed/ingesta.
- `CONSTRAINTS.md`: **update** — nueva sección **«API pública: detalle de
  publicación»**: solo lectura y público; sirve **solo** resúmenes
  `estado = 'publicado'`; identificador en path con `400`/`404`; reutiliza el
  contrato `PublicacionDto` y el mapeo de FT00026; arranque sin BD y pool único; sin
  migración ni lo diferido.
- `AGENTS.md`: **not needed** — no cambia el flujo, el arranque ni las reglas.
- Other docs: `docs/adr/0022-detalle-publicacion-endpoint.md` — **create** (decisión
  durable: detalle por identificador, solo `publicado`, contrato reutilizado,
  `404`/`400`, pool compartido) + índice `docs/adr/README.md`;
  `.agents/skills/ktor-backend-architecture/SKILL.md` — **update** opcional (la
  sección «API» menciona `detalle` como pendiente); `docs/desarrollo-local.md` —
  **update**.

## Implementation Plan

1. Crear `publication/PublicationDetailService.kt` (reutiliza
   `PublicationRepository`, `SummaryRepository`, `SummaryState.PUBLISHED` y
   `FeedDtoMapper`) con su test de gate de dobles.
2. Crear `plugins/PublicationDetail.kt` (`GET /publicacion/{id}`, validación de
   `id`, `400`/`404`) y `PublicationDetailRouteTest`.
3. Modificar `plugins/Routing.kt` (segundo servicio opcional) y `Application.kt`
   (construir el detalle sobre el pool único); verificar `/health` sin BD y el
   arranque con BD.
4. Añadir `PublicationDetailLiveTest` (**opt-in** `DB_LIVE_TEST=1`).
5. Pasar el gate sin red ni BD y actualizar `ARCHITECTURE.md`, `CONSTRAINTS.md`,
   ADR 0022 + índice y `docs/desarrollo-local.md`; `PROGRESS.md`/`feature_list.json`
   los cierra el orquestador.

## Implementation Tasks

- [ ] `publication/PublicationDetailService` (`suspend`, `withContext(Dispatchers.IO)`,
      `findById` + `findByPublication`, filtro `PUBLISHED`, `FeedDtoMapper`,
      `MAX_ID_LENGTH`).
- [ ] `plugins/PublicationDetail.kt` (`GET /publicacion/{id}`, `400`/`404`/`200`) +
      `plugins/Routing.kt` (segundo servicio opcional).
- [ ] `Application.kt`: construir el detalle sobre el pool único y registrarlo.
- [ ] Tests de gate: servicio (escenarios 1–3, 6) y ruta (200/400/404/404 sin servicio).
- [ ] `PublicationDetailLiveTest` opt-in (`DB_LIVE_TEST=1`, escenario 8).
- [ ] Docs: `ARCHITECTURE.md`, `CONSTRAINTS.md`, ADR 0022 + índice,
      `docs/desarrollo-local.md`.

## Verification Plan

Desde la raíz del producto (`..`, JDK 21 vía JBR/`JAVA_HOME`):

- **Gate sin red ni BD (obligatorio)**: `./gradlew :backend:test --rerun-tasks` y
  `./gradlew :shared:jvmTest` → BUILD SUCCESSFUL con los tests nuevos en verde y el
  resto intacto; `./gradlew build --no-daemon -PskipClient` (incluye `detekt` +
  `:cpdCheck`), `./gradlew test`, `./gradlew detekt` y `env -u JAVA_HOME
  .harness/init.sh` → exit 0.
- **Rutas (gate)**: `PublicationDetailRouteTest` con `testApplication` y repos en
  memoria comprueba `200` (JSON `PublicacionDto` con `resumen`/`categoria`/
  `urlOficial`/`plazo`), `400` por id en blanco/desmesurado, `404` por id
  desconocido o resumen no publicado y `404` cuando no se registra el servicio.
- **Servicio (gate)**: `PublicationDetailServiceTest` cubre publicado → DTO, no
  publicado → `null`, sin resumen → `null`, publicación inexistente → `null`,
  categoría nula → `null` y determinismo/trazabilidad (escenario 6).
- **Arranque sin BD**: `./gradlew :backend:run` sin `POSTGRES_PASSWORD` → `/health`
  200, `/feed` y `/publicacion/{id}` 404; con BD, el detalle responde y el pool se
  comparte con feed/ingesta.
- **Escenario 8 (opt-in, fuera del gate y de la CI)**:
  ```sh
  cp .env.example .env
  docker compose up -d
  ./gradlew :backend:flywayMigrate
  DB_LIVE_TEST=1 ./gradlew :backend:test --tests '*PublicationDetailLiveTest'
  docker compose down -v
  ```
  Esperado: la publicación con resumen `publicado` se sirve; la encolada no.
- **E2E**: no aplica — el repo no tiene comando E2E persistente (el cliente es
  Compose Multiplatform y aún no consume `:shared`); el flujo de API se cubre con
  `testApplication` en el gate.
- `init.sh` (harness): **no** se modifica.

## Evidence To Capture

- Salida de los tests nuevos (`:backend:test` y `:shared:jvmTest`) con recuento y 0
  fallos, y del gate (`build -PskipClient`, `test`, `detekt`, `init.sh` exit 0).
- Ejemplo real de respuesta `GET /publicacion/BOE-A-…` (con `resumen`, `categoria`,
  `urlOficial`, `plazo` y `avisoIA`) y de `404` (no publicado / desconocido) y `400`.
- Confirmación de que `Application.kt` arranca sin BD (`/health` 200; detalle y feed
  404) y de que el pool es único.
- Salida del test opt-in `PublicationDetailLiveTest` (solo publicados).
- Ficheros del commit `FT00027`, PR (base `feat/ft00026-api-feed-diario`) y run de
  CI; entradas en `PROGRESS.md` y `feature_list.json` (`evidence`).

## Validator Checklist

- [ ] Alcance acotado: solo `publication/`, `plugins/PublicationDetail`/`Routing` y
      el wiring de `Application.kt`; **sin** generación/cacheo/disposición, **sin**
      búsqueda/chat/feed nuevo, **sin** CORS/rate limit/OpenAPI, **sin** UI, **sin**
      migración, **sin** cambio de `:shared`.
- [ ] Escenarios 1–8 pasan; **todo el gate corre sin red ni BD** y la prueba real se
      omite sin `DB_LIVE_TEST`.
- [ ] El detalle sirve **solo** resúmenes `estado = 'publicado'` (token tipado
      `SummaryState.PUBLISHED`); los no publicados/inexistentes devuelven `404`.
- [ ] La respuesta es el `PublicacionDto` completo, con `urlOficial`/`fuenteOficial`
      (trazabilidad) y `avisoIA`; determinista.
- [ ] `id` en path con `400` (blanco/desmesurado) y `404` (desconocido); arranque
      **sin** dependencia de la BD (ruta condicional, `/health` operativo) y pool
      único creado/cerrado una vez.
- [ ] Lectura JDBC en `Dispatchers.IO`; **sin** SQL duplicado (reutiliza
      repos/mappers existentes); sin secretos.
- [ ] DTOs con `@SerialName` explícito y sufijo `Dto` (reutilizados); un solo
      `return`, sin `else if`, funciones ≤40 líneas, KDoc en castellano con
      identificadores en inglés.
- [ ] `ARCHITECTURE.md`, `CONSTRAINTS.md`, ADR 0022 + índice,
      `docs/desarrollo-local.md`, `PROGRESS.md` y `feature_list.json` actualizados.
- [ ] Sin comportamiento de producto no relacionado ni ficheros fuera de alcance.

## Risks / Open Questions

- **Dependencia implícita de FT00023.** El detalle filtra por `estado = 'publicado'`,
  que solo escribe `cola-revision-confianza` (FT00023). Añadir
  `cola-revision-confianza` a `depends_on` (lo aplica el orquestador).
- **Detalle vacío sin el pipeline cableado.** FT00020–FT00023 siguen siendo
  librerías sin wiring: en producción el detalle devolverá `404` hasta que exista el
  cableado generación → guardrails → disposición (mismo gap de planificación que
  FT00026, no cubierto por ninguna feature). Se documenta como no-objetivo.
- **Dos consultas en vez de un `JOIN`.** Se reutilizan `findById`+`findByPublication`
  en lugar de duplicar el SQL del feed; el coste (dos lookups por PK/FK, una fila) es
  despreciable en el N100. Si se quisiera una sola consulta habría que extender
  `FeedRepository`, con duplicación de columnas y riesgo de CPD.
- **Categoría nula = dato corrupto.** Una publicación sin categoría no mapea a
  `PublicacionDto`; se trata como **no servible** (`404`) sin inventar categoría ni
  provocar un crash (patrón FT00026). Con el contrato de error (FT00030) podría
  revisarse a `500`.
- **Reutilización cross-package.** El detalle reutiliza `feed.FeedDtoMapper`
  (documentado como reutilizable por FT00026); si más adelante se desea un hogar
  neutral (p. ej. `api/`), sería un refactor posterior, no de esta feature.
- **Path sin versión.** Se usa `/publicacion/{id}` (coherente con `/feed` y
  `/health`); el versionado/OpenAPI del path es FT00029 y puede añadir prefijo.
- **`id` desmesurado.** El único límite es `MAX_ID_LENGTH` (anti-abuso); no se valida
  el formato del identificador del BOE (es opaco: la existencia decide `200`/`404`),
  para no rechazar identificadores legítimos de secciones con formato distinto.
- **División.** ≈8 ficheros: muy por debajo de 30 → **atómica**; no se recomienda
  partir en `FT00027-PTn`.
