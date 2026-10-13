# Validación — `api-cors-ratelimit-errores` (FT00030)

- **Fecha:** 2026-10-13
- **Rol:** `feature-validator` (validación independiente)
- **Spec:** `docs/specs/api-cors-ratelimit-errores.md`
- **Rama:** `feat/ft00030-api-cors-ratelimit-errores` (rebasada sobre `origin/main` = `7ca8dff`)
- **Diff de producto:** 19 ficheros
- **Veredicto:** **`accept`**

## Gate reejecutado (real)

| Comando | Resultado |
| --- | --- |
| `:backend:test --rerun-tasks` | **481 tests, 0 fallos, 0 errores** |
| `:shared:jvmTest --rerun-tasks` | **39 tests, 0 fallos** |
| `build --no-daemon -PskipClient` | 23 tareas (detekt + `:cpdCheck`) |
| `test` | 67 tareas / 3 módulos |
| `detekt` + `:cpdCheck` | BUILD SUCCESSFUL |
| `env -u JAVA_HOME .harness/init.sh` | exit 0 |

Incremento +21 backend / +2 shared respecto a FT00029 (460/37): cuadra con
`HttpHardeningConfigTest` 6, `CorsRouteTest` 5, `RateLimitRouteTest` 4,
`ErrorsRouteTest` 5, `ErrorContractTest` 2 y `OpenApiRouteTest` +1.

## Arranque sin BD/modelo/clave

| Comprobación | Resultado |
| --- | --- |
| `GET /health` | 200 `{"status":"ok"}` |
| `GET /openapi.json` | 200 `application/json`, `info.version="0.5.1"`, esquemas `ApiErrorDto`/`ApiErrorCodeDto` |
| `GET /v1/feed` | 404 con cuerpo tipado `{"codigo":"no_encontrado","mensaje":"…"}` |
| `OPTIONS /v1/chat` (preflight) | 200, `Access-Control-Allow-Origin: *`, `Allow-Headers: Content-Type` |

## Contrato

- **CORS**: `CORS_ALLOWED_ORIGINS` (allowlist) o `anyHost()`; `allowCredentials=false`;
  preflight de `/v1/chat` resuelto.
- **Rate limiting**: por IP en memoria; general 60/60 s y chat 6/60 s; `/health` y
  `/openapi.json` exentos; 429 + `Retry-After` + cuerpo `demasiadas_peticiones`;
  configurble por entorno con fail-fast; `applyRateLimits=false` por defecto.
- **Error tipado**: `ApiErrorDto`/`ApiErrorCodeDto`; `StatusPages` mapea
  400/404/429/500/502; mensajes genéricos; `CancellationException` relanzada.
- **OpenAPI**: esquema de error + `429` con `Retry-After` + `info.version` 0.5.1;
  test anti-deriva real extendido.
- **3 dependencias Ktor 3.0.3** (cors/rate-limit/status-pages), sin sockets.
- Estilo MUST cumplido; sin migración, sin `:composeApp`/CI/`init.sh`.

## Hallazgos

- **Low (declarado aceptado):** `Access-Control-Allow-Methods` solo `OPTIONS`
  (Ktor filtra los métodos safelisted; el preflight funciona).
- **Low (declarado aceptado):** entrada `RateLimiting.kt$ApiRateLimiter` en
  `config/detekt/backend-baseline.xml` (`MatchingDeclarationName`).
- **Low (resuelto por el orquestador):** bookkeeping del harness —
  actualizado a `accepted`.

Sin hallazgos Critical/High/Medium. Sin hallazgos de seguridad.
