# ADR 0027: Base del cliente Compose Multiplatform: tema/design system, i18n por recursos, capas de feature y datos de ejemplo

## Estado

Aceptado (2026-10-13). Decisión del dueño del proyecto al ejecutar `ui-feed`
(FT00032), la primera UI real de `:composeApp`.

## Contexto

`:composeApp` era un **esqueleto** (FT00005): una única `App()` con textos
literales, `MaterialTheme` con dos colores y ningún componente, recurso ni capa.
La primera pantalla real (el feed diario) obliga a decidir, de una vez y para las
features de UI siguientes (detalle FT00033, navegación/estado FT00034, red
FT00035, búsqueda FT00036, chat FT00037), **dónde viven** el tema, los
componentes reutilizables, los textos, los modelos y los datos.

Restricciones que condicionan la decisión:

- `DESIGN.md` es la fuente de verdad de los tokens (color, tipografía, formas) y
  de la dirección visual.
- `CONSTRAINTS.md` exige: `@Preview` en toda función `@Composable`, textos desde
  recursos i18n, Material Icons, colores solo de `MaterialTheme.colorScheme`, sin
  crashes, un solo `return`, sin `else if`, ≤40 líneas por función.
- El **gate estándar es SDK-free** (`-PskipClient` excluye `:composeApp`) y no se
  puede cambiar en esta feature. `:shared` solo declara `jvm()`, así que
  consumirlo desde `androidTarget`/`iosArm64`/`wasmJs` exigiría añadirle targets
  KMP (y AGP en `:shared`), lo que rompería ese gate.
- El feed real del backend sale **vacío** en runtime (el pipeline de resumen no
  está cableado), así que la UI no puede depender de la API para existir.

## Decisión

1. **Tema único**: `DatoPublicoTheme` (`design/theme/DatoPublicoTheme.kt`) es la
   **única** entrada de tema del cliente. Mapea los tokens de `DESIGN.md` a un
   `lightColorScheme` de Material 3 (`primary #1A4D8F`, `secondary #0F766E`,
   `tertiary` = `accent #F59E0B`, `background #F7F9FC`, `surface #FFFFFF`, texto
   `#1F2937`), con pares `on*` de contraste **AA**, más `Typography` (títulos 700,
   cuerpo 400, cuerpo ≥16sp) y `Shapes` (`sm` 6dp, `md` 12dp). Es el **único**
   lugar con literales de color; el resto de la UI lee de `colorScheme`.
2. **Componentes reutilizables en `design/components/`**: `CategoryLabel`,
   `PublicationCard` y `PublicationBadges`. La etiqueta de categoría usa los tres
   tonos de `DESIGN.md` (normativo → `primary`; informativo/administrativo →
   `secondary`; plazo/atención → `tertiary`) y los badges usan **Material Icons**
   con `contentDescription`.
3. **Textos en recursos i18n**: `composeResources/values/strings.xml` es la única
   fuente de textos visibles (títulos, 11 categorías, 5 motivos de destacado,
   plazo, estados, `contentDescription`), leídos con
   `stringResource(Res.string.*)`. Solo se admiten literales en `@Preview`.
4. **Capas de feature por capas** en `feature/feed/{domain,data,ui}`:
   - `domain/` — modelos **propios del cliente** (`DailyFeed`, `Publication`,
     `PublicationCategory`, `HighlightReason`, `Deadline`), `GetDailyFeed` y el
     resultado **tipado** `FeedLoadResult` (`Success`/`Failure`, sin excepción).
   - `data/` — el *port* `FeedRepository` y `InMemoryFeedRepository` con datos de
     ejemplo y modos `EMPTY`/`UNAVAILABLE` (placeholder explícito hasta FT00035).
   - `ui/` — `FeedUiState`, `FeedStateHolder` local (`mutableStateOf`, sin
     ViewModel/StateFlow), `FeedRoute` (efectos) y `FeedScreen`/`HighlightsSection`
     **stateless**.
5. **`:composeApp` sigue desacoplado de `:shared`**: el mapeo
   `PublicacionDto → Publication` y el cliente HTTP/caché son FT00035. Se
   mantiene el gate SDK-free.
6. **Fecha sin `java.time`**: las fechas viajan como `String` ISO-8601 y se
   formatean con una función pura (`dd/mm/aaaa`), sin añadir `kotlinx-datetime`.

## Alternativas consideradas

- **Cablear `:shared` ahora** (añadir `androidTarget`/iOS/Wasm a `:shared`):
  descartado porque exige AGP y Android SDK en `:shared`, lo que **rompe el gate
  SDK-free** y cambia las reglas de verificación, fuera del alcance de FT00032.
- **Cargar el feed desde la API real**: descartado porque el pipeline de resumen
  no está cableado y el feed sale vacío; además arrastraría `ktor-client` y la
  configuración de URL por plataforma (FT00035).
- **ViewModel + `StateFlow` ya**: descartado por alcance; FT00034 lo entrega y
  `FeedStateHolder` está diseñado para ser sustituido sin tocar `FeedScreen`.
- **Framework de DI**: descartado; la skill mantiene DI manual por constructor
  hasta que se justifique lo contrario.
- **Un color por categoría** (11 colores): descartado por `DESIGN.md`, que agrupa
  las 11 categorías en tres tonos.
- **`kotlinx-datetime`**: descartado; un formateador puro evita una dependencia
  y no rompe iOS/Wasm.

## Consecuencias

- Habilita toda la UI siguiente: FT00033 (detalle) reutiliza el tema, la tarjeta
  y los badges; FT00034 sustituye `FeedStateHolder` por un ViewModel con
  `StateFlow` y añade navegación; FT00035 implementa `FeedRepository` con HTTP y
  caché y mapea desde `:shared`; FT00036/FT00037 reutilizan `design/components/`.
- Coste asumido: `design/components/` conoce los modelos de `feature/feed/domain`
  (el spec fija que los componentes reciben la categoría/motivo de dominio). Si
  otra feature necesita componentes equivalentes, se extraen a un modelo
  compartido de presentación en vez de duplicarlos.
- Añade una dependencia de Gradle en `:composeApp` (`compose.components.resources`
  en `commonMain` y `kotlinx-coroutines-test` en `commonTest`); ninguna de red.
- El tema define el esquema **claro** únicamente; el modo oscuro y la
  accesibilidad/i18n multi-idioma formal son FT00043.
- Documentación afectada: `ARCHITECTURE.md` (§`:composeApp`), `CONSTRAINTS.md`
  (§«Cliente (Compose Multiplatform)»), skill
  `compose-multiplatform-architecture` (§«Estado actual») y
  `docs/desarrollo-local.md` (producto).
