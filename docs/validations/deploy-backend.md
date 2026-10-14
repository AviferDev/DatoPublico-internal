# Validación — `deploy-backend` (FT00041)

- **Fecha:** 2026-10-14
- **Rol:** `feature-validator` (validación independiente; ejecutada vía agente `general` en el worktree)
- **Spec:** `docs/specs/deploy-backend.md`
- **Rama:** `feat/ft00041-deploy-backend` (base `origin/main` = `082245b`)
- **Diff:** 18 ficheros de producto
- **Veredicto:** **`accept`**

## Gate reejecutado (real)

| Check | Resultado |
| --- | --- |
| `build -PskipClient --no-daemon` | BUILD SUCCESSFUL |
| `test -PskipClient --rerun-tasks` | `:backend` **486/0**, `:shared` **39/0** |
| `ForwardedHeadersRouteTest` | 2/0 |
| `detekt -PskipClient` | BUILD SUCCESSFUL |
| `:backend:installDist -PskipClient` | OK (`bin/backend`) |
| `docker compose config -q` (base / puertos alternativos / override backend-direct) | exit 0 |
| `./deploy/verify-deploy.sh` | exit 0 |

`docker build` y lint de Nginx: opt-in no ejecutados (daemon Docker no disponible).

## Escenarios / MUST

- S1: postgres **loopback**, backend **sin puerto**, nginx 80/443 parametrizable,
  `INGESTA_ENABLED=true`, `restart: unless-stopped` + healthchecks.
- S2: sin credenciales versionadas; `deploy/.env.production` ignorado; la plantilla
  `.example` **sí** se versiona (negación en `.gitignore` frente al patrón global
  `.env.*`); fail-fast de secretos.
- S3: Nginx TLS + redirect 301 + `X-Forwarded-*` + cabeceras de seguridad.
- S4: `TRUST_PROXY_HEADERS` **opt-in** (default false); plugin oficial solo cuando true.
- S5: ingesta = scheduler interno (ADR 0004); sin cron externo.
- S6: volumen `pgdata` + `flywayMigrate` explícito; `V1`…`V5` intactas.
- S7: gate offline; `init.sh`/CI/`:composeApp`/migraciones intactos; única dep.
  nueva `ktor-server-forwarded-header` 3.0.3.
- Modelo E5 fuera de la imagen (volumen `:ro`). Estilo MUST conforme.

## Hallazgos

- **Low (resuelto por el orquestador):** docs durables del harness — `ARCHITECTURE.md`,
  `CONSTRAINTS.md` §«Despliegue», skill y ADR **0030**.
- **Low (resuelto):** referencia ADR del `deploy/README.md` — fijada a 0030.
- **Low (pendiente, opcional):** el `default.conf` de Nginx no se retira (un `Host`
  desconocido en :80 sirve la página de bienvenida); el dominio configurado sí
  redirige. Hardening futuro.

Sin hallazgos Critical/High/Medium. Sin secretos versionados.
