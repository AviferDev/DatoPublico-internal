# ADR 0031: Navegación oficial de Compose Multiplatform y estado por ViewModel/StateFlow (UDF)

## Estado

Aceptado (2026-10-14). Decisión del dueño del proyecto al ejecutar
`ui-navegacion-estado` (FT00034). Continúa el ADR 0027 (base del cliente CMP) y no
supersede ninguno.

## Contexto

FT00032 dejó un **holder de estado local** (`FeedStateHolder` con `mutableStateOf`)
y **sin** navegación, deliberadamente (ADR 0027), para que FT00034 formalizara el
**patrón de estado** y la **navegación** entre pantallas. FT00033 entregó la
pantalla de detalle como contrato (`DetailRoute`), sin cablearla.

Restricciones: Compose Multiplatform 1.7.3 (Kotlin 2.1.20); targets Android/Wasm/iOS;
gate SDK-free intacto; MUST de UI (i18n, `@Preview`, Material Icons, sin crashes,
un solo `return`, sin `else if`, ≤40 líneas/función).

## Decisión

1. **Navegación oficial de JetBrains**: `org.jetbrains.androidx.navigation:navigation-compose`
   (versión alineada con CMP 1.7.3) + `lifecycle-viewmodel-compose`/`lifecycle-runtime-compose`
   (versiones que declara navigation, para evitar `IrLinkageError` en iOS). Rutas
   **string** con `navArgument` (sin plugin de serialización). Grafo en
   `app/AppNavHost` + `app/AppRoutes` (`feed` y `detail/{publicationId}`); el
   argumento se lee con `.orEmpty()` (nunca `!!`).
2. **Estado UDF por ViewModel**: cada pantalla expone su estado con un `XViewModel`
   (androidx.lifecycle multiplataforma) como `StateFlow<XUiState>` **inmutable**;
   los composables son **stateless** y la UI recolecta con
   `collectAsStateWithLifecycle()`; los eventos son métodos del ViewModel (p. ej.
   `onRetry()`), nunca estado mutable expuesto. `FeedStateHolder` se **elimina**.
3. **`SharingStarted.Eagerly`** para el feed (fuente caliente en memoria): conserva
   el estado al volver del detalle en vez de reejecutar la carga (sin volver a
   `Loading`). Se reevaluará cuando FT00035 introduzca un flujo frío/cacheado.
4. **DI manual** por constructor/factory (sin Koin/Hilt).
5. **El destino `detail` es un placeholder** en FT00034; la pantalla real de FT00033
   (`DetailRoute`) se integrará en el grafo en un paso posterior.

## Alternativas consideradas

- **Voyager / Decompose**: descartados (terceros; más superficie para dos destinos).
- **Navegación propia** (`mutableStateOf` + `BackHandler` `expect/actual`):
  descartada; reimplementa el back del sistema/navegador.
- **Plugin de serialización de rutas**: descartado; rutas string con `navArgument`
  evitan añadir el plugin a `:composeApp`.
- **`WhileSubscribed`** (recomendado por la skill): descartado para el feed por la
  fuente caliente; se reevaluará con FT00035.

## Consecuencias

- `:composeApp` cumple el patrón de estado/navegación objetivo; habilita FT00036/FT00037
  (búsqueda/chat) sobre el mismo grafo.
- Coste asumido: `navigation-compose` KMP está en **alpha** (`2.8.0-alpha11`), fijada
  la versión y usando solo la superficie estable; dependencia de `lifecycle`
  multiplataforma en `commonMain` (sin red).
- Pendiente: integrar `DetailRoute` (FT00033) en el grafo (hoy placeholder).
- Documentación afectada: `ARCHITECTURE.md` (§`:composeApp`), `CONSTRAINTS.md`
  (§«Cliente»), skill `compose-multiplatform-architecture`, `docs/desarrollo-local.md`.
