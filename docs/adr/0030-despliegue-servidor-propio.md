# ADR 0030: Despliegue del backend en servidor propio (Docker + Nginx + HTTPS, sin cron externo)

## Estado

Aceptado (2026-10-14). Decisión del dueño del proyecto al ejecutar `deploy-backend`
(FT00041). Precisa el ADR 0004 (ingesta programada interna) y el ADR 0026
(endurecimiento HTTP); no supersede ninguno.

## Contexto

La API ya está endurecida (FT00030: CORS, rate limiting por IP y errores tipados)
pero **no había** forma de desplegarla: no existía `Dockerfile`, ni compose de
producción, ni Nginx/HTTPS. El objetivo es el **servidor propio** (Intel N100,
8 GB, sin GPU), con secretos solo por entorno y sin romper el **gate offline**
(sin Docker, red ni BD).

Dos problemas concretos:

- Tras Nginx, `call.request.origin.remoteHost` es la **IP del proxy**, así que el
  rate limiting por IP de FT00030 quedaría inservible (todos comparten cupo).
- El roadmap decía «cron», pero el ADR 0004 ya decidió un **scheduler interno** por
  corrutina (09:30 + 18:00, `Europe/Madrid`).

## Decisión

1. **Imagen del backend multi-stage** (`backend/Dockerfile`): build con JDK 21
   (`installDist -PskipClient`, sin Android SDK), runtime JRE 21, **usuario
   no-root**, sin secretos ni modelo; `EXPOSE 8080` interno. `.dockerignore`
   excluye `.harness`, `build/`, `composeApp/`, `.env*`, `backend/models/`, `docs/pr/`.
2. **Compose de producción** (`deploy/docker-compose.prod.yml`), tres servicios con
   `restart: unless-stopped` y healthchecks: `postgres` (pgvector, **solo loopback**
   `127.0.0.1:${POSTGRES_PORT}:5432`, `shared_buffers=1GB`, volumen `pgdata`),
   `backend` (**sin `ports`**, `depends_on: postgres healthy`, modelo montado `:ro`,
   `INGESTA_ENABLED=true`) y `nginx` (única entrada publicada, **puertos
   parametrizables** `HTTP_PORT`/`HTTPS_PORT`, defaults 80/443).
3. **Nginx termina TLS** (`deploy/nginx/templates/datopublico.conf.template`):
   bloque 80 para ACME + **redirect 301** a HTTPS, bloque 443 con el certificado de
   `/etc/letsencrypt/live/${DOMAIN}`, `proxy_pass http://backend:8080` con
   `X-Forwarded-For/-Proto/-Host`, `server_tokens off` y cabeceras de seguridad.
4. **Confianza de cabeceras de proxy opt-in**: plugin oficial de Ktor
   `ktor-server-forwarded-header` (`XForwardedHeaders`, `useFirstProxy()`),
   **instalado solo si `TRUST_PROXY_HEADERS=true`** (por defecto `false`). Es seguro
   porque el backend **nunca** publica puerto; con el flag ausente, desarrollo y gate
   no cambian.
5. **Secretos solo por entorno**: `deploy/.env.production` (ignorado por git, chmod
   600) con *placeholders* en `deploy/.env.production.example` (versionado);
   *fail-fast* de `POSTGRES_PASSWORD`/`OPENCODE_API_KEY`.
6. **Ingesta = scheduler interno** (ADR 0004); **no** hay cron externo.
7. **El gate sigue offline**; `docker build`/`compose`/lint de Nginx/`flywayMigrate`
   son **opt-in** (nunca en `build`/`check`/CI).
8. **Alternativas al puerto 80** documentadas: detrás de un proxy existente
   (puertos internos + `proxy_pass`) o publicar el backend directo sin Nginx
   (`deploy/docker-compose.backend-direct.yml`, solo pruebas, sin HTTPS).

## Alternativas consideradas

- **Cron externo** (systemd timer/cron del host): descartado; supersede el ADR 0004
  sin necesidad (el scheduler interno basta).
- **Publicar el backend sin confiar en cabeceras**: descartado; rompería el rate
  limiting por IP tras el proxy.
- **CORS/rate limiting en Nginx**: descartado; duplicaría FT00030.
- **Rate limiting distribuido**: descartado (una instancia).
- **Terraform/cert-manager**: descartado; el certificado se emite a mano (certbot).
- **Modelo E5 en la imagen**: descartado (~118 MB, no versionado); se monta por volumen.

## Consecuencias

- Habilita HTTPS y la operación en producción sin exponer la BD ni las claves.
- Coste asumido: emisión **manual** del certificado (HTTP-01 exige DNS/puertos
  80/443) y que la confianza de cabeceras solo es segura si el backend no publica
  puerto (garantizado en el compose).
- Documentación afectada: `ARCHITECTURE.md` (superficie de despliegue), `CONSTRAINTS.md`
  (§«Despliegue»), skill `ktor-backend-architecture`, `docs/desarrollo-local.md` y
  `README.md` (producto), `deploy/README.md` (runbook).
- Verificación: gate con `testApplication` (sin sockets) + comprobaciones manuales
  opt-in en el servidor (`deploy/verify-deploy.sh`).
