# Feature Implementation Spec: Cliente HTTP común y cache offline

## Source Feature

- `id`: ui-cliente-http-cache
- `ft_id`: FT00035 (registrado en `docs/feature-ids.md`)
- `parts`: **none** (atómica; ≈25 ficheros de producto, por debajo del límite de 30)
- `area`: cliente-cmp
- `depends_on`: ui-feed (FT00032, **`accepted`** y en `main`)
- `status`: not_started (al planificar)
- `source`: `feature_list.json` (`notes`: `docs/roadmap.md` 0.6-T04, `docs/technical-discovery.md` ktor-client)
- `claim`: rama `feat/ft00035-ui-cliente-http-cache` reclamada en `origin`
  (`98be653 chore(FT00035-): claim ui-cliente-http-cache`); sin PR abierto hacia `main`.
  Se trabaja en el worktree de producto
  `/Users/aviferdev/Documents/Git/DatoPublico-wt/ft00035` (contenido idéntico a
  `origin/main` en `:composeApp`/`:shared`, verificado con `git diff`).

> **Cierra el aplazamiento de FT00032.** FT00032 dejó la UI del feed con **modelos
> de dominio propios** y un **repositorio en memoria** (`InMemoryFeedRepository`),
> deliberadamente desacoplada de `:shared` (ADR 0027). FT00035 sustituye ese
> repositorio por el **cliente HTTP real** (`ktor-client`) contra la API `/v1` y añade
> la **cache offline básica**, mapeando el contrato público al dominio del cliente.
> No introduce `ViewModel`/`StateFlow`/navegación (FT00034) ni la pantalla de detalle
> (FT00033).

## Goal

Construir en `commonMain` de `:composeApp` la **capa de datos de red** del cliente:
un **cliente HTTP común** (`ktor-client` + `kotlinx.serialization`) con **URL base por
plataforma**, manejo de **errores tipados** (sin crashes), los **DTOs de wire del
cliente** y su **mapeo al dominio** de FT00032, y una **cache offline básica** (en
memoria, sin datos personales) que mantiene visible el último feed cuando la red
falla. La UI del feed (`FeedScreen`) y sus estados no cambian.

## Non-Goals

- **Navegación y estado compartido** (FT00034): `ViewModel`, `StateFlow`, `stateIn`,
  grafo de navegación, DI con framework, `collectAsStateWithLifecycle`. FT00035 solo
  sustituye el repositorio en el *composition root* manual.
- **Detalle** (FT00033), **búsqueda** (FT00036) y **chat** (FT00037): no se implementan
  sus pantallas, DTOs ni endpoints; `core/network` queda listo para que las reutilicen.
- **Persistencia de la cache entre arranques**: SQLDelight, fichero o
  `expect/actual` de almacenamiento multiplataforma quedan **fuera** (ver *Risks*).
  Aquí la cache es **en memoria** (por sesión), suficiente para la verificación
  («con la red caída, el contenido cacheado sigue visible»).
- **Indicador visible de «sin conexión»/contenido obsoleto**: no se cambia
  `FeedUiState`/`FeedScreen`; mostrar el feed cacheado como contenido normal (ver
  *Risks*).
- **Paginación/infinite scroll** del feed (`pagina`/`tamanoPagina`): se pide la
  página 1 por defecto; el scroll/paginación es posterior.
- **Cambiar `:shared`**: **no** se le añaden targets KMP ni AGP (rompería el gate
  SDK-free); **no** se toca `:backend`, CI, `init.sh`, migraciones ni el contrato.
- **Firma/empaquetado** (FT00038–FT00040) y **accesibilidad/i18n formal** (FT00043).

## Job Story

When abro la app con el backend accesible (o sin red),
I want ver el **feed real** del BOE servido por la API y, si la red cae, seguir viendo
el último feed cargado,
so I can informarme con datos reales y sin que la app se rompa ni se quede en blanco
cuando no hay conexión.

## Users And Permissions

- **Ciudadanía (usuario final):** anónima, solo lectura; sin cuentas, sin datos
  personales, sin analítica. La cache solo guarda **contenido público del BOE**.
- **Desarrollador (único actor técnico):** ejecuta el backend/el gate y sirve la app
  para verificar.
- Sin autenticación ni autorización (la API es pública).

## Acceptance Scenarios

### Scenario 1: feed real desde la API

Given el backend accesible con publicaciones publicadas para el día,
When la pantalla del feed carga,
Then se piden `GET {baseUrl}/v1/feed?fecha=<ISO>` y las tarjetas muestran los datos
reales mapeados a `Publication` (título, categoría, fecha, resumen corto, destacado
con motivos y plazo si aplica); el feed decodificado queda **cacheado**.

### Scenario 2: error de red sin cache → estado de error

Given la red caída y **sin** feed cacheado,
When la pantalla carga (o se pulsa «Reintentar»),
Then el repositorio devuelve `FeedLoadResult.Failure` y la UI muestra el **estado de
error** con reintento; la app **nunca** se cierra ni propaga la excepción.

### Scenario 3: error de red con cache → contenido cacheado visible

Given un feed ya cargado (cacheado) y la red caída,
When la pantalla vuelve a cargar (o se pulsa «Reintentar»),
Then el repositorio devuelve `FeedLoadResult.Success(<feed cacheado>)` y la UI sigue
mostrando el contenido, sin estado de error.

### Scenario 4: respuestas de error tipadas de la API

Given el backend responde `400`/`404`/`429`/`500`/`502` con `ApiErrorDto`
(`codigo`/`mensaje`),
When el cliente procesa la respuesta,
Then se traduce a un **fallo tipado** (`ApiFailure.Server`), nunca a una excepción no
controlada, y se aplica el **mismo** respaldo de cache que el fallo de red.

### Scenario 5: cuerpo inválido o inesperado

Given una respuesta `200` con un JSON que no decodifica (campo ausente o tipo
distinto),
When el cliente la procesa,
Then el fallo se modela (`ApiFailure.InvalidBody`) y el repositorio **no** lanza:
respalda a cache o devuelve `Failure`.

### Scenario 6: URL base por plataforma (`expect/actual`)

Given el código común de `:composeApp`,
When se revisa el cliente HTTP,
Then **no** hay ninguna URL `http://…` cableada en `commonMain`; la base se resuelve
con `expect fun platformApiBaseUrl()` y un `actual` por plataforma (Android
`http://10.0.2.2:8080` para el emulador, iOS/Wasm/JVM `http://localhost:8080`), y es
**inyectable** (`ApiConfig`) para tests y previews.

### Scenario 7: sin cambios visuales ni de estado de UI

Given la pantalla del feed de FT00032,
When se integra el repositorio HTTP,
Then `FeedScreen`, `FeedUiState`, `FeedStateHolder` y `FeedRoute` **no** cambian de
comportamiento ni de aspecto; `GetDailyFeed` y el puerto `FeedRepository` siguen
igual y `App()` solo cambia el repositorio que construye.

### Scenario 8: DTOs de cliente con `@SerialName` y estilo MUST

Given los DTOs de wire del cliente y el mapeo,
When se revisan,
Then cada propiedad lleva `@SerialName` explícito, los identificadores están en
inglés y el KDoc en castellano, y se respeta el estilo MUST (un solo `return`, sin
`else if`, funciones ≤40 líneas, sin crashes).

### Scenario 9: el gate sigue verde y `:shared` intacto

Given un entorno sin red ni base de datos,
When ejecuto `./gradlew build -PskipClient`, `./gradlew test`, `./gradlew detekt`
(+ `:cpdCheck`) y `.harness/init.sh`,
Then el gate **SDK-free** sigue en verde (no exige Android SDK) y, con el cliente
(`--with-client`), también quedan verdes `:composeApp:assembleDebug`,
`:composeApp:wasmJsBrowserDistribution`, `:composeApp:jvmTest` y el análisis estático.
`:shared`, `:backend`, CI e `init.sh` **no** cambian.

## Repository Research

### Files Inspected

- `composeApp/build.gradle.kts` — targets `androidTarget`/`jvm`/`iosArm64`/
  `iosSimulatorArm64`/`wasmJs`; `commonMain` con Compose + `compose.components.resources`;
  `commonTest` con `kotlin("test")` + `kotlinx-coroutines-test`. **No** hay ktor ni el
  plugin de serialización.
- `shared/build.gradle.kts` — **solo `jvm()`**; `commonMain` con
  `kotlinx-serialization-json`. Por eso `:composeApp` no lo consume (resolución de
  metadata para Android/iOS/Wasm).
- `composeApp/src/commonMain/kotlin/…/feature/feed/{domain,data,ui}/*` — modelos de
  dominio (`DailyFeed`, `Publication`, `PublicationCategory`, `HighlightReason`,
  `Deadline`, `FeedLoadResult`), puerto `FeedRepository.load(): FeedLoadResult`,
  `InMemoryFeedRepository` (placeholder), `GetDailyFeed`, `FeedUiState`,
  `FeedStateHolder` (local), `FeedRoute`, `FeedScreen`, `HighlightsSection`.
- `composeApp/src/commonMain/kotlin/…/app/App.kt` — *composition root* manual:
  `remember { FeedStateHolder(GetDailyFeed(InMemoryFeedRepository())) }` (a sustituir).
- `shared/src/commonMain/kotlin/…/model/{ResumenDiarioDto,PublicacionDto,CategoriaDto,
  HighlightDto,HighlightReasonDto,PlazoDto,ResumenDto,ApiErrorDto}.kt` y
  `serialization/DatoPublicoJson.kt` — contrato de wire que el cliente **replica** como
  capa anti-corrupción (tokens `snake_case`, `@SerialName`).
- `gradle/libs.versions.toml` — `ktor = 3.0.3`; ya existen `ktor-client-core`,
  `ktor-client-cio`, `ktor-client-content-negotiation`, `ktor-serialization-kotlinx-json`,
  `ktor-client-mock`, `kotlinx-serialization-json`; **faltan** motores OkHttp/Darwin/JS.
- `settings.gradle.kts` y `build.gradle.kts` (raíz) — `:composeApp` se incluye solo sin
  `-PskipClient`; detekt por módulo y `:cpdCheck` global (umbral 100 tokens).
- `composeApp/src/androidMain/AndroidManifest.xml` — tema sin ActionBar; **sin**
  permiso `INTERNET` ni política de tráfico claro (ambos hacen falta para la red).
- `.harness/{ARCHITECTURE.md (§`:composeApp`, §Fronteras),CONSTRAINTS.md (§Cliente,
  §Serialización, §Nombres, §Estilo),DESIGN.md}`,
  `.harness/docs/{technical-discovery.md,roadmap.md §0.6.0,risks-and-open-questions.md,
  feature-ids.md,git-workflow.md,pr/README.md}` y `docs/adr/{0027,README}.md`.
- `.harness/.agents/skills/compose-multiplatform-architecture/SKILL.md` — capas
  UI→Dominio→Datos, «cliente HTTP común `ktor-client` en un data source», «cache
  offline básica: con la red caída, el contenido cacheado sigue visible», URL resuelta
  por plataforma y **nunca** `http://localhost` en `commonMain`, DI manual.
- `docs/desarrollo-local.md` (producto) — endpoints `/v1`, cómo arrancar el backend y
  el cliente; a actualizar.
- Specs precedentes: `docs/specs/ui-feed.md` (FT00032) y `docs/specs/api-feed-diario.md`
  (contrato `GET /v1/feed`).

### Existing Patterns To Follow

- **Capas de feature** `feature/feed/{domain,data,ui}`; la UI no conoce Ktor ni DTOs
  (skill CMP). El nuevo código de red va en `data/` y en una capa común `core/network/`.
- **Resultados tipados, sin excepciones hacia la UI** (`FeedLoadResult`), un solo
  `return`, sin `else if`, ≤40 líneas/función, KDoc en castellano e identificadores en
  inglés, `@SerialName` explícito.
- **Version catalog + Kotlin DSL**; sin versiones nuevas (Ktor ya fijado en `3.0.3`).
- **Tests de lógica en `commonTest`** con `kotlin.test` + `runTest`; **sin red** en el
  gate (se dobla el HTTP con `ktor-client-mock`/`MockEngine`, patrón ya usado en
  `:backend`).

### Current Gaps

- No existe cliente HTTP ni `expect/actual` de plataforma en `:composeApp`.
- `:composeApp` no tiene el plugin de serialización ni dependencias de ktor.
- El feed real del backend sale **vacío** en runtime (pipeline de resumen no cableado,
  Session 068) y exige base de datos; la verificación de la ruta HTTP se apoya en
  **tests con `MockEngine`** (sin red ni BD), no en datos reales.
- El backend exige `fecha` **obligatoria** en `/v1/feed`; el cliente debe resolver la
  fecha del día sin `java.time` en `commonMain`.

## Technical Approach

### Decisión clave: `:composeApp` **no** depende de `:shared`

Se mantiene el desacoplamiento de ADR 0027 y el **gate SDK-free**. `:shared` solo
declara `jvm()`; para consumirlo desde `:composeApp` habría que añadirle targets
`iosArm64`/`iosSimulatorArm64`/`wasmJs` (exigen Xcode y la toolchain Wasm, hoy fuera
del gate SDK-free) y, para Android, `androidTarget()` (exige AGP + Android SDK en
`:shared`, que **sí** se compila con `-PskipClient`). Añadirlo **rompería el gate**, que
`CONSTRAINTS.md` prohíbe cambiar en la implementación.

Alternativas evaluadas y descartadas:

- **Añadir targets/AGP a `:shared`**: rompe el gate SDK-free; fuera de alcance.
- **Módulo KMP de contrato `:api-contract`**: o duplica los DTOs, o exige moverlos
  fuera de `:shared` (churn en `:backend` > 30 ficheros) y, para Android, AGP; descartado.
- **`expect/actual` para el contrato**: los DTOs no son «específicos de plataforma»; un
  `actual` por target no aporta y multiplica ficheros.

Por tanto, el cliente define su **propia capa anti-corrupción**: DTOs de wire
`@Serializable` (sufijo `Dto`, `@SerialName` explícito) que **replican el subconjunto**
del contrato `/v1` que el cliente usa, y los **mapean** a los modelos de dominio de
FT00032. Coste: duplicación controlada del contrato (riesgo *Low/Medium*, ver *Risks*),
mitigada con tests que decodifican respuestas de ejemplo del contrato. Cuando exista
una feature de infraestructura que haga `:shared` multiplataforma, estos DTOs se
sustituirán por los compartidos.

### Capa común `core/network/`

- **`ApiConfig.kt`** — `data class ApiConfig(baseUrl: String = platformApiBaseUrl(),
  requestTimeoutMillis: Long = 15_000)`; inyectable en tests/previews.
- **`Platform.kt`** (expect) + un `actual` por plataforma:
  - `expect fun platformApiBaseUrl(): String` — Android `http://10.0.2.2:8080`
    (loopback del emulador al host); iOS/Wasm/JVM `http://localhost:8080`. **Nunca** una
    URL en `commonMain`; los valores de producción son FT00038–FT00040.
  - `expect fun currentIsoDate(): String` — fecha local `YYYY-MM-DD` sin `java.time`
    en común (Android/JVM `LocalDate.now()`; iOS `NSDateFormatter`; Wasm `Date`
    local). Es la fecha que exige `/v1/feed`.
- **`HttpClientFactory.kt`** — `fun createDatoPublicoHttpClient(): HttpClient` con
  `HttpClient { … }` (sin motor explícito: Ktor resuelve el motor del *source set* de
  cada plataforma) y una extensión reutilizable
  `HttpClientConfig<*>.configureDatoPublicoClient()` que instala `ContentNegotiation`
  (`Json { ignoreUnknownKeys = true }`), `HttpTimeout` explícito y `expectSuccess =
  false`. Los tests construyen `HttpClient(MockEngine) { configureDatoPublicoClient() }`.
- **`ApiResult.kt`** — `sealed interface ApiResult<out T>` (`Success(data)` /
  `Failure(reason)`) y `sealed interface ApiFailure` (`Network`, `Server(status, code?)`,
  `InvalidBody`): los fallos son **valores**, no excepciones.
- **`ClientApiErrorDto.kt`** — DTO de error de wire del cliente (espejo de
  `ApiErrorDto`/`ApiErrorCodeDto`) para leer el cuerpo tipado de `400/404/429/500/502`.

### Capa de datos del feed

- **`feature/feed/data/remote/FeedResponseDto.kt`** — DTOs de wire del cliente:
  `FeedResponseDto` (`fecha`, `publicaciones`, `destacados`, paginación),
  `FeedPublicationDto` (`id`, `titulo`, `fechaPublicacion`, `categoria`, `urlOficial`,
  `resumen?`, `plazo?`), `FeedHighlightDto` (`publicacion`, `motivos`),
  `FeedDeadlineDto` (`fechaLimite`). Cada propiedad con `@SerialName`.
- **`feature/feed/data/remote/FeedDtoMapper.kt`** — funciones puras
  `FeedResponseDto → DailyFeed` y `FeedPublicationDto → Publication`: traduce los
  tokens `snake_case` (`categoria`, `motivos`) a los enums de dominio, deriva
  `shortSummary` de `resumen.queCambia` y marca `isHighlighted`/`highlightReasons`
  cruzando `publications` con `destacados`. **No lanza**: campos ausentes usan valores
  seguros.
- **`feature/feed/data/remote/FeedApi.kt`** — `suspend fun dailyFeed(date: String):
  ApiResult<FeedResponseDto>` contra `GET {baseUrl}/v1/feed?fecha=…`; `200` ⇒ decodifica
  el cuerpo; no-2xx ⇒ intenta `ClientApiErrorDto` y devuelve `ApiFailure.Server`;
  excepciones de red/serialización (salvo `CancellationException`, que se re-lanza) ⇒
  `ApiFailure.Network`/`InvalidBody`. Sin `else if`, un solo `return`.
- **`feature/feed/data/cache/FeedCache.kt`** — puerto `suspend fun read(): DailyFeed?`
  / `suspend fun write(feed: DailyFeed)`.
- **`feature/feed/data/cache/InMemoryFeedCache.kt`** — implementación en memoria (último
  feed), sin persistencia ni datos personales; base para una futura cache persistente.
- **`feature/feed/data/HttpFeedRepository.kt`** — implementa el puerto `FeedRepository`
  de FT00032: pide el feed del día (`dateProvider` inyectable, por defecto
  `currentIsoDate`); en éxito mapea, **escribe la cache** y devuelve `Success`; en fallo
  **lee la cache**: si existe, `Success(cacheado)`; si no, `Failure`. Misma semántica
  que el repositorio en memoria (vacío ⇒ `Success(feed vacío)` ⇒ `FeedUiState.Empty`).

### Composition root (`App.kt`)

`App()` construye, con `remember`, el `HttpClient` app-scoped, `FeedApi`, la
`InMemoryFeedCache` y el `HttpFeedRepository`, y los inyecta en
`GetDailyFeed` → `FeedStateHolder`. Es el único cambio de FT00035 en la UI; si FT00034
aterriza antes, el mismo repositorio se inyecta en la factoría del ViewModel. La
`@Preview` de `App()` no lanza la red en modo estático (muestra `Loading`); las
previews de estados siguen usando `InMemoryFeedRepository` (sin red).

### Build y plataformas

- `:composeApp`: `alias(libs.plugins.kotlin.serialization)`; en `commonMain`
  `ktor-client-core`, `ktor-client-content-negotiation`, `ktor-serialization-kotlinx-json`
  y `kotlinx-serialization-json`; motores por *source set* (`androidMain`
  `ktor-client-okhttp`; `jvmMain` `ktor-client-cio`; `iosMain` `ktor-client-darwin`;
  `wasmJsMain` `ktor-client-js`); en `commonTest` `ktor-client-mock`. Se añaden solo
  los alias nuevos al catálogo (`ktor-client-okhttp`, `ktor-client-darwin`,
  `ktor-client-js`); versiones ya fijadas en `3.0.3`.
- **Android, permiso y tráfico claro**: se añade `<uses-permission
  android:name="android.permission.INTERNET" />` (hoy **no** está) y, como el emulador
  habla `http://10.0.2.2:8080` y con `targetSdk 35` el tráfico claro está bloqueado,
  `android:networkSecurityConfig` con permiso de claro **solo** para `10.0.2.2`/
  `localhost` (evita `usesCleartextTraffic` global); el manifiesto conserva el tema sin
  ActionBar.
- **iOS**: el framework queda listo; el permiso ATS para `http://localhost` vive en el
  proyecto Xcode (FT00040) — riesgo declarado. **Wasm**: CORS ya lo resuelve FT00030.

### Estilo y límites a vigilar

- **Sin crash**: todo fallo (red, HTTP, JSON) se modela; nunca `throw`/`TODO()` como
  control. `CancellationException` se re-lanza para no romper la cancelación.
- **Un solo `return`**, sin `else if`, ≤40 líneas/función; `when` como expresión.
- **CPD**: factorizar la configuración del cliente para que los tests la reutilicen
  (evita duplicar bloques >100 tokens).

## Expected File Changes

Rutas en el repo de producto (`..`); `es/aviferdev/datopublico` se abrevia `…`:

- `gradle/libs.versions.toml` — modify; alias `ktor-client-okhttp`, `ktor-client-darwin`,
  `ktor-client-js` (+ comentario FT00035).
- `composeApp/build.gradle.kts` — modify; plugin de serialización, deps ktor
  `commonMain`/motores por *source set* y `ktor-client-mock` en `commonTest`.
- `composeApp/src/commonMain/kotlin/…/core/network/ApiConfig.kt` — create.
- `composeApp/src/commonMain/kotlin/…/core/network/Platform.kt` — create (expect).
- `composeApp/src/androidMain/kotlin/…/core/network/Platform.android.kt` — create (actual).
- `composeApp/src/iosMain/kotlin/…/core/network/Platform.ios.kt` — create (actual).
- `composeApp/src/wasmJsMain/kotlin/…/core/network/Platform.wasmJs.kt` — create (actual).
- `composeApp/src/jvmMain/kotlin/…/core/network/Platform.jvm.kt` — create (actual; dir nueva).
- `composeApp/src/commonMain/kotlin/…/core/network/HttpClientFactory.kt` — create.
- `composeApp/src/commonMain/kotlin/…/core/network/ApiResult.kt` — create.
- `composeApp/src/commonMain/kotlin/…/core/network/ClientApiErrorDto.kt` — create.
- `composeApp/src/commonMain/kotlin/…/feature/feed/data/remote/FeedResponseDto.kt` — create.
- `composeApp/src/commonMain/kotlin/…/feature/feed/data/remote/FeedDtoMapper.kt` — create.
- `composeApp/src/commonMain/kotlin/…/feature/feed/data/remote/FeedApi.kt` — create.
- `composeApp/src/commonMain/kotlin/…/feature/feed/data/cache/FeedCache.kt` — create.
- `composeApp/src/commonMain/kotlin/…/feature/feed/data/cache/InMemoryFeedCache.kt` — create.
- `composeApp/src/commonMain/kotlin/…/feature/feed/data/HttpFeedRepository.kt` — create.
- `composeApp/src/commonMain/kotlin/…/app/App.kt` — modify; inyecta el repositorio HTTP.
- `composeApp/src/androidMain/AndroidManifest.xml` — modify; permiso `INTERNET` +
  `networkSecurityConfig`.
- `composeApp/src/androidMain/res/xml/network_security_config.xml` — create.
- `composeApp/src/commonTest/kotlin/…/feature/feed/data/remote/FeedDtoMapperTest.kt` — create.
- `composeApp/src/commonTest/kotlin/…/feature/feed/data/remote/FeedApiTest.kt` — create.
- `composeApp/src/commonTest/kotlin/…/feature/feed/data/HttpFeedRepositoryTest.kt` — create.
- `composeApp/src/commonTest/kotlin/…/feature/feed/data/cache/InMemoryFeedCacheTest.kt` — create.
- `docs/desarrollo-local.md` — modify; cliente HTTP, URL base por plataforma y caché.

Harness (privado, repo aparte): ADR `0028` + índice, `ARCHITECTURE.md`,
`CONSTRAINTS.md`, skill `compose-multiplatform-architecture`, `PROGRESS.md`,
`feature_list.json` (ver *Durable Documentation Impact*).

Total ≈ **25 ficheros de producto** → **atómica**, sin división en `FT00035-PTn`.

## Visual Design Impact

- UI involved: **no** (cambio de capa de datos). El layout, el tema, los componentes y
  los textos del feed **no** cambian (`DESIGN.md` intacto).
- Capturas: **no obligatorias** (`docs/pr/README.md`: solo si cambian píxeles). Se
  recomienda adjuntar, como evidencia, una captura opcional de la app con el
  repositorio HTTP (estado de error/offline o datos reales) en
  `docs/pr/ft00035-ui-cliente-http-cache/`, o justificar en el PR que no hay cambio
  visual.

## Durable Documentation Impact

- `ARCHITECTURE.md`: **update** — `:composeApp` gana `core/network/` (cliente HTTP
  común, `expect/actual` de URL/fecha, resultados tipados), DTOs de cliente y cache en
  `feature/feed/data/`, y deja de usar solo el repositorio en memoria; se anota que
  `:shared` sigue sin cablearse y por qué.
- `CONSTRAINTS.md`: **update** (pequeño) — MUST nuevos del cliente: el HTTP va por el
  cliente común de `core/network` (con `HttpTimeout` y errores tipados), la URL base se
  resuelve por plataforma (nunca en `commonMain`) y la cache offline es un puerto sin
  datos personales.
- `AGENTS.md`: **not needed** — no cambia el flujo, el arranque ni la verificación.
- Other docs: `docs/adr/0028-*.md` — **create** (decisión durable: cliente HTTP común,
  DTOs de cliente como capa anti-corrupción sin cablear `:shared`, cache offline en
  memoria y URL por plataforma) + índice `docs/adr/README.md`; skill
  `compose-multiplatform-architecture` §«Estado actual» — **update**;
  `docs/desarrollo-local.md` (producto) — **update**.

## Implementation Plan

1. Catálogo + `composeApp/build.gradle.kts` (plugin de serialización, deps ktor y
   motores por *source set*); comprobar que `assembleDebug`/`wasmJsBrowserDistribution`
   resuelven los motores.
2. `core/network`: `ApiConfig`, `Platform` (expect) + 4 actuals, `ApiResult`,
   `ClientApiErrorDto`, `HttpClientFactory`.
3. `feature/feed/data/remote`: DTOs, `FeedDtoMapper`, `FeedApi`; tests de mapeo y de la
   API con `MockEngine` (200/400/404/429/500/502, JSON inválido y excepción de red).
4. Cache: `FeedCache` + `InMemoryFeedCache` (+ test).
5. `HttpFeedRepository` (éxito cachea; fallo respalda a cache; sin cache ⇒ `Failure`) y
   su test.
6. `App()`: inyectar el repositorio HTTP; manifiesto Android + config de red.
7. Verificar el gate (SDK-free y con cliente) y los tres targets; actualizar
   `ARCHITECTURE.md`, `CONSTRAINTS.md`, ADR 0028 + índice, la skill y
   `docs/desarrollo-local.md`. `PROGRESS.md`/`feature_list.json` los cierra el
   orquestador.

## Implementation Tasks

- [ ] `libs.versions.toml` + `composeApp/build.gradle.kts` (serialización, ktor y
      motores OkHttp/CIO/Darwin/JS, `ktor-client-mock` en tests).
- [ ] `core/network/{ApiConfig,Platform,ApiResult,ClientApiErrorDto,HttpClientFactory}.kt`.
- [ ] `Platform.android/ios/wasmJs/jvm.kt` (`actual`: URL base y fecha ISO).
- [ ] `feature/feed/data/remote/{FeedResponseDto,FeedDtoMapper,FeedApi}.kt`.
- [ ] `feature/feed/data/cache/{FeedCache,InMemoryFeedCache}.kt`.
- [ ] `feature/feed/data/HttpFeedRepository.kt` (fallback a cache).
- [ ] `App.kt` con el repositorio HTTP; `AndroidManifest.xml` (permiso `INTERNET` +
      `networkSecurityConfig`) y `res/xml/network_security_config.xml`.
- [ ] Tests `commonTest`: mapeo, `FeedApi` (`MockEngine`), `HttpFeedRepository`
      (offline con/sin cache), `InMemoryFeedCache`.
- [ ] Gate: `build -PskipClient`, `test`, `detekt` + `:cpdCheck`, `init.sh` (SDK-free) y
      `init.sh --with-client`; framework iOS.
- [ ] Docs durables (ADR 0028 + índice, `ARCHITECTURE.md`, `CONSTRAINTS.md`, skill,
      `docs/desarrollo-local.md`).

## Verification Plan

Desde la raíz del producto (`..`, JDK 21; Android SDK para el cliente):

- **Gate SDK-free (obligatorio, sin cambios)**: `./gradlew build -PskipClient`,
  `./gradlew test`, `./gradlew detekt` (+ `:cpdCheck`) y `.harness/init.sh` →
  BUILD SUCCESSFUL / exit 0. `init.sh` **no** se modifica.
- **Gate con cliente (`--with-client`)**: `./gradlew :composeApp:assembleDebug`,
  `./gradlew :composeApp:wasmJsBrowserDistribution` y `./gradlew :composeApp:jvmTest`
  (tests nuevos + los 15 de FT00032) en verde; `./gradlew detekt` cubre `:composeApp`.
- **iOS (host macOS)**: `./gradlew :composeApp:compileKotlinIosSimulatorArm64` +
  `:composeApp:linkDebugFrameworkIosSimulatorArm64` (o `init.sh --with-ios`).
- **Tests (evidencia principal, sin red ni BD)**: `FeedApiTest` (200 decodifica; 400/
  404/429/500/502 → `ApiFailure.Server` con `codigo`; JSON inválido → `InvalidBody`;
  excepción del motor → `Network`); `HttpFeedRepositoryTest` (éxito cachea; fallo con
  cache → `Success`; fallo sin cache → `Failure`; la fecha inyectada viaja en la
  query); `FeedDtoMapperTest` (categorías/motivos/plazo/destacados y campos ausentes);
  `InMemoryFeedCacheTest`.
- **Manual (opcional, una plataforma)**: arrancar el backend (`:backend:run`) y la app
  Web/Android; comprobar la petición a `/v1/feed` y el estado de error con el backend
  parado. El feed real puede salir **vacío** (pipeline de resumen no cableado), así que
  la evidencia fuerte son los tests con `MockEngine`.
- **Offline**: se verifica con el test `HttpFeedRepositoryTest` (red caída + cache ⇒
  `Success` cacheado); manualmente, cargar con backend accesible y pararlo antes de
  «Reintentar».
- **Sin red ni BD**: ningún test ni gate abre sockets ni toca PostgreSQL.
- **E2E**: no aplica — el repo **no** tiene comando E2E persistente para el cliente
  (Wasm/Karma fuera del gate); la cobertura es unitaria/integración con `MockEngine`.
- **Capturas**: no obligatorias (sin cambio visual); captura opcional de la app con el
  repositorio HTTP o justificación en el PR.

## Evidence To Capture

- Salida de `:composeApp:jvmTest` (recuento, 0 fallos), `assembleDebug`,
  `wasmJsBrowserDistribution` y del gate (`build -PskipClient`, `test`, `detekt` +
  `:cpdCheck`, `init.sh` exit 0; `--with-client` verde).
- Confirmación de que `:shared`/`:backend`/CI/`init.sh` **no** cambian y de que no se
  añaden dependencias fuera de ktor/serialización.
- Confirmación (grep) de que **no** hay URLs en `commonMain` y de que los DTOs de
  cliente llevan `@SerialName`.
- Ficheros del commit `FT00035`, PR y run de CI; entradas en `PROGRESS.md` y
  `feature_list.json` (`evidence`).

## Validator Checklist

- [ ] Alcance: solo capa de red/cache del cliente + wiring en `App()`; **sin**
      `ViewModel`/`StateFlow`/navegación, **sin** detalle/búsqueda/chat, **sin** cambios
      en `:shared`/`:backend`/CI/`init.sh`/`DESIGN.md`.
- [ ] Escenarios 1–9 pasan (feed real, error sin cache, offline con cache, errores
      tipados, JSON inválido, URL por plataforma, UI sin cambios, estilo MUST, gate).
- [ ] `:composeApp` **no** depende de `:shared`; el gate SDK-free sigue verde y el
      cliente compila Android/Wasm/iOS.
- [ ] Los DTOs de cliente llevan `@SerialName`; identificadores en inglés, KDoc en
      castellano; un solo `return`, sin `else if`, funciones ≤40 líneas; sin crashes
      (fallos modelados; `CancellationException` re-lanzada).
- [ ] URL base solo en `expect/actual` (nunca en `commonMain`); `HttpTimeout` explícito.
- [ ] Cache sin datos personales (solo contenido público); el feed cacheado se muestra
      cuando la red falla.
- [ ] `docs/adr/0028`, `ARCHITECTURE.md`, `CONSTRAINTS.md`, la skill de CMP y
      `docs/desarrollo-local.md` actualizados; PR ≤ 30 ficheros.

## Risks / Open Questions

- **Duplicación del contrato (capa anti-corrupción).** Los DTOs de cliente replican el
  subconjunto de `:shared` usado por el feed; si el contrato cambia, hay que
  actualizarlos a mano (el test anti-deriva de `:shared` no los cubre). Mitigación:
  tests que decodifican respuestas de ejemplo del contrato y KDoc que enlaza a
  `docs/specs/api-feed-diario.md`; a futuro, sustituirlos por los de `:shared` cuando
  sea multiplataforma. **Es la decisión más discutible del plan.**
- **Motores ktor y Android.** `ktor-client-okhttp` se publica solo con variante `jvm`
  (Ktor 3.0.3) y Android la consume; verificar en `assembleDebug`. Si fallara, usar
  `ktor-client-android` o un `expect/actual` de motor.
- **Cache en memoria.** No sobrevive al reinicio; «offline» aquí significa «red caída en
  la misma sesión», que es lo que pide la verificación. La persistencia
  (SQLDelight/fichero/almacenamiento multiplataforma, con `Context` en Android) queda
  como follow-up; si el orquestador la exige, FT00035 se divide en `FT00035-PT1`
  (HTTP) y `FT00035-PT2` (cache persistente).
- **Sin indicador de «sin conexión».** El feed cacheado se muestra como contenido
  normal; señalizarlo exigiría tocar `FeedUiState`/`FeedScreen` (FT00034/FT00043).
- **iOS y tráfico claro.** ATS bloquea `http://localhost` salvo excepción en el
  proyecto Xcode, que aún no existe (FT00040); el framework queda listo pero la
  verificación manual en iOS se limita a compilación/enlace.
- **Feed real vacío.** El pipeline de resumen no está cableado (Session 068): la
  verificación de la ruta HTTP se apoya en `MockEngine`, no en datos de producción.
- **`currentIsoDate` y zona horaria.** Se usa la fecha **local** del dispositivo; Wasm
  con `toLocaleDateString('en-CA')` y iOS con `NSDateFormatter` local. Un dispositivo en
  otra zona puede pedir un día distinto al del servidor (aceptable en el MVP).
- **División.** ≈25 ficheros: por debajo de 30 → **atómica**; no procede partir en
  `FT00035-PTn` salvo que se incorpore la cache persistente.
