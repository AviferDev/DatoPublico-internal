# Validación — `ui-design-refresh` (FT00053)

- **Rama**: `feat/ft00053-ui-design-refresh` (PR #47) · fusionada en `main` como
  `2fdb02a`; la reparación de la ronda 2 vive en el árbol de trabajo de cierre.
- **Spec**: `docs/specs/ui-design-refresh.md`.
- **Validador**: `feature-validator` (independiente del implementador).
- **Fecha**: 2026-10-18.

## Veredicto

**`accept`** (ronda 2).

| Ronda | Veredicto | Motivo |
| --- | --- | --- |
| 1 | `revise` | **D1 (Media, bloqueante)**: rompía la MUST «`@Preview` en toda función `@Composable`» — 17 composables sin preview directa en 4 ficheros y **3 previews borradas** en `ChatScreen.kt`. **D2–D5 (Low)** y observaciones de a11y. |
| 2 | **`accept`** | D1 resuelto: **0 composables sin preview**, 3 previews restauradas, sin cambios de comportamiento; gate verde. |

## Checks reejecutados

### Ronda 1

- `./init.sh --with-client` → **Gate OK** (exit 0; 212 tareas) y
  `:composeApp:compileKotlinWasmJs`/`jvmTest`/`detekt`/`:cpdCheck --rerun-tasks` →
  BUILD SUCCESSFUL, 0 warnings.
- Barridos propios: sin `else if`, sin `throw`/`TODO()`/`!!` en UI, sin colores
  literales fuera del tema, textos desde recursos, Material Icons, ≤30 ficheros
  (23, todos en `:composeApp`).
- Capturas: el navegador del harness está desconectado → justificación *headless*
  corroborada (`docs/pr/feat-ft00053-ui-design-refresh/README.md`).

### Ronda 2 (tras la reparación de D1)

- `:composeApp:compileKotlinWasmJs :composeApp:jvmTest :composeApp:detekt :cpdCheck --rerun-tasks`
  → BUILD SUCCESSFUL (19 tareas): **110 tests, 0 fallos**; detekt **0 hallazgos**;
  `:cpdCheck` **0 duplicaciones**.
- Cobertura de `@Preview` medida con un script propio del validador (independiente
  del usado por el implementador):

| Métrica | Ronda 1 | Ronda 2 |
| --- | --- | --- |
| Funciones `@Composable` | 192 | 209 |
| Funciones `@Preview` | 95 | **112** |
| `@Composable` sin `@Preview` que los invoque | **17** | **0** |
| `@Preview` huérfanas | 0 | 0 |
| Composables privados sin preview en el mismo fichero | — | 0 (65/65) |
| `@Preview` fuera de `commonMain` / sin tema / con color literal | — | 0 / 0 / 0 |

- Las **3 previews borradas** se restauraron con cuerpo **idéntico** al histórico
  (única diferencia: `onSuggestionClick = {}`, parámetro real nuevo de
  `ChatAnswerContent`). Las 17 nuevas/restauradas se contrastaron parámetro a
  parámetro con las firmas reales: sin desajustes.
- Diff de la reparación: **adición pura** de `@Preview` + KDoc (0 líneas borradas en
  los 4 ficheros). Las únicas supresiones del árbol son KDoc de FT00048 y la línea de
  `@file:Suppress` ampliada. Datos de ejemplo *placeholder* o ya presentes en otras
  previews del fichero.

## Hallazgos

### Ronda 1 (cerrados o aceptados como deuda)

- **D1 (Media, bloqueante)** — `@Preview` ausentes y 3 borradas. **Resuelto** en la
  ronda 2.
- **D2 (Low)** — claves i18n huérfanas `feed_filters`/`feed_category_all`
  (controles omitidos a propósito). **Deuda.**
- **D3 (Low)** — `feature_list.json` marcaba `accepted` (bookkeeping en masa del
  commit `1be16da`) mientras `docs/feature-ids.md` decía `passing`. **Resuelto**:
  estado revertido a `in_progress` al detectar el `revise`, y ahora `accepted` tras la
  ronda 2, con ambas fuentes alineadas.
- **D4 (Low)** — 5 funciones >40 líneas contando firma+parámetros (por líneas
  efectivas, máx. 38; detekt no las marca). **Deuda.**
- **D5 (Low)** — la prosa §«Colors» de `DESIGN.md` contradice su frontmatter M3.
  **Deuda.**
- **Observaciones** — `search_api_badge` = «BOE-API v2.4» es un literal fabricado
  (el contrato real es `/v1`); `SearchSortIndicator` sugiere un desplegable
  inexistente; `contentDescription` duplicado en 3 sitios (TalkBack lee dos veces).
  **Deuda.**

### Ronda 2 (nuevos)

- **O1 (Low)** — `@file:Suppress("TooManyFunctions")` en `AppChrome.kt`,
  `ChatScreen.kt` y `ChatAnswerCard.kt`: coherente con el patrón ya existente en
  `FeedScreen.kt`; las previews inflan el recuento por fichero
  (`thresholdInFiles: 15`). No viola ninguna MUST.
- **O2 (Low)** — la reparación no está commiteada; la entrega la persiste el
  orquestador.

## Seguridad

Sin hallazgos. El diff es exclusivamente de UI/textos en `:composeApp`; no toca
backend, red, contrato ni almacenamiento; sin dependencias, secretos ni telemetría.
La única URL introducida es un literal público del BOE dentro de un `@Preview`,
idéntico al fixture preexistente. `OfficialSourceUrl` copia al portapapeles la URL
oficial ya presente (sin PII) y no falla con URL vacía; se mantiene la guarda
`isHttpUrl` antes de `LocalUriHandler`.

## Estado

- **FT00053 → `accepted`** (persistido en `feature_list.json` y
  `docs/feature-ids.md`).
- El resto de features de UI de las que depende ya estaban `accepted`.
- Deuda Low pendiente (D2/D4/D5 + observaciones de a11y) para un PR menor de
  documentación/UI.
