# Feature Implementation Spec: Navegación y estado compartido

## Source Feature

- `id`: ui-navegacion-estado
- `ft_id`: FT00034 (registrado en `docs/feature-ids.md`)
- `parts`: none (atómica; ≈18–20 ficheros de producto, por debajo del límite de 30)
- `area`: cliente-cmp
- `depends_on`: ui-feed (FT00032, `accepted`)
- `status`: not_started (al planificar)
- `source`: `feature_list.json` (`notes`: `docs/roadmap.md` 0.6-T03,
  `docs/technical-discovery.md` §Concurrencia/estado); ADR 0027
- `claim`: rama `feat/ft00034-ui-navegacion-estado` ya reclamada en `origin`
  (`582ca5c chore(FT00034-): claim ui-navegacion-estado`); sin PR abierto hacia
  `main`.

> **Formaliza el patrón de estado y la navegación del cliente.** FT00032 dejó un
> **holder local** (`FeedStateHolder` con `mutableStateOf`) explícitamente
> temporal y tarjetas **sin clic**, y fijó en ADR 0027 que FT00034 lo sustituiría
> por un **ViewModel con `StateFlow`** y añadiría **navegación**. Esta feature
> entrega eso: feed ↔ detalle → atrás con estado conservado, sobre las capas ya
> existentes (`design/`, `feature/feed/{domain,data,ui}`).

## Goal

Introducir en `commonMain` de `:composeApp` el **patrón de estado objetivo**
(ViewModel multiplataforma con `StateFlow<FeedUiState>`, UDF, composables
stateless, `collectAsStateWithLifecycle`) y la **navegación** entre el **feed** y
un **destino de detalle**, de modo que pulsar una tarjeta navegue al detalle con
el `id` de la publicación, el **atrás** vuelva al feed y el **estado del feed se
conserve** (sin recargar) al volver.

La feature **sustituye** `FeedStateHolder` por `FeedViewModel` (FT00032 lo diseñó
para esto), añade el **grafo de navegación** con las rutas `feed` y
`detail/{publicationId}` y habilita el **clic** en `PublicationCard` (que FT00032
dejó sin `onClick` a propósito). El **contenido** del detalle (resumen
estructurado, plazo, fuente oficial, aviso de IA) es **FT00033**; el **cliente
HTTP/cache** es **FT00035**: aquí el detalle es solo un **placeholder de
navegación**.

## Non-Goals

- **Pantalla de detalle real** (FT00033): no se implementan «¿Qué cambia?»,
  «¿A quién afecta?», «Cifras clave», el enlace oficial destacado ni el aviso de
  IA. Solo un destino **placeholder** para que la navegación funcione.
- **Cliente HTTP, `:shared` y cache offline** (FT00035): no se cablea red, ni
  `ktor-client`, ni el mapeo `PublicacionDto → Publication`, ni `expect/actual`.
  El repositorio sigue siendo `InMemoryFeedRepository` (datos de ejemplo).
- **Búsqueda** (FT00036) y **chat** (FT00037); **detalle/búsqueda/chat** no
  aparecen en el grafo más allá de `feed`/`detail`.
- **Tema**: ya lo entrega FT00032 (`DatoPublicoTheme`); **no** se rehace. El
  roadmap 0.6-T03 menciona «theming», pero está cubierto por ADR 0027.
- **Framework de DI**: se mantiene **DI manual** por constructor/factory (skill);
  no se introduce Koin/Hilt.
- **Modo oscuro, i18n multi-idioma y accesibilidad formal** (FT00043);
  **empaquetado/firma** (FT00038–FT00040).
- **No** se cambia el contrato de `:shared`, ni `:backend`, ni migraciones, ni
  `init.sh`, ni CI, ni `DESIGN.md`, ni las reglas del gate.

## Job Story

When abro la app y quiero ver una publicación concreta,
I want pulsar su tarjeta, llegar a su detalle y poder volver al feed tal y como
lo dejé,
so I can explorar el BOE del día sin perder el hilo ni recargar la lista cada
vez que vuelvo.

## Users And Permissions

- **Ciudadanía (usuario final):** anónima, solo lectura; sin cuentas, sin datos
  personales, sin analítica. La navegación no pide permisos ni escribe datos.
- **Desarrollador (único actor técnico):** ejecuta los gates y sirve la app
  (Android/Web) para verificar y capturar.
- Sin autenticación ni autorización.

## Acceptance Scenarios

### Scenario 1: navegar del feed al detalle

Given el feed con contenido y tarjetas clicables,
When pulso una tarjeta de publicación,
Then la app navega al destino de **detalle** llevando el `id` de esa publicación
(`BOE-A-…`) como argumento y muestra el **placeholder de detalle** (sin resumen ni
fuente: eso es FT00033).

### Scenario 2: volver atrás conserva el estado

Given que estoy en el detalle tras haber cargado el feed,
When vuelvo atrás (botón de la UI o atrás del sistema/navegador),
Then vuelvo al feed **sin recargar**: se mantiene el estado ya cargado
(`Content`/`Empty`/`Error`) y la posición de scroll razonable, y **no** se vuelve
a mostrar `Loading`.

### Scenario 3: el feed usa ViewModel + `StateFlow`

Given la pantalla del feed,
When se inspecciona su estado,
Then lo expone un **`FeedViewModel`** (androidx.lifecycle multiplataforma) como
`StateFlow<FeedUiState>` con UDF (estado inmutable que la UI solo lee), la UI lo
recolecta con `collectAsStateWithLifecycle()` y el reintento es un **evento del
ViewModel** (`onRetry()`), no estado mutable expuesto. Los composables siguen
**stateless**.

### Scenario 4: mismos estados que FT00032

Given un repositorio que devuelve contenido, vacío o fallo,
When el `FeedViewModel` carga,
Then el estado resultante sigue siendo `Content` / `Empty` / `Error` (y `Loading`
mientras carga), con la misma UI de estados y reintento que FT00032; un fallo
llega **tipado** (`FeedLoadResult.Failure → Error`), nunca como excepción, y la
app no se cierra.

### Scenario 5: i18n, previews, Material Icons y colores del tema

Given el código nuevo de UI,
When se revisan los composables,
Then **cada** función `@Composable` de UI (incluidos el grafo de navegación y el
placeholder) tiene su `@Preview` dentro del tema; **ningún** texto visible está
hardcodeado (solo literales en `@Preview`); los iconos con significado usan
`Icons.AutoMirrored.Outlined.*`/`Icons.Outlined.*` con `contentDescription`; y los
colores salen **solo** de `MaterialTheme.colorScheme.*`.

### Scenario 6: misma navegación en las tres plataformas

Given la UI en `commonMain`,
When compilo Android (`:composeApp:assembleDebug`), Web
(`:composeApp:wasmJsBrowserDistribution`) e iOS
(`:composeApp:linkDebugFrameworkIosSimulatorArm64`, host macOS),
Then las tres compilan y montan el **mismo** grafo; cada plataforma aporta solo
su entrypoint y el atrás del sistema/navegador se comporta como el botón de la UI.

### Scenario 7: el gate sigue verde

Given un entorno sin red ni base de datos,
When ejecuto `./gradlew build -PskipClient`, `./gradlew test`, `./gradlew detekt`
(+ `:cpdCheck`) y `.harness/init.sh`,
Then el gate SDK-free sigue en verde (no exige Android SDK) y, con
`.harness/init.sh --with-client`, también quedan verdes
`:composeApp:assembleDebug`, `:composeApp:wasmJsBrowserDistribution`,
`:composeApp:jvmTest` (tests nuevos incluidos) y el análisis estático. `init.sh`
**no** se modifica.

### Scenario 8: capturas antes/después

Given un cambio de interfaz,
When se abre el PR,
Then la rama incluye capturas **antes** (feed de FT00032, tarjetas no clicables) y
**después** (detalle placeholder tras pulsar una tarjeta) en
`docs/pr/ft00034-ui-navegacion-estado/`, enlazadas con URL absoluta a la rama
(`docs/pr/README.md`).

## Repository Research

### Files Inspected

> La planificación se hizo sobre el árbol de producto en el tip de FT00032
> (`68d69c3` = `2eec726`, `feat(FT00032): complete ui-feed`), que es la **base
> exacta** de la rama FT00034 (`582ca5c` = claim sobre `2eec726`). El worktree
> `/Users/aviferdev/Documents/Git/DatoPublico-wt/ft00034` no era accesible desde
> el sandbox de planificación; no se modificó nada.

- `composeApp/src/commonMain/kotlin/…/app/App.kt` — composition root manual:
  `remember { FeedStateHolder(GetDailyFeed(InMemoryFeedRepository())) }` +
  `DatoPublicoTheme { Surface { FeedRoute(stateHolder, safeDrawingPadding()) } }`.
  Es lo que hay que sustituir por tema + grafo de navegación.
- `composeApp/src/commonMain/kotlin/…/feature/feed/ui/FeedStateHolder.kt` — holder
  **local** (`mutableStateOf`), KDoc dice «FT00034 lo sustituirá por un ViewModel
  con `StateFlow`». Es el punto de sustitución.
- `…/feature/feed/ui/FeedUiState.kt` — sealed `Loading`/`Content`/`Empty`/`Error`;
  **se reutiliza sin cambios**.
- `…/feature/feed/ui/FeedRoute.kt` — `rememberCoroutineScope` + `LaunchedEffect`
  para la carga y el reintento; pasa `state`/`onRetry` a `FeedScreen`.
- `…/feature/feed/ui/FeedScreen.kt` — stateless; `FeedContent` pinta
  `HighlightsSection` y `PublicationCard` **sin clic**.
- `…/feature/feed/ui/HighlightsSection.kt` — pinta `PublicationCard` de destacados
  sin clic.
- `…/design/components/PublicationCard.kt` — `Surface` con radio `md`/borde; KDoc:
  «sin `onClick` (el clic hacia el detalle llega con la navegación, FT00034)».
- `…/feature/feed/domain/{FeedModels,GetDailyFeed}.kt` — `Publication.id`
  (`BOE-A-aaaa-nnnnn`), `FeedLoadResult` tipado y `GetDailyFeed`; la UI ya usa
  estos modelos.
- `…/feature/feed/data/{FeedRepository,InMemoryFeedRepository}.kt` — puerto e
  implementación en memoria (modos `SAMPLE`/`EMPTY`/`UNAVAILABLE`); **se
  reutilizan** (FT00035 implementará el HTTP).
- `composeApp/build.gradle.kts` — targets `androidTarget`/`jvm`/`iosArm64`/
  `iosSimulatorArm64`/`wasmJs`; `commonMain` con `compose.runtime`/`foundation`/
  `material3`/`ui`/`components.uiToolingPreview`/`components.resources`;
  `commonTest` con `kotlin("test")` + `kotlinx-coroutines-test`; `wasmJsBrowserTest`
  desactivado.
- `gradle/libs.versions.toml` — Kotlin `2.1.20`, Compose Multiplatform `1.7.3`;
  `kotlinx-coroutines-core`/`-test` `1.10.1` ya declarados. **No** hay lifecycle
  ni navigation todavía.
- `composeApp/src/commonMain/composeResources/values/strings.xml` — 30 claves
  i18n (castellano); hay que añadir las del placeholder/atrás.
- `composeApp/src/commonTest/kotlin/…/feature/feed/FeedStateHolderTest.kt` — 6
  tests del holder (Loading, Content, Empty, Error, transición y reintento);
  se migran al ViewModel.
- `.harness/DESIGN.md`, `.harness/CONSTRAINTS.md` §«Cliente (Compose
  Multiplatform)», `.harness/ARCHITECTURE.md` §`:composeApp`,
  `.harness/docs/technical-discovery.md` (§Concurrencia/estado: «coroutines,
  `StateFlow`, ViewModels compartidos»), `.harness/docs/roadmap.md` §0.6.0
  (0.6-T03), `.harness/docs/adr/0027-*.md` y `.harness/docs/pr/README.md`.
- Skill `.agents/skills/compose-multiplatform-architecture/SKILL.md` (§Estado/UDF:
  `XViewModel` con `StateFlow` + `stateIn`, composables stateless,
  `collectAsStateWithLifecycle`; §Navegación y DI: navegación entre pantallas con
  estado compartido y **DI manual**).

### Existing Patterns To Follow

- **UI única en `commonMain`**, entrypoints mínimos por plataforma; **DI manual**
  por constructor (skill §Navegación y DI).
- **UDF**: `FeedUiState` (sealed, inmutable) ya existe; la UI solo lo lee.
- **Estilo MUST**: identificadores en inglés, KDoc/comentarios en castellano, un
  solo `return`, sin `else if`, funciones ≤40 líneas, sin crashes, sin literales
  de color de runtime; `@Preview` en toda función `@Composable`.
- **Tests de estado/dominio en `commonTest`** con `runTest` (corren en
  `:composeApp:jvmTest` y Android/iOS), sin tests de vistas.
- **Version catalog + Kotlin DSL**: las dependencias nuevas se declaran en
  `libs.versions.toml`, no con versiones sueltas en el build.

### Current Gaps

- No hay `ViewModel`/`StateFlow`, ni `lifecycle`, ni navegación, ni `NavHost`.
- Las tarjetas no son clicables y `App()` monta una sola pantalla.
- No existe `feature/detail/` (llega con FT00033).
- No hay comando E2E persistente para el cliente (`wasmJsBrowserTest` fuera del
  gate).

## Technical Approach

### Decisión de librería (navegación)

Se usa la **librería de navegación multiplataforma oficial de JetBrains**,
`org.jetbrains.androidx.navigation:navigation-compose`, en la versión **exacta**
con la que Compose Multiplatform `1.7.3` está construido: **`2.8.0-alpha11`**
(base Jetpack Navigation 2.8.0). Junto a ella, el **lifecycle multiplataforma**
oficial en su versión alineada **`2.8.4`**:
`lifecycle-viewmodel-compose` (ViewModel + `viewModel()` + `viewModelScope`) y
`lifecycle-runtime-compose` (`collectAsStateWithLifecycle`).

Motivos:

- Es la **misma familia** que el skill ya prescribe («`XViewModel` de
  androidx.lifecycle multiplataforma», navegación con estado compartido), y evita
  inventar una navegación propia.
- Resuelve el **atrás del sistema/navegador** (Android `OnBackPressedDispatcher`,
  historial del navegador en Wasm, swipe en iOS) sin código `expect/actual`
  (que es FT00035) ni `BackHandler` por plataforma.
- `navigation-compose:2.8.0-alpha11` **declara** `lifecycle-*:2.8.4` y
  `savedstate:1.2.2`, exactamente las versiones de CMP `1.7.3`: usar las versiones
  alineadas evita el `IrLinkageError`/`performRestore` que aparece al mezclar
  versiones de `savedstate`/`lifecycle`.

Alternativas descartadas: **Voyager** y **Decompose** (terceros, otro modelo de
ciclo de vida; más superficie que mantener para dos destinos); **navegación
propia** con `mutableStateOf<Screen>` + `BackHandler` por plataforma (reimplementa
lo que la librería oficial ya da y adelanta trabajo de `expect/actual`).

### 1. Dependencias (`gradle/libs.versions.toml` + `composeApp/build.gradle.kts`)

- Version catalog: `androidxLifecycle = "2.8.4"`, `androidxNavigation =
  "2.8.0-alpha11"` y las librerías
  `androidx-lifecycle-viewmodel-compose`, `androidx-lifecycle-runtime-compose`,
  `androidx-navigation-compose` (`org.jetbrains.androidx.*`).
- `commonMain`: añadir las tres + `implementation(libs.kotlinx.coroutines.core)`
  (ya declarado en el catálogo; `StateFlow` se usa directamente).
- **Sin** `kotlinx-serialization` plugin: las rutas son **strings** con
  `navArgument` (evita añadir el plugin de serialización a `:composeApp`).
- No se toca `:shared`, `:backend`, CI ni `init.sh`; el gate SDK-free no cambia
  (`-PskipClient` ya excluye `:composeApp`).

### 2. Estado: `FeedViewModel` (nuevo, sustituye `FeedStateHolder`)

- `class FeedViewModel(getDailyFeed: GetDailyFeed) : ViewModel()`.
- `val uiState: StateFlow<FeedUiState>` construido con
  `stateIn(viewModelScope, SharingStarted.Eagerly, FeedUiState.Loading)` sobre un
  disparador `MutableStateFlow<Int>` que, en cada emisión, hace
  `emit(Loading)` y luego el resultado mapeado (`Success`+vacío → `Empty`,
  `Success`+contenido → `Content`, `Failure` → `Error`). Se **conserva** la
  traducción de `FeedStateHolder` (misma semántica y mismos estados).
- Evento `fun onRetry()` (incrementa el disparador). Sin estado mutable expuesto.
- **`SharingStarted.Eagerly`, no `WhileSubscribed(5_000)`** (desviación
  justificada del ejemplo del skill): con una fuente **caliente** en memoria,
  `WhileSubscribed` detendría el flujo al no haber colectores y, al volver del
  detalle, reejecutaría la carga (rompería «se conserva el estado»).
  `WhileSubscribed` pasará a tener sentido cuando FT00035 exponga un flujo
  frío/cacheado; se documenta la decisión en el ADR.
- `Factory` manual: `viewModelFactory { initializer { FeedViewModel(
  GetDailyFeed(InMemoryFeedRepository())) } }`, construida en el composition root
  (`App()`), coherente con la DI manual.

### 3. Navegación (`app/AppNavHost.kt` + `app/AppRoutes.kt`, nuevos)

- `AppRoutes`: `const val FEED = "feed"`, `const val DETAIL =
  "detail/{publicationId}"`, `const val ARG_PUBLICATION_ID = "publicationId"` y
  `fun detail(publicationId: String): String` (con codificación segura del `id`;
  los ids BOE son URL-safe, pero se codifica para no romper con caracteres
  reservados).
- `AppNavHost(feedViewModelFactory, modifier)`: `rememberNavController()` +
  `NavHost(startDestination = AppRoutes.FEED)` con dos `composable`:
  - `FEED` → `FeedRoute(onPublicationClick = { id ->
    navController.navigate(AppRoutes.detail(id)) }, viewModel = viewModel(factory =
    feedViewModelFactory))`.
  - `DETAIL` (con `navArgument(ARG_PUBLICATION_ID) { type = NavType.StringType }`)
    → `DetailPlaceholderScreen(publicationId =
    entry.arguments?.getString(ARG_PUBLICATION_ID).orEmpty(), onBack = {
    navController.popBackStack() })`. **Nunca** un `!!`/excepción por argumento
    ausente: `.orEmpty()` evita el crash.
- El `FeedViewModel` queda **scopeado a la entrada de back stack** del feed (el
  `viewModel()` dentro de `composable(FEED)` usa el `ViewModelStoreOwner` de esa
  entrada): al volver del detalle, el feed reaparece con su estado ya cargado.

### 4. UI de la feature (`feature/feed/ui/`, `design/components/`)

- `FeedRoute.kt` (modify): recibe `onPublicationClick: (String) -> Unit` y
  `viewModel: FeedViewModel = viewModel(factory = …)`; recolecta
  `val state by viewModel.uiState.collectAsStateWithLifecycle()` y delega en
  `FeedScreen(state, onRetry = viewModel::onRetry, onPublicationClick)`. Ya **no**
  mantiene holder ni `LaunchedEffect` de carga (la carga la dispara el ViewModel).
- `FeedScreen.kt` (modify): añade `onPublicationClick: (String) -> Unit` y lo
  propaga a `FeedContent` → `HighlightsSection`/`PublicationCard`.
- `HighlightsSection.kt` (modify): propaga `onPublicationClick`.
- `PublicationCard.kt` (modify): añade `onClick: () -> Unit` y la hace clicable
  con la variante de `Surface(onClick = onClick, …)` o `Modifier.clickable`
  (la que resulte estable en la material3 de CMP `1.7.3`); el llamante pasa
  `{ onPublicationClick(publication.id) }`. `@Preview` actualizadas con `{}`.

### 5. Detalle placeholder (nuevo, temporal)

- `feature/detail/ui/DetailPlaceholderScreen.kt`:
  `DetailPlaceholderScreen(publicationId, onBack)` stateless, con un botón/icono
  de **atrás** (`Icons.AutoMirrored.Outlined.ArrowBack` + `contentDescription` de
  recurso) y un mensaje de recurso que indica que el detalle llega en FT00033
  (sin resumen, sin fuente, sin aviso de IA). `@Preview`.
- KDoc explícito: es **placeholder de navegación**; **FT00033 lo sustituye** por
  la pantalla de detalle real reutilizando la ruta `detail/{publicationId}`.

### 6. `App()` (modify)

`DatoPublicoTheme { AppNavHost(feedViewModelFactory,
Modifier.safeDrawingPadding()) }`, con la factory construida en `remember { … }`.
Se elimina el `remember { FeedStateHolder(...) }`.

### 7. Restricciones de estilo a vigilar

- **Sin crash**: argumento ausente con `.orEmpty()`; `FeedLoadResult.Failure →
  Error`; sin `!!`/`throw`/`error`/`TODO` como control.
- **Previews**: cada `@Composable` (incluido `AppNavHost`, que se previsualiza con
  `rememberNavController()` y la factory de preview, y el placeholder) lleva su
  `@Preview` dentro del tema.
- **CPD/detekt**: los `@Preview` viven en `commonMain` y `:cpdCheck` los barre;
  evitar bloques repetidos >100 tokens (factorizar contenido, variar datos).
- **≤40 líneas/función**: si `AppNavHost` crece, extraer el `composable(DETAIL)`
  a una función privada.

## Expected File Changes

Rutas en el repo de producto (`..`); `es/aviferdev/datopublico` se abrevia `…`:

- `gradle/libs.versions.toml` — modify; versiones/librerías lifecycle + navigation.
- `composeApp/build.gradle.kts` — modify; deps en `commonMain`.
- `composeApp/src/commonMain/kotlin/…/app/App.kt` — modify; tema + `AppNavHost`.
- `composeApp/src/commonMain/kotlin/…/app/AppNavHost.kt` — create; grafo + preview.
- `composeApp/src/commonMain/kotlin/…/app/AppRoutes.kt` — create; rutas y helper.
- `composeApp/src/commonMain/kotlin/…/feature/feed/ui/FeedViewModel.kt` — create;
  ViewModel + `StateFlow` + factory.
- `composeApp/src/commonMain/kotlin/…/feature/feed/ui/FeedStateHolder.kt` — delete;
  sustituido por el ViewModel.
- `composeApp/src/commonMain/kotlin/…/feature/feed/ui/FeedRoute.kt` — modify;
  ViewModel + `collectAsStateWithLifecycle` + `onPublicationClick`.
- `composeApp/src/commonMain/kotlin/…/feature/feed/ui/FeedScreen.kt` — modify;
  `onPublicationClick`.
- `composeApp/src/commonMain/kotlin/…/feature/feed/ui/HighlightsSection.kt` —
  modify; `onPublicationClick`.
- `composeApp/src/commonMain/kotlin/…/design/components/PublicationCard.kt` —
  modify; `onClick`.
- `composeApp/src/commonMain/kotlin/…/feature/detail/ui/DetailPlaceholderScreen.kt`
  — create; placeholder de navegación (FT00033 lo sustituye).
- `composeApp/src/commonMain/composeResources/values/strings.xml` — modify;
  textos del placeholder y `contentDescription` de atrás.
- `composeApp/src/commonTest/kotlin/…/feature/feed/FeedViewModelTest.kt` — create;
  `Loading → Content/Empty/Error`, reintento y estado conservado.
- `composeApp/src/commonTest/kotlin/…/feature/feed/FeedStateHolderTest.kt` —
  delete; migrado al test del ViewModel.
- `composeApp/src/commonTest/kotlin/…/app/AppRoutesTest.kt` — create; `detail(id)`
  y la clave del argumento.
- `docs/pr/ft00034-ui-navegacion-estado/antes-feed.png` — create; feed base.
- `docs/pr/ft00034-ui-navegacion-estado/despues-detalle.png` — create; placeholder.
- `docs/desarrollo-local.md` — modify; nota de navegación/estado.

Harness (privado, repo aparte): `ARCHITECTURE.md`, `CONSTRAINTS.md`, ADR `0028` +
índice, skill `compose-multiplatform-architecture` §«Estado actual», `PROGRESS.md`,
`feature_list.json` (ver *Durable Documentation Impact*).

Total ≈ **18–20 ficheros de producto** (incluidas capturas) → **atómica**, sin
división en `FT00034-PTn`.

## Visual Design Impact

- UI involved: **yes** (cambio de interfaz menor).
- Design source: `.harness/DESIGN.md` (tokens = fuente de verdad; no cambia).
- Screens or states affected: **Feed** (tarjetas ahora clicables) y **Detalle**
  (placeholder, Core Screen 2 en estado embrionario); estados de carga/vacío/error
  sin cambios visuales.
- New design artifact required: **no** — `DESIGN.md` ya describe el detalle y la
  tarjeta; el placeholder es scaffolding de navegación, no diseño final.

## Durable Documentation Impact

- `ARCHITECTURE.md`: **update** — `:composeApp` incorpora el patrón de estado
  (ViewModel + `StateFlow` + UDF + `collectAsStateWithLifecycle`) y la navegación
  (`AppNavHost`/`AppRoutes`, `navigation-compose` + `lifecycle` multiplataforma,
  DI manual), con el detalle aún en placeholder (FT00033) y el HTTP en FT00035.
- `CONSTRAINTS.md`: **update** (pequeño) — MUST nuevos: cada pantalla expone su
  estado con un `XViewModel` (`StateFlow`) y composables stateless; la navegación
  usa la librería oficial de CMP (`navigation-compose`) con rutas declaradas y DI
  manual; el detalle es placeholder hasta FT00033.
- `AGENTS.md`: **not needed** — no cambia el flujo, el arranque ni las reglas.
- Other docs: `docs/adr/0028-navegacion-viewmodel-stateflow-cmp.md` — **create**
  (decisión durable: navegación oficial CMP + lifecycle ViewModel/StateFlow, rutas
  string, `SharingStarted.Eagerly` por conservación de estado, DI manual) + índice
  `docs/adr/README.md`; skill `compose-multiplatform-architecture` §«Estado
  actual» — **update**; `docs/desarrollo-local.md` (producto) — **update**.

## Implementation Plan

1. **Capturar el «antes»** (feed de FT00032, tarjetas no clicables) antes de tocar
   código (ver *Evidence To Capture*).
2. Version catalog + `composeApp/build.gradle.kts` (lifecycle + navigation +
   coroutines-core); verificar que resuelve en `:composeApp:jvmTest`.
3. `FeedViewModel` (+ factory) sustituyendo `FeedStateHolder`; migrar
   `FeedStateHolderTest` → `FeedViewModelTest`.
4. `AppRoutes` (+ test) y `AppNavHost` con los destinos `feed`/`detail`.
5. `PublicationCard`/`HighlightsSection`/`FeedScreen`/`FeedRoute` con el clic y
   `collectAsStateWithLifecycle`; `App()` con tema + grafo.
6. `DetailPlaceholderScreen` + textos i18n del placeholder/atrás; previews de todo.
7. Verificar Android/Wasm/iOS, el atrás y la conservación de estado; capturar el
   «después».
8. Actualizar `ARCHITECTURE.md`, `CONSTRAINTS.md`, ADR 0028 + índice, la skill y
   `docs/desarrollo-local.md`; commitear capturas; `PROGRESS.md`/`feature_list.json`
   los cierra el orquestador.

## Implementation Tasks

- [ ] Capturar `antes-feed.png` antes de tocar código.
- [ ] `libs.versions.toml` + `build.gradle.kts`: lifecycle `2.8.4`, navigation
      `2.8.0-alpha11`, coroutines-core en `commonMain`.
- [ ] `feature/feed/ui/FeedViewModel.kt` (ViewModel + `StateFlow` + factory) y
      **eliminar** `FeedStateHolder.kt`.
- [ ] `FeedViewModelTest` (Loading/Content/Empty/Error/reintento/estado
      conservado) y **eliminar** `FeedStateHolderTest.kt`.
- [ ] `app/AppRoutes.kt` (+ `AppRoutesTest`) y `app/AppNavHost.kt`.
- [ ] Clic en `PublicationCard` + propagación por `HighlightsSection`/`FeedScreen`/
      `FeedRoute`; `FeedRoute` con `collectAsStateWithLifecycle`.
- [ ] `App()` con `DatoPublicoTheme { AppNavHost(…) }`.
- [ ] `feature/detail/ui/DetailPlaceholderScreen.kt` + textos i18n + `@Preview`.
- [ ] `:shared` **no** se cablea; sin red, sin `ktor-client`, sin serialization.
- [ ] Gate: `assembleDebug`, `wasmJsBrowserDistribution`, `jvmTest`, `detekt` +
      `:cpdCheck`, `init.sh` (SDK-free) y `init.sh --with-client`.
- [ ] Docs durables (ADR 0028, `ARCHITECTURE.md`, `CONSTRAINTS.md`, skill,
      `docs/desarrollo-local.md`) y capturas commiteadas.

## Verification Plan

Desde la raíz del producto (`..`, JDK 21; Android SDK y `local.properties` para el
cliente):

- **Gate SDK-free (obligatorio, sin cambios)**: `./gradlew build -PskipClient`,
  `./gradlew test`, `./gradlew detekt` (+ `:cpdCheck`) y `env -u JAVA_HOME
  .harness/init.sh` → BUILD SUCCESSFUL / exit 0. `init.sh` **no** se modifica.
- **Gate con cliente (`--with-client`)**: `./gradlew :composeApp:assembleDebug`,
  `./gradlew :composeApp:wasmJsBrowserDistribution` y
  `./gradlew :composeApp:jvmTest` (tests nuevos + `SmokeTest`) en verde;
  `./gradlew detekt` cubre `:composeApp`.
- **iOS (host macOS)**: `./gradlew :composeApp:compileKotlinIosSimulatorArm64` +
  `:composeApp:linkDebugFrameworkIosSimulatorArm64` (o `init.sh --with-ios`).
- **Manual (una plataforma representativa)**: servir
  `composeApp/build/dist/wasmJs/productionExecutable/` en `http://127.0.0.1` (o
  APK en emulador); pulsar una tarjeta → placeholder de detalle → **atrás** (botón
  y atrás del sistema/navegador) y comprobar que el feed **no** vuelve a `Loading`
  y conserva su estado.
- **Tests**: `FeedViewModelTest` cubre `Loading → Content/Empty/Error`, el
  reintento tras fallo y que el estado no se reinicia; `AppRoutesTest` cubre el
  helper de ruta y la clave del argumento. Requiere
  `Dispatchers.setMain(StandardTestDispatcher())` (con `resetMain()`), porque
  `viewModelScope` usa el dispatcher Main.
- **Sin red ni BD**: ningún test ni gate abre sockets ni toca PostgreSQL.
- **E2E**: no aplica — el repo **no** tiene comando E2E persistente para el
  cliente (`wasmJsBrowserTest`/Karma/Chrome fuera del gate); la cobertura es de
  estado/dominio + verificación visual manual + previews.
- **Capturas (obligatorio)**: `docs/pr/ft00034-ui-navegacion-estado/` con
  `antes-feed.png` (base) y `despues-detalle.png` (placeholder tras el clic),
  enlazadas en el PR con URL absoluta a la rama
  (`https://github.com/AviferDev/DatoPublico/blob/feat/ft00034-ui-navegacion-estado/docs/pr/ft00034-ui-navegacion-estado/despues-detalle.png?raw=true`).
  Si no hay navegador/emulador, justificarlo en el PR (`docs/pr/README.md`).

## Evidence To Capture

- Salida de `:composeApp:jvmTest` (recuento de tests, 0 fallos, incluidos
  `FeedViewModelTest`/`AppRoutesTest`), `:composeApp:assembleDebug`,
  `:composeApp:wasmJsBrowserDistribution` y del gate (`build -PskipClient`, `test`,
  `detekt` + `:cpdCheck`, `init.sh` exit 0; `--with-client` verde).
- Capturas **antes** (feed) y **después** (placeholder de detalle) en
  `docs/pr/ft00034-ui-navegacion-estado/`.
- Confirmación manual de navegación feed → detalle → atrás con estado conservado
  (sin `Loading` al volver).
- Confirmación de que no hay texto visible hardcodeado, que cada `@Composable`
  tiene `@Preview` y que los colores salen solo de `colorScheme`.
- Confirmación de que `:shared`, `:backend`, CI e `init.sh` no cambian y de que
  no se añaden dependencias de red (solo lifecycle/navigation oficiales).
- Ficheros del commit `FT00034`, PR y run de CI; entradas en `PROGRESS.md` y
  `feature_list.json` (`evidence`).

## Validator Checklist

- [ ] Alcance acotado: navegación feed↔detalle (detalle **placeholder**) +
      ViewModel/`StateFlow`; **sin** detalle real (FT00033), **sin** HTTP/`:shared`
      (FT00035), **sin** búsqueda/chat, **sin** framework de DI, **sin** cambios en
      `:shared`/`:backend`/CI/`init.sh`/`DESIGN.md`.
- [ ] Escenarios 1–8 pasan (navegar, atrás conserva estado, ViewModel+`StateFlow`,
      estados, i18n/previews/iconos/colores, tres plataformas, gate, capturas).
- [ ] `FeedStateHolder` eliminado y sustituido por `FeedViewModel` con
      `StateFlow`; composables stateless; UI recolecta con
      `collectAsStateWithLifecycle`.
- [ ] Cada `@Composable` de UI tiene `@Preview` dentro del tema; ningún texto
      visible hardcodeado; iconos con significado usan Material Icons +
      `contentDescription`; colores **solo** de `MaterialTheme.colorScheme.*`.
- [ ] Nunca se provoca un crash: argumento de ruta con `.orEmpty()`, fallo
      modelado (`FeedLoadResult.Failure → Error`) con reintento.
- [ ] Estilo MUST: un solo `return`, sin `else if`, funciones ≤40 líneas, KDoc en
      castellano, identificadores en inglés.
- [ ] El gate SDK-free sigue verde; el gate con cliente compila Android/Wasm/iOS y
      pasa `jvmTest`; `init.sh` no se modifica; el PR no supera los 30 ficheros.
- [ ] Capturas antes/después en `docs/pr/ft00034-ui-navegacion-estado/` enlazadas
      con URL absoluta a la rama (o justificación).
- [ ] `ARCHITECTURE.md`, `CONSTRAINTS.md`, ADR 0028 + índice, la skill de CMP y
      `docs/desarrollo-local.md` actualizados; `PROGRESS.md` y `feature_list.json`
      corregidos.

## Risks / Open Questions

- **Frontera con FT00033 (la más sensible).** El destino `detail` es un
  **placeholder** porque la pantalla de detalle es FT00033 (que **no** depende de
  FT00034 en `feature_list.json`). Coordinación necesaria: FT00033 debe
  **sustituir** `DetailPlaceholderScreen` por la pantalla real reutilizando
  `AppRoutes`/`AppNavHost` y el `publicationId`; se recomienda planificar FT00033
  **después** de FT00034 o anotar este contrato en su futuro spec. Si el
  orquestador prefiere que FT00034 no cree ningún destino de detalle, la
  verificación «feed → detalle → atrás» no se podría cumplir sin FT00033.
- **`navigation-compose` KMP es `alpha` (`2.8.0-alpha11`).** Es la versión con la
  que CMP `1.7.3` está construido (la más alineada posible). Riesgo: cambios de
  API en futuras alphas. Mitigación: usar solo `NavHost`/`composable`/`navigate`/
  `popBackStack`/`navArgument` (superficie estable dentro de la librería) y fijar
  la versión exacta en el catálogo.
- **`lifecycle`/`savedstate` en iOS.** Mezclar versiones distintas de
  `savedstate`/`lifecycle` provoca `IrLinkageError` (`performRestore`) en iOS. Se
  mitiga usando las versiones que declara `navigation-compose:2.8.0-alpha11`
  (`lifecycle 2.8.4`, `savedstate 1.2.2`) sin overrides. Verificar en
  `linkDebugFrameworkIosSimulatorArm64`.
- **`SharingStarted.Eagerly` vs `WhileSubscribed(5_000)`.** El skill ejemplifica
  `WhileSubscribed(5_000)`; aquí se usa `Eagerly` para **conservar** el estado al
  volver del detalle con una fuente caliente en memoria. Decisión documentada en
  el ADR; cuando FT00035 introduzca un flujo frío/cacheado, reevaluar
  `WhileSubscribed`.
- **Rutas string y codificación del `id`.** Los ids BOE (`BOE-A-aaaa-nnnnn`) son
  URL-safe, pero `AppRoutes.detail` debe codificar el `id` para no romper con
  caracteres reservados; los tests cubren el helper.
- **`viewModel()` en previews.** `AppNavHost` se previsualiza con
  `rememberNavController()` + factory de preview; si el preview de `NavHost`
  resulta inestable en alguna plataforma, documentarlo y mantener el preview de
  `App()` como cobertura principal.
- **CPD/detekt sobre previews.** `:cpdCheck` barre `commonMain`; evitar bloques
  repetidos >100 tokens entre previews nuevas.
- **División.** ≈18–20 ficheros: muy por debajo de 30 → **atómica**; **no**
  procede partir en `FT00034-PTn`.
