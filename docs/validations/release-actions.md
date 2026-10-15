# Validación — `release-actions` (FT00052)

## FT00052-PT1 — Backend (imagen a GHCR + despliegue por SSH)

- **Rama**: `feat/ft00052-pt1-backend-release` (PR #44) · base `origin/main` `34b49fc`.
- **Spec**: `docs/specs/release-actions.md` (§PT1).
- **Validador**: `feature-validator` (independiente del implementador).

### Rondas

| Ronda | Veredicto | Motivo |
| --- | --- | --- |
| 1 | `revise` | **High**: el job `backend` del *umbrella* `release.yml` no concedía `packages: write` (un workflow reutilizable solo puede *degradar* los permisos del caller → el disparo manual no publicaría en GHCR). **Medium**: `docs/feature-ids.md` desalineado. **Low**: ADR 0034 declaraba actualizada una skill sin tocar; faltaba la nota de `BACKEND_IMAGE` en `deploy/README.md`. |
| 2 | **`accept`** | Reparado en producto `3e06470` y harness `07a93f9`. Sin bloqueantes. |

### Checks reejecutados (ronda 2)

- `./gradlew build -PskipClient` → BUILD SUCCESSFUL.
- `./gradlew test -PskipClient --rerun-tasks` → `:shared` 39/0, `:backend` 486/0.
- `./gradlew detekt` → BUILD SUCCESSFUL.
- `.harness/init.sh` → Gate OK (exit 0); `ci.yml`/`init.sh` intactos.
- Parseo YAML de `release.yml`/`release-backend.yml`/`action.yml`; `bash -n scripts/release/deploy-backend.sh`; `docker compose -f deploy/docker-compose.prod.yml --env-file deploy/.env.production.example config -q` → OK.
- Alcance: solo PT1 (sin `release-web/android/ios.yml`); triggers `workflow_dispatch`/`workflow_call`/`push: tags: v*`; `cancel-in-progress: false`; `packages: write` acotado; sin secretos versionados.

### Estado

- **FT00052-PT1 → `accepted`** (persistido en `feature_list.json` y `docs/feature-ids.md`).
- `release-actions` sigue **`in_progress`**: PT2 (Web), PT3 (Android) y PT4 (iOS) pendientes y bloqueadas por FT00039/FT00038/FT00040.

### Notas no bloqueantes (deuda futura)

- Acciones de terceros *pinned* por tag mayor (`appleboy/ssh-action@v1`, `actions/*@v5`), consistente con `ci.yml`; el *pinning* por SHA sería una mejora.
- `secrets: inherit` pasa todos los secretos al callee (solo consume `SSH_*`); un mapeo explícito sería más auditable.
