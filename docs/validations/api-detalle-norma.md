# Validación — `api-detalle-norma` (FT00027)

- **Fecha:** 2026-10-13
- **Rol:** `feature-validator` (validación independiente)
- **Spec:** `docs/specs/api-detalle-norma.md`
- **Rama:** `feat/ft00027-api-detalle-norma` (rebasada sobre `origin/main`, que ya incluye FT00026 `8bc7ad8`)
- **Diff de producto:** 8 ficheros vs `origin/main` (coincide con *Expected File Changes*)
- **Veredicto:** **`accept`**

## Gate reejecutado (real, no la evidencia)

| Comando | Resultado |
| --- | --- |
| `:backend:test --rerun-tasks` | BUILD SUCCESSFUL — **414 tests, 0 fallos, 0 errores** |
| `:shared:jvmTest` | **30 tests, 0 fallos** |
| `build --no-daemon -PskipClient` | 23 tareas |
| `test` | 63 tareas / 3 módulos |
| `detekt` + `:cpdCheck --rerun-tasks` | 4 tareas |
| `env -u JAVA_HOME .harness/init.sh` | exit 0 |
| Arranque sin BD | `/health` 200 · `/feed` 404 · `/publicacion/{id}` 404 · log `Base de datos no configurada` |

Tests nuevos: `PublicationDetailServiceTest` 6/0/0, `PublicationDetailRouteTest` 4/0/0,
`PublicationDetailLiveTest` 1 (omitido). Backend 403 (FT00026) → **414** (+11).

## Escenarios

- **E1** (publicado → 200 con `PublicacionDto` completo): ✓
- **E2** (solo `publicado`; otros estados → `null`/404): ✓
- **E3** (id desconocido → 404): ✓
- **E4** (blanco o `> MAX_ID_LENGTH` → 400): ✓
- **E5** (arranque sin BD / pool único / ruta condicional): ✓
- **E6** (determinismo y trazabilidad `urlOficial == resumen.fuenteOficial`, `avisoIA`): ✓
- **E7** (gate sin red ni BD): ✓
- **E8** (live opt-in `DB_LIVE_TEST=1`): **no ejecutado** — sin Docker/PostgreSQL en el entorno; limitación aceptada (test auto-omitido).

## MUST / alcance / seguridad

- Solo `estado='publicado'` vía token tipado `SummaryState.PUBLISHED`; sin literal suelto en el servicio.
- Reutilización real sin duplicar: `PublicationRepository.findById` + `SummaryRepository.findByPublication` + `feed.FeedDtoMapper.toPublicacionDto`; sin SQL nuevo.
- Categoría nula (`takeIf { categoria != null }`) → 404 sin crash.
- Lectura en `Dispatchers.IO`; `200/400/404`; `/health` intacto; pool JDBC único compartido y cierre único.
- `@SerialName` explícito (contrato `:shared` reutilizado); un solo `return`, sin `else if`, ≤40 líneas.
- Alcance: sin migración (`V1`…`V5` intactas), sin dependencias Gradle, sin tocar `:shared`/`:composeApp`/CI/`init.sh`.
- Seguridad: endpoint público de solo lectura sobre información pública; SQL parametrizado; entrada acotada; sin secretos; CORS/rate-limit diferidos a FT00030. **Sin hallazgos.**

## Hallazgos

- **Low (resuelto por el orquestador al persistir):** el estado del harness
  (`feature_list.json`, `feature-ids.md`, `PROGRESS.md`) seguía `not_started`; ya
  actualizado a `accepted` con esta evidencia.
- Sin hallazgos Critical/High/Medium. Sin hallazgos de seguridad.
