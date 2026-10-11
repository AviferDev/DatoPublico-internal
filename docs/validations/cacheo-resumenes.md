# Validación — `cacheo-resumenes` (FT00021)

- Veredicto: **`accept`**
- Fecha: 2026-10-11
- Rol: `validator` (independiente, solo lectura; no implementa ni corrige)
- Spec: `.harness/docs/specs/cacheo-resumenes.md`
- Rama: `feat/ft00021-cacheo-resumenes` (commit `f7cf517 chore(FT00021): claim`;
  cambios de la feature **sin commitear** en el árbol de trabajo)
- Estado en `feature_list.json`: `passing` (a persistir `accepted` por el
  orquestador).

## Checks reejecutados (JAVA_HOME = JBR 21, desde `..`)

| Comando | Resultado |
| --- | --- |
| `./gradlew :backend:test --rerun-tasks` | BUILD SUCCESSFUL; **278** tests, 0 fallos, 0 errores, 0 omitidos (59 suites). |
| `./gradlew build --no-daemon -PskipClient` | BUILD SUCCESSFUL (23 tareas). |
| `./gradlew test` | BUILD SUCCESSFUL (63 tareas, 3 módulos). |
| `./gradlew detekt -PskipClient` | BUILD SUCCESSFUL (`:shared:detekt`, `:backend:detekt`, `:cpdCheck`). |
| `env -u JAVA_HOME .harness/init.sh` | **exit 0** («Gate OK»). |
| `docker compose up -d` + `:backend:flywayMigrate` + `DB_LIVE_TEST=1 :backend:test --tests '*SummaryCachePersistenceLiveTest'` | **BUILD SUCCESSFUL**; test real ejecutado: *round-trip* OK, *upsert* idempotente (filas=1), uso OK (registros=2, delta=33). |

Recuento real de tests nuevos (+25 = 278−253): `SummaryCacheKeyTest` 7,
`CachedCitizenSummaryGeneratorTest` 5, `ResumenCacheMigrationSqlTest` 5,
`SummaryCachePersistenceTest` 3, `SummaryCachePersistenceLiveTest` 1,
`CitizenSummaryGeneratorTest` +2 (7) y `OpenCodeTextGenerationProviderTest` +2 (7).

## Escenarios del spec

1–5 (gate): `CachedCitizenSummaryGeneratorTest` + `SummaryCacheKeyTest` con
dobles. Acierto **no** llama al proveedor (`provider.calls == 0`) y registra
`cache_hit = true` con 0 tokens; fallo genera, cachea y registra tokens reales;
inválido (`MISSING_DEADLINE`) **no** se cachea pero **sí** registra uso; modelo o
`promptVersion` distintos → fallo de caché; clave determinista y *fail-fast*
(`IllegalArgumentException`) en blanco. Verificado.
6 (gate): `OpenCodeTextGenerationProviderTest` con `MockEngine` (con `usage` ⇒
tokens; sin `usage` ⇒ `null`). Verificado.
7 (gate sin red ni BD): todos los comandos del gate en verde; las pruebas reales
imprimen «omitido» sin abrir sockets ni conexiones (guardas `DB_LIVE_TEST`/
`OPENCODE_LIVE_TEST`/`EMBEDDING_LIVE_TEST`). Verificado.
8 (opt-in): **ejecutada por el validator** contra PostgreSQL/Docker con la
migración `V4` aplicada; `find` devuelve el mismo `ResumenDto`, `totalTokens()`
cuadra y el *upsert* es idempotente por `cache_key`. Verificado.

## Hallazgos

Ninguno bloqueante. Único hallazgo **Low** (evidencia, no código):

- `feature_list.json` (`evidence`) dice «6 tests nuevos»; son **5** ficheros de
  test nuevos (el total «17 ficheros de producto» sí cuadra excluyendo
  `docs/desarrollo-local.md`). Corregir la cifra al persistir la evidencia.

## Seguridad

Sin hallazgos. SQL **parametrizado** (`?`, sin concatenación) en ambos
repositorios; sin secretos ni credenciales versionadas (el test opt-in lee
`POSTGRES_*` del entorno/`.env` gitignored); sin entrada de usuario no confiable
(el resumen lo valida `CitizenSummaryValidator` antes de cachearse y solo se
cachean `Valid`); un fallo del proveedor **no** se cachea ni registra uso (la
excepción propaga antes de `record`/`put`); *fail-fast* de `SummaryCacheKey` y del
`decode` de un JSON corrupto. FK en cascada en `resumen_cache`; `generacion_uso`
sin FK (log de coste). Sin red en el gate.

## Alcance, arquitectura y estilo

- Alcance verificado por `git status`: solo `rag/generation/` (2 mod),
  `rag/summary/` (3 mod + 2 nuevos), `persistence/` (2 nuevos), migración `V4`,
  tests y `docs/desarrollo-local.md`. **Intactos**: `Application.kt`, `ingesta/`
  (job/backfill), `:shared`, `:composeApp`, CI e `init.sh`; sin dependencias Gradle
  nuevas ni cambios en `build.gradle.kts`/`config/detekt`.
- Migración `V4` versionada (no edita `V1`/`V2`/`V3`) y fuera de `build`/`check`;
  el test de contrato SQL la lee del classpath sin ejecutar SQL.
- Estilo MUST: `return` único por función, sin `else if`, funciones ≪40 líneas,
  KDoc en castellano e identificadores en inglés; `@SerialName` explícito en los
  DTOs de wire nuevos (`ChatUsageDto`, `ChatCompletionResponseDto.usage`); sufijos
  correctos (`...Entity` en persistencia, `Dto` en wire, `TokenUsage`/
  `CachedSummaryResult` internos sin sufijo).
- Sin wiring: `CachedCitizenSummaryGenerator` es una librería; el modelo se inyecta
  por constructor. Dirección de dependencias correcta (`rag/summary` → `persistence`).

## Documentación y harness

- `ARCHITECTURE.md` (párrafo FT00021), `CONSTRAINTS.md` §«Cacheo y control de
  coste», ADR `docs/adr/0016-cacheo-resumenes-uso-tokens.md` + índice
  (`docs/adr/README.md` línea 76), skill `rag-datapublico` §5 (estado FT00021) y
  `docs/desarrollo-local.md` actualizados y coherentes con el código.
- `feature_list.json` FT00021 `passing` con evidencia; `docs/feature-ids.md` línea
  39 `passing`; `PROGRESS.md` con la entrada de sesión. JSON válido.
- **Pendiente del orquestador**: persistir `accepted` en `feature_list.json` y
  `docs/feature-ids.md` y corregir la cifra Low de tests nuevos.

## Nota sobre el riesgo cerrado

El implementer marcó la prueba real opt-in como **no ejecutada**. Este validator
la ejecutó con éxito (PostgreSQL/Docker + `V4`), cerrando el riesgo de
persistencia. La limitación declarada queda **resuelta**.
