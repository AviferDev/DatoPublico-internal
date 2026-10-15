# ADR 0034: Release y CI/CD con GitHub Actions (GHCR + SSH, versionado por tag semver)

## Estado

Aceptado (2026-10-15). Decisión del dueño al planificar y ejecutar `release-actions`
(FT00052-PT1). Complementa el ADR 0030 (despliegue en servidor propio) y no
supersede ninguno. Deja **anotada una decisión pendiente** (herramienta de subida a
tiendas) que solo afecta a PT3/PT4.

## Contexto

El backend ya se despliega en el servidor propio (FT00041: `backend/Dockerfile`,
`deploy/docker-compose.prod.yml`, Nginx + HTTPS, secretos por entorno), pero **todo
es manual**: no hay ningún workflow de publicación, ni versión por tag, ni imagen
publicada en un registro, ni forma repetible de actualizar el servidor. La Web
(FT00039), Android (FT00038) e iOS (FT00040) aún no tienen empaquetado.

Restricciones que condicionan la decisión:

- El **gate** (`./gradlew build -PskipClient`, `test`, `detekt`, `.harness/init.sh`)
  es offline (sin Docker, red ni BD) y **no** puede engancharse a la publicación.
- **Ningún secreto versionado** (MUST de `CONSTRAINTS.md`); los secretos del
  servidor (`POSTGRES_PASSWORD`, `OPENCODE_API_KEY`…) viven en el servidor.
- Servidor **Intel N100 / 8 GB**: construir la imagen allí (Gradle + JDK) es lento
  y compite con el servicio; el registro debe traer la imagen ya construida.
- El dueño quiere un **botón** (o un tag) y **nunca** despliegue automático en cada
  `push` a `main`.

## Decisión

1. **Disparo manual o por tag, nunca automático**: `workflow_dispatch` (con
   `targets`/`version`/`environment`) y `push` de tags **`vMAJOR.MINOR.PATCH`**.
   Ningún workflow de release se dispara en `push` a `main`.
2. **Versionado por tag semver** (`0.x` preproducción, `1.0.0` producción): la
   versión es el tag; los workflows la derivan (`${GITHUB_REF_NAME#v}` o el input) y
   la aplican al **tag de la imagen** (`BACKEND_IMAGE_TAG`) y, en las apps, a
   `-PappVersion`/`-PappVersionCode`. **No** se duplica en varios ficheros (el
   backend no tiene campo de versión).
3. **Imagen del backend a GHCR** con `docker/build-push-action` (Buildx, caché
   `type=gha,scope=backend`), tags `<version>` y `latest`; autenticación con
   `GITHUB_TOKEN` (`packages: write`), sin secreto extra. El nombre del repositorio
   GHCR se normaliza a **minúsculas** (`ghcr.io/aviferdev/datopublico-backend`).
4. **Despliegue por SSH** con una acción *pinned* (`appleboy/ssh-action@v1`): el
   runner fija el checkout del servidor en el tag (`git fetch --tags && git checkout
   --force vX.Y.Z`) y ejecuta `scripts/release/deploy-backend.sh` **en el servidor**.
   El script es **fail-fast**: `docker compose up -d postgres` + espera `healthy`,
   migraciones Flyway, `docker compose pull backend` + `up -d`, y health-check
   (contenedor `healthy` + `GET /health` por HTTPS). Si algo falla, el run queda en
   rojo y el release **no** se marca como bueno.
5. **Flyway: Gradle del host si hay JDK; si no, contenedor `flyway/flyway`**
   (`11-alpine`, `--network host` contra `127.0.0.1`) sobre el mismo directorio de
   migraciones. `FLYWAY_MODE=auto|gradle|container` lo fuerza. Flyway **nunca** se
   engancha al gate y las migraciones son **aditivas** (el rollback es volver a
   desplegar el tag anterior, no revertir el esquema).
6. **Compose generalizado a `image:`**: `deploy/docker-compose.prod.yml` usa
   `image: ${BACKEND_IMAGE:?}:${BACKEND_VERSION:-latest}` **conservando `build:`**
   para el desarrollo local y el primer despliegue manual. El release exporta
   `BACKEND_IMAGE`/`BACKEND_VERSION` (el entorno del shell gana a `--env-file`).
7. **Un único umbrella `release.yml`** (`workflow_dispatch`) que reparte por
   destinos y llama a los workflows reutilizables (`workflow_call`). Cada parte
   (PT2 Web, PT3 Android, PT4 iOS) añade su job en su propio PR: el fichero nunca
   referencia un workflow inexistente.
8. **Permisos mínimos y concurrencia que no cancela**: `contents: read` en todos
   los workflows; `packages: write` **solo** en el job de la imagen (PT1). Todos con
   `cancel-in-progress: false` (un despliegue no se aborta a medias).
9. **GitHub Environments** con revisores: `production` (backend y Web) y `internal`
   (Play internal / TestFlight). Los secretos/variables pueden acotarse al entorno;
   el job `deploy` valida su presencia y **falla con mensaje claro** nombrando los
   que falten.
10. **Setup común reutilizable**: acción compuesta
    `.github/actions/setup-jdk-gradle` (JDK 21 temurin + `gradle/actions/setup-gradle@v4`)
    para los jobs que compilan en el runner (Web/Android). El job de la imagen no la
    usa: `backend/Dockerfile` compila dentro de la imagen.
11. **El gate no cambia**: `ci.yml` y `.harness/init.sh` intactos; `docker build`,
    `docker compose config`, el lint de Nginx y `flywayMigrate` siguen siendo
    **opt-in**. La verificación local del cambio es estática (`bash -n`, parseo YAML
    y `docker compose config`).
12. **Pendiente (no bloquea PT1)**: la **herramienta de subida a tiendas** —
    Android: `fastlane supply` (propuesto) vs. `r0adkll/upload-google-play` vs.
    Gradle Play Publisher; iOS: `fastlane pilot` (propuesto) vs. `xcrun`/
    `iTMSTransporter`. Se decide al implementar **PT3/PT4** (dependen de FT00038/
    FT00040) y se registra aquí o en un ADR que lo ajuste.

## Alternativas consideradas

- **Auto-despliegue en `push` a `main`**: descartado por decisión del dueño; un
  merge no debe publicar ni desplegar.
- **Construir la imagen en el servidor** (como el primer despliegue de FT00041):
  descartado para releases; el N100 no debe compilar Gradle en cada versión.
- **Registro alternativo** (Docker Hub, registry propio): descartado; GHCR usa el
  `GITHUB_TOKEN` y permisos por workflow, sin secreto adicional.
- **Despliegue pull-based** (watchtower/agente en el servidor): descartado; el
  disparo debe ser explícito y con health-check en el propio run.
- **Un único workflow monolítico** para todo: descartado; workflows reutilizables
  por destino permiten partes independientes (PT1–PT4) y permisos mínimos.
- **Terraform/Ansible para el despliegue**: descartado (una sola máquina y ya hay
  runbook en `deploy/README.md`).
- **Secretos de servidor en GitHub** (para que el runner haga Flyway): descartado;
  los secretos de producción se quedan en el servidor.
- **`git checkout` del tag dentro del script de despliegue**: descartado; bash lee
  el script por partes y `git checkout` lo reemplazaría en caliente (el `exec` que
  lo evitaba rompía el rollback a tags sin el script). La fase git vive en el
  wrapper SSH del workflow.

## Consecuencias

- Publicar una versión pasa a ser un tag (o un botón) con health-check y evidencia
  en el run; el servidor no compila y el rollback es desplegar el tag anterior.
- Coste asumido: dependencia de GHCR y de la acción SSH *pinned*; el **primer** run
  real puede fallar por JDK ausente (Flyway), permisos SSH, DNS/TLS o
  `SSH_KNOWN_HOSTS` — mitigado con el modo contenedor de Flyway, la clave *pinned* y
  el runbook.
- Un tag olvidado **no** despliega: es intencional y queda documentado.
- Documentación afectada: `docs/release.md` (producto, runbook + inventario de
  secretos), `README.md` (producto), `ARCHITECTURE.md` (superficie de publicación),
  `CONSTRAINTS.md` (§«Publicación / Release»), `deploy/README.md` (referencia al
  nuevo camino) y skill `ktor-backend-architecture`.
- Verificación: estática local (parseo YAML, `bash -n`, `docker compose config`) +
  gate intacto; la ejecución real con tag requiere servidor y secretos (opt-in,
  evidencia manual).
