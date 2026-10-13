# Feature Implementation Spec: Despliegue del backend en servidor propio

## Source Feature

- `id`: deploy-backend
- `ft_id`: FT00041 (registrado en `docs/feature-ids.md`)
- `parts`: none (atómica; ≈17 ficheros de producto, por debajo del límite de 30)
- `area`: operacion
- `depends_on`: api-contratos-openapi (FT00029, `accepted`) + api-cors-ratelimit-errores
  (FT00030, `accepted`). **Se recomienda añadir** `bootstrap-postgres-pgvector`
  (FT00003), `bootstrap-ktor-healthcheck` (FT00004), `ingesta-job-diario` (FT00009) y
  `embeddings-locales-onnx` (FT00015): ver *Dependencias*.
- `status`: not_started (al planificar)
- `source`: `feature_list.json` (`notes`: `docs/roadmap.md` 0.7-T04 y 0.10-T04)
- `claim`: rama `feat/ft00041-deploy-backend` ya reclamada en `origin`
  (`8c4efa07…`). El planner no edita ramas ni `feature_list.json`.

> **Dependencias.** Las dos features de `depends_on` están `accepted` y en `main`.
> Esta feature **extiende** `docker-compose.yml`/Flyway (FT00003), usa el `/health`
> del esqueleto Ktor (FT00004), habilita el **scheduler interno** de la ingesta
> (FT00009) y monta el **modelo E5** (FT00015); por eso se recomienda al
> **orquestador** añadirlas a `depends_on`. No se añaden las features de API/UI:
> quedan cubiertas transitivamente y no se tocan.

## Goal

Desplegar el backend y PostgreSQL/pgvector en el **servidor propio** (Intel N100,
8 GB) con **Docker Compose + Nginx**, **HTTPS**, la **ingesta diaria con segunda
pasada** en marcha y **secretos solo por entorno**, sin versionar credenciales.

El resultado es un **runbook reproducible** (`deploy/`), una **imagen de backend
multi-stage** (`-PskipClient`, sin Android SDK), un **compose de producción**
(PostgreSQL en loopback, backend no publicado, Nginx como única entrada) y el
**endurecimiento** que faltaba tras FT00030: **terminación TLS** en Nginx y
**confianza de cabeceras de proxy** (opt-in) para que el rate limiting por IP siga
funcionando detrás del proxy. El **gate estándar no cambia**: sigue offline, sin
Docker, sin red y sin BD.

## Non-Goals

- **Cron externo** (`systemd timer`, `cron` del host, CronJob): la ingesta es un
  **scheduler interno por corrutina** (ADR 0004). Esta feature **habilita** ese
  scheduler (`INGESTA_ENABLED=true` + `restart: unless-stopped`), no añade cron.
- **Backups y observabilidad de producción** (retención, alertas externas,
  métricas): FT00042. Aquí solo el `healthcheck` de Compose y los logs JSON.
- **Web (Wasm) / Android / iOS**: FT00038–FT00040 y la UI (FT00032+).
- **Certificados y DNS gestionados por código** (Terraform, cert-manager): el
  certificado TLS se emite **a mano** (Let's Encrypt/certbot) en el servidor.
- **Cambiar el pipeline de resumen, el indexado del corpus o los endpoints**: gaps
  de planificación ya registrados (Sessions 068/070); aquí no se cablean.
- **Autenticación, cuentas, panel de administración, Swagger UI**.
- **Añadir migraciones** (`V1`…`V5` intactas) ni tocar `:composeApp`, la CI o
  `.harness/init.sh`.
- **Rate limiting distribuido** (sigue en memoria, por instancia).

## Job Story

When preparo el servidor propio para la 1.0.0,
I want desplegar backend y base de datos con Docker y Nginx, servir por HTTPS,
dejar la ingesta programada en marcha y mantener los secretos fuera del repositorio,
so I can operar el producto en producción sin exponer la base ni las claves, y sin
que el gate de desarrollo dependa de infraestructura.

## Users And Permissions

- **Operador (dueño del proyecto):** único actor. Instala Docker, emite el
  certificado, crea `deploy/.env.production` (no versionado), aplica migraciones,
  levanta/para el stack y observa los logs. Sin cuentas ni roles.
- **Ciudadanía (usuario final):** solo lectura por HTTPS; nunca accede a PostgreSQL
  ni al backend directamente (solo a través de Nginx).
- **Nginx:** única superficie publicada (80/443); termina TLS y hace de proxy.
- **Backend:** habla con PostgreSQL por la red interna de Compose; **no** publica
  puerto al host.

## Acceptance Scenarios

### Scenario 1: el stack de producción valida sin arrancarlo

Given el repo con Docker instalado (sin servidor real, sin red y sin BD),
When se ejecuta `docker compose -f deploy/docker-compose.prod.yml --env-file
deploy/.env.production.example config`,
Then la configuración resuelve sin errores; PostgreSQL se publica **solo en
loopback** (`127.0.0.1:${POSTGRES_PORT}:5432`); el backend **no** publica puertos;
`INGESTA_ENABLED=true`; y ningún valor obligatorio falta.

### Scenario 2: secretos fuera del repositorio y fail-fast

Given un checkout limpio,
When se revisan los ficheros versionados (`git grep`) y se intenta arrancar el stack
sin `POSTGRES_PASSWORD` (o el chat sin `OPENCODE_API_KEY`),
Then no aparece ninguna credencial real (solo *placeholders* en
`deploy/.env.production.example`), `deploy/.env.production` está **ignorado por git**
y el arranque **falla con mensaje claro** en lugar de usar un valor por defecto.

### Scenario 3: HTTPS en Nginx y proxy al backend

Given Nginx con certificado TLS del dominio y el backend `healthy`,
When un cliente pide `https://<dominio>/health`,
Then Nginx termina TLS y hace proxy a `backend:8080`, devolviendo
`{"status":"ok"}`; una petición por HTTP se **redirige** a HTTPS; y las cabeceras
`X-Forwarded-For`/`X-Forwarded-Proto`/`X-Forwarded-Host` llegan al backend.

### Scenario 4: el rate limiting ve la IP real detrás del proxy

Given `TRUST_PROXY_HEADERS=true` y el backend detrás de Nginx,
When dos clientes con IPs distintas llegan con distinto `X-Forwarded-For`,
Then el *rate limiter* (FT00030) usa la **IP del cliente**, no la del proxy; con el
flag **ausente/false** el plugin no se instala (desarrollo y gate **sin** cambios).

### Scenario 5: ingesta diaria y segunda pasada

Given el backend en marcha con `INGESTA_ENABLED=true` y el esquema migrado,
When llega la ventana de las **09:30** (y la **segunda pasada** de las 18:00),
Then el job se ejecuta y registra `ingestion.run.completed`; reejecutar la misma
fecha **no duplica** (*upsert* por `id`); y el contenedor vuelve solo tras un reinicio
(`restart: unless-stopped`). **No** hay cron externo (ADR 0004).

### Scenario 6: migraciones y persistencia

Given PostgreSQL arriba (loopback) y el operador ejecuta
`./gradlew :backend:flywayMigrate` (y `flywayInfo`),
Then el esquema queda aplicado y los datos **persisten** entre reinicios del stack
(volumen nombrado `pgdata`).

### Scenario 7: el gate sigue offline

Given el runner de CI **sin** Docker, sin PostgreSQL, sin red y sin secretos,
When se ejecutan `./gradlew build -PskipClient`, `./gradlew test`, `./gradlew detekt`
y `.harness/init.sh`,
Then todo está en verde; **ningún** script de despliegue se engancha al gate; el
único test nuevo (`ForwardedHeadersRouteTest`) usa `testApplication` y **no abre
sockets**.

## Repository Research

### Files Inspected

- Checkout de producto en la raíz del workspace (rama `feat/ft00032-ui-feed`, que
  incluye `main` con FT00029/FT00030): los ficheros relevantes para el despliegue
  (`docker-compose.yml`, `.env.example`, `backend/build.gradle.kts`, `README.md`,
  CI, `init.sh`) son **idénticos a `origin/main`** (verificado con `git diff
  --stat origin/main HEAD`). El *worktree* `/…/DatoPublico-wt/ft00041` queda fuera
  del sandbox del planner; se planifica contra el estado de `main`.
- `docker-compose.yml` — compose **de desarrollo** actual: solo `postgres`
  (`pgvector/pgvector:pg17`), `POSTGRES_PASSWORD:?` fail-fast, puerto **loopback**
  y volumen `pgdata`. **No** hay servicio `backend` ni `Dockerfile`.
- `.env.example` — plantilla de desarrollo (`POSTGRES_*`, overrides `FLYWAY_*`),
  solo *placeholders*.
- `backend/build.gradle.kts` — plugin `application` (`mainClass`
  `…backend.ApplicationKt`), tareas `flywayMigrate`/`flywayInfo` (fail-fast sin
  contraseña) y las one-shot `backfill`/`evaluateRetrieval`/`evaluateSummary` (fuera
  de `build`/`check`).
- `settings.gradle.kts` — `include(":shared", ":backend")` y `:composeApp` **solo**
  sin `-PskipClient` (la imagen del backend lo usa).
- `backend/src/main/kotlin/…/backend/Application.kt` — composition root: pool JDBC
  único, wiring condicional (embeddings/OpenCode/ingesta) y los plugins de FT00030;
  punto donde se instalarían las cabeceras de proxy.
- `backend/src/main/kotlin/…/backend/infra/HttpHardeningConfig.kt` — `CorsSettings`
  y `RateLimitSettings` con `fromEnv`/`default` y *fail-fast* (patrón a seguir para
  el flag de proxy).
- `backend/src/main/kotlin/…/backend/ingesta/job/IngestionConfig.kt` + `Application.kt`
  — scheduler interno `09:30`+`18:00` (`Europe/Madrid`), condicional a
  `INGESTA_ENABLED` y a la config de BD.
- `backend/tools/download-embedding-model.sh` — aprovisiona `backend/models/`
  (ignorado por git); el modelo se monta por volumen, **nunca** va en la imagen.
- `.gitignore` — ya ignora `.env`, `backend/models/`, `build/`; **no** ignora
  `deploy/.env.production`.
- `.github/workflows/ci.yml` — CI `ubuntu-latest` + JDK 21 + `./gradlew build`
  (sin BD/Docker explícito).
- `.harness/init.sh` — gate SDK-free (`build -PskipClient` + `detekt`); **no arranca
  servidores**; el spec lo deja **sin cambios**.
- `docs/desarrollo-local.md` — guía local (compose dev, Flyway, ingesta, chat…);
  punto de entrada de la sección de despliegue.
- Harness: `feature_list.json` (FT00041), `docs/roadmap.md` §0.7 (`0.7-T04`) y
  §0.10 (`0.10-T04`), `docs/technical-discovery.md` §«Deployment and Operations»,
  `docs/risks-and-open-questions.md`, `CONSTRAINTS.md` §«Operación», ADR **0004**
  (ingesta interna), ADR **0026** (endurecimiento HTTP) y skill
  `ktor-backend-architecture` (§«Docker y entorno local»).

### Existing Patterns To Follow

- **Configuración por entorno con `fromEnv(env)` y *fail-fast*** en `infra/`
  (`AppConfig`, `EmbeddingConfig`, `OpenCodeConfig`, `HttpHardeningConfig`).
- **Compose con `POSTGRES_PASSWORD:?`** (fail-fast) y PostgreSQL **solo loopback**.
- **Secretos solo por entorno**, jamás en código/compose/CI/plantillas (MUST de
  `CONSTRAINTS.md`).
- **El gate no arranca servidores ni depende de servicios externos**; las tareas
  pesadas (Flyway, backfill, evaluaciones) son **explícitas/opt-in**.
- **Plugin oficial de Ktor** como dependencia nueva, justificada y documentada
  (precedente FT00030/ADR 0026).
- **Identificadores en inglés, KDoc en castellano**; un solo `return`, sin `else if`,
  funciones ≤40 líneas.
- **ADR para decisiones durables** (despliegue, seguridad).

### Current Gaps

- **No existe** `Dockerfile` del backend ni `.dockerignore`.
- **No existe** compose de producción ni servicio `backend`/`nginx` (solo el
  `postgres` de desarrollo).
- **No hay** Nginx, TLS ni cabeceras de proxy: el rate limiting por IP de FT00030
  vería la **IP del proxy** (todos los clientes comparten cupo).
- **No hay** plantilla de entorno de producción (`deploy/.env.production.example`)
  ni `.gitignore` para `deploy/.env.production`.
- **No hay** runbook de despliegue ni script de verificación offline.

## Technical Approach

Deriva de `docs/roadmap.md` 0.7-T04/0.10-T04, `docs/technical-discovery.md`
(§«Deployment and Operations»), ADR 0004 y `CONSTRAINTS.md`. Decisión durable en un
**ADR 0028**.

### Reconciliación con el «cron» (decisión clave)

`feature_list.json`/roadmap dicen «cron»; **ADR 0004 ya decidió un scheduler
interno por corrutina** (09:30 + 18:00, `Europe/Madrid`) sin cron externo. Esta
feature **no añade cron**: habilita el scheduler (`INGESTA_ENABLED=true`) y hace
que el contenedor se reinicie solo (`restart: unless-stopped`). Si el dueño quiere
un cron externo, sería un ADR nuevo que **supersede** el 0004 (ver *Risks*).

### Cabeceras de proxy (el único cambio de código)

FT00030 dejó explícito que la confianza de `X-Forwarded-*` era **FT00041**. Sin
ella, tras Nginx `call.request.origin.remoteHost` es la IP del proxy y el rate
limiting queda inservible. Se instala el plugin **oficial** de Ktor
`XForwardedHeaders` (`io.ktor:ktor-server-forwarded-header`, **verificado en Maven
Central a la versión fijada 3.0.3**), **condicionado** por `TRUST_PROXY_HEADERS`
(por defecto **false**), de modo que desarrollo y gate no cambian. Se usa la
política por defecto `useFirstProxy()` (Nginx añade la IP del cliente al **frente**
de `X-Forwarded-For`). El backend **nunca** publica puerto: solo Nginx lo alcanza.

### 1. Imagen del backend (`backend/Dockerfile` + `.dockerignore`, create)

- **Multi-stage**: stage *build* con JDK 21 (Temurin) ejecuta
  `./gradlew :backend:installDist -PskipClient --no-daemon`; stage *runtime* con
  JRE 21 copia `backend/build/install/backend` y arranca el *launcher*.
- **Sin secretos ni modelo** en la imagen; usuario no-root; `EXPOSE 8080` (interno).
- `.dockerignore` en la raíz excluye `.harness`, `.git`, `build/`, `**/build/`,
  `.gradle`, `.kotlin`, `composeApp/`, `local.properties`, `.env*`,
  `backend/models/` y `docs/pr/`.
- `-PskipClient` evita el Android SDK (ya previsto en `settings.gradle.kts`).

### 2. Compose de producción (`deploy/docker-compose.prod.yml`, create)

Tres servicios en una red interna, con `restart: unless-stopped`:

- **`postgres`**: `pgvector/pgvector:pg17`; `environment` desde `--env-file`;
  `ports: ["127.0.0.1:${POSTGRES_PORT:-5432}:5432"]` (**solo loopback**, para que el
  host aplique Flyway); `command` con `-c shared_buffers=1GB` (N100); volumen
  `pgdata`; `healthcheck` `pg_isready`.
- **`backend`**: `build: { context: .., dockerfile: backend/Dockerfile }`;
  `depends_on: postgres (service_healthy)`; `environment` (interpolado con
  `${VAR}`): `POSTGRES_HOST=postgres`, `INGESTA_ENABLED=true`, `TRUST_PROXY_HEADERS`,
  `EMBEDDING_MODEL_PATH=/models/multilingual-e5-small/model.onnx`, `APP_ENV`,
  `LOG_LEVEL`, `JAVA_TOOL_OPTIONS=-Xmx1g`, CORS/rate limit y claves de OpenCode;
  volumen de solo lectura del modelo (`${EMBEDDING_MODEL_HOST_DIR:-../backend/models}:/models:ro`);
  **sin** `ports`; `healthcheck` HTTP a `/health`.
- **`nginx`**: imagen fijada (`nginx:1.27-alpine`); `ports: ["80:80","443:443"]`;
  `volumes` con `./nginx/templates` y `/etc/letsencrypt:ro`; `depends_on: backend`.

Se usa **`environment:` interpolado + `--env-file`** (no `env_file`) para que
`docker compose config --env-file deploy/.env.production.example` valide **sin** el
fichero real y sin *daemon*.

### 3. Nginx con HTTPS (`deploy/nginx/templates/datopublico.conf.template`, create)

- Plantilla de la imagen oficial de Nginx (`envsubst` al arrancar) con `${DOMAIN}`:
  bloque **80** para el *challenge* ACME y **redirect 301 a HTTPS**; bloque **443**
  con `ssl_certificate`/`ssl_certificate_key` de `/etc/letsencrypt/live/${DOMAIN}/`.
- `proxy_pass http://backend:8080`; `proxy_set_header Host/X-Real-IP/X-Forwarded-For
  ($proxy_add_x_forwarded_for)/X-Forwarded-Proto ($scheme)/X-Forwarded-Host`;
  `proxy_http_version 1.1`; `client_max_body_size` acotado; `server_tokens off` y
  cabeceras de seguridad (`X-Content-Type-Options`, `X-Frame-Options`, HSTS).

### 4. Entorno y secretos (`deploy/.env.production.example`, create; `.gitignore`, modify)

- Plantilla con **solo *placeholders***: `POSTGRES_*` (`POSTGRES_PASSWORD` sin valor
  real), `OPENCODE_*`, `EMBEDDING_MODEL_PATH`/`_TOKENIZER_PATH`, `CORS_ALLOWED_ORIGINS`,
  `RATE_LIMIT_*`/`CHAT_RATE_LIMIT_*`, `INGESTA_*`, `TRUST_PROXY_HEADERS=true`,
  `DOMAIN`, `APP_ENV=production`, `LOG_LEVEL`, `JAVA_TOOL_OPTIONS`,
  `EMBEDDING_MODEL_HOST_DIR`.
- `.gitignore`: ignorar `deploy/.env.production` (la plantilla `.example` **sí** se
  versiona), manteniendo el patrón actual de `.env`.

### 5. Cabeceras de proxy (`infra/HttpHardeningConfig.kt`, `plugins/ForwardedHeaders.kt`,
`Application.kt`; modificar/crear)

- `ProxySettings(trustProxyHeaders: Boolean)` con `default()` (false) y
  `fromEnv(env)` (*fail-fast* si el valor no es booleano), en `infra/`.
- `fun Application.configureForwardedHeaders(settings: ProxySettings)`: si
  `trustProxyHeaders`, `install(XForwardedHeaders) { useFirstProxy() }`; si no, no
  instala nada. Se llama desde `Application.module()` tras `configureMonitoring()`.
- Dependencia nueva `ktor-server-forwarded-header` en `libs.versions.toml` +
  `backend/build.gradle.kts` (oficial, versión fijada 3.0.3).

### 6. Runbook y verificación offline (`deploy/README.md`, `deploy/verify-deploy.sh`; create)

- `deploy/README.md`: pasos manuales del servidor (Docker, DNS, `certbot`,
  `deploy/.env.production` con permisos restringidos, `up -d postgres` →
  `./gradlew :backend:flywayMigrate` → `up -d`, comprobación HTTPS, observación de la
  ingesta y *rollback*).
- `deploy/verify-deploy.sh` (**opt-in**, no lo llama el gate): valida
  `docker compose config` con la plantilla, hace *lint* de la config de Nginx (si hay
  Docker/nginx), y comprueba **estáticamente** que no hay secretos versionados y que
  `deploy/.env.production` está ignorado. Omite con mensaje claro si falta Docker.

### Sin anticipar lo diferido

Sin cron externo, sin backups/alertas (FT00042), sin certificados por código, sin
tocar migraciones, `:composeApp`, la CI, `init.sh`, `rag/*`, `persistence/*` ni los
endpoints.

## Expected File Changes

Rutas en el repo de producto (`..`); `es/aviferdev/datopublico/backend` se abrevia
`…`:

- `backend/Dockerfile` — create; imagen multi-stage (`installDist -PskipClient`).
- `.dockerignore` — create; contexto de build pequeño y sin secretos.
- `deploy/docker-compose.prod.yml` — create; `postgres` + `backend` + `nginx`.
- `deploy/nginx/templates/datopublico.conf.template` — create; TLS, redirect y proxy.
- `deploy/.env.production.example` — create; *placeholders* de entorno de producción.
- `deploy/README.md` — create; runbook del servidor.
- `deploy/verify-deploy.sh` — create; verificación offline opt-in.
- `.gitignore` — modify; ignorar `deploy/.env.production`.
- `gradle/libs.versions.toml` — modify; `ktor-server-forwarded-header`.
- `backend/build.gradle.kts` — modify; cablear la dependencia.
- `backend/src/main/kotlin/…/backend/infra/HttpHardeningConfig.kt` — modify;
  `ProxySettings`.
- `backend/src/main/kotlin/…/backend/plugins/ForwardedHeaders.kt` — create;
  `configureForwardedHeaders(settings)`.
- `backend/src/main/kotlin/…/backend/Application.kt` — modify; instalar el plugin
  condicional.
- `backend/src/test/kotlin/…/backend/plugins/ForwardedHeadersRouteTest.kt` — create;
  IP de cliente desde `X-Forwarded-For` (y no instalado por defecto).
- `backend/src/test/kotlin/…/backend/infra/HttpHardeningConfigTest.kt` — modify;
  parseo y *fail-fast* de `TRUST_PROXY_HEADERS`.
- `docs/desarrollo-local.md` (producto) — modify; sección de despliegue y puntero a
  `deploy/README.md`.
- `README.md` (producto) — modify; enlace a `deploy/README.md`.

Harness (privado): `ARCHITECTURE.md`, `CONSTRAINTS.md` (nueva sección),
ADR `0028` + índice, skill `ktor-backend-architecture`, `PROGRESS.md` y
`feature_list.json` (los cierra el orquestador).

Total ≈ **17 ficheros de producto**: por debajo del límite de 30 → **no** requiere
división en partes `FT00041-PTn`.

## Visual Design Impact

- UI involved: no. Sin pantallas, tokens ni textos.
- Design source: no aplica (`DESIGN.md` no se toca).
- Screens or states affected: ninguno.
- New design artifact required: no.

## Durable Documentation Impact

- `ARCHITECTURE.md`: **update** — nueva superficie de **despliegue** (imagen del
  backend, compose de producción, Nginx/HTTPS, secretos por entorno, volumen del
  modelo) y **confianza de cabeceras de proxy** (opt-in) en la frontera HTTP.
- `CONSTRAINTS.md`: **update** — nueva sección **«Despliegue»**: secretos solo por
  entorno y nunca versionados (fail-fast si faltan); PostgreSQL de producción en
  **loopback**; backend **sin** puerto publicado (solo Nginx); HTTPS obligatorio; el
  gate **no** arranca servidores ni depende de Docker/red/BD; `TRUST_PROXY_HEADERS`
  opt-in; el scheduler interno (ADR 0004) es el **único** cron.
- `AGENTS.md`: **not needed** — el flujo, el arranque y las reglas de trabajo no
  cambian (el gate sigue igual).
- Other docs: `docs/adr/0028-despliegue-servidor-propio.md` — **create** (Docker +
  Nginx + HTTPS + secretos + cabeceras de proxy + sin cron externo) + índice
  `docs/adr/README.md`; `.agents/skills/ktor-backend-architecture/SKILL.md` —
  **update** (§«Docker y entorno local»: despliegue de producción y cabeceras de
  proxy); `docs/desarrollo-local.md` — **update**; `deploy/README.md` — **create**.

## Implementation Plan

1. Crear `backend/Dockerfile` y `.dockerignore`; verificar `installDist
   -PskipClient` en local.
2. Crear `deploy/docker-compose.prod.yml`, `deploy/nginx/templates/…`,
   `deploy/.env.production.example` y actualizar `.gitignore`.
3. Añadir `ktor-server-forwarded-header` a `libs.versions.toml`/`backend/build.gradle.kts`.
4. Añadir `ProxySettings` a `HttpHardeningConfig.kt`, crear
   `plugins/ForwardedHeaders.kt` e instalarlo en `Application.kt`.
5. Crear `ForwardedHeadersRouteTest` y ampliar `HttpHardeningConfigTest`.
6. Crear `deploy/verify-deploy.sh` y `deploy/README.md`.
7. Pasar el gate offline; actualizar `ARCHITECTURE.md`, `CONSTRAINTS.md`, ADR 0028 +
   índice, la skill y `docs/desarrollo-local.md`/`README.md`;
   `PROGRESS.md`/`feature_list.json` los cierra el orquestador.

## Implementation Tasks

- [ ] `backend/Dockerfile` + `.dockerignore` (multi-stage, `installDist -PskipClient`,
      sin secretos ni modelo).
- [ ] `deploy/docker-compose.prod.yml` (`postgres` loopback, `backend` sin puerto,
      `nginx` 80/443, `restart: unless-stopped`, healthchecks).
- [ ] `deploy/nginx/templates/datopublico.conf.template` (TLS, redirect, proxy,
      `X-Forwarded-*`, cabeceras de seguridad).
- [ ] `deploy/.env.production.example` (*placeholders*) y `.gitignore`
      (`deploy/.env.production`).
- [ ] `libs.versions.toml` + `backend/build.gradle.kts`: `ktor-server-forwarded-header`
      (3.0.3).
- [ ] `infra/HttpHardeningConfig.kt` (`ProxySettings`), `plugins/ForwardedHeaders.kt`
      y `Application.kt`.
- [ ] `ForwardedHeadersRouteTest` y `HttpHardeningConfigTest`.
- [ ] `deploy/verify-deploy.sh` y `deploy/README.md`.
- [ ] Docs: `ARCHITECTURE.md`, `CONSTRAINTS.md`, ADR 0028 + índice, skill,
      `docs/desarrollo-local.md`, `README.md`.

## Verification Plan

### A. Gate offline (obligatorio; sin Docker, red ni BD)

- `./gradlew :backend:test --rerun-tasks` → `ForwardedHeadersRouteTest` y el resto
  en verde (0 fallos).
- `./gradlew :shared:jvmTest`, `./gradlew build --no-daemon -PskipClient`,
  `./gradlew test`, `./gradlew detekt` y `env -u JAVA_HOME .harness/init.sh` →
  exit 0.
- Estático: `git grep` no encuentra credenciales; `deploy/.env.production` **no**
  está *tracked*; `git diff` no toca migraciones (`V1`…`V5`) ni `:composeApp`/CI/
  `init.sh`.
- `init.sh`: **no** se modifica; el gate **no** arranca servidores ni Docker.

### B. Verificación local/offline opt-in (Docker instalado; sin servidor real)

- `docker compose -f deploy/docker-compose.prod.yml --env-file
  deploy/.env.production.example config -q` → OK (PostgreSQL loopback, backend sin
  puerto, `INGESTA_ENABLED=true`).
- `deploy/verify-deploy.sh` → *lint* de la config de Nginx (vía Docker si está) y
  comprobación estática de secretos; omite con mensaje si falta Docker.
- `docker build -f backend/Dockerfile -t datopublico-backend:dev .` → imagen
  construida (requiere red para la base y las dependencias de Gradle).
- Flujo de migración: `cp deploy/.env.production.example deploy/.env.production` +
  contraseña local; `docker compose … up -d postgres`;
  `set -a; . deploy/.env.production; set +a; ./gradlew :backend:flywayMigrate` y
  `./gradlew :backend:flywayInfo`; `docker compose … down -v`.

### C. Manual en el servidor real (opt-in; no automatizable aquí)

- DNS + certificado (`certbot`) → `curl -fsS https://<dominio>/health` `200` y
  redirect `301` desde HTTP.
- `docker compose … up -d` en el N100; `docker compose ps` `healthy`; logs JSON del
  backend.
- Secretos inyectados **solo** en `deploy/.env.production` del servidor (permisos
  restringidos).
- Observar la ingesta de **09:30** y la **segunda pasada** (`ingestion.run.completed`,
  sin duplicados).
- Rate limiting tras el proxy: dos IPs de cliente con cupos independientes
  (`TRUST_PROXY_HEADERS=true`).
- Persistencia tras `restart` del stack. Backups/alertas → **FT00042** (fuera).

### D. E2E

No aplica: el repo no tiene comando E2E persistente y el despliegue no cambia flujos
de usuario/API; el comportamiento HTTP nuevo se cubre con `testApplication` en el
gate y las comprobaciones manuales de C.

## Evidence To Capture

- Salida del gate (`build -PskipClient`, `test`, `detekt`, `init.sh` exit 0) con
  recuento y 0 fallos.
- Salida de `docker compose config`, del `docker build` y de `deploy/verify-deploy.sh`.
- `flywayInfo` tras migrar y prueba de persistencia tras reinicio.
- `curl` de HTTPS (`/health`, redirect 301) y ejemplo de `X-Forwarded-For` llegando
  al backend.
- Log `ingestion.run.completed` de la ventana diaria y de la segunda pasada.
- Confirmación de que no hay secretos versionados y de que `deploy/.env.production`
  está ignorado.
- Ficheros del commit `FT00041`, PR y run de CI; entradas en `PROGRESS.md` y
  `feature_list.json` (`evidence`).

## Validator Checklist

- [ ] Alcance acotado: imagen + compose de producción + Nginx/HTTPS + secretos por
      entorno + cabeceras de proxy; **sin** cron externo, **sin** backups/alertas,
      **sin** certificados por código, **sin** migraciones, **sin** UI, **sin**
      cambios en `:composeApp`/CI/`init.sh`.
- [ ] Escenarios 1–7 pasan; **el gate corre sin Docker, red, BD ni secretos**.
- [ ] `docker compose config` valida con la plantilla; PostgreSQL **solo loopback**;
      backend **sin** puerto publicado; `restart: unless-stopped` y healthchecks.
- [ ] Nginx termina TLS, redirige HTTP→HTTPS y reenvía `X-Forwarded-*`; el backend
      no es alcanzable directamente.
- [ ] **Ninguna** credencial versionada; `deploy/.env.production` ignorado; el
      arranque falla con mensaje claro si falta un secreto.
- [ ] `TRUST_PROXY_HEADERS` es **opt-in** (por defecto false); con él, el rate
      limiting usa la IP real; sin él, el comportamiento actual no cambia.
- [ ] La ingesta usa el **scheduler interno** (ADR 0004); no se añade cron externo.
- [ ] La dependencia nueva es solo `ktor-server-forwarded-header` (oficial, 3.0.3);
      identificadores en inglés y KDoc en castellano; un solo `return`, sin `else if`,
      funciones ≤40 líneas.
- [ ] `ARCHITECTURE.md`, `CONSTRAINTS.md`, ADR 0028 + índice, skill,
      `docs/desarrollo-local.md`, `README.md`, `PROGRESS.md` y `feature_list.json`
      actualizados.
- [ ] Sin comportamiento de producto no relacionado ni ficheros fuera de alcance.

## Risks / Open Questions

- **«Cron» vs. ADR 0004 (decisión del dueño).** El roadmap dice «cron»; la
  implementación real es un scheduler interno. El spec **no** añade cron externo. Si
  el dueño lo quiere (p. ej. para el backfill), hace falta un ADR nuevo que
  supersede el 0004 y amplía el alcance.
- **TLS en un servidor doméstico.** Let's Encrypt HTTP-01 exige DNS propio y puertos
  80/443 accesibles; con IP dinámica o ISP que los bloquea haría falta DNS-01 o un
  túnel. Se documenta en el runbook; la emisión del certificado es **manual**.
- **Confianza de `X-Forwarded-For`.** Solo es segura si el backend **nunca** publica
  puerto (se garantiza en el compose). El flag va **apagado** por defecto; activarlo
  sin proxy permitiría falsear la IP del *rate limit*. Se documenta como MUST.
- **Dependencia nueva.** `ktor-server-forwarded-header` es oficial y 3.0.3 está en
  Maven Central (verificado); es la misma excepción deliberada que FT00030/ADR 0026.
  Si el dueño prefiere no añadirla, se puede **diferir** y documentar el rate
  limiting tras proxy como limitación conocida (entonces sobran 6 ficheros).
- **`docker build` necesita red** (imagen base + dependencias Gradle): queda
  **fuera** del gate y de la CI; es opt-in local.
- **Modelo E5 no versionado.** En el servidor hay que ejecutar
  `backend/tools/download-embedding-model.sh` y montar el volumen; sin él
  `/v1/buscar` y `/v1/chat` responden `404` (ya documentado).
- **Gaps de runtime ajenos.** El pipeline de resumen y el indexado del corpus siguen
  sin cablear (Sessions 068/070): en producción el feed puede salir vacío hasta que
  se resuelvan; **no** es alcance de esta feature.
- **`docker compose config` requiere el CLI de Docker.** `deploy/verify-deploy.sh`
  omite con mensaje claro si no está; el gate estándar no lo necesita.
- **División.** ≈17 ficheros → por debajo de 30 → **atómica**; no se recomienda
  partir en `FT00041-PTn`.
