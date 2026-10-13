# Feature Implementation Spec: Pantalla de detalle con resumen y fuente

## Source Feature

- `id`: ui-detalle
- `ft_id`: FT00033 (registrado en `docs/feature-ids.md`; `not_started`)
- `parts`: none (atómica; ≈23–24 ficheros de producto, por debajo del límite de 30)
- `area`: cliente-cmp
- `depends_on`: api-detalle-norma (FT00027, `accepted`) + ui-feed (FT00032,
  `accepted` y en `origin/main`)
- `status`: not_started (al planificar)
- `source`: `feature_list.json` (`notes`: `docs/roadmap.md` 0.6-T02,
  `docs/build-brief.md`)
- `claim`: rama `feat/ft00033-ui-detalle` ya reclamada en `origin`
  (`e662b28 chore(FT00033-): claim ui-detalle`, base `origin/main` = `2eec726` que
  ya incluye FT00032); sin PR abierto hacia `main`.

> **Segunda pantalla real del cliente.** Reutiliza la base de FT00032 (tema
> `DatoPublicoTheme`, `design/components/`, i18n por recursos y capas
> `feature/<nombre>/{domain,data,ui}`) y añade la **pantalla de detalle**:
> resumen ciudadano estructurado («¿Qué cambia?», «¿A quién afecta?», «Cifras
> clave»), **plazo** resaltado si la publicación es una convocatoria, **enlace
> destacado a la fuente oficial** y **aviso de contenido generado por IA**.
> Deriva de `docs/roadmap.md` 0.6-T02, `DESIGN.md` (§Core Screens 2, §Components)
> y del contrato de `:shared` (`PublicacionDto`/`ResumenDto`/`PlazoDto`), **sin
> inventar**.

## Goal

Construir en `commonMain` de `:composeApp` la **pantalla de detalle de una
publicación** con la dirección visual de `DESIGN.md`: cabecera (título, categoría,
fecha), el **resumen estructurado** en tres bloques, el **plazo** destacado en
convocatorias, el **enlace a la fuente oficial** siempre visible y el **aviso de
IA** siempre visible, con los estados **carga / contenido / no encontrada /
error** y un botón de **volver**.

La feature introduce la **segunda capa de feature** (`feature/detail/`) con sus
modelos de dominio del cliente, un caso de uso, un repositorio **en memoria** de
ejemplo (el cliente HTTP real es FT00035) y un **holder local** de estado
(ViewModel/`StateFlow` y navegación son FT00034). Para que el enlace oficial
funcione sin código de plataforma se usa `LocalUriHandler` de Compose
(`androidx.compose.ui.platform`), disponible en `commonMain`.

Como la segunda feature que consume los componentes de `design/components/`,
extrae la **vocabulario compartido del cliente** (`PublicationCategory`,
`HighlightReason`, `Deadline`, `formatIsoDate`) fuera de `feature/feed/domain`
para evitar que `design/components/` o `feature/detail` dependan de
`feature/feed/domain` (inversión de capas ya señalada como *Low* en la validación
de FT00032 y anticipada en ADR 0027).

## Non-Goals

- **Navegación y estado compartido**: grafo de navegación, `ViewModel`,
  `StateFlow`, `stateIn`, `collectAsStateWithLifecycle`, DI con framework y el
  paso feed → detalle son `ui-navegacion-estado` (FT00034). Aquí solo hay un
  estado **local** del detalle y el composable `DetailRoute` como **contrato de
  invocación** que FT00034 conectará. **No** se añade `onClick` a
  `PublicationCard` ni se cablea el feed → detalle.
- **Cliente HTTP y `:shared`**: `ktor-client`, la URL del backend, la caché y el
  mapeo `PublicacionDto → modelos del cliente` son FT00035. Esta feature **no**
  añade la dependencia `:composeApp → :shared` ni abre red (ver *Risks*).
- **Búsqueda** (FT00036) y **chat** (FT00037); el detalle no implementa citas de
  chat.
- **`expect/actual`** de plataforma (FT00035), **firma y empaquetado**
  (FT00038–FT00040), **accesibilidad/i18n multi-idioma** formal (FT00043) y
  **avisos legales** (FT00044).
- **No** se cambia el contrato de `:shared`, ni `:backend`, ni migraciones, ni
  `init.sh`, ni CI, ni `DESIGN.md` (fuente de verdad del diseño), ni las
  dependencias de Gradle.

## Job Story

When abro una publicación del BOE desde el feed (o desde un enlace compartido),
I want leer su resumen ciudadano completo («¿Qué cambia?», «¿A quién afecta?»,
«Cifras clave»), ver su plazo si es una convocatoria y saltar a la fuente oficial,
so I can entender qué se ha publicado y a quién afecta en lenguaje claro, sabiendo
que el resumen es generado por IA y con la fuente oficial siempre a un toque.

## Users And Permissions

- **Ciudadanía (usuario final):** anónima, solo lectura; sin cuentas, sin datos
  personales, sin analítica. La UI no pide permisos ni escribe datos; abrir el
  enlace oficial delega en el navegador del sistema.
- **Desarrollador (único actor técnico):** ejecuta los gates y sirve la app
  (Android/Web) para verificar y capturar la pantalla.
- Sin autenticación ni autorización.

## Acceptance Scenarios

### Scenario 1: detalle de una convocatoria (con plazo)

Given una publicación de una convocatoria con `resumen` estructurado y `plazo`,
When se muestra la pantalla de detalle,
Then aparece el **título**, la **etiqueta de categoría** y la **fecha**; los tres
bloques **«¿Qué cambia?»**, **«¿A quién afecta?»** y **«Cifras clave»** con su
contenido; el **plazo resaltado** en el tono de atención (`tertiary`) con la fecha
límite formateada `dd/mm/aaaa`; el **enlace a la fuente oficial** visible; y el
**aviso de IA** visible. Todo el texto sale de recursos i18n y todos los colores
de `MaterialTheme.colorScheme`.

### Scenario 2: detalle sin plazo (no convocatoria)

Given una publicación **sin** plazo,
When se muestra el detalle,
Then **no** aparece el bloque de plazo (ni un hueco vacío) y el resto del detalle
(título, categoría, resumen, fuente oficial y aviso de IA) se muestra igual.

### Scenario 3: publicación no encontrada

Given un identificador que el repositorio no conoce (equivalente al `404` del
endpoint FT00027),
When se muestra la pantalla,
Then aparece el **estado «no encontrada»** (icono + mensaje), **no** un error ni
una pantalla en blanco; la app **nunca** se cierra.

### Scenario 4: error y reintento

Given un repositorio que devuelve **fallo** (resultado tipado, sin excepción),
When se muestra la pantalla,
Then aparece el **estado de error** (icono + mensaje + botón «Reintentar»);
pulsar «Reintentar» vuelve a cargar y, si el repositorio responde, pasa a
contenido. La app **nunca** se cierra por este fallo.

### Scenario 5: estado de carga

Given que el repositorio tarda un instante en responder,
When la pantalla arranca y aún no hay datos,
Then se muestra un **indicador de carga** hasta que llega el contenido.

### Scenario 6: aviso de IA y fuente oficial siempre visibles

Given cualquier detalle **con contenido**,
When se revisa la pantalla,
Then el **enlace a la fuente oficial** y el **aviso de contenido generado por IA**
están **siempre** visibles (regla MUST de `CONSTRAINTS.md`); el enlace abre la URL
oficial con `LocalUriHandler` y una URL no `http(s)://` no provoca ningún *crash*.

### Scenario 7: textos desde recursos (i18n) y previews

Given el código de UI en `commonMain`,
When se revisan los composables,
Then **ningún** texto visible al usuario está hardcodeado (solo literales en
`@Preview` y símbolos tipográficos) y **cada** función `@Composable` de UI tiene al
menos una `@Preview` dentro del tema (los privados, en el mismo fichero).

### Scenario 8: reutilización del tema y los componentes de FT00032

Given la base de FT00032,
When se revisan pantalla y componentes,
Then se reutilizan `DatoPublicoTheme`, `CategoryLabel` y `DeadlineBadge`/badges y
los colores se leen **solo** de `MaterialTheme.colorScheme.*`; los iconos con
significado son **Material Icons** (`Icons.Outlined.*`) con `contentDescription`; y
los componentes reutilizables nuevos viven en `design/components/`.

### Scenario 9: misma UI en las tres plataformas

Given la UI en `commonMain`,
When compilo Android (`:composeApp:assembleDebug`), Web
(`:composeApp:wasmJsBrowserDistribution`) e iOS
(`:composeApp:linkDebugFrameworkIosSimulatorArm64`, en host macOS),
Then las tres compilan y montan la **misma** pantalla de detalle
(`DetailScreen`); cada plataforma sigue aportando **solo** su entrypoint.

### Scenario 10: el gate sigue verde

Given un entorno sin red ni base de datos,
When ejecuto `./gradlew build -PskipClient`, `./gradlew test`, `./gradlew detekt`
(+ `:cpdCheck`) y `.harness/init.sh`,
Then el gate SDK-free sigue en verde (no exige Android SDK) y, con el cliente
(`.harness/init.sh --with-client`), también quedan verdes
`:composeApp:assembleDebug`, `:composeApp:wasmJsBrowserDistribution`,
`:composeApp:jvmTest` y el análisis estático. `init.sh` **no** se modifica.

### Scenario 11: capturas antes/después

Given un cambio de interfaz,
When se abre el PR,
Then la rama incluye capturas **antes** (app base: feed de FT00032, la pantalla de
detalle no existe) y **después** (detalle) en `docs/pr/ft00033-ui-detalle/`,
enlazadas con URL absoluta a la rama (ver `docs/pr/README.md`); si el detalle no se
puede capturar, se justifica.

## Repository Research

### Files Inspected

- `composeApp/src/commonMain/kotlin/…/app/App.kt` — *composition root* manual:
  `remember { FeedStateHolder(GetDailyFeed(InMemoryFeedRepository())) }` +
  `DatoPublicoTheme { Surface { FeedRoute(...) } }` con `safeDrawingPadding()`. Es
  el punto donde FT00034 conectará la navegación; FT00033 **no** lo cambia.
- `composeApp/src/commonMain/kotlin/…/feature/feed/{domain/FeedModels.kt,
  domain/GetDailyFeed.kt,data/FeedRepository.kt,data/InMemoryFeedRepository.kt,
  ui/{FeedUiState,FeedStateHolder,FeedRoute,FeedScreen,HighlightsSection}.kt}` —
  patrón exacto a replicar en `feature/detail/` (resultado tipado, use case,
  *port* + repositorio en memoria con modos y latencia inyectable, holder local
  con `mutableStateOf`, ruta con efectos y pantalla stateless + previews).
- `composeApp/src/commonMain/kotlin/…/design/theme/DatoPublicoTheme.kt` — tema
  único (tokens de `DESIGN.md`); `tertiary` = `accent` para el plazo.
- `composeApp/src/commonMain/kotlin/…/design/components/{CategoryLabel,
  PublicationBadges,PublicationCard}.kt` — `CategoryLabel` (11 categorías, tres
  tonos), `HighlightBadge`/`DeadlineBadge` (Material Icons + `contentDescription`)
  y la tarjeta. Hoy importan tipos de `feature/feed/domain` (inversión a corregir).
- `composeApp/src/commonMain/composeResources/values/strings.xml` — 30 claves de
  UI (castellano); hay que **añadir** las del detalle.
- `composeApp/build.gradle.kts` — `commonMain` ya tiene
  `compose.components.resources`; `commonTest` tiene `kotlinx-coroutines-test`;
  **sin** dependencias nuevas.
- `composeApp/src/commonTest/kotlin/…/feature/feed/{FeedStateHolderTest,
  InMemoryFeedRepositoryTest}.kt` — patrón de tests de estado/repositorio en
  `commonTest` (sin tests de vistas).
- `shared/src/commonMain/kotlin/…/model/{PublicacionDto,ResumenDto,PlazoDto}.kt` —
  contrato que la pantalla **representa** (se consume en FT00035): el detalle
  devuelve `PublicacionDto` con `titulo`, `categoria`, `fechaPublicacion`,
  `urlOficial`, `resumen` (`queCambia`, `aQuienAfecta`, `cifrasClave`,
  `fuenteOficial`, `avisoIA`) y `plazo` (`fechaLimite`, `descripcion?`).
- `shared/src/commonMain/kotlin/…/model/{CategoriaDto,SeccionBoeDto}.kt` — 11
  categorías curadas (espejo de `PublicationCategory`).
- `composeApp/src/androidMain/AndroidManifest.xml` — `Theme.Material.Light.
  NoActionBar` + `safeDrawingPadding()` (edge-to-edge), sin cambios.
- `.harness/DESIGN.md` — §Layout («Detalle: bloques … + enlace destacado a la
  fuente oficial; plazo resaltado en convocatorias»), §Components («Aviso de IA:
  banda sobria y visible», «Enlace de fuente oficial: siempre visible y claro»,
  «Bloque de sección: etiqueta + contenido»), §Core Screens 2 y 5.
- `.harness/CONSTRAINTS.md` §«Producto y datos» (fuente oficial y aviso de IA
  visibles) y §«Cliente (Compose Multiplatform)» (MUST de UI).
- `.harness/docs/adr/0027-cliente-cmp-tema-i18n-capas.md` — base del cliente; sus
  *Consecuencias* anticipan el modelo de presentación compartido.
- `.harness/docs/validations/ui-feed.md` — *Low* de seguimiento: inversión
  `design/components → feature/feed/domain`.
- `.harness/docs/specs/{ui-feed,api-detalle-norma}.md`,
  `.harness/docs/roadmap.md` §0.6 (0.6-T02), `.harness/docs/git-workflow.md`
  §«Capturas», `.harness/docs/pr/README.md` y la skill
  `compose-multiplatform-architecture` (§Pantallas 2, §Diseño, §Tests).
- `docs/desarrollo-local.md` (producto) — guía a actualizar.

### Existing Patterns To Follow

- **UI única en `commonMain`** y entrypoints mínimos por plataforma (FT00005).
- **Arquitectura por capas** `feature/<nombre>/{domain,data,ui}` con resultado
  **tipado** (sin excepción) y use case obligatorio (skill CMP).
- **Estado local** con `mutableStateOf` en un holder (sin ViewModel/`StateFlow`,
  que son FT00034) y pantalla **stateless** + `@Preview` por estado.
- **`@Preview` de `org.jetbrains.compose.ui.tooling.preview.Preview`** junto al
  composable y dentro del tema.
- **Estilo MUST**: identificadores en inglés, KDoc/comentarios en castellano, un
  solo `return`, sin `else if`, funciones ≤40 líneas, sin crashes, sin literales
  de color de runtime, `@SerialName` explícito (no aplica: sin DTOs nuevos).
- **Tests de estado/dominio en `commonTest`** (corren en `:composeApp:jvmTest` y en
  Android/iOS), sin tests de vistas.

### Current Gaps

- No existe `feature/detail/`, ni modelo del resumen ciudadano en el cliente, ni
  el aviso de IA, ni el enlace oficial, ni el bloque de sección.
- `PublicationCategory`/`HighlightReason`/`Deadline`/`formatIsoDate` viven en
  `feature/feed/domain`, así que `design/components/` y la nueva feature no pueden
  usarlos sin acoplarse a una feature.
- El detalle del backend sale **vacío** en runtime (el pipeline de resumen no está
  cableado: FT00020–FT00023 son librerías sin wiring) y el cliente **no** consume
  `:shared` todavía; se usan datos de ejemplo (ver *Risks*).

## Technical Approach

La pantalla **representa** el contrato del detalle con **modelos de dominio
propios del cliente** y se alimenta de un **repositorio en memoria** con datos de
ejemplo. Se mantiene `:composeApp` desacoplado de `:shared` y el gate SDK-free.

### 1. Vocabulario compartido del cliente (extracción, `core/model/`)

- `composeApp/src/commonMain/kotlin/es/aviferdev/datopublico/core/model/ClientModels.kt`
  (create): mueve aquí `PublicationCategory` (11 valores), `HighlightReason` (5),
  `Deadline` y `formatIsoDate` (documentación y nombres intactos). Paquete neutral
  `es.aviferdev.datopublico.core.model` (no colisiona con
  `es.aviferdev.datopublico.model` de `:shared`, que FT00035 cableará).
- `feature/feed/domain/FeedModels.kt` conserva `DailyFeed`, `Publication` y
  `FeedLoadResult` e importa lo movido; se actualizan los imports en
  `design/components/{CategoryLabel,PublicationBadges,PublicationCard}.kt`,
  `feature/feed/data/InMemoryFeedRepository.kt` y
  `commonTest/…/InMemoryFeedRepositoryTest.kt`. Refactor **mecánico** (sin cambios
  de comportamiento ni de datos).

### 2. Capas de la feature (`feature/detail/`, create)

- **Dominio** (`domain/`):
  - `DetailModels.kt`: `data class PublicationDetail(id, title, category,
    publishedDate, summary: CitizenSummary, deadline: Deadline?, officialSourceUrl,
    showsAiNotice)`, `data class CitizenSummary(whatChanges, whoIsAffected,
    keyFigures: List<String>)` y el resultado **tipado** `sealed interface
    DetailLoadResult { Success(detail) / NotFound / Failure }`. Sin sufijo (valores
    de dominio internos; no son `Dto`/`Entity`/`Row`/`Ui`). KDoc mapea los campos a
    «¿Qué cambia?», «¿A quién afecta?» y «Cifras clave».
  - `GetPublicationDetail.kt`: use case `class GetPublicationDetail(private val
    repository: DetailRepository) { suspend operator fun invoke(id: String):
    DetailLoadResult }`.
- **Datos** (`data/`):
  - `DetailRepository.kt`: *port* `suspend fun load(id: String): DetailLoadResult`.
  - `InMemoryDetailRepository.kt`: implementación **en memoria** con datos de
    ejemplo (una convocatoria con plazo y otra publicación sin plazo, con resumen
    estructurado y `officialSourceUrl`), modos `SAMPLE` / `NOT_FOUND` /
    `UNAVAILABLE` y latencia **inyectable** (default corto; tests con 0). KDoc
    explica que es un **placeholder** hasta FT00035. Para `SAMPLE`, un id
    desconocido devuelve `NotFound` (espeja el `404` de FT00027).
- **UI** (`ui/`):
  - `DetailUiState.kt`: sealed `Loading` / `Content(detail)` / `NotFound` / `Error`.
  - `DetailStateHolder.kt`: holder **local** (`mutableStateOf`) construido con el
    `id` y el use case; `val state` y `suspend fun load()` (pasa por `Loading` y
    mapea `Success` → `Content`, `NotFound` → `NotFound`, `Failure` → `Error`). Es
    el punto que FT00034 sustituirá por un ViewModel con `StateFlow`.
  - `DetailRoute.kt`: composable que `remember`iza/recibe el holder, dispara
    `LaunchedEffect` para la carga inicial y `rememberCoroutineScope` para el
    reintento, y delega en `DetailScreen`. **Es el contrato de invocación**: FT00034
    lo llamará con el `id` seleccionado y `onBack`.
  - `DetailScreen.kt`: `DetailScreen(state, onRetry, onBack, modifier)` stateless +
    vistas privadas `DetailContent` (cabecera + bloques + plazo + fuente + aviso),
    `LoadingView`, `NotFoundView` y `ErrorView` (icono + mensaje + «Reintentar»),
    cada una con su `@Preview` en el mismo fichero. El plazo se resalta en un bloque
    propio (`DeadlineNotice`, privado, tono `tertiary` + `formatIsoDate`).

### 3. Componentes reutilizables (`design/components/`, create)

- `AiNotice.kt`: banda sobria y visible (icono `Icons.Outlined.Info` +
  `contentDescription` + texto de recurso). La reutilizará el chat (FT00037).
- `OfficialSourceLink.kt`: enlace destacado a la fuente oficial; usa
  `LocalUriHandler.openUri` con guarda `http(s)://` (sin *crash* con URL inválida).
- `SectionBlock.kt`: bloque de sección («etiqueta + contenido» de `DESIGN.md`),
  usado por los tres bloques del resumen.
- Se revisó que no existían equivalentes; viven en `design/components/` porque son
  elementos de `DESIGN.md` reutilizables por las features siguientes.

### 4. Invocación de la pantalla (frontera con FT00034)

- FT00033 entrega `DetailRoute(stateHolder, onBack, modifier)` y `DetailScreen`
  como **API de invocación**. **No** se añade `onClick` a `PublicationCard` ni se
  cablea el feed → detalle: eso es FT00034 (navegación + ViewModel/`StateFlow`).
- Para la **verificación manual y las capturas** de esta feature, se renderiza
  temporalmente `DetailRoute` en `App()` con el repositorio de ejemplo (y en modo
  `NOT_FOUND`/`UNAVAILABLE`), se captura y se **revierte** (patrón ya documentado
  en FT00032 para los estados vacío/error). Los estados también quedan fijados por
  los tests y por las `@Preview`.

### 5. Restricciones de estilo a vigilar

- **Sin crash**: `NotFound` y `Failure` se **modelan** (nunca se lanzan); los
  composables no hacen IO; el enlace oficial valida el esquema antes de abrirlo.
- **Fecha sin `java.time`**: `publishedDate`/`deadline.limitDate` son `String`
  ISO-8601 y se formatean con `formatIsoDate` (`dd/mm/aaaa`).
- **Previews**: cada `@Composable` de UI (incluidas las privadas) lleva su
  `@Preview` dentro del tema; las funciones marcadas `@Preview` están exentas.
- **CPD**: los `@Preview` viven en `commonMain` (el `:cpdCheck` global barre
  `src/**` salvo tests); evitar bloques repetidos >100 tokens (factorizar datos de
  preview y variarlos).

## Expected File Changes

Rutas en el repo de producto (`..`); `es/aviferdev/datopublico` se abrevia `…`:

- `composeApp/src/commonMain/kotlin/…/core/model/ClientModels.kt` — create;
  vocabulario compartido (`PublicationCategory`, `HighlightReason`, `Deadline`,
  `formatIsoDate`).
- `composeApp/src/commonMain/kotlin/…/feature/feed/domain/FeedModels.kt` — modify;
  conserva `DailyFeed`/`Publication`/`FeedLoadResult` e importa lo movido.
- `composeApp/src/commonMain/kotlin/…/design/components/CategoryLabel.kt` — modify;
  import del vocabulario.
- `composeApp/src/commonMain/kotlin/…/design/components/PublicationBadges.kt` —
  modify; import del vocabulario.
- `composeApp/src/commonMain/kotlin/…/design/components/PublicationCard.kt` —
  modify; import del vocabulario.
- `composeApp/src/commonMain/kotlin/…/feature/feed/data/InMemoryFeedRepository.kt` —
  modify; import del vocabulario.
- `composeApp/src/commonTest/kotlin/…/feature/feed/InMemoryFeedRepositoryTest.kt` —
  modify; import de `formatIsoDate`.
- `composeApp/src/commonMain/kotlin/…/design/components/AiNotice.kt` — create.
- `composeApp/src/commonMain/kotlin/…/design/components/OfficialSourceLink.kt` —
  create.
- `composeApp/src/commonMain/kotlin/…/design/components/SectionBlock.kt` — create.
- `composeApp/src/commonMain/kotlin/…/feature/detail/domain/DetailModels.kt` —
  create.
- `composeApp/src/commonMain/kotlin/…/feature/detail/domain/GetPublicationDetail.kt`
  — create.
- `composeApp/src/commonMain/kotlin/…/feature/detail/data/DetailRepository.kt` —
  create.
- `composeApp/src/commonMain/kotlin/…/feature/detail/data/InMemoryDetailRepository.kt`
  — create.
- `composeApp/src/commonMain/kotlin/…/feature/detail/ui/DetailUiState.kt` — create.
- `composeApp/src/commonMain/kotlin/…/feature/detail/ui/DetailStateHolder.kt` —
  create.
- `composeApp/src/commonMain/kotlin/…/feature/detail/ui/DetailRoute.kt` — create.
- `composeApp/src/commonMain/kotlin/…/feature/detail/ui/DetailScreen.kt` — create.
- `composeApp/src/commonMain/composeResources/values/strings.xml` — modify; textos
  del detalle (títulos de bloque, plazo, fuente, aviso de IA, volver, estados y
  `contentDescription`).
- `composeApp/src/commonTest/kotlin/…/feature/detail/DetailStateHolderTest.kt` —
  create; carga → contenido, no encontrada y error; transición `Loading`.
- `composeApp/src/commonTest/kotlin/…/feature/detail/InMemoryDetailRepositoryTest.kt`
  — create; datos de ejemplo (con y sin plazo, resumen y fuente) y modos.
- `docs/pr/ft00033-ui-detalle/antes-detalle.png` — create; app base (feed, sin
  detalle).
- `docs/pr/ft00033-ui-detalle/despues-detalle.png` — create; detalle.
- `docs/desarrollo-local.md` (producto) — modify; comando/notas del detalle.

Harness (privado, repo aparte): `ARCHITECTURE.md`, `CONSTRAINTS.md`, ADR `0028` +
índice, skill `compose-multiplatform-architecture`, `PROGRESS.md`,
`feature_list.json` (ver *Durable Documentation Impact*).

Total ≈ **24 ficheros de producto** (incluidas capturas) → **atómica**, por debajo
del límite de 30. Si el recuento real se acercara a 30, se dividiría en
`FT00033-PT1` (extracción del vocabulario compartido) + `FT00033-PT2` (pantalla de
detalle), encadenadas.

## Visual Design Impact

- UI involved: **yes**.
- Design source: `.harness/DESIGN.md` (tokens del frontmatter = fuente de verdad;
  §Core Screens 2 y 5, §Components y §Layout).
- Screens or states affected: **Detalle de publicación** (Core Screen 2) y
  **Estados** (Core Screen 5): carga, contenido, no encontrada y error. Componentes:
  bloque de sección, aviso de IA, enlace de fuente oficial y plazo resaltado.
- New design artifact required: **no** — `DESIGN.md` ya describe la pantalla y sus
  componentes; esta feature los **aplica**.

## Durable Documentation Impact

- `ARCHITECTURE.md`: **update** — `:composeApp` gana `feature/detail/{domain,data,ui}`
  y el paquete neutral `core/model/` (vocabulario compartido del cliente);
  `design/components/` gana `AiNotice`, `OfficialSourceLink` y `SectionBlock` y deja
  de depender de `feature/feed/domain`. Se anota que `:shared` sigue sin cablearse y
  que FT00034 conecta la navegación y FT00035 la red.
- `CONSTRAINTS.md`: **update** (pequeño) — MUST: la pantalla de detalle muestra
  **siempre** el enlace a la fuente oficial y el aviso de IA; el vocabulario
  compartido del cliente vive en `core/model/` y `design/components/` **no** depende
  de ninguna `feature/`.
- `AGENTS.md`: **not needed** — no cambia el flujo, el arranque ni las reglas.
- Other docs: `docs/adr/0028-*.md` — **create** (decisión durable: modelo de
  presentación compartido del cliente y frontera del detalle) + índice
  `docs/adr/README.md`; skill `compose-multiplatform-architecture` §«Estado actual»
  — **update**; `docs/desarrollo-local.md` (producto) — **update**.

## Implementation Plan

1. **Capturar el «antes»** desde el estado base de la rama (app = feed de FT00032;
   la pantalla de detalle no existe).
2. Extraer el vocabulario compartido a `core/model/` y actualizar imports (refactor
   mecánico); gate verde.
3. Textos i18n del detalle en `strings.xml`.
4. Componentes `design/components/{AiNotice,OfficialSourceLink,SectionBlock}.kt` con
   previews.
5. Capas de la feature: `DetailModels` + `GetPublicationDetail` +
   `DetailRepository` + `InMemoryDetailRepository` (datos de ejemplo) + tests.
6. `DetailUiState`, `DetailStateHolder` (+ test) y `DetailScreen` con las vistas de
   carga/no encontrada/error y previews de cada estado; `DetailRoute`.
7. Verificar Android/Wasm/iOS y el gate; **capturar el «después»** (render temporal
   de `DetailRoute` en `App()`, capturar y revertir) y commitear las capturas.
8. Actualizar `ARCHITECTURE.md`, `CONSTRAINTS.md`, ADR 0028 + índice, la skill y
   `docs/desarrollo-local.md`; `PROGRESS.md`/`feature_list.json` los cierra el
   orquestador.

## Implementation Tasks

- [ ] Capturar `antes-detalle.png` (app base: feed) antes de tocar código.
- [ ] `core/model/ClientModels.kt` + actualizar imports (feed, design components,
      test de repositorio del feed).
- [ ] `composeResources/values/strings.xml` con los textos del detalle.
- [ ] `design/components/{AiNotice,OfficialSourceLink,SectionBlock}.kt` con
      previews y colores solo de `colorScheme`.
- [ ] `feature/detail/domain/{DetailModels,GetPublicationDetail}.kt` (result
      tipado, sin excepción) + `DetailLoadResult`.
- [ ] `feature/detail/data/{DetailRepository,InMemoryDetailRepository}.kt` (datos
      de ejemplo; modos `SAMPLE`/`NOT_FOUND`/`UNAVAILABLE`; latencia inyectable).
- [ ] `feature/detail/ui/{DetailUiState,DetailStateHolder,DetailRoute,DetailScreen}
      .kt` (stateless + estados; `@Preview` por estado; `DetailRoute` = contrato de
      invocación).
- [ ] `:shared` **no** se cablea; sin red, sin ktor-client, sin
      ViewModel/`StateFlow`/navegación.
- [ ] Tests `commonTest`: `DetailStateHolderTest` + `InMemoryDetailRepositoryTest`.
- [ ] Gate: `assembleDebug`, `wasmJsBrowserDistribution`, `jvmTest`, `detekt` +
      `:cpdCheck`, `init.sh` (SDK-free) y `init.sh --with-client`.
- [ ] Docs durables (`ARCHITECTURE.md`, `CONSTRAINTS.md`, ADR 0028, skill,
      `docs/desarrollo-local.md`) y capturas `despues-*` commiteadas.

## Verification Plan

Desde la raíz del producto (`..`, JDK 21 vía JBR/`JAVA_HOME`; Android SDK y
`local.properties` para el cliente):

- **Gate SDK-free (obligatorio, sin cambios)**: `./gradlew build -PskipClient`,
  `./gradlew test`, `./gradlew detekt` (+ `:cpdCheck`) y `env -u JAVA_HOME
  .harness/init.sh` → BUILD SUCCESSFUL / exit 0. `init.sh` **no** se modifica.
- **Gate con cliente (`--with-client`, exige Android SDK)**: `./gradlew
  :composeApp:assembleDebug` (APK), `./gradlew :composeApp:wasmJsBrowserDistribution`
  (dist Web) y `./gradlew :composeApp:jvmTest` (tests nuevos + los de FT00032) en
  verde; `./gradlew detekt` cubre `:composeApp` (previews incluidas).
- **iOS (host macOS)**: `./gradlew :composeApp:compileKotlinIosSimulatorArm64` +
  `:composeApp:linkDebugFrameworkIosSimulatorArm64` (o `init.sh --with-ios`).
- **Manual (una plataforma representativa)**: renderizar temporalmente
  `DetailRoute(DetailStateHolder(GetPublicationDetail(InMemoryDetailRepository()),
  "BOE-A-2026-21002"), onBack = {})` en `App()` (una línea), servir
  `composeApp/build/dist/wasmJs/productionExecutable/` en `http://127.0.0.1` y
  abrir en el navegador (o instalar el APK en un emulador); comprobar los tres
  bloques del resumen, el plazo, el enlace oficial y el aviso de IA. Repetir con el
  repositorio en modo `NOT_FOUND` y `UNAVAILABLE`, capturar y **revertir** `App()`
  al estado de feed antes de commitear.
- **Tests**: `DetailStateHolderTest` cubre `Loading → Content/NotFound/Error`, el
  `Content` con plazo y sin plazo, y que «Reintentar» vuelve a cargar;
  `InMemoryDetailRepositoryTest` cubre los datos de ejemplo (con/sin plazo, resumen
  y fuente) y los modos.
- **Sin red ni BD**: ningún test ni gate abre sockets ni toca PostgreSQL.
- **E2E**: no aplica — el repo **no** tiene comando E2E persistente para el cliente
  (Compose Multiplatform; `wasmJsBrowserTest`/Karma/Chrome queda fuera del gate) y
  no hay flujo de API cableado; la cobertura es de estado/dominio + verificación
  visual manual + previews.
- **Capturas (obligatorio)**: `docs/pr/ft00033-ui-detalle/` con
  `antes-detalle.png` (app base: feed) y `despues-detalle.png` (detalle), enlazadas
  en el PR con URL absoluta a la rama
  (`https://github.com/AviferDev/DatoPublico/blob/feat/ft00033-ui-detalle/docs/pr/ft00033-ui-detalle/despues-detalle.png?raw=true`).
  Si el navegador/emulador no está disponible, justificarlo en el PR
  (`docs/pr/README.md`).

## Evidence To Capture

- Salida de `:composeApp:assembleDebug`, `:composeApp:wasmJsBrowserDistribution` y
  `:composeApp:jvmTest` (recuento de tests, 0 fallos), y del gate (`build
  -PskipClient`, `test`, `detekt` + `:cpdCheck`, `init.sh` exit 0; `--with-client`
  verde).
- Capturas **antes** (app base: feed) y **después** (detalle) en
  `docs/pr/ft00033-ui-detalle/` (y no encontrada/error si se pudieron capturar).
- Confirmación de que los textos viven en recursos (grep: sin literales visibles en
  los composables fuera de previews) y que no hay colores de runtime fuera de
  `colorScheme`/previews.
- Confirmación de que `:shared`, `:backend`, CI e `init.sh` no cambian y de que no
  se añaden dependencias de Gradle ni de red; y de que `design/components/` ya no
  importa de `feature/feed/domain`.
- Ficheros del commit `FT00033`, PR y run de CI; entradas en `PROGRESS.md` y
  `feature_list.json` (`evidence`).

## Validator Checklist

- [ ] Alcance acotado: solo `:composeApp` (vocabulario compartido, componentes,
      capas del detalle con datos de ejemplo); **sin** red, **sin** `:shared`,
      **sin** ViewModel/`StateFlow`/navegación, **sin** cablear feed → detalle,
      **sin** búsqueda/chat, **sin** cambios en `:shared`/`:backend`/CI/`init.sh` ni
      dependencias Gradle.
- [ ] Escenarios 1–11 pasan (contenido con/sin plazo, no encontrada, error+reintento,
      carga, aviso IA + fuente siempre visibles, i18n/previews, reutilización del
      tema/componentes, tres plataformas, gate, capturas).
- [ ] El **aviso de IA** y el **enlace a la fuente oficial** son siempre visibles en
      el detalle con contenido; abrir el enlace no provoca *crash* con URL inválida.
- [ ] Cada `@Composable` de UI tiene `@Preview` dentro del tema; ningún texto
      visible hardcodeado (solo previews/símbolos); iconos con significado usan
      `Icons.Outlined.*` + `contentDescription`.
- [ ] Colores **solo** de `MaterialTheme.colorScheme.*` fuera de previews; el plazo
      usa el tono de atención; `design/components/` no depende de `feature/`.
- [ ] Nunca se provoca un crash: `NotFound`/`Failure` se modelan y se muestran; los
      composables no hacen IO.
- [ ] Estilo MUST: un solo `return`, sin `else if`, funciones ≤40 líneas, KDoc en
      castellano, identificadores en inglés, sin literales de color de runtime.
- [ ] El gate SDK-free sigue verde; el gate con cliente compila Android/Wasm/iOS y
      pasa `jvmTest`; `init.sh` no se modifica; el PR no supera los 30 ficheros.
- [ ] Capturas antes/después en `docs/pr/ft00033-ui-detalle/` enlazadas con URL
      absoluta a la rama (o justificación de por qué no se pudo capturar).
- [ ] `ARCHITECTURE.md`, `CONSTRAINTS.md`, ADR 0028 + índice, la skill de CMP y
      `docs/desarrollo-local.md` actualizados; `PROGRESS.md` y `feature_list.json`
      corregidos.

## Risks / Open Questions

- **Frontera con FT00034 (navegación/estado).** FT00033 entrega la pantalla y su
  contrato de invocación (`DetailRoute`), pero **no** cablea el feed → detalle ni
  añade `onClick` a `PublicationCard`; eso es FT00034 (nav + ViewModel/`StateFlow`).
  Consecuencia: en la app final el detalle **no** es alcanzable hasta FT00034; la
  captura «después» exige renderizarlo temporalmente en `App()` (documentado). **Es
  la decisión más discutible del plan**: si el orquestador prefiere que el detalle
  sea alcanzable ya, habría que aceptar un seam local feed → detalle en `App()`
  (selección con `mutableStateOf`, sin grafo de navegación) y declararlo
  explícitamente como temporal hasta FT00034.
- **Frontera con FT00035 (HTTP/`:shared`).** La pantalla usa un repositorio en
  memoria; el cliente HTTP, la caché y el mapeo `PublicacionDto → modelos del
  cliente` son FT00035. `:composeApp` sigue desacoplado de `:shared` y el gate
  SDK-free no cambia.
- **Extracción del vocabulario compartido (refactor de FT00032).** Toca 5 ficheros
  de FT00032 (mecánico) y crea `core/model/`. Alternativa si se quiere un PR más
  pequeño: **diferir** la extracción y que `feature/detail` importe el vocabulario
  de `feature/feed/domain` (deuda de acoplamiento entre features, peor que la
  inversión actual). Se recomienda hacerla ahora (segunda feature; ADR 0027 ya la
  anticipa y la validación de FT00032 la dejó como *Low*).
- **Nombre del paquete neutral.** Se propone `es.aviferdev.datopublico.core.model`
  para no colisionar con `es.aviferdev.datopublico.model` de `:shared` (que FT00035
  cableará). Si el implementador prefiere otro nombre, debe mantenerlo neutral (sin
  depender de una feature).
- **Iconos Material disponibles.** Solo está `material-icons-core` (sin
  `material-icons-extended`): hay que usar iconos del set core (p. ej.
  `Icons.Outlined.Info`, `Warning`, `DateRange`, `ExitToApp`, `ArrowBack`); **no**
  añadir la dependencia extendida.
- **Apertura del enlace oficial.** Se usa `LocalUriHandler` (común, sin
  `expect/actual`); una URL no `http(s)://` se ignora sin *crash*. No requiere
  FT00035.
- **CPD/detekt sobre previews.** Los `@Preview` viven en `commonMain` y el
  `:cpdCheck` global los barre; evitar bloques repetidos >100 tokens entre previews
  (factorizar datos y variarlos). Un hallazgo nuevo rompe el build.
- **Capturas.** Compose pinta sobre canvas: la captura Web/Android vale; hay que
  capturar el **antes** antes de tocar código y el **después** tras reconstruir; si
  no hay navegador/emulador, justificar en el PR (`docs/pr/README.md`).
- **`wasmJsBrowserTest` fuera del gate** (deuda Low de FT00005): la verificación del
  Wasm es compilación + inspección manual; no se reactiva aquí.
- **División.** ≈24 ficheros: por debajo de 30 → **atómica**; si el recuento real
  se acercara al límite, dividir en `FT00033-PT1`/`FT00033-PT2`.
