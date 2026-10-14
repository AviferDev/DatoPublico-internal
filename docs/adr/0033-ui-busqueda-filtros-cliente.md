# ADR 0033: UI de búsqueda con filtros en el cliente CMP (HTTP real y estados)

## Estado

Aceptado (2026-10-14). Decisión del dueño del proyecto al ejecutar
`ui-busqueda-filtros` (FT00036). Continúa los ADR 0027 (base del cliente), 0029
(cliente HTTP común) y 0031 (navegación + ViewModel/`StateFlow`); no supersede
ninguno.

## Contexto

La API de búsqueda (`GET /v1/buscar`, FT00028) existe y filtra por categoría y
rango de fechas. Faltaba la **pantalla** en `:composeApp`. El spec se planificó
antes de que existiera el cliente HTTP (FT00035), con un repositorio en memoria.

## Decisión

1. **Capa `feature/search/{domain,data,ui}`**: dominio propio (`SearchFilters`,
   `SearchResults`, `SearchLoadResult` tipado, `isIsoDate` puro sin `java.time`),
   `SearchPublications` (consulta en blanco no llama), puerto `SearchRepository`,
   `SearchViewModel` (`StateFlow<SearchUiState>`, UDF) y UI stateless
   (`SearchScreen`/`SearchView`s/`SearchFilterBar`).
2. **Filtros** de categoría (11 curadas + «Todas») y rango de fechas ISO
   **inclusivo**; fechas inválidas se marcan y **omiten** (sin crash); rango
   invertido → lista vacía → estado «sin resultados».
3. **HTTP real (ajuste del orquestador):** además del repositorio en memoria
   (previews/tests), `HttpSearchRepository` + `SearchApi` sobre `core/network`
   (ADR 0029) llaman a `GET /v1/buscar` con DTO propio (`@SerialName`),
   reutilizando `FeedPublicationDto` y el mapeo del feed, y derivando el token de
   categoría de los `@SerialName` de `FeedCategoryDto`; el *composition root*
   inyecta el real en `App()`.
4. **Navegación aditiva:** `AppRoutes.SEARCH`, destino `search` y acción (icono)
   en el **encabezado del feed**, visible en **todos** los estados; abrir un
   resultado navega al detalle y el atrás conserva el estado (ViewModel scopeado al
   back stack).

## Alternativas consideradas

- **Solo repositorio en memoria** (spec original): descartado tras aterrizar
  FT00035; se conserva para previews/tests.
- **Filtro de «ámbito»** (roadmap 0.9-T01): diferido; el endpoint no lo expone.
- **Duplicar el mapeo HTTP**: descartado; se extrajo el manejo común de respuesta a
  `core/network/ApiResult.kt` y `FeedApi` lo reutiliza (evita CPD).

## Consecuencias

- La UI de búsqueda queda funcional y conectada a la API real; cierra el alcance de
  UI del cliente CMP junto con FT00032–FT00035 y FT00037.
- Coste asumido: duplicación del contrato de wire (capa anti-corrupción, ADR 0029);
  en runtime, sin el corpus indexado, la búsqueda devuelve 0 resultados.
- Documentación afectada: `ARCHITECTURE.md` (§`:composeApp`), `CONSTRAINTS.md`
  (§«Cliente»), skill `compose-multiplatform-architecture`, `docs/desarrollo-local.md`.
