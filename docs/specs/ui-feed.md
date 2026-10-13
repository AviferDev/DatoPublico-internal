# Feature Implementation Spec: UI del feed con estados y dirección visual

## Source Feature

- `id`: ui-feed
- `ft_id`: FT00032 (registrado en `docs/feature-ids.md`)
- `parts`: none (atómica; ≈21–23 ficheros de producto, por debajo del límite de 30)
- `area`: cliente-cmp
- `depends_on`: api-feed-diario (FT00026, `accepted`) + bootstrap-cmp-targets
  (FT00005, `accepted`)
- `status`: not_started (al planificar)
- `source`: `feature_list.json` (`notes`: `docs/roadmap.md` 0.6-T01/T07, `DESIGN.md`)
- `claim`: rama `feat/ft00032-ui-feed` ya reclamada en `origin`
  (`97db208 chore(FT00032): claim`); sin PR abierto hacia `main` (el PR #32 abierto
  es de FT00030 y no toca `:composeApp`).

> **Es la primera UI real del cliente.** Sustituye la pantalla literal de FT00005
> (`App()` con «DatoPublico» + «Esqueleto Compose Multiplatform» y textos
> hardcodeados, deuda registrada en FT00005) por el **feed diario** con destacados,
> categorías, tarjetas y estados vacío/carga/error, aplicando `DESIGN.md`.

## Goal

Construir en `commonMain` de `:composeApp` la **primera pantalla real**: el **feed
diario** de publicaciones con su **categoría**, sus **destacados del día** y los
estados **carga / contenido / vacío / error**, sobre la dirección visual de
`DESIGN.md` (tokens de color/tipografía/formas, tarjeta de publicación, etiqueta de
categoría, badge de destacado y de plazo).

La feature **introduce la base del cliente**: un **tema** único
(`DatoPublicoTheme`) derivado de los tokens de `DESIGN.md`, una carpeta de
**componentes reutilizables** (`design/components/`), los **textos en recursos
i18n** (`composeResources/values/strings.xml`, `stringResource(Res.string.*)`) y la
**primera capa de feature** por capas (`feature/feed/{domain,data,ui}`) con un
**repositorio en memoria** de datos de ejemplo. El cliente HTTP real y la
dependencia de `:shared` son FT00035; la navegación y el estado compartido
(ViewModel/`StateFlow`) son FT00034.

## Non-Goals

- **Cliente HTTP y `:shared`**: `ktor-client`, la URL del backend y la dependencia
  `:composeApp → :shared` son `ui-cliente-http-cache` (FT00035). Esta feature **no**
  cablea red ni DTOs de `:shared` (ver *Risks*: el gate estándar es SDK-free).
- **Navegación y estado compartido**: `ViewModel`, `StateFlow`, `stateIn`, grafo de
  navegación, DI con framework, `collectAsStateWithLifecycle` y el paso
  feed → detalle son `ui-navegacion-estado` (FT00034). Aquí solo hay un estado
  **local** de la pantalla del feed.
- **Detalle de publicación** (FT00033): no se implementa la pantalla de detalle ni
  el clic a detalle; tampoco el aviso de IA visible ni el enlace oficial destacado
  (van en FT00033).
- **Búsqueda** (FT00036) y **chat** (FT00037).
- **Cache offline** (FT00035), **`expect/actual`** de plataforma (FT00035), **firma
  y empaquetado** Android/Web/iOS (FT00038–FT00040) y **accesibilidad/i18n
  multi-idioma** formal (FT00043). Aquí solo se introduce el **locale por defecto**
  (castellano).
- **No** se cambia el contrato de `:shared`, ni `:backend`, ni migraciones, ni
  `init.sh`, ni CI, ni `DESIGN.md` (es la fuente de verdad del diseño).

## Job Story

When abro la app,
I want ver de un vistazo las publicaciones del BOE del día, empezando por los
**destacados** y con cada publicación etiquetada por **categoría** (y su **plazo**
si es una convocatoria),
so I can informarme rápido, en lenguaje claro y con una interfaz cívica y fiable,
entendiendo además por qué algo está destacado.

## Users And Permissions

- **Ciudadanía (usuario final):** anónima, solo lectura; sin cuentas, sin datos
  personales, sin analítica. La UI no pide permisos ni escribe datos.
- **Desarrollador (único actor técnico):** ejecuta los gates y sirve la app
  (Android/Web) para verificar y capturar la pantalla.
- Sin autenticación ni autorización.

## Acceptance Scenarios

### Scenario 1: feed con contenido (destacados + tarjetas)

Given un feed de ejemplo con varias publicaciones (de distintas categorías), una de
ellas sin plazo, una convocatoria con **plazo** y alguna marcada como **destacada**,
When se muestra la pantalla del feed,
Then aparece arriba el bloque **«Destacados del día»** con las publicaciones
destacadas (cada una con su **motivo** en texto y su badge), y debajo la lista de
publicaciones; cada tarjeta muestra **título**, **etiqueta de categoría**, **fecha**
y **resumen corto**, y la convocatoria muestra su **badge de plazo**. Todo el texto
sale de recursos y todos los colores de `MaterialTheme.colorScheme`.

### Scenario 2: estado de carga

Given que el repositorio tarda un instante en responder,
When la pantalla arranca y aún no hay datos,
Then se muestra un **indicador de carga** (sin error) hasta que llega el contenido.

### Scenario 3: estado vacío

Given un repositorio que devuelve un día **sin publicaciones publicadas**,
When se muestra la pantalla,
Then aparece el **estado vacío** (icono + mensaje «no hay publicaciones»), **no** un
error ni una lista vacía sin explicación.

### Scenario 4: estado de error y reintento

Given un repositorio que devuelve **fallo** (resultado tipado, sin excepción no
controlada),
When se muestra la pantalla,
Then aparece el **estado de error** (icono + mensaje + botón «Reintentar»); pulsar
«Reintentar» vuelve a cargar y, si el repositorio ya responde, pasa a contenido. La
app **nunca** se cierra por este fallo.

### Scenario 5: textos desde recursos (i18n) y previews

Given el código de UI en `commonMain`,
When se revisan los composables,
Then **ningún** texto visible al usuario está hardcodeado (solo se admiten literales
en `@Preview` y símbolos tipográficos) y **cada** función `@Composable` de UI tiene
al menos una `@Preview` dentro del tema (los privados, en el mismo fichero).

### Scenario 6: tema y tokens de `DESIGN.md`

Given el tema del cliente,
When se revisan pantallas y componentes,
Then los colores se leen **solo** de `MaterialTheme.colorScheme.*` (sin literales de
color de runtime fuera de `@Preview`), los tokens de `DESIGN.md` están mapeados
(`primary #1A4D8F`, `secondary #0F766E`, `accent #F59E0B`, `background #F7F9FC`,
`surface #FFFFFF`, `text #1F2937`; formas `sm` 6px/`md` 12px) y las **etiquetas de
categoría** usan los tres tonos de `DESIGN.md` (normativo → `primary`; informativo/
administrativo → `secondary`; plazo/atención → `tertiary`, que porta el `accent`).

### Scenario 7: misma UI en las tres plataformas

Given la UI en `commonMain`,
When compilo Android (`:composeApp:assembleDebug`), Web (`:composeApp:wasmJsBrowserDistribution`)
e iOS (`:composeApp:linkDebugFrameworkIosSimulatorArm64`, en host macOS),
Then las tres compilan y montan la **misma** pantalla de feed (`FeedScreen`); cada
plataforma sigue aportando **solo** su entrypoint (`MainActivity`, `main()`,
`MainViewController`), sin duplicar UI.

### Scenario 8: el gate sigue verde

Given un entorno sin red ni base de datos,
When ejecuto `./gradlew build -PskipClient`, `./gradlew test`, `./gradlew detekt`
(+ `:cpdCheck`) y `.harness/init.sh`,
Then el gate SDK-free sigue en verde (no exige Android SDK) y, con el cliente
(`.harness/init.sh --with-client`), también quedan verdes
`:composeApp:assembleDebug`, `:composeApp:wasmJsBrowserDistribution`,
`:composeApp:jvmTest` y el análisis estático. `init.sh` **no** se modifica.

### Scenario 9: capturas antes/después

Given un cambio de interfaz,
When se abre el PR,
Then la rama incluye capturas **antes** (pantalla esqueleto de FT00005) y
**después** (feed) en `docs/pr/ft00032-ui-feed/`, enlazadas con URL absoluta a la
rama (ver `docs/pr/README.md`); si el estado vacío/error no se puede capturar, se
justifica.

## Repository Research

### Files Inspected

- `composeApp/src/commonMain/kotlin/…/app/App.kt` — pantalla mínima de FT00005:
  `MaterialTheme` con solo `primary`/`background`, `Surface` + textos **literales**
  (`APP_TITLE`/`APP_SUBTITLE`) y `@Preview`. Es lo que hay que sustituir.
- `composeApp/src/{androidMain,wasmJsMain,iosMain}/…/` — entrypoints
  (`MainActivity` → `setContent { App() }`, `main()` → `ComposeViewport`, iOS →
  `ComposeUIViewController`); **no hay que tocarlos**.
- `composeApp/build.gradle.kts` — targets `androidTarget`/`jvm`/`iosArm64`/
  `iosSimulatorArm64`/`wasmJs`; `commonMain` con `compose.runtime`/`foundation`/
  `material3`/`ui`/`components.uiToolingPreview`; `commonTest` con `kotlin("test")`;
  `wasmJsBrowserTest` desactivado del gate.
- `shared/build.gradle.kts` — **solo `jvm()`**: hoy `:composeApp` **no** puede
  consumir `:shared` en Android/iOS/Wasm (resolución de metadata). Ver *Risks*.
- `shared/src/commonMain/kotlin/…/model/{ResumenDiarioDto,PublicacionDto,
  CategoriaDto,HighlightDto,HighlightReasonDto,PlazoDto}.kt` — contrato del feed que
  esta UI **representa** (aunque se consuma en FT00035): el feed tiene
  `publicaciones` + `destacados` (`HighlightDto.publication` + `motivos`), cada
  publicación tiene `categoria` (11 valores), `fechaPublicacion`, `epigrafe?`,
  `urlOficial`, `resumen?` y `plazo?`.
- `.harness/DESIGN.md` — dirección visual, tokens, tarjeta de publicación, etiqueta
  de categoría, bloque de destacados, Core Screens 1 (feed) y 5 (estados).
- `.harness/CONSTRAINTS.md` §«Cliente (Compose Multiplatform)» — MUST de UI
  (previews, i18n por recursos, `Icons.Outlined.*`, colores solo de
  `colorScheme`, no crash, un solo `return`, sin `else if`, ≤40 líneas/función,
  30 ficheros, capturas en PR).
- `.harness/ARCHITECTURE.md` §`:composeApp`, `.harness/CONTEXT.md` §Feed diario /
  §Destacados, `.harness/docs/domain-model.md` (Feed/Resumen/Destacado),
  `.harness/docs/roadmap.md` §0.6.0 (0.6-T01/T07), `.harness/docs/git-workflow.md`
  §«Capturas en cambios de interfaz» y `.harness/docs/pr/README.md`.
- Skill `.harness/.agents/skills/compose-multiplatform-architecture/SKILL.md`
  (§Modelo de capas, §Estado/UDF, §Pantallas, §Diseño y accesibilidad, §Tests).
- Specs precedentes: `docs/specs/bootstrap-cmp-targets.md` (estado actual del
  módulo) y `docs/specs/api-feed-diario.md` (contrato del feed).
- `docs/desarrollo-local.md` (producto) — guía de ejecución local a actualizar.

### Existing Patterns To Follow

- **UI única en `commonMain`** y entrypoints mínimos por plataforma (FT00005).
- **Version catalog + Kotlin DSL**; accesores del plugin Compose
  (`compose.material3`, `compose.components.resources`…), sin añadir versiones.
- **`@Preview` de `org.jetbrains.compose.ui.tooling.preview.Preview`** junto al
  composable y dentro del tema.
- **Estilo MUST**: identificadores en inglés, KDoc/comentarios en castellano, un
  solo `return`, sin `else if`, funciones ≤40 líneas, sin crashes, sin literales de
  color de runtime.
- **Tests de estado/dominio en `commonTest`** (corren en `:composeApp:jvmTest` y en
  Android/iOS), sin tests de vistas.

### Current Gaps

- No existe tema completo, ni recursos i18n, ni componentes, ni capas de feature.
- `App()` no tiene estado ni datos; no hay repositorio ni modelos de cliente.
- El feed del backend sale **vacío** en runtime (el pipeline de resumen no está
  cableado: Session 068), así que **no** se puede depender de la API para poblar la
  UI; se usan datos de ejemplo (ver *Risks*).
- `:composeApp` no depende de `:shared` (los targets de `:shared` no coinciden) y el
  gate estándar es SDK-free.

## Technical Approach

La UI **representa** el contrato del feed con **modelos de dominio propios del
cliente** (FT00035 hará el mapeo `PublicacionDto → Publication` en su data source),
y se alimenta de un **repositorio en memoria** con datos de ejemplo. Se decide
**no** cablear `:shared` en esta feature (ver *Risks*); así se mantiene el gate
SDK-free y la feature queda acotada a UI.

### 1. Build y recursos i18n

- `composeApp/build.gradle.kts`: añadir `implementation(compose.components.resources)`
  a `commonMain` y `implementation(libs.kotlinx.coroutines.test)` a `commonTest`
  (alias ya existente; **sin** tocar `gradle/libs.versions.toml`). Configurar, si
  hace falta, `compose.resources { packageOfResClass = "es.aviferdev.datopublico.resources" }`.
- **Recursos** (`composeApp/src/commonMain/composeResources/values/strings.xml`):
  todos los textos visibles en castellano — título de la app, «Destacados del día»,
  «Publicaciones del día», las **11 etiquetas de categoría**, los **5 motivos** de
  destacado, «Plazo: %1$s»/«Plazo abierto hasta %1$s», «Cargando…», estado vacío,
  error y «Reintentar», `contentDescription` de los iconos. Ninguna clave se
  hardcodea en composables (`stringResource(Res.string.*)`).

### 2. Tema (`design/theme/DatoPublicoTheme.kt`, create)

- `lightColorScheme` mapeando los tokens de `DESIGN.md` a roles Material 3:
  `primary #1A4D8F`, `secondary #0F766E`, `tertiary #F59E0B`, `background #F7F9FC`,
  `surface #FFFFFF`, `onBackground`/`onSurface`/`onPrimary` con contraste AA.
- `Typography` acorde a `DESIGN.md` (títulos 700, cuerpo 400, cuerpo ≥16sp) y
  `Shapes` (`sm` 6dp, `md` 12dp).
- `@Composable fun DatoPublicoTheme(content)`: **única** entrada de tema; envuelve
  `MaterialTheme(colorScheme, typography, shapes, content)`. Incluye su `@Preview`.

### 3. Componentes reutilizables (`design/components/`, create)

- `CategoryLabel.kt`: pastilla sobria de categoría; recibe la categoría de dominio y
  resuelve **texto** (recurso) y **tono** (`primary`/`secondary`/`tertiary`) según
  `DESIGN.md`; color solo desde `colorScheme`. `@Preview` por tono.
- `PublicationBadges.kt`: `HighlightBadge` (con `Icons.Outlined.Star` +
  `contentDescription`) y `DeadlineBadge` (con `Icons.Outlined.DateRange`, tono
  `tertiary`). `@Preview`.
- `PublicationCard.kt`: tarjeta `Surface` con radio `md` y borde/sombra mínima
  (`DESIGN.md`): **título**, `CategoryLabel`, **fecha** y **resumen corto** (máx.
  líneas) + badges de destacado/plazo. Sin `onClick` (el clic a detalle es FT00034).
  `@Preview` (con y sin plazo/destacado).
- Reutilización previa: se revisó que **no** existía ningún componente equivalente
  en el repo; viven en `design/components/` porque los reutilizarán FT00033+.

### 4. Capas de la feature (`feature/feed/`, create)

- **Dominio** (`domain/`):
  - `FeedModels.kt`: `data class DailyFeed(date, highlights, publications)`,
    `data class Publication(id, title, category, publishedDate, shortSummary,
    isHighlighted, highlightReasons, deadline?, officialUrl)`,
    `enum class PublicationCategory` (11 valores, espejo de la taxonomía curada),
    `enum class HighlightReason` (5 motivos), `data class Deadline(limitDate)`.
    **Sin** sufijo (`Publication`/`DailyFeed`… valores de dominio internos; no son
    `Dto`/`Entity`/`Row`/`Ui`).
  - `GetDailyFeed.kt`: use case `class GetDailyFeed(private val repository:
    FeedRepository) { suspend operator fun invoke(): FeedLoadResult }` (toda acción
    pasa por un use case, según la skill).
  - `FeedLoadResult`: sealed `Success(feed)` / `Failure` (**tipado, sin excepción**),
    de modo que un fallo es un **estado modelado**, no un crash.
- **Datos** (`data/`):
  - `FeedRepository.kt`: interfaz `suspend fun load(): FeedLoadResult` (el *port*;
    FT00035 implementará el cliente HTTP/cache).
  - `InMemoryFeedRepository.kt`: implementación **en memoria** con datos de ejemplo
    (varias categorías, 2–3 destacados con motivos, una convocatoria con plazo),
    más modos `EMPTY` y `UNAVAILABLE` para poder mostrar vacío/error; latencia de
    simulación **inyectable** (default corto; tests con 0). KDoc explica que es un
    **placeholder** hasta FT00035.
- **UI** (`ui/`):
  - `FeedUiState.kt`: sealed `Loading` / `Content(feed)` / `Empty` / `Error`.
  - `FeedStateHolder.kt`: holder **local** (clase normal, `mutableStateOf`;
    **sin** `ViewModel` ni `StateFlow` ni navegación) con `val state` y
    `suspend fun load()`: pasa a `Loading`, invoca `GetDailyFeed` y mapea
    `Success`+vacío → `Empty`, `Success`+contenido → `Content`, `Failure` → `Error`.
    Es el punto que FT00034 sustituirá por un ViewModel con `StateFlow`.
  - `FeedRoute.kt`: composable que `remember`iza el holder, dispara `LaunchedEffect`
    para la carga inicial y el `rememberCoroutineScope` para `onRetry`, y delega en
    `FeedScreen` (los composables de UI son **stateless**).
  - `FeedScreen.kt`: `FeedScreen(state, onRetry)` stateless + vistas privadas
    `LoadingView` (`CircularProgressIndicator`), `EmptyView` y `ErrorView`
    (icono `Icons.Outlined.*` + mensaje + botón «Reintentar»), cada una con su
    `@Preview` en el mismo fichero.
  - `HighlightsSection.kt`: bloque de **Destacados del día** (título + tarjetas de
    destacados con su motivo). `@Preview`.
- **DI manual** y `App()`: `App()` (modify) pasa a
  `DatoPublicoTheme { FeedRoute(holder) }`, construyendo el holder con
  `GetDailyFeed(InMemoryFeedRepository(...))` y un `Surface(background)`. Sin
  framework de DI (decisión de la skill hasta que se justifique).

### 5. Restricciones de estilo a vigilar

- **Sin crash**: el error se modela (`FeedLoadResult.Failure → Error`), nunca se
  lanza como control; los composables no hacen IO (el IO vive en el data source).
- **Fecha sin `java.time`**: `publishedDate`/`limitDate` son `String` ISO-8601 y se
  formatean con una función pura (p. ej. `dd/mm/aaaa`); **no** se añade
  `kotlinx-datetime`.
- **Previews**: cada `@Composable` de UI (incluidas las vistas privadas) lleva su
  `@Preview` dentro del tema; las funciones marcadas `@Preview` están exentas de
  tener a su vez otra preview.
- **CPD**: los `@Preview` viven en `commonMain` (el `:cpdCheck` global barre
  `src/**` salvo tests); se evita boilerplate repetido >100 tokens entre previews
  (factorizar contenido pequeño, variar datos).

## Expected File Changes

Rutas en el repo de producto (`..`); `es/aviferdev/datopublico` se abrevia `…`:

- `composeApp/build.gradle.kts` — modify; `compose.components.resources` en
  `commonMain` y `kotlinx-coroutines-test` en `commonTest`; `compose.resources {}`
  si hace falta.
- `composeApp/src/commonMain/composeResources/values/strings.xml` — create; textos
  de UI (castellano) e `contentDescription`.
- `composeApp/src/commonMain/kotlin/…/app/App.kt` — modify; tema + feed.
- `composeApp/src/commonMain/kotlin/…/design/theme/DatoPublicoTheme.kt` — create.
- `composeApp/src/commonMain/kotlin/…/design/components/CategoryLabel.kt` — create.
- `composeApp/src/commonMain/kotlin/…/design/components/PublicationBadges.kt` —
  create.
- `composeApp/src/commonMain/kotlin/…/design/components/PublicationCard.kt` —
  create.
- `composeApp/src/commonMain/kotlin/…/feature/feed/domain/FeedModels.kt` — create;
  modelos de dominio + `FeedLoadResult` (resultado tipado, sin excepción).
- `composeApp/src/commonMain/kotlin/…/feature/feed/domain/GetDailyFeed.kt` — create;
  use case (`suspend operator fun invoke`).
- `composeApp/src/commonMain/kotlin/…/feature/feed/data/FeedRepository.kt` — create.
- `composeApp/src/commonMain/kotlin/…/feature/feed/data/InMemoryFeedRepository.kt` —
  create.
- `composeApp/src/commonMain/kotlin/…/feature/feed/ui/FeedUiState.kt` — create.
- `composeApp/src/commonMain/kotlin/…/feature/feed/ui/FeedStateHolder.kt` — create.
- `composeApp/src/commonMain/kotlin/…/feature/feed/ui/FeedRoute.kt` — create.
- `composeApp/src/commonMain/kotlin/…/feature/feed/ui/FeedScreen.kt` — create.
- `composeApp/src/commonMain/kotlin/…/feature/feed/ui/HighlightsSection.kt` — create.
- `composeApp/src/commonTest/kotlin/…/feature/feed/FeedStateHolderTest.kt` — create;
  carga → contenido, vacío y error, transición `Loading`.
- `composeApp/src/commonTest/kotlin/…/feature/feed/InMemoryFeedRepositoryTest.kt` —
  create; datos de ejemplo (destacados con motivos, plazo) y modos vacío/fallo.
- `docs/pr/ft00032-ui-feed/antes-feed.png` — create; esqueleto (base).
- `docs/pr/ft00032-ui-feed/despues-feed.png` — create; feed.
  (`despues-feed-vacio.png` / `despues-feed-error.png` — opcionales si se capturan.)
- `docs/desarrollo-local.md` — modify; comando del cliente y notas de i18n/estados.

Harness (privado, repo aparte): `ARCHITECTURE.md`, `CONSTRAINTS.md`, ADR `0027` +
índice, skill `compose-multiplatform-architecture`, `PROGRESS.md`,
`feature_list.json` (ver *Durable Documentation Impact*).

Total ≈ **21–23 ficheros de producto** (incluidas capturas) → **atómica**, sin
división en `FT00032-PTn`.

## Visual Design Impact

- UI involved: **yes** (primera UI real).
- Design source: `.harness/DESIGN.md` (tokens de frontmatter = fuente de verdad).
- Screens or states affected: **Feed diario** (Core Screen 1) y **Estados**
  (Core Screen 5): carga, contenido, vacío, error. Componentes: tarjeta de
  publicación, etiqueta de categoría, badge de destacado, badge de plazo.
- New design artifact required: **no** — `DESIGN.md` ya describe la dirección, los
  tokens, la tarjeta y el bloque de destacados; esta feature los **aplica**. El
  mapeo fino categoría→tono se documenta en el código (no cambia `DESIGN.md`).

## Durable Documentation Impact

- `ARCHITECTURE.md`: **update** — `:composeApp` deja de ser esqueleto: `design/`
  (tema + componentes), `feature/feed/{domain,data,ui}` con capas UI→Dominio→Datos,
  recursos i18n y datos de ejemplo; se anota que `:shared` **aún no** se cablea (y
  por qué) y que FT00034/FT00035 completan estado/navegación y red.
- `CONSTRAINTS.md`: **update** (pequeño) — MUST nuevos: el tema del cliente es
  `DatoPublicoTheme` (tokens de `DESIGN.md`, única entrada) y los componentes
  reutilizables de `:composeApp` viven en `design/components/`; las pantallas leen
  color solo de `colorScheme` y el texto solo de `composeResources`.
- `AGENTS.md`: **not needed** — no cambia el flujo, el arranque ni las reglas.
- Other docs: `docs/adr/0027-*.md` — **create** (decisión durable: base del cliente
  CMP = tema/design system, i18n por recursos, capas de feature y datos de ejemplo
  hasta FT00035) + índice `docs/adr/README.md`; skill
  `compose-multiplatform-architecture` §«Estado actual» — **update**;
  `docs/desarrollo-local.md` (producto) — **update**.

## Implementation Plan

1. **Capturar el «antes»** (pantalla esqueleto) desde el estado base de la rama,
   antes de tocar código (ver *Evidence To Capture*).
2. Recursos i18n + `composeApp/build.gradle.kts` (`compose.components.resources`).
3. Tema `DatoPublicoTheme` (colores/tipografía/formas) con su `@Preview`.
4. Componentes `design/components/` (etiqueta de categoría, badges, tarjeta) con
   previews.
5. Capas de la feature: modelos + `GetDailyFeed` + `FeedRepository` +
   `InMemoryFeedRepository` (datos de ejemplo); tests de gate.
6. `FeedUiState`, `FeedStateHolder` (+ test) y `FeedScreen` stateless con las vistas
   de carga/vacío/error y previews de cada estado; `HighlightsSection`.
7. `FeedRoute` y `App()` (tema + feed); verificar Android/Wasm/iOS y el gate.
8. Actualizar `ARCHITECTURE.md`, `CONSTRAINTS.md`, ADR 0027 + índice, la skill y
   `docs/desarrollo-local.md`; **capturar el «después»** y commitear las capturas;
   `PROGRESS.md`/`feature_list.json` los cierra el orquestador.

## Implementation Tasks

- [ ] Capturar `antes-feed.png` (esqueleto) antes de tocar código.
- [ ] `build.gradle.kts`: `compose.components.resources` + `coroutines-test`.
- [ ] `composeResources/values/strings.xml` con todos los textos (11 categorías,
      5 motivos, estados, plazo, `contentDescription`).
- [ ] `design/theme/DatoPublicoTheme.kt` (tokens `DESIGN.md` + `@Preview`).
- [ ] `design/components/{CategoryLabel,PublicationBadges,PublicationCard}.kt` con
      previews y colores solo de `colorScheme`.
- [ ] `feature/feed/domain/{FeedModels,GetDailyFeed}.kt` (result tipado, sin
      excepción) + `FeedLoadResult`.
- [ ] `feature/feed/data/{FeedRepository,InMemoryFeedRepository}.kt` (datos de
      ejemplo; modos vacío/fallo; latencia inyectable).
- [ ] `feature/feed/ui/{FeedUiState,FeedStateHolder,FeedRoute,FeedScreen,
      HighlightsSection}.kt` (stateless + estados; `@Preview` por estado).
- [ ] `:shared` **no** se cablea; sin red, sin ktor-client, sin ViewModel/StateFlow.
- [ ] Tests `commonTest`: `FeedStateHolderTest` + `InMemoryFeedRepositoryTest`.
- [ ] Gate: `assembleDebug`, `wasmJsBrowserDistribution`, `jvmTest`, `detekt` +
      `:cpdCheck`, `init.sh` (SDK-free) y `init.sh --with-client`.
- [ ] Docs durables (`ARCHITECTURE.md`, `CONSTRAINTS.md`, ADR 0027, skill,
      `docs/desarrollo-local.md`) y capturas `despues-*` commiteadas.

## Verification Plan

Desde la raíz del producto (`..`, JDK 21 vía JBR/`JAVA_HOME`; Android SDK y
`local.properties` para el cliente):

- **Gate SDK-free (obligatorio, sin cambios)**: `./gradlew build -PskipClient`,
  `./gradlew test`, `./gradlew detekt` (+ `:cpdCheck`) y `env -u JAVA_HOME
  .harness/init.sh` → BUILD SUCCESSFUL / exit 0. `init.sh` **no** se modifica.
- **Gate con cliente (`--with-client`, exige Android SDK)**: `./gradlew
  :composeApp:assembleDebug` (APK), `./gradlew :composeApp:wasmJsBrowserDistribution`
  (dist Web) y `./gradlew :composeApp:jvmTest` (tests nuevos + `SmokeTest`) en verde;
  `./gradlew detekt` cubre `:composeApp` (previews incluidas).
- **iOS (host macOS)**: `./gradlew :composeApp:compileKotlinIosSimulatorArm64` +
  `:composeApp:linkDebugFrameworkIosSimulatorArm64` (o `init.sh --with-ios`).
- **Manual (una plataforma representativa)**: servir
  `composeApp/build/dist/wasmJs/productionExecutable/` en `http://127.0.0.1` y abrir
  en el navegador (o instalar el APK en un emulador); comprobar destacados, tarjetas
  con categoría/fecha/resumen, badge de plazo, y las transiciones de estado.
- **Estados vacío/error**: construir temporalmente el `InMemoryFeedRepository` en
  modo `EMPTY`/`UNAVAILABLE` (una línea en `App()`), capturar, y **revertir** al modo
  de ejemplo antes de commitear; los estados también quedan fijados por los tests y
  por las `@Preview`.
- **Tests**: `FeedStateHolderTest` cubre `Loading → Content/Empty/Error`, el
  `Content` con destacados y plazo, y que «Reintentar» vuelve a cargar;
  `InMemoryFeedRepositoryTest` cubre los datos de ejemplo y los modos.
- **Sin red ni BD**: ningún test ni gate abre sockets ni toca PostgreSQL.
- **E2E**: no aplica — el repo **no** tiene comando E2E persistente para el cliente
  (Compose Multiplatform; `wasmJsBrowserTest`/Karma/Chrome queda fuera del gate) y
  no hay flujo de API cableado; la cobertura es de estado/dominio + verificación
  visual manual + previews.
- **Capturas (obligatorio)**: `docs/pr/ft00032-ui-feed/` con `antes-feed.png`
  (esqueleto, base de la rama) y `despues-feed.png` (feed); enlazadas en el PR con
  URL absoluta a la rama
  (`https://github.com/AviferDev/DatoPublico/blob/feat/ft00032-ui-feed/docs/pr/ft00032-ui-feed/despues-feed.png?raw=true`).
  Si el navegador/emulador no está disponible, justificarlo en el PR
  (`docs/pr/README.md`).

## Evidence To Capture

- Salida de `:composeApp:assembleDebug`, `:composeApp:wasmJsBrowserDistribution` y
  `:composeApp:jvmTest` (recuento de tests, 0 fallos), y del gate (`build
  -PskipClient`, `test`, `detekt` + `:cpdCheck`, `init.sh` exit 0; `--with-client`
  verde).
- Capturas **antes** (esqueleto) y **después** (feed) en `docs/pr/ft00032-ui-feed/`
  (y vacío/error si se pudieron capturar).
- Confirmación de que los textos viven en recursos (grep: sin literales visibles en
  los composables fuera de previews) y que no hay colores de runtime fuera de
  `colorScheme`/previews.
- Confirmación de que `:shared`, `:backend`, `:composeApp/build.gradle.kts`
  (contrato), CI e `init.sh` no cambian más allá de lo previsto, y de que no se
  añaden dependencias de red.
- Ficheros del commit `FT00032`, PR y run de CI; entradas en `PROGRESS.md` y
  `feature_list.json` (`evidence`).

## Validator Checklist

- [ ] Alcance acotado: solo UI/tema/recursos/componentes + capas del feed con datos
      de ejemplo; **sin** red, **sin** `:shared`, **sin** ViewModel/`StateFlow`/navegación,
      **sin** detalle/búsqueda/chat, **sin** cambios en `:shared`/`:backend`/CI/`init.sh`.
- [ ] Escenarios 1–9 pasan (contenido, carga, vacío, error+reintento, i18n/previews,
      tema/tokens, tres plataformas, gate, capturas).
- [ ] Cada `@Composable` de UI tiene `@Preview` dentro del tema; ningún texto
      visible hardcodeado (solo previews/símbolos); iconos con significado usan
      `Icons.Outlined.*` + `contentDescription`.
- [ ] Colores **solo** de `MaterialTheme.colorScheme.*` fuera de previews; el tema
      mapea los tokens de `DESIGN.md`; las categorías usan los tres tonos.
- [ ] Nunca se provoca un crash: el fallo se modela (`FeedLoadResult.Failure →
      Error`) y se muestra con reintento; los composables no hacen IO.
- [ ] Estilo MUST: un solo `return`, sin `else if`, funciones ≤40 líneas, KDoc en
      castellano, identificadores en inglés, sin literales de color de runtime.
- [ ] El gate SDK-free sigue verde; el gate con cliente compila Android/Wasm/iOS y
      pasa `jvmTest`; `init.sh` no se modifica; el PR no supera los 30 ficheros.
- [ ] Capturas antes/después en `docs/pr/ft00032-ui-feed/` enlazadas con URL
      absoluta a la rama (o justificación de por qué no se pudo capturar).
- [ ] `ARCHITECTURE.md`, `CONSTRAINTS.md`, ADR 0027 + índice, la skill de CMP y
      `docs/desarrollo-local.md` actualizados; `PROGRESS.md` y `feature_list.json`
      corregidos.

## Risks / Open Questions

- **`:composeApp` no depende de `:shared` (decisión deliberada).** `:shared` solo
  declara `jvm()`; consumirlo desde los targets Android/iOS/Wasm exige añadirle
  targets KMP (y `androidTarget()` requiere AGP `com.android.library` + Android SDK),
  lo que **rompería el gate SDK-free** (hoy `-PskipClient` solo excluye
  `:composeApp`, y `:backend` depende de `:shared`). Añadir esa infraestructura
  cambiaría las reglas de verificación, prohibido para esta feature. Por eso la UI
  usa **modelos de dominio del cliente** y el mapeo `PublicacionDto → Publication`
  ocurre en FT00035 (o en una feature de infraestructura previa a FT00035). **Es la
  decisión más discutible del plan**; si el orquestador prefiere cablear `:shared`
  ahora, hay que tratar el cambio de gate/targets como parte explícita del alcance.
- **Feed vacío en runtime (gap de planificación, Session 068).** El pipeline de
  resumen (FT00020–FT00023) no está cableado y la API saldría vacía; por eso FT00032
  usa **datos de ejemplo** y no la API. Cuando exista el cableado, FT00035 conectará
  la UI a datos reales.
- **Recursos de Compose (nuevo en el módulo).** `compose.components.resources` y la
  clase `Res` generada deben compilar en Android/iOS/Wasm y resolverse en `@Preview`
  y en el bundle Wasm; verificar en el build servido. El paquete de `Res` puede
  configurarse con `compose.resources { packageOfResClass = … }`.
- **Formato de fecha sin `java.time`.** `publishedDate`/`limitDate` son `String`
  ISO; se formatean con una función pura. No se añade `kotlinx-datetime`.
- **CPD/detekt sobre previews.** Los `@Preview` viven en `commonMain` y el
  `:cpdCheck` global los barre; evitar bloques repetidos >100 tokens entre previews
  (factorizar contenido y variar datos). Un hallazgo nuevo rompe el build.
- **Capturas.** Compose pinta sobre canvas: la captura Web/Android vale, pero hay
  que capturar el **antes** antes de tocar código y el **después** tras reconstruir;
  si no hay navegador/emulador, justificar en el PR (`docs/pr/README.md`).
- **`wasmJsBrowserTest` fuera del gate** (deuda Low de FT00005): la verificación del
  Wasm es compilación + inspección manual; no se reactiva aquí.
- **División.** ≈21–23 ficheros: muy por debajo de 30 → **atómica**; **no** procede
  partir en `FT00032-PTn`.
