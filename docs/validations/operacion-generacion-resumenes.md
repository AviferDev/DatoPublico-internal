# Validación — `operacion-generacion-resumenes` (FT00049)

- **Rama**: `feat/ft00049-operacion-generacion-resumenes` (PR #42) · fusionada en
  `main` como `d3125e5`; las reparaciones de las rondas 2–3 viven en el árbol de
  trabajo de cierre.
- **Spec**: `docs/specs/operacion-generacion-resumenes.md` (**retroactivo**, creado en
  la ronda 2 para cerrar la gobernanza de una feature entregada sin spec).
- **Validador**: `feature-validator` (independiente del implementador).
- **Fecha**: 2026-10-18.

## Veredicto

**`accept`** (ronda 3).

| Ronda | Veredicto | Motivo |
| --- | --- | --- |
| 1 | `revise` | **F1 (High, gobernanza)**: sin spec ni registro de validación. **F2 (Medium)**: la doc describía el proveedor sin la cabecera `x-opencode-session` y no documentaba el CLI `generateSummaries`. **F3 (Medium)**: faltaba `GenerateSummariesConfigTest`. **F4–F6 (Low)**. |
| 2 | `revise` | F1/F2/F3 **resueltos** (494 tests, +8); quedaban **M1 (Medium)** —`CONSTRAINTS.md` sin actualizar, aunque el spec lo exigía— y **L1 (Low)** —nota de riesgos del spec obsoleta—. |
| 3 | **`accept`** | M1/L1 cerrados; sin cambios de código ni tests. |

## Checks reejecutados

### Ronda 1

- `:backend:test`/`detekt`/`:cpdCheck` con `--rerun-tasks` → **486 tests, 0 fallos**;
  `OpenCodeTextGenerationProviderTest` 7/7.
- Arranque real del CLI: sin `OPENCODE_API_KEY` → exit ≠ 0 con mensaje claro y **sin
  filtrar el secreto**; rango invertido y `SUMMARY_LIMIT=0` → fail-fast correcto.
- La tarea `:backend:generateSummaries` no está enganchada a `build`/`check`, ni en
  `.github/` ni en `init.sh` (grep: 0 coincidencias).
- **No reproducible aquí**: la ejecución real contra PostgreSQL + OpenCode (sin
  `OPENCODE_API_KEY`; el contenedor `datopublico-postgres` estaba `Exited` y el único
  Postgres vivo era de `boe-rag`).

### Rondas 2–3

- `:backend:test :backend:detekt :cpdCheck --rerun-tasks` → BUILD SUCCESSFUL:
  **494 tests, 0 fallos** (`:backend` pasa de 486 a 494 = los 8 del test nuevo);
  `detekt.txt` vacío; `cpdCheck.xml` con **0 duplicaciones**.
- Ronda 3: `:backend:detekt :cpdCheck` → BUILD SUCCESSFUL, ambos `UP-TO-DATE` (prueba
  independiente de que las fuentes no cambiaron en la ronda). El validador confirmó
  además por `mtime` que no se tocó código ni tests.
- Cotejo de las reglas nuevas de `CONSTRAINTS.md` contra el código real:
  `OpenCodeTextGenerationProvider` (cabecera + `User-Agent`),
  `GenerateSummariesConfig` (defaults 25/250 ms y fail-fast), `GenerateSummariesMain`
  (PostgreSQL + E5 + clave), `SummaryGenerationPipeline` (reejecutable, guardrails +
  disposición) y `Application.kt` (proveedor compartido con el chat).

## Hallazgos

- **F1 (High, gobernanza)** — Sin spec ni registro de validación: la feature se
  fusionó sin pasar por `planner→implementer→validator`. **Resuelto** con el spec
  retroactivo (ronda 2).
- **F2 (Medium)** — Doc que contradecía el comportamiento (cabecera obligatoria) y CLI
  sin documentar. **Resuelto**: sección nueva en `docs/desarrollo-local.md` y mención
  de FT00049 en `ARCHITECTURE.md`.
- **F3 (Medium)** — `GenerateSummariesConfigTest` ausente. **Resuelto**: 8 casos
  (defaults, `dates()` inclusivo de 3 días, overrides, valores en blanco, rango
  invertido, `LIMIT<=0` con `0`/`-3`, `DELAY_MS<0`, fecha no ISO).
- **M1 (Medium)** — `CONSTRAINTS.md` sin la regla que el spec exigía. **Resuelto**
  (ronda 3): dos **MUST** nuevas (cabecera de sesión y generación opt-in fuera del
  gate).
- **L1 (Low)** — Nota de riesgos del spec obsoleta sobre `OPENCODE_SESSION_ID`.
  **Resuelto** (ronda 3).
- **N1 (Low)** — §«Chat RAG» de `CONSTRAINTS.md` decía que el proveedor «no se
  modifica». **Resuelto**: se acota con «(FT00020; FT00049 añade la cabecera
  `x-opencode-session` y el `User-Agent`)».
- **N2 (Low)** — Roces de redacción entre la regla histórica «librería sin wiring /
  sin guardrails» y la nueva MUST (patrón de secciones por feature del fichero). **No
  es contradicción real.** **Deuda.**
- **F4 (Low)** — El test del `sessionId` solo comprueba *presencia* de cabeceras, no
  que el id se reutilice. **Deuda.**
- **F5 (Low)** — `hasRealSummary` queda fuera del `try/catch` por publicación,
  contradiciendo el KDoc de `attempt`. **Deuda.**
- **F6 (Low)** — Construcción de `SearchFilter` duplicada entre
  `SummaryGenerationPipeline` y `CitizenSummaryGenerator` (MUST «reutilizar antes de
  escribir»). **Deuda.**

## Seguridad

Sin hallazgos. Sin secretos versionados (`OPENCODE_API_KEY` solo por entorno con
fail-fast; el test usa `"clave-de-prueba"`); el abort por falta de clave imprime solo
el **nombre** de la variable. Los logs registran `id`, `outcome` y el balance
agregado, nunca prompt, contexto, contenido del resumen ni la clave. La cabecera
`x-opencode-session` no es secreto ni contiene PII. Sin endpoints ni UI nuevos: el CLI
es una tarea opt-in no expuesta por red. SQL parametrizado; `SUMMARY_*` con parseo
fail-fast.

## Estado

- **FT00049 → `accepted`** (persistido en `feature_list.json` y
  `docs/feature-ids.md`).
- Deuda Low pendiente: F4/F5/F6 y N2.
