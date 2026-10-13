# Validación — `api-contratos-openapi` (FT00029)

- **Fecha:** 2026-10-13
- **Rol:** `feature-validator` (validación independiente)
- **Spec:** `docs/specs/api-contratos-openapi.md`
- **Rama:** `feat/ft00029-api-contratos-openapi` (rebasada sobre `origin/main` = `db33428`)
- **Diff de producto:** 11 ficheros
- **Veredicto:** **`accept`**

## Gate reejecutado (real)

| Comando | Resultado |
| --- | --- |
| `:backend:test --rerun-tasks` | **460 tests, 0 fallos, 0 errores, 0 skipped** |
| `:shared:jvmTest` | **37 tests, 0 fallos** |
| `build --no-daemon -PskipClient` | 23 tareas (incluye detekt + `:cpdCheck`) |
| `test` | 3 módulos |
| `detekt` (+`:cpdCheck`) | BUILD SUCCESSFUL |
| `env -u JAVA_HOME .harness/init.sh` | exit 0 |
| Arranque sin BD/modelo/clave | `/health` 200; `/openapi.json` 200 `application/json`; `/v1/…` 404; sin `/v1` 404 |

Tests nuevos: `OpenApiRouteTest` 3, `OpenApiContractTest` 2.

## Comprobaciones

- Documento OpenAPI 3.1 (`openapi=3.1.0`, `info.title="DatoPublico API"`,
  `info.version="0.5.0"`) con `paths` = `/v1/feed`, `/v1/publicacion/{id}`,
  `/v1/buscar`, `/v1/chat`, `/health`, `/openapi.json`.
- **Test anti-deriva real**: propiedades contra `descriptor.elementNames` y enums
  contra tokens (verificado a mano contra los DTOs de `:shared`).
- Prefijo `/v1` en las rutas de dominio; `/health` y `/openapi.json` sin prefijo.
- Rutas reutilizadas sin modificar; tests de features `accepted` solo con cambio de
  URL (mecánico) + 1 test aditivo en `FeedRouteTest`.
- Sin dependencia Gradle nueva, sin migración, sin `:composeApp`/CI/`init.sh`.
- Estilo MUST cumplido.

## Hallazgos

- **Low (resuelto por el orquestador):** estado del harness sin persistir —
  actualizado a `accepted`.
- **Low (mejora futura):** el anti-deriva no afirma que *todos* los
  `components.schemas` estén cubiertos.
- Desviaciones declaradas aceptadas: `object`+`by lazy` para la carga del
  documento; `ChatRouteLiveTest` a `/v1/chat`.

Sin hallazgos Critical/High/Medium. Sin hallazgos de seguridad.
