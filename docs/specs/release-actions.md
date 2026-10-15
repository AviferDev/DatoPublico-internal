# Feature Implementation Spec: CI/CD de publicación con GitHub Actions (backend y apps)

## Source Feature

- `id`: release-actions
- `ft_id`: FT00052 (registrado en `docs/feature-ids.md`)
- `parts`: FT00052-PT1 (backend), FT00052-PT2 (Web Wasm), FT00052-PT3 (Android), FT00052-PT4 (iOS)
- `area`: operacion
- `depends_on`: `deploy-backend` (FT00041), `dist-web` (FT00039), `dist-android`
  (FT00038), `dist-ios` (FT00040)
- `status`: not_started (al planificar)
- `source`: `feature_list.json` (`notes`: petición del dueño 2026-10-15 + `docs/roadmap.md`
  0.7-T01/T02, 0.8-T01..T04, 1.0-T01)
- `claim`: **sin reclamar** (no existe rama `feat/ft00052*` en `origin`, ni PR abierto con
  ese `FT`). El planner no crea ramas ni edita `feature_list.json`.

> **Decisiones cerradas con el dueño (no reabrir).** (1) Alcance backend **y** las tres
> plataformas de app → 4 partes. (2) Disparo **manual** (`workflow_dispatch`, con
> destino(s)/versión/entorno) **y por tag** de versión; **nunca** despliegue automático en
> cada push a `main`. (3) Backend: imagen a **GHCR** + despliegue por **SSH**. (4) Web:
> estático servido por el **Nginx del servidor propio**. (5) El dueño ya dispone de servidor
> con SSH, Play Console y Apple Developer; aun así el spec enumera los secretos exactos.

> **Dependencias y orden.** PT1 solo depende de **FT00041 fusionada** (aún en PR #35,
> sin fusionar; `deploy/` vive en `feat/ft00041-deploy-backend`, no en `main`). PT2/PT3/PT4
> **están bloqueadas** por FT00039/FT00038/FT00040 respectivamente (todas `not_started`):
> PT2 necesita el build Wasm con **URL de API parametrizable**; PT3 necesita la **firma
> release/keystore** y el `bundleRelease`; PT4 necesita el **proyecto Xcode**, la firma y el
> esquema de archivo. Orden recomendado: **PT1 → PT2 → PT3 → PT4**.

## Goal

Publicar el producto desde **GitHub Actions** con un botón (o un tag `vX.Y.Z`): construir y
publicar la **imagen del backend en GHCR** y desplegarla por **SSH** en el servidor propio
(pull + migraciones Flyway + `docker compose up -d` + health-check), publicar el **estático
Wasm de producción** en el **Nginx del mismo servidor**, y subir **Android (AAB, pista
internal de Google Play)** e **iOS (TestFlight vía App Store Connect API)**, sin versionar
**ningún** secreto y sin tocar el **gate estándar** (que sigue offline, sin Docker, sin red y
sin BD).

El resultado es un conjunto de workflows en `.github/workflows/`, con **permisos mínimos**,
**caché**, **concurrencia que nunca cancela un despliegue**, **GitHub Environments** con
revisores, y un **inventario exacto de secretos/variables** a crear. `ci.yml` y `.harness/init.sh`
**no se modifican**; los workflows de publicación **no** se enganchan al gate.

## Non-Goals

- **Empaquetado y firma por plataforma**: viven en FT00038 (Android), FT00039 (Web) y FT00040
  (iOS). PT2/PT3/PT4 **cablean la publicación** sobre esos artefactos, no los crean.
- **Despliegue automático en push a `main`.** El disparo es manual o por tag, por decisión del dueño.
- **Backups, observabilidad de producción y alertas** (FT00042).
- **Aprovisionamiento del servidor** (Docker, DNS, certificado TLS, modelo E5, `deploy/.env.production`):
  lo cubre FT00041 y su runbook `deploy/README.md`.
- **Cuentas de tienda nuevas** (Play Console, Apple Developer) y sus altas administrativas.
- **Versionado de la app más allá del tag**: no se introduce un sistema de changelog/notas automáticas.
- **Cambiar `ci.yml`, `init.sh` o las reglas del gate**; ni añadir dependencias a los módulos Gradle.
- **Publicación en producción estable de tienda (pista `production`/App Store público)**: la 1.0.0
  real (FT00046) queda fuera; aquí basta con **internal/TestFlight**.

## Job Story

When tengo el backend, la Web y las apps listos para una versión,
I want disparar una publicación desde GitHub (a mano eligiendo destinos o con un tag) que
construya, publique y despliegue cada artefacto sin manejar credenciales a mano,
so I can sacar versiones de forma repetible y sin filtrar secretos, sin romper el flujo de
desarrollo local ni la CI.

## Users And Permissions

- **Dueño/operador (owner):** único actor que dispara los workflows (`workflow_dispatch` o
  push de tag) y aprueba los entornos protegidos. Tiene permisos de administración del repo
  para crear Environments/Secrets/Variables.
- **GitHub Actions runner:** ejecuta con `GITHUB_TOKEN` de **permisos mínimos** por workflow;
  solo PT1 añade `packages: write` (GHCR). Nunca recibe secretos que no necesite.
- **GitHub Environments:** `production` (backend/Web) con **required reviewers**; `internal`
  (Android Play internal / iOS TestFlight). Los secretos/variables pueden estar *scoped* al entorno.
- **Servidor propio:** usuario SSH de despliegue con acceso al checkout del repo y al
  `deploy/.env.production` (que **permanece en el servidor**; no viaja a GitHub).
- **Google Play / Apple Developer:** **cuenta de servicio** de Play (Play Developer API) y
  **clave de App Store Connect API** (`.p8`) con rol suficiente. La ciudadanía **no** participa.

## Acceptance Scenarios

### Scenario PT1-1: un tag publica y despliega el backend

Given `deploy/` de FT00041 fusionado, los secretos SSH configurados y el entorno `production` aprobado,
When se hace push del tag `v0.7.0`,
Then el workflow construye la imagen del backend (`backend/Dockerfile`, `installDist -PskipClient`),
la publica en **GHCR** con tags `0.7.0` y `latest`, se conecta por **SSH** al servidor, hace
`git fetch --tags && git checkout v0.7.0`, `docker compose pull backend`, aplica **Flyway**,
`docker compose up -d` y, al final, el **health-check** (`/health`) responde `200`.

### Scenario PT1-2: dispatch manual con versión y entorno

Given el workflow `release` con `workflow_dispatch`,
When el dueño elige `targets=backend`, `version=0.7.1` y `environment=production`,
Then solo se ejecuta el job del backend, la imagen se etiqueta `0.7.1`/`latest` y el despliegue
sigue el mismo camino que el tag; el resto de destinos quedan sin ejecutar.

### Scenario PT1-3: fallo de health-check no deja el servicio a medias

Given un despliegue en curso,
When el contenedor arranca pero `/health` no responde `200` tras el tiempo de espera,
Then el job termina en **fallo** con el log del `docker compose ps`/logs, sin marcar el release
como correcto (y el `restart: unless-stopped` mantiene la versión anterior o la nueva sana).

### Scenario PT2-1: la Web de producción se sirve desde Nginx

Given FT00039 fusionada (build Wasm con URL de API parametrizable) y `WEB_ROOT` configurado,
When se dispara la publicación de la Web (tag o dispatch) y el job sube el estático por SSH/rsync,
Then `https://<dominio>/` sirve `index.html` + `*.wasm` con la **URL de API de producción**
incrustada, y las rutas de la API (`/v1/*`, `/health`, `/openapi.json`) **siguen proxied** al backend.

### Scenario PT2-2: SPA con fallback y caché correcta

Given el estático publicado,
When se pide una ruta cliente que no es fichero (p. ej. `/detalle/...`),
Then Nginx devuelve `index.html` (fallback SPA) con `200`, y sirve `*.wasm`/`*.js` con
`Content-Type` correcto y caché de larga duración, sin cachear `index.html`.

### Scenario PT3-1: AAB firmado en la pista internal

Given FT00038 fusionada y los secretos del keystore + la cuenta de servicio de Play,
When se publica Android,
Then se genera un **AAB release firmado** (`bundleRelease`) y se sube a la pista **`internal`**
de Google Play mediante la **Play Developer API**, quedando asociado a la versión pedida.

### Scenario PT3-2: sin firma válida, no se sube

Given el keystore ausente o con contraseña incorrecta,
When se ejecuta el workflow,
Then `bundleRelease` (o la subida) **falla con mensaje claro** y no se publica nada en Play.

### Scenario PT4-1: build iOS a TestFlight

Given FT00040 fusionada (proyecto Xcode + esquema) y la clave ASC + certificado/provisioning,
When se publica iOS en un runner `macos-14`,
Then se archiva (`xcodebuild archive`), se exporta y se sube **vía App Store Connect API**;
la build aparece en **TestFlight**.

### Scenario PT4-2: assets de firma mal configurados

Given certificado/provisioning o clave `.p8` inválidos,
When se ejecuta el workflow,
Then el job falla de forma explícita en la fase de firma/export, sin subir nada a App Store Connect.

### Scenario GATE-1 (transversal): el gate no cambia

Given los workflows de publicación añadidos,
When se ejecutan `./gradlew build -PskipClient`, `./gradlew test`, `./gradlew detekt` y
`.harness/init.sh` **sin** Docker, red, BD ni secretos,
Then todo está en verde; `ci.yml` y `init.sh` no cambian; ningún workflow de publicación se
dispara en `push` a `main`; y `git grep` no encuentra credenciales versionadas.

## Repository Research

### Files Inspected

- `.github/workflows/ci.yml` (producto) — CI actual: `push`/`pull_request` a `main`,
  `ubuntu-latest`, JDK 21 (temurin), `gradle/actions/setup-gradle@v4`,
  `./gradlew build --no-daemon`, `permissions: contents: read`. **No** hay workflows de despliegue.
- `.github/workflows/` (producto) — solo existe `ci.yml`.
- `settings.gradle.kts` — `include(":shared", ":backend")`; `:composeApp` **solo** sin
  `-PskipClient` (exige Android SDK). Repos (Ivy para Binaryen/Node/Yarn) en `PREFER_SETTINGS`.
- `composeApp/build.gradle.kts` — targets `androidTarget()`, `jvm()`, `iosArm64`,
  `iosSimulatorArm64`, `wasmJs { browser(); binaries.executable() }`; **sin `signingConfig`**;
  `versionCode = 1`, `versionName = "0.1.0"` en `defaultConfig`; `wasmJsBrowserTest` desactivado.
- `composeApp/src/*/…/core/network/Platform.*.kt` + `ApiConfig.kt` — la URL base es **por
  plataforma**: Android `http://localhost:8080` (adb reverse), iOS/JVM `localhost`, **Wasm
  `https://terrorist-wan-strikes-grade.trycloudflare.com`**. Son valores de **desarrollo**: no
  hay mecanismo de URL de producción (lo introduce FT00039).
- `gradle/libs.versions.toml`, `build.gradle.kts` (raíz), `gradle.properties` — catálogo,
  detekt/CPD bloqueantes, `-PskipClient`.
- `.env.example` (raíz) y `.env` (local, ignorado) — plantilla de desarrollo, solo placeholders.
- `docs/desarrollo-local.md` (producto) — build Web `:composeApp:wasmJsBrowserDistribution` →
  `composeApp/build/dist/wasmJs/productionExecutable/`; sección de URL base por plataforma.
- `gradle/wrapper/gradle-wrapper.properties` — Gradle **8.10.2**.
- **FT00041 (`origin/feat/ft00041-deploy-backend`, PR #35 abierto, sin fusionar)**:
  - `backend/Dockerfile` — multi-stage (`installDist -PskipClient`, JRE 21, no-root, `EXPOSE 8080`).
  - `.dockerignore` — contexto de build pequeño y sin secretos.
  - `deploy/docker-compose.prod.yml` — `postgres` (loopback) + `backend` (**`build:`**, sin
    puerto, `INGESTA_ENABLED=true`, `restart: unless-stopped`) + `nginx` (80/443, solo `proxy_pass`
    a `backend:8080`).
  - `deploy/nginx/templates/datopublico.conf.template` — 80 (ACME + redirect) y 443 (TLS +
    proxy a `backend:8080` con `X-Forwarded-*`); **no sirve estático**.
  - `deploy/.env.production.example` — placeholders (`DOMAIN`, `POSTGRES_*`, `OPENCODE_API_KEY`,
    `CORS_ALLOWED_ORIGINS`, `TRUST_PROXY_HEADERS=true`, `INGESTA_*`, `HTTP_PORT`/`HTTPS_PORT`…).
  - `deploy/README.md` — runbook (Docker, DNS, `certbot`, `flywayMigrate` en host, `up -d`).
  - `deploy/verify-deploy.sh` — verificación offline **opt-in** (Compose + Nginx + secretos).
- Harness: `feature_list.json` (FT00052 + partes; FT00038/39/40), `docs/feature-ids.md`,
  `docs/roadmap.md` (0.7/0.8/1.0), `docs/technical-discovery.md` §«Deployment and Operations»,
  `docs/risks-and-open-questions.md`, `CONSTRAINTS.md` §«Operación»/§«Despliegue»,
  `docs/specs/deploy-backend.md`, ADR `0030-despliegue-servidor-propio`, `docs/git-workflow.md`.

### Existing Patterns To Follow

- **CI ya fijado**: `actions/checkout@v5`, `actions/setup-java@v5` (temurin, JDK 21),
  `gradle/actions/setup-gradle@v4` (caché). Los workflows de release **reutilizan** este patrón.
- **Acciones *pinned* por versión mayor** (precedente `@v5`/`@v4`); evitar acciones sin versión.
- **8.10.2 como wrapper**: los workflows usan `./gradlew` con el wrapper versionado.
- **Secretos solo por entorno** (MUST de `CONSTRAINTS.md`); la plantilla solo admite *placeholders*.
- **El gate no arranca servidores/Docker/red/BD**; las tareas pesadas son **opt-in**.
- **Identificadores en inglés, KDoc/comentarios en castellano**; Conventional Commits con el `FT`
  como scope; **ADR** para decisiones durables; **≤30 ficheros** por PR.
- **Verificación offline posible** (`deploy/verify-deploy.sh`): el estilo de check estático sin
  credenciales reales se replica en los workflows.

### Current Gaps

- **No hay ningún workflow de despliegue/publicación** ni entorno de release.
- **PT1 bloqueada por FT00041** (`deploy/` no está en `main`): el compose usa `build:` del contexto,
  no una imagen de **GHCR**; hay que permitir `image:` con la etiqueta publicada.
- **PT2 bloqueada por FT00039**: no existe build Wasm con URL de API de producción; el Nginx de
  FT00041 **no sirve estáticos** (solo proxy), así que hay que añadir `root`/`try_files` y montar
  el webroot en el compose.
- **PT3 bloqueada por FT00038**: `:composeApp` **no tiene `signingConfig`** ni keystore, y no hay
  `versionCode`/`versionName` derivados del tag.
- **PT4 bloqueada por FT00040**: **no existe proyecto Xcode** (`*.xcodeproj`/`*.xcworkspace`),
  ni firma, ni esquema de archivo.
- **No existe versionado por tag** ni fuente única de versión (backend sin versión; app con
  `0.1.0` literal).
- **No hay ADR de estrategia de release/CI-CD.**
- **Herramienta de subida a tiendas sin decidir** (fastlane vs. acción de Play vs. GPP): decisión
  durable pendiente (ver *Risks*).

## Technical Approach

Deriva de las decisiones cerradas con el dueño, `docs/roadmap.md` 0.7/0.8/1.0,
`docs/technical-discovery.md` §«Deployment and Operations» y `CONSTRAINTS.md`. Decisión durable en
un **ADR 0034**.

### Estrategia de release y versionado

- **Tags semánticos** `vMAJOR.MINOR.PATCH` (p. ej. `v0.7.0`, `v1.0.0`); `0.x` = preproducción,
  `1.0.0` = producción (`docs/roadmap.md` §3). Un tag dispara **todos** los workflows de release.
- **`workflow_dispatch`** con entradas comunes: `version` (string; por defecto derivada del tag
  `GITHUB_REF_NAME`), `environment` (`internal` | `production`) y —solo en el *umbrella*— `targets`
  (`backend`, `web`, `android`, `ios`; multi-selección).
- **Fuente única de versión**: los workflows exportan la versión (`${GITHUB_REF_NAME#v}` o el input)
  y la pasan a los builds (`-PappVersion`, `-PappVersionCode` / `BACKEND_IMAGE_TAG`). El backend no
  tiene campo de versión hoy: la versión vive en el **tag de la imagen**. **No** se duplica la versión
  en varios ficheros.
- **Nunca** despliegue automático en `push` a `main` (decisión del dueño).

### Inventario de workflows (`.github/workflows/`)

| Fichero | Parte | Trigger | Jobs | Permisos | Entorno | Concurrencia |
| --- | --- | --- | --- | --- | --- | --- |
| `release.yml` | PT1 (se amplía en PT2–PT4) | `workflow_dispatch` (`targets`/`version`/`environment`) | fan-out a los workflows reutilizables | `contents: read` | — | `release-umbrella`, no cancela |
| `release-backend.yml` | PT1 | `workflow_call` + `workflow_dispatch` + `push: tags: ['v*']` | `image` (buildx→GHCR) · `deploy` (SSH) | `contents: read`, `packages: write` | `production` | `release-backend-${{ref}}`, no cancela |
| `release-web.yml` | PT2 | `workflow_call` + `workflow_dispatch` + `push: tags` | `build` (Wasm prod) · `publish` (rsync/SSH) | `contents: read` | `production` | `release-web-${{ref}}`, no cancela |
| `release-android.yml` | PT3 | `workflow_call` + `workflow_dispatch` + `push: tags` | `bundle` (AAB firmado) · `publish` (Play internal) | `contents: read` | `internal` | `release-android-${{ref}}`, no cancela |
| `release-ios.yml` | PT4 | `workflow_call` + `workflow_dispatch` + `push: tags` | `archive` (macos-14) · `upload` (TestFlight) | `contents: read` | `internal` | `release-ios-${{ref}}`, no cancela |
| `_setup-jdk-gradle` (acción compuesta) | PT1 | — (acción) | setup JDK 21 + Gradle con caché | — | — | — |

- **Reutilización**: el *umbrella* `release.yml` llama a los cuatro mediante `on: workflow_call`
  (`uses: ./.github/workflows/release-backend.yml`). **Cada parte añade su job al `release.yml` en su
  propio PR**, de modo que el fichero siempre es válido (nunca referencia un workflow inexistente).
  Como los jobs reutilizables deben existir al cargar el workflow, el *umbrella* nace en PT1 con el
  job del backend y se amplía en cada parte.
- **Setup común**: acción compuesta `.github/actions/setup-jdk-gradle/action.yml` (checkout se hace
  aparte) con JDK 21 temurin + `gradle/actions/setup-gradle@v4`; la reutilizan PT1–PT3 (PT4 usa
  `macos-14` y Xcode propios). Se crea en PT1.
- **Concurrencia**: `cancel-in-progress: false` siempre (un despliegue **no** se cancela a medias).
- **Caché**: Gradle (`setup-gradle`); Docker Buildx con `cache-from/to: type=gha,scope=backend`;
  para Wasm, caché de las distribuciones de Kotlin/JS-Wasm vía `setup-gradle`.
- **Environments**: `production` (backend/Web) con **required reviewers**; `internal`
  (Android/iOS). Los secretos/variables pueden colgar del entorno para acotarlos.
- **Idempotencia/rollback**: el deploy del backend fija el `git checkout <tag>` en el servidor; si
  el health-check falla, el job falla (sin marcar el tag como bueno). El rollback manual reutiliza
  el tag anterior (se documenta en el runbook).

### Inventario de secretos y variables (crear en GitHub)

**Secretos** (Settings → Secrets and variables → Actions; *encrypted*):

| Secreto | Para | Notas |
| --- | --- | --- |
| `SSH_HOST` | PT1/PT2 | host del servidor (o variable si no se considera sensible) |
| `SSH_USER` | PT1/PT2 | usuario de despliegue |
| `SSH_PRIVATE_KEY` | PT1/PT2 | clave privada (solo despliegue) |
| `SSH_KNOWN_HOSTS` | PT1/PT2 | *host key* fijada (evita MITM) |
| `ANDROID_KEYSTORE_BASE64` | PT3 | keystore release en base64 |
| `ANDROID_KEYSTORE_PASSWORD` | PT3 | — |
| `ANDROID_KEY_ALIAS` | PT3 | — |
| `ANDROID_KEY_PASSWORD` | PT3 | — |
| `PLAY_SERVICE_ACCOUNT_JSON` | PT3 | clave JSON de la cuenta de servicio de Play |
| `ASC_KEY_ID` | PT4 | App Store Connect API key id |
| `ASC_ISSUER_ID` | PT4 | issuer id |
| `ASC_PRIVATE_KEY` | PT4 | contenido del `.p8` |
| `BUILD_CERTIFICATE_BASE64` | PT4 | certificado de distribución (`.p12` base64) |
| `P12_PASSWORD` | PT4 | contraseña del `.p12` |
| `PROVISIONING_PROFILE_BASE64` | PT4 | perfil de aprovisionamiento (base64) |

**Variables** (no secretas):

| Variable | Para | Valor previsto |
| --- | --- | --- |
| `SSH_PORT` | PT1/PT2 | `22` |
| `DEPLOY_PATH` | PT1/PT2 | ruta del checkout en el servidor |
| `WEB_ROOT` | PT2 | ruta del webroot estático de Nginx |
| `PROD_API_BASE_URL` | PT2 | `https://<dominio>` (consumida por el build de FT00039) |
| `ANDROID_PACKAGE_NAME` | PT3 | `es.aviferdev.datopublico` |
| `PLAY_TRACK` | PT3 | `internal` |
| `APPLE_TEAM_ID` | PT4 | team de Apple |
| `IOS_BUNDLE_ID` | PT4 | bundle id |
| `IOS_SCHEME` / `IOS_PROJECT` | PT4 | esquema y proyecto Xcode de FT00040 |

- **GHCR** no necesita secreto: usa el `GITHUB_TOKEN` con `packages: write`.
- **Los secretos del servidor** (`POSTGRES_PASSWORD`, `OPENCODE_API_KEY`…) **no** van a GitHub:
  permanecen en `deploy/.env.production` del servidor (FT00041).
- **Nunca** se versiona ningún secreto: keystore, `.p8`, JSON de Play y claves SSH viven solo en
  GitHub Secrets (MUST de `CONSTRAINTS.md`).

### PT1 — Backend (imagen a GHCR + despliegue por SSH)

- `image`: `docker/build-push-action` (Buildx) con `context: .`, `file: backend/Dockerfile`,
  `push: true`, `tags: ghcr.io/<owner>/datopublico-backend:<version>` y `:latest`,
  `cache-from/to: type=gha`.
- `deploy`: por SSH (acción *pinned*, p. ej. `appleboy/ssh-action`) ejecutando
  `scripts/release/deploy-backend.sh` **en el servidor** con la `version`: `git fetch --tags`,
  `git checkout <tag>`, `docker compose pull backend`, Flyway, `docker compose up -d`, health-check.
- **Flyway**: se mantiene el camino de FT00041 (`./gradlew :backend:flywayMigrate` en el host contra
  `127.0.0.1:5432`) tras `up -d postgres`. *Open question*: si el servidor no tiene JDK, migrar con el
  contenedor `flyway/flyway` (se decide en el ADR).
- **Compose**: se generaliza `deploy/docker-compose.prod.yml` para aceptar `image: ${BACKEND_IMAGE:-…}`
  además de `build:` (así el servidor hace `pull` del tag y el desarrollo local puede seguir con `build`).
- **Health-check final**: `docker compose ps` + `wget -qO- http://localhost:8080/health` en el servidor
  y, si hay DNS público desde el runner, `curl -fsS https://<DOMINIO>/health`.

### PT2 — Web (build Wasm de producción + Nginx del servidor)

- `build`: `.github/actions/setup-jdk-gradle` + `./gradlew :composeApp:wasmJsBrowserDistribution`
  con la URL de API de producción inyectada **según el mecanismo de FT00039** (variable
  `PROD_API_BASE_URL`); artefacto `composeApp/build/dist/wasmJs/productionExecutable/`.
- `publish`: `rsync` por SSH a `WEB_ROOT` (ficheros con `--delete`, atómico en la medida de lo posible).
- **Nginx**: se amplía `deploy/nginx/templates/datopublico.conf.template` para servir el estático en
  `location /` (`root`+`try_files $uri $uri/ /index.html`, fallback SPA) **conservando** el proxy a
  `/v1/*`, `/health` y `/openapi.json`; `deploy/docker-compose.prod.yml` monta el webroot en el
  servicio `nginx`; `deploy/.env.production.example` añade `WEB_ROOT`.

### PT3 — Android (firma release + AAB a Play internal)

- `bundle`: `.github/actions/setup-jdk-gradle` + `./gradlew :composeApp:bundleRelease` con la firma
  de **FT00038** alimentada por los secretos del keystore y `-PappVersion`/`-PappVersionCode` del tag.
- `publish`: subida del AAB a la pista `internal` por la **Play Developer API** con la cuenta de
  servicio (`PLAY_SERVICE_ACCOUNT_JSON`). **Herramienta a decidir en el ADR**: `fastlane supply`
  (por defecto propuesto), la acción `r0adkll/upload-google-play` o el plugin Gradle Play Publisher.

### PT4 — iOS (firma + archivo a TestFlight)

- Runner `macos-14` + Xcode; `xcodebuild archive` + `-exportArchive` sobre el proyecto de **FT00040**,
  con el certificado/provisioning instalados desde los secretos (o `-allowProvisioningUpdates` con la
  clave ASC).
- Subida a TestFlight **vía App Store Connect API** con `ASC_KEY_ID`/`ASC_ISSUER_ID`/`ASC_PRIVATE_KEY`.
  **Herramienta a decidir en el ADR** (por defecto propuesto: `fastlane pilot`; alternativa: `xcrun`/`iTMSTransporter`).

### Sin anticipar lo diferido

Sin auto-deploy en `main`, sin backups/alertas (FT00042), sin pista `production`/App Store público
(FT00046), sin cambios en `ci.yml`/`init.sh`/módulos Gradle, sin tocar migraciones.

## Expected File Changes

Rutas en el repo de producto (`..`). Recuento por parte (límite 30):

**PT1 — Backend** (≈8 ficheros):
- `.github/workflows/release.yml` — create; *umbrella* `workflow_dispatch` (job backend).
- `.github/workflows/release-backend.yml` — create; `workflow_call`+`workflow_dispatch`+`tags` → GHCR + SSH.
- `.github/actions/setup-jdk-gradle/action.yml` — create; acción compuesta (JDK 21 + caché Gradle).
- `scripts/release/deploy-backend.sh` — create; despliegue en el servidor (pull + Flyway + up + health).
- `deploy/docker-compose.prod.yml` — modify; `image: ${BACKEND_IMAGE}` además de `build:`.
- `deploy/.env.production.example` — modify; `BACKEND_IMAGE`/`BACKEND_VERSION` (placeholders).
- `docs/release.md` (producto) — create; runbook de publicación (tags, dispatch, secretos, rollback).
- `README.md` (producto) — modify; enlace al runbook.

**PT2 — Web** (≈7 ficheros):
- `.github/workflows/release-web.yml` — create.
- `.github/workflows/release.yml` — modify; añadir job Web.
- `deploy/docker-compose.prod.yml` — modify; montar `WEB_ROOT` en `nginx`.
- `deploy/nginx/templates/datopublico.conf.template` — modify; servir estático + fallback SPA + proxy.
- `deploy/.env.production.example` — modify; `WEB_ROOT`.
- `scripts/release/deploy-web.sh` — create; `rsync` del estático por SSH.
- `docs/release.md` — modify; sección Web.

**PT3 — Android** (≈3–4 ficheros, según lo que ya haga FT00038):
- `.github/workflows/release-android.yml` — create.
- `.github/workflows/release.yml` — modify; añadir job Android.
- `composeApp/build.gradle.kts` — modify **solo si** FT00038 no dejó firma/versión parametrizables.
- `docs/release.md` — modify; sección Android.

**PT4 — iOS** (≈3 ficheros):
- `.github/workflows/release-ios.yml` — create.
- `.github/workflows/release.yml` — modify; añadir job iOS.
- `docs/release.md` — modify; sección iOS.

Harness (privado): `ARCHITECTURE.md`, `CONSTRAINTS.md`, ADR `0034` + índice, `PROGRESS.md` y
`feature_list.json` (los cierra el orquestador).

## Visual Design Impact

- UI involved: **no**. Sin pantallas, tokens ni textos; no se toca `:composeApp` (salvo, en PT3,
  la firma/versión del build, sin cambio visual).
- Design source: no aplica (`DESIGN.md` no se toca).
- Screens or states affected: ninguno.
- New design artifact required: no. **No** se requieren capturas antes/después (no hay cambio de interfaz).

## Durable Documentation Impact

- `ARCHITECTURE.md`: **update** — nueva superficie de **publicación/CI-CD** (workflows, GHCR,
  despliegue por SSH, estático Web en Nginx, subida a tiendas) y su relación con `deploy/` de FT00041.
- `CONSTRAINTS.md`: **update** — nueva sección **«Publicación / Release»**: disparo **manual o por
  tag** (nunca auto-deploy en `main`); secretos **solo** en GitHub Secrets/Environments y **nunca**
  versionados; permisos mínimos por workflow y `concurrencia` que **no** cancela despliegues; el
  gate (`build`/`test`/`detekt`/`init.sh`) **no** cambia ni se engancha a los workflows de release;
  versionado por **tag semver** (`0.x` preproducción, `1.0.0` producción).
- `AGENTS.md`: **not needed** — el flujo de agentes, el arranque y las reglas de trabajo no cambian
  (el gate sigue igual).
- Other docs: `docs/adr/0034-release-github-actions.md` — **create** (estrategia de release/CI-CD,
  herramienta de subida a tiendas, versionado por tag) + índice `docs/adr/README.md`;
  `docs/release.md` (producto) — **create**; `PROGRESS.md` — **update** (bitácora).

## Implementation Plan

Orden recomendado por dependencia: **PT1 → PT2 → PT3 → PT4** (cada parte, su rama/PR y su `FT00052-PTn`).

1. **PT1**: esperar/rebasar sobre FT00041 (PR #35) fusionada. Crear la acción compuesta, el *umbrella*
   y `release-backend.yml`; generalizar el compose a `image:`; `scripts/release/deploy-backend.sh`;
   validar build de imagen + `docker compose config`; documentar secretos y runbook.
2. **PT2**: tras FT00039. `release-web.yml` (+ job en el *umbrella*), `deploy-web.sh`, Nginx estático
   y webroot en el compose; validar servido local del estático y proxy de la API.
3. **PT3**: tras FT00038. `release-android.yml` (+ job), firma desde secretos, AAB y subida a `internal`.
4. **PT4**: tras FT00040. `release-ios.yml` (+ job), archivo y subida a TestFlight.
5. Cerrar: ADR 0034 + índice, `ARCHITECTURE.md`, `CONSTRAINTS.md` y `docs/release.md`;
   `PROGRESS.md`/`feature_list.json` los cierra el orquestador.

## Implementation Tasks

**PT1 — Backend**
- [ ] `.github/actions/setup-jdk-gradle/action.yml` (JDK 21 temurin + `gradle/actions/setup-gradle@v4`).
- [ ] `.github/workflows/release-backend.yml` (buildx→GHCR; SSH; `permissions` mínimos; `concurrency`).
- [ ] `.github/workflows/release.yml` (*umbrella* `workflow_dispatch` con `targets`/`version`/`environment`).
- [ ] `scripts/release/deploy-backend.sh` (pull + Flyway + `up -d` + health-check; fail-fast).
- [ ] `deploy/docker-compose.prod.yml` → `image: ${BACKEND_IMAGE}` (mantener `build:` para local).
- [ ] `deploy/.env.production.example` → `BACKEND_IMAGE`/`BACKEND_VERSION`.
- [ ] `docs/release.md` (tags, dispatch, secretos, entornos, rollback) + enlace en `README.md`.

**PT2 — Web**
- [ ] `.github/workflows/release-web.yml` (Wasm prod con `PROD_API_BASE_URL`; rsync por SSH).
- [ ] Job Web en `.github/workflows/release.yml`.
- [ ] Nginx: servir estático (`root`+`try_files`+fallback SPA) conservando el proxy de la API.
- [ ] `deploy/docker-compose.prod.yml` monta `WEB_ROOT`; `deploy/.env.production.example` lo declara.
- [ ] `scripts/release/deploy-web.sh`; `docs/release.md`.
- [ ] `docs/release.md` §Web.

**PT3 — Android**
- [ ] `.github/workflows/release-android.yml` (firma desde secretos; `bundleRelease`; subida a `internal`).
- [ ] Job Android en `.github/workflows/release.yml`.
- [ ] Cablear firma/versión desde el tag (reutilizando FT00038); `docs/release.md` §Android.

**PT4 — iOS**
- [ ] `.github/workflows/release-ios.yml` (macos-14; archivo+export; TestFlight vía ASC API).
- [ ] Job iOS en `.github/workflows/release.yml`.
- [ ] `docs/release.md` §iOS.

## Verification Plan

### A. Gate estándar (obligatorio; sin Docker, red, BD ni secretos)

- `./gradlew build -PskipClient`, `./gradlew test`, `./gradlew detekt` y `.harness/init.sh` → exit 0.
- `ci.yml` y `.harness/init.sh` **sin cambios**; ningún workflow de release se dispara en `push` a `main`.
- `git grep` no encuentra credenciales; ningún keystore/`.p8`/JSON de Play versionado.

### B. Verificación estática de workflows (local, sin cuentas)

- Sintaxis/estructura: parseo YAML y, **opt-in**, `actionlint` (si está instalado) sobre
  `.github/workflows/*.yml` → 0 errores.
- Los *triggers* son solo `workflow_dispatch`, `workflow_call` y `push: tags: ['v*']` (revisión manual).
- Los `permissions` de cada workflow son los mínimos (revisión); `concurrency.cancel-in-progress: false`.
- `bash -n scripts/release/*.sh` y los scripts fallan con mensaje claro si falta una variable.
- `docker compose -f deploy/docker-compose.prod.yml --env-file deploy/.env.production.example config -q`
  (con Docker) resuelve con `BACKEND_IMAGE`/`WEB_ROOT`.
- El *umbrella* referencia solo workflows existentes en ese commit (validación de carga).

### C. Verificación local sin tiendas (opt-in)

- **PT1**: `docker build -f backend/Dockerfile -t datopublico-backend:test .`; `deploy/verify-deploy.sh`.
- **PT2**: `./gradlew :composeApp:wasmJsBrowserDistribution` con `PROD_API_BASE_URL` de prueba; servir
  `productionExecutable/` y comprobar `index.html`, `*.wasm` y el fallback SPA.
- **PT3**: `./gradlew :composeApp:bundleRelease` con un **keystore de prueba** local → AAB firmado
  (`jarsigner -verify`/`apksigner`).
- **PT4**: requiere macOS + Xcode; `xcodebuild -showBuildSettings` del esquema de FT00040.

### D. Verificación con cuentas/infra reales (opt-in; no automatizable aquí)

- **PT1/PT2**: push de tag → GHCR recibe la imagen; el servidor actualiza y `/health` responde `200`
  por HTTPS; el sitio sirve el Wasm de producción y la API sigue proxyada.
- **PT3**: el AAB aparece en la pista **internal** de Play Console.
- **PT4**: la build aparece en **TestFlight**.
- Se documenta como evidencia manual (requiere servidor, Play Console y Apple Developer reales).

### E. `init.sh` y E2E

- `./init.sh` **no** se modifica y **no** arranca servidores ni Docker (regla del harness).
- E2E: no aplica (no hay comando E2E persistente; el cambio es de CI/CD, no de flujo de usuario/API).
  La cobertura es la verificación estática/local (B/C) y las comprobaciones manuales de D.

## Evidence To Capture

- Salida del gate (`build -PskipClient`, `test`, `detekt`, `init.sh` exit 0) y ausencia de cambios en `ci.yml`/`init.sh`.
- Salida de `actionlint` (o parseo YAML) y revisión de *triggers*/*permissions*/*concurrency*.
- `docker compose config` con la plantilla; `docker build` de la imagen.
- Build Wasm local con URL de producción de prueba + servido del estático con fallback SPA.
- AAB firmado de prueba (`bundleRelease` + verificación de firma).
- Runs reales (tag): tag de imagen en GHCR, `/health` tras el despliegue, sitio Web en HTTPS,
  build en Play internal y en TestFlight.
- Ficheros del commit de cada `FT00052-PTn`, PR y run de CI; entradas en `PROGRESS.md`/`feature_list.json`.

## Validator Checklist

- [ ] Alcance por parte: PT1 backend (GHCR+SSH), PT2 Web (Wasm prod + Nginx), PT3 Android (Play
      internal), PT4 iOS (TestFlight); **sin** auto-deploy en `main`, **sin** backups, **sin** pista producción real.
- [ ] Escenarios PT1-1..PT4-2 y GATE-1 pasan (los de D con evidencia manual).
- [ ] `ci.yml` e `init.sh` **sin cambios**; el gate sigue verde, offline, sin Docker/red/BD/secretos.
- [ ] Ningún workflow de release se dispara en `push` a `main`; *triggers* = `workflow_dispatch`/`workflow_call`/`tags`.
- [ ] Permisos mínimos por workflow; `packages: write` solo en PT1; `concurrency` no cancela despliegues.
- [ ] **Ningún** secreto versionado; inventario de secretos/variables documentado y con *placeholders* solo en plantillas.
- [ ] Versionado por **tag semver**; la versión no se duplica en varios ficheros.
- [ ] Dependencias respetadas: PT1 sobre FT00041 fusionada; PT2/PT3/PT4 sobre FT00039/FT00038/FT00040.
- [ ] ≤30 ficheros por PR; ADR 0034 + índice, `ARCHITECTURE.md`, `CONSTRAINTS.md`, `docs/release.md`,
      `PROGRESS.md` y `feature_list.json` actualizados.
- [ ] Sin comportamiento de producto no relacionado ni ficheros fuera de alcance.

## Risks / Open Questions

- **PT1 bloqueada por FT00041 (PR #35 sin fusionar).** No empezar PT1 hasta rebasar sobre su estado
  mergeado; el compose actual usa `build:` y hay que generalizarlo a `image:`.
- **PT2/PT3/PT4 bloqueadas por FT00039/FT00038/FT00040** (todas `not_started`). Son el **camino crítico**:
  sin URL de API parametrizable (Web), firma release (Android) o proyecto Xcode (iOS) no hay nada que publicar.
- **Ningún secreto versionado.** Keystore, `.p8`, JSON de Play y clave SSH viven **solo** en GitHub
  Secrets; si se filtran, hay que **rotarlos**. Los secretos del servidor (`deploy/.env.production`)
  **no** viajan a GitHub.
- **Primer despliegue real.** El primer run de PT1 sobre el servidor puede fallar por JDK ausente
  (Flyway), permisos SSH, DNS/TLS o `ssh-keyscan`; mitigar con `SSH_KNOWN_HOSTS` fijado y el runbook.
- **Herramienta de subida a tiendas sin decidir** (fastlane vs. acción de Play vs. GPP; `pilot` vs.
  `xcrun`). Se decide en el **ADR 0034**; afecta a PT3/PT4 y al *toolchain* del runner.
- **`ci.yml` corre `./gradlew build` sin `-PskipClient`** (incluye `:composeApp` y exige Android SDK,
  que `ubuntu-latest` trae). Los workflows de release **no** deben alterar ese comportamiento.
- **Ejecución manual como única red de seguridad.** Al no haber auto-deploy en `main`, un tag olvidado
  no despliega: es intencional; se documenta el procedimiento.
- **Riesgo de revisión de Apple** (contenido informativo + IA) para TestFlight/App Store
  (`docs/risks-and-open-questions.md`); PT4 llega a TestFlight, no al App Store público.
- **Ambigüedad de división.** El *umbrella* `release.yml` lo toca cada parte (ediciones pequeñas);
  con trabajo en paralelo puede haber conflictos → rebasar y resolver antes del PR.
