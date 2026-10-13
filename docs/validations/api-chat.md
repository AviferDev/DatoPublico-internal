# Validación — `api-chat` (FT00031)

- **Fecha:** 2026-10-13
- **Rol:** `feature-validator` (validación independiente; `revise` → reparación → `accept`)
- **Spec:** `docs/specs/api-chat.md`
- **Rama:** `feat/ft00031-api-chat` (`4fdcb8f`, base `origin/main` = `defd04f`, con FT00025/26/27)
- **Diff de producto:** 19 ficheros (+1487/−26)
- **Veredicto final:** **`accept`**

## Gate reejecutado (real)

| Comando | Resultado |
| --- | --- |
| `:backend:test --rerun-tasks` | **436 tests, 0 fallos, 0 errores** |
| `:shared:jvmTest` | **34 tests, 0 fallos** |
| `build --no-daemon -PskipClient` | 23 tareas |
| `test` | 63 tareas / 3 módulos |
| `detekt` (+`:cpdCheck`) | exit 0 |
| `env -u JAVA_HOME .harness/init.sh` | exit 0 |
| Arranque sin BD/modelo/clave | `/health` 200; `/feed`, `/publicacion/{id}`, `/chat` 404 |

Tests nuevos: `ChatServiceTest` 6, `ChatRouteTest` 8, `ChatDtoMapperTest` 4,
`PublicationCitationResolverTest` 2, `ChatContractTest` 4; live opt-in omitidos.

## Contrato / escenarios

- `:shared`: `ChatRequestDto`/`ChatResponseDto`/`ChatStatusDto`/`ChatCitationDto` con
  `@SerialName` explícito y tokens `respondida`/`refutada`/`sin_fundamento`; sin
  `usage`.
- Primer `CitationResolver` de producción (`PublicationCitationResolver`): URL
  inyectada desde la publicación; no resoluble → `null`.
- `ChatDtoMapper` puro (`when` exhaustivo); `ChatService` (`Dispatchers.IO`,
  `MAX_QUERY_LENGTH`, `limit` fijo).
- `POST /chat`: 200 (incl. `sin_fundamento`), 400, 404, 502, 500;
  `CancellationException` re-lanzada.
- Primer cableado condicional de OpenCode + embeddings (sin clave/modelo/BD →
  `/chat` 404); cierre único (`monitorResources`).
- Reutiliza `rag/chat` y `rag/*` sin modificarlos; SQL parametrizado; alcance sin
  migración ni dependencias nuevas ni `:composeApp`/CI/`init.sh`.

## Hallazgos

- **Medium (cerrado):** identificador en castellano `serviceCon` en
  `ChatServiceTest.kt` (regla MUST). Reparado a `serviceWith`; también renombrado en
  `RagChatServiceTest.kt` (test de FT00025) por la misma regla, renombrado puro
  (12/−12) sin cambio de comportamiento — aceptado con nota.
- **Low (resuelto por el orquestador):** bookkeeping del harness
  (`feature_list.json`/`feature-ids.md`/`PROGRESS.md`) — persistido `accepted`.
- **Low (limitación aceptada):** escenarios live opt-in no ejecutados (sin
  Docker/modelo/`OPENCODE_API_KEY`).

Sin hallazgos High. Sin hallazgos de corrección funcional, alcance, arquitectura ni
seguridad.
