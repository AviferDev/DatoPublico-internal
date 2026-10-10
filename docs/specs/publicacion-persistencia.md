# Feature Implementation Spec: Persistencia de publicaciones, fragmentos y resúmenes

## Source Feature

- `id`: publicacion-persistencia
- `ft_id`: FT00008
- `parts`: none (atómica; ~21 ficheros, por debajo del límite de 30)
- `area`: ingesta-boe
- `depends_on`: bootstrap-postgres-pgvector (FT00003, `accepted`), boe-parser-publicacion (FT00007, `accepted`)
- `status`: accepted (implementada y validada de forma independiente 2026-10-10; rama `feat/ft00008-publicacion-persistencia`)
- `source`: `feature_list.json`

> **Nota de coherencia con FT00007/FT00012.** El parser (FT00007) deja a propósito
> `categoria = null`; la clasificación curada y la extracción de plazos son
> **FT00012**. La persistencia no espera a FT00012: crea ya las columnas
> (`categoria`, `plazo_*`) **nullable** y guarda/recupera lo que el modelo lleve.
> FT00012 rellenará esos valores a través del mismo repositorio.

## Decisiones de planificación (resueltas)

1. **Esquema (migración V2 nueva; V1 intacta).** Una única migración
   `V2__persistencia_publicaciones.sql` crea `publicacion`, `fragmento`, `resumen`
   y `cola_revision` con sus PK/FK/índices. Lo **diferido** se deja fuera:
   - la **columna de embedding** de `fragmento` y su índice **HNSW 384 dims** → **FT00016**;
   - los **valores** de `categoria` y `plazo` → **FT00012** (columnas presentes, nullable);
   - el versionado/consolidación de publicaciones → FT00009 (la escritura ya es
     *upsert* por `id`).
2. **`categoria`/`plazo` en el esquema.** Se modelan ahora: `publicacion.categoria`
   (text, nullable), `publicacion.plazo_fecha_limite` (date, null) y
   `publicacion.plazo_descripcion` (text, null). El parser las deja nulas; el
   repositorio las persiste y las devuelve. `Publicacion` gana un campo
   `plazo: PlazoDto? = null` (aditivo) para poder cumplir el "guarda y recupera…
   con plazo". `seccion` (text, NOT NULL) y `epigrafe` (text, nullable) ya vienen
   de FT00007.
3. **Capa de datos: JDBC + HikariCP, sin ORM.** El pool y la config de conexión
   viven en `infra/`; los **repositorios** en un paquete transversal
   `persistence/` (el esquema es compartido por ingesta/RAG/resumen). Interfaz de
   repositorio + implementación JDBC en el mismo fichero (precedente
   `BoePublicacionParser.kt`) y **entidad de persistencia `...Entity`** como
   representación de fila; el repositorio habla modelos internos (`Publicacion`).
   **Sin wiring en el arranque** (`Application.kt` intacto).
4. **Test sin BD.** El gate **no** puede ejecutar la verificación real
   (guardar/recuperar y existencia de tablas) sin PostgreSQL (MUST de
   `CONSTRAINTS.md`). Estrategia: (a) prueba **opt-in** `DB_LIVE_TEST=1` contra el
   Postgres de `docker-compose` (patrón `BOE_LIVE_TEST`), que guarda/recupera y
   comprueba las cuatro tablas en `information_schema`; (b) en el gate, tests
   **sin BD** (config de conexión, mapeo `Publicacion`↔`PublicationEntity` y
   contrato SQL de la migración). Límite documentado en *Risks*.

## Goal

Añadir en `:backend` la **capa de persistencia** sobre PostgreSQL: la migración
Flyway que crea las tablas `publicacion`, `fragmento`, `resumen` y `cola_revision`,
y los **repositorios JDBC** (HikariCP) que guardan y recuperan esos datos. Es la
base de `docs/roadmap.md` 0.2-T03: el job diario (FT00009) y la clasificación
(FT00012) escribirán publicaciones a través de estos repositorios; el chunking
(FT00014), la generación de resúmenes (FT00019) y la cola de revisión (FT00023)
enriquecerán su comportamiento.

La feature **no** se cablea en el arranque del servidor, **no** ingiere, **no**
clasifica, **no** fragmenta y **no** genera resúmenes: es la capa de acceso a datos
con sus tests.

## Non-Goals

- **Categorización curada y plazos** (valores) → FT00012. Las columnas existen;
  los valores llegan después.
- **Columna de embedding `vector(384)` + índice HNSW** en `fragmento` → FT00016.
- **Job programado**, idempotencia end-to-end, segunda pasada, backfill,
  deduplicación → FT00009/FT00011.
- **Chunking** (definir fragmentos) → FT00014; **generación** de resúmenes con IA
  → FT00019/FT00020; **guardrails/confianza** → FT00022/FT00023.
- **Wiring en el arranque**, endpoints HTTP y migración automática al arrancar →
  features posteriores (`Application.kt` intacto).
- **ORM** (Exposed/Hibernate): se usa JDBC + HikariCP (decisión durable → ADR).
- **Transacciones multi-repositorio / unit of work**: cada método abre su conexión
  (autocommit); la transacción lógica llega con FT00014/FT00019.

## Job Story

Cuando implemento la ingesta del BOE,
quiero guardar y recuperar publicaciones, fragmentos, resúmenes y entradas de la
cola de revisión en PostgreSQL mediante repositorios,
para que el job, la clasificación y el RAG operen sobre datos persistidos y
consultables sin reescribir SQL en cada feature.

## Users And Permissions

- Desarrollador / job de ingesta (interno): invoca los repositorios desde código
  de `:backend`. Sin cuentas, sin datos personales, sin autenticación. La conexión
  usa las variables `POSTGRES_*` (fuente única, como Flyway y `docker-compose`) y
  **fail-fast** si falta la contraseña.

## Acceptance Scenarios

### Scenario 1: guardar y recuperar una publicación con sus metadatos

Given una base PostgreSQL (imagen pgvector del `docker-compose`) con las
migraciones aplicadas y los repositorios construidos sobre el pool,
When se guarda una `Publicacion` con `seccion`, `epigrafe`, `categoria` y `plazo`
no nulos y luego se recupera por su `id`,
Then la publicación recuperada es **igual** a la guardada (todos los metadatos,
texto y URLs), incluidos `categoria` y `plazo`.

### Scenario 2: las cuatro tablas existen vía migración Flyway

Given las migraciones aplicadas con `./gradlew :backend:flywayMigrate`,
When se consulta el catálogo (`information_schema.tables` / `flyway_schema_history`),
Then existen las tablas `publicacion`, `fragmento`, `resumen` y `cola_revision` y
la migración `V2` figura en `Success` (V1 intacta).

### Scenario 3: upsert idempotente de publicación

Given una publicación ya guardada,
When se vuelve a guardar con el mismo `id` y un título actualizado,
Then no se crea una segunda fila y se actualiza la existente (`actualizado_en`
avanzado) — habilita la idempotencia de FT00009.

### Scenario 4: metadatos opcionales nulos

Given una `Publicacion` con `categoria`, `plazo`, `organismo`, `epigrafe`, `texto`
y `urlXml` nulos (caso del parser FT00007 antes de FT00012),
When se guarda y se recupera,
Then la recuperada conserva los nulos sin excepción (columnas nullable).

### Scenario 5: fragmento, resumen y cola de revisión (guardar/recuperar mínimo)

Given una publicación persistida,
When se guarda un `FragmentEntity`, un `SummaryEntity` y una entrada de
`ReviewQueueEntity` ligados a ella y se leen por su publicación/resumen,
Then los datos se recuperan íntegros y las FK (`ON DELETE CASCADE`) están activas.

### Scenario 6: el gate sigue sin depender de la base de datos

Given el runner de CI **sin PostgreSQL** y Docker parado,
When se ejecuta `./gradlew build -PskipClient`, `./gradlew test`, `./gradlew detekt`
o `.harness/init.sh`,
Then todo está en verde (los repositorios **no** se cablean al arranque y los tests
reales de BD son opt-in).

## Repository Research

### Files Inspected

- `.harness/feature_list.json` (FT00008; FT00003/FT00007 `accepted`),
  `PROGRESS.md` (estado verificado), `docs/feature-ids.md` (FT00008 registrado),
  `docs/roadmap.md` §0.2.0 (`0.2-T03`), `docs/domain-model.md` (Publicación,
  Fragmento, Resumen ciudadano, Cola de revisión, estados), `docs/technical-
  discovery.md` (Data and Storage), `ARCHITECTURE.md`, `CONSTRAINTS.md`,
  `docs/git-workflow.md` (claim/límite de 30), `docs/adr/0002` (fuente de texto) y
  la skill `ktor-backend-architecture` (persistencia JDBC + HikariCP, layout).
- Producto `..`: `backend/build.gradle.kts` (plugin Flyway, config `flyway`,
  driver PostgreSQL solo en la config `flyway`, sin JDBC/Hikari), `V1__esquema_base.sql`
  (extensión `vector` + `esquema_info`; sin tablas de dominio), `gradle/libs.versions.toml`
  (`postgresql = 42.7.14`, sin Hikari), `Application.kt` (composition root sin BD),
  `infra/AppConfig.kt`, `ingesta/sumario/EntradaSumario.kt`,
  `ingesta/publicacion/{Publicacion,DocumentoBoe,PublicacionParser,BoePublicacionParser}.kt`,
  DTOs de `:shared` (`PublicacionDto`, `ResumenDto`, `PlazoDto`, `CategoriaDto`,
  `SeccionBoeDto`), `docs/desarrollo-local.md`, `docker-compose.yml`,
  `.env.example` (`POSTGRES_*` fuente única).
- `git branch`/`git ls-remote`: rama `feat/ft00008-publicacion-persistencia`
  reclamada (local y `origin`). Sin ficheros aún.

### Existing Patterns To Follow

- **Migraciones** Flyway en `backend/src/main/resources/db/migration/`
  (`V1__esquema_base.sql`; **nunca** editar una aplicada) con `CREATE EXTENSION`
  ya hecho en V1; nombres en castellano snake_case.
- **Config por entorno** con `fromEnv(env: Map<String,String> = System.getenv())`
  y **fail-fast** (patrón `AppConfig`); sin secretos versionados; `POSTGRES_*` como
  **fuente única** (Flyway/Compose).
- **Feature-first**: interfaz + impl en el mismo fichero (`BoePublicacionParser.kt`,
  `BoeTextoClient.kt`); modelo interno sin sufijo (`EntradaSumario`), entidades de
  persistencia `...Entity`; KDoc obligatorio; `return` único, sin `else if`,
  ≤40 líneas/función.
- **Tests** `kotlin.test` en espejo del paquete; fixtures en `src/test/resources`;
  opt-in por variable de entorno (`BOE_LIVE_TEST=1`) fuera del gate, sin abrir
  sockets si falta.

### Current Gaps

- No existe `persistence/` ni pool JDBC/Hikari; el driver PostgreSQL solo está en
  la configuración `flyway` (fuera del classpath de producción).
- No existen tablas de dominio (`publicacion`, `fragmento`, `resumen`,
  `cola_revision`).
- `Publicacion` no tiene campo `plazo`.

## Technical Approach

1. **Migración `V2__persistencia_publicaciones.sql`** (no editar V1). Esquema
   propuesto (el implementador puede ajustar nombres de índice libremente):
   - `publicacion`: `id text PK`, `titulo text NOT NULL`, `fecha_publicacion date
     NOT NULL`, `organismo text`, `seccion text NOT NULL`, `epigrafe text`,
     `categoria text` (FT00012), `texto text`, `url_oficial text NOT NULL`,
     `url_xml text`, `url_pdf text`, `rango text`, `plazo_fecha_limite date`
     (FT00012), `plazo_descripcion text`, `creado_en timestamptz NOT NULL DEFAULT
     now()`, `actualizado_en timestamptz NOT NULL DEFAULT now()`; índices por
     `fecha_publicacion`, `seccion`, `categoria`, `organismo`.
   - `fragmento`: `id bigint identity PK`, `publicacion_id text NOT NULL
     REFERENCES publicacion(id) ON DELETE CASCADE`, `orden integer NOT NULL`,
     `referencia text`, `contenido text NOT NULL`, `creado_en timestamptz`; `UNIQUE
     (publicacion_id, orden)`. **Sin** columna de embedding (→ FT00016).
   - `resumen`: `id bigint identity PK`, `publicacion_id text NOT NULL UNIQUE
     REFERENCES publicacion(id) ON DELETE CASCADE`, `que_cambia text NOT NULL`,
     `a_quien_afecta text NOT NULL`, `cifras_clave text[] NOT NULL DEFAULT '{}'`,
     `fuente_oficial text NOT NULL`, `aviso_ia boolean NOT NULL DEFAULT true`,
     `estado text NOT NULL DEFAULT 'pendiente'`, `confianza numeric`,
     `creado_en`/`actualizado_en`. UNIQUE por publicación (1:1, sin versionado).
   - `cola_revision`: `id bigint identity PK`, `resumen_id bigint NOT NULL
     REFERENCES resumen(id) ON DELETE CASCADE`, `motivo text`, `estado text NOT
     NULL DEFAULT 'pendiente'`, `creado_en timestamptz`, `revisado_en timestamptz`;
     índice por `estado`.
   - **Embedding/HNSW y valores de categoría/plazo quedan fuera** (FT00016/FT00012).
2. **`infra/DatabaseConfig.kt`**: `data class DatabaseConfig(url, usuario,
   password)` + `fromEnv(env)` que **deriva** la URL de `POSTGRES_*`
   (`jdbc:postgresql://host:port/db`, defaults no sensibles) y **fail-fast** si
   falta `POSTGRES_PASSWORD` (mismo mensaje/patrón que Flyway). Puro y testeable
   en el gate.
3. **`infra/Database.kt`**: factory que construye un `HikariDataSource` a partir de
   `DatabaseConfig` (pool pequeño: `maximumPoolSize` ~5). No se
   invoca en el arranque; el consumidor (test/job) lo crea y lo cierra.
4. **Paquete `persistence/`** con un fichero por agregado (interfaz + entidad +
   impl JDBC):
   - `PublicationRepository.kt`: interfaz `PublicationRepository { save(p):
     Publicacion; findById(id): Publicacion?; listByDate(fecha): List<Publicacion> }`
     + `PublicationEntity` (fila) + `PublicationRepositoryJdbc(dataSource)` con
     SQL parametrizado y *upsert* `INSERT … ON CONFLICT (id) DO UPDATE`.
     Mapeo `Publicacion` ↔ `PublicationEntity` (fechas ISO `String` ↔ `date`;
     `seccion`/`categoria` como `text` con el nombre del enum; `plazo` ↔ dos
     columnas).
   - `FragmentRepository.kt`, `SummaryRepository.kt`, `ReviewQueueRepository.kt`:
     **mínimos** (guardar + leer por publicación/resumen), operando sobre su
     `...Entity` provisional. KDoc avisa de que su modelo de dominio y su
     comportamiento llegan con FT00014/FT00019/FT00023.
   - `cifras_clave` (`text[]`) se mapea con `connection.createArrayOf` o
     `getArray`/`java.sql.Array`.
5. **Ajuste aditivo de dominio**: `Publicacion` añade `val plazo: PlazoDto? = null`
   (KDoc: relleno en FT00012), reutilizando `PlazoDto` de `:shared` como ya se
   reutilizan `SeccionBoeDto`/`CategoriaDto`.
6. **Sin wiring**: `Application.kt`, `:shared`, `:composeApp`, la raíz del build y
   el CI quedan intactos salvo `libs.versions.toml`/`backend/build.gradle.kts`.

**Riesgos clave:** (a) el gate no puede probar contra BD — mitigado con opt-in +
tests SIN BD (config/mapeo/contrato SQL); (b) `categoria`/`plazo` aún no los
produce la ingesta — columnas nullable y prueba que las fija a mano; (c) el embedding
de `fragmento` es de FT00016 — no debe aparecer aquí; (d) driver PostgreSQL hoy
solo en la config `flyway` — hay que añadirlo a `implementation` para JDBC de
producción; (e) alcance amplio (4 tablas) — repositorios secundarios mínimos,
posible división si crecen.

## Expected File Changes

Rutas en el repo de producto (`..`):

- `gradle/libs.versions.toml` — modify; versión/alias `hikari` (`com.zaxxer:HikariCP`).
- `backend/build.gradle.kts` — modify; `implementation(libs.postgresql)` +
  `implementation(libs.hikari)` (la config `flyway` no cambia).
- `backend/src/main/resources/db/migration/V2__persistencia_publicaciones.sql` — create.
- `backend/src/main/kotlin/…/backend/infra/DatabaseConfig.kt` — create.
- `backend/src/main/kotlin/…/backend/infra/Database.kt` — create.
- `backend/src/main/kotlin/…/backend/persistence/PublicationRepository.kt` — create.
- `backend/src/main/kotlin/…/backend/persistence/FragmentRepository.kt` — create.
- `backend/src/main/kotlin/…/backend/persistence/SummaryRepository.kt` — create.
- `backend/src/main/kotlin/…/backend/persistence/ReviewQueueRepository.kt` — create.
- `backend/src/main/kotlin/…/backend/ingesta/publicacion/Publicacion.kt` — modify;
  campo `plazo: PlazoDto? = null`.
- `backend/src/test/kotlin/…/backend/infra/DatabaseConfigTest.kt` — create (gate, sin BD).
- `backend/src/test/kotlin/…/backend/persistence/PublicationPersistenceTest.kt` —
  create (gate: mapeo entidad↔dominio, sin BD).
- `backend/src/test/kotlin/…/backend/persistence/MigrationSqlTest.kt` — create
  (gate: contrato SQL de V2, sin BD).
- `backend/src/test/kotlin/…/backend/persistence/PublicationPersistenceLiveTest.kt`
  — create (opt-in `DB_LIVE_TEST=1`).
- `docs/desarrollo-local.md` — modify; sección de persistencia (esquema, pool,
  prueba opt-in de BD).

Harness: `ARCHITECTURE.md`, `CONSTRAINTS.md`, `docs/adr/0003-…` + índice,
`feature_list.json`, `PROGRESS.md` (ver *Durable Documentation Impact*).

**Sin cambios** en `Application.kt`, `:shared`, `:composeApp`, la raíz del build,
`settings.gradle.kts` ni `.github/workflows/ci.yml`.

## Visual Design Impact

- UI involved: no. Sin pantallas, tokens ni textos de UI.

## Durable Documentation Impact

- `ARCHITECTURE.md` (harness): update — `:backend` añade `persistence/`
  (repositorios JDBC + entidades) e `infra/` (config y pool Hikari); frontera
  **Backend → PostgreSQL** (JDBC/HikariCP, migraciones Flyway); esquema de las
  cuatro tablas y lo diferido (embedding/HNSW → FT00016).
- `CONSTRAINTS.md`: update — MUST durables: (1) acceso a datos con **JDBC +
  HikariCP**, sin ORM; (2) las pruebas que **tocan la BD real son opt-in**
  (`DB_LIVE_TEST=1`), fuera de `build`/`test`/`init.sh`/CI; (3) el *upsert* de
  publicación por `id` es idempotente. (La regla «el gate no depende de BD» ya existe.)
- `AGENTS.md` (harness): not needed — no cambia flujo ni arranque.
- **ADR `docs/adr/0003-…`** (recomendado): registrar la decisión durable «capa de
  datos con JDBC + HikariCP (sin ORM) y esquema relacional de
  publicacion/fragmento/resumen/cola_revision, con embedding diferido a FT00016».
  El planner **no** lo crea; lo escribe el implementador/orquestador e inscribe el
  índice en `docs/adr/README.md`.
- Otros: `docs/desarrollo-local.md` (producto) — update; `README.md`/`ROADMAP.md`
  — not needed.

## Implementation Plan

1. Añadir HikariCP al version catalog y a `implementation` de `:backend` (junto al
   driver PostgreSQL).
2. Escribir `V2__persistencia_publicaciones.sql` con las cuatro tablas, FKs e
   índices; verificar con `:backend:flywayMigrate`/`:backend:flywayInfo`.
3. Implementar `infra/DatabaseConfig.kt` y `infra/Database.kt` (config pura +
   pool Hikari).
4. Implementar el paquete `persistence/` (entidades + interfaces + impl JDBC),
   con `Publicacion` ganando el campo `plazo`.
5. Tests del gate sin BD (config, mapeo, contrato SQL) y test opt-in `DB_LIVE_TEST`
   (guardar/recuperar + tablas en `information_schema`); ejecutar y capturar.
6. Actualizar `ARCHITECTURE.md`, `CONSTRAINTS.md`, ADR 0003, `docs/desarrollo-local.md`,
   `PROGRESS.md` y `feature_list.json`; commit/push/PR/CI los gestiona el orquestador.

## Implementation Tasks

- [ ] `libs.versions.toml` + `backend/build.gradle.kts`: HikariCP y driver PostgreSQL
      en el classpath de producción.
- [ ] `V2__persistencia_publicaciones.sql`: `publicacion`, `fragmento`, `resumen`,
      `cola_revision` con PK/FK/índices; sin embedding ni HNSW.
- [ ] `DatabaseConfig` (derivación de `POSTGRES_*` + fail-fast) y `Database`
      (Hikari `DataSource`).
- [ ] `PublicationRepository` (+`PublicationEntity` + impl *upsert*).
- [ ] `FragmentRepository`, `SummaryRepository`, `ReviewQueueRepository` mínimos.
- [ ] `Publicacion` con `plazo: PlazoDto? = null`.
- [ ] Tests de gate sin BD: config, mapeo, contrato SQL de la migración.
- [ ] Test opt-in `DB_LIVE_TEST=1`: guardar/recuperar publicación con
      categoria/sección/epígrafe/plazo + tablas existentes.
- [ ] `ARCHITECTURE.md`, `CONSTRAINTS.md`, ADR 0003 + índice, `docs/desarrollo-local.md`,
      `PROGRESS.md`, `feature_list.json`.

## Verification Plan

Desde la raíz del producto (`..`, JDK 21 vía JBR/`JAVA_HOME`):

- **Gate sin BD (Docker parado):** `./gradlew :backend:test --rerun-tasks` →
  BUILD SUCCESSFUL con `DatabaseConfigTest`, `PublicationPersistenceTest` y
  `MigrationSqlTest` en verde (el test opt-in se omite sin `DB_LIVE_TEST`).
  `./gradlew build --no-daemon -PskipClient`, `./gradlew test`, `./gradlew detekt`
  (Detekt + `:cpdCheck`) y `.harness/init.sh` → exit 0.
- **Migración (BD arriba):** `cp .env.example .env && docker compose up -d`;
  `./gradlew :backend:flywayMigrate` → `BUILD SUCCESSFUL`; `:backend:flywayInfo` →
  `V1` + `V2` en `Success`; en psql, `\dt` / `information_schema.tables` muestra
  las cuatro tablas.
- **Guardar/recuperar (opt-in):**
  `DB_LIVE_TEST=1 ./gradlew :backend:test --tests '*PublicationPersistenceLiveTest'`
  → verde: publicación con `categoria`, `seccion`, `epigrafe` y `plazo` recuperada
  idéntica; *upsert* no duplica; nulos conservados; FK `ON DELETE CASCADE` activas.
- **CI:** se mantiene sin BD (no cambia el workflow).
- **E2E:** no aplica — sin flujo de usuario ni endpoint nuevo.
- `init.sh` (harness): **no** se modifica.

## Evidence To Capture

- Salida de `./gradlew :backend:test` con `DatabaseConfigTest`/`PublicationPersistenceTest`/
  `MigrationSqlTest` y el test opt-in (recuento, 0 fallos).
- `flywayInfo` con `V1`+`V2` en `Success` y salida de `information_schema.tables`
  (o `\dt`) con las cuatro tablas; prueba del *upsert* (una sola fila).
- Gate sin BD (Docker parado): `build -PskipClient`, `test`, `detekt`, `init.sh`.
- Ficheros del commit `FT00008`, PR y run de CI; entradas en `PROGRESS.md` y
  `feature_list.json` (`evidence`).

## Validator Checklist

- [ ] Alcance acotado: solo migración V2 + `infra/` (config/pool) + `persistence/`
      + el campo `plazo` de `Publicacion` + tests; sin clasificación (FT00012), sin
      embedding/HNSW (FT00016), sin chunking/generación, sin wiring en
      `Application.kt`, sin endpoints.
- [ ] Escenarios 1–6 pasan; la verificación real (guardar/recuperar y tablas) se
      ejecutó con BD real y está etiquetada como opt-in (límite documentado).
- [ ] La migración `V2` existe y aplica; `V1` **no** se editó; las cuatro tablas se
      crean con FK/índices coherentes con el spec.
- [ ] El acceso a datos es JDBC + HikariCP sin ORM; los repositorios no se cablean
      al arranque; el driver PostgreSQL está en el classpath de producción.
- [ ] `categoria`/`plazo` nullable y coherentes con FT00007 (parser deja null) y
      FT00012 (rellena después); `embedding` ausente.
- [ ] `return` único, sin `else if`, funciones ≤40 líneas y KDoc en todo lo nuevo.
- [ ] El gate sigue verde **sin BD** y sin red; `ARCHITECTURE.md`, `CONSTRAINTS.md`,
      ADR 0003, `docs/desarrollo-local.md`, `PROGRESS.md` y `feature_list.json`
      actualizados.
- [ ] No unrelated product behavior or extra feature work was added.

## Risks / Open Questions

- **El gate no ejecuta la verificación real (MUST de `CONSTRAINTS.md`).** La
  prueba de guardar/recuperar y la de tablas reales requieren PostgreSQL, así que
  son **opt-in** (`DB_LIVE_TEST=1`) contra el `docker-compose` del proyecto; el
  gate cubre config de conexión, mapeo y contrato SQL de la migración. Si el
  orquestador exigiera una prueba de BD en el gate, sería un cambio de reglas y
  necesitaría un servicio Postgres en CI (hoy prohibido). **Confirmar este límite.**
- **Alcance amplio (4 tablas).** Los repositorios de `fragmento`/`resumen`/
  `cola_revision` son mínimos y provisionales; si el implementador los ve crecer
  (o si se prefieren diferir a FT00014/FT00019/FT00023), dividir en
  `FT00008-PT1` (esquema + `publicacion`) y `FT00008-PT2` (resto).
- **`fragmento` sin embedding.** FT00016 añadirá `embedding vector(384)` + HNSW vía
  migración nueva; no anticiparlo aquí.
- **Modelo de `Publicacion` tocado por otra feature.** Añadir `plazo` es aditivo
  (default `null`); el parser y sus tests de FT00007 no cambian de comportamiento.
- **`text[]` vs `jsonb` para `cifras_clave`.** Se elige `text[]` (nativo y simple);
  si el contrato cambia, ajustar antes de producción.
- **Recursos:** pool Hikari pequeño (≤5) y métodos bloqueantes; el job
  (FT00009) los invocará en `Dispatchers.IO`.

## Implementation Notes (2026-10-10)

- **Helper JDBC compartido nuevo:** además de los ficheros previstos, se añadió
  `persistence/Jdbc.kt` (`executeUpdate`, `queryRows`, `mapAll`)
  para centralizar el manejo de conexiones/sentencias y evitar duplicación entre
  los cuatro repositorios (regla de reutilización y CPD). Sigue dentro del
  alcance de la capa de datos.
- **Representación en `text`:** `publicacion.seccion`/`categoria` guardan el
  **nombre** del enum (`II_A`, `BECAS_SUBVENCIONES_Y_AYUDAS`) y se reconstruyen con
  `valueOf` (fail-fast ante dato corrupto). `plazo` se reparte en
  `plazo_fecha_limite` + `plazo_descripcion`.
- **Entidad sin timestamps:** `PublicationEntity` modela solo las columnas que
  gestiona el repositorio; `creado_en`/`actualizado_en` los administra la base de
  datos (el test comprueba el avance de `actualizado_en` consultando la tabla).
- **Test opt-in autocontenido:** `PublicationPersistenceLiveTest` lee `POSTGRES_*`
  del entorno y, si faltan, de la `.env` de la raíz, de modo que
  `DB_LIVE_TEST=1 ./gradlew :backend:test --tests '*PublicationPersistenceLiveTest'`
  funciona tras `cp .env.example .env && docker compose up -d`.
- **Recuento del gate:** `:backend:test` pasa a 61 tests (18 nuevos: 8 + 4 + 5 + 1).
- **Renombrado a inglés (2026-10-10, petición del dueño):** los identificadores
  nuevos (clases, variables, funciones, params y ficheros) usan nombres en
  inglés, conservando los tipos de dominio existentes (`Publicacion`, `PlazoDto`,
  `SeccionBoeDto`, `CategoriaDto`). Equivalencias: `ConfiguracionBd`→`DatabaseConfig`,
  `BaseDatos`→`Database`, `PublicacionRepositorio`→`PublicationRepository`,
  `FragmentoRepositorio`→`FragmentRepository`, `ResumenRepositorio`→`SummaryRepository`,
  `ColaRevisionRepositorio`→`ReviewQueueRepository`, entidades
  `*Entity` con propiedades en inglés (`title`, `publicationDate`…), paquete
  `persistencia/`→`persistence/` y métodos `save`/`findById`/`listByDate`. Se
  eliminaron además las referencias al hardware («N100 / 8 GB», «carga baja»).
