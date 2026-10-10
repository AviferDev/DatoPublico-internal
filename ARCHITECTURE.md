# Architecture — DatoPublico

> Mapa durable de módulos y fronteras. **No** es un inventario de ficheros. El
> detalle por módulo vive en las skills `ktor-backend-architecture`,
> `compose-multiplatform-architecture` y `rag-datapublico`.

## Módulos (monorepo Gradle)

- **`:shared`** — DTOs y lógica compartida con `kotlinx.serialization`.
  Namespace `es.aviferdev.datopublico`.
- **`:backend`** — Ktor: ingesta del BOE, RAG, resúmenes, destacados y API.
  Namespace `es.aviferdev.datopublico.backend`. Ya existe el **esqueleto**
  (composition root `Application.kt`, `plugins/` e `infra/`, `GET /health`,
  configuración por entorno y logging JSON) y existe **`ingesta/`**:
  `ingesta/sumario/` (cliente del sumario diario del BOE + modelo interno y
  filtrado de secciones), `ingesta/publicacion/` (parser del **texto XML**
  oficial `xml.php`, cliente de texto, modelo `Publicacion` y combinador
  sumario + texto) e `ingesta/job/` (FT00009: config del horario `IngestaConfig`,
  cálculo puro del siguiente disparo `IngestaSchedule`, orquestador
  `IngestaJob`/`IngestaJobDiario` y scheduler por corrutina `IngestaScheduler`).
  Existe **`persistence/`** (FT00008): repositorios **JDBC**
  + entidades `...Entity` de `publicacion`, `fragmento`, `resumen` y
  `cola_revision`, más los helpers JDBC compartidos; la configuración de
  conexión (`infra/DatabaseConfig`, derivada de `POSTGRES_*`) y el pool
  (`infra/Database`, HikariCP ≤5) viven en `infra/`. El resto de paquetes
  llega con sus features. `Application.kt` **cablea la ingesta de forma
  condicional y no bloqueante**: solo si `INGESTA_ENABLED` está activo y la
  configuración de BD resuelve; un fallo al construirla se registra y el
  servidor sigue sirviendo `/health`; al parar se cancela el bucle y se cierran
  el pool y los clientes HTTP.
- **`:composeApp`** — cliente Compose Multiplatform (Android, iOS, Web).
  Namespace `es.aviferdev.datopublico`. Ya **existe y compila** para
  `androidTarget`, `iosArm64`/`iosSimulatorArm64` (framework `ComposeApp`) y
  `wasmJs` (browser, ejecutable), con la **UI compartida en `commonMain`**
  (`App()`) y un entrypoint por plataforma; además conserva `jvm()` **solo** para
  tests/dev. Aún **no** depende de `:shared` (llega con la primera UI que necesite
  DTOs, FT00032).

## Build y gate

- Raíz Gradle multi-proyecto (Kotlin DSL) con **version catalog** (`gradle/libs.versions.toml`).
- `:shared` y `:backend` son **SDK-free**; `:composeApp` aplica AGP (exige el Android SDK)
  y se incluye salvo con `-PskipClient`.
- **Gate de calidad bloqueante**: **Detekt** por módulo (`config/detekt/detekt.yml` +
  `config/detekt/<módulo>-baseline.xml`) y **CPD** global (`:cpdCheck`, PMD, umbral 100
  tokens); `check`/`build` y `.harness/init.sh` los ejecutan. Un hallazgo nuevo o un
  duplicado rompe el build.
- **Gate estándar** (`.harness/init.sh`, SDK-free): `./gradlew build -PskipClient` +
  `./gradlew detekt`. Con `--with-client`/`--with-ios`/`--with-all` se añade el cliente
  (Android/Web, iOS).
- **Migraciones** Flyway con tareas explícitas (`./gradlew :backend:flywayMigrate`), fuera
  de `check`; la CI no necesita base de datos.

## Fronteras

- **Cliente → API HTTP** (público, solo lectura). El cliente no conoce los
  internals del backend.
- **Backend → BOE** (API de datos abiertos + XML oficial, solo lectura, **sin
  clave ni credenciales**): `ingesta/` obtiene el sumario diario (JSON) y, por
  cada entrada, el **texto XML estructurado** (`xml.php`); el job programado
  (`ingesta/job/`, FT00009) **ejecuta esa descarga en runtime** a las 09:30 y en
  una segunda pasada (18:00 por defecto, `Europe/Madrid`, configurable) y
  persiste el resultado. Los clientes HTTP fijan `HttpTimeout` explícito. Es una
  dependencia **externa en tiempo de ejecución**, no del gate: los tests del gate
  no hacen red y las pruebas contra el BOE son opt-in. La **fuente de verdad** del
  texto y los metadatos es el XML estructurado, no el HTML (`txt.php`) ni el PDF
  (ver `docs/adr/0002`).
- **Backend → PostgreSQL** (JDBC + **HikariCP**, **sin ORM**; migraciones
  **Flyway**; ver `docs/adr/0003`): los repositorios de `persistence/` escriben
  y leen `publicacion` (con `categoria` y `plazo` nullable), `fragmento`,
  `resumen` y `cola_revision`. La conexión se **deriva** de `POSTGRES_*` (fuente
  única, la misma que Compose/Flyway) y falla en claro si falta la contraseña. El
  *upsert* de publicación por `id` es idempotente y es la base del job diario: la
  segunda pasada reejecuta la misma fecha sin duplicar. `Application.kt` crea el
  pool **solo** si la ingesta está habilitada y la config de BD resuelve, y lo
  cierra en `ApplicationStopped`. Lo diferido no se anticipa: la columna
  `embedding vector(384)` y su índice HNSW llegan con FT00016, y los valores de
  categoría/plazo con FT00012.
- **Backend:** `plugins/` (HTTP) → servicios → dominio puro → repositorios y
  clientes → `infra/`.
- **IA:** embeddings **locales** (ONNX) y generación/chat **remoto** (OpenCode),
  cada uno tras una interfaz intercambiable.
- **Datos:** PostgreSQL + pgvector; migraciones Flyway (`V1` esquema base, `V2`
  persistencia). Sin cuentas ni datos personales.

## Reglas transversales

- El dominio es puro (sin Ktor, JDBC, ONNX ni HTTP).
- **Trazabilidad** obligatoria: todo resumen apunta a la fuente oficial.
- Secretos y claves **solo** por entorno, en el servidor.
- El texto de UI vive en recursos y en castellano.

## Convenciones de nombres

- **Todo tipo `@Serializable`/de transporte** lleva sufijo **`Dto`**: el contrato
  de **`:shared`** (las `data class` `PublicacionDto`, `ResumenDto`, `PlazoDto`,
  `ResumenDiarioDto` y los **enums de wire** `CategoriaDto`, `SeccionBoeDto`) y
  también los DTOs de transporte de **`:backend`** (`HealthDto`,
  `BoeSumarioResponseDto`, `BoeSeccionDto`…). Aplica a **cualquier** tipo
  `@Serializable`, no solo a los contenedores.
- La **configuración de serialización** (`DatoPublicoJson`) **no** es un tipo de
  contrato y va **sin** `Dto`.
- **Todo tipo `@Serializable`**: cada propiedad lleva `@SerialName` explícito,
  aunque el nombre coincida con la clave de wire (sin depender del nombre por
  defecto); los valores de los enums de wire también lo llevan.
- En las capas internas: entidades de persistencia `...Entity`, filas `...Row`,
  modelos de UI `...Ui`. Un **modelo de dominio/valor interno** que no sea
  serializable ni `Entity`/`Row`/`Ui` va **sin sufijo** (p. ej. `EntradaSumario`).
- **Sin prefijos** (nada de notación húngara).
