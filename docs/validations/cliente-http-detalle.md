# Validación — `cliente-http-detalle` (FT00048)

- **Rama**: `feat/ft00048-cliente-http-detalle` (PR #41) · fusionada en `main` como
  `21f7299`; la reparación de las rondas 2–3 vive en el árbol de trabajo de cierre.
- **Spec**: `docs/specs/cliente-http-detalle.md` (**retroactivo**, creado en la
  ronda 2 para cerrar la gobernanza de una feature entregada sin spec).
- **Validador**: `feature-validator` (independiente del implementador).
- **Fecha**: 2026-10-18.

## Veredicto

**`accept`** (ronda 3).

| Ronda | Veredicto | Motivo |
| --- | --- | --- |
| 1 | `revise` | **G1 (Medium, gobernanza)**: sin spec ni artefacto de validación. **M1 (Medium)**: el KDoc de `app/App.kt` decía que el detalle «lee de un repositorio en memoria (su cliente HTTP es una feature posterior)». **M2 (Medium)**: `ARCHITECTURE.md` no mencionaba `HttpDetailRepository`. **L1–L3 (Low)**. |
| 2 | `revise` | G1/M1/M2 **resueltos**; único hallazgo abierto: **D1 (Medium)** — `docs/desarrollo-local.md` seguía afirmando lo contrario del comportamiento entregado, incumpliendo la sección `Durable Documentation Impact` del propio spec. |
| 3 | **`accept`** | D1 cerrado; sin cambios de código ni tests; gate verde. |

## Checks reejecutados

### Ronda 1

- `:composeApp:jvmTest --rerun-tasks` → **110 tests, 0 fallos**;
  `HttpDetailRepositoryTest` **5/5** (`200`→contenido, `404`→`NotFound`,
  `500`→`Failure`, red→`Failure`, y el `id` viaja en la ruta
  `http://api.test/v1/publicacion/BOE-A-2026-21321`).
- `:composeApp:detekt` y `:cpdCheck` → verdes.
- Contrato con el backend (FT00027) verificado por lectura: ruta, forma del JSON,
  nullabilidad, `@SerialName` explícito y sufijo `Dto`, cableado en
  `App`/`AppNavHost`, y errores sin crash.

### Rondas 2–3

- Ronda 2: gate reejecutado en verde (110 tests, 0 fallos; detekt + `:cpdCheck`).
- Ronda 3: `:composeApp:jvmTest`/`detekt`/`:cpdCheck` → verde
  (`HttpDetailRepositoryTest` 5/5, `DetailStateHolderTest` 7/7,
  `InMemoryDetailRepositoryTest` 6/6). Comprobaciones documentales propias:
  `grep "feature posterior" docs/` → **0 coincidencias**; `v1/publicacion` presente
  en la sección del cliente; fidelidad contrastada contra `app/App.kt`,
  `app/AppNavHost.kt` y `feature/detail/data/`.
- Alcance de la entrega original: **7 ficheros** (los que declara el spec), sin tocar
  `:shared`, `:backend`, CI, `init.sh` ni `DESIGN.md`.

**No reproducido en ningún entorno**: la verificación «en el emulador» del
`feature_list.json` (sin emulador ni backend con datos); evidencia sustituta: los 5
tests con `MockEngine` + la comprobación en Web de `PROGRESS.md` (Session 083).

## Hallazgos

- **G1 (Medium, gobernanza)** — Sin spec ni artefacto de validación: la feature se
  fusionó sin pasar por `planner→implementer→validator`. **Resuelto** con el spec
  retroactivo `docs/specs/cliente-http-detalle.md` (ronda 2), que describe fielmente
  el código entregado (verificado en la ronda 3).
- **M1 (Medium)** — KDoc de `app/App.kt` contrario al comportamiento. **Resuelto**
  (ronda 2).
- **M2 (Medium)** — `ARCHITECTURE.md` sin `HttpDetailRepository`. **Resuelto**
  (ronda 2).
- **D1 (Medium)** — `docs/desarrollo-local.md` afirmaba que el detalle usa un
  repositorio en memoria y que el HTTP «será una feature posterior». **Resuelto**
  (ronda 3), como exige la sección `Durable Documentation Impact` del spec.
- **L1/L2 (Low)** — KDoc de `DetailApi`/`HttpDetailRepository`/`DetailRepository`/
  `InMemoryDetailRepository`/`DetailModels`/mapper/DTO que aún citan **FT00035** en
  vez de FT00048, y descripciones prospectivas ya obsoletas. **Deuda** (el
  comportamiento que describen es correcto).
- **L3 (Low)** — Verificación en emulador no reproducible. **Deuda.**
- **Nota (Low)** — `id` concatenado en la URL sin codificar; riesgo bajo (procede de
  la navegación interna y el backend valida longitud); a revisar si FT00039-PT2
  expone *deep links*.
- **Nota (Info)** — `docs/adr/0028` afirma que «FT00035 reemplazará
  `InMemoryDetailRepository` por HTTP»; lo hizo FT00048. Los ADR son registros
  puntuales y el spec los marca como *not needed*.

## Seguridad

Sin hallazgos bloqueantes (rondas 1–3). Sin secretos en el diff; endpoint público de
solo lectura, sin cuentas ni authz; el `id` procede de navegación interna y el backend
valida la entrada; solo datos públicos del BOE (sin PII); sin dependencias nuevas;
reutiliza el `HttpClient` común con `HttpTimeout` acotado.

## Estado

- **FT00048 → `accepted`** (persistido en `feature_list.json` y
  `docs/feature-ids.md`).
- Deuda Low pendiente: L1/L2 (KDoc con FT00035), L3 y la nota de la URL.
