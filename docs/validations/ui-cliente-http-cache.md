# Validación — `ui-cliente-http-cache` (FT00035)

- **Fecha:** 2026-10-14
- **Rol:** `feature-validator` (validación independiente; ejecutada vía agente `general` en el worktree)
- **Spec:** `docs/specs/ui-cliente-http-cache.md`
- **Rama:** `feat/ft00035-ui-cliente-http-cache` (rebasada sobre `origin/main` = `082245b`)
- **Diff:** 25 ficheros de producto
- **Veredicto:** **`accept`**

## Gate reejecutado (real)

| Comando | Resultado |
| --- | --- |
| `:composeApp:jvmTest` (`--rerun`) | **33/0** (18 nuevos con `MockEngine`) |
| `:composeApp:assembleDebug` | OK |
| `:composeApp:wasmJsBrowserDistribution` | OK |
| `:composeApp:linkDebugFrameworkIosSimulatorArm64` | OK |
| `build -PskipClient` | OK |
| `test` (agregado) | OK |
| `detekt` + `:cpdCheck` | OK |
| `build --no-daemon` | 211 tareas |

## Comprobaciones

- **0** `http://` en `commonMain`; URL base y fecha por `expect/actual` (4 actuals).
- DTOs de cliente con `@SerialName` explícito y tokens **1:1** con `:shared`; mapeo
  puro a los modelos de dominio.
- `HttpFeedRepository`: éxito → mapea + cachea; fallo → cache o `Failure`; día vacío
  → `Success`.
- Errores tipados (`Network`/`Server(status, code)`/`InvalidBody`); `CancellationException`
  relanzada; `HttpTimeout`.
- Tests con `MockEngine` (sin sockets); sin datos personales; Android con
  `INTERNET` + `network_security_config` limitado.
- Estilo MUST conforme; **no** se toca `:shared`/`:backend`/CI/`init.sh`; `:composeApp`
  no depende de `:shared`.

## Hallazgos

- **Medium (resuelto):** docs durables del harness — ADR **0029** + índice,
  `ARCHITECTURE.md`, `CONSTRAINTS.md` §«Cliente», validación, `PROGRESS.md`,
  `feature_list.json`.
- **Medium (resuelto):** conflicto de rebase en `docs/desarrollo-local.md` (FT00033
  vs FT00035) — conservadas ambas secciones.
- **Low (resuelto):** `kotlin-js-store/yarn.lock` — revertido (ruido no reproducible).
- **Low (aceptado):** `js("new Date()")` en Wasm; `ClientApiErrorDto.code: String?`.
- **Low:** `InMemoryFeedCache` sin sincronización; sin indicador de staleness; espejo
  de DTOs sin test anti-deriva (mitigado por tests con JSON de ejemplo).

Sin hallazgos Critical/High. Sin hallazgos de seguridad.
