---
name: compose-multiplatform-architecture
description: Guía de arquitectura del cliente Compose Multiplatform (módulo :composeApp) de DatoPublico. Úsala al añadir o modificar pantallas, ViewModel, estado (UDF/StateFlow), use cases, repositorios/data sources, capas, navegación, DI, identidad de plataforma, tema, accesibilidad o tests del cliente Android/iOS/Web, o al planificar targets nuevos. Distingue el estado actual verificado del patrón objetivo (arquitectura por capas) y deriva del código real del repositorio, no de una arquitectura inventada.
---

# Arquitectura del cliente Compose Multiplatform — DatoPublico

Guía práctica para trabajar en `:composeApp`. Antes de tocar el cliente, lee
`DESIGN.md`, `docs/technical-discovery.md` y `docs/domain-model.md`. `CONTEXT.md`
fija el lenguaje de dominio.

**Estado actual:** el cliente todavía **no existe** (fase pre-bootstrap; el
esqueleto llega con `bootstrap-cmp-targets`). El patrón de este documento es el
**objetivo acordado**. No asumas que el estado actual ya lo cumple y no inventes
otra arquitectura.

## Topología de build (decidido)

- Kotlin Multiplatform + `org.jetbrains.compose`, **un único módulo
  `:composeApp`** que depende de `:shared` (DTOs y lógica compartida).
- Targets:
  - `androidTarget()`.
  - `iosArm64()` + `iosSimulatorArm64()` con `binaries.framework { baseName = ... }`.
  - `wasmJs { browser(); binaries.executable() }` (Web).
- Gradle Kotlin DSL con **version catalog**.
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
