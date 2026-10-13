# Validación — `api-busqueda` (FT00028)

- **Fecha:** 2026-10-13
- **Rol:** `feature-validator` (validación independiente)
- **Spec:** `docs/specs/api-busqueda.md`
- **Rama:** `feat/ft00028-api-busqueda` (rebasada sobre `origin/main`, merge-base `defd04f`, que incluye FT00026 `8bc7ad8` y FT00027 `defd04f`)
- **Diff de producto:** 14 ficheros vs `origin/main`
- **Veredicto:** **`accept`**

## Gate reejecutado (real)

| Comando | Resultado |
| --- | --- |
| `:backend:test --rerun-tasks` | **432 tests, 0 fallos, 0 errores** |
| `:shared:jvmTest` | **33 tests, 0 fallos** |
| `build --no-daemon -PskipClient` | 23 tareas |
| `test` | 63 tareas / 3 módulos |
| `detekt --rerun-tasks -PskipClient` (+`:cpdCheck`) | 3 tareas forzadas |
| `env -u JAVA_HOME .harness/init.sh` | exit 0 |
| Arranque sin BD ni modelo | `/health` 200 · `/feed` 404 · `/publicacion/{id}` 404 · `/buscar` 404 |

Tests nuevos: `SearchServiceTest` 9, `SearchRouteTest` 7, `SearchContractTest` 3;
live opt-in `SearchPersistenceLiveTest`/`SearchServiceLiveTest` (soft-skip).

## Contrato / escenarios

- Escenarios 1–8 cubiertos (filtros, rango inclusivo, solo publicados, sin
  resultados, rango invertido → 200 vacío, dedup + orden de relevancia, ventana de
  candidatos, recorte a `limite`, fail-fast, 200/400/404).
- Solo `estado='publicado'` vía `SummaryState.PUBLISHED`; `resumen.publicacion_id`
  `UNIQUE` ⇒ sin duplicados; categoría nula excluida.
- Reutilización real de `HybridSearch`/`SearchFilter` y `FeedDtoMapper`; sin mapper
  por ítem; `FeedRepository.listPublishedByIds` ampliación aditiva.
- Rebase revisado: `configureRouting(feed, detail, search)`; pool y proveedor de
  embeddings creados/compartidos/cerrados una sola vez.
- Primer **cableado condicional** del `EmbeddingProvider` (sin modelo → `/buscar`
  404).
- SQL parametrizado (`ANY(?::text[])`); inferencia ONNX y JDBC en `Dispatchers.IO`.
- Estilo/contrato: `Dto` con `@SerialName` explícito; un solo `return`, sin
  `else if`, ≤40 líneas.
- Alcance: sin migración, sin dependencias nuevas, sin tocar
  `:composeApp`/CI/`init.sh`.

## Hallazgos

- **Low (resuelto por el orquestador):** estado del harness sin persistir
  (`feature_list.json`/`feature-ids.md`/`PROGRESS.md`) — actualizado a `accepted`.
- **Low (corregido):** frase obsoleta en `ARCHITECTURE.md` («sigue sin filtros de
  búsqueda»).
- **Low (corregido):** dos puntos colgantes en `docs/desarrollo-local.md` (sección
  «Búsqueda»).
- **Low (limitación aceptada):** tests live opt-in no ejecutados (sin
  Docker/PostgreSQL/modelo); cobertura doble en memoria + inspección del contrato SQL.

Sin hallazgos Critical/High/Medium. Sin hallazgos de seguridad.
