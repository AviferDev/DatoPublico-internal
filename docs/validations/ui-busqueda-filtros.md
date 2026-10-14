# Validación — `ui-busqueda-filtros` (FT00036)

- **Fecha:** 2026-10-14
- **Rol:** `feature-validator` (validación independiente; `revise` → rebase sobre FT00037 → `accept`; vía agente `general` en el worktree)
- **Spec:** `docs/specs/ui-busqueda-filtros.md`
- **Rama:** `feat/ft00036-ui-busqueda-filtros` (rebasada sobre `origin/main` = `dd2fab7`, con FT00037; HEAD `55b59cc`)
- **Diff:** 30 ficheros
- **Veredicto final:** **`accept`**

## Gate reejecutado (real)

| Comando | Resultado |
| --- | --- |
| `:composeApp:jvmTest --rerun-tasks` | **105 tests, 0 fallos** (26 de búsqueda, con `MockEngine`) |
| `:composeApp:detekt` + `:cpdCheck` | OK |
| `:composeApp:assembleDebug` / `wasmJsBrowserDistribution` / iOS framework | OK |

## Comprobaciones

- Filtros de categoría (11 + «Todas») y rango de fechas ISO inclusivo; fechas
  inválidas se omiten sin crash; rango invertido → «sin resultados»; consulta en
  blanco no llama.
- Estados inicial/carga/resultados/sin resultados/error+reintento.
- `HttpSearchRepository`/`SearchApi` sobre `core/network` (`GET /v1/buscar`),
  inyectado en `App()`; repositorio en memoria para previews/tests.
- Navegación aditiva (`AppRoutes.SEARCH`, destino `search`, acción en el encabezado
  del feed **visible en todos los estados**).
- `@Preview` en toda función `@Composable`; i18n; Material Icons; colores del tema;
  estilo MUST; sin tocar `:shared`/`:backend`/CI/`init.sh`.
- Rebase sobre `main` (FT00037) sin romper chat ni detalle.

## Hallazgos

- **High (cerrado):** el acceso a búsqueda desaparecía con el feed sin contenido →
  encabezado movido fuera de la rama de estado (resuelto al rebasar sobre FT00037 y
  unificar el encabezado con chat + búsqueda).
- **Low (resuelto por el orquestador):** docs durables del harness (ADR 0033 + docs).
- **Low (declarado):** captura `antes-busqueda` tomada sobre la base previa a
  FT00037 (no muestra la acción de chat); sin `despues-busqueda-sin-resultados`
  (opcional). PR en el límite de 30 ficheros.

Sin hallazgos High residuales. Sin hallazgos de seguridad.
