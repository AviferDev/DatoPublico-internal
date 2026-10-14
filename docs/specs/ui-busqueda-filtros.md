# Feature Implementation Spec: UI de búsqueda con filtros

## Source Feature

- `id`: ui-busqueda-filtros
- `ft_id`: FT00036 (registrado en `docs/feature-ids.md`)
- `parts`: none (atómica; ≈20–22 ficheros de producto, por debajo del límite de 30)
- `area`: cliente-cmp
- `depends_on`: api-busqueda (FT00028, `accepted`) + ui-navegacion-estado
  (FT00034, **en validación; aún sin mergear**)
- `status`: not_started (al planificar)
- `source`: `feature_list.json` (`notes`: `docs/roadmap.md` 0.9-T01; contrato
  `SearchResultsDto` de FT00028)
- `claim`: rama `feat/ft00036-ui-busqueda-filtros` ya reclamada en `origin`
  (`619a8ae chore(FT00033): claim ui-busqueda-filtros`), con base `082245b`
  (`feat(FT00033): complete ui-detalle`). **La base actual NO incluye FT00034**;
  el implementador debe **rebasarla** sobre FT00034 cuando se mergee (ver *Risks*).
  Sin PR abierto hacia `main`.

> **Tercera pantalla real del cliente.** Reutiliza la base de FT00032 (tema
> `DatoPublicoTheme`, `design/components/`, i18n por recursos, capas
> `feature/<nombre>/{domain,data,ui}`), el contrato de navegación/estado de FT00034
> (`AppNavHost`/`AppRoutes`, `ViewModel` + `StateFlow` + `collectAsStateWithLifecycle`)
> y la pantalla de detalle de FT00033 (ya en `main`). Añade la pantalla de
> **búsqueda**: campo de texto + filtros de **categoría** y **fecha** + resultados +
> estado «sin resultados». Deriva de `docs/roadmap.md` 0.9-T01, `DESIGN.md` (§Core
> Screens 3 «Búsqueda» y 5 «Estados») y del contrato `SearchResultsDto` de FT00028,
> **sin inventar**.

## Goal

Construir en `commonMain` de `:composeApp` la **pantalla de búsqueda**: un campo de
texto, **filtros de categoría** (las 11 categorías curadas) y **de fecha**
(`desde`/`hasta`, ISO), una lista de **resultados** con la tarjeta reutilizada del
feed y los estados **inicial / carga / resultados / sin resultados / error**, todo
con la dirección visual de `DESIGN.md`.

La feature introduce la **tercera capa de feature** (`feature/search/`) con modelos
de dominio propios del cliente, un caso de uso, un repositorio **en memoria** de
ejemplo (el cliente HTTP/caché real es FT00035) y un **`SearchViewModel` con
`StateFlow`** siguiendo el patrón que fija FT00034. Conecta la pantalla al **grafo de
navegación** de FT00034 (destino nuevo `search`, resultados → detalle existente
`detail/{publicationId}`) y añade un **acceso desde el feed**. Los resultados son
`Publication` (el mismo modelo del feed), porque `/v1/buscar` devuelve el **mismo**
`PublicacionDto` que `/v1/feed` (ADR 0021/0023).

## Non-Goals

- **Cliente HTTP, `:shared` y cache offline** (FT00035): no se cablea red, ni
  `ktor-client`, ni el mapeo `PublicacionDto → Publication`, ni `expect/actual`. El
  repositorio es `InMemorySearchRepository` (datos de ejemplo). FT00035 lo sustituye.
- **Navegación y patrón de estado base** (FT00034): **no** se reimplementan
  `AppNavHost`/`AppRoutes`/ViewModel/`StateFlow`/DI; se **extienden** (un destino y
  una ruta nuevos, una factory nueva) y se **reutilizan**.
- **Detalle real** (FT00033): ya existe; la búsqueda **navega** a él, no lo modifica.
- **Filtro de «ámbito»** (sección/organismo) que menciona `0.9-T01`: el endpoint
  `/v1/buscar` **no** lo expone (solo `categoria`, `desde`, `hasta`, `limite`; ver
  `docs/specs/api-busqueda.md`, *Non-Goals*). Se **difiere**: requeriría ampliar
  FT00028. La `uvb` de FT00036 solo pide **categoría y fecha**.
- **Historial de búsquedas, sugerencias/autocompletado, paginación, snippet del
  fragmento, «compartir»/deep links** (`0.9-T02`/`0.9-T03`) y **chat** (FT00037).
- **Modo oscuro, i18n multi-idioma y accesibilidad formal** (FT00043); **empaquetado**
  (FT00038–FT00040); **avisos legales** (FT00044).
- **No** se cambia el contrato de `:shared`, ni `:backend`, ni migraciones, ni
  `init.sh`, ni CI, ni `DESIGN.md`, ni las dependencias de Gradle.

## Job Story

When quiero encontrar algo concreto en el BOE y no me basta con el feed del día
(«becas para jóvenes», «oposiciones de sanidad»),
I want escribir una búsqueda y acotarla por categoría y por rango de fechas, ver
resultados con su categoría y fecha, y abrir el que me interese,
so I can encontrar normas más allá del día de hoy y llegar a su detalle con la
fuente oficial, sin cuentas ni ruido.

## Users And Permissions

- **Ciudadanía (usuario final):** anónima, solo lectura; sin cuentas, sin datos
  personales, sin analítica. La búsqueda no pide permisos ni persiste nada.
- **Desarrollador (único actor técnico):** ejecuta los gates y sirve la app
  (Android/Web) para verificar y capturar la pantalla.
- Sin autenticación ni autorización.

## Acceptance Scenarios

### Scenario 1: búsqueda con texto y filtro de categoría

Given la pantalla de búsqueda con el campo de texto y el filtro de categoría,
When escribo un término y elijo una categoría (p. ej. «Becas y subvenciones») y
envío,
Then aparecen los **resultados** en tarjetas (`PublicationCard`) **solo** de esa
categoría, con su categoría y su fecha visibles; el estado pasa por `Loading` y
llega a `Content`.

### Scenario 2: filtro de rango de fechas inclusivo

Given publicaciones en fechas distintas,
When indico `desde` y `hasta` (ISO `aaaa-mm-dd`) y envío,
Then solo aparecen resultados con `desde <= fechaPublicacion <= hasta`.

### Scenario 3: sin resultados

Given una búsqueda cuya combinación de texto y filtros no casa con ninguna
publicación,
When se envía,
Then aparece el estado **«sin resultados»** (icono + mensaje), **no** un error ni
una lista vacía sin explicación.

### Scenario 4: estado inicial

Given la pantalla recién abierta, antes de buscar,
When se muestra,
Then aparece el **estado inicial** (invitación a buscar + campo + filtros), **no**
un `Loading`, un error ni «sin resultados». Enviar con la consulta en blanco **no**
lanza ninguna petición y mantiene el estado inicial.

### Scenario 5: error y reintento

Given un repositorio que devuelve **fallo** (resultado tipado, sin excepción),
When se envía la búsqueda,
Then aparece el **estado de error** (icono + mensaje + botón «Reintentar»); pulsar
«Reintentar» repite la **última** búsqueda y, si el repositorio responde, pasa a
resultados. La app **nunca** se cierra por este fallo.

### Scenario 6: estado de carga

Given que el repositorio tarda un instante en responder,
When se envía la búsqueda y aún no hay resultados,
Then se muestra un **indicador de carga** hasta que llegan los resultados.

### Scenario 7: abrir un resultado lleva al detalle

Given una lista de resultados con contenido,
When pulso una tarjeta,
Then la app navega al destino de **detalle** de FT00034/FT00033 con el `id` de esa
publicación (`BOE-A-…`); el **atrás** vuelve a la búsqueda **conservando** el estado
(texto, filtros y resultados).

### Scenario 8: acceso desde el feed

Given la pantalla del feed (FT00032/FT00034),
When pulso la acción de **búsqueda** del encabezado,
Then se navega al destino `search`; el **atrás** vuelve al feed.

### Scenario 9: i18n, previews, Material Icons y colores del tema

Given el código nuevo de UI,
When se revisan los composables,
Then **cada** función `@Composable` de UI (incluidas las privadas) tiene su
`@Preview` dentro del tema; **ningún** texto visible está hardcodeado (solo
literales en `@Preview`); los iconos con significado usan Material Icons
(`Icons.Outlined.*`/`Icons.AutoMirrored.Outlined.*`) con `contentDescription`; y los
colores salen **solo** de `MaterialTheme.colorScheme.*`.

### Scenario 10: validación de fechas sin crash

Given los campos `desde`/`hasta`,
When introduzco una fecha que no es ISO (`aaaa-mm-dd`) o dejo el rango invertido,
Then la app **no** se cierra: la fecha inválida se marca/omite sin enviarse y un
rango invertido no provoca error (el endpoint responde lista vacía → estado «sin
resultados»).

### Scenario 11: misma UI en las tres plataformas

Given la UI en `commonMain`,
When compilo Android (`:composeApp:assembleDebug`), Web
(`:composeApp:wasmJsBrowserDistribution`) e iOS
(`:composeApp:linkDebugFrameworkIosSimulatorArm64`, host macOS),
Then las tres compilan y montan la **misma** pantalla de búsqueda; cada plataforma
aporta **solo** su entrypoint.

### Scenario 12: el gate sigue verde

Given un entorno sin red ni base de datos,
When ejecuto `./gradlew build -PskipClient`, `./gradlew test`, `./gradlew detekt`
(+ `:cpdCheck`) y `.harness/init.sh`,
Then el gate SDK-free sigue en verde (no exige Android SDK) y, con el cliente
(`.harness/init.sh --with-client`), también quedan verdes
`:composeApp:assembleDebug`, `:composeApp:wasmJsBrowserDistribution`,
`:composeApp:jvmTest` y el análisis estático. `init.sh` **no** se modifica.

### Scenario 13: capturas antes/después

Given un cambio de interfaz,
When se abre el PR,
Then la rama incluye capturas **antes** (app base: feed sin acción de búsqueda ni
pantalla de búsqueda) y **después** (pantalla de búsqueda con resultados y, si se
puede, el estado «sin resultados») en `docs/pr/ft00036-ui-busqueda-filtros/`,
enlazadas con URL absoluta a la rama (`docs/pr/README.md`); si no se puede capturar
algún estado, se justifica.

## Repository Research

### Files Inspected

- `composeApp/src/commonMain/kotlin/…/feature/feed/domain/FeedModels.kt` —
  `Publication` (id, title, category, publishedDate, shortSummary, isHighlighted,
  highlightReasons, deadline, officialUrl), `PublicationCategory` (11 valores),
  `HighlightReason`, `Deadline`, `FeedLoadResult` (tipado) y `formatIsoDate`
  (`internal`, `dd/mm/aaaa`). **Es el modelo que reutiliza la búsqueda** (los
  resultados son publicaciones del mismo contrato).
- `composeApp/src/commonMain/kotlin/…/feature/feed/data/InMemoryFeedRepository.kt` —
  patrón exacto a replicar en `feature/search/data`: puerto + implementación en
  memoria con `enum` de modos (`SAMPLE`/`EMPTY`/`UNAVAILABLE`), `latencyMillis`
  inyectable y datos de ejemplo deterministas.
- `composeApp/src/commonMain/kotlin/…/feature/feed/ui/{FeedRoute,FeedScreen,
  FeedUiState}.kt` — patrón de UI: `FeedScreen(state, onRetry)` **stateless** con
  vistas privadas de carga/vacío/error y `@Preview` por estado. `FeedScreen` pinta
  el encabezado `app_title` (sin barra de acciones) → punto donde añadir la acción
  de búsqueda.
- `composeApp/src/commonMain/kotlin/…/feature/detail/{domain/DetailModels.kt,
  data/InMemoryDetailRepository.kt, ui/DetailRoute.kt}` — patrón de la segunda capa
  (`DetailLoadResult` tipado, modos `SAMPLE`/`NOT_FOUND`/`UNAVAILABLE`,
  `DetailRoute(stateHolder, onBack)` como contrato de invocación).
- `composeApp/src/commonMain/kotlin/…/design/components/{PublicationCard,
  CategoryLabel,PublicationBadges}.kt` — `PublicationCard(publication, modifier)`
  (hoy **sin** `onClick`; FT00034 añade el clic) reutilizable para los resultados;
  `CategoryLabel` resuelve texto i18n + tono (no hay un color por categoría).
  `design/components/` importa el vocabulario de `feature/feed/domain` (ADR 0028).
- `composeApp/src/commonMain/kotlin/…/design/theme/DatoPublicoTheme.kt` — tema único
  (tokens de `DESIGN.md`); `tertiary` = `accent`.
- `composeApp/src/commonMain/composeResources/values/strings.xml` — **47** claves
  (feed + detalle + 11 categorías + estados + `contentDescription`); hay que **añadir**
  las de búsqueda (campo, filtros, «sin resultados», carga, error, reintentar, atrás,
  `contentDescription`).
- `composeApp/src/commonMain/kotlin/…/app/App.kt` — *composition root* manual: hoy
  `remember { FeedStateHolder(GetDailyFeed(InMemoryFeedRepository())) }` +
  `DatoPublicoTheme { Surface { FeedRoute(...) } }`. FT00034 lo convierte en
  `DatoPublicoTheme { AppNavHost(feedViewModelFactory, …) }`.
- `composeApp/build.gradle.kts` — `commonMain` ya tiene
  `compose.components.resources`; `commonTest` tiene `kotlinx-coroutines-test`;
  **sin** dependencias nuevas previstas. FT00034 añade lifecycle/navigation
  (`org.jetbrains.androidx.*`).
- `config/detekt/detekt.yml` — `TooManyFunctions.thresholdInFiles: 15` (límite por
  fichero a vigilar al repartir la UI de búsqueda).
- `shared/src/commonMain/kotlin/…/model/SearchResultsDto.kt` — contrato de respuesta
  de FT00028: `@SerialName("q") query` + `@SerialName("resultados")
  results: List<PublicacionDto>`. **No** se cablea en FT00036 (FT00035), pero fija la
  forma del resultado (lista de publicaciones).
- `backend/…/plugins/{Routing,Search}.kt` — `GET /v1/buscar` (bajo el prefijo `/v1`
  de FT00029) con `q` (obligatoria), `categoria` (token de wire `CategoriaDto`),
  `desde`/`hasta` (ISO inclusivas), `limite` (default 10, máx 50).
- `.harness/DESIGN.md` — §Core Screens 3 («Búsqueda: campo + filtros (categoría,
  fecha) + resultados») y 5 («Estados: … "sin resultados"»), §Components (tarjeta).
- `.harness/CONSTRAINTS.md` §«Cliente (Compose Multiplatform)» — MUST de UI
  (previews, i18n por recursos, Material Icons, colores solo de `colorScheme`, no
  crash, un solo `return`, sin `else if`, ≤40 líneas/función, 30 ficheros, capturas);
  MUST de que el vocabulario (`PublicationCategory`/`Deadline`/`formatIsoDate`) se
  reutiliza desde `feature/feed/domain` (ADR 0028).
- `.harness/ARCHITECTURE.md` §`:composeApp`, `docs/roadmap.md` §0.9 (0.9-T01),
  `docs/adr/0027`/`0028`, `docs/technical-discovery.md` (StateFlow/ViewModels),
  skill `compose-multiplatform-architecture` (§Estado/UDF, §Navegación y DI,
  §Pantallas 3, §Tests) y specs `ui-feed.md`, `ui-detalle.md`,
  `ui-navegacion-estado.md`, `api-busqueda.md`.
- `docs/desarrollo-local.md` (producto) — guía a actualizar.
- Git: `main` = `082245b` (incluye FT00032+FT00033); rama FT00036 base `082245b`;
  FT00034 **sin mergear** (su rama parte de FT00032 y aún **borra** los ficheros de
  FT00033: hay que rebasarla antes de mergear).

### Existing Patterns To Follow

- **UI única en `commonMain`**, entrypoints mínimos por plataforma; **DI manual** por
  constructor/factory.
- **Arquitectura por capas** `feature/<nombre>/{domain,data,ui}` con resultado
  **tipado** (sin excepción) y **use case** obligatorio (`operator fun invoke`).
- **Estado objetivo (FT00034)**: `XViewModel` con `val uiState: StateFlow<XUiState>`,
  UDF (estado inmutable, eventos como métodos), composables **stateless**,
  `collectAsStateWithLifecycle()`.
- **Reutilización**: `PublicationCard`/`CategoryLabel`/`DeadlineBadge`,
  `DatoPublicoTheme`, `Publication`/`PublicationCategory`/`Deadline`/`formatIsoDate`
  (desde `feature/feed/domain`, ADR 0028), `AppNavHost`/`AppRoutes`.
- **Estilo MUST**: identificadores en inglés, KDoc/comentarios en castellano, un solo
  `return`, sin `else if`, funciones ≤40 líneas, sin crashes, sin literales de color
  de runtime; `@Preview` en toda función `@Composable`.
- **Tests de estado/dominio en `commonTest`** (corren en `:composeApp:jvmTest` y
  Android/iOS), sin tests de vistas.

### Current Gaps

- No existe `feature/search/` ni una pantalla de búsqueda; el feed **no** tiene
  acción de búsqueda.
- No existe el destino `search` en el grafo (lo crea FT00034; FT00036 lo extiende).
- El cliente **no** consume `:shared` y no hay HTTP (FT00035): la búsqueda real
  devolvería resultados vacíos hasta que el corpus esté indexado; se usan datos de
  ejemplo (ver *Risks*).
- No hay comando E2E persistente para el cliente (`wasmJsBrowserTest` fuera del gate).

## Technical Approach

La pantalla **representa** el contrato de `/v1/buscar` con **modelos de dominio
propios del cliente** y se alimenta de un **repositorio en memoria** con datos de
ejemplo. Se mantiene `:composeApp` desacoplado de `:shared` y el gate SDK-free. Los
resultados reutilizan `Publication` y `PublicationCard` (los ítems de `/v1/buscar`
son el mismo `PublicacionDto` del feed); en los resultados de búsqueda
`isHighlighted=false` y `highlightReasons=emptyList()` (sin badges de destacado),
pero se conserva el `deadline` (badge de plazo) si la publicación lo tiene.

### 1. Capas de la feature (`feature/search/`, create)

- **Dominio** (`domain/`):
  - `SearchModels.kt`: `data class SearchFilters(category: PublicationCategory? =
    null, fromDate: String? = null, toDate: String? = null)`, `data class
    SearchResults(query: String, publications: List<Publication>)`, `sealed interface
    SearchLoadResult { Success(results: SearchResults) / Failure }` (tipado, sin
    excepción) y `fun isIsoDate(value: String): Boolean` (puro; `aaaa-mm-dd`, sin
    `java.time`). Sin sufijo (`Publication` se importa de `feature/feed/domain`).
  - `SearchPublications.kt`: use case `class SearchPublications(private val
    repository: SearchRepository) { suspend operator fun invoke(query: String,
    filters: SearchFilters): SearchLoadResult }`; `require(query.isNotBlank())`
    (mirror del endpoint; el ViewModel no llama con consulta en blanco).
- **Datos** (`data/`):
  - `SearchRepository.kt`: *port* `suspend fun search(query: String, filters:
    SearchFilters): SearchLoadResult` (FT00035 lo implementará sobre
    `/v1/buscar`).
  - `InMemorySearchRepository.kt`: implementación **en memoria** con un conjunto de
    publicaciones de ejemplo (reutiliza `sampleFeed().publications` o un set propio
    con varias categorías y fechas) que **filtra** por texto (título/resumen, sin
    distinguir mayúsculas), categoría y rango de fechas (inclusivo, ISO por
    comparación de cadenas), con `enum InMemorySearchMode { SAMPLE, EMPTY,
    UNAVAILABLE }` y `latencyMillis` inyectable (default corto; tests con 0). KDoc:
    **placeholder** hasta FT00035. Datos deterministas (sin reloj/aleatoriedad).
- **UI** (`ui/`):
  - `SearchUiState.kt`: `@Immutable data class SearchUiState(query: String = "",
    category: PublicationCategory? = null, fromDate: String = "", toDate: String = "",
    result: SearchResultState = SearchResultState.Idle)` y `sealed interface
    SearchResultState { Idle / Loading / Content(publications) / Empty / Error }`.
    Un único estado inmutable con la **entrada** del usuario y el **resultado**
    (UDF).
  - `SearchViewModel.kt`: `class SearchViewModel(searchPublications:
    SearchPublications) : ViewModel()` con `private val _uiState =
    MutableStateFlow(SearchUiState())` y `val uiState: StateFlow<SearchUiState> =
    _uiState.asStateFlow()`; eventos `onQueryChange`, `onCategorySelected`,
    `onFromDateChange`, `onToDateChange`, `onSubmit`, `onRetry`, `onClearFilters`.
    `onSubmit` con consulta en blanco **no** cambia el resultado (se queda `Idle`);
    con consulta válida pasa a `Loading` y lanza la búsqueda en `viewModelScope`
    (las fechas inválidas se **omiten** del `SearchFilters`, sin crash), mapeando
    `Success`+vacío → `Empty`, `Success`+contenido → `Content`, `Failure` → `Error`.
    `onRetry` repite la última búsqueda. `Factory` manual
    (`viewModelFactory { initializer { SearchViewModel(SearchPublications(
    InMemorySearchRepository())) } }`), coherente con la DI manual.
  - `SearchRoute.kt`: composable con efectos: recibe `viewModel: SearchViewModel =
    viewModel(factory = …)`, `onPublicationClick: (String) -> Unit`, `onBack: () ->
    Unit`; recolecta `val state by viewModel.uiState.collectAsStateWithLifecycle()` y
    delega en `SearchScreen(...)` pasando los eventos del ViewModel. `@Preview`.
  - `SearchScreen.kt`: `SearchScreen(state, onQueryChange, onCategorySelected,
    onFromDateChange, onToDateChange, onSubmit, onRetry, onPublicationClick, onBack,
    modifier)` **stateless** + vistas privadas `SearchResultsContent` (lista de
    `PublicationCard` con `onClick`), `IdleView`, `LoadingView`, `EmptyView`
    («sin resultados») y `ErrorView` (icono + mensaje + «Reintentar»), cada una con
    su `@Preview`. Encabezado con **atrás** (`Icons.AutoMirrored.Outlined.ArrowBack`
    + `contentDescription`).
  - `SearchFilterBar.kt`: barra de filtros específica de la feature: `OutlinedTextField`
    de consulta (`Icons.Outlined.Search` como *leading icon*), selector de
    **categoría** (chips de las 11 categorías con `FilterChip`, opción «Todas») y dos
    campos `desde`/`hasta` (ISO) con validación pura (`isIsoDate`) y botón «Buscar»
    (`button-primary`). `@Preview`.
- Se revisó que **no** existe un componente equivalente reutilizable; la barra de
  filtros es específica de búsqueda → vive en `feature/search/ui/` (regla de
  `CONSTRAINTS.md`: lo de una sola feature va en `feature/<nombre>/ui/`).

### 2. Navegación (reutilizar y extender FT00034)

- `app/AppRoutes.kt` (**modify**): añadir `const val SEARCH = "search"` (ruta
  estática; sin argumentos).
- `app/AppNavHost.kt` (**modify**): añadir `searchViewModelFactory` (parámetro con
  default) y un `composable(AppRoutes.SEARCH)` que invoca
  `SearchRoute(onPublicationClick = { id -> navController.navigate(AppRoutes.detail(id)) },
  onBack = { navController.popBackStack() })`. El `SearchViewModel` queda scopeado a
  su entrada de back stack (el estado se conserva al volver del detalle).
- `app/App.kt` (**modify**, si FT00034 construye las factories aquí): construir
  `searchViewModelFactory` y pasarla a `AppNavHost`; si FT00034 deja el default
  dentro de `AppNavHost`, no tocar `App.kt`. Se ajusta a cómo quede FT00034.

### 3. Acceso desde el feed (`feature/feed/ui/`, modify)

- `FeedScreen.kt`/`FeedRoute.kt` (**modify**): añadir `onSearchClick: () -> Unit`
  propagado desde el grafo; en el encabezado del feed, una fila con el título y un
  `IconButton` de búsqueda (`Icons.Outlined.Search` + `contentDescription` de
  recurso). Cambio mínimo; el resto del feed no cambia.

### 4. Restricciones de estilo a vigilar

- **Sin crash**: la consulta en blanco no llama al repositorio; fechas inválidas se
  omiten (validadas con `isIsoDate`); el fallo se modela
  (`SearchLoadResult.Failure → Error`) con reintento; los composables no hacen IO.
- **Sin `java.time`**: las fechas son `String` ISO y se comparan/formatean con
  funciones puras (`formatIsoDate` de `feature/feed/domain`).
- **Previews**: cada `@Composable` de UI (incluidas las privadas) lleva su `@Preview`
  dentro del tema.
- **detekt `TooManyFunctions` (15/fichero)**: repartir la UI en
  `SearchScreen.kt` + `SearchFilterBar.kt`; si un fichero se acerca al límite,
  extraer vistas privadas a un tercer fichero (`SearchViews.kt`).
- **CPD**: los `@Preview` viven en `commonMain` y `:cpdCheck` los barre; evitar
  bloques repetidos >100 tokens (factorizar datos de preview y variarlos).

## Expected File Changes

Rutas en el repo de producto (`..`); `es/aviferdev/datopublico` se abrevia `…`:

- `composeApp/src/commonMain/kotlin/…/feature/search/domain/SearchModels.kt` — create.
- `composeApp/src/commonMain/kotlin/…/feature/search/domain/SearchPublications.kt` — create.
- `composeApp/src/commonMain/kotlin/…/feature/search/data/SearchRepository.kt` — create.
- `composeApp/src/commonMain/kotlin/…/feature/search/data/InMemorySearchRepository.kt` — create.
- `composeApp/src/commonMain/kotlin/…/feature/search/ui/SearchUiState.kt` — create.
- `composeApp/src/commonMain/kotlin/…/feature/search/ui/SearchViewModel.kt` — create.
- `composeApp/src/commonMain/kotlin/…/feature/search/ui/SearchRoute.kt` — create.
- `composeApp/src/commonMain/kotlin/…/feature/search/ui/SearchScreen.kt` — create.
- `composeApp/src/commonMain/kotlin/…/feature/search/ui/SearchFilterBar.kt` — create.
- `composeApp/src/commonMain/kotlin/…/app/AppRoutes.kt` — modify; ruta `search`.
- `composeApp/src/commonMain/kotlin/…/app/AppNavHost.kt` — modify; destino `search`.
- `composeApp/src/commonMain/kotlin/…/app/App.kt` — modify; factory de búsqueda
  (según FT00034).
- `composeApp/src/commonMain/kotlin/…/feature/feed/ui/FeedScreen.kt` — modify; acción
  de búsqueda.
- `composeApp/src/commonMain/kotlin/…/feature/feed/ui/FeedRoute.kt` — modify;
  `onSearchClick`.
- `composeApp/src/commonMain/composeResources/values/strings.xml` — modify; textos de
  búsqueda (campo, filtros, categoría «Todas», desde/hasta, buscar, sin resultados,
  carga, error, reintentar, limpiar filtros, `contentDescription`).
- `composeApp/src/commonTest/kotlin/…/feature/search/SearchViewModelTest.kt` — create.
- `composeApp/src/commonTest/kotlin/…/feature/search/InMemorySearchRepositoryTest.kt` — create.
- `composeApp/src/commonTest/kotlin/…/app/AppRoutesTest.kt` — modify (o create si
  FT00034 no lo dejó); ruta `search`.
- `docs/pr/ft00036-ui-busqueda-filtros/antes-busqueda.png` — create; app base.
- `docs/pr/ft00036-ui-busqueda-filtros/despues-busqueda.png` — create; búsqueda con
  resultados.
- `docs/pr/ft00036-ui-busqueda-filtros/despues-busqueda-sin-resultados.png` — create
  (opcional si se captura).
- `docs/desarrollo-local.md` (producto) — modify; notas de la pantalla de búsqueda.

Harness (privado, repo aparte): `ARCHITECTURE.md`, `CONSTRAINTS.md`, ADR `0029` +
índice, skill `compose-multiplatform-architecture` §«Estado actual», `PROGRESS.md`,
`feature_list.json` (ver *Durable Documentation Impact*).

Total ≈ **20–22 ficheros de producto** (incluidas capturas) → **atómica**, sin
división en `FT00036-PTn`.

## Visual Design Impact

- UI involved: **yes**.
- Design source: `.harness/DESIGN.md` (tokens del frontmatter = fuente de verdad;
  §Core Screens 3 «Búsqueda» y 5 «Estados»; §Components: tarjeta de publicación).
- Screens or states affected: **Búsqueda** (Core Screen 3) y **Estados** (Core
  Screen 5): inicial, carga, resultados, «sin resultados» y error. Componentes:
  campo de texto, chips de categoría, campos de fecha, tarjeta reutilizada.
- New design artifact required: **no** — `DESIGN.md` ya describe la pantalla
  («campo + filtros (categoría, fecha) + resultados») y el estado «sin resultados»;
  esta feature los **aplica**.

## Durable Documentation Impact

- `ARCHITECTURE.md`: **update** — `:composeApp` gana `feature/search/{domain,data,ui}`
  (use case, puerto + repositorio en memoria, `SearchViewModel` con `StateFlow`,
  `SearchRoute`/`SearchScreen`/`SearchFilterBar`), el destino `search` en el grafo y
  el acceso desde el feed; se anota que `:shared` sigue sin cablearse y que FT00035
  conecta la red.
- `CONSTRAINTS.md`: **update** (pequeño) — MUST: la pantalla de búsqueda usa
  `SearchViewModel` (`StateFlow`) + composables stateless; filtra por **categoría** y
  **rango de fechas** (ISO, inclusivo) con estado «sin resultados»; reutiliza
  `PublicationCard`; el filtro de «ámbito» queda diferido (el endpoint no lo expone).
- `AGENTS.md`: **not needed** — no cambia el flujo, el arranque ni las reglas.
- Other docs: `docs/adr/0029-ui-busqueda-filtros.md` — **create** (decisión durable:
  UI de búsqueda sobre `/v1/buscar`, resultados como publicaciones, `SearchViewModel`
  con `StateFlow`, validación de fechas sin `java.time`, repositorio en memoria hasta
  FT00035, «ámbito» diferido) + índice `docs/adr/README.md`; skill
  `compose-multiplatform-architecture` §«Estado actual» — **update**;
  `docs/desarrollo-local.md` (producto) — **update**.

## Implementation Plan

1. **Rebasar** la rama sobre FT00034 mergeado (o sobre `main` cuando FT00034 esté) y
   confirmar los contratos (`AppRoutes`/`AppNavHost`, `PublicationCard.onClick`,
   ViewModel/`collectAsStateWithLifecycle`). **Capturar el «antes»** antes de tocar
   código.
2. Textos i18n de búsqueda en `strings.xml`.
3. Capas de la feature: `SearchModels` + `SearchPublications` + `SearchRepository` +
   `InMemorySearchRepository` (datos de ejemplo; modos; latencia inyectable) + tests.
4. `SearchUiState` + `SearchViewModel` (+ factory) + `SearchViewModelTest`.
5. UI: `SearchFilterBar` (consulta + chips de categoría + fechas + «Buscar») y
   `SearchScreen` (estados inicial/carga/resultados/sin resultados/error) con
   `@Preview` por estado; `SearchRoute`.
6. Navegación: `AppRoutes.SEARCH` (+ test), destino en `AppNavHost`, factory en
   `App.kt`; acceso desde el feed (`FeedScreen`/`FeedRoute`).
7. Verificar Android/Wasm/iOS y el gate; recorrer el flujo (feed → búsqueda →
   filtros → resultado → detalle → atrás) y **capturar el «después»**; commitear las
   capturas.
8. Actualizar `ARCHITECTURE.md`, `CONSTRAINTS.md`, ADR 0029 + índice, la skill y
   `docs/desarrollo-local.md`; `PROGRESS.md`/`feature_list.json` los cierra el
   orquestador.

## Implementation Tasks

- [ ] Rebasear sobre FT00034 y capturar `antes-busqueda.png` antes de tocar código.
- [ ] `composeResources/values/strings.xml` con los textos de búsqueda.
- [ ] `feature/search/domain/{SearchModels,SearchPublications}.kt` (result tipado,
      `isIsoDate` puro, sin `java.time`).
- [ ] `feature/search/data/{SearchRepository,InMemorySearchRepository}.kt` (datos de
      ejemplo; filtrado texto/categoría/fechas; modos `SAMPLE`/`EMPTY`/`UNAVAILABLE`;
      latencia inyectable).
- [ ] `feature/search/ui/{SearchUiState,SearchViewModel}.kt` (`StateFlow`, eventos,
      factory) + `SearchViewModelTest` (Loading/Content/Empty/Error, consulta en
      blanco, fechas inválidas, reintento).
- [ ] `feature/search/ui/{SearchFilterBar,SearchScreen,SearchRoute}.kt` (stateless +
      `@Preview` por estado; reutiliza `PublicationCard`).
- [ ] `app/AppRoutes.kt` (`SEARCH`) + `AppNavHost.kt` (destino) + `App.kt` (factory);
      `AppRoutesTest` (ruta `search`).
- [ ] Acceso desde el feed (`FeedScreen`/`FeedRoute`, `Icons.Outlined.Search`).
- [ ] `InMemorySearchRepositoryTest` (filtros y modos).
- [ ] `:shared` **no** se cablea; sin red, sin `ktor-client`, sin serialization.
- [ ] Gate: `assembleDebug`, `wasmJsBrowserDistribution`, `jvmTest`, `detekt` +
      `:cpdCheck`, `init.sh` (SDK-free) y `init.sh --with-client`.
- [ ] Docs durables (ADR 0029, `ARCHITECTURE.md`, `CONSTRAINTS.md`, skill,
      `docs/desarrollo-local.md`) y capturas `despues-*` commiteadas.

## Verification Plan

Desde la raíz del producto (`..`, JDK 21 vía JBR/`JAVA_HOME`; Android SDK y
`local.properties` para el cliente):

- **Gate SDK-free (obligatorio, sin cambios)**: `./gradlew build -PskipClient`,
  `./gradlew test`, `./gradlew detekt` (+ `:cpdCheck`) y `env -u JAVA_HOME
  .harness/init.sh` → BUILD SUCCESSFUL / exit 0. `init.sh` **no** se modifica.
- **Gate con cliente (`--with-client`, exige Android SDK)**: `./gradlew
  :composeApp:assembleDebug` (APK), `./gradlew :composeApp:wasmJsBrowserDistribution`
  (dist Web) y `./gradlew :composeApp:jvmTest` (tests nuevos + los de FT00032/FT00033/
  FT00034) en verde; `./gradlew detekt` cubre `:composeApp`.
- **iOS (host macOS)**: `./gradlew :composeApp:compileKotlinIosSimulatorArm64` +
  `:composeApp:linkDebugFrameworkIosSimulatorArm64` (o `init.sh --with-ios`).
- **Manual (una plataforma representativa)**: servir
  `composeApp/build/dist/wasmJs/productionExecutable/` en `http://127.0.0.1` (o APK en
  emulador); desde el feed pulsar búsqueda → escribir un término, elegir categoría y
  rango de fechas → ver resultados → abrir uno (detalle) → atrás (se conserva el
  estado de búsqueda). Repetir con una combinación sin resultados (estado «sin
  resultados») y con el repositorio en modo `UNAVAILABLE` (error + reintento),
  capturar y **revertir** al modo de ejemplo antes de commitear.
- **Tests**: `SearchViewModelTest` cubre `Idle → Loading → Content/Empty/Error`, la
  consulta en blanco (no llama al repositorio), la omisión de fechas inválidas y que
  «Reintentar» repite la última búsqueda; `InMemorySearchRepositoryTest` cubre el
  filtrado por texto, categoría y rango inclusivo, y los modos. Requiere
  `Dispatchers.setMain(StandardTestDispatcher())` (con `resetMain()`), porque
  `viewModelScope` usa el dispatcher Main. `AppRoutesTest` cubre la ruta `search`.
- **Sin red ni BD**: ningún test ni gate abre sockets ni toca PostgreSQL.
- **E2E**: no aplica — el repo **no** tiene comando E2E persistente para el cliente
  (`wasmJsBrowserTest`/Karma/Chrome fuera del gate) y no hay flujo de API cableado; la
  cobertura es de estado/dominio + verificación visual manual + previews.
- **Capturas (obligatorio)**: `docs/pr/ft00036-ui-busqueda-filtros/` con
  `antes-busqueda.png` (app base) y `despues-busqueda.png` (resultados) —y
  `despues-busqueda-sin-resultados.png` si se captura— enlazadas en el PR con URL
  absoluta a la rama
  (`https://github.com/AviferDev/DatoPublico/blob/feat/ft00036-ui-busqueda-filtros/docs/pr/ft00036-ui-busqueda-filtros/despues-busqueda.png?raw=true`).
  Si no hay navegador/emulador, justificarlo en el PR (`docs/pr/README.md`).

## Evidence To Capture

- Salida de `:composeApp:assembleDebug`, `:composeApp:wasmJsBrowserDistribution` y
  `:composeApp:jvmTest` (recuento de tests, 0 fallos), y del gate (`build
  -PskipClient`, `test`, `detekt` + `:cpdCheck`, `init.sh` exit 0; `--with-client`
  verde).
- Capturas **antes** (app base) y **después** (búsqueda con resultados y «sin
  resultados») en `docs/pr/ft00036-ui-busqueda-filtros/`.
- Confirmación de que los textos viven en recursos (grep: sin literales visibles en
  los composables fuera de previews) y que no hay colores de runtime fuera de
  `colorScheme`/previews.
- Confirmación manual de que feed → búsqueda → filtros → resultado → detalle → atrás
  funciona y conserva el estado, y de que el filtro de categoría y el rango de fechas
  se respetan.
- Confirmación de que `:shared`, `:backend`, CI e `init.sh` no cambian, de que no se
  añaden dependencias Gradle/red y de que `PublicationCard`/`Publication` se
  **reutilizan** (sin DTO ni tarjeta nuevos).
- Ficheros del commit `FT00036`, PR y run de CI; entradas en `PROGRESS.md` y
  `feature_list.json` (`evidence`).

## Validator Checklist

- [ ] Alcance acotado: solo `:composeApp` (capa `feature/search/`, destino `search`,
      acceso desde el feed, textos, tests); **sin** red/`:shared` (FT00035), **sin**
      reimplementar navegación/estado (FT00034), **sin** detalle (FT00033), **sin**
      chat/«ámbito»/historial/deep links, **sin** cambios en `:shared`/`:backend`/CI/
      `init.sh`/`DESIGN.md` ni dependencias Gradle.
- [ ] Escenarios 1–13 pasan (categoría, fechas, sin resultados, inicial, error+
      reintento, carga, resultado→detalle, acceso desde el feed, i18n/previews/
      iconos/colores, validación de fechas, tres plataformas, gate, capturas).
- [ ] `SearchViewModel` expone `StateFlow<SearchUiState>`; composables **stateless**;
      la UI recolecta con `collectAsStateWithLifecycle`; los eventos son métodos del
      ViewModel; la consulta en blanco no llama al repositorio.
- [ ] Filtros de **categoría** (11 categorías) y **fechas** ISO inclusivas; fechas
      inválidas se omiten sin crash; rango invertido no es error.
- [ ] Se **reutilizan** `Publication`/`PublicationCategory`/`Deadline`/`formatIsoDate`
      (de `feature/feed/domain`), `PublicationCard`, `DatoPublicoTheme` y el grafo
      `AppNavHost`/`AppRoutes`; **no** se duplican tarjeta, tema ni navegación.
- [ ] Cada `@Composable` de UI tiene `@Preview` dentro del tema; ningún texto visible
      hardcodeado; iconos con significado usan Material Icons + `contentDescription`;
      colores **solo** de `MaterialTheme.colorScheme.*`.
- [ ] Nunca se provoca un crash: fallo modelado (`SearchLoadResult.Failure → Error`)
      con reintento; sin `throw`/`error`/`TODO` como control.
- [ ] Estilo MUST: un solo `return`, sin `else if`, funciones ≤40 líneas, KDoc en
      castellano, identificadores en inglés, sin literales de color de runtime;
      `TooManyFunctions` (15/fichero) respetado.
- [ ] El gate SDK-free sigue verde; el gate con cliente compila Android/Wasm/iOS y
      pasa `jvmTest`; `init.sh` no se modifica; el PR no supera los 30 ficheros.
- [ ] Capturas antes/después en `docs/pr/ft00036-ui-busqueda-filtros/` enlazadas con
      URL absoluta a la rama (o justificación).
- [ ] `ARCHITECTURE.md`, `CONSTRAINTS.md`, ADR 0029 + índice, la skill de CMP y
      `docs/desarrollo-local.md` actualizados; `PROGRESS.md` y `feature_list.json`
      corregidos.

## Risks / Open Questions

- **Ordenación con FT00034 (bloqueante, el riesgo mayor).** FT00036 depende de
  FT00034, que **aún no está mergeado** (su rama parte de FT00032 y todavía **borra**
  los ficheros de FT00033: hay que rebasarla sobre `main` antes de mergear). La rama
  de FT00036 está reclamada sobre FT00033 (`082245b`), **sin** FT00034. El
  implementador **debe** rebasar FT00036 sobre FT00034 mergeado (o sobre `main` una
  vez lo esté) y confirmar los contratos que FT00036 asume: `AppRoutes`
  (`FEED`/`DETAIL`/`detail(id)`), `AppNavHost`, `FeedViewModel` con
  `collectAsStateWithLifecycle`, `PublicationCard.onClick` y lifecycle/navigation en
  el catálogo. Si FT00034 entrega un `DetailPlaceholderScreen` en vez de reutilizar
  el `DetailRoute` real de FT00033, la navegación resultado → detalle debe apuntar al
  destino que finalmente exista.
- **Frontera con FT00035 (HTTP/caché).** FT00035 **no** es dependencia de FT00036 (es
  hermano) y su rama solo tiene el *claim* (sin HTTP). FT00036 usa un
  `InMemorySearchRepository` **placeholder** (patrón de FT00032/FT00033) y **no**
  cablea `:shared`/`ktor-client`/cache; FT00035 sustituye el repositorio y mapea
  `PublicationCategory → CategoriaDto`. Si el orquestador prefiere que FT00036 use ya
  el HTTP real, FT00035 debe **preceder** y pasar a ser dependencia (cambia el grafo
  y el alcance).
- **Filtro de «ámbito» (0.9-T01).** El endpoint no lo expone; se **difiere** (haría
  falta ampliar FT00028). La `uvb` de FT00036 solo pide categoría y fecha.
- **UX de fechas.** Se usan campos de texto ISO (`aaaa-mm-dd`) con validación pura
  (`isIsoDate`) en lugar de `DatePicker` de Material 3 (complejo y con roces en CMP
  `1.7.3`); el rango invertido no es error (lista vacía → «sin resultados»). Decisión
  a registrar en el ADR 0029.
- **`MutableStateFlow` + `asStateFlow()` frente a `stateIn(...)`.** La skill
  ejemplifica `stateIn(viewModelScope, …)`; aquí el estado es **imperativo** (entrada
  del usuario), así que se usa `MutableStateFlow` expuesto como `StateFlow`. Se
  documenta la desviación en el ADR; sigue siendo UDF (estado inmutable + eventos).
- **Tokens de wire.** `categoria` viaja como token `@SerialName` de `CategoriaDto`
  (snake_case) y `desde`/`hasta` como ISO; ese mapeo es de FT00035 (aquí el puerto
  usa tipos de dominio).
- **`PublicationCard` sin destacado en resultados.** Los ítems de búsqueda no traen
  destacado (`isHighlighted=false`, `highlightReasons=emptyList()`) para no mostrar
  badges sin sentido; el `deadline` sí se conserva. Si se quiere mostrar el fragmento
  que casó, es una extensión posterior (no rompe el wire).
- **CPD/detekt sobre previews.** Los `@Preview` viven en `commonMain` y el
  `:cpdCheck` global los barre; `TooManyFunctions` limita a 15 por fichero → repartir
  la UI. Un hallazgo nuevo rompe el build.
- **Resultados vacíos en runtime (gap de planificación).** El corpus no está indexado
  y no hay HTTP: en runtime la búsqueda real saldría vacía; por eso se usan datos de
  ejemplo hasta FT00035 (mismo gap que FT00026/FT00032).
- **División.** ≈20–22 ficheros: por debajo de 30 → **atómica**; **no** procede
  partir en `FT00036-PTn`.
