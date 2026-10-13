# Validación — `ui-detalle` (FT00033)

- **Fecha:** 2026-10-13
- **Rol:** `feature-validator` (validación independiente; ejecutada vía agente `general` en el worktree por la restricción `external_directory` de los agentes de proyecto)
- **Spec:** `docs/specs/ui-detalle.md`
- **Rama:** `feat/ft00033-ui-detalle` (base `origin/main` = `2eec726`)
- **Diff:** 20 ficheros de producto (12 src + 2 test + `strings.xml` + `docs/desarrollo-local.md` + 4 PNG)
- **Veredicto:** **`accept`**

## Gate reejecutado (real, `--rerun-tasks`)

| Check | Resultado |
| --- | --- |
| `:composeApp:jvmTest` | **28 tests, 0 fallos** |
| `:composeApp:assembleDebug` | APK de debug |
| `:composeApp:wasmJsBrowserDistribution` | dist Wasm |
| `test` (agregado) | `:shared` 39 + `:backend` 481 + `:composeApp` → 0 fallos |
| `detekt` + `:cpdCheck` | sin hallazgos |
| `build --no-daemon --rerun-tasks` | 211/211 tareas, exit 0 (iOS link + lint) |

## Capturas / MUST

- Capturas abiertas: antes = feed (FT00032); después = detalle con los tres
  bloques, plazo (`tertiary`), enlace oficial y aviso de IA; no encontrada; error.
- i18n; `@Preview` (12 composables, 15 previews); Material Icons core; colores del
  tema; aviso de IA + enlace siempre visibles; `LocalUriHandler` con guarda
  `http(s)://`; estados sin crashes; estilo MUST; frontera respetada; sin tocar
  `:shared`/`:backend`/CI/`init.sh`/`libs.versions.toml`.

## Hallazgos

- **Low:** duplicación de la clave i18n `detail_retry` (frente a `feed_retry`).
- **Low:** acoplamiento `feature/detail → feature/feed/domain` y
  `design/components → feature/feed/domain` por la extracción diferida del
  vocabulario compartido (ADR 0028).
- **Low:** puerto de datos en `data/` (patrón preexistente de FT00032).

Sin hallazgos Critical/High/Medium. Sin hallazgos de seguridad.
