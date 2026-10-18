# FT00050 — Script de arranque del entorno local (dev-up)

## Source Feature

- `id`: `dev-up-local`
- `ft_id`: `FT00050` (registrado en `docs/feature-ids.md`)
- `parts`: none (atómica; 1 fichero de producto)
- `area`: `operacion`
- `depends_on`: `publicacion-persistencia` (FT00008), `api-feed-diario` (FT00026)
- `status`: `passing` (entregada en `main` y **reparada** el 2026-10-18; validada de
  forma independiente en las rondas 2–3 y aceptada por el orquestador)
- `source`: `feature_list.json` (petición directa del dueño, sesión 083)
- `delivered_in`: commit `5cae1a7` (PR #43), fusionado en `main`

> **Spec retroactivo.** Escrito **después** de la entrega (commit `5cae1a7`, PR #43 ya
> fusionado en `main`) para cerrar la gobernanza: la feature se implementó como petición
> directa del dueño, sin spec previo. Describe el **contrato realmente entregado**, no
> planifica trabajo nuevo. El orquestador mantiene `feature_list.json`/`PROGRESS.md`.

## Goal

Ofrecer un **único comando** (`./scripts/dev-up.sh`) que prepare el entorno de
desarrollo local: baje los stacks Compose **hermanos del mismo repositorio** (para no
pisar el puerto `5432` ni el nombre fijo del contenedor), levante
**PostgreSQL/pgvector**, aplique las **migraciones Flyway** y **(re)inicie el backend**
esperando a `/health`, habilitando búsqueda/chat si el modelo E5 está descargado. El
cliente (app Android / Web) se arranca a mano.

## Non-Goals

- **Arrancar el cliente** (Android/Web/iOS): queda al usuario; el script solo imprime
  las instrucciones siguientes.
- **Sustituir el gate**: `./init.sh` sigue siendo el camino de verificación (no arranca
  servidores); `dev-up.sh` es una herramienta de desarrollo, no un gate.
- **Bajar stacks de otros proyectos** (p. ej. `vuelantis`): el script solo toca stacks
  Compose del **mismo** repositorio/worktrees.
- **Provisionar secretos**: el `.env` es la fuente de verdad; no se versiona ninguno.
- **Despliegue/producción**: es `deploy/` + `docs/release.md` (FT00041/FT00052).
- **Cambios en `docker-compose.yml`, migraciones, backend o cliente**: el script solo
  los orquesta.

## Acceptance Scenarios

Derivados de `feature_list.json.verification` y del comportamiento real entregado:

### Scenario 1: arranque completo en un comando
Given un `.env` (o `.env.example` para copiar) y Docker + JDK 21,
When se ejecuta `./scripts/dev-up.sh`,
Then levanta PostgreSQL/pgvector (`docker compose up -d --wait`), espera a su
healthcheck, aplica `:backend:flywayMigrate` y (re)inicia `:backend:run` en segundo
plano, esperando a que **el backend propio** responda en `http://localhost:8080/health`
(cuerpo `{"status":"ok"}` y `/openapi.json` 200).

### Scenario 2: no pisa stacks hermanos ni el contenedor fijo
Given otros stacks Compose del **mismo** repositorio (o de sus worktrees, incluidos los
ya eliminados de git cuyos contenedores siguen vivos),
When se ejecuta el script,
Then los baja (`docker compose --project-name <proyecto> down --remove-orphans`) antes
de levantar el actual, para no chocar con el puerto `5432` ni el contenedor
`datopublico-postgres`.

### Scenario 3: no toca stacks de otros proyectos
Given un stack Compose de **otro** proyecto (p. ej. `boe-rag`, `vuelantis`),
When se ejecuta el script,
Then sus contenedores **no** se bajan (el `working_dir` no pertenece a este repositorio).

### Scenario 4: búsqueda/chat habilitados si hay modelo E5
Given el modelo E5 en `backend/models/multilingual-e5-small/` y sin
`EMBEDDING_MODEL_PATH` fijado a mano,
When se arranca el backend,
Then el script exporta `EMBEDDING_MODEL_PATH`/`EMBEDDING_TOKENIZER_PATH`, de modo que
`/v1/buscar` y `/v1/chat` se registran.

### Scenario 5: el `.env` gana sobre el entorno del shell
Given variables del shell que colisionan con claves definidas en `.env`,
When se ejecuta el script,
Then se desexportan (solo en el proceso del script) para que gane el `.env`, y se
exporta el `.env` completo al backend.

### Scenario 6: flags y sin JDK
Given `--no-backend` o `--no-migrate`,
When se ejecuta el script,
Then omite respectivamente el arranque del backend o las migraciones; si no hay JDK 21
ni JBR, avisa, deja PostgreSQL arriba y sale con 0 imprimiendo el comando manual.

### Scenario 7: el gate no cambia
Given el script añadido,
When se ejecuta `bash -n scripts/dev-up.sh` y el gate estándar
(`./gradlew build -PskipClient`, `test`, `detekt`, `.harness/init.sh`),
Then `bash -n` no da error y el gate sigue verde; `init.sh` no cambia.

### Scenario 8: el arranque exige el backend propio y falla de verdad (reparación 2026-10-18)
Given el puerto `8080` ocupado por un servicio **ajeno** (p. ej. un túnel SSH) o el
proceso del backend muerto,
When se ejecuta el script,
Then **no** acepta un `200` cualquiera como éxito: exige que el proceso lanzado siga
vivo (`backend_process_alive`) y que responda el backend propio
(`backend_is_ours`: cuerpo exacto `{"status":"ok"}` **y** `/openapi.json` 200);
si no llega a estar listo en el plazo, emite `ERROR` a stderr, sale con código ≠ 0 y
**nunca** imprime el mensaje de «Listo».

## Delivered Changes (Expected File Changes)

Rutas en el repo de producto (`..`):

- `scripts/dev-up.sh` — **create** (233 líneas, ejecutable); único fichero de producto.
  Descansa sobre `docker-compose.yml` y `.env.example` **existentes** (sin modificarlos).
- **Reparación del 2026-10-18** (hallazgo H3 de la validación, +33/−7 líneas): el mismo
  fichero pasa a exigir el backend propio en el arranque y a fallar de verdad
  (ver *Scenario 8*). Sigue siendo el único fichero de producto de la feature.

## Technical Approach (real entregado)

- **Resolución de la raíz**: `cd "$(git rev-parse --show-toplevel)"`.
- **Flags**: `--no-migrate`, `--no-backend`, `-h/--help`; argumento desconocido → exit 2.
- **`.env`**: se crea desde `.env.example` si falta (avisa y sale); `scrub_shadowing_env`
  desexporta del proceso las claves del `.env` que el shell traiga (salvo
  `COMPOSE_PROJECT_NAME`); luego se exporta el `.env` completo (`set -a; . ./.env`).
- **Stacks hermanos**: descubre worktrees con `git worktree list --porcelain` y las
  convenciones `<repo>-wt` / `<repo>.worktrees`; con `docker ps --all` y las etiquetas
  `com.docker.compose.project(.working_dir)` selecciona los proyectos del repo y baja
  los distintos del actual.
- **PostgreSQL**: `docker compose up --detach --wait --wait-timeout 60`.
- **JDK**: `resolve_java` usa `JAVA_HOME`, el JBR de Android Studio o `java` del `PATH`;
  si no hay, avisa y sale 0.
- **Migraciones**: `./gradlew --quiet :backend:flywayMigrate` (salvo `--no-migrate`).
- **Backend**: `enable_embeddings_if_available` (E5 en `backend/models/…`), `stop_backend`
  (`pkill -f datopublico.backend.ApplicationKt`) y `start_backend` (`nohup ./gradlew
  --no-daemon --quiet :backend:run > build/dev-up/backend.log`), con `wait_for_health`,
  que exige el **backend propio** (`backend_process_alive` + `backend_is_ours`) hasta
  180 s contra `http://localhost:8080/health` y falla (exit ≠ 0) si no llega a estar
  listo.
- **Cierre**: imprime las instrucciones para Android (`adb reverse`), Web
  (`wasmJsBrowserDistribution`) y cómo parar el backend; remite a
  `docs/desarrollo-local.md`.

> **Nota de reparación (2026-10-18).** Este spec se escribió describiendo el fichero
> entregado en `5cae1a7`. La validación independiente detectó que el health-check podía
> reportar un falso éxito (hallazgo **H3**); la reparación —ya integrada en el contrato
> descrito arriba y en *Scenario 8*— endurece el arranque: exige el **backend propio**
> (`backend_process_alive` + `backend_is_ours`) y **falla** con exit ≠ 0 si no llega a
> estar listo. El fichero resultante sigue siendo el único de producto de la feature.

## Durable Documentation Impact

- `ARCHITECTURE.md`: **update** — `dev-up.sh` es tooling de desarrollo, pero se menciona
  en §«Build y gate» como el camino de un solo comando del entorno local (no cambia
  módulos, fronteras ni superficies de runtime).
- `CONSTRAINTS.md`: **not needed** — no introduce reglas MUST/MUST NOT nuevas (el gate y
  el arranque siguen igual).
- `AGENTS.md`: **not needed** — el camino de arranque/verificación sigue siendo
  `./init.sh`; `dev-up.sh` es una herramienta de entorno local que arranca procesos
  largos (lo que `init.sh` no debe hacer), así que no lo sustituye.
- Other docs: `docs/desarrollo-local.md` (producto) — **update** (documentar
  `./scripts/dev-up.sh` como arranque local de un comando: qué hace, flags, `.env`,
  log del backend y relación con `docker compose` + `:backend:flywayMigrate` +
  `:backend:run`). **Hecho** (sección «Arranque del entorno de desarrollo
  (`scripts/dev-up.sh`)», reparación del 2026-10-18).

## Verification Plan

Desde la raíz del producto (`..`):

- **Sintaxis**: `bash -n scripts/dev-up.sh` → sin errores.
- **Ejecución real (local, con Docker y JDK 21)**:
  ```sh
  cp .env.example .env   # define POSTGRES_PASSWORD
  ./scripts/dev-up.sh
  docker compose ps      # postgres Healthy
  curl -s http://localhost:8080/health    # {"status":"ok"}
  curl -s 'http://localhost:8080/v1/feed?fecha=<ISO>' | jq .
  curl -s 'http://localhost:8080/v1/buscar?q=becas&limite=5' | jq .   # si hay E5
  ```
  Esperado: PostgreSQL `Healthy`, migraciones aplicadas (no-op si ya están), backend
  sirviendo `/health`, `/v1/feed` y `/v1/buscar` (evidencia registrada en `PROGRESS.md`,
  sesiones 082/083).
- **No tocar stacks ajenos**: con un stack `boe-rag`/`vuelantis` arriba, comprobar que
  sus contenedores **no** se bajan.
- **Flags**: `--no-backend` / `--no-migrate` omiten la fase correspondiente.
- **Gate**: `.harness/init.sh` → exit 0; `init.sh` no cambia.
- **E2E**: no aplica — no hay comando E2E persistente; la verificación es la ejecución
  real del script y el gate.

## Evidence To Capture

- `bash -n` sin errores y salida de la ejecución real (Postgres `Healthy`, migraciones
  no-op, `/health` 200, `/v1/feed` y `/v1/buscar` con datos).
- Confirmación de que el stack ajeno no se toca.
- Ficheros del commit `5cae1a7`, PR #43 y confirmación de fusión en `main`.

## Validator Checklist

- [x] `scripts/dev-up.sh` es el único fichero de producto; no modifica
      `docker-compose.yml`/`.env.example`/migraciones/backend/cliente.
- [x] Levanta Postgres/pgvector, aplica Flyway y arranca el backend esperando a que
      responda el **backend propio**; habilita E5 si está el modelo.
- [x] Baja solo stacks Compose del **mismo** repositorio/worktrees; **no** toca otros
      proyectos (verificado con `vuelantis`/`boe-rag` arriba).
- [x] `.env` es la fuente de verdad; no se versionan secretos; `--no-backend`/
      `--no-migrate` funcionan.
- [x] `bash -n` OK y el gate (`init.sh`) sin cambios; `docs/desarrollo-local.md`
      actualizado.
- [x] El arranque **no** reporta falso éxito: rechaza un `200` ajeno, exige el backend
      propio y falla con exit ≠ 0 sin imprimir «Listo» (banco aislado del validador:
      14 PASS / 0 FAIL).

## Risks / Open Questions

- **Puerto `8080` fijo y ocupado por proyectos ajenos.** El script espera en
  `http://localhost:8080/health` (puerto por defecto del backend) y solo baja stacks del
  **mismo** repositorio; un proyecto externo que ocupe `8080` (observado con `vuelantis`
  en sesión 082) **no** lo resuelve el script. Desde la reparación del 2026-10-18 el
  conflicto **se detecta y se reporta** (el health-check exige el backend propio y falla
  con error claro), pero no se parametriza el puerto. Decidir si se debe parametrizar.
- **`wait_for_health` (resuelto).** La versión entregada en `5cae1a7` solo avisaba si el
  backend no respondía; desde la reparación del 2026-10-18 la versión **estricta es el
  contrato** (ver *Scenario 8*): exige el backend propio y falla con exit ≠ 0.
- **`docs/desarrollo-local.md` (resuelto).** El impacto documental quedó **cerrado**: el
  documento ya describe `dev-up.sh` (sección propia).
- **Dependencias de entorno del script**: `docker` (Compose v2), `git`, JDK 21 (o JBR),
  `curl`, `pgrep`/`pkill` y convenciones de worktrees (`<repo>-wt` / `<repo>.worktrees`).
  Fuera de ese entorno (p. ej. sin `pkill`) no está cubierto.
