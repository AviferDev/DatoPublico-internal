---
name: compose-multiplatform-architecture
description: Guía de arquitectura del cliente Compose Multiplatform (módulo :composeApp) de DatoPublico. Úsala al añadir o modificar pantallas, ViewModel, estado (UDF/StateFlow), use cases, repositorios/data sources, capas, navegación, DI, identidad de plataforma, tema, accesibilidad o tests del cliente Android/iOS/Web, o al planificar targets nuevos. Distingue el estado actual verificado del patrón objetivo (arquitectura por capas) y deriva del código real del repositorio, no de una arquitectura inventada.
---

# Arquitectura del cliente Compose Multiplatform — DatoPublico

Guía práctica para trabajar en `:composeApp`. Antes de tocar el cliente, lee
`DESIGN.md`, `docs/technical-discovery.md` y `docs/domain-model.md`. `CONTEXT.md`
fija el lenguaje de dominio.

**Estado actual:** `:composeApp` **ya existe y compila** (FT00005,
`bootstrap-cmp-targets`): Compose Multiplatform para **Android** (`androidTarget`),
**iOS** (`iosArm64` + `iosSimulatorArm64`, framework `ComposeApp`) y **Web/Wasm**
(`wasmJs { browser(); binaries.executable() }`), con la UI compartida en
`commonMain` (`App()`) y un entrypoint mínimo por plataforma. El target `jvm()` se
conserva **solo** para tests/dev (`:composeApp:jvmTest` y la task raíz `test`).

Desde FT00032 (`ui-feed`) hay **UI real y su base** (decisión durable en
`docs/adr/0027`): el **tema** `DatoPublicoTheme` (`design/theme/`, tokens de
`DESIGN.md`, única entrada), los **componentes reutilizables**
`design/components/{CategoryLabel,PublicationCard,PublicationBadges}`, los
**textos i18n** en `composeResources/values/strings.xml` (leídos con
`stringResource(Res.string.*)`) y la **primera capa de feature**
`feature/feed/{domain,data,ui}` con modelos propios del cliente, `GetDailyFeed` +
`FeedRepository` + `InMemoryFeedRepository` (datos de ejemplo; modos vacío/fallo),
`FeedUiState`/`FeedStateHolder` (estado **local** con `mutableStateOf`) y
`FeedRoute`/`FeedScreen`/`HighlightsSection` (stateless + `@Preview` por estado).

Todavía **no** hay navegación, ViewModels/`StateFlow`, cliente HTTP ni caché
(FT00034/FT00035) ni detalle/búsqueda/chat (FT00033/FT00036/FT00037); y
`:composeApp` **no** depende de `:shared` (el mapeo `PublicacionDto → Publication`
llega con FT00035, para no romper el gate SDK-free). El patrón de este documento
sigue siendo el **objetivo acordado**: no asumas que el estado actual ya lo cumple
y no inventes otra arquitectura.

## Topología de build (decidido)

- Kotlin Multiplatform + `org.jetbrains.compose`, **un único módulo
  `:composeApp`** que depende de `:shared` (DTOs y lógica compartida).
- Targets:
  - `androidTarget()`.
  - `iosArm64()` + `iosSimulatorArm64()` con `binaries.framework { baseName = ... }`.
  - `wasmJs { browser(); binaries.executable() }` (Web).
- Gradle Kotlin DSL con **version catalog**.
- `settings.gradle.kts` usa `RepositoriesMode.PREFER_SETTINGS` y declara los
  repositorios Ivy de las distribuciones de Kotlin/JS-Wasm (Binaryen, Node,
  Yarn): el plugin las registra a nivel de proyecto y `FAIL_ON_PROJECT_REPOS`
  rompería el build. Los tests de Wasm en navegador (Karma/Chrome) quedan **fuera**
  del gate; el `SmokeTest` corre en `jvmTest`/Android/iOS.
- La URL del backend se resuelve por plataforma (Android por `BuildConfig` por
  flavor; iOS en runtime desde el `Info.plist`; Wasm desde una config generada en
  build time). **Nunca** cablear `http://localhost` en `commonMain`.

## Arquitectura objetivo

### Modelo de capas y regla de dependencia

```
UI (Compose stateless + ViewModel)  ->  Dominio (use cases)  ->  Datos (repositorio -> data sources)
```

Arquitectura por capas estricta (base: guía UI/Dominio/Datos de Google + UDF, sin
Clean dogmática).

- La UI conoce el Dominio; **no** conoce Ktor ni DTOs de red.
- El Dominio no conoce Compose, Ktor ni plataforma: solo modelos e interfaces de
  repositorio.
- Los Datos implementan las interfaces que declara el Dominio; conocen
  `ktor-client`.

Prohibido: un composable que llame a `*Api`; un repositorio que importe de
`design/`; un use case que use tipos de Compose/Ktor.

### Estado, UDF y ViewModel

- Cada pantalla tiene un `XViewModel` (androidx.lifecycle multiplataforma) que
  expone `val uiState: StateFlow<XUiState>` con
  `stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), initial)`.
- `XUiState` es un `sealed interface` (Loading/Content/Empty/Error) o una
  `data class` inmutable anotada `@Immutable`.
- Los composables son **stateless**: reciben `uiState` + lambdas de eventos. Cero
  IO en composables.
- La UI recolecta con `collectAsStateWithLifecycle()`.
- Los eventos son métodos del ViewModel (`onSubmit()`, `onSelectPublication()`),
  nunca estado mutable expuesto.

### Dominio (obligatorio: use cases)

- **Toda** acción relevante pasa por un use case (`operator fun invoke`).
- El ViewModel llama **siempre** a use cases; nunca a repositorios directamente.

### Datos

- Cliente HTTP común `ktor-client` en un data source; DTOs de `:shared`
  (`kotlinx.serialization`).
- Cache offline básica: con la red caída, el contenido cacheado sigue visible.
- Errores tipados traducidos a estados de UI; no propagar excepciones de red a los
  composables.

### Navegación y DI

- Navegación entre feed, detalle, búsqueda y chat con estado compartido.
- **DI manual** por ahora (construcción de dependencias en el entrypoint de cada
  plataforma y paso por constructor). Evita introducir un framework de DI hasta
  que su necesidad esté justificada.

## Pantallas (según DESIGN.md)

1. **Feed diario:** bloque de **Destacados del día** + lista de **Publicaciones**
   con **etiqueta de categoría** (Norma / Empleo público / Becas y subvenciones),
   fecha, resumen corto y, si es convocatoria, **plazo**. Estados vacío/carga/error.
2. **Detalle de publicación:** "¿Qué cambia?", "¿A quién afecta?", "Cifras
   clave", **plazo** resaltado si aplica, enlace destacado a la **fuente oficial**
   y **aviso de IA**.
3. **Búsqueda:** campo de texto + filtros de **categoría** y **fecha** + resultados
   + estado "sin resultados".
4. **Chat RAG:** entrada de pregunta o afirmación; respuesta con **citas** a la
   fuente; estados de carga, error, **sin fundamento** y **refutada**.

## Diseño y accesibilidad

- Tokens y dirección visual de `DESIGN.md` (fuente de verdad de color/tipografía).
- Contraste **AA** mínimo; tamaño de texto escalable; no transmitir estado solo
  con color; objetivos táctiles ≥ 44 px.
- Textos externalizados en **castellano**.
- No ocultar nunca el aviso de IA ni el enlace a la fuente.

## Tests

- Tests de ViewModel/use cases en `commonTest`.
- Tests de UI por plataforma solo donde aporten; evitar duplicar lógica de UI.
- No meter dependencias de JVM (`java.time`) en `commonMain` (rompe iOS/Wasm).
