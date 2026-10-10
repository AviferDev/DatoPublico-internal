# Feature Implementation Spec: PostgreSQL + pgvector en docker-compose

## Source Feature

- `id`: bootstrap-postgres-pgvector
- `ft_id`: FT00003
- `parts`: none (atomic)
- `area`: fundaciones
- `depends_on`: bootstrap-monorepo-gradle (FT00001, `accepted`)
- `status`: not_started (a planificar; rama `feat/ft00003-bootstrap-postgres-pgvector` ya reclamada)
- `source`: `feature_list.json`

## Goal

Dejar un **entorno local reproducible de base de datos**: un `docker-compose.yml`
que levanta **PostgreSQL con la extensión `pgvector`** y una **migración base de
Flyway** (`CREATE EXTENSION IF NOT EXISTS vector;` + una tabla mínima) que se
aplica sin errores. Define además **cómo se ejecuta Flyway** desde el repo
(plugin de Gradle) de forma que **no rompa la CI**, que corre en `ubuntu-latest`
**sin base de datos**. Es la base de `docs/roadmap.md` 0.1-T04 y el punto de apoyo
de la persistencia (FT00008), el indexado vectorial (FT00016) y el backend
(FT00004).

## Non-Goals

- **Tablas de dominio** (`publicacion`, `fragmento`, `resumen`, `cola_revision`) y
  repositorios → FT00008; **columna de embedding, índice HNSW y dimensión 384** →
  FT00016.
- **Ktor, healthcheck, configuración por entorno y logging del servidor** →
  FT00004.
- **Despliegue en producción** (Dockerfile del backend, Nginx, HTTPS, secretos
  reales, backups) → FT00041/FT00042.
- **Guía de arranque del README** (0.1-T07) y ajuste fino de `shared_buffers` del
  N100 para producción.

## Job Story

Cuando desarrollo el backend o la ingesta, quiero levantar PostgreSQL con
pgvector y aplicar las migraciones con un comando reproducible, para trabajar
sobre un esquema versionado sin tocar una base real y sin que el build de CI
dependa de un servicio externo.

## Users And Permissions

- Desarrollador (único actor): levanta la BD con `docker compose up -d` y aplica
  migraciones con `./gradlew :backend:flywayMigrate`. Sin cuentas ni datos
  personales; los secretos de producción no entran aquí (FT00041).

## Acceptance Scenarios

### Scenario 1: la base arranca y responde

Given Docker/Colima operativo y un `.env` local (o los valores por defecto),
When ejecuto `docker compose up -d`,
Then el contenedor `postgres` queda `healthy` y
`psql -c 'SELECT 1;'` devuelve `1`.

### Scenario 2: pgvector está disponible

Given la base levantada desde la imagen con pgvector,
When aplico la migración base,
Then `SELECT extversion FROM pg_extension WHERE extname = 'vector';` devuelve una
versión no vacía (la extensión se creó con `CREATE EXTENSION IF NOT EXISTS vector`).

### Scenario 3: Flyway aplica la migración base

Given la base levantada y las variables de conexión resueltas,
When ejecuto `./gradlew :backend:flywayMigrate`,
Then termina en `BUILD SUCCESSFUL`, `flyway_schema_history` registra `V1` en
estado `Success` y existe la tabla mínima creada por la migración.

### Scenario 4: la CI sigue verde sin base de datos

Given el runner `ubuntu-latest` **sin PostgreSQL**,
When ejecuto `./gradlew build --no-daemon` (o `./init.sh`),
Then el build pasa: las tareas de Flyway **no** están enganchadas a
`build`/`check` y no se conectan a ninguna base.

## Repository Research

### Files Inspected

- `.harness/feature_list.json` (FT00003), `PROGRESS.md` (Sessions 008–016),
  `docs/feature-ids.md` — estado real: FT00001/FT00002 `accepted`; siguiente
  feature `bootstrap-postgres-pgvector`.
- `.harness/docs/roadmap.md` §0.1.0 (`0.1-T04`), `docs/technical-discovery.md`
  (PostgreSQL + pgvector + Flyway), `ARCHITECTURE.md` (Datos: PostgreSQL +
  pgvector, Flyway; convenciones de nombres) y `CONSTRAINTS.md` (migraciones
  versionadas, secretos por entorno).
- Skill `ktor-backend-architecture` (persistencia, layout
  `backend/src/main/resources/db/migration/`, Docker/Colima, CI).
- Producto `..`: `settings.gradle.kts` (`:shared`, `:backend`, `:composeApp`),
  `build.gradle.kts` raíz (plugins `apply false` + task raíz `test`),
  `gradle/libs.versions.toml` (sin Flyway/JDBC/Hikari),
  `backend/build.gradle.kts` (Kotlin JVM vacío, `implementation(project(":shared"))`),
  `.github/workflows/ci.yml` (`./gradlew build --no-daemon`, sin BD),
  `.gitignore` (sin `.env`), `.harness/init.sh` (gate no bloqueante).
- `git branch`/`git ls-remote` → rama `feat/ft00003-bootstrap-postgres-pgvector`
  en local y `origin` (claim hecho). Docker 29.8.2 y Compose v5.6.0 disponibles.

### Existing Patterns To Follow

- Version catalog + Kotlin DSL; plugins raíz declarados `apply false`; migraciones
  en `backend/src/main/resources/db/migration/` con nombres `V1__descripcion.sql`
  (**nunca** editar una ya aplicada).
- Nombres de BD en **castellano snake_case** (`publicacion`, `fragmento`…);
  secretos por entorno (`.env` ignorado); commits con scope `FT00003`.

### Current Gaps

- No existe `docker-compose.yml`, ni `.env.example`, ni `.env` en `.gitignore`,
  ni directorio de migraciones.
- No hay Flyway (plugin ni dependencia), ni driver PostgreSQL, ni Hikari.
- `:backend` no tiene `main` ni `application` plugin (llega en FT00004).

## Technical Approach

1. **PostgreSQL + pgvector con Docker Compose** (`docker-compose.yml` en la raíz):
   - Imagen **`pgvector/pgvector:pg17`** (imagen oficial de pgvector, multi-arq
     para Apple Silicon/Colima). Fijar la etiqueta exacta elegida en el fichero y
     anotarla en la evidencia.
   - Servicio `postgres`: `POSTGRES_DB`/`POSTGRES_USER`/`POSTGRES_PASSWORD` por
     entorno (valores por defecto de desarrollo, no secretos reales), puerto host
     configurable (`${POSTGRES_PORT:-5432}`), volumen nombrado `pgdata` para
     persistencia y `healthcheck` con `pg_isready`.
   - `.env.example` en la raíz con las claves documentadas; añadir `.env` a
     `.gitignore` (MUST: secretos por entorno).
2. **Migración base de Flyway** en
   `backend/src/main/resources/db/migration/V1__esquema_base.sql`:
   - `CREATE EXTENSION IF NOT EXISTS vector;`
   - Una **tabla mínima** neutra, `esquema_info (clave text PK, valor text NOT
     NULL, actualizado_en timestamptz NOT NULL DEFAULT now())` con una fila
     marcadora. No se crean tablas de dominio (FT00008).
3. **Ejecución de Flyway = plugin Gradle `org.flywaydb.flyway` en `:backend`**
   (`flywayMigrate` / `flywayInfo`), con `url`/`user`/`password` resueltos de
   entorno (`FLYWAY_*`) con valores por defecto de desarrollo. Se añaden al
   catálogo el plugin, el driver `org.postgresql:postgresql` y
   `org.flywaydb:flyway-database-postgresql` (Flyway 10+ requiere el módulo por
   motor) en la configuración `flyway`.
   - **Clave para la CI:** la tarea `flywayMigrate` es explícita y **no** se
     engancha a `build`/`check`; el build de CI nunca se conecta a la BD.
   - Alternativa descartada como mecanismo principal: servicio `flyway` de
     Compose (one-shot); se mantiene el plugin por coherencia con la skill de
     backend y para reutilizar las migraciones en FT00004.

**Riesgos clave:** CI sin BD (tarea Flyway explícita, no enganchada a
`build`/`check`); imagen oficial con etiqueta fijada; Flyway 10+ exige
`flyway-database-postgresql`; puerto 5432 configurable por `.env`; `CREATE
EXTENSION` requiere superusuario (lo es en la imagen oficial).

### Nota de implementación (2026-10-10)

Hallazgos al implementar (no cambian el alcance):

- El plugin de Flyway **no** crea una configuración `flyway` por sí mismo (en la
  11.x usa `compileClasspath`/`runtimeClasspath` por defecto). En `:backend` se
  crea una configuración `flyway` explícita, se añaden el driver PostgreSQL y
  `flyway-database-postgresql`, y la extensión la referencia con
  `configurations = ["flyway"]`.
- El módulo `org.flywaydb:flyway-database-postgresql` debe estar **además** en el
  `buildscript` classpath de `:backend`: Flyway lo resuelve por ServiceLoader
  desde el build classpath y, sin él, la tarea falla con `No Flyway database
  plugin found to handle jdbc:postgresql...`. La versión queda fijada a la del
  plugin (`11.20.3`).
- `.gitignore` incluye `!.env.example` porque un `.env.*` local (`info/exclude`)
  excluía la plantilla; así la plantilla siempre es versionable.


### Nota de reparación de seguridad (2026-10-10, reapertura)

Hallazgo tras la aceptación: había una **credencial de desarrollo versionada** y
un default silencioso inseguro. Reparación (sin cambiar el alcance funcional):

- `backend/build.gradle.kts`: eliminado el *fallback* literal
  (`password = System.getenv("FLYWAY_PASSWORD") ?: "datopublico"`). La conexión
  `FLYWAY_*` se resuelve del entorno y, si no está definida, del `.env` de la
  raíz (parser mínimo `clave=valor`, nunca imprime valores). `url`/`user`
  conservan default no sensible; **`password` no**: si falta tras cargar `.env`,
  la tarea Flyway falla con `FLYWAY_PASSWORD no definido: copia .env.example a
  .env o expórtalo`. La validación se hace en **tiempo de ejecución** (`doFirst`
  sobre las tareas Flyway) porque la extensión del plugin usa `String` (no un
  `Provider`); así `./gradlew build` sigue verde sin `.env` ni base de datos.
- `docker-compose.yml`: `POSTGRES_PASSWORD` **obligatorio**
  (`${POSTGRES_PASSWORD:?define POSTGRES_PASSWORD en .env}`); puerto publicado
  **solo en loopback** (`127.0.0.1:${POSTGRES_PORT:-5432}:5432`).
- `.env.example`: `POSTGRES_PASSWORD`/`FLYWAY_PASSWORD` con *placeholder*
  explícito de desarrollo (`cambia_esta_clave_local`), documentado como no
  secreto; comentario de `FLYWAY_*` actualizado (el build ya no tiene default de
  contraseña).
- `CONSTRAINTS.md`: MUST de no versionar credenciales (ni de desarrollo),
  fail-fast ante secreto ausente y Postgres local solo en loopback.

Escenarios y ficheros del spec no cambian; el comportamiento observable es el
mismo con `.env` presente y **más seguro** cuando falta.

### Nota de reparación de configuración de conexión (2026-10-10, reapertura)

Hallazgo L2 del validador: `.env.example` fijaba `FLYWAY_URL` a
`jdbc:postgresql://localhost:5432/datopublico` y `FLYWAY_PASSWORD` duplicaba el
valor de `POSTGRES_PASSWORD`; cambiar `POSTGRES_PORT` no llegaba a Flyway.
Reparación (sin cambiar el alcance funcional):

- `backend/build.gradle.kts`: la conexión se **deriva** de las piezas con
  `FLYWAY_*` como *override* opcional: `host = FLYWAY_HOST ?: POSTGRES_HOST ?
  "localhost"`, `port = FLYWAY_PORT ?: POSTGRES_PORT ?: "5432"`,
  `db = FLYWAY_DB ?: POSTGRES_DB ?: "datopublico"`,
  `user = FLYWAY_USER ?: POSTGRES_USER ?: "datopublico"`,
  `password = FLYWAY_PASSWORD ?: POSTGRES_PASSWORD` (fail-fast si falta) y
  `url = FLYWAY_URL ?: "jdbc:postgresql://$host:$port/$db"`. Se conservan el
  cargador de `.env` de la raíz y la validación en `doFirst` (así `build`/`check`
  siguen verdes sin BD) y no se imprimen valores.
- `.env.example`: solo `POSTGRES_*` como **fuente única de verdad** (obligatoria
  `POSTGRES_PASSWORD`; `POSTGRES_PORT` opcional con default 5432); `FLYWAY_*`
  documentadas como *overrides* opcionales (comentadas), sin duplicar la
  contraseña.
- `CONSTRAINTS.md`: MUST de no duplicar la configuración de conexión entre
  herramientas (una sola fuente `POSTGRES_*`; `FLYWAY_*` solo *override*).

Escenarios 1–4 y ficheros del spec no cambian; el comportamiento observable es el
mismo con un `.env` de solo `POSTGRES_*` y **coherente** al cambiar el puerto.

### Nota de limpieza de comentarios (2026-10-10)

Petición de estilo (sin cambiar comportamiento): dejar los comentarios de código
al mínimo y mover lo explicativo a un Markdown.

- Nuevo `docs/desarrollo-local.md` (repo de producto): requisitos (JDK 21,
  Docker/Colima), arranque de la BD (`.env` + `docker compose up -d`), migraciones
  Flyway (`:backend:flywayMigrate`/`:backend:flywayInfo`, fuera de `build`/`check`),
  variables (`POSTGRES_*` fuente única; `FLYWAY_*` *overrides*; URL derivada) y
  notas (módulo `flyway-database-postgresql` en el buildscript, loopback,
  fail-fast sin credenciales). Enlazado desde `README.md`.
- `backend/build.gradle.kts`: eliminado el bloque de cabecera y los comentarios
  largos; quedan 4 comentarios de **una línea** en lo no obvio (buildscript,
  parser de `.env`, `flywayPasswordOrFail` y `doFirst`). Sin cambios en
  `buildscript`/`dependencies`/lógica.
- `docker-compose.yml`: eliminado el bloque de cabecera; queda un comentario de
  una línea (`# Solo loopback.`). Sin cambios funcionales.
- `.env.example`: eliminado el bloque de cabecera; quedan comentarios mínimos de
  una línea por clave. Sin cambios en las claves.

## Expected File Changes

Rutas en el repo de producto (`..`):

- `docker-compose.yml` — create; servicio `postgres` (pgvector) + volumen +
  healthcheck.
- `.env.example` — create; claves `POSTGRES_*` documentadas (sin secretos).
- `.gitignore` — modify; añadir `.env`.
- `gradle/libs.versions.toml` — modify; versiones/aliases de Flyway, driver
  PostgreSQL y `flyway-database-postgresql`.
- `backend/build.gradle.kts` — modify; aplicar el plugin Flyway, configurar
  `flyway { … }` y añadir dependencias a la configuración `flyway`.
- `backend/src/main/resources/db/migration/V1__esquema_base.sql` — create;
  extensión `vector` + tabla mínima.

No se toca la raíz del build, `:shared`, `:composeApp` ni `.github/workflows/ci.yml`
(la CI no cambia: debe seguir verde sin BD).

## Visual Design Impact

- UI involved: no. Sin pantallas, tokens ni textos de UI.

## Durable Documentation Impact

- `ARCHITECTURE.md` (harness): not needed — ya describe PostgreSQL + pgvector y
  las migraciones Flyway.
- `CONSTRAINTS.md`: update — añadir un MUST durable: el gate de build/tests
  (`./gradlew build`, `init.sh`) **no** depende de servicios externos (BD); las
  migraciones se ejecutan con una tarea explícita.
- `AGENTS.md` (harness): not needed — no cambia flujo ni arranque.
- Otros: `README.md`/`ROADMAP.md` públicos — not needed; la guía de arranque es
  0.1-T07.

## Implementation Plan

1. Crear `docker-compose.yml`, `.env.example` y añadir `.env` a `.gitignore`.
2. Añadir Flyway + driver PostgreSQL + módulo de Postgres al version catalog y
   aplicar el plugin Flyway en `:backend` configurado por entorno, sin
   engancharlo a `build`/`check`.
3. Escribir `V1__esquema_base.sql` (extensión `vector` + tabla mínima) y
   verificar los escenarios 1–4 (BD arriba y `./gradlew build` sin BD).
4. Actualizar `CONSTRAINTS.md`/`PROGRESS.md`/`feature_list.json` y abrir el PR
   `FT00003`.

## Implementation Tasks

- [ ] `docker-compose.yml` con `pgvector/pgvector:pg17`, volumen, healthcheck y
      puerto configurable.
- [ ] `.env.example` (claves `POSTGRES_*`) y `.env` en `.gitignore`.
- [ ] Version catalog: plugin `org.flywaydb.flyway`, `org.postgresql:postgresql`
      y `org.flywaydb:flyway-database-postgresql`.
- [ ] `:backend`: aplicar plugin Flyway y configurar `url`/`user`/`password` por
      entorno.
- [ ] `V1__esquema_base.sql`: `CREATE EXTENSION IF NOT EXISTS vector;` + tabla
      mínima `esquema_info`.
- [ ] `docker compose up -d` → `healthy` + `SELECT 1`.
- [ ] `./gradlew :backend:flywayMigrate` + `:backend:flywayInfo` en verde.
- [ ] `./gradlew build` (sin BD) en verde y `flywayMigrate` fuera del grafo de
      `build`.
- [ ] `CONSTRAINTS.md`, `PROGRESS.md`, `feature_list.json` actualizados.

## Verification Plan

Desde la raíz del producto (`..`, JDK 21 vía JBR/`JAVA_HOME`):

- `docker compose up -d` → `docker compose ps` muestra `postgres` `healthy`, y
  `docker compose exec postgres psql -U datopublico -d datopublico -c 'SELECT 1;'`
  devuelve `1`.
- `./gradlew :backend:flywayMigrate` → `BUILD SUCCESSFUL`;
  `./gradlew :backend:flywayInfo` → `V1` en `Success`.
- `docker compose exec postgres psql -U datopublico -d datopublico -c "SELECT extversion FROM pg_extension WHERE extname='vector';"`
  → versión no vacía; y `SELECT * FROM esquema_info;` devuelve la fila marcadora.
- **CI sin BD**: `docker compose down` y luego `./gradlew build --no-daemon` →
  `BUILD SUCCESSFUL`; `./gradlew build --dry-run | grep -i flyway` → sin
  resultados (tarea no enganchada).
- `./init.sh` sigue siendo el gate no bloqueante (`./gradlew build`) y no arranca
  servicios. E2E: no aplica (sin flujo de usuario ni API).

## Evidence To Capture

- Salida de `docker compose ps` (healthy), de `psql 'SELECT 1;'`, de
  `flywayMigrate`/`flywayInfo` y fila de `flyway_schema_history` con `V1` en
  `Success`; `extversion` de `vector` y fila de `esquema_info`.
- Etiqueta de imagen (`pgvector/pgvector:…`) y versiones fijadas de Flyway/driver;
  `./gradlew build` en verde con la BD parada (prueba de CI sin BD); ficheros del
  commit `FT00003`, PR, CI y entradas en `PROGRESS.md`/`feature_list.json`.

## Validator Checklist

- [ ] Implementation stays within scope (sin tablas de dominio, sin Ktor, sin
      índice HNSW ni embedding).
- [ ] Escenarios 1–4 pasan (base `healthy`, `vector` disponible, migración
      aplicada, CI/build verde sin BD).
- [ ] La migración base existe y aplica; `CREATE EXTENSION IF NOT EXISTS vector;`
      funciona.
- [ ] `flywayMigrate` es explícita y **no** está enganchada a `build`/`check`.
- [ ] No hay secretos en el repositorio; `.env` ignorado y `.env.example` sin
      valores sensibles.
- [ ] `CONSTRAINTS.md`, `feature_list.json` y `PROGRESS.md` actualizados
      correctamente.
- [ ] No unrelated product behavior or extra feature work was added.
