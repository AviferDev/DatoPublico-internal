# Validación — `dev-up-local` (FT00050)

- **Rama**: `feat/ft00050-dev-up-local` (PR #43) · fusionada en `main` como
  `5cae1a7`; las reparaciones de las rondas 2–3 viven en el árbol de trabajo de
  cierre.
- **Spec**: `docs/specs/dev-up-local.md` (**retroactivo**, creado en la ronda 2 para
  cerrar la gobernanza de una feature entregada sin spec).
- **Validador**: `feature-validator` (independiente del implementador).
- **Fecha**: 2026-10-18.

## Veredicto

**`accept`** (ronda 3).

| Ronda | Veredicto | Motivo |
| --- | --- | --- |
| 1 | `revise` | **H1 (High, gobernanza)**: sin spec ni registro de validación. **H2 (Medium)**: `dev-up.sh` no documentado en `docs/desarrollo-local.md`, que es la doc que el propio script cita. **H3 (Medium)**: `wait_for_health` aceptaba cualquier `200` y podía reportar **éxito en falso**. **H4–H7 (Low)**. |
| 2 | `revise` | H1/H2/H3 **resueltos y verificados** (banco aislado 14 PASS/0 FAIL, gate verde); el único hallazgo fue que el **spec retroactivo** había quedado desalineado con la reparación. |
| 3 | **`accept`** | Spec alineado; sin cambios de código ni docs de producto. |

## Checks reejecutados

### Ronda 1

- `bash -n scripts/dev-up.sh` → OK; `--help` → OK (imprime `set -euo pipefail`:
  deuda H6 conocida); argumento inválido → exit 2; sin `docker` en `PATH` →
  `docker: command not found`, exit 127, sin tocar contenedores.
- `docker compose config -q` → OK; `docker compose version` → v5.6.0 con `--wait` y
  `--wait-timeout`.
- Filtro de stacks hermanos: réplica *read-only* + `docker ps` → `vuelantis`
  (10 contenedores) y `boe-rag` **no se tocan**; el único proyecto del repo se salta
  el `down`.
- Coherencia con `docker-compose.yml` (`container_name`, `127.0.0.1:${POSTGRES_PORT:-5432}`,
  healthcheck `pg_isready`), con la tarea `:backend:flywayMigrate` y con el
  `mainClass` de `:backend:run`; layout del modelo E5 coincidente con
  `EmbeddingConfig`.
- `build -PskipClient` → BUILD SUCCESSFUL.
- **No ejecutado**: el script completo (levantaría contenedores y bajaría stacks
  Compose hermanos; el 8080 estaba ocupado por un túnel SSH). Declarado.

### Rondas 2–3

- Ronda 2: banco aislado propio del validador (funciones **extraídas** del script
  real, con `localhost:8080`→puerto efímero y bucle acortado): **14 PASS / 0 FAIL** —
  `backend_is_ours` acepta solo cuerpo `{"status":"ok"}` **y** `/openapi.json` 200;
  `wait_for_health` con PID muerto → `ERROR` en stderr y RC≠0; con `set -euo pipefail`
  el fallo propaga y el heredoc «Listo» **no** se imprime. Contraste: la comprobación
  **vieja** (solo `curl /health` 200) **sí** aceptaba el 200 ajeno → confirma que H3
  era real.
- Ronda 2: `build -PskipClient` → BUILD SUCCESSFUL; `./init.sh` → Gate OK (exit 0),
  `init.sh` sin cambios; diff con 3 hunks, todos en `wait_for_health`/`start_backend`
  (filtro de stacks, flags y orden de fases intactos).
- Ronda 3: `bash -n` OK; gate verde (23 tareas); greps de afirmaciones falsas en el
  spec → **0 coincidencias**; banco aislado reconstruido (6 casos) → misma propiedad;
  `mtime` confirma que no se tocó código ni docs de producto.

## Hallazgos

- **H1 (High, gobernanza)** — Sin spec ni registro de validación. **Resuelto** con el
  spec retroactivo (ronda 2).
- **H2 (Medium)** — `dev-up.sh` sin documentar. **Resuelto**: sección «Arranque del
  entorno de desarrollo (`scripts/dev-up.sh`)» en `docs/desarrollo-local.md` y mención
  en `ARCHITECTURE.md` §«Build y gate».
- **H3 (Medium)** — Falso éxito en el arranque. **Resuelto**: `backend_process_alive` +
  `backend_is_ours` (cuerpo exacto + `/openapi.json`), timeout → exit ≠ 0 con `ERROR`,
  «Listo» inalcanzable tras fallo.
- **Spec desalineado (Medium, ronda 2)** — Describía el script anterior y excluía H3
  del contrato. **Resuelto** (ronda 3): plegado en `Goal`/`Scenario 1`/`Technical
  Approach`, nuevo `Scenario 8`, `Durable Documentation Impact` con la doc marcada como
  hecha, `Risks` resueltos y `status` alineado.
- **H4 (Low)** — Sin guarda de `docker`/Colima: falla rápido pero con mensaje opaco.
  **Deuda.**
- **H5 (Low)** — `current_project` se calcula antes de cargar `.env` (latente; hoy
  ninguna `.env` define `COMPOSE_PROJECT_NAME`). **Deuda.**
- **H6 (Low)** — `--help` imprime `set -euo pipefail` (`sed -n '2,33p'`). **Deuda.**
- **H7 (Low)** — `stop_backend` mata cualquier backend del repo, incluso de otra sesión
  o puerto. **Deuda** (perfil operativo: conviene pidfile propio o documentarlo).
- **Puerto 8080 no parametrizable (Low)** — desde la reparación el conflicto se
  **detecta y reporta**, pero el puerto sigue fijo. **Deuda.**
- **Nota (Info)** — `docs/pantallas-frontend.md` sin versionar (ajeno a la feature).

## Seguridad

Sin hallazgos bloqueantes. El diff no versiona secretos (`.env` ignorado; el script
solo imprime **nombres** de claves, nunca valores); solo consulta `localhost`; y el
health-check endurecido **reduce** el riesgo de confundir un servicio local ajeno (p.
ej. un túnel SSH en el 8080) con el backend propio. Nota preexistente no bloqueante:
`set -a; . ./.env` ejecuta el contenido del `.env` local (confiable y no versionado).

## Estado

- **FT00050 → `accepted`** (persistido en `feature_list.json` y
  `docs/feature-ids.md`).
- Deuda Low pendiente: H4–H7 y la parametrización del puerto 8080.
