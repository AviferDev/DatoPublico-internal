# Validación — `ui-navegacion-estado` (FT00034)

- **Fecha:** 2026-10-14
- **Rol:** `feature-validator` (validación independiente; ejecutada vía agente `general` en el worktree)
- **Spec:** `docs/specs/ui-navegacion-estado.md`
- **Rama:** `feat/ft00034-ui-navegacion-estado` (rebasada sobre `origin/main` = `082245b`)
- **Diff:** 21 ficheros
- **Veredicto:** **`accept`**

## Gate reejecutado (real)

| Check | Resultado |
| --- | --- |
| `:composeApp:jvmTest` | **22 tests, 0 fallos** |
| `:composeApp:assembleDebug` | OK |
| `:composeApp:wasmJsBrowserDistribution` | OK |
| `:composeApp:linkDebugFrameworkIosSimulatorArm64` | OK |
| `test` (agregado) | `:composeApp` 22 + `:backend` 481 + `:shared` 39, 0 fallos |
| `detekt` + `:cpdCheck` | OK |
| `build --no-daemon` | 211 tareas |
| `build -PskipClient` | OK |

## Comprobaciones

- **UDF**: `FeedViewModel` con `StateFlow<FeedUiState>` inmutable; `onRetry()` como
  evento; composables stateless; `collectAsStateWithLifecycle`; `FeedStateHolder`
  eliminado sin referencias stale.
- **Navegación**: `AppNavHost`/`AppRoutes` con `navArgument` y `.orEmpty()`
  (`navigation-compose` 2.8.0-alpha11 + `lifecycle` 2.8.4).
- **Clic** propagado `PublicationCard` → `HighlightsSection`/`FeedScreen`/`FeedRoute`.
- **Detalle placeholder** (no invade FT00033); **conservación de estado** al volver.
- i18n, `@Preview`, Material Icons, colores del tema; capturas abiertas y correctas.
- Alcance: sin tocar `:shared`/`:backend`/CI/`init.sh`/`DESIGN.md`.

## Hallazgos

- **Low (resuelto por el orquestador):** docs durables — ADR **0031** + índice,
  `ARCHITECTURE.md`, `CONSTRAINTS.md` §«Cliente», validación, `PROGRESS.md`,
  `feature_list.json`.
- **Low (resuelto):** KDoc de `FeedViewModel` citaba «ADR 0028» (ocupado) —
  corregido a 0031.
- **Low (resuelto):** el rebase sobre `main` (FT00033) produjo un **duplicado** de la
  clave i18n `cd_back` (rompía `convertXmlValueResourcesForCommonMain`) — corregido;
  conflicto de `docs/desarrollo-local.md` resuelto.
- **Low (aceptado):** `@Suppress("FunctionNaming")` en `AppNavHost.kt`; `viewModel()`
  por defecto en `FeedRoute`; cabecera de `strings.xml`.

Sin hallazgos Critical/High/Medium. Sin hallazgos de seguridad.
